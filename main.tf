# -----------------------
# VPC
# -----------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "main-vpc"
  }
}

# -----------------------
# Subnets
# -----------------------
resource "aws_subnet" "public_1a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-1a"
  }
}

resource "aws_subnet" "public_1b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-1b"
  }
}

resource "aws_subnet" "private_1a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "private-1a"
  }
}

resource "aws_subnet" "private_1b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "private-1b"
  }
}

resource "aws_subnet" "private_3a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.5.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "private-3a"
  }
}

resource "aws_subnet" "private_3b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.6.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "private-3b"
  }
}

# -----------------------
# Internet Gateway
# -----------------------
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-igw"
  }
}

# -----------------------
# NAT Gateway
# -----------------------
resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_1a.id

  tags = {
    Name = "nat-gateway"
  }
}

# -----------------------
# Route Tables
# -----------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-rt"
  }
}

resource "aws_route_table_association" "public_1a" {
  subnet_id      = aws_subnet.public_1a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_1b" {
  subnet_id      = aws_subnet.public_1b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "private-rt"
  }
}

resource "aws_route_table_association" "private_1a" {
  subnet_id      = aws_subnet.private_1a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_1b" {
  subnet_id      = aws_subnet.private_1b.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_3a" {
  subnet_id      = aws_subnet.private_3a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_3b" {
  subnet_id      = aws_subnet.private_3b.id
  route_table_id = aws_route_table.private.id
}

# -----------------------
# Security Group
# -----------------------
resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.main.id
  name   = "web-sg"

  # HTTP for Web Servers
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH for Admin
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # MySQL for RDS
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    # Option 1: allow all (not secure in prod)
    # cidr_blocks = ["0.0.0.0/0"]

    # Option 2 (recommended): allow only within VPC
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "web-sg"
  }
}

# -----------------------
# Launch Template for Public Instances
# -----------------------
resource "aws_launch_template" "public_web_lt" {
  name_prefix   = "public-web-"
  image_id      = "ami-020cba7c55df1f615"
  instance_type = "t2.micro"

  vpc_security_group_ids = [aws_security_group.web_sg.id]

  user_data = base64encode(<<-EOF
              #!/bin/bash
              apt update -y
              apt install -y apache2
              systemctl start apache2
              echo "Hello from Public Instance" > /var/www/html/index.html
              EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "public-web-instance"
    }
  }
}

# -----------------------
# ALB + ASG for Public Instances
# -----------------------
resource "aws_lb" "public_alb" {
  name               = "public-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = [aws_subnet.public_1a.id, aws_subnet.public_1b.id]
}

resource "aws_lb_target_group" "public_tg" {
  name     = "public-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

resource "aws_lb_listener" "public_http" {
  load_balancer_arn = aws_lb.public_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.public_tg.arn
  }
}

resource "aws_autoscaling_group" "public_web_asg" {
  name                = "public-web-asg"
  min_size            = 2
  max_size            = 4
  desired_capacity    = 2
  vpc_zone_identifier = [aws_subnet.public_1a.id, aws_subnet.public_1b.id]

  target_group_arns = [aws_lb_target_group.public_tg.arn]

  launch_template {
    id      = aws_launch_template.public_web_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "public-web-instance"
    propagate_at_launch = true
  }
}

# -----------------------
# Launch Template for Private Instances
# -----------------------
resource "aws_launch_template" "private_web_lt" {
  name_prefix   = "private-web-"
  image_id      = "ami-020cba7c55df1f615"
  instance_type = "t2.micro"

  vpc_security_group_ids = [aws_security_group.web_sg.id]

  user_data = base64encode(<<-EOF
              #!/bin/bash
              apt update -y
              apt install -y apache2
              systemctl start apache2
              echo "Hello from Private Instance" > /var/www/html/index.html
              EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "private-web-instance"
    }
  }
}

# -----------------------
# ALB + ASG for Private Instances
# -----------------------
resource "aws_lb" "app_alb" {
  name               = "app-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = [aws_subnet.public_1a.id, aws_subnet.public_1b.id]
}

