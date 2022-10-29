# AWS ingress-controller 가이드 참고
# https://aws.amazon.com/ko/premiumsupport/knowledge-center/eks-alb-ingress-controller-setup/

# EKS Cluster 정보 확인
data "aws_eks_cluster" "eks_cluster" {
  name = aws_eks_cluster.eks_cluster.name
}

data "aws_eks_cluster_auth" "eks_cluster" {
  depends_on = [aws_eks_cluster.eks_cluster]
  name       = aws_eks_cluster.eks_cluster.name
}

# local에서 kubeconfig, ingress-contoller yaml, OIDC issuer URL 생성
locals {
  kubeconfig = <<KUBECONFIG
apiVersion: v1
clusters:
- cluster:
    server: ${aws_eks_cluster.eks_cluster.endpoint}
    certificate-authority-data: ${aws_eks_cluster.eks_cluster.certificate_authority.0.data}
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: aws
  name: aws
current-context: aws
kind: Config
preferences: {}
users:
- name: aws
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1alpha1
      command: aws-iam-authenticator
      args:
        - "token"
        - "-i"
        - "${aws_eks_cluster.eks_cluster.name}"
KUBECONFIG

  CustomResourceDefinition = <<DEFINITION
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: eniconfigs.crd.k8s.amazonaws.com
spec:
  scope: Cluster
  group: crd.k8s.amazonaws.com
  version: v1alpha1
  names:
    plural: eniconfigs
    singular: eniconfig
    kind: ENIConfig
DEFINITION

  ENIconfig = <<ENICONFIG
apiVersion: crd.k8s.amazonaws.com/v1alpha1
kind: ENIConfig
metadata:
  name: ap-northeast-2a
spec:
  subnet: ${aws_subnet.sbn_pria.id}
  securityGroups:
    - ${aws_security_group.sg_cluster.id}
---
apiVersion: crd.k8s.amazonaws.com/v1alpha1
kind: ENIConfig
metadata:
  name: ap-northeast-2c
spec:
  subnet: ${aws_subnet.sbn_pric.id}
  securityGroups:
    - ${aws_security_group.sg_cluster.id}
ENICONFIG

  ServiceAccount = <<SERVICEACCOUNT
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    app.kubernetes.io/component: controller
    app.kubernetes.io/name: aws-load-balancer-controller
  name: aws-load-balancer-controller
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: ${aws_iam_role.aws-load-balancer-controller-role.arn}
SERVICEACCOUNT

  oidc = trimprefix("${aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer}", "https://")

}
output "kubeconfig" {
  value = local.kubeconfig
}
# ingress-contoller 동작에 필요한 IAM Policy 생성
resource "aws_iam_policy" "load-balancer-policy" {
  name        = "AWSLoadBalancerControllerIAMPolicy-${var.env}-${var.pjt}"
  path        = "/"
  description = "AWS LoadBalancer Controller IAM Policy"
  policy      = file("${path.module}/iam-policy.json")
}

# ingress-contoller 동작에 필요한 IAM Role 생성
resource "aws_iam_role" "aws-load-balancer-controller-role" {
  name = "aws-load-balancer-controller-${var.env}-${var.pjt}"
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Federated" : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.oidc}"
        },
        "Action" : "sts:AssumeRoleWithWebIdentity",
        "Condition" : {
          "StringEquals" : {
            "${local.oidc}:sub" : "system:serviceaccount:kube-system:aws-load-balancer-controller"
          }
        }
      }
    ]
  })
}

# Load Balancer controller 동작에 필요한 IAM Policy-Role Attachment
resource "aws_iam_role_policy_attachment" "alb-controller-attachment" {
  role       = aws_iam_role.aws-load-balancer-controller-role.name
  policy_arn = aws_iam_policy.load-balancer-policy.arn
}


