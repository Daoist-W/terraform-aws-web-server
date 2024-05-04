terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
  access_key = "dummy"
  secret_key = "dummy"
}

# create a VPC
resource "aws_vpc" "dev_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
  	Name = "dev_vpc"
  }
}

# create Internet Gateway

resource "aws_internet_gateway" "dev_gw" {
  vpc_id = aws_vpc.dev_vpc.id
  tags = {
    Name = "dev-gateway"
  }
}

# create custom route table 

resource "aws_route_table" "dev_route_table" {
  vpc_id = aws_vpc.dev_vpc.id

# This is a common configuration for a public subnet, 
# where you want to route all internet-bound traffic through 
# the internet gateway, allowing resources in that subnet to access the internet.
  route {
    cidr_block = "0.0.0.0/0" # direct all internet bound traffic on this vpc to internet gateway
    gateway_id = aws_internet_gateway.dev_gw.id
  }

# This is a common configuration for a private subnet that needs to 
# access the internet for outbound-only IPv6 traffic, while still
# maintaining a secure, inbound-only IPv4 connection.
  route {
    ipv6_cidr_block        = "::/0" # apply to all IPV6 traffic
    gateway_id =  aws_internet_gateway.dev_gw.id
  }

  tags = {
    Name = "dev_route_table"
  }
}

# create a subnet 


resource "aws_subnet" "dev_subnet_1" {
  vpc_id     = aws_vpc.dev_vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  
  tags = {
    Name = "dev-subnet-1"
  }
}

# associate subnet with route table 
resource "aws_route_table_association" "dev_rt_assoc" {
  subnet_id      = aws_subnet.dev_subnet_1.id
  route_table_id = aws_route_table.dev_route_table.id
}


# create security group to allow ingress and egress to port 22, 80, 443

resource "aws_security_group" "dev_allow_web_traffic" {
  name        = "allow_web_traffic"
  description = "Allow web traffic"
  vpc_id      = aws_vpc.dev_vpc.id

  tags = {
    Name = "dev_allow_web_traffic"
  }
}

resource "aws_vpc_security_group_ingress_rule" "dev_allow_web_ipv4" {
  security_group_id = aws_security_group.dev_allow_web_traffic.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

resource "aws_vpc_security_group_ingress_rule" "dev_allow_http_ipv4" {
  security_group_id = aws_security_group.dev_allow_web_traffic.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "dev_allow_ssh_ipv4" {
  security_group_id = aws_security_group.dev_allow_web_traffic.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

resource "aws_vpc_security_group_ingress_rule" "dev_allow_web_ipv6" {
  security_group_id = aws_security_group.dev_allow_web_traffic.id
  cidr_ipv6         = "::/0"
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

resource "aws_vpc_security_group_ingress_rule" "dev_allow_http_ipv6" {
  security_group_id = aws_security_group.dev_allow_web_traffic.id
  cidr_ipv6         = "::/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "dev_allow_ssh_ipv6" {
  security_group_id = aws_security_group.dev_allow_web_traffic.id
  cidr_ipv6         = "::/0"
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

resource "aws_vpc_security_group_egress_rule" "dev_allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.dev_allow_web_traffic.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

resource "aws_vpc_security_group_egress_rule" "dev-allow_all_traffic_ipv6" {
  security_group_id = aws_security_group.dev_allow_web_traffic.id
  cidr_ipv6         = "::/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

# create network interface with a private ip within range of subnet created earlier

resource "aws_network_interface" "dev_network_interface" {
  subnet_id       = aws_subnet.dev_subnet_1.id
  # need to be within the subnets cidr range and available (AWS reserves some addresses)
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.dev_allow_web_traffic.id]

}

# assign an elastic ip (public ip) address to the network interface 

resource "aws_eip" "dev_eip_1" {
  domain                    = "vpc"
  network_interface         = aws_network_interface.dev_network_interface.id
  associate_with_private_ip = "10.0.1.50"
  depends_on = [aws_internet_gateway.dev_gw]
}


# create and configure ubunter based web server, install and enable apache2 with dummy web page
resource "aws_instance" "web-server-instance" {
	ami           	  = "ami-04b70fa74e45c3917"
	instance_type 	  = "t3.micro"
    availability_zone = "us-east-1a"
    key_name = "terraform-demo"
    network_interface {
    	network_interface_id = aws_network_interface.dev_network_interface.id
    	device_index         = 0
  	}
    
    # here we can get apache to run some user commands on initialisation
    user_data = <<-EOF
    			#!/bin/bash
                sudo apt update -y
                sudo apt install apache2 -y
                sudo systemctl start apache2
                sudo bash -c 'echo your very first web server > /var/www/html/index.html'
                EOF
 	tags = {
	  Name = "web-server"
	}               
    
}
