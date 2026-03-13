resource "aws_iam_role" "this" {
  name               = var.name
  assume_role_policy = var.assume_role_policies
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each = { for idx, arn in var.policy_arns : tostring(idx) => arn }

  role       = aws_iam_role.this.name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "inline_policies" {
  count = length(var.inline_policies)

  role   = aws_iam_role.this.name
  name   = var.inline_policies[count.index]["name"]
  policy = var.inline_policies[count.index]["policy"]
}
