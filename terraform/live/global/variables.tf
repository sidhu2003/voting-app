variable "project" {
  description = "Project slug."
  type        = string
  default     = "voting-app"
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "ap-south-1"
}

variable "owner" {
  description = "Owner tag."
  type        = string
  default     = "venkata"
}

variable "services" {
  description = "One ECR repository per service."
  type        = list(string)
  default     = ["vote", "result", "worker"]
}

variable "image_retention_count" {
  description = "How many tagged images to keep per repository before expiring the oldest."
  type        = number
  default     = 10
}
