output "ec2_public_ip" {
  value = aws_instance.ec2.public_ip
}

output "rds_endpoint" {
  value = aws_db_instance.postgres.address
}

output "s3_avatar_bucket_name" {
  value = aws_s3_bucket.avatars.bucket
}
