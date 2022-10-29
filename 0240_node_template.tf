###################################################################
# EKS Custom AMI 사용시 launch template을 통해 Node 추가가 필요함
# User Data는 줄바꿈이 민감하므로 아래 포맷을 잘 지킬것
###################################################################
resource "aws_launch_template" "eks-node" {
  name = "${var.env}-${var.pjt}-ucmp-eks-node-template-v0.2"
  //vpc_security_group_ids = [aws_security_group.sg_node.id, aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id]
  //vpc_security_group_ids=aws_security_group.sg_node.id
  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size = 300
      volume_type = "gp3"
      encrypted   = true
    }
  }

  image_id      = data.aws_ami.node_ami_id.id
  instance_type = var.node_instance_types
  key_name      = aws_key_pair.generated_key.key_name
  #user_data = filebase64("./custom_script/installsw.sh")
  user_data = base64encode(<<-EOF
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="==MYBOUNDARY=="

--==MYBOUNDARY==
Content-Type: text/x-shellscript; charset="us-ascii"

#!/bin/bash
sudo /etc/eks/bootstrap.sh --apiserver-endpoint '${aws_eks_cluster.eks_cluster.endpoint}' --b64-cluster-ca '${aws_eks_cluster.eks_cluster.certificate_authority.0.data}' '${aws_eks_cluster.eks_cluster.name}'

--==MYBOUNDARY==--\
  EOF
  )


  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "eks-${var.env}-${var.pjt}-node",
    }
  }
}
