terraform {
  backend "s3" {
    bucket = "nehru-demo010-tfstate-bucket"
    key    = "three-tier-eks/terraform.tfstate"
    region = "ap-south-1"
  }
}


