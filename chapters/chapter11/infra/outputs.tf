output "bucket_name" {
  value = aws_s3_bucket.techflow_ml.id
}

output "scores_uri" {
  value = "s3://${aws_s3_bucket.techflow_ml.id}/scores/"
}

output "techflow_ml_role_arn" {
  value = aws_iam_role.techflow_ml.arn
}
