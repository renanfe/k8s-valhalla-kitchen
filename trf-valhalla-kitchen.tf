provider "aws" {
  region = "us-east-1"
  profile = "default"
}

data "aws_eks_cluster" "default" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "default" {
  name = module.eks.cluster_id
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.default.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.default.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.default.token
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.2"

  name = "vpc-valhalla-kitchen"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true
  enable_vpn_gateway = true
  enable_dns_hostnames = true
  public_subnet_tags = {
    "kubernetes.io/cluster/my_eks" = "shared"
    "kubernetes.io/role/internal-elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/my_eks" = "shared"
    "kubernetes.io/role/internal-elb" = 1
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "18.31.2"

  cluster_name    = "cluster-valhalla-kitchen"
  cluster_version = "1.28"

  subnets         = module.vpc.public_subnets
  vpc_id          = module.vpc.vpc_id
  
}

resource "aws_eks_node_group" "node_group" {
  cluster_name    = cluster-valhalla-kitchen
  node_group_name = "group_cluster_valhalla_kitchen"
  node_role_arn   = aws_iam_role.ec2_iam_role.arn
  subnet_ids      = module.vpc.public_subnets
  instance_types = ["t2.micro"]

  scaling_config {
    desired_size = 1
    max_size     = 2
    min_size     = 1
  }

  update_config {
    max_unavailable = 1
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  # Otherwise, EKS will not be able to properly delete EC2 Instances and Elastic Network Interfaces.
  depends_on = [
    aws_iam_role_policy_attachment.example-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.example-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.example-AmazonEC2ContainerRegistryReadOnly,
  ]
}
