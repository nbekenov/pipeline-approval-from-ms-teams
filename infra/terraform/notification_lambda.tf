# 
# Lambda function to send approval requests to MS Teams
#################################################

data "archive_file" "sns_teams_lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambda_code/notification_lambda"
  output_path = "${path.module}/.terraform/archive_files/notification_lambda.zip"
}

resource "aws_lambda_function" "sns_teams_lambda" {
  #checkov:skip=CKV_AWS_50: "X-ray tracing is enabled for Lambda"
  #checkov:skip=CKV_AWS_116: "Ensure that AWS Lambda function is configured for a Dead Letter Queue(DLQ)"
  #checkov:skip=CKV_AWS_117: "Ensure that AWS Lambda function is configured inside a VPC"
  description                    = "teams notification trigger for ${var.name}"
  filename                       = "${path.module}/.terraform/archive_files/notification_lambda.zip"
  function_name                  = "${var.name}-ms-teams-notification-lambda"
  role                           = aws_iam_role.iam_for_sns_teams.arn
  handler                        = "notification_lambda.handler"
  source_code_hash               = data.archive_file.sns_teams_lambda_zip.output_base64sha256
  runtime                        = "python3.9"
  timeout                        = var.teams_timeout
  reserved_concurrent_executions = 100
  kms_key_arn                    = var.kms_key_id

  environment {
    variables = {
      WEBHOOK_PATH = var.teams_webhook
      ACCOUNT_ID   = data.aws_caller_identity.current.account_id
    }
  }

  tags = var.additional_tags
}

resource "aws_lambda_permission" "sns_invoke_lambda" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sns_teams_lambda.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.teams_sns.arn
}

resource "aws_iam_role" "iam_for_sns_teams" {
  name               = "${var.name}-teams-lambda"
  tags               = var.additional_tags
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

}
resource "aws_iam_role_policy" "sns_teams_role_policy" {
  name   = "${var.name}-teams-lambda-policy"
  role   = aws_iam_role.iam_for_sns_teams.id
  policy = data.aws_iam_policy_document.sns_teams_policy_document.json
}

data "aws_iam_policy_document" "sns_teams_policy_document" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]

    resources = [
      "arn:aws:logs:*:*:*",
    ]
  }
}

