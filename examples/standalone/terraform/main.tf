provider "aws" {
  region = var.aws_region
}

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
  name_prefix = "manual-model-demo-"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = var.server_port
    to_port     = var.server_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role" "server" {
  name_prefix        = "manual-model-demo-"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.server.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "server" {
  name_prefix = "manual-model-demo-"
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
    load_model_py_b64    = base64encode(file("${path.module}/../app/01-load-model.py"))
    server_py_b64        = base64encode(file("${path.module}/../app/server.py"))
    requirements_txt_b64 = base64encode(file("${path.module}/../app/requirements.txt"))
    model_id             = var.model_id
    hf_token             = var.hf_token
    server_port          = var.server_port
  })

  root_block_device {
    volume_size = 150
    volume_type = "gp3"
  }
}
