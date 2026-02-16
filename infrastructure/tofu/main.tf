provider "aws" {
  region = var.aws_region
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "ec2_sg" {
  name        = "grocery-ec2-sg"
  description = "SSH + App access"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  ingress {
    description = "App"
    from_port   = var.app_port
    to_port     = var.app_port
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

resource "aws_security_group" "rds_sg" {
  name        = "grocery-rds-sg"
  description = "Postgres access from EC2 only"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "Postgres from EC2 SG"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_subnet_group" "rds_subnets" {
  name       = "grocery-rds-subnets"
  subnet_ids = data.aws_subnets.default.ids
}

resource "aws_db_instance" "postgres" {
  identifier             = "grocerymate-db"
  engine                 = "postgres"
  engine_version         = "17"
  instance_class         = var.rds_instance_class
  allocated_storage      = 20
  storage_type           = "gp3"

  db_name                = var.db_name
  username               = var.db_user
  password               = var.db_password

  publicly_accessible    = false
  skip_final_snapshot    = true
  deletion_protection    = false

  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.rds_subnets.name
}

resource "aws_instance" "ec2" {
  ami                    = var.ec2_ami_id
  instance_type          = var.ec2_instance_type
  key_name               = var.ec2_keypair_name
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  tags = {
    Name = "grocery-ec2"
  }
}

