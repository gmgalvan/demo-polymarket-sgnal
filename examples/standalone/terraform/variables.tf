variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "instance_type" {
  type    = string
  default = "g5.xlarge"
}

variable "gateway_port" {
  type    = number
  default = 18789
}

variable "gateway_bind" {
  type    = string
  default = "loopback"
}

variable "allowed_cidr_blocks" {
  type    = list(string)
  default = []
}

variable "hf_token" {
  type      = string
  sensitive = true
  default   = ""
}

variable "gateway_token" {
  type      = string
  sensitive = true
  default   = ""
}

variable "vllm_api_key" {
  type      = string
  sensitive = true
  default   = "vllm-local"
}

variable "vllm_gpu_memory_utilization" {
  type    = number
  default = 0.92
}

variable "vllm_max_model_len" {
  type    = number
  default = 32768
}

variable "vllm_model_id" {
  type    = string
  default = "Qwen/Qwen2.5-14B-Instruct-AWQ"
}

variable "vllm_port" {
  type    = number
  default = 8000
}

variable "vllm_served_model_name" {
  type    = string
  default = "qwen2.5-14b-instruct-awq-local"
}