# EKS Pod의 Secondary CIDR 구성& Load Balancer controller 동작에 필요한 ServiceAccount 생성
resource "null_resource" "eks-secondary-cidr-1" {
  depends_on = [
    aws_eks_cluster.eks_cluster,
    aws_iam_role_policy_attachment.alb-controller-attachment
  ]
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = <<EOF
mkdir -p ~/.kube
cat <<EOT > ~/.kube/config
${local.kubeconfig}
EOT
ls -al ./
ls -al ${path.module}
chmod +x ${path.module}/kubectl
chmod +x ${path.module}/aws-iam-authenticator
cd ${path.module}
export PATH=$PATH:$(pwd)
kubectl set env daemonset aws-node -n kube-system AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true
sleep 20
kubectl set env daemonset aws-node -n kube-system ENI_CONFIG_LABEL_DEF=failure-domain.beta.kubernetes.io/zone
cat <<EOT > CustomResourceDefinition.yaml
${local.CustomResourceDefinition}
EOT
kubectl apply -f CustomResourceDefinition.yaml
ls -al ./
cat <<EOT > ENIconfig.yaml
${local.ENIconfig}
EOT
kubectl apply -f ENIconfig.yaml
kubectl get all --all-namespaces
echo "ENIconfig apply completed !"
kubectl get pod -o wide -A

cat <<EOT > ServiceAccount.yaml
${local.ServiceAccount}
EOT
kubectl apply -f ServiceAccount.yaml

    EOF
  }
}

locals {
  IngressController = <<INGRESSSTR
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  annotations:
    controller-gen.kubebuilder.io/version: v0.5.0
  creationTimestamp: null
  labels:
    app.kubernetes.io/name: aws-load-balancer-controller
  name: ingressclassparams.elbv2.k8s.aws
spec:
  group: elbv2.k8s.aws
  names:
    kind: IngressClassParams
    listKind: IngressClassParamsList
    plural: ingressclassparams
    singular: ingressclassparams
  scope: Cluster
  versions:
  - additionalPrinterColumns:
    - description: The Ingress Group name
      jsonPath: .spec.group.name
      name: GROUP-NAME
      type: string
    - description: The AWS Load Balancer scheme
      jsonPath: .spec.scheme
      name: SCHEME
      type: string
    - description: The AWS Load Balancer ipAddressType
      jsonPath: .spec.ipAddressType
      name: IP-ADDRESS-TYPE
      type: string
    - jsonPath: .metadata.creationTimestamp
      name: AGE
      type: date
    name: v1beta1
    schema:
      openAPIV3Schema:
        description: IngressClassParams is the Schema for the IngressClassParams API
        properties:
          apiVersion:
            description: 'APIVersion defines the versioned schema of this representation of an object. Servers should convert recognized schemas to the latest internal value, and may reject unrecognized values. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources'
            type: string
          kind:
            description: 'Kind is a string value representing the REST resource this object represents. Servers may infer this from the endpoint the client submits requests to. Cannot be updated. In CamelCase. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds'
            type: string
          metadata:
            type: object
          spec:
            description: IngressClassParamsSpec defines the desired state of IngressClassParams
            properties:
              group:
                description: Group defines the IngressGroup for all Ingresses that belong to IngressClass with this IngressClassParams.
                properties:
                  name:
                    description: Name is the name of IngressGroup.
                    type: string
                required:
                - name
                type: object
              ipAddressType:
                description: IPAddressType defines the ip address type for all Ingresses that belong to IngressClass with this IngressClassParams.
                enum:
                - ipv4
                - dualstack
                type: string
              loadBalancerAttributes:
                description: LoadBalancerAttributes define the custom attributes to LoadBalancers for all Ingress that that belong to IngressClass with this IngressClassParams.
                items:
                  description: Attributes defines custom attributes on resources.
                  properties:
                    key:
                      description: The key of the attribute.
                      type: string
                    value:
                      description: The value of the attribute.
                      type: string
                  required:
                  - key
                  - value
                  type: object
                type: array
              namespaceSelector:
                description: NamespaceSelector restrict the namespaces of Ingresses that are allowed to specify the IngressClass with this IngressClassParams. * if absent or present but empty, it selects all namespaces.
                properties:
                  matchExpressions:
                    description: matchExpressions is a list of label selector requirements. The requirements are ANDed.
                    items:
                      description: A label selector requirement is a selector that contains values, a key, and an operator that relates the key and values.
                      properties:
                        key:
                          description: key is the label key that the selector applies to.
                          type: string
                        operator:
                          description: operator represents a key's relationship to a set of values. Valid operators are In, NotIn, Exists and DoesNotExist.
                          type: string
                        values:
                          description: values is an array of string values. If the operator is In or NotIn, the values array must be non-empty. If the operator is Exists or DoesNotExist, the values array must be empty. This array is replaced during a strategic merge patch.
                          items:
                            type: string
                          type: array
                      required:
                      - key
                      - operator
                      type: object
                    type: array
                  matchLabels:
                    additionalProperties:
                      type: string
                    description: matchLabels is a map of {key,value} pairs. A single {key,value} in the matchLabels map is equivalent to an element of matchExpressions, whose key field is "key", the operator is "In", and the values array contains only "value". The requirements are ANDed.
                    type: object
                type: object
              scheme:
                description: Scheme defines the scheme for all Ingresses that belong to IngressClass with this IngressClassParams.
                enum:
                - internal
                - internet-facing
                type: string
              tags:
                description: Tags defines list of Tags on AWS resources provisioned for Ingresses that belong to IngressClass with this IngressClassParams.
                items:
                  description: Tag defines a AWS Tag on resources.
                  properties:
                    key:
                      description: The key of the tag.
                      type: string
                    value:
                      description: The value of the tag.
                      type: string
                  required:
                  - key
                  - value
                  type: object
                type: array
            type: object
        type: object
    served: true
    storage: true
    subresources: {}
status:
  acceptedNames:
    kind: ""
    plural: ""
  conditions: []
  storedVersions: []
---
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  annotations:
    controller-gen.kubebuilder.io/version: v0.5.0
  creationTimestamp: null
  labels:
    app.kubernetes.io/name: aws-load-balancer-controller
  name: targetgroupbindings.elbv2.k8s.aws
spec:
  group: elbv2.k8s.aws
  names:
    kind: TargetGroupBinding
    listKind: TargetGroupBindingList
    plural: targetgroupbindings
    singular: targetgroupbinding
  scope: Namespaced
  versions:
  - additionalPrinterColumns:
    - description: The Kubernetes Service's name
      jsonPath: .spec.serviceRef.name
      name: SERVICE-NAME
      type: string
    - description: The Kubernetes Service's port
      jsonPath: .spec.serviceRef.port
      name: SERVICE-PORT
      type: string
    - description: The AWS TargetGroup's TargetType
      jsonPath: .spec.targetType
      name: TARGET-TYPE
      type: string
    - description: The AWS TargetGroup's Amazon Resource Name
      jsonPath: .spec.targetGroupARN
      name: ARN
      priority: 1
      type: string
    - jsonPath: .metadata.creationTimestamp
      name: AGE
      type: date
    name: v1alpha1
    schema:
      openAPIV3Schema:
        description: TargetGroupBinding is the Schema for the TargetGroupBinding API
        properties:
          apiVersion:
            description: 'APIVersion defines the versioned schema of this representation of an object. Servers should convert recognized schemas to the latest internal value, and may reject unrecognized values. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources'
            type: string
          kind:
            description: 'Kind is a string value representing the REST resource this object represents. Servers may infer this from the endpoint the client submits requests to. Cannot be updated. In CamelCase. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds'
            type: string
          metadata:
            type: object
          spec:
            description: TargetGroupBindingSpec defines the desired state of TargetGroupBinding
            properties:
              networking:
                description: networking provides the networking setup for ELBV2 LoadBalancer to access targets in TargetGroup.
                properties:
                  ingress:
                    description: List of ingress rules to allow ELBV2 LoadBalancer to access targets in TargetGroup.
                    items:
                      properties:
                        from:
                          description: List of peers which should be able to access the targets in TargetGroup. At least one NetworkingPeer should be specified.
                          items:
                            description: NetworkingPeer defines the source/destination peer for networking rules.
                            properties:
                              ipBlock:
                                description: IPBlock defines an IPBlock peer. If specified, none of the other fields can be set.
                                properties:
                                  cidr:
                                    description: CIDR is the network CIDR. Both IPV4 or IPV6 CIDR are accepted.
                                    type: string
                                required:
                                - cidr
                                type: object
                              securityGroup:
                                description: SecurityGroup defines a SecurityGroup peer. If specified, none of the other fields can be set.
                                properties:
                                  groupID:
                                    description: GroupID is the EC2 SecurityGroupID.
                                    type: string
                                required:
                                - groupID
                                type: object
                            type: object
                          type: array
                        ports:
                          description: List of ports which should be made accessible on the targets in TargetGroup. If ports is empty or unspecified, it defaults to all ports with TCP.
                          items:
                            properties:
                              port:
                                anyOf:
                                - type: integer
                                - type: string
                                description: The port which traffic must match. When NodePort endpoints(instance TargetType) is used, this must be a numerical port. When Port endpoints(ip TargetType) is used, this can be either numerical or named port on pods. if port is unspecified, it defaults to all ports.
                                x-kubernetes-int-or-string: true
                              protocol:
                                description: The protocol which traffic must match. If protocol is unspecified, it defaults to TCP.
                                enum:
                                - TCP
                                - UDP
                                type: string
                            type: object
                          type: array
                      required:
                      - from
                      - ports
                      type: object
                    type: array
                type: object
              serviceRef:
                description: serviceRef is a reference to a Kubernetes Service and ServicePort.
                properties:
                  name:
                    description: Name is the name of the Service.
                    type: string
                  port:
                    anyOf:
                    - type: integer
                    - type: string
                    description: Port is the port of the ServicePort.
                    x-kubernetes-int-or-string: true
                required:
                - name
                - port
                type: object
              targetGroupARN:
                description: targetGroupARN is the Amazon Resource Name (ARN) for the TargetGroup.
                type: string
              targetType:
                description: targetType is the TargetType of TargetGroup. If unspecified, it will be automatically inferred.
                enum:
                - instance
                - ip
                type: string
            required:
            - serviceRef
            - targetGroupARN
            type: object
          status:
            description: TargetGroupBindingStatus defines the observed state of TargetGroupBinding
            properties:
              observedGeneration:
                description: The generation observed by the TargetGroupBinding controller.
                format: int64
                type: integer
            type: object
        type: object
    served: true
    storage: false
    subresources:
      status: {}
  - additionalPrinterColumns:
    - description: The Kubernetes Service's name
      jsonPath: .spec.serviceRef.name
      name: SERVICE-NAME
      type: string
    - description: The Kubernetes Service's port
      jsonPath: .spec.serviceRef.port
      name: SERVICE-PORT
      type: string
    - description: The AWS TargetGroup's TargetType
      jsonPath: .spec.targetType
      name: TARGET-TYPE
      type: string
    - description: The AWS TargetGroup's Amazon Resource Name
      jsonPath: .spec.targetGroupARN
      name: ARN
      priority: 1
      type: string
    - jsonPath: .metadata.creationTimestamp
      name: AGE
      type: date
    name: v1beta1
    schema:
      openAPIV3Schema:
        description: TargetGroupBinding is the Schema for the TargetGroupBinding API
        properties:
          apiVersion:
            description: 'APIVersion defines the versioned schema of this representation of an object. Servers should convert recognized schemas to the latest internal value, and may reject unrecognized values. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources'
            type: string
          kind:
            description: 'Kind is a string value representing the REST resource this object represents. Servers may infer this from the endpoint the client submits requests to. Cannot be updated. In CamelCase. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds'
            type: string
          metadata:
            type: object
          spec:
            description: TargetGroupBindingSpec defines the desired state of TargetGroupBinding
            properties:
              ipAddressType:
                description: ipAddressType specifies whether the target group is of type IPv4 or IPv6. If unspecified, it will be automatically inferred.
                enum:
                - ipv4
                - ipv6
                type: string
              networking:
                description: networking defines the networking rules to allow ELBV2 LoadBalancer to access targets in TargetGroup.
                properties:
                  ingress:
                    description: List of ingress rules to allow ELBV2 LoadBalancer to access targets in TargetGroup.
                    items:
                      description: NetworkingIngressRule defines a particular set of traffic that is allowed to access TargetGroup's targets.
                      properties:
                        from:
                          description: List of peers which should be able to access the targets in TargetGroup. At least one NetworkingPeer should be specified.
                          items:
                            description: NetworkingPeer defines the source/destination peer for networking rules.
                            properties:
                              ipBlock:
                                description: IPBlock defines an IPBlock peer. If specified, none of the other fields can be set.
                                properties:
                                  cidr:
                                    description: CIDR is the network CIDR. Both IPV4 or IPV6 CIDR are accepted.
                                    type: string
                                required:
                                - cidr
                                type: object
                              securityGroup:
                                description: SecurityGroup defines a SecurityGroup peer. If specified, none of the other fields can be set.
                                properties:
                                  groupID:
                                    description: GroupID is the EC2 SecurityGroupID.
                                    type: string
                                required:
                                - groupID
                                type: object
                            type: object
                          type: array
                        ports:
                          description: List of ports which should be made accessible on the targets in TargetGroup. If ports is empty or unspecified, it defaults to all ports with TCP.
                          items:
                            description: NetworkingPort defines the port and protocol for networking rules.
                            properties:
                              port:
                                anyOf:
                                - type: integer
                                - type: string
                                description: The port which traffic must match. When NodePort endpoints(instance TargetType) is used, this must be a numerical port. When Port endpoints(ip TargetType) is used, this can be either numerical or named port on pods. if port is unspecified, it defaults to all ports.
                                x-kubernetes-int-or-string: true
                              protocol:
                                description: The protocol which traffic must match. If protocol is unspecified, it defaults to TCP.
                                enum:
                                - TCP
                                - UDP
                                type: string
                            type: object
                          type: array
                      required:
                      - from
                      - ports
                      type: object
                    type: array
                type: object
              nodeSelector:
                description: node selector for instance type target groups to only register certain nodes
                properties:
                  matchExpressions:
                    description: matchExpressions is a list of label selector requirements. The requirements are ANDed.
                    items:
                      description: A label selector requirement is a selector that contains values, a key, and an operator that relates the key and values.
                      properties:
                        key:
                          description: key is the label key that the selector applies to.
                          type: string
                        operator:
                          description: operator represents a key's relationship to a set of values. Valid operators are In, NotIn, Exists and DoesNotExist.
                          type: string
                        values:
                          description: values is an array of string values. If the operator is In or NotIn, the values array must be non-empty. If the operator is Exists or DoesNotExist, the values array must be empty. This array is replaced during a strategic merge patch.
                          items:
                            type: string
                          type: array
                      required:
                      - key
                      - operator
                      type: object
                    type: array
                  matchLabels:
                    additionalProperties:
                      type: string
                    description: matchLabels is a map of {key,value} pairs. A single {key,value} in the matchLabels map is equivalent to an element of matchExpressions, whose key field is "key", the operator is "In", and the values array contains only "value". The requirements are ANDed.
                    type: object
                type: object
              serviceRef:
                description: serviceRef is a reference to a Kubernetes Service and ServicePort.
                properties:
                  name:
                    description: Name is the name of the Service.
                    type: string
                  port:
                    anyOf:
                    - type: integer
                    - type: string
                    description: Port is the port of the ServicePort.
                    x-kubernetes-int-or-string: true
                required:
                - name
                - port
                type: object
              targetGroupARN:
                description: targetGroupARN is the Amazon Resource Name (ARN) for the TargetGroup.
                minLength: 1
                type: string
              targetType:
                description: targetType is the TargetType of TargetGroup. If unspecified, it will be automatically inferred.
                enum:
                - instance
                - ip
                type: string
            required:
            - serviceRef
            - targetGroupARN
            type: object
          status:
            description: TargetGroupBindingStatus defines the observed state of TargetGroupBinding
            properties:
              observedGeneration:
                description: The generation observed by the TargetGroupBinding controller.
                format: int64
                type: integer
            type: object
        type: object
    served: true
    storage: true
    subresources:
      status: {}
status:
  acceptedNames:
    kind: ""
    plural: ""
  conditions: []
  storedVersions: []
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  labels:
    app.kubernetes.io/name: aws-load-balancer-controller
  name: aws-load-balancer-controller-leader-election-role
  namespace: kube-system
rules:
- apiGroups:
  - ""
  resources:
  - configmaps
  verbs:
  - create
- apiGroups:
  - ""
  resourceNames:
  - aws-load-balancer-controller-leader
  resources:
  - configmaps
  verbs:
  - get
  - update
  - patch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  creationTimestamp: null
  labels:
    app.kubernetes.io/name: aws-load-balancer-controller
  name: aws-load-balancer-controller-role
rules:
- apiGroups:
  - ""
  resources:
  - endpoints
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - ""
  resources:
  - events
  verbs:
  - create
  - patch
- apiGroups:
  - ""
  resources:
  - namespaces
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - ""
  resources:
  - nodes
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - ""
  resources:
  - pods
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - ""
  resources:
  - pods/status
  verbs:
  - patch
  - update
- apiGroups:
  - ""
  resources:
  - secrets
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - ""
  resources:
  - services
  verbs:
  - get
  - list
  - patch
  - update
  - watch
- apiGroups:
  - ""
  resources:
  - services/status
  verbs:
  - patch
  - update
- apiGroups:
  - discovery.k8s.io
  resources:
  - endpointslices
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - elbv2.k8s.aws
  resources:
  - ingressclassparams
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - elbv2.k8s.aws
  resources:
  - targetgroupbindings
  verbs:
  - create
  - delete
  - get
  - list
  - patch
  - update
  - watch
- apiGroups:
  - elbv2.k8s.aws
  resources:
  - targetgroupbindings/status
  verbs:
  - patch
  - update
- apiGroups:
  - extensions
  resources:
  - ingresses
  verbs:
  - get
  - list
  - patch
  - update
  - watch
- apiGroups:
  - extensions
  resources:
  - ingresses/status
  verbs:
  - patch
  - update
- apiGroups:
  - networking.k8s.io
  resources:
  - ingressclasses
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - networking.k8s.io
  resources:
  - ingresses
  verbs:
  - get
  - list
  - patch
  - update
  - watch
- apiGroups:
  - networking.k8s.io
  resources:
  - ingresses/status
  verbs:
  - patch
  - update
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  labels:
    app.kubernetes.io/name: aws-load-balancer-controller
  name: aws-load-balancer-controller-leader-election-rolebinding
  namespace: kube-system
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: aws-load-balancer-controller-leader-election-role
subjects:
- kind: ServiceAccount
  name: aws-load-balancer-controller
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  labels:
    app.kubernetes.io/name: aws-load-balancer-controller
  name: aws-load-balancer-controller-rolebinding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: aws-load-balancer-controller-role
subjects:
- kind: ServiceAccount
  name: aws-load-balancer-controller
  namespace: kube-system
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app.kubernetes.io/name: aws-load-balancer-controller
  name: aws-load-balancer-webhook-service
  namespace: kube-system
spec:
  ports:
  - port: 443
    targetPort: 9443
  selector:
    app.kubernetes.io/component: controller
    app.kubernetes.io/name: aws-load-balancer-controller
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app.kubernetes.io/component: controller
    app.kubernetes.io/name: aws-load-balancer-controller
  name: aws-load-balancer-controller
  namespace: kube-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/component: controller
      app.kubernetes.io/name: aws-load-balancer-controller
  template:
    metadata:
      labels:
        app.kubernetes.io/component: controller
        app.kubernetes.io/name: aws-load-balancer-controller
    spec:
      containers:
      - args:
        - --cluster-name=${aws_eks_cluster.eks_cluster.name}
        - --ingress-class=alb
        image: amazon/aws-alb-ingress-controller:v2.4.0
        livenessProbe:
          failureThreshold: 2
          httpGet:
            path: /healthz
            port: 61779
            scheme: HTTP
          initialDelaySeconds: 30
          timeoutSeconds: 10
        name: controller
        ports:
        - containerPort: 9443
          name: webhook-server
          protocol: TCP
        resources:
          limits:
            cpu: 200m
            memory: 500Mi
          requests:
            cpu: 100m
            memory: 200Mi
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          runAsNonRoot: true
        volumeMounts:
        - mountPath: /tmp/k8s-webhook-server/serving-certs
          name: cert
          readOnly: true
      priorityClassName: system-cluster-critical
      securityContext:
        fsGroup: 1337
      serviceAccountName: aws-load-balancer-controller
      terminationGracePeriodSeconds: 10
      volumes:
      - name: cert
        secret:
          defaultMode: 420
          secretName: aws-load-balancer-webhook-tls
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  labels:
    app.kubernetes.io/name: aws-load-balancer-controller
  name: aws-load-balancer-serving-cert
  namespace: kube-system
spec:
  dnsNames:
  - aws-load-balancer-webhook-service.kube-system.svc
  - aws-load-balancer-webhook-service.kube-system.svc.cluster.local
  issuerRef:
    kind: Issuer
    name: aws-load-balancer-selfsigned-issuer
  secretName: aws-load-balancer-webhook-tls
---
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  labels:
    app.kubernetes.io/name: aws-load-balancer-controller
  name: aws-load-balancer-selfsigned-issuer
  namespace: kube-system
spec:
  selfSigned: {}
---
apiVersion: admissionregistration.k8s.io/v1
kind: MutatingWebhookConfiguration
metadata:
  annotations:
    cert-manager.io/inject-ca-from: kube-system/aws-load-balancer-serving-cert
  labels:
    app.kubernetes.io/name: aws-load-balancer-controller
  name: aws-load-balancer-webhook
webhooks:
- admissionReviewVersions:
  - v1beta1
  clientConfig:
    service:
      name: aws-load-balancer-webhook-service
      namespace: kube-system
      path: /mutate-v1-pod
  failurePolicy: Fail
  name: mpod.elbv2.k8s.aws
  namespaceSelector:
    matchExpressions:
    - key: elbv2.k8s.aws/pod-readiness-gate-inject
      operator: In
      values:
      - enabled
  objectSelector:
    matchExpressions:
    - key: app.kubernetes.io/name
      operator: NotIn
      values:
      - aws-load-balancer-controller
  rules:
  - apiGroups:
    - ""
    apiVersions:
    - v1
    operations:
    - CREATE
    resources:
    - pods
  sideEffects: None
- admissionReviewVersions:
  - v1beta1
  clientConfig:
    service:
      name: aws-load-balancer-webhook-service
      namespace: kube-system
      path: /mutate-elbv2-k8s-aws-v1beta1-targetgroupbinding
  failurePolicy: Fail
  name: mtargetgroupbinding.elbv2.k8s.aws
  rules:
  - apiGroups:
    - elbv2.k8s.aws
    apiVersions:
    - v1beta1
    operations:
    - CREATE
    - UPDATE
    resources:
    - targetgroupbindings
  sideEffects: None
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  annotations:
    cert-manager.io/inject-ca-from: kube-system/aws-load-balancer-serving-cert
  labels:
    app.kubernetes.io/name: aws-load-balancer-controller
  name: aws-load-balancer-webhook
webhooks:
- admissionReviewVersions:
  - v1beta1
  clientConfig:
    service:
      name: aws-load-balancer-webhook-service
      namespace: kube-system
      path: /validate-elbv2-k8s-aws-v1beta1-targetgroupbinding
  failurePolicy: Fail
  name: vtargetgroupbinding.elbv2.k8s.aws
  rules:
  - apiGroups:
    - elbv2.k8s.aws
    apiVersions:
    - v1beta1
    operations:
    - CREATE
    - UPDATE
    resources:
    - targetgroupbindings
  sideEffects: None
- admissionReviewVersions:
  - v1beta1
  clientConfig:
    service:
      name: aws-load-balancer-webhook-service
      namespace: kube-system
      path: /validate-networking-v1-ingress
  failurePolicy: Fail
  matchPolicy: Equivalent
  name: vingress.elbv2.k8s.aws
  rules:
  - apiGroups:
    - networking.k8s.io
    apiVersions:
    - v1
    operations:
    - CREATE
    - UPDATE
    resources:
    - ingresses
  sideEffects: None
---
apiVersion: elbv2.k8s.aws/v1beta1
kind: IngressClassParams
metadata:
  labels:
    app.kubernetes.io/name: aws-load-balancer-controller
  name: alb
---
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  labels:
    app.kubernetes.io/name: aws-load-balancer-controller
  name: alb
spec:
  controller: ingress.k8s.aws/alb
  parameters:
    apiGroup: elbv2.k8s.aws
    kind: IngressClassParams
    name: alb

INGRESSSTR
}
resource "null_resource" "kubectl" {
  depends_on = [
    null_resource.eks-secondary-cidr-1,
    aws_eks_node_group.node
  ]
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    # Load credentials to local environment so subsequent kubectl commands can be run
    command = <<EOF
mkdir -p ~/.kube
cat <<EOT > ~/.kube/config
${local.kubeconfig}
EOT
ls -al ./
cat <<EOT > ingress-controller.yaml
${local.IngressController}
EOT
ls -al ./
# aws eks --region ${var.region} update-kubeconfig --name ${aws_eks_cluster.eks_cluster.name}
chmod +x ./kubectl
chmod +x ./aws-iam-authenticator
export PATH=$PATH:$(pwd)
./kubectl version --client
./kubectl version
./kubectl apply -f cert-manager.yaml
./kubectl get all --all-namespaces
./kubectl rollout status deployment cert-manager-webhook -n cert-manager
./kubectl get all --all-namespaces
./kubectl apply -f ingress-controller.yaml
sleep 5
./kubectl apply -f ingress-controller.yaml
./kubectl rollout status deployment aws-load-balancer-controller -n kube-system
./kubectl get all --all-namespaces
    EOF
  }
}

