resource "aws_ecs_cluster" "ecs-cluster" {
  name = "${var.project_name}-${var.env}-cluster"
}

resource "aws_cloudwatch_log_group" "ecs-log-group" {
  name = "/ecs/${var.project_name}-${var.env}-task-definition"
}

resource "aws_ecs_task_definition" "ecs-task" {
  family                   = "${var.project_name}-${var.env}-task-definition"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.cpu   
  memory                   = var.memory
  execution_role_arn       = "arn:aws:iam::713881805414:role/ecsTaskExecutionRole"
  task_role_arn            = "arn:aws:iam::713881805414:role/ecsTaskExecutionRole"

  container_definitions = jsonencode([
    {
      name  = "${var.project_name}-${var.env}-con"
      image = var.docker_image_name               
      essential : true

      portMappings = [
        {
          containerPort = tonumber(var.container_port)
          hostport      = tonumber(var.container_port)
          protocol      = "tcp"
          appProtocol   = "http"
        }
      ],

      environmentFiles = [
        {
          value = var.s3_env_vars_file_arn,
          type  = "s3"
        }
      ],

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-create-group"  = "true"
          "awslogs-group"         = aws_cloudwatch_log_group.ecs-log-group.name
          "awslogs-region"        = var.awslogs_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "ecs-service" {
  name            = "${var.project_name}-service"
  launch_type     = "FARGATE"
  cluster         = aws_ecs_cluster.ecs-cluster.id
  task_definition = aws_ecs_task_definition.ecs-task.arn
  desired_count   = 1

  # Define configurações de rede para o serviço ECS
  network_configuration {
    assign_public_ip = true
    subnets          = [module.vpc.public_subnets[0]]                      
    security_groups  = [module.container-security-group.security_group_id] 
  }

  # Configura o balanceamento de carga para o serviço ECS
  health_check_grace_period_seconds = 0
  load_balancer {
    target_group_arn = aws_lb_target_group.ecs-target-group.arn
    container_name   = "${var.project_name}-${var.env}-con"
    container_port   = var.container_port
  }
}

# Define o Application Load Balancer (ALB)
resource "aws_lb" "ecs-alb" {
  name               = "${var.project_name}-${var.env}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [module.alb-security-group.security_group_id]                
  subnets            = [module.vpc.public_subnets[0], module.vpc.public_subnets[1]] 
}

# Define o Target Group
resource "aws_lb_target_group" "ecs-target-group" {
  name        = "${var.project_name}-${var.env}-target-group"
  port        = var.container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = module.vpc.vpc_id 

  health_check {
    path                = var.health_check_path 
    protocol            = "HTTP"
    matcher             = "200-299"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
  }
}

# O Listener associa o ALB com o Target Group
resource "aws_lb_listener" "ecs-listener" {
  load_balancer_arn = aws_lb.ecs-alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs-target-group.arn
  }
}


