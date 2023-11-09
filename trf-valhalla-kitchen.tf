provider "aws" {
  region = "us-east-1"
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

  public_subnet_tags = {
    "kubernetes.io/cluster/my_eks" = "shared"
    "kubernetes.io/role/internal-elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/my_eks" = "shared"
    "kubernetes.io/role/internal-elb" = 1
  }
}

resource "aws_iam_role" "role" {
  name = "EksValhallaKitchen"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "17.1.0"

  cluster_name    = "cluster-valhalla-kitchen"
  cluster_version = "1.28"

  manage_cluster_iam_resources= true
  cluster_iam_role_name = aws_iam_role.role.name

  subnets         = module.vpc.public_subnets
  vpc_id          = module.vpc.vpc_id

  depends_on = [module.vpc]
  
}

resource "aws_iam_role_policy_attachment" "policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.role.name
  depends_on = [aws_iam_role.role]
}

resource "aws_eks_node_group" "node_group" {
  cluster_name    = "cluster-valhalla-kitchen"
  node_group_name = "valhalla_node_group"
  node_role_arn   = aws_iam_role.role.arn
  subnet_ids      = module.vpc.public_subnets

  scaling_config {
    desired_size = 1
    max_size     = 1
    min_size     = 1
  }

  depends_on = [aws_iam_role_policy_attachment.policy, module.eks]
}
