variable "bucket_name" {
  description = "Globally-unique S3 bucket name to create"
  type        = string
}

variable "env" {
  description = "Environment name (dev/qa/staging/prod)"
  type        = string
}

variable "versioning" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = "Allow bucket to be destroyed even if it contains objects (use with caution)"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags to attach to the bucket"
  type        = map(string)
  default     = {}
}
