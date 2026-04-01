resource "aws_ecs_cluster" "taskoverflow" {
  name = "taskoverflow"
}

resource "aws_ecs_task_definition" "taskoverflow" {
  family                   = "taskoverflow"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 1024
  memory                   = 2048
  execution_role_arn       = data.aws_iam_role.lab.arn

  container_definitions = <<DEFINITION
[
  {
    "image": "${local.image}",
    "cpu": 1024,
    "memory": 2048,
    "name": "taskoverflow",
    "networkMode": "awsvpc",
    "portMappings": [
      {
        "containerPort": 6400,
        "hostPort": 6400
      }
    ],
    "environment": [
      {
        "name": "SQLALCHEMY_DATABASE_URI",
        "value": "postgresql://${local.database_username}:${local.database_password}@${aws_db_instance.taskoverflow_database.address}:${aws_db_instance.taskoverflow_database.port}/${aws_db_instance.taskoverflow_database.db_name}"
      }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "/taskoverflow/db",
        "awslogs-region": "us-east-1",
        "awslogs-stream-prefix": "ecs",
        "awslogs-create-group": "true"
      }
    }
  }
]
DEFINITION
}

resource "aws_ecs_service" "taskoverflow" {
  name            = "taskoverflow"
  cluster         = aws_ecs_cluster.taskoverflow.id
  task_definition = aws_ecs_task_definition.taskoverflow.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets             = data.aws_subnets.private.ids
    security_groups     = [aws_security_group.taskoverflow.id]
    assign_public_ip    = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.taskoverflow.arn
    container_name = "taskoverflow"
    container_port = 6400
  }

}

resource "aws_security_group" "taskoverflow" {
  name = "taskoverflow"
  description = "TaskOverflow Security Group"

  ingress {
    from_port = 6400
    to_port = 6400
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "taskoverflow_security_group"
  }
}

resource "aws_lb_target_group" "taskoverflow" {
  name = "taskoverflow"
  port = 6400
  protocol = "HTTP"
  vpc_id = aws_security_group.taskoverflow.vpc_id
  target_type = "ip"

  health_check {
    path = "/api/v1/health"
    port = "6400"
    protocol = "HTTP"
    healthy_threshold = 2
    unhealthy_threshold = 2
    timeout = 5
    interval = 10
  }
}

resource "aws_lb" "taskoverflow" {
  name = "taskoverflow"
  internal = false
  load_balancer_type = "application"
  subnets = data.aws_subnets.private.ids
  security_groups = [aws_security_group.taskoverflow_lb.id]
}

resource "aws_security_group" "taskoverflow_lb" {
  name = "taskoverflow_lb"
  description = "TaskOverflow Load Balancer Security Group"

  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "taskoverflow_lb_security_group"
  }
}

resource "aws_lb_listener" "taskoverflow" {
  load_balancer_arn = aws_lb.taskoverflow.arn
  port = "80"
  protocol =  "HTTP"

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.taskoverflow.arn
  }
}

resource "aws_appautoscaling_target" "taskoverflow" {
  max_capacity = 4
  min_capacity = 1
  resource_id = "service/taskoverflow/taskoverflow"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace = "ecs"

  depends_on = [aws_ecs_service.taskoverflow]
}

resource "aws_appautoscaling_policy" "taskoverflow-cpu" {
  name = "taskoverflow-cpu"
  policy_type = "TargetTrackingScaling"
  resource_id = aws_appautoscaling_target.taskoverflow.resource_id
  scalable_dimension = aws_appautoscaling_target.taskoverflow.scalable_dimension
  service_namespace = aws_appautoscaling_target.taskoverflow.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = 20
  }
}

output "taskoverflow_dns_name" {
value = aws_lb.taskoverflow.dns_name
description = "DNS name of the TaskOverflow load balancer."
}
