output "ec2_public_ip" {
  description = "Oeffentliche IP der EC2-Instanz."
  value       = aws_instance.ec2.public_ip
}

output "rds_endpoint" {
  description = "Endpoint der PostgreSQL-RDS-Instanz."
  value       = aws_db_instance.postgres.address
}

output "s3_avatar_bucket_name" {
  description = "Name des erzeugten S3-Buckets fuer Avatare."
  value       = aws_s3_bucket.avatars.bucket
}

output "cloudwatch_log_group_name" {
  description = "CloudWatch Log Group fuer Backend-Container-Logs."
  value       = aws_cloudwatch_log_group.backend.name
}
