# 
# api_gateway resources
#
#            --------------------------
#            |            resource     |
#            |---------||--------------|
# Request--->|   method||   integration|------> Lambda
#            |         ||              |            
#            ---------------------------   
#
#################################################


resource "aws_api_gateway_rest_api" "approval_api" {
  name        = "${var.name}-ms-teams-approval_api"
  description = "MS Teams approval api"
  policy      = data.aws_iam_policy_document.webhook_api_gateway_policy.json

  # creates a new API Gateway first and then will delete the old one automatically
  # to avoid a possible outage when the API Gateway needs to be recreated during an update
  lifecycle {
    create_before_destroy = true
  }
}

# resource path for the API endpoint
resource "aws_api_gateway_resource" "approval_resource" {
  rest_api_id = aws_api_gateway_rest_api.approval_api.id
  parent_id   = aws_api_gateway_rest_api.approval_api.root_resource_id
  path_part   = "approval"
}

# specification of the endpoint we are listening
resource "aws_api_gateway_method" "method" {
  #checkov:skip=CKV_AWS_59: "Ensure there is no open access to back-end resources through API"
  # only people with admin access to MS teams notification channel would be able to trigger api
  rest_api_id   = aws_api_gateway_rest_api.approval_api.id
  resource_id   = aws_api_gateway_resource.approval_resource.id
  http_method   = "POST" # the method to use when calling the API Gateway endpoint CKV_AWS_59
  authorization = "NONE"
}

# define integration with Lambda that will process the approval result
resource "aws_api_gateway_integration" "integration" {
  rest_api_id = aws_api_gateway_rest_api.approval_api.id
  resource_id = aws_api_gateway_resource.approval_resource.id
  http_method = aws_api_gateway_method.method.http_method

  integration_http_method = "POST" # the method used by API Gateway to call the backend
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.approval_lambda.invoke_arn
}

resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.approval_api.id

  triggers = {
    # NOTE: The configuration below will satisfy ordering considerations,
    #       but not pick up all future REST API changes. More advanced patterns
    #       are possible, such as using the filesha1() function against the
    #       Terraform configuration file(s) or removing the .id references to
    #       calculate a hash against whole resources. Be aware that using whole
    #       resources will show a difference after the initial implementation.
    #       It will stabilize to only change when resources change afterwards.
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.approval_resource.id,
      aws_api_gateway_method.method.id,
      aws_api_gateway_integration.integration.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "stage" {
  #checkov:skip=CKV_AWS_120: "Ensure API Gateway caching is enabled"
  #checkov:skip=CKV_AWS_73: "Ensure API Gateway has X-Ray Tracing enabled"
  depends_on = [aws_cloudwatch_log_group.execution_logs]

  deployment_id = aws_api_gateway_deployment.deployment.id
  rest_api_id   = aws_api_gateway_rest_api.approval_api.id
  stage_name    = "prod"

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.access_logs.arn
    format          = "$context.identity.sourceIp $context.identity.caller $context.identity.user [$context.requestTime] $context.httpMethod $context.resourcePath $context.protocol $context.status $context.responseLength $context.requestId"
  }
}

# data "aws_ssm_parameter" "wafv2_default_acl" {
#   name = "/nextgen/wafv2/regional/nextgen-base"
# }

# resource "aws_wafv2_web_acl_association" "edge" {
#   resource_arn = aws_api_gateway_stage.stage.arn
#   web_acl_arn   = data.aws_ssm_parameter.wafv2_default_acl.value
# }

resource "aws_api_gateway_method_settings" "webhook" {
  #checkov:skip=CKV_AWS_225: "Ensure API Gateway method setting caching is enabled"
  rest_api_id = aws_api_gateway_rest_api.approval_api.id
  stage_name  = aws_api_gateway_stage.stage.stage_name

  method_path = "*/*"

  settings {
    metrics_enabled = true
    logging_level   = var.api_execution_log_level
  }
}


resource "aws_cloudwatch_log_group" "access_logs" {
  name              = "/aws/apigw/${var.name}"
  retention_in_days = var.api_access_log_retention
  kms_key_id        = var.logs_kms_key_id

  tags = var.additional_tags
}

resource "aws_cloudwatch_log_group" "execution_logs" {
  name              = "API-Gateway-Execution-Logs_${aws_api_gateway_rest_api.approval_api.id}/prod"
  retention_in_days = var.api_execution_log_retention
  kms_key_id        = var.logs_kms_key_id

  tags = var.additional_tags
}

data "aws_iam_policy_document" "webhook_api_gateway_policy" {
  statement {
    sid     = "AllowAllByDefault"
    effect  = "Allow"
    actions = ["execute-api:Invoke"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    resources = [
      "arn:aws:execute-api:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*/*/*/*"
    ]
  }

  statement {
    sid     = "BlockUnlessFromMSTeams"
    effect  = "Deny"
    actions = ["execute-api:Invoke"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    resources = [
      "arn:aws:execute-api:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*/*/*/*"
    ]
    condition {
      test     = "NotIpAddress"
      variable = "aws:SourceIp"
      values   = var.ms_teams_server_ips
    }
  }
}