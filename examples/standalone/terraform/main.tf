data "aws_ssm_parameter" "gpu_ami" {
  name = "/aws/service/deeplearning/ami/x86_64/oss-nvidia-driver-gpu-pytorch-2.6-amazon-linux-2023/latest/ami-id"
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_security_group" "server" {
  name_prefix = "openclaw-demo-"
  vpc_id      = data.aws_vpc.default.id

  dynamic "ingress" {
    for_each = length(var.allowed_cidr_blocks) > 0 ? [1] : []

    content {
      from_port   = var.gateway_port
      to_port     = var.gateway_port
      protocol    = "tcp"
      cidr_blocks = var.allowed_cidr_blocks
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role" "server" {
  name_prefix        = "openclaw-demo-"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.server.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "server" {
  name_prefix = "openclaw-demo-"
  role        = aws_iam_role.server.name
}

resource "aws_instance" "server" {
  ami                         = data.aws_ssm_parameter.gpu_ami.value
  instance_type               = var.instance_type
  subnet_id                   = sort(data.aws_subnets.default.ids)[0]
  vpc_security_group_ids      = [aws_security_group.server.id]
  iam_instance_profile        = aws_iam_instance_profile.server.name
  associate_public_ip_address = true
  user_data_replace_on_change = true

  user_data = templatefile("${path.module}/cloud-init.sh.tftpl", {
    configure_openclaw_sh_b64 = base64encode(templatefile("${path.module}/../openclaw/configure-openclaw.sh.tftpl", {
      gateway_bind           = var.gateway_bind
      gateway_port           = var.gateway_port
      vllm_api_key           = var.vllm_api_key
      vllm_max_model_len     = var.vllm_max_model_len
      vllm_port              = var.vllm_port
      vllm_served_model_name = var.vllm_served_model_name
    }))
    gateway_token           = var.gateway_token
    install_openclaw_sh_b64 = base64encode(templatefile("${path.module}/../openclaw/install-openclaw.sh.tftpl", {}))
    install_vllm_sh_b64 = base64encode(templatefile("${path.module}/../vllm/install-vllm.sh.tftpl", {
      hf_token               = var.hf_token
      vllm_api_key           = var.vllm_api_key
      vllm_model_id          = var.vllm_model_id
      vllm_served_model_name = var.vllm_served_model_name
    }))
    vllm_api_key = var.vllm_api_key
    vllm_port    = var.vllm_port
    vllm_service_b64 = base64encode(templatefile("${path.module}/../vllm/vllm.service.tftpl", {
      vllm_api_key                = var.vllm_api_key
      vllm_gpu_memory_utilization = var.vllm_gpu_memory_utilization
      vllm_max_model_len          = var.vllm_max_model_len
      vllm_model_id               = var.vllm_model_id
      vllm_port                   = var.vllm_port
      vllm_served_model_name      = var.vllm_served_model_name
    }))
  })

  root_block_device {
    volume_size = 150
    volume_type = "gp3"
  }
}
