output "bucket_id" {
  description = "S3 bucket ID (name)"
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.this.arn
}

output "bucket_region" {
  description = "Region where bucket exists (inferred via provider)"
  value       = aws_s3_bucket.this.region
  # note: older aws provider versions may not expose region attribute; if not available, remove or compute at env-level
}