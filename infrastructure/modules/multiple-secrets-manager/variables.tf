variable "secrets" {
  description = "Map of logical secret keys to secret metadata."
  type = map(object({
    name            = string
    initial_payload = map(string)
  }))
}

variable "recovery_window_in_days" {
  description = "Number of days to wait before deleting a secret."
  type        = number
  default     = 7
}

variable "tags" {
  description = "Common tags applied to all secrets."
  type        = map(string)
  default     = {}
}
