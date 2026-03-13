# IAM policy document that allows AWS Lambda service to assume a role
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# IAM role specifically for AWS Lambda functions
resource "aws_iam_role" "lambda" {
  name               = var.role_name
  description        = var.role_description
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

# IAM policy to allow Lambda function to read/write from/to the S3 bucket
resource "aws_iam_policy" "this" {
  name        = var.s3_lambda_access_policy_name
  description = "Allow Lambda to read/write from/to the S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"],
        Resource = [var.bucket_arn, "${var.bucket_arn}/*"]
      }
    ]
  })
}

# Attach the above policy to the specified IAM role
resource "aws_iam_role_policy_attachment" "this" {
  policy_arn = aws_iam_policy.this.arn
  role       = aws_iam_role.lambda.name
}

# Attach the AWS managed basic execution role policy to the Lambda role
# This provides permissions for Lambda functions to send logs to AWS CloudWatch
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda.name
}

# Custom IAM policy allowing Lambda to read from ECR
resource "aws_iam_policy" "lambda_ecr_access" {
  name        = var.ecr_policy_name
  description = var.ecr_policy_description

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ],
        Resource = var.ecr_policy_resource
      }
    ]
  })
}

# Attach the custom ECR access policy to the Lambda role
resource "aws_iam_role_policy_attachment" "lambda_ecr_access" {
  policy_arn = aws_iam_policy.lambda_ecr_access.arn
  role       = aws_iam_role.lambda.name
}

# Textract IAM Policy
resource "aws_iam_policy" "textract_policy" {
  count       = var.enable_textract_policy ? 1 : 0
  name        = var.texttrack_lambda_access_policy_name
  description = "Policy to allow Textract operations"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["textract:DetectDocumentText"],
        Resource = "*"
      },
    ]
  })
}

# Attach the Textract policy to the Lambda role
resource "aws_iam_role_policy_attachment" "textract_attach" {
  count      = var.enable_textract_policy ? 1 : 0
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.textract_policy[0].arn
}

resource "aws_iam_policy" "lambda_ec2_access" {
  name        = var.ec2_policy_name
  description = var.ec2_policy_description

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "ec2:DetachNetworkInterface",
          "ec2:AttachNetworkInterface",
          "SNS:Publish",
          "comprehendmedical:DetectEntitiesV2",
          "comprehendmedical:DetectEntities",
          "comprehendmedical:DetectPHI",

          "comprehendmedical:StartEntitiesDetectionV2Job",
          "comprehendmedical:ListEntitiesDetectionV2Jobs",
          "comprehendmedical:DescribeEntitiesDetectionV2Job",
          "comprehendmedical:StopEntitiesDetectionV2Job",
          "comprehendmedical:StartPHIDtectionJob",
          "comprehendmedical:ListPHIDetectionJobs",
          "comprehendmedical:DescribePHIDetectionJob",
          "comprehendmedical:StopPHIDetectionJob",

          "comprehendmedical:StartRxNormInferenceJob",
          "comprehendmedical:ListRxNormInferenceJobs",
          "comprehendmedical:DescribeRxNormInferenceJob",
          "comprehendmedical:StopRxNormInferenceJob",

          "comprehendmedical:StartICD10CMInferenceJob",
          "comprehendmedical:ListICD10CMInferenceJobs",
          "comprehendmedical:DescribeICD10CMInferenceJob",
          "comprehendmedical:StopICD10CMInferenceJob",

          "comprehendmedical:StartSNOMEDCTInferenceJob",
          "comprehendmedical:ListSNOMEDCTInferenceJobs",
          "comprehendmedical:DescribeSNOMEDCTInferenceJob",
          "comprehendmedical:StopSNOMEDCTInferenceJob",

          "comprehendmedical:InferRxNorm",
          "comprehendmedical:InferICD10CM",
          "comprehendmedical:InferSNOMEDCT"
        ],
        Resource = var.ecr_policy_resource
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_ec2_access" {
  policy_arn = aws_iam_policy.lambda_ec2_access.arn
  role       = aws_iam_role.lambda.name
}
