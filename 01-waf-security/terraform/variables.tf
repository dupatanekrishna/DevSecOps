variable "aws_region" {
  description = "AWS region for regional resources"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "devsecops-waf-lab"
}

variable "alert_email" {
  description = "Email address used for security lab alerts"
  type        = string
}
