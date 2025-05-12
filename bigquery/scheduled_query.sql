-- scheduled queries to insert Slack Events data from staging pubsub into destination
DECLARE start_ts TIMESTAMP;
DECLARE end_ts   TIMESTAMP;

BEGIN TRANSACTION;

SET (start_ts, end_ts) = (
  SELECT AS STRUCT
         TIMESTAMP_SUB(TIMESTAMP(@run_time), INTERVAL 2 HOUR) AS start_ts
       , TIMESTAMP(@run_time) AS end_ts
);


CREATE TEMP TABLE latest AS (
  SELECT message_id
       , publish_time AS insert_timestamp
       , JSON_VALUE(data, '$.team_id') AS team_id
       , JSON_VALUE(data, '$.event.channel') AS channel
       , COALESCE(JSON_VALUE(data, '$.event.user')
                , JSON_VALUE(data, '$.event.message.user')
                , JSON_VALUE(data, '$.event.previous_message.user')
         ) AS user_id
       , COALESCE(JSON_VALUE(data, '$.event.username')
                , JSON_VALUE(data, '$.event.message.username')
                , JSON_VALUE(data, '$.event.previous_message.username')
         ) AS username
       , COALESCE(JSON_VALUE(data, '$.event.bot_id')
                , JSON_VALUE(data, '$.event.message.bot_id')
                , JSON_VALUE(data, '$.event.previous_message.bot_id')
         ) AS bot_id
       , JSON_VALUE(data, '$.event.type') AS type
       , JSON_VALUE(data, '$.event.subtype') AS subtype
       , COALESCE(JSON_VALUE(data, '$.event.thread_ts')
                , JSON_VALUE(data, '$.event.message.thread_ts')
                , JSON_VALUE(data, '$.event.previous_message.thread_ts')
                , JSON_VALUE(data, '$.event.event_ts')
                , JSON_VALUE(data, '$.event.message.event_ts')
         ) AS thread_ts
       , COALESCE(JSON_VALUE(data, '$.event.text')
                , JSON_VALUE(data, '$.event.message.text')
                , JSON_VALUE(data, '$.event.previous_message.text')
         ) AS text
       , COALESCE(JSON_EXTRACT_ARRAY(data, '$.event.files'), JSON_EXTRACT_ARRAY(data, '$.event.message.files')) AS attachments
       , COALESCE(JSON_EXTRACT_ARRAY(data, '$.event.attachments'), JSON_EXTRACT_ARRAY(data, '$.event.message.attachments')) AS auto_attachments
       , TIMESTAMP_MILLIS(CAST(ROUND(CAST(JSON_VALUE(data, '$.event.event_ts') AS FLOAT64) * 1000) AS INT64)) AS event_ts
       , JSON_VALUE(data, '$.event.event_ts') AS event_ts_epoch
    FROM staging.pubsub_slack_event
   WHERE publish_time >= start_ts
     AND publish_time < end_ts
 QUALIFY ROW_NUMBER() OVER (PARTITION BY data ORDER BY publish_time DESC) = 1 -- Filter to keep only the latest row for each unique `data`
)

CREATE TEMP TABLE deletes AS (
  SELECT channel
       , COALESCE(JSON_VALUE(data, '$.event.previous_message.user'), '') AS user_id
       , COALESCE(JSON_VALUE(data, '$.event.previous_message.bot_id'), '') AS bot_id
       , JSON_VALUE(data, '$.event.previous_message.event_ts') AS event_ts_epoch
    FROM latest
   WHERE subtype IN ('message_deleted', 'message_changed')
);

DELETE FROM development.slack_message AS m
 WHERE m.insert_timestamp < end_ts
   AND (
    EXISTS ( -- check if the message is deleted
      SELECT 1
        FROM deletes AS d
       WHERE m.channel = d.channel
         AND COALESCE(m.user_id, '') = d.user_id
         AND COALESCE(m.bot_id, '') = d.bot_id
         AND m.event_ts_epoch = d.event_ts_epoch
    )
    OR (  -- delete all messages in the time range
          m.insert_timestamp >= start_ts
      AND m.insert_timestamp < end_ts
    )
  );

INSERT INTO development.slack_message
SELECT l.message_id
     , l.insert_timestamp
     , l.team_id
     , l.channel
     , l.user_id
     , l.username
     , l.bot_id
     , l.`type`
     , l.subtype
     , l.thread_ts
     , l.`text`
     , l.attachments
     , l.auto_attachments
     , l.event_ts
     , l.event_ts_epoch
  FROM latest AS l
  LEFT JOIN development.slack_message AS t
    ON l.message_id = t.message_id
   AND t.insert_timestamp >= start_ts 
   AND t.insert_timestamp < end_ts
  LEFT JOIN deletes AS d
    ON l.channel = d.channel
   AND l.user_id = d.user_id
   AND l.bot_id = d.bot_id
   AND l.event_ts_epoch = d.event_ts_epoch
 WHERE t.message_id IS NULL
   AND d.channel IS NULL
   AND l.subtype NOT IN ('message_deleted');

COMMIT TRANSACTION;
