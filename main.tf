provider "aws" {
  region = "us-east-1"
}

# Random ID to make unique S3 bucket
resource "random_id" "id" {
  byte_length = 4
}

# S3 Bucket for future logs
resource "aws_s3_bucket" "pulsewatch_logs" {
  bucket        = "pulsewatch-logs-${random_id.id.hex}"
  force_destroy = true
}

# IAM Role for Lambda Execution
resource "aws_iam_role" "lambda_exec_role" {
  name = "pulsewatch_lambda_exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# Attach AWSLambdaBasicExecutionRole to Lambda
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda Function
resource "aws_lambda_function" "pulsewatch_hello" {
  function_name    = "pulsewatch_hello"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "index.handler"
  runtime          = "nodejs18.x"
  filename         = "lambda.zip"
  source_code_hash = filebase64sha256("lambda.zip")
}

# API Gateway REST API
resource "aws_api_gateway_rest_api" "pulsewatch_api" {
  name        = "pulsewatch-api"
  description = "API Gateway for PulseWatch Lambda"
}

# API Resource: /pulse
resource "aws_api_gateway_resource" "pulse_resource" {
  rest_api_id = aws_api_gateway_rest_api.pulsewatch_api.id
  parent_id   = aws_api_gateway_rest_api.pulsewatch_api.root_resource_id
  path_part   = "pulse"
}

# Method: GET /pulse
resource "aws_api_gateway_method" "get_pulse" {
  rest_api_id   = aws_api_gateway_rest_api.pulsewatch_api.id
  resource_id   = aws_api_gateway_resource.pulse_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

# Integration: Link GET /pulse to Lambda
resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.pulsewatch_api.id
  resource_id             = aws_api_gateway_resource.pulse_resource.id
  http_method             = aws_api_gateway_method.get_pulse.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/${aws_lambda_function.pulsewatch_hello.arn}/invocations"
}

# Lambda Permission for API Gateway
resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.pulsewatch_hello.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.pulsewatch_api.execution_arn}/prod/GET/pulse"

  depends_on = [
    aws_api_gateway_integration.lambda_integration,
    aws_api_gateway_deployment.pulsewatch_deployment,
    aws_api_gateway_stage.pulsewatch_stage
  ]
}

# Deploy API Gateway
resource "aws_api_gateway_deployment" "pulsewatch_deployment" {
  rest_api_id = aws_api_gateway_rest_api.pulsewatch_api.id

  depends_on = [
    aws_api_gateway_integration.lambda_integration
  ]
}

# Create Stage: prod
resource "aws_api_gateway_stage" "pulsewatch_stage" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.pulsewatch_api.id
  deployment_id = aws_api_gateway_deployment.pulsewatch_deployment.id
}

# Output the final API URL
output "api_gateway_url" {
  value = "https://${aws_api_gateway_rest_api.pulsewatch_api.id}.execute-api.us-east-1.amazonaws.com/prod/pulse"
}
