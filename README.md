# Three-Tier App on AWS EKS with Terraform (modernised)

A three-tier To-Do application (React frontend, Node.js API, MongoDB) running on **Amazon EKS**, with the whole platform created by **Terraform**: VPC, EKS cluster, node group, IAM roles for service accounts, EBS CSI driver, Cluster Autoscaler, AWS Load Balancer Controller and a Prometheus + Grafana monitoring stack.

This is a fork of [LondheShubham153/three-tier-eks-iac](https://github.com/LondheShubham153/three-tier-eks-iac) (MIT licence). The original Terraform was written for Kubernetes 1.25 and no longer works on current EKS, so **my main contribution is bringing the infrastructure code up to date and getting the whole stack running end to end.**

## Architecture

```
                         Internet
                             |
                             v
        AWS Application Load Balancer  (Ingress "mainlb", created by the
                             |          AWS Load Balancer Controller)
              +--------------+---------------+
              | /api                         | /
              v                              v
     Service "api" :8080            Service "frontend" :3000
     Node.js API (2 replicas)       React app
              |
              v
     Service "mongodb" -> MongoDB 4.4.6 (1 pod)

  Namespace "workshop"  ............  the application
  Namespace "prometheus" ...........  Prometheus, Alertmanager, Grafana
  Namespace "kube-system" ..........  Cluster Autoscaler, LB Controller, EBS CSI, CoreDNS
```

**Infrastructure (Terraform, `ap-south-1`):**
- VPC with 2 public and 2 private subnets across 2 AZs, one shared NAT gateway
- EKS 1.35 with a managed node group: 2 x `t3.medium` (Amazon Linux 2023), scaling between 1 and 3
- IAM roles for service accounts (IRSA) for the EBS CSI driver, Cluster Autoscaler and Load Balancer Controller
- Helm releases managed by Terraform: Cluster Autoscaler, AWS Load Balancer Controller, `kube-prometheus-stack`
- Terraform state in my own S3 bucket

## What I did

1. **Audited the original Terraform** and found it could not create a working cluster on current EKS (details below).
2. **Rewrote the infrastructure code** for the current EKS module, VPC module, node images and add-ons, keeping the original file layout.
3. **Provisioned the platform** with `terraform apply`: 72 resources, two nodes `Ready`, every system pod `Running`.
4. **Built and pushed the images** for the frontend and backend to my own Docker Hub account, because the original manifests pulled from the author's registry.
5. **Deployed the app** to a `workshop` namespace (MongoDB, API, frontend) and exposed it through an ALB Ingress.
6. **Fixed the Ingress** so it works from the load balancer's own address (the original was locked to the author's domain).
7. **Verified and monitored** the app: added items in the UI, then checked Prometheus targets and Grafana dashboards for the `workshop` namespace.
8. **Tore everything down in a safe order** (Ingress and services first, then `terraform destroy`) so no load balancer or network resource was left behind.

## What was wrong with the original, and what I changed

| Area | Original | Now |
|---|---|---|
| Kubernetes version | `1.25` (a number, which also turns `1.30` into `1.3`) | `"1.35"` as a string |
| EKS module | `terraform-aws-modules/eks` `18.29.0` | `~> 20.37`; `manage_aws_auth_configmap` replaced by EKS access entries |
| Node image | Amazon Linux 2 (AWS stopped publishing EKS AL2 AMIs on 26 Nov 2025) | Amazon Linux 2023 (`AL2023_x86_64_STANDARD`) |
| Node sizes | `t3.small` + a tainted `t3.micro` spot group, max 10 each | 2 x `t3.medium`, max 3; spot group removed |
| Add-ons | Hard-coded 1.25 versions in `variables.tf` | `most_recent = true`; EBS CSI driver as `aws_eks_addon` |
| Cluster Autoscaler | Hand-written manifests, image `v1.23.1` | Official Helm chart, image `v1.35.1` |
| Load Balancer Controller | Helm chart `1.4.4` (2022) | Latest chart; `region` and `vpcId` set explicitly |
| Monitoring | Pinned to old chart/values | `kube-prometheus-stack` via Helm |
| VPC module | Old version | `~> 5.21`, single NAT gateway to save cost |
| State backend | Author's S3 bucket | My own S3 bucket in `ap-south-1` |
| Providers | `kubectl` provider for manifests | Not needed; `kubernetes` and `helm` providers authenticate with `aws eks get-token` |
| Demo IAM user, group and role | Created by `iam.tf` | Removed; the identity running `apply` is cluster admin via the module |

