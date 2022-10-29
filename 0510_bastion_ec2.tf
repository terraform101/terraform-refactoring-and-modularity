# 1. bastion host용도의 ec2 생성
# 2. 인터넷 연동이 가능하도록 elastic ip 연동
# 3. ssh 연동을 위한 pem key와 key pair 생성

# bastion ec2 instance 생성
resource "aws_instance" "bastion_ec2" {
  #ami                         = var.bastion_ami
  ami                         = data.aws_ami.bastion_ami_id.id
  instance_type               = var.bastion_type
  subnet_id                   = aws_subnet.sbn_puba.id
  vpc_security_group_ids      = [aws_security_group.sg_bastion.id]
  key_name                    = aws_key_pair.generated_key.key_name
  associate_public_ip_address = true

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
    encrypted   = true
  }

  ebs_block_device {
    # device_name = "/dev/sd[f-p]"
    device_name           = "/dev/sdi"
    volume_size           = 50
    volume_type           = "gp3"
    delete_on_termination = false
  }

  tags = {
    Name    = "ec2-${var.env}-${var.pjt}-puba-bastion",
    Service = "puba-bastion"
  }
}


resource "aws_eip_association" "asso_bastion_eip" {
  instance_id   = aws_instance.bastion_ec2.id
  allocation_id = aws_eip.eip_bastion.id
}


# bastion host 사용을 위한 ssh 접속 키를 생성
resource "tls_private_key" "ca_key" {
  algorithm = "RSA"
  #  rsa_bits  = 4096

  provisioner "local-exec" {
    command = "echo '${self.private_key_pem}' > ./ec2-${var.env}-${var.pjt}-bastion1.pem"
  }
}


resource "aws_key_pair" "generated_key" {
  key_name   = "${var.pjt}-${var.env}-${var.key_name}"
  public_key = tls_private_key.ca_key.public_key_openssh
}


output "private_key" {
  value = nonsensitive(tls_private_key.ca_key.private_key_pem)
  # sensitive = true
}

