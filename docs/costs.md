# Cost assumptions — review before apply

Prepared 2026-11-02. This is a conservative planning allowance, **not a live Azure quote**.
No resources have been created. Regional SKU availability, quotas, subscription offers,
currency conversion and current retail pricing have not been verified in the account.

## Proposed configuration

Poland Central; AKS Free; two Standard_D4as_v5 nodes (4 vCPU / 16 GiB each), two 64 GiB
managed OS disks, ACR Basic, Standard egress load balancer and its public IP.
No NAT Gateway, application LoadBalancer, private endpoints, Log Analytics or paid
Grafana service. Stage 3 adds a 10 GiB Jenkins PVC (managed-csi); monitoring storage is still planned.
Azure managed disk allocation/billing tiers can exceed the PVC request. Reserve extra
for this disk and the additional boot/test time; the table below is the original
stage 1 allowance, not an updated live quote or a cost cap.

| Item | Planning assumption (USD, before tax) |
| --- | --- |
| Two Linux nodes combined | $0.40–$0.70/hour allowance, replace with current regional quote |
| Disks, ACR Basic, outbound LB/public IP, small lab transfer | Reserve another $0.10/hour for a short session; actual billing meters differ |
| Stage 1 allowance | $0.50–$0.80/hour; roughly $3–$5 for 6 hours |
| Accidental 24 hours | About $12–$20 using the same assumptions |
| Accidental 730-hour month | About $365–$585 using the same assumptions |

These are intentionally rounded assumptions, not fetched SKU rates or a guaranteed cap.
Provisioning and cleanup time also count. Large transfers, extra disks, upgrades and
later monitoring/PVC stages can exceed the allowance. ACR and other services have their
own time/storage billing granularity, so this simple hourly model is approximate.

Before apply, calculate the selected region/SKU in the [Azure pricing calculator](https://azure.microsoft.com/en-us/pricing/calculator/).
Check [Linux VM pricing](https://azure.microsoft.com/en-us/pricing/details/virtual-machines/linux/),
[AKS pricing](https://azure.microsoft.com/en-us/pricing/details/kubernetes-service/),
[ACR pricing](https://azure.microsoft.com/en-us/pricing/details/container-registry/),
[Load Balancer pricing](https://azure.microsoft.com/en-us/pricing/details/load-balancer/),
[IP pricing](https://azure.microsoft.com/en-us/pricing/details/ip-addresses/) and
[managed disks](https://azure.microsoft.com/en-us/pricing/details/managed-disks/).
AKS Free applies to control-plane management; it does not make nodes or networking free.

## Operating rules

1. Run for a learning session, then destroy using the original Terraform state.
2. Use port-forward for applications; avoid per-service public IPs/load balancers.
3. Do not rely on stopping AKS as full cleanup: storage and other services may remain billable.
4. Preserve Jenkins backup outside the cluster before destruction once Jenkins is installed.
5. Verify deletion of both the lab resource group and AKS node resource group.
6. Review Cost Management by subscription, date, both resource groups and tags after reporting catches up.

`project=devops-platform-lab-azure`, `environment=learning` and `lifecycle=ephemeral`
tags identify managed resources where supported. Some managed resources may not inherit
every tag, so resource-group filtering is also necessary.

## Cost Management exercise

Before the first paid session, open Cost Management + Billing in the selected subscription.
Review the cost analysis scope and create a small lab budget with actual and forecast
alerts if desired. Confirm alert recipients yourself; this repo sends no emails.
A budget only notifies; it does not enforce a spending cap or delete resources.
Budget-as-code and a reproducible session report are planned for stage 6.
Record actual versus estimated costs after each session. Cost data may arrive after cleanup.
