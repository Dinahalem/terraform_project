provider "aws" {
  region = "${var.AWS_REGION}"
  access_key = "${var.AWS_ACCESS_KEY}"
  secret_key = "${var.AWS_SECRET_KEY}"
}
#create vpc
resource "aws_vpc" "first-vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "production"
}
}
#create internet gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.first-vpc.id

}

#create custom route table
resource "aws_route_table" "prod-route-table" {
  vpc_id = aws_vpc.first-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  #route {
    #ipv6_cidr_block        = "::/0"
   # egress_only_gateway_id = aws_internet_gateway.gw.id
  #}

  tags = {
    Name = "Prod"
  }
}


variable "subnet_prefix" {
  description = "cidr block for the subnet"
}

#create subnet
resource "aws_subnet" "my_subnet" {
  vpc_id            = aws_vpc.first-vpc.id
  #cidr_block       = "10.0.1.0/24"
  cidr_block        = var.subnet_prefix[0].cidr_block
  availability_zone = "us-east-1a"

  tags = {
    Name = var.subnet_prefix[0].name
  }
}
#create subnet 2
resource "aws_subnet" "my_subnet2" {
  vpc_id            = aws_vpc.first-vpc.id
  cidr_block        = var.subnet_prefix[1].cidr_block
  availability_zone = "us-east-1a"

  tags = {
    Name = var.subnet_prefix[1].name
  }
}

#create associate route table
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.my_subnet.id
  route_table_id = aws_route_table.prod-route-table.id
}

#create security group
resource "aws_security_group" "allow_web" {
  name        = "allow_web_traffic"
  description = "Allow web inbound traffic"
  vpc_id      = aws_vpc.first-vpc.id

  ingress {
    description      = "HTTPS"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  ingress {
    description      = "HTTP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  ingress {
    description      = "SSH"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_web"
  }
}

#create network interface
resource "aws_network_interface" "web-server-nic" {
  subnet_id       = aws_subnet.my_subnet.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.allow_web.id]
}

#create elastic ip eip
resource "aws_eip" "one" {
  vpc                       = true
  network_interface         = aws_network_interface.web-server-nic.id
  associate_with_private_ip = "10.0.1.50"
  depends_on                = [aws_internet_gateway.gw]
}

output "server_public_ip" {
  value = aws_eip.one.public_ip
}

#create instance ec2
resource "aws_instance" "first-server" {
  ami           = "ami-005de95e8ff495156"
  instance_type = "t2.micro"
  security_groups = [aws_security_group.allow_web.name]
  availability_zone = "us-east-1a"
  key_name = "main-key"

  network_interface {
    device_index = 0
    network_interface_id = aws_network_interface.web-server-nic.id
  }

  user_data = <<-EOF
              #! /bin/bash
              sudo apt update -y
              sudo apt install apache2 -y
              sudo systemctl start apache2
              sudo bash -c 'echo your very first web server > /var/www/html/index.html'
              EOF
  tags = {
    Name = "ubuntu"
  }
}

#Create ALB
resource "aws_alb" "alb" {
  name            = "terraform-example-alb"
  security_groups = ["${aws_security_group.allow_web.id}"]
  subnets         = ["${aws_subnet.my_subnet.id, my_subnet2.id}"]
  tags {
    Name = "terraform-example-alb"
  }
}


#Create a new target group for the application load balancer. Traffic will be routed to target web server instances on HTTP port 80.
resource "aws_alb_target_group" "group" {
  name     = "terraform-example-alb-target"
  port     = 80
  protocol = "HTTP"
  vpc_id   = "${aws_vpc.first-vpc.id}"
  stickiness {
    type = "lb_cookie"
  }
  # Alter the destination of the health check to be the login page.
  health_check {
    path = "/login"
    port = 80
  }
}
#The first listener is configured to accept HTTP client connections.
resource "aws_alb_listener" "listener_http" {
  load_balancer_arn = "${aws_alb.alb.arn}"
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = "${aws_alb_target_group.group.arn}"
    type             = "forward"
  }
}

#AutoScaling Group
resource "aws_autoscaling_group" "web_server_asg" {
  name                 = "web-server-asg"
  launch_configuration = aws_instance.first-server.name
  min_size             = 1
  max_size             = 3
  desired_capacity     = 2
  health_check_type    = "EC2"
  load_balancers       = [aws_elb.web_server_lb.name]
  vpc_zone_identifier  = [aws_subnet.my_subnet.id, my_subnet2.id]
}

output "server_private_ip" {
 value = aws_instance.first-server.private_ip
}
output "server_id" {
 value = aws_instance.first-server.id
}