resource "aws_lb_target_group" "app_tg" {
  name     = "app-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

resource "aws_lb_listener" "app_http" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

resource "aws_autoscaling_group" "private_web_asg" {
  name                = "private-web-asg"
  min_size            = 2
  max_size            = 4
  desired_capacity    = 2
  vpc_zone_identifier = [aws_subnet.private_1a.id, aws_subnet.private_1b.id]

  target_group_arns = [aws_lb_target_group.app_tg.arn]

  launch_template {
    id      = aws_launch_template.private_web_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "private-web-instance"
    propagate_at_launch = true
  }
}

# -----------------------
# RDS Subnet Group
# -----------------------
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds-subnet-group"
  subnet_ids = [aws_subnet.private_3a.id, aws_subnet.private_3b.id]

  tags = {
    Name = "rds-subnet-group"
  }
}

# -----------------------
# RDS Instance
# -----------------------
resource "aws_db_instance" "mydb" {
  identifier              = "mydb-instance"
  allocated_storage       = 20
  engine                  = "mysql"
  engine_version          = "8.0"
  instance_class          = "db.t3.micro"
  username                = "admin"
  password                = "MySecurePass123!"
  db_name                 = "mydb"
  db_subnet_group_name    = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids  = [aws_security_group.web_sg.id]
  skip_final_snapshot     = true
  multi_az                = false
  publicly_accessible     = true

  tags = {
    Name = "my-rds-instance"
  }
}
# -----------------------
# VPC
# -----------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "main-vpc"
  }
}

# -----------------------
# Subnets
# -----------------------
resource "aws_subnet" "public_1a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-1a"
  }
}

resource "aws_subnet" "public_1b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-1b"
  }
}

resource "aws_subnet" "private_1a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "private-1a"
  }
}

resource "aws_subnet" "private_1b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "private-1b"
  }
}

resource "aws_subnet" "private_3a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.5.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "private-3a"
  }
}

resource "aws_subnet" "private_3b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.6.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "private-3b"
  }
}

# -----------------------
# Internet Gateway
# -----------------------
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-igw"
  }
}

# -----------------------
# NAT Gateway
# -----------------------
resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_1a.id

  tags = {
    Name = "nat-gateway"
  }
}

# -----------------------
# Route Tables
# -----------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-rt"
  }
}

resource "aws_route_table_association" "public_1a" {
  subnet_id      = aws_subnet.public_1a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_1b" {
  subnet_id      = aws_subnet.public_1b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "private-rt"
  }
}

resource "aws_route_table_association" "private_1a" {
  subnet_id      = aws_subnet.private_1a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_1b" {
  subnet_id      = aws_subnet.private_1b.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_3a" {
  subnet_id      = aws_subnet.private_3a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_3b" {
  subnet_id      = aws_subnet.private_3b.id
  route_table_id = aws_route_table.private.id
}

# -----------------------
# Security Group
# -----------------------
resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.main.id
  name   = "web-sg"

  # HTTP for Web Servers
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH for Admin
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # MySQL for RDS
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    # Option 1: allow all (not secure in prod)
    # cidr_blocks = ["0.0.0.0/0"]

    # Option 2 (recommended): allow only within VPC
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "web-sg"
  }
}

# -----------------------
# Launch Template for Public Instances
# -----------------------
resource "aws_launch_template" "public_web_lt" {
  name_prefix   = "public-web-"
  image_id      = "ami-020cba7c55df1f615"
  instance_type = "t2.micro"

  vpc_security_group_ids = [aws_security_group.web_sg.id]

  user_data = base64encode(<<-EOF
              #!/bin/bash
              apt update -y
              apt install -y apache2
              systemctl start apache2
              echo "Hello from Public Instance" > /var/www/html/index.html
              EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "public-web-instance"
    }
  }
}

# -----------------------
# ALB + ASG for Public Instances
# -----------------------
resource "aws_lb" "public_alb" {
  name               = "public-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = [aws_subnet.public_1a.id, aws_subnet.public_1b.id]
}

resource "aws_lb_target_group" "public_tg" {
  name     = "public-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

resource "aws_lb_listener" "public_http" {
  load_balancer_arn = aws_lb.public_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.public_tg.arn
  }
}