## Problems I hit and how I solved them

| Problem | Cause | Fix |
|---|---|---|
| `terraform validate` failed with "no attribute `cluster_name`" | Some files used the new module outputs while `eks.tf` still used the old module | Replaced all the files so the module version and outputs matched; removed `.terraform.lock.hcl` so providers re-resolved |
| Heredoc files contained a stray `EOF` line | Pasted into an editor instead of the terminal prompt | Pasted at the prompt, then checked each file with `grep`/`tail` |
| EBS CSI IAM role would create a circular dependency | The role needs the cluster's OIDC provider, but the add-on was declared inside the EKS module | Created the add-on as a separate `aws_eks_addon` resource |
| Browser got `404` from the ALB address | The Ingress rule had `host: app.sandipdas.in` (the author's domain) | Removed the `host` line so the rule matches any host |
| Images could not be pulled from the author's registry | Manifests referenced `public.ecr.aws/w8u5e4v2/...`, which I cannot push to | Built the images on an EC2 server and pushed to Docker Hub, then updated the image lines |
| `docker` not found on the build server | Docker was not installed | `apt-get install docker.io`, then `docker login` |
| Prometheus page `ERR_CONNECTION_TIMED_OUT` | I opened the internal ClusterIP instead of an external address | Temporarily switched the service to `LoadBalancer` and used port 9090 |
| README commands that cannot work as written | `kubectl delete -f -f`, `logs -f POD -f`, two `kubectl apply` commands on one line | Used correct, separate commands |
| Risk of leftover AWS resources | Load balancers created by Kubernetes block deletion of the VPC | Deleted the Ingress and services first, confirmed no load balancers remained, then ran `terraform destroy` |

## What I learned

- **Infrastructure code goes stale.** A tutorial from 2023 could not create a cluster in 2026: the Kubernetes version, node OS image, module versions and chart versions had all moved on. I checked AWS's own documentation for supported versions and the Amazon Linux 2 end of support before changing anything.
- **Terraform module upgrades are real work.** Moving the EKS module from v18 to v20 changed output names (`cluster_id` to `cluster_name`), removed the `aws-auth` ConfigMap in favour of access entries, and exposed dependency cycles. Running `validate` and `plan` first caught these before any money was spent.
- **IRSA** (IAM roles for service accounts) lets individual pods get least-privilege AWS permissions through the cluster's OIDC provider, which is how the autoscaler, EBS driver and load balancer controller get their access.
- **How the Cluster Autoscaler finds node groups:** EKS managed node groups are tagged automatically, so auto-discovery works without extra configuration.
- **ALB Ingress with `target-type: ip`** sends traffic straight to pod IPs, and path rules (`/api` and `/`) let one load balancer serve both the API and the frontend.
- **Helm through Terraform** (`helm_release`) keeps cluster add-ons in the same plan as the cluster, but dependencies must be explicit: the monitoring stack waits for the load balancer controller, whose webhook intercepts Service creation.
- **Cost control:** one NAT gateway instead of two, small node counts, a node group maximum of 3 instead of 10, and a fixed teardown order. While running, the cluster costs roughly $0.30 to $0.35 per hour (my estimate from published prices).
- **Teardown order matters.** Resources that Kubernetes creates (load balancers, volumes) are not in the Terraform state, so they must be deleted first or `terraform destroy` hangs on the VPC.
- **Verify, don't assume.** I checked every file after writing it (`grep`, `tail`, `validate`) and confirmed the AWS side (`aws elbv2` and `aws elb`) was empty before destroying.

## Repository layout

```
.
|-- app/
|   |-- frontend/            React app + Dockerfile
|   `-- backend/             Node.js API + Dockerfile
|-- k8s_manifests/
|   |-- mongo/               secrets.yaml, deploy.yaml, service.yaml
|   |-- backend-deployment.yaml, backend-service.yaml
|   |-- frontend-deployment.yaml, frontend-service.yaml
|   `-- full_stack_lb.yaml   ALB Ingress
`-- terraform/
    |-- provider.tf, helm-provider.tf, backend.tf, variables.tf
    |-- vpc.tf, eks.tf, ebs_csi_driver.tf
    |-- autoscaler-iam.tf, autoscaler-manifest.tf
    |-- helm-load-balancer-controller.tf, monitoring.tf
    `-- iam.tf               (intentionally empty)
```

## How to run it

Prerequisites: AWS CLI v2, Terraform >= 1.5, `kubectl`, Helm, Docker, and an AWS account with permissions to create VPC, EKS, IAM, KMS and EC2 resources.

```bash
# 1. Infrastructure (about 20-25 minutes)
cd terraform
# edit backend.tf to use your own S3 bucket, or remove the backend block for local state
terraform init
terraform validate
terraform plan -out=tfplan
terraform apply tfplan

# 2. Connect to the cluster
aws eks update-kubeconfig --name three-tier-eks --region ap-south-1
kubectl get nodes
kubectl get pods -A

# 3. Build and push the images (use your own registry)
docker login -u YOUR_DOCKERHUB_USER
docker build -t YOUR_DOCKERHUB_USER/workshop-frontend:v1 app/frontend
docker push YOUR_DOCKERHUB_USER/workshop-frontend:v1
docker build -t YOUR_DOCKERHUB_USER/workshop-backend:v1 app/backend
docker push YOUR_DOCKERHUB_USER/workshop-backend:v1
# then set these image names in k8s_manifests/frontend-deployment.yaml and backend-deployment.yaml

# 4. Deploy the app
kubectl create ns workshop
kubectl apply -n workshop -f k8s_manifests/mongo/
kubectl apply -n workshop -f k8s_manifests/backend-deployment.yaml -f k8s_manifests/backend-service.yaml
kubectl apply -n workshop -f k8s_manifests/frontend-deployment.yaml -f k8s_manifests/frontend-service.yaml
kubectl apply -f k8s_manifests/full_stack_lb.yaml
kubectl get ingress -n workshop        # open the ADDRESS in a browser (http://)
```

Grafana (default login is `admin` / `prom-operator`: change it):

```bash
kubectl port-forward -n prometheus svc/prometheus-grafana 3000:80
```

For my screenshots I temporarily switched the Grafana and Prometheus services to `LoadBalancer` and switched them back to `ClusterIP` afterwards. Prometheus has no login, so do not leave it exposed.

## Cleanup (in this order)

```bash
# 1. Remove everything Kubernetes created
kubectl patch svc prometheus-grafana -n prometheus -p '{"spec":{"type":"ClusterIP"}}'
kubectl patch svc prometheus-kube-prometheus-prometheus -n prometheus -p '{"spec":{"type":"ClusterIP"}}'
kubectl delete -f k8s_manifests/full_stack_lb.yaml
kubectl delete ns workshop

# 2. Confirm no load balancers are left (both should print [])
aws elbv2 describe-load-balancers --region ap-south-1 --query 'LoadBalancers[].LoadBalancerName'
aws elb describe-load-balancers --region ap-south-1 --query 'LoadBalancerDescriptions[].LoadBalancerName'

# 3. Destroy the infrastructure
cd terraform
terraform destroy
```


## Credits

- Original project and tutorial: [LondheShubham153/three-tier-eks-iac](https://github.com/LondheShubham153/three-tier-eks-iac) (MIT licence), from TrainWithShubham.
- Infrastructure modernisation, deployment, monitoring and write-up: Venkata Nehru Kotapati ([GitHub](https://github.com/Nehru442) / [LinkedIn](https://www.linkedin.com/in/nehru-kotapati)).