apiVersion: crd.k8s.amazonaws.com/v1alpha1
kind: ENIConfig
metadata:
  name: ap-northeast-2a
spec:
  subnet: ${subnet_a_id}
  securityGroups:
    - ${security_group_id}
---
apiVersion: crd.k8s.amazonaws.com/v1alpha1
kind: ENIConfig
metadata:
  name: ap-northeast-2c
spec:
  subnet: ${subnet_c_id}
  securityGroups:
    - ${security_group_id}