variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "availability_zones" {
  type    = list(string)
  default = ["ap-south-1a", "ap-south-1b"]
}

variable "cluster_name" {
  type    = string
  default = "three-tier-eks"
}

# Must be a string ("1.35"), not a number, or 1.30 would become 1.3.
# Check the versions EKS currently supports before changing this.
variable "cluster_version" {
  type    = string
  default = "1.35"
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 3
}

# The Cluster Autoscaler minor version should match the Kubernetes version.
variable "autoscaler_image_tag" {
  type    = string
  default = "v1.35.1"
}
