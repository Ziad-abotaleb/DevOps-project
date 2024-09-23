resource "aws_vpc" "main" {
  cidr_block       = "10.0.0.0/16"
  

  tags = {
    Name = "vpc_project"
  }
}
resource "aws_subnet" "pub-subnet1" {
  vpc_id = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  tags = {
   Name = "pub_subnet_1"
  }
}
resource "aws_subnet" "pub-subnet2" {
  vpc_id = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-east-1b"
  tags = {
   Name = "pub_subnet_2"
  }
}
resource "aws_subnet" "private-subnet1" {
  vpc_id = aws_vpc.main.id
  cidr_block = "10.0.3.0/24"
  availability_zone = "us-east-1a"
  tags = {
   Name = "private_subnet_1"
  }
}
resource "aws_subnet" "private-subnet2" {
  vpc_id = aws_vpc.main.id
  cidr_block = "10.0.4.0/24"
  availability_zone = "us-east-1b"
  tags = {
   Name = "private_subnet_2"
  }
}
resource "aws_instance" "bastion_host" {
  ami = "ami-0182f373e66f89c85"
  instance_type = "t2.micro"
  subnet_id = aws_subnet.pub-subnet1.id
  vpc_security_group_ids = [aws_security_group.SG.id]
  tags = {
    Name = "Bastion_host"
  }
  
}
resource "aws_internet_gateway" "IGW" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "main_gateway"
  }
}
resource "aws_eip" "nat_eip" {
  tags = {
    Name = "nat-eip"
  }
}
  resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.pub-subnet2.id
  tags = {
    Name = "nat-gateway"
  }
}
resource "aws_route_table" "pub_RT" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "public_RT"
  }
}
  resource "aws_route" "internet_access" {
    route_table_id = aws_route_table.pub_RT.id
    destination_cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.IGW.id
  }
resource "aws_route_table" "priv_RT" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "private_RT"
  }
}
resource "aws_route" "private_route" {
  route_table_id         = aws_route_table.priv_RT.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gw.id
}
resource "aws_route_table_association" "subnet1_association" {
  subnet_id      = aws_subnet.private-subnet1.id
  route_table_id = aws_route_table.priv_RT.id
}
resource "aws_route_table_association" "subnet2_association" {
  subnet_id      = aws_subnet.private-subnet2.id
  route_table_id = aws_route_table.priv_RT.id
}
resource "aws_route_table_association" "subnet3_association" {
  subnet_id      = aws_subnet.pub-subnet1.id
  route_table_id = aws_route_table.pub_RT.id
}
resource "aws_route_table_association" "subnet4_association" {
  subnet_id      = aws_subnet.pub-subnet2.id
  route_table_id = aws_route_table.pub_RT.id
}
resource "aws_security_group" "SG" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Add SSH ingress rule
  ingress {
    from_port   = 22
    to_port     = 22
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
    Name = "HTTP-SG"
  }
}
resource "aws_security_group" "Bastion-SG" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
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
    Name = "bastion-SG"
  }
}
resource "aws_lb" "test" {
  name               = "ALB-zeyad"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.SG.id]
  subnets            = [aws_subnet.pub-subnet1.id, aws_subnet.pub-subnet2.id]

  enable_deletion_protection = false

  tags = {
    Name = "zeyad-lb"
  }
}
resource "aws_lb_target_group" "TG" {
  name        = "TG"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
 health_check {
    protocol = "HTTP"
    path     = "/"
  }

  tags = {
    Name = "TG"
  }
}
resource "aws_launch_configuration" "app" {
  name          = "app-launch-configuration"
  image_id      = "ami-0182f373e66f89c85"
  instance_type = "t2.micro"
  security_groups      = [aws_security_group.SG.id]

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y python3
              echo "Hello, World from ASG" > /home/ec2-user/index.html
              cd /home/ec2-user
              python3 -m http.server 80 &
              EOF
}

resource "aws_autoscaling_group" "app" {
  launch_configuration = aws_launch_configuration.app.id
  min_size             = 1
  max_size             = 3
  desired_capacity     = 2
  vpc_zone_identifier  = [aws_subnet.private-subnet1.id, aws_subnet.private-subnet2.id]

  target_group_arns = [aws_lb_target_group.TG.arn]

  tag {
    key                 = "Name"
    value               = "ASG_Instance"
    propagate_at_launch = true
  }

  lifecycle {
    ignore_changes = [desired_capacity]  
  }
}