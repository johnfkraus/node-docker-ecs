provider "aws" {
  region  = "us-east-1" # Setting my region to London. Use your own region here
  profile = "terraform-user-pgrm"
  default_tags {
    tags = {
      Owner   = "John Kraus"
      Project = "How to Deploy a Dockerised Application on AWS ECS With Terraform"
      MyTag = "Demo"
    }
  }
}

resource "aws_ecr_repository" "my_first_ecr_repo" {
  name = "my-first-ecr-repo" # Naming my repository
  # lifecycle {
  #   prevent_destroy = true
  # }
}

resource "aws_ecs_cluster" "my_cluster" {
  name = "my-cluster" # Naming the cluster
}

resource "aws_ecs_task_definition" "my_first_task" {
  family                   = "my-first-task" # Naming our first task
  container_definitions    = <<DEFINITION
  [
    {
      "name": "my-first-task",
      "image": "${aws_ecr_repository.my_first_ecr_repo.repository_url}",
      "essential": true,
      "portMappings": [
        {
          "containerPort": 3000,
          "hostPort": 3000
        }
      ],
      "memory": 512,
      "cpu": 256
    }
  ]
  DEFINITION
  requires_compatibilities = ["FARGATE"] # Stating that we are using ECS Fargate
  network_mode             = "awsvpc"    # Using awsvpc as our network mode as this is required for Fargate
  memory                   = 512         # Specifying the memory our container requires
  cpu                      = 256         # Specifying the CPU our container requires
  execution_role_arn = aws_iam_role.ecsTaskExecutionRole2.arn
}

resource "aws_iam_role" "ecsTaskExecutionRole2" {
  name               = "ecsTaskExecutionRole2"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
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

resource "aws_iam_role_policy_attachment" "ecsTaskExecutionRole_policy" {
  role       = aws_iam_role.ecsTaskExecutionRole2.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Providing a reference to our default VPC
resource "aws_default_vpc" "default_vpc" {
}

# Providing a reference to our default subnets
resource "aws_default_subnet" "default_subnet_a" {
  availability_zone = "us-east-1a"
}

resource "aws_default_subnet" "default_subnet_b" {
  availability_zone = "us-east-1b"
}

# resource "aws_default_subnet" "default_subnet_c" {
#   availability_zone = "us-east-1c"
# }

resource "aws_ecs_service" "my_first_service" {
  name            = "my-first-service"                        # Naming our first service
  cluster         = aws_ecs_cluster.my_cluster.id             # Referencing our created Cluster
  task_definition = aws_ecs_task_definition.my_first_task.arn # Referencing the task our service will spin up
  launch_type     = "FARGATE"
  desired_count   = 2 # Setting the number of containers to 3

  load_balancer {
    target_group_arn = aws_lb_target_group.target_group.arn # Referencing our target group
    container_name   = aws_ecs_task_definition.my_first_task.family
    container_port   = 3000 # Specifying the container port
  }

  network_configuration {
    # subnets          = ["${aws_default_subnet.default_subnet_a.id}", "${aws_default_subnet.default_subnet_b.id}", "${aws_default_subnet.default_subnet_c.id}"]
    subnets          = ["${aws_default_subnet.default_subnet_a.id}", "${aws_default_subnet.default_subnet_b.id}"]
    assign_public_ip = true # Providing our containers with public IPs
    security_groups  = ["${aws_security_group.service_security_group.id}"]
  }
}

resource "aws_security_group" "service_security_group" {
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    # Only allowing traffic in from the load balancer security group
    security_groups = ["${aws_security_group.load_balancer_security_group.id}"]
  }

  egress {
    from_port   = 0             # Allowing any incoming port
    to_port     = 0             # Allowing any outgoing port
    protocol    = "-1"          # Allowing any outgoing protocol 
    cidr_blocks = ["0.0.0.0/0"] # Allowing traffic out to all IP addresses
  }
}


resource "aws_alb" "application_load_balancer" {
  name               = "test-lb-tf" # Naming our load balancer
  load_balancer_type = "application"
  # subnets = [ # Referencing the default subnets
  #   "${aws_default_subnet.default_subnet_a.id}",
  #   "${aws_default_subnet.default_subnet_b.id}",
  #   "${aws_default_subnet.default_subnet_c.id}"
  # ]
  subnets = [ # Referencing the default subnets
    "${aws_default_subnet.default_subnet_a.id}",
  "${aws_default_subnet.default_subnet_b.id}"]

  # Referencing the security group
  security_groups = ["${aws_security_group.load_balancer_security_group.id}"]
}

# Creating a security group for the load balancer:
resource "aws_security_group" "load_balancer_security_group" {
  ingress {
    from_port   = 80 # Allowing traffic in from port 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Allowing traffic in from all sources
  }

  egress {
    from_port   = 0             # Allowing any incoming port
    to_port     = 0             # Allowing any outgoing port
    protocol    = "-1"          # Allowing any outgoing protocol 
    cidr_blocks = ["0.0.0.0/0"] # Allowing traffic out to all IP addresses
  }
}

resource "aws_lb_target_group" "target_group" {
  name        = "target-group"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_default_vpc.default_vpc.id # Referencing the default VPC
  health_check {
    matcher = "200,301,302"
    path    = "/"
  }
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_alb.application_load_balancer.arn # Referencing our load balancer
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target_group.arn # Referencing our target group
  }
}

output "lb_dns_name" {
  value = aws_alb.application_load_balancer.dns_name
}
