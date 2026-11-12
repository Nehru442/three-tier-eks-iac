# Prometheus + Grafana. The release is named "prometheus", so the Grafana
# service is prometheus-grafana in the prometheus namespace.
# Installed after the load balancer controller, whose webhook intercepts
# Service creation.
resource "helm_release" "prometheus" {
  name             = "prometheus"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = "prometheus"
  create_namespace = true
  timeout          = 900

  depends_on = [
    module.eks,
    aws_eks_addon.ebs_csi,
    helm_release.aws_load_balancer_controller,
  ]
}
