terraform {
  required_version = ">= 1.4.4"
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 3.30.0"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}

provider "aws" {
  region = var.region
}

provider "random" {}

locals {
  tags = {
    Name = var.name
    Project = var.name
    Environment = var.environment
  }
}

data "aws_ami" "ubuntu" {
  owners = ["099720109477"] # Canonical
  most_recent = true
  filter {
    name = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
}


resource "random_password" "mysql" {
  length = 16
  special = false
}

resource "random_password" "sftp" {
  length = 16
  special = false
}
resource "aws_vpc" "default" {
  cidr_block = "10.0.0.0/16"  # Change this CIDR block if needed
}

resource "aws_internet_gateway" "default" {
  vpc_id = aws_vpc.default.id
}

resource "aws_subnet" "default" {
  vpc_id     = aws_vpc.default.id
  cidr_block = "10.0.0.0/24"  # Change this CIDR block if needed
}

resource "aws_route_table" "default" {
  vpc_id = aws_vpc.default.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.default.id
  }
}

resource "aws_route_table_association" "default" {
  subnet_id      = aws_subnet.default.id
  route_table_id = aws_route_table.default.id
}

resource "aws_instance" "wordpress" {
  ami                         = data.aws_ami.ubuntu.id
  associate_public_ip_address = true
  disable_api_termination     = true
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.default.id
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  vpc_security_group_ids      = [aws_security_group.wordpress-sg.id]
  tags                        = local.tags
  volume_tags                 = local.tags
  credit_specification {
    cpu_credits = "standard"
  }
  root_block_device {
    volume_size = var.disk_size
    volume_type = "gp3"
  }
  user_data = <<-USERDATA
#!/bin/bash
# Install dependencies
apt-get update && apt-get install -y apache2 mariadb-server php libapache2-mod-php php-mysql php-gd

# Configure MySQL
mysql_secure_installation
mysql -u root -p -e "CREATE DATABASE wordpress;"
mysql -u root -p -e "CREATE USER 'wordpressuser'@'localhost' IDENTIFIED BY '<span class="math-inline">\{random\_password\.mysql\.result\}';"
mysql \-u root \-p \-e "GRANT ALL PRIVILEGES ON wordpress\.\* TO 'wordpressuser'@'localhost';"
\# Download and extract WordPress
cd /var/www/html
wget https\://wordpress\.org/latest\.tar\.gz
tar \-xzvf latest\.tar\.gz
chown \-R www\-data\:www\-data /var/www/html/wordpress
\# Configure Apache
<1\>cp /var/www/html/wordpress/wp\-config\-sample\.php /var/www/html/wordpress/wp\-config\.php
sed \-i "s/database\_name\_here/wordpress/" /var/www/html/wordpress/wp\-config\.php
sed \-i "s/username\_here/wordpressuser/"</1\> /var/www/html/wordpress/wp\-config\.php
sed \-i "s/password\_here/</span>{random_password.mysql.result}/" /var/www/html/wordpress/wp-config.php
a2enmod rewrite
service apache2 restart
USERDATA

  lifecycle {
    ignore_changes = [disable_api_termination]
  }
}

resource "aws_ssm_parameter" "name" {
  name = "/wordpress/${var.name}"
  description = "Credentials for ${var.name} WordPress instance with initial IP ${aws_instance.wordpress.public_ip}"
  type = "SecureString"
  tags = local.tags
  value = <<-CREDENTIALS
MYSQL_USERNAME=wordpressuser
MYSQL_PASSWORD=${random_password.mysql.result}
SFTP_USERNAME=sftpuser
SFTP_PASSWORD=${random_password.sftp.result}
CREDENTIALS
}


resource "aws_iam_role" "wordpress" {
  name = "wordpress"
  description = "Role for WordPress EC2 instances"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "wordpress-s3" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
  role       = aws_iam_role.wordpress.name
}

resource "aws_iam_role_policy_attachment" "wordpress-ssm" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMFullAccess"
  role       = aws_iam_role.wordpress.name
}
resource "aws_iam_instance_profile" "ec2_profile" {
  role = aws_iam_role.wordpress.name 
}

resource "aws_security_group" "wordpress-sg" {
  name        = "${var.name}-security-group"
  description = "${var.name} Security Group in Default VPC"
  vpc_id      = aws_vpc.default.id

  ingress {
    from_port = 80
    to_port   = 80
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Open to the world, you may want to restrict this based on your use case
  }

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Open to the world, you may want to restrict this based on your use case
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}