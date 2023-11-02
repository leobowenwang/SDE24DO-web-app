provider "aws" {
  region = "us-east-1"
}

variable "ecr_repository_url" {
  description = "The URL of the ECR repository"
  default     = "245154219216.dkr.ecr.us-east-1.amazonaws.com/wang-repo"
}

resource "aws_ecr_repository" "app_repository" {
  name = "wang-repo"
}

resource "aws_ecs_cluster" "app_cluster" {
  name = "next-js-app-cluster"
}

resource "aws_ecs_task_definition" "app_task" {
  family                   = "next-js-app"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  container_definitions    = jsonencode([{
    name  = "next-js-app-container"
    image = var.ecr_repository_url
    portMappings = [{
      containerPort = 3000
      hostPort      = 3000
    }]
  }])
  cpu    = "256"
  memory = "512"
}

resource "aws_ecs_service" "app_service" {
  name            = "next-js-app-service"
  cluster         = aws_ecs_cluster.app_cluster.id
  task_definition = aws_ecs_task_definition.app_task.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets = [aws_subnet.app_subnet.id]
    security_groups = [aws_security_group.app_sg.id]
  }
}

resource "aws_vpc" "app_vpc" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "app_subnet" {
  vpc_id     = aws_vpc.app_vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1a"
}

resource "aws_security_group" "app_sg" {
  vpc_id = aws_vpc.app_vpc.id

  ingress {
    from_port   = 3000
    to_port     = 3000
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

resource "aws_alb" "app_alb" {
  name               = "next-js-app-alb"
  subnets            = [aws_subnet.app_subnet.id]
  security_groups    = [aws_security_group.app_sg.id]
  internal           = false
  load_balancer_type = "application"
}

resource "aws_alb_listener" "app_alb_listener" {
  load_balancer_arn = aws_alb.app_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.app_tg.arn
  }
}

resource "aws_alb_target_group" "app_tg" {
  name     = "next-js-app-tg"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = aws_vpc.app_vpc.id

  health_check {
    path     = "/"
    protocol = "HTTP"
    matcher  = "200"
  }
}

resource "aws_iam_role" "ecs_execution_role" {
  name = "ecs_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy_attachment" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}