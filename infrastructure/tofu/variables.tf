variable "allowed_ssh_cidr" {
  type        = string
  description = "2.203.27.68/32"
}


variable "aws_region" {
  type    = string
  default = "eu-central-1"
}


variable "app_port" {
  type    = number
  default = 5000
}

variable "ec2_ami_id" {
  type        = string
  description = "Ubuntu AMI in eu-central-1"
}

variable "ec2_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "ec2_keypair_name" {
  type        = string
  description = "Name des vorhandenen EC2 Keypairs"
}

variable "rds_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "db_name" {
  type    = string
  default = "grocerymate_db"
}

variable "db_user" {
  type    = string
  default = "grocery_user"
}

variable "db_password" {
  type        = string
  sensitive   = true
  description = "DB Passwort (nicht committen!)"
}

variable "repo_url" {
  type        = string
  description = "Git Repository URL fuer Deployment"
  default     = "https://github.com/mhtechnik/AWS_grocery.git"
}

variable "repo_branch" {
  type        = string
  description = "Git Branch fuer Deployment"
  default     = "version2"
}
