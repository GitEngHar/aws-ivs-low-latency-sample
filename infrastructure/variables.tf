variable "aws_region" {
  description = "AWS region to deploy resources into"
  type        = string
  default     = "ap-northeast-1"
}

variable "aws_profile" {
  description = "Named AWS CLI profile to authenticate with (see ~/.aws/config). Leave null to use the default credential chain (env vars, default profile, etc.)."
  type        = string
  default     = null
}

variable "name_prefix" {
  description = "Prefix applied to the names of resources created by this stack"
  type        = string
  default     = "ivs-low-latency-sample"
}
