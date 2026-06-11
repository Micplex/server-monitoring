variable "aws_region"     { default = "us-east-1" }
variable "ami_id"         { default = "ami-0c7217cdde317cfec" }
variable "instance_type"  { default = "t3.small" }
variable "ssh_key_name"   { type = string }
variable "environment"    { default = "production" }
