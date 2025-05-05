## Slack message events pipeline code
### App Engine
Make sure you have the gcloud CLI installed, if not download it from [here](https://cloud.google.com/sdk/docs/install)
Deploy by running:
```sh
cd app_negine
gcloud app deploy
```

### BigQuery
Deploy in the BigQuery GCP console

### Blog post for more details
[Create a Slack messages pipeline in GCP](https://www.khalidibrahim.io/blog/create-a-slack-messages-pipeline-in-gcp/)

## Data Structure
Testing the data from Slack events with different types of events, we can see some things to note:

1. Messages are sent as events of type "message". The `text` parameter will contain the text contents of the message, formatted depending on the original message formatting.
2. Messages with rich text (attachments, links, etc) will have a blocks array that divides the rich text into chunks that are easier to identify and extract. For example, a link like this: "test link" will be shown with an additional block parameter that is an array, looking like:

```json
"blocks": [
      {
        "type": "rich_text",
        "block_id": "edjp8",
        "elements": [
          {
            "type": "rich_text_section",
            "elements": [
              {
                "type": "text",
                "text": "Test "
              },
              {
                "type": "link",
                "url": "https://www.google.com",
                "text": "link"
              }
            ]
          }
        ]
      }
    ],
```

3. Whenever we send a message with rich text that has a preview (like a link to another message with an attachment), there is a second event that takes place of type "message" and subtype "message\_changed" where Slack automatically changes a message to add in the preview of the link/attachments. There is also a `previous_message` parameter containing the main data of the previous message that has been updated
4. When we send attachments, they are added to the `files` field under event. **Messages that get modified with rich text attachments** (auto added link preview images, etc by slack) will have their attachments in the `attachments` field under the event.message sub-parameter (available only if subtype is `message_changed` ). But for **attachments added by the user directly,** it will be under the `files` field under `events` directly
5. There isn't information on the [Slack docs](https://slack.com/intl/en-gb/help/articles/202395258-Edit-or-delete-messages#desktop-1) about the duration for which the `edit` and `delete` and `unsend` options can be available. From manual testing, I could edit messages within 24 hours after sending. Messages older than 24 hours were not editable. For delete, I could go back a **month** and the delete option is still available. This is what a deleted message event looks like:

```json
{
  "token": "<TOKEN>",
  "team_id": "T0xxxxxx",
  "context_team_id": "T0D33F66E",
  "context_enterprise_id": null,
  "api_app_id": "Axxxxxxx",
  "event": {
    "type": "message",
    "subtype": "message_deleted",
    "previous_message": {
      "user": "Uxxxxxxx",
      "type": "message",
      "ts": "1744105502.233609",
      "client_msg_id": "633f379a-81fc-49e0-8cc6-e7d0be69e2f0",
      "text": "deleting",
      "team": "T0xxxxxx",
      "thread_ts": "1744090096.484059",
      "parent_user_id": "Uxxxxxxx",
      "blocks": [
        {
          "type": "rich_text",
          "block_id": "y2TE6",
          "elements": [
            {
              "type": "rich_text_section",
              "elements": [
                {
                  "type": "text",
                  "text": "deleting"
                }
              ]
            }
          ]
        }
      ]
    },
    "channel": "C0xxxxxxxxx",
    "hidden": true,
    "deleted_ts": "1744105502.233609",
    "event_ts": "1744105506.001100",
    "ts": "1744105506.001100",
    "channel_type": "channel"
  },
  "type": "event_callback",
  "event_id": "Ev0xxxxxxxxx",
  "event_time": 1744105506,
  "authorizations": [
    {
      "enterprise_id": null,
      "team_id": "T0xxxxxx",
      "user_id": "Uxxxxxxx",
      "is_bot": false,
      "is_enterprise_install": false
    }
  ],
  "is_ext_shared_channel": false,
  "event_context": "4-eyJldCI6Im1lc3NhZ2UiLCJ0aWQiOiJUMEQyNzdFRTUiLCJhaWQiOiJBMDhNREpSOFE3SiIsImNpZCI6IkMwNkM2NkdNQkNQIn0"
}
```

We can use the data `event.channel` `event.previous_message.user` and `event.previous_message.event_ts` to get the previous message and delete it. In case of edits, the new message will be inserted as normal with the edit's `event_ts` . In case of delete, nothing will be inserted. Only old data will be deleted.

If we need to, we can track edits and deletes in the original staging table

6. To identify messages uniquely (either for delete or update), we cannot rely in `message_id` because it is kind of a surrogate key in the staging table. We need a composite key of the following: \[`channel` , `user_id` , `bot_id` , `event_ts_epoch` \]. Check tests below to confirm no duplicates for these values
