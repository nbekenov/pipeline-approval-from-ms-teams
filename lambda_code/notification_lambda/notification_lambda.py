"""
AWS Lambda function to send CodePipeline approval requests to MS Teams.
"""
import os
import json
from datetime import datetime
import logging
import requests

# Set up logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

webhook = os.environ['WEBHOOK_PATH']
api_endpoint_url = os.environ['API_GATEWAY_URL']
region = os.getenv('REGION', 'us-east-1')
account = os.environ['ACCOUNT_ID']

def handler(event, context):
    """
    Handler Function that processes the SNS event and send notification to MS Teams.

    Args:
        event(dict): The SNS event object.
        context(object): The Lambda context object.
    
    Returns:
        None
    """
    logger.debug('Received event: %s', json.dumps(event))
    # extract the message from the SNS event
    message = event["Records"][0]["Sns"]["Message"]
    data = json.loads(message)

    # extract custom data from the manual approval action
    token = data["approval"]["token"]
    codepipeline_name = data["approval"]["pipelineName"]
    action_name = data["approval"]["actionName"]
    stage_name = data["approval"]["stageName"]
    approval_review_link = data["approval"]["approvalReviewLink"]
    timestamp = datetime.utcnow().strftime("%m/%d/%Y %H:%M:%S")

    # Create the message payload
    body_approve = {
        "token": token,
        "account": account,
        "region": region,
        "codepipelineName": codepipeline_name,
        "stageName": stage_name,
        "actionName": action_name,
        "message": "message",
        "creationTime": timestamp,
        "link": approval_review_link,
        "action": "approve"
    }
    body_reject = {
        "token": token,
        "account": account,
        "region": region,
        "codepipelineName": codepipeline_name,
        "stageName": stage_name,
        "actionName": action_name,
        "message": "message",
        "creationTime": timestamp,
        "link": approval_review_link,
        "action": "reject"
    }
    message = {
        "@type": "MessageCard",
        "@context": "http://schema.org/extensions",
        "summary": "Pipeline Approval Request",
        "themeColor": "#2196F3",
        "title": "Pipeline Approval Request",
        "text": f"Pipeline name: **{codepipeline_name}**",
        "sections": [
            {
                "facts": [
                    { "name": "Status:", "value": "requested" },
                    { "name": "Stage Name:", "value": stage_name },
                    { "name": "Account:", "value": account },
                    { "name": "Region:", "value": region },
                    { "name": "Event Time[UTC]:", "value": timestamp },
                ]
            },
            {
                "potentialAction": [{
                    "@type": "HttpPOST",
                    "name": "Approve",
                    "target": api_endpoint_url,
                    "body": json.dumps(body_approve)
                }, {
                    "@type": "HttpPOST",
                    "name": "Reject",
                    "target": api_endpoint_url,
                    "body": json.dumps(body_reject)
                }, {
                    "@type": "OpenUri",
                    "name": "Open Approval Review",
                    "targets": [{"os": "default", "uri": approval_review_link}]
                }]
            }
        ]
    }

    send_to_teams(message)

def send_to_teams(data):
    """
    Send the message to the MS Teams channel

    Args:
        data(dict): Message card to be sent in MS Teams
    
    Returns:
        None
    """
    logger.debug('JSON data being sent to Teams: %s', json.dumps(data))
    logger.info("Sending the message to the MS Teams channel")
    try:
        response = requests.post(
            webhook,
            data = json.dumps(data),
            headers = {'Content-Type': 'application/json'},
            timeout = 60
        )
        logger.info("Response status code: %s" % response.status_code)
        if response.status_code != 200:
            raise Exception("Teams webhook returned `%s` Response: `%s`" % (response.status_code, response.text))
    except requests.exceptions.RequestException as error:
        logger.error("post request failed", exc_info=True)
        raise error from error
    except Exception as error:
        logger.error("Sending the message failed", exc_info=True)
        raise error from error
