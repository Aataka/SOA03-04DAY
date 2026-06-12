variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "instance_type" {
  description = "EC2 instance type for AppServer"
  type        = string
  default     = "t3.micro"
}

variable "canary_site" {
  description = "URL the Lambda canary checks"
  type        = string
  default     = "https://docs.aws.amazon.com/lambda/latest/dg/welcome.html"
}

variable "canary_expected" {
  description = "String the Lambda canary expects in the response body"
  type        = string
  default     = "What is AWS Lambda?"
}

variable "mem_alarm_threshold" {
  description = "mem_used_percent alarm threshold (%)"
  type        = number
  default     = 80
}
