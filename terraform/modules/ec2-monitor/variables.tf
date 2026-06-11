variable "ami_id"          {}
variable "instance_type"   { default = "t3.micro" }
variable "ssh_key_name"    {}
variable "tags"            { type = map(string); default = {} }
