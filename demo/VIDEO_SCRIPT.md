# Presentation video: recording script (about 10–12 minutes)

Record with QuickTime (File → New Screen Recording) or OBS at 1080p with your microphone on.
Save the file as `demo/presentation.mp4`. If it is over 100 MB, attach it to a GitHub Release and
link it in `demo/README.md` instead (GitHub rejects files over 100 MB in Git).

Open these tabs before you start:
1. `demo/slides.pdf` (full screen)
2. The repository on GitHub
3. The Actions tab of the repository
4. The latest green run: *Summary* page plus the `evidence-deploy` artifact
5. `demo/screenshots/` in the repo (Prometheus, Grafana, app via Ingress)
6. A terminal in the repo folder

---

## Part 1: Slides (≈3 min)

| Slide | Say |
|---|---|
| Title | "This is IncidentDesk, my DevOps capstone: an incident-management app taken from my laptop to a monitored Kubernetes deployment." |
| 1 Overview | What the app does: incidents, severities, statuses, KPIs. The goal is the delivery chain, not just the app. |
| 2 Stack | Walk through the four groups: app, delivery, platform, observability. |
| 3 Architecture | Follow one commit through the diagram, left to right. |
| 4 CI/CD | Five jobs. Every stage is a gate, and the image tag is the commit SHA. |
| 5 DevSecOps | gitleaks on history, Trivy on both images before push. Explain `--ignore-unfixed`. |
| 6 Terraform | VPC with 2 public + 2 private subnets, NAT, EKS + node group in ap-south-1. Be upfront: no AWS account, so CI runs it on LocalStack; EKS is in the plan but not applied. |
| 7 K8s + Helm | Deployments with 2 replicas, probes, StatefulSet, Services, Ingress routing, HPA. |
| 8 Observability | /metrics → Prometheus → Grafana; the 6 alert rules. |
| 9 Troubleshooting | Broken image and broken Service, and how you find each. |
| 10 Learnings | Pick 3 and say them in your own words. |

## Part 2: Codebase (≈1.5 min)

In the GitHub repo or your editor, show:
- folder structure: `backend/ frontend/ docker-compose.yml k8s/ helm/ terraform/ monitoring/ gitops/ troubleshooting/ .github/workflows/`
- `backend/app/main.py`: the endpoints, `/health` vs `/ready`
- `backend/alembic/versions/0001_create_incidents.py`
- `backend/tests/conftest.py`: the separate test database
- `backend/Dockerfile` and `frontend/Dockerfile`: multi-stage builds, `USER 10001` / `USER 101`
- `helm/incidentdesk/templates/ingress.yaml`: `/api` → backend, `/` → frontend
- `terraform/eks.tf`

## Part 3: CI/CD live (≈2 min)

Make a small visible change and push it:

```bash
# e.g. change the dashboard subtitle in frontend/src/main.jsx, then:
git add frontend/src/main.jsx
git commit -m "Frontend: clarify dashboard subtitle"
git push
```

- Open Actions and show the new run start. Click into **Test** and show pytest running.
- The whole run takes about 15 minutes, so **cut or speed up the recording** here, or switch to the
  previous green run.
- In the green run show: the job graph (all green), the **Trivy** step output, the **Push to GHCR**
  step, the summary (`kubectl get pods`), and the artifacts.
- Show the GHCR packages page with the SHA tag.

## Part 4: Terraform (≈1.5 min)

- Open the **Terraform** job: `init`, `validate`, then `plan` with `aws_eks_cluster.main[0]` and
  `aws_eks_node_group.default[0]` "will be created".
- Then `apply` (VPC, 4 subnets, NAT…), `state list`, and `destroy` ending with an empty state.
- Say: "There's no AWS console screenshot because I had no AWS account. With credentials, the same
  code runs `terraform apply` in ap-south-1."

## Part 5: Argo CD (≈1 min)

- Open `gitops/application-ci.yaml`: repo, path, auto-sync, prune, self-heal.
- In the deploy job open the **Argo CD** step (or `demo/evidence/argocd.txt`): `Synced / Healthy`,
  then the Service deleted by hand and recreated by Argo CD.

## Part 6: Kubernetes (≈1.5 min)

- `demo/evidence/kubectl-get-all.txt` (or the deploy job's *Cluster state* step):
  `kubectl get pods`, all Running with 2 backend + 2 frontend; `get svc`; `get ingress`;
  `get hpa`; `helm list`.
- `demo/screenshots/app-via-ingress.png`: the app served through the Ingress hostname.
- Troubleshooting step: ImagePullBackOff → describe → fix; empty endpoints → labels → fix.

## Part 7: Prometheus + Grafana (≈1 min)

- `demo/screenshots/prometheus-targets.png`: IncidentDesk pods **UP**.
- `demo/evidence/prometheus-grafana.txt`: PromQL results (`up`, request rate per route).
- `demo/screenshots/grafana-dashboard.png`: request rate, latency, pods up.

Close with: "One commit, tested, scanned, pushed with a SHA tag, deployed with Helm, exposed via
Ingress, autoscaled, monitored, and repaired when it broke. Thank you."
