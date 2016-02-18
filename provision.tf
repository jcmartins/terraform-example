provider "aws" {
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  region = "sa-east-1"
}

resource "aws_key_pair" "ttg-dev-root-key" {
  key_name = "my-key-name"
  public_key = "insert your public key here"
}

//Create a VPC
resource "aws_vpc" "terraform-vpc-ttg-dev" {
  cidr_block = "172.16.0.0/16"
  tags {
    Name = "terraform-vpc"
  }
}

//Create a Internet Gateway
resource "aws_internet_gateway" "terraform-igw-ttg-dev" {
    vpc_id = "${aws_vpc.terraform-vpc-ttg-dev.id}"
    tags {
        Name = "terraform-ttg-gw"
    }
}

//Create two subnets(public and private)
resource "aws_subnet" "terraform-subnet-ttg-pub" {
    vpc_id = "${aws_vpc.terraform-vpc-ttg-dev.id}"
    availability_zone = "sa-east-1a"
    cidr_block = "172.16.1.0/24"
    map_public_ip_on_launch = true
    tags {
        Name = "terraform-subnet-ttg-pub"
    }
}

resource "aws_subnet" "terraform-subnet-ttg-pvt" {
    vpc_id = "${aws_vpc.terraform-vpc-ttg-dev.id}"
    availability_zone = "sa-east-1a"
    cidr_block = "172.16.5.0/24"
    tags {
        Name = "terraform-subnet-ttg-pvt"
    }
}

//Add a default route to Internet
resource "aws_route_table" "terraform-route-table-ttg-dev" {
    vpc_id = "${aws_vpc.terraform-vpc-ttg-dev.id}"
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = "${aws_internet_gateway.terraform-igw-ttg-dev.id}"
    }
    tags {
        Name = "Terraform route table ttg-dev"
    }
}

// The Route Table Association binds our public subnet and route together.
resource "aws_route_table_association" "terraform-route-table-ttg-dev" {
  subnet_id = "${aws_subnet.terraform-subnet-ttg-pub.id}"
  route_table_id = "${aws_route_table.terraform-route-table-ttg-dev.id}"
}

//Create a ELB and association subnet and security groups
resource "aws_elb" "terraform-elb-ttg-dev" {
    name = "terraform-ttg-elb"
    subnets = [ "${aws_subnet.terraform-subnet-ttg-pub.id}" ]
    security_groups = [ "${aws_security_group.terraform-sg-ttg-dev.id}" ]
    listener {
        instance_port = 80
        instance_protocol = "http"
        lb_port = 80
        lb_protocol = "http"
    }
    health_check {
        healthy_threshold = 3
        unhealthy_threshold = 3
        interval = 15
        timeout = 5
        target = "HTTP:80/"
    }
    tags {
        Name = "terraform-ttg-elb"
    }
}

//Create a Security Group with full permissions
resource "aws_security_group" "terraform-sg-ttg-dev" {
    name = "Aws-Terraform-ttg-Dev"
    description = "Terraform ttg Dev SG"
    vpc_id = "${aws_vpc.terraform-vpc-ttg-dev.id}"
    ingress {
      protocol = "-1"
        from_port = 0
        to_port = 0
        cidr_blocks = [ "0.0.0.0/0" ]
    }
    egress {
      protocol = "-1"
        from_port = 0
        to_port = 0
        cidr_blocks = [ "0.0.0.0/0" ]
    }
}

//Create a launch configuration
resource "aws_launch_configuration" "ttg-dev" {
  name_prefix = "terraform-ttggroup-"
  image_id = "ami-25c52345"
  instance_type = "t2.small"
  key_name      = "${aws_key_pair.ttg-dev-root-key.key_name}"
  user_data = "#!/bin/bash\napt-get update && apt-get -y --no-install-recommends install nginx && service nginx restart"
  security_groups = [ "${aws_security_group.terraform-sg-ttg-dev.id}" ]
  lifecycle {
      create_before_destroy = true  # create new LC before destroy the old one (if the config changes)
  }
}

//Create a Autoscaling Group and associate to a vpc and load balance
resource "aws_autoscaling_group" "ttg-dev-asg" {
    name = "autoscaling-terraform-ttg-dev"
    launch_configuration = "${aws_launch_configuration.ttg-dev.name}"
    vpc_zone_identifier = [ "${aws_subnet.terraform-subnet-ttg-pub.id}" ]
    load_balancers = [ "${aws_elb.terraform-elb-ttg-dev.name}" ]
    min_size = 1
    max_size = 3
    desired_capacity = 1
    lifecycle {
        create_before_destroy = true  # create new ASG before destroy the old one (if the config changes)
    }
}
