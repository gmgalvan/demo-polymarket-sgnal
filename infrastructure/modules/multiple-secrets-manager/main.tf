resource "aws_secretsmanager_secret" "this" {
  for_each = var.secrets

  name                    = each.value.name
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(
    var.tags,
    {
      SecretPurpose = each.key
    },
  )
}

resource "aws_secretsmanager_secret_version" "this" {
  for_each = var.secrets

  lifecycle {
    ignore_changes = [secret_string]
  }

  secret_id     = aws_secretsmanager_secret.this[each.key].id
  secret_string = jsonencode(each.value.initial_payload)
}