resource "aws_autoscaling_group" "public_web_asg" {
  name                = "public-web-asg"
  min_size            = 2
  max_size            = 4
  desired_capacity    = 2
  vpc_zone_identifier = [aws_subnet.public_1a.id, aws_subnet.public_1b.id]

  target_group_arns = [aws_lb_target_group.public_tg.arn]

  launch_template {
    id      = aws_launch_template.public_web_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "public-web-instance"
    propagate_at_launch = true
  }
}

# -----------------------
# Launch Template for Private Instances
# -----------------------
resource "aws_launch_template" "private_web_lt" {
  name_prefix   = "private-web-"
  image_id      = "ami-020cba7c55df1f615"
  instance_type = "t2.micro"

  vpc_security_group_ids = [aws_security_group.web_sg.id]

  user_data = base64encode(<<-EOF
              #!/bin/bash
              apt update -y
              apt install -y apache2
              systemctl start apache2
              echo "Hello from Private Instance" > /var/www/html/index.html
              EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "private-web-instance"
    }
  }
}

# -----------------------
# ALB + ASG for Private Instances
# -----------------------
resource "aws_lb" "app_alb" {
  name               = "app-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = [aws_subnet.public_1a.id, aws_subnet.public_1b.id]
}

resource "aws_lb_target_group" "app_tg" {
  name     = "app-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

resource "aws_lb_listener" "app_http" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

resource "aws_autoscaling_group" "private_web_asg" {
  name                = "private-web-asg"
  min_size            = 2
  max_size            = 4
  desired_capacity    = 2
  vpc_zone_identifier = [aws_subnet.private_1a.id, aws_subnet.private_1b.id]

  target_group_arns = [aws_lb_target_group.app_tg.arn]

  launch_template {
    id      = aws_launch_template.private_web_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "private-web-instance"
    propagate_at_launch = true
  }
}

# -----------------------
# RDS Subnet Group
# -----------------------
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds-subnet-group"
  subnet_ids = [aws_subnet.private_3a.id, aws_subnet.private_3b.id]

  tags = {
    Name = "rds-subnet-group"
  }
}

# -----------------------
# RDS Instance
# -----------------------
resource "aws_db_instance" "mydb" {
  identifier              = "mydb-instance"
  allocated_storage       = 20
  engine                  = "mysql"
  engine_version          = "8.0"
  instance_class          = "db.t3.micro"
  username                = "admin"
  password                = "MySecurePass123!"
  db_name                 = "mydb"
  db_subnet_group_name    = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids  = [aws_security_group.web_sg.id]
  skip_final_snapshot     = true
  multi_az                = false
  publicly_accessible     = true

  tags = {
    Name = "my-rds-instance"
  }
}
# -----------------------
# VPC
# -----------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "main-vpc"
  }
}

# -----------------------
# Subnets
# -----------------------
resource "aws_subnet" "public_1a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-1a"
  }
}

resource "aws_subnet" "public_1b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-1b"
  }
}

resource "aws_subnet" "private_1a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "private-1a"
  }
}

resource "aws_subnet" "private_1b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "private-1b"
  }
}

resource "aws_subnet" "private_3a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.5.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "private-3a"
  }
}

resource "aws_subnet" "private_3b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.6.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "private-3b"
  }
}

# -----------------------
# Internet Gateway
# -----------------------
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-igw"
  }
}

# -----------------------
# NAT Gateway
# -----------------------
resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_1a.id

  tags = {
    Name = "nat-gateway"
  }
}

# -----------------------
# Route Tables
# -----------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-rt"
  }
}

resource "aws_route_table_association" "public_1a" {
  subnet_id      = aws_subnet.public_1a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_1b" {
  subnet_id      = aws_subnet.public_1b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "private-rt"
  }
}

resource "aws_route_table_association" "private_1a" {
  subnet_id      = aws_subnet.private_1a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_1b" {
  subnet_id      = aws_subnet.private_1b.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_3a" {
  subnet_id      = aws_subnet.private_3a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_3b" {
  subnet_id      = aws_subnet.private_3b.id
  route_table_id = aws_route_table.private.id
}

