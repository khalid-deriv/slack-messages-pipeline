CREATE SCHEMA IF NOT EXISTS staging
OPTIONS (
  Description ="Initial raw data dataset"
);

CREATE SCHEMA IF NOT EXISTS development
OPTIONS (
  Description ="Development and testing dataset"
);

CREATE TABLE IF NOT EXISTS staging.pubsub_slack_event
(
    subscription_name STRING
  , message_id STRING
  , publish_time TIMESTAMP
  , attributes STRING
  , data STRING
)
PARTITION BY TIMESTAMP_TRUNC(publish_time, MONTH)
OPTIONS(
    description="Staging table to store the data from pubsub slack event"
  , require_partition_filter=TRUE
);

CREATE TABLE IF NOT EXISTS development.slack_message
(
    message_id STRING OPTIONS (description="PubSub message ID")
  , insert_timestamp TIMESTAMP OPTIONS (description="PubSub message insert timestamp")
  , team_id STRING
  , channel STRING
  , user_id STRING
  , username STRING
  , bot_id STRING OPTIONS (description="Slack bot ID in case the message is sent by a bot")
  , `type` STRING
  , subtype STRING
  , thread_ts STRING
  , `text` STRING
  , attachments ARRAY<STRING> OPTIONS (description="Slack message attachments")
  , auto_attachments ARRAY<STRING> OPTIONS (description="Attachments automatically added by Slack message preview")
  , event_ts TIMESTAMP OPTIONS (description="Slack event timestamp")
  , event_ts_epoch STRING OPTIONS (description="Slack event timestamp in epoch string format to be used as a unique key in combination with channel, user and bot_id")
)
PARTITION BY TIMESTAMP_TRUNC(insert_timestamp, MONTH)
CLUSTER BY message_id
OPTIONS(
    description="Slack public messages recorded from PubSub using Slack Events API"
  , require_partition_filter=TRUE
);