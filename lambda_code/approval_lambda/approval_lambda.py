"""
AWS Lambda function to handle MS Teams reponses to CodePipeline approval requests
"""
import os
import json
from datetime import datetime
import logging
import boto3
from botocore.exceptions import ClientError

# Set up logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

region = os.getenv('REGION', 'us-west-2')
account = os.environ['ACCOUNT_ID']

def handler(event, context):
    """
    Lambda Function that handles the responses from MS Teams.

    Args:
        event(dict): The event object from MS Teams action
        context(object): The Lambda context object.
    
    Returns:
        dict: response date to be sent back to MS Teams
    """
    logger.debug('Received event: %s', json.dumps(event))
    body = json.loads(event['body'])

    approval_action = body['action']
    codepipeline_status = "Approved" if approval_action == "approve" else "Rejected"
    codepipeline_name = body["codepipelineName"]
    stage_name = body['stageName']
    approval_review_link = body['link']
    msg_color = "#069638" if approval_action == "approve" else "#ff0000"
    timestamp = datetime.utcnow().strftime("%m/%d/%Y %H:%M:%S")

    logger.info(f'pipeline stage {stage_name} was: {codepipeline_status}')
    client = boto3.client('codepipeline')
    try:
        response_approval = client.put_approval_result(
            pipelineName=codepipeline_name,
            stageName=stage_name,
            actionName=body['actionName'],
            result={'summary':'','status':codepipeline_status},
            token=body["token"]
        )
        logger.info(f'approval reponse: {response_approval}')
    except ClientError as error:
        logger.error("get_item failed", exc_info=True)
        return error.response['Error']['Code']

    logger.info(f'Updating message card in MS Teams')
    teams_msg = {
        "@type": "MessageCard",
        "@context": "http://schema.org/extensions",
        "summary": "Pipeline Approval Request",
        "themeColor": msg_color,
        "title": "Pipeline Approval Request",
        "text": f"Pipeline name: **{codepipeline_name}**",
        "sections": [
            {
                "facts": [
                    { "name": "Status:", "value": codepipeline_status },
                    { "name": "Stage Name:", "value": stage_name },
                    { "name": "Account:", "value": account },
                    { "name": "Region:", "value": region },
                    { "name": "Event Time[UTC]:", "value": timestamp },
                ]
            },
            {
                "potentialAction": [{
                    "@type": "OpenUri",
                    "name": "Open Approval Review",
                    "targets": [{"os": "default", "uri": approval_review_link}]
                }]
            }
        ]
    }

    return {
        "isBase64Encoded": "false",
        "statusCode": 200,
        "body": json.dumps(teams_msg),
        "headers": {
            "Content-Type": "application/json",
            "CARD-ACTION-STATUS": codepipeline_status,
            "CARD-UPDATE-IN-BODY": "true"
        }
    }
