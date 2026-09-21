variable "name" {
  description = "Name prefix, e.g. 'voting-app-dev'."
  type        = string
}

variable "tags" {
  description = "Tags applied to every role."
  type        = map(string)
  default     = {}
}
