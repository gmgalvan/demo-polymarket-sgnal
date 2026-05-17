variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "instance_type" {
  type    = string
  default = "g5.xlarge"
}

variable "server_port" {
  type    = number
  default = 8000
}

variable "hf_token" {
  type      = string
  sensitive = true
  default   = ""
}

variable "model_id" {
  type    = string
  default = "TinyLlama/TinyLlama-1.1B-Chat-v1.0"
}
