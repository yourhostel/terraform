variable "region" {
  type        = string
  description = "AWS Region"
  default     = "us-east-1"
}

variable "name" {
  type        = string
  description = "Project name"
  default     = "danit_test"
}
variable "environment" {
  type        = string
  description = "Project environment"
  default     = "dev"
}
variable "disk_size" {
  type        = string
  description = "Disk size"
  default     = "20"
}
variable "instance_type" {
  type        = string
  description = "Instance type"
  default     = "t2.micro"
}