# -----------------------
# Security Group
# -----------------------
resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.main.id
  name   = "web-sg"

  # HTTP for Web Servers
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH for Admin
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # MySQL for RDS
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    # Option 1: allow all (not secure in prod)
    # cidr_blocks = ["0.0.0.0/0"]

    # Option 2 (recommended): allow only within VPC
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "web-sg"
  }
}

# -----------------------
# Launch Template for Public Instances
# -----------------------
resource "aws_launch_template" "public_web_lt" {
  name_prefix   = "public-web-"
  image_id      = "ami-020cba7c55df1f615"
  instance_type = "t2.micro"

  vpc_security_group_ids = [aws_security_group.web_sg.id]

  user_data = base64encode(<<-EOF
              #!/bin/bash
              apt update -y
              apt install -y apache2
              systemctl start apache2
              echo "Hello from Public Instance" > /var/www/html/index.html
              EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "public-web-instance"
    }
  }
}

# -----------------------
# ALB + ASG for Public Instances
# -----------------------
resource "aws_lb" "public_alb" {
  name               = "public-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = [aws_subnet.public_1a.id, aws_subnet.public_1b.id]
}

resource "aws_lb_target_group" "public_tg" {
  name     = "public-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

resource "aws_lb_listener" "public_http" {
  load_balancer_arn = aws_lb.public_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.public_tg.arn
  }
}

resource "aws_autoscaling_group" "public_web_asg" {
  name                = "public-web-asg"
  min_size            = 2
  max_size            = 4
  desired_capacity    = 2
  vpc_zone_identifier = [aws_subnet.public_1a.id, aws_subnet.public_1b.id]

  target_group_arns = [aws_lb_target_group.public_tg.arn]

  launch_template {
    id      = aws_launch_template.public_web_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "public-web-instance"
    propagate_at_launch = true
  }
}

# -----------------------
# Launch Template for Private Instances
# -----------------------
resource "aws_launch_template" "private_web_lt" {
  name_prefix   = "private-web-"
  image_id      = "ami-020cba7c55df1f615"
  instance_type = "t2.micro"

  vpc_security_group_ids = [aws_security_group.web_sg.id]

  user_data = base64encode(<<-EOF
              #!/bin/bash
              apt update -y
              apt install -y apache2
              systemctl start apache2
              echo "Hello from Private Instance" > /var/www/html/index.html
              EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "private-web-instance"
    }
  }
}

# -----------------------
# ALB + ASG for Private Instances
# -----------------------
resource "aws_lb" "app_alb" {
  name               = "app-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = [aws_subnet.public_1a.id, aws_subnet.public_1b.id]
}

resource "aws_lb_target_group" "app_tg" {
  name     = "app-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

resource "aws_lb_listener" "app_http" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

resource "aws_autoscaling_group" "private_web_asg" {
  name                = "private-web-asg"
  min_size            = 2
  max_size            = 4
  desired_capacity    = 2
  vpc_zone_identifier = [aws_subnet.private_1a.id, aws_subnet.private_1b.id]

  target_group_arns = [aws_lb_target_group.app_tg.arn]

  launch_template {
    id      = aws_launch_template.private_web_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "private-web-instance"
    propagate_at_launch = true
  }
}

# -----------------------
# RDS Subnet Group
# -----------------------
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds-subnet-group"
  subnet_ids = [aws_subnet.private_3a.id, aws_subnet.private_3b.id]

  tags = {
    Name = "rds-subnet-group"
  }
}

# -----------------------
# RDS Instance
# -----------------------
resource "aws_db_instance" "mydb" {
  identifier              = "mydb-instance"
  allocated_storage       = 20
  engine                  = "mysql"
  engine_version          = "8.0"
  instance_class          = "db.t3.micro"
  username                = "admin"
  password                = "MySecurePass123!"
  db_name                 = "mydb"
  db_subnet_group_name    = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids  = [aws_security_group.web_sg.id]
  skip_final_snapshot     = true
  multi_az                = false
  publicly_accessible     = true

  tags = {
    Name = "my-rds-instance"
  }
}
