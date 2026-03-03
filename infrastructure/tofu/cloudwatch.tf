# CloudWatch Logging fuer den Backend-Container auf EC2.
#
# Befehle:
# tofu plan -var-file=dev.tfvars
# tofu apply -var-file=dev.tfvars
# tofu destroy -var-file=dev.tfvars

# Aufbewahrungsdauer der CloudWatch-Logs in Tagen.
variable "log_retention_days" {
  type        = number
  description = "Retention fuer CloudWatch Log Group in Tagen."
  default     = 14
}

# Name der Log Group, damit sie in dev/prod sauber unterscheidbar bleibt.
variable "cloudwatch_log_group_name" {
  type        = string
  description = "CloudWatch Log Group Name fuer Backend-Container-Logs."
  default     = "/grocerymate/ec2/backend"
}

# Log Group fuer Docker-Container-Logs.
resource "aws_cloudwatch_log_group" "backend" {
  name              = var.cloudwatch_log_group_name
  retention_in_days = var.log_retention_days

  tags = {
    Name        = var.cloudwatch_log_group_name
    Environment = "Dev"
    Project     = "GroceryMate"
  }
}

# IAM-Policy-Dokument fuer CloudWatch Logs API-Zugriffe von EC2.
data "aws_iam_policy_document" "ec2_cloudwatch_logs_doc" {
  statement {
    sid    = "AllowCloudWatchLogsWrite"
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents"
    ]

    resources = [
      aws_cloudwatch_log_group.backend.arn,
      "${aws_cloudwatch_log_group.backend.arn}:*"
    ]
  }
}

# IAM-Policy auf Basis des obigen Dokuments.
resource "aws_iam_policy" "ec2_cloudwatch_logs" {
  name        = "grocery-ec2-cloudwatch-logs"
  description = "Erlaubt dem EC2-Backend das Schreiben in CloudWatch Logs."
  policy      = data.aws_iam_policy_document.ec2_cloudwatch_logs_doc.json
}

# Verknuepfung der CloudWatch-Policy mit der vorhandenen EC2-IAM-Rolle.
resource "aws_iam_role_policy_attachment" "ec2_cloudwatch_logs_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ec2_cloudwatch_logs.arn
}
