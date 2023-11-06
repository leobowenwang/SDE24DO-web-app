terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }
  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_ecr_repository" "aws-crud-ecr-repo" {
  name         = "wang-repo"
  force_delete = true
}

resource "aws_ecs_cluster" "aws-crud-cluster" {
  name = "wang-cluster"
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecsTaskExecutionRole" {
  name               = "wang-execution-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "ecsTaskExecutionRole_policy" {
  role       = aws_iam_role.ecsTaskExecutionRole.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ecs_task_definition" "aws-crud-task" {
  family                   = "wang-task"
  container_definitions    = jsonencode([{
    name        = "wang-container",
    image       = "${aws_ecr_repository.aws-crud-ecr-repo.repository_url}:latest",
    essential   = true,
    portMappings = [{
      containerPort = 3000,
      hostPort      = 3000
    }],
    memory      = 512,
    cpu         = 256
  }])
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  memory                   = 512
  cpu                      = 256
  execution_role_arn       = aws_iam_role.ecsTaskExecutionRole.arn
}

resource "aws_default_vpc" "default_vpc" {}

resource "aws_default_subnet" "default_subnet_a" {
  availability_zone = "us-east-1a"
}

resource "aws_default_subnet" "default_subnet_b" {
  availability_zone = "us-east-1b"
}

resource "aws_default_subnet" "default_subnet_c" {
  availability_zone = "us-east-1c"
}

resource "aws_alb" "aws-crud-lb" {
  name               = "wang-lb"
  load_balancer_type = "application"
  subnets = [
    aws_default_subnet.default_subnet_a.id,
    aws_default_subnet.default_subnet_b.id,
    aws_default_subnet.default_subnet_c.id
  ]
  security_groups = [aws_security_group.aws-crud-lb_security_group.id]
}

resource "aws_security_group" "aws-crud-lb_security_group" {
  ingress {
    from_port   = 80
    to_port     = 80
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

resource "aws_lb_target_group" "aws-crud-target_group" {
  name        = "wang-target-group"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_default_vpc.default_vpc.id
  health_check {
    matcher = "200,301,302"
    path    = "/"
  }
}

resource "aws_lb_listener" "aws-crud-listener" {
  load_balancer_arn = aws_alb.aws-crud-lb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.aws-crud-target_group.arn
  }
}

resource "aws_ecs_service" "aws-crud-service" {
  name            = "wang-service"
  cluster         = aws_ecs_cluster.aws-crud-cluster.id
  task_definition = aws_ecs_task_definition.aws-crud-task.arn
  launch_type     = "FARGATE"
  desired_count   = 3
  load_balancer {
    target_group_arn = aws_lb_target_group.aws-crud-target_group.arn
    container_name   = "wang-container"
    container_port   = 3000
  }
  network_configuration {
    subnets          = [aws_default_subnet.default_subnet_a.id, aws_default_subnet.default_subnet_b.id, aws_default_subnet.default_subnet_c.id]
    assign_public_ip = true
    security_groups  = [aws_security_group.aws-crud-service_security_group.id]
  }
}

resource "aws_security_group" "aws-crud-service_security_group" {
  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.aws-crud-lb_security_group.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

output "lb_dns" {
  value       = aws_alb.aws-crud-lb.dns_name
  description = "AWS load balancer DNS Name"
}

resource "aws_security_group" "allow_web_traffic" {
  name        = "allow_web_traffic"
  description = "Allow web inbound traffic"
  vpc_id      = "vpc-0e2232ea7e03046b9"

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_web_traffic"
  }
}

resource "aws_instance" "app_server" {
  ami                    = "ami-0e8a34246278c21e4"
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.allow_web_traffic.id]
  tags = {
    Name = "web-app"
  }
}
