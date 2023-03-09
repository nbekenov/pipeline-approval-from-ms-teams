# 
# Lambda function to handle requests from MS teams to CodePipeline
#################################################

data "archive_file" "approval_lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambda_code/approval_lambda"
  output_path = "${path.module}/.terraform/archive_files/approval_lambda.zip"
}

resource "aws_lambda_function" "approval_lambda" {
  #checkov:skip=CKV_AWS_50: "X-ray tracing is enabled for Lambda" - N/A
  #checkov:skip=CKV_AWS_116: "Ensure that AWS Lambda function is configured for a Dead Letter Queue(DLQ)" - N/A
  #checkov:skip=CKV_AWS_117: "Ensure that AWS Lambda function is configured inside a VPC" - not accessing any data from AWS
  description                    = "teams approval trigger for ${var.name}"
  filename                       = "${path.module}/.terraform/archive_files/approval_lambda.zip"
  function_name                  = "${var.name}-approval-lambda"
  role                           = aws_iam_role.iam_for_approval_lambda.arn
  handler                        = "approval_lambda.handler"
  source_code_hash               = data.archive_file.approval_lambda_zip.output_base64sha256
  runtime                        = "python3.9"
  timeout                        = var.teams_timeout
  reserved_concurrent_executions = 100
  kms_key_arn                    = var.kms_key_id

  environment {
    variables = {
      ACCOUNT_ID = data.aws_caller_identity.current.account_id
    }
  }

  tags = var.additional_tags
}

resource "aws_lambda_permission" "api_invoke_lambda" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.approval_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.approval_api.execution_arn}/*/${aws_api_gateway_method.method.http_method}${aws_api_gateway_resource.approval_resource.path}"
}


resource "aws_iam_role" "iam_for_approval_lambda" {
  name               = "${var.name}-approval-lambda"
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

resource "aws_iam_role_policy" "approval_lambda_role_policy" {
  name   = "${var.name}-approval-lambda-policy"
  role   = aws_iam_role.iam_for_approval_lambda.id
  policy = data.aws_iam_policy_document.approval_lambda_policy_document.json
}

data "aws_iam_policy_document" "approval_lambda_policy_document" {
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
  statement {
    actions = [
      "codepipeline:GetPipeline",
      "codepipeline:GetPipelineState",
      "codepipeline:GetPipelineExecution",
      "codepipeline:ListPipelineExecutions",
      "codepipeline:ListPipelines",
      "codepipeline:PutApprovalResult"
    ]

    resources = [
      "*",
    ]
  }
}