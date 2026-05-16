# --- Module: VPC
module "vpc" {
  source               = "../../modules/vpc" # Provide github url if the module is in a central git repo 
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  env                  = var.env
  tags                 = merge(var.tags, { Project = "learn-tf-modules" })
}

# --- Module: S3 (app storage)
module "s3" {
  source      = "../../modules/s3"
  bucket_name = var.bucket_name
  env         = var.env
  versioning  = true
  force_destroy = false
  tags = merge(var.tags, { Project = "learn-tf-modules" })
}

# --- Module: Compute (bastion + web)
module "ec2" {
  source               = "../../modules/ec2"
  ami_id               = var.ami_id
  instance_type        = var.instance_type
  bastion_key_name     = var.bastion_key_name
  public_subnet_ids    = module.vpc.public_subnet_ids
  private_subnet_ids   = module.vpc.private_subnet_ids
  bastion_sg_id        = module.vpc.bastion_sg_id
  web_sg_id            = module.vpc.web_sg_id
  env                  = var.env
  tags                 = merge(var.tags, { Project = "learn-tf-modules" })
}