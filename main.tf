# --- Data sources -----------------------------------------------------------

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# --- CloudWatch Agent config in Parameter Store -----------------------------
# ラボの「AgentConfigFile」相当。名前を AmazonCloudWatch- で始めるのは、
# CloudWatchAgentServerPolicy が ssm:GetParameter を
# arn:aws:ssm:*:*:parameter/AmazonCloudWatch-* にしか許可していないため。

resource "aws_ssm_parameter" "cw_agent_config" {
  name = "AmazonCloudWatch-AgentConfigFile"
  type = "String"

  value = jsonencode({
    agent = {
      metrics_collection_interval = 60
    }
    metrics = {
      namespace = "CWAgent"
      append_dimensions = {
        InstanceId = "$${aws:InstanceId}"
      }
      metrics_collected = {
        mem = {
          measurement = ["mem_used_percent"]
        }
        swap = {
          measurement = ["swap_used_percent"]
        }
      }
    }
  })
}

# --- IAM for EC2 (SSM + CloudWatch Agent) ------------------------------------

resource "aws_iam_role" "app_server" {
  name_prefix = "soa03-4day-appserver-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.app_server.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cw_agent" {
  role       = aws_iam_role.app_server.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "app_server" {
  name_prefix = "soa03-4day-appserver-"
  role        = aws_iam_role.app_server.name
}

# --- Security group (egress only: Session Manager / SSM endpoints) -----------

resource "aws_security_group" "app_server" {
  name_prefix = "soa03-4day-appserver-"
  description = "AppServer: no ingress, egress only (SSM/CloudWatch)"
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- EC2 AppServer ------------------------------------------------------------

resource "aws_instance" "app_server" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.app_server.id]
  iam_instance_profile   = aws_iam_instance_profile.app_server.name

  user_data = templatefile("${path.module}/user_data.sh.tpl", {
    cw_agent_param = aws_ssm_parameter.cw_agent_config.name
  })

  metadata_options {
    http_tokens   = "required" # IMDSv2 必須
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "AppServer"
  }
}