# kubectl-destroy
resource "null_resource" "kubectl-destroy" {
  depends_on = [
    aws_eks_node_group.node,
    aws_iam_openid_connect_provider.eks_oidc_provider,
    aws_iam_policy.load-balancer-policy,
    aws_iam_role.aws-load-balancer-controller-role,
    aws_iam_role_policy_attachment.alb-controller-attachment,
    aws_subnet.sbn_puba,
    # aws_subnet.sbn_pubc,
    aws_eip.eip_nat_puba,
    # aws_eip.eip_nat_pubc,
    aws_nat_gateway.nat_a,
    # aws_nat_gateway.nat_c,
    aws_route_table_association.asso_sbn_pria,
    # aws_route_table_association.asso_sbn_pric,
    aws_route_table_association.asso_sbn_puba,
    # aws_route_table_association.asso_sbn_pubc,
    aws_route_table.route_pria,
    # aws_route_table.route_pric,
    aws_route_table.route_pub,
    aws_security_group.sg_node

  ]
  triggers = {
    kube = local.kubeconfig
  }
  provisioner "local-exec" {
    when    = destroy
    command = <<EOF
mkdir -p ~/.kube
cat <<EOT > ~/.kube/config
${self.triggers.kube}
EOT
ls -al ./
chmod +x ./kubectl
chmod +x ./aws-iam-authenticator
export PATH=$PATH:$(pwd)
./kubectl version --client
./kubectl version
./kubectl get all --all-namespaces
KUBECTL_GET_ING=`./kubectl get ingress --all-namespaces`
if [[ -z $KUBECTL_GET_ING ]]
then
  echo "No Ingress Resources Found."
else
  ./kubectl get ingress --all-namespaces | grep -v NAMESPACE | awk '{ print "kubectl delete ingress "$2" -n "$1 }' | sh -v
fi
./kubectl get all --all-namespaces
    EOF
  }
}



