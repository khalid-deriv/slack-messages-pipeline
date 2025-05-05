import json
import logging
import os

from fastapi import FastAPI, Request, BackgroundTasks
from fastapi.responses import JSONResponse
from google.cloud import pubsub_v1

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize FastAPI app
app = FastAPI()

# Configure Pub/Sub
pubsub_topic = os.getenv('PUBSUB_TOPIC')
google_cloud_project = os.getenv('GOOGLE_CLOUD_PROJECT')

print(f'PubSub Topic: {pubsub_topic}, Google Cloud Project: {google_cloud_project}')

def push_pubsub(project: str, topic: str, data: dict) -> None:
    try:
        publisher = pubsub_v1.PublisherClient()
        path = publisher.topic_path(project, topic)
        json_string = json.dumps(data, default=str)
        publish_future=publisher.publish(path, data=json_string.encode())
        message_id = publish_future.result()
    except Exception as e:
        logger.error(f"Failed to publish message of ID {message_id}: {e}", exc_info=True)

@app.post("/messages")
async def slack_events(request: Request, background_tasks: BackgroundTasks):
    """Handle Slack events and publish them to Pub/Sub in the background."""
    data = await request.json()
    # logger.info(f"Received Slack event") ## Optional - just for debugging
    
    # Check if this is a URL verification request
    if data.get("type") == "url_verification":
        return JSONResponse(content={"challenge": data.get("challenge")})
    
    # Add the task to the background queue
    background_tasks.add_task(
        push_pubsub,
        google_cloud_project,
        pubsub_topic,
        dict(data),
    )

    # Return immediately while the background task processes
    return JSONResponse(content={"status": "processing"})

# For local development
if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=8080)
