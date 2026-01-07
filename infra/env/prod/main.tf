resource "aws_vpc" "b14" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "b14-vpc-terraform"
  }
}

resource "aws_subnet" "public_subnet_1" {
  vpc_id     = aws_vpc.b14.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "ap-south-1a"

  tags = {
    Name = "public-subnet-1"
  }
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id     = aws_vpc.b14.id
  cidr_block = "10.0.2.0/24"
  tags= {
    Name = "public-subnet-2"
  }
}
resource "aws_subnet" "private_subnet_1" {
  vpc_id     = aws_vpc.b14.id
  cidr_block = "10.0.3.0/24"
  availability_zone = "ap-south-1b"

  tags = {
    Name = "private_subnet_1"
  }
}

resource "aws_subnet" "private_subnet_2" {
  vpc_id     = aws_vpc.b14.id
  cidr_block = "10.0.4.0/24"
  tags= {
    Name = "private_subnet_2"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.b14.id

  tags = {
    Name = "b14-igw"
  }
}

resource "aws_eip" "nat-eip" {
    domain = "vpc"

    tags = {
        Name = "b14-nat-eip"
    }
}
resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.nat-eip.id
  subnet_id     = aws_subnet.public_subnet_1.id

  tags = {
    Name = "b14_nat_gateway"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.b14.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
    
  tags = {
        Name = "public_route_table"
    }
}
resource "aws_route_table_association" "public_RT_association_1" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_route_table.id
}
resource "aws_route_table_association" "public-RT-association-2" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.b14.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway.id
  }
  tags = {
        Name = "private-route-table"
    }
}
resource "aws_route_table_association" "private_RT_association_1" {
  subnet_id      = aws_subnet.private_subnet_1.id
  route_table_id = aws_route_table.private_route_table.id
}
resource "aws_route_table_association" "private_RT_association_2" {
  subnet_id      = aws_subnet.private_subnet_2.id
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_security_group" "web-sg" {
  name        = "allow_tls"
  description = "Allow TLS inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.b14.id

  tags = {
    Name = "web-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_http_ipv4" {
  security_group_id = aws_security_group.web-sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "allow_ssh_ipv4" {
  security_group_id = aws_security_group.web-sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.web-sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}  

resource "aws_instance" "bastion" {
  ami                         = "ami-02b8269d5e85954ef" 
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public_subnet_1.id
  vpc_security_group_ids      = [aws_security_group.web-sg.id]
  associate_public_ip_address = true

  tags = {
    Name = "bastation-server"
  }
}

resource "aws_iam_role" "eks_cluster_role" {
  name = "b14-eks-cluster-role"
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
resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSClusterPolicy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_cluster" "b14-eks-cluster" {
  name     = "b14-eks-cluster"
  role_arn = aws_iam_role.eks_cluster_role.arn
  version = "1.32"

  vpc_config {
    subnet_ids = [
      aws_subnet.private_subnet_1.id,
      aws_subnet.private_subnet_2.id
    ]
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_AmazonEKSClusterPolicy,
    
  ]
}

data "aws_eks_cluster" "b14-eks-cluster" {
  name = aws_eks_cluster.b14-eks-cluster.name
}
data "aws_eks_cluster_auth" "b14-eks-cluster" {
  name = aws_eks_cluster.b14-eks-cluster.name
}

resource "aws_eks_addon"  "vpc_cni" {
    cluster_name = aws_eks_cluster.b14-eks-cluster.name
    addon_name   = "vpc-cni"
}  
resource "aws_eks_addon"  "coredns" {
    cluster_name = aws_eks_cluster.b14-eks-cluster.name
    addon_name   = "coredns"
}
resource "aws_eks_addon"  "kube_proxy" {
    cluster_name = aws_eks_cluster.b14-eks-cluster.name
    addon_name   = "kube-proxy"
}  

resource "aws_iam_role" "eks_node_role" {
  name = "b14-eks-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "node_policy_1" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_policy_2" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy" 
}

resource "aws_iam_role_policy_attachment" "node_policy_3" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_eks_node_group" "b14-eks-node-group" {
  cluster_name    = aws_eks_cluster.b14-eks-cluster.name
  node_group_name = "b14-eks-node-group"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = [
    aws_subnet.private_subnet_1.id,
    aws_subnet.private_subnet_2.id]
  scaling_config {
    desired_size = 2
    max_size     = 2
    min_size     = 1
  }
  instance_types=["c7i-flex.large"]
}
