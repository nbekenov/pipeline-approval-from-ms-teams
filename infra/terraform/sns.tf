# 
# SNS topic
# SNS subscription to Lambda endpoint
# SNS topic policy
#
#################################################

resource "aws_sns_topic" "teams_sns" {
  name              = "${var.name}-teams"
  kms_master_key_id = var.kms_key_id
}

resource "aws_sns_topic_subscription" "sns_teams_subscription" {
  topic_arn = aws_sns_topic.teams_sns.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.sns_teams_lambda.arn
}

resource "aws_sns_topic_policy" "teams_sns" {
  arn    = aws_sns_topic.teams_sns.arn
  policy = data.aws_iam_policy_document.teams_sns_policy.json
}

data "aws_iam_policy_document" "teams_sns_policy" {
  policy_id = "__default_policy_ID"

  statement {
    sid    = "Allow_Publish_Events"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "codepipeline.amazonaws.com"]
    }
    actions = [
      "SNS:Publish",
    ]
    resources = [
      aws_sns_topic.teams_sns.arn,
    ]
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceOwner"
      values = [
        data.aws_caller_identity.current.account_id,
      ]
    }
  }

  statement {
    sid    = "Allow_Subscribe_Receive"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = [
      "SNS:Subscribe",
      "SNS:Receive",
      "SNS:ListSubscriptionsByTopic",
      "SNS:GetTopicAttributes",
      "SNS:Publish",
      "SNS:SetTopicAttributes",
    ]
    resources = [
      aws_sns_topic.teams_sns.arn,
    ]
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceOwner"
      values = [
        data.aws_caller_identity.current.account_id,
      ]
    }
  }

}