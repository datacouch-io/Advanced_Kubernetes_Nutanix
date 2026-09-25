# Further Labs — not scheduled in this delivery

Twelve labs from the full 26-lab course that the **three-day outline does not cover**. They are
complete and tested — each has real screenshots, evidence and a `.docx` — and can be dropped into a
longer engagement, used as follow-up reading, or swapped in if a client's priorities differ.

| Lab | What it proves | Platform |
|---|---|---|
| [Cluster Architecture: Autopilot vs Standard](lab-05-cluster-architecture.md) | Private clusters, master-authorized-networks lockout/recovery, release channels | GKE |
| [Cluster Scale Knee-Point](lab-07-cluster-scale-knee-point.md) | Find the load level where scheduling latency degrades | GKE |
| [Multi-Cluster Service Mesh with Istio](lab-09-multicluster-service-mesh.md) | One logical Service across two clusters; verify cross-cluster routing in Envoy | GKE ×2 |
| [Image Scanning & Admission Control (Kyverno)](lab-10-image-scanning-admission-control.md) | Block non-compliant images at admission; spec-compliant ≠ safe | GKE |
| [Dynamic Resource Allocation (DRA)](lab-18-dra.md) | Request a device by attribute; placed only on a matching node | kind |
| [Kueue-Managed Distributed Training](lab-19-distributed-training.md) | A real `torch.distributed` PyTorchJob queued and admitted by Kueue | GKE |
| [Advanced HPA/VPA Autoscaling](lab-20-hpa-vpa-autoscaling.md) | Asymmetric HPA behavior; VPA in-place resize with zero restarts | kind |
| [Inference Autoscaling Signals](lab-21-inference-autoscaling.md) | TTFT/queue-depth spike under load, then recover after scaling out | GKE |
| [Workload Identity & Binary Authorization](lab-22-workload-identity-binary-authorization.md) | Per-pod cloud identity; only signed images admitted | GKE |
| [Runtime Security with Falco](lab-23-falco-runtime-security.md) | Kernel-level alerts on live container misbehavior; a custom rule | kind |
| [Guardrailed Agentic Kubernetes](lab-24-agentic-guardrails.md) | An agent's mutations denied + audited by policy; reads succeed | GKE |
| [Chaos Engineering with Chaos Mesh](lab-25-chaos-mesh.md) | Kill a Pod (self-heal) and inject latency (surface a hidden outage) | kind |

**Themes covered here that the three-day outline leaves out:** managed-vs-self-managed cluster
architecture, scale testing, service mesh, image-scanning admission control, GPU/accelerator scheduling
(DRA), distributed training and inference autoscaling, HPA/VPA, workload identity and supply-chain
security, runtime security, agentic guardrails, and chaos engineering.

---

Full index: [`../../COURSE-MAP.md`](../../COURSE-MAP.md)
