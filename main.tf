provider "aws" {
  region = "us-east-1"
   access_key = var.aws_provider.access_key
  secret_key = var.aws_provider.secret_key
}

# Variáveis
variable "aws_provider" {
  description = "AWS Access Key ID and Secret Key"
}



# 1. Criar a VPC
resource "aws_vpc" "trackdog-vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "Trackdog VPC"
  }
}

# 2. Criar os Gateways
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.trackdog-vpc.id

}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat-eip.id
  subnet_id     = aws_subnet.trackdog-public-subnet.id
  tags = {
    Name = "gw NAT"
  }
  depends_on = [aws_internet_gateway.gw, aws_eip.nat-eip]
}

resource "aws_eip" "nat-eip"{
  depends_on = [aws_internet_gateway.gw]

}

# 3. Criar custom Route Table
resource "aws_route_table" "trackdog-public-rt" {
  vpc_id = aws_vpc.trackdog-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "trackdog-pub-rt"
  }
}

resource "aws_route_table" "trackdog-private-rt" {
  vpc_id = aws_vpc.trackdog-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "trackdog-private-rt"
  }
}

# 4. Criar subnet
resource "aws_subnet" "trackdog-public-subnet" {
  vpc_id     = aws_vpc.trackdog-vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "Trackdog Public Subnet"
  }
}

resource "aws_subnet" "trackdog-private-subnet" {
  vpc_id     = aws_vpc.trackdog-vpc.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "Trackdog private Subnet"
  }
}

# 5. Associar a subnet com a route table
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.trackdog-public-subnet.id
  route_table_id = aws_route_table.trackdog-public-rt.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.trackdog-private-subnet.id
  route_table_id = aws_route_table.trackdog-private-rt.id
}

# 6. Criar um Security Group para permitir as portas 22, 80 e 443
resource "aws_security_group" "allow-web" {
  name        = "allow-web-traffic"
  description = "Allow web inbound traffic"
  vpc_id      = aws_vpc.trackdog-vpc.id

  ingress {
    description      = "HTTPS"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    
  }
    ingress {
    description      = "HTTP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    
  }
    ingress {
    description      = "SSH"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_web"
  }
}

resource "aws_security_group" "allow-ssh" {
  name        = "allow-ssh-only"
  description = "Allow ssh traffic"
  vpc_id      = aws_vpc.trackdog-vpc.id
    
    ingress {
    description      = "SSH"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    
  }

    ingress {
    description      = "HTTPS"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_ssh"
  }
}



# 7. Criar uma interface de Rede com um ip na subnet que foi criada no passo 4
resource "aws_network_interface" "webserver-nic" {
  subnet_id       = aws_subnet.trackdog-public-subnet.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.allow-web.id]

}

resource "aws_network_interface" "private-nic" {
  subnet_id       = aws_subnet.trackdog-private-subnet.id
  private_ips     = ["10.0.2.15"]
  security_groups = [aws_security_group.allow-ssh.id]

}



# 8. Definir um IP elastico para a interface de rede criada no passo 7
resource "aws_eip" "one" {
  vpc                       = true
  network_interface         = aws_network_interface.webserver-nic.id
  associate_with_private_ip = "10.0.1.50"
  depends_on = [aws_internet_gateway.gw]
}


# 10. Criar um Servidor Ubuntu e instalar/habilitar o apache 2
resource "aws_instance" "web-server-instance"{
  ami = "ami-08d4ac5b634553e16"
  instance_type = "t2.micro"
  availability_zone = "us-east-1a"
  key_name = "cloud-key"
  
  network_interface {
    device_index = 0
    network_interface_id = aws_network_interface.webserver-nic.id
  }
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

resource "aws_instance" "private-instance"{
  ami = "ami-08d4ac5b634553e16"
  instance_type = "t2.micro"
  availability_zone = "us-east-1a"
  key_name = "cloud-key"
  
  network_interface {
    device_index = 0
    network_interface_id = aws_network_interface.private-nic.id
  }
    
    tags = {
      Name = "private-server"
    }
}


   

