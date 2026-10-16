# IncidentDesk — DevOps Final Capstone (Session 21)

IncidentDesk is a small incident-management SaaS: engineers open incidents (title, service,
severity SEV1–SEV4), track them through *open → investigating → resolved*, and see live KPIs.
This repository takes it from a developer laptop to a monitored, autoscaled Kubernetes
deployment:

```
Developer ─► Git/GitHub ─► GitHub Actions ─┬─ pytest + ruff + frontend build      (quality gate)
                                           ├─ gitleaks                             (secret scan)
                                           ├─ docker build ×2 ─► Trivy (HIGH/CRITICAL gate) ─► GHCR :<commit-sha>
                                           ├─ Terraform: VPC + EKS plan, apply/destroy (LocalStack)
                                           └─ deploy: kind ─► Helm ─► Ingress ─► HPA ─► Prometheus ─► Grafana ─► Argo CD
```

**Domain:** incident management (not the TaskBoard reference). The DevOps layer follows the
Session 21 architecture.

**Evidence:** every log and screenshot in [`demo/`](demo) comes from one real GitHub Actions run
of this repository, [run #5](https://github.com/BinaryBhakti/incidentdesk-devops-capstone/actions/runs/38940190952) (all 5 jobs green). Links are in [Evidence](#evidence).

---

## Architecture

![architecture](architecture.svg)

| Layer | What | Where |
|---|---|---|
| Frontend | React 19 + Vite, served by unprivileged nginx, which proxies `/api` | [`frontend/`](frontend) |
| Backend | FastAPI, SQLAlchemy 2, Pydantic, Prometheus instrumentator | [`backend/app/`](backend/app) |
| Database | PostgreSQL 16, schema owned by Alembic | [`backend/alembic/versions/`](backend/alembic/versions) |
| Tests | pytest, 13 cases against a separate test PostgreSQL | [`backend/tests/`](backend/tests) |
| Containers | multi-stage Dockerfiles, non-root (uid 10001 / 101), Compose | [`backend/Dockerfile`](backend/Dockerfile), [`frontend/Dockerfile`](frontend/Dockerfile), [`docker-compose.yml`](docker-compose.yml) |
| CI/CD | GitHub Actions: test → build → Trivy → GHCR → deploy, plus Terraform | [`.github/workflows/ci.yml`](.github/workflows/ci.yml) |
| Security | Trivy, gitleaks, Semgrep and Bandit configs | [`security/`](security) |
| IaC | Terraform: VPC (2 public + 2 private subnets, NAT), EKS + node group, S3, IAM | [`terraform/`](terraform) |
| Kubernetes | namespace + plain manifests; Helm chart (Deployments, StatefulSet + PVC, Services, Ingress, HPA, PDB, probes) | [`k8s/`](k8s), [`helm/incidentdesk/`](helm/incidentdesk) |
| GitOps | Argo CD Application syncing the chart from Git | [`gitops/`](gitops) |
| Observability | Prometheus, Grafana, alert rules, dashboard as code | [`monitoring/`](monitoring) |
| Troubleshooting | broken image, broken Service selector, and 6 Helm fault injections | [`troubleshooting/`](troubleshooting) |

## Tech stack

Python 3.12 · FastAPI · SQLAlchemy · Alembic · PostgreSQL 16 · pytest · ruff · React 19 · Vite ·
nginx · Docker / Compose · GitHub Actions · GitHub Container Registry · Trivy · gitleaks ·
Terraform (AWS provider 6) · AWS VPC + EKS (LocalStack in CI) · Kubernetes (kind) · Helm ·
NGINX Ingress · metrics-server + HPA · Prometheus · Grafana · Argo CD · Playwright (screenshots).

---

## 1. Application

**Backend API** ([`backend/app/main.py`](backend/app/main.py)). Swagger is at `/docs`.

| Method | Path | Purpose |
|---|---|---|
| GET | `/health` | liveness: process is up, no DB call |
| GET | `/ready` | readiness: `SELECT 1` against PostgreSQL |
| GET | `/metrics` | Prometheus metrics (RED + `incidents_created_total`, `incidents_resolved_total`) |
| GET | `/api/incidents` | list incidents, filters `status`, `severity` |
| GET | `/api/incidents/{id}` | one incident |
| POST | `/api/incidents` | create |
| PUT | `/api/incidents/{id}` | update / resolve / reopen |
| DELETE | `/api/incidents/{id}` | delete |
| GET | `/api/incidents/stats` | KPI counters for the dashboard |

**Frontend** ([`frontend/src`](frontend/src)): a responsive dashboard with KPI cards, filters,
a severity-coloured incident table and a create/resolve flow. The browser only calls the
relative path `/api/...`: nginx in Compose, or the Ingress in Kubernetes, routes it.

**Database:** the `incidents` table is created by Alembic migration
[`0001_create_incidents.py`](backend/alembic/versions/0001_create_incidents.py). The container
runs `alembic upgrade head` before uvicorn starts.

## 2. Run locally

```bash
docker compose up --build         # postgres + backend + frontend
# UI       http://localhost:3000
# API docs http://localhost:8000/docs     health  http://localhost:8000/health
docker compose down -v            # stop and delete the database volume
```

Backend without Docker:

```bash
cd backend && python -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
export DATABASE_URL='postgresql+psycopg://incidentdesk:local-dev-only@localhost:5432/incidentdesk'
alembic upgrade head && uvicorn app.main:app --reload --port 8000
```

## 3. Tests

```bash
cd backend
export TEST_DATABASE_URL='postgresql+psycopg://test:test@localhost:5432/incidentdesk_test'
pytest -v
```

[`tests/conftest.py`](backend/tests/conftest.py) refuses to run without `TEST_DATABASE_URL`, so
the suite can never touch the application database. It migrates a fresh schema and truncates
between tests. In CI the database is a throwaway `postgres:16-alpine` service container. The 13
tests cover health/ready, create, list + filters, get, update/resolve, delete, stats, 404s and
validation errors. Coverage is gated at 85% ([`pytest.ini`](backend/pytest.ini)).

## 4. Docker

- **Backend:** `python:3.12-slim` build stage installs wheels; the runtime stage copies only the
  venv and app, runs as **uid 10001**, and the entrypoint runs Alembic then uvicorn.
- **Frontend:** multi-stage. `node:22-alpine` runs `npm ci && npm run build`, then
  `nginx-unprivileged` serves `dist/` as **uid 101** and proxies `/api` to `BACKEND_URL`.
- **Compose:** Postgres has a healthcheck. The backend waits for `service_healthy`, and the
  frontend waits for a healthy backend.

## 5. CI/CD pipeline ([`.github/workflows/ci.yml`](.github/workflows/ci.yml))

It triggers on every push to `main` (docs-only changes are skipped), on pull requests, and on
manual dispatch.

| Job | What it does | Fails the build when |
|---|---|---|
| **Test** | ruff lint + format check, `pytest -v` against Postgres, `npm ci && npm run build` | a test fails, coverage < 85%, lint error, frontend build error |
| **Secret scan** | gitleaks over the full Git history | any secret is found |
| **Build, scan, push** | builds both images tagged with **`${{ github.sha }}`**, runs Trivy on both, pushes to GHCR on `main` | Trivy finds a fixable HIGH/CRITICAL CVE |
| **Terraform** | fmt, init, validate, **plan (VPC + EKS)**, apply, state list, **destroy** against LocalStack | invalid HCL, plan/apply error |
| **Deploy** | kind (2 nodes), NGINX Ingress, metrics-server, Prometheus, Grafana; `helm upgrade --install`; smoke test through the Ingress; load test; HPA; PromQL checks; Playwright screenshots; Argo CD sync; troubleshooting lab | rollout, Ingress or API check fails |

Image tags are the full commit SHA, so every image in GHCR traces back to exactly one commit:

```
ghcr.io/binarybhakti/incidentdesk-capstone-backend:<commit-sha>
ghcr.io/binarybhakti/incidentdesk-capstone-frontend:<commit-sha>
```

## 6. DevSecOps: Trivy

The **Build, scan, push** job runs `trivy image --severity HIGH,CRITICAL --ignore-unfixed
--exit-code 1` on **both** images *before* the push step. A finding stops the job, and nothing
reaches GHCR. Accepted risks live in [`security/.trivyignore`](security/.trivyignore), each with
a reason and a review date.

**What the scan means:** Trivy inventories the OS packages (Debian for the backend, Alpine
for the frontend) and the language dependencies (Python wheels, npm lockfile) in each image. It
matches them against vulnerability databases and reports any HIGH or CRITICAL CVE that has a
fixed version available. See the [scan output](demo/evidence/trivy-scan.txt): a clean result
means that at build time no fixable HIGH/CRITICAL CVE existed in either image. It does not mean
the images are "secure": unfixed CVEs, runtime behaviour and application logic are covered by
other layers (SAST, dependency audit, secret scan, runtime controls).

## 7. Terraform: AWS VPC + EKS ([`terraform/`](terraform))

| File | Creates |
|---|---|
| [`network.tf`](terraform/network.tf) | VPC `10.20.0.0/16`, **2 public + 2 private subnets** across 2 AZs, IGW, NAT gateway, route tables |
| [`eks.tf`](terraform/eks.tf) | IAM roles for the cluster and nodes, **EKS cluster** (v1.33), **managed node group** (2 × t3.medium, private subnets) |
| [`security.tf`](terraform/security.tf) | security groups: web 80/443, db 5432 only from web |
| [`storage.tf`](terraform/storage.tf), [`iam.tf`](terraform/iam.tf) | versioned, encrypted backup bucket with lifecycle rules; least-privilege backup role; DynamoDB state-lock table |

Default region is **`ap-south-1`**. Only [`terraform.tfvars.example`](terraform/terraform.tfvars.example)
is committed. `terraform.tfvars`, state and `.terraform/` are git-ignored, and gitleaks checks
every commit.

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform plan && terraform apply
aws eks update-kubeconfig --region ap-south-1 --name incidentdesk-dev-eks   # printed as output kubeconfig_command
terraform destroy
```

**How it was run:** there was no AWS account for this project, so CI runs Terraform against
**LocalStack** (`use_localstack=true`). `terraform plan` runs with `enable_eks=true` and shows the
full design, VPC through EKS node group. `apply` and `destroy` run with `enable_eks=false`,
because EKS is a LocalStack *Pro* API. The VPC, 4 subnets, NAT, route tables, security groups,
S3, IAM and DynamoDB are created, listed and torn down for real. See
[plan](demo/evidence/terraform-plan.txt), [apply](demo/evidence/terraform-apply.txt) and
[destroy](demo/evidence/terraform-destroy.txt).

## 8. Kubernetes + Helm

```bash
kubectl apply -f k8s/namespace.yaml
helm upgrade --install incidentdesk ./helm/incidentdesk -n incidentdesk \
  -f helm/incidentdesk/values-dev.yaml --set postgres.password="$(openssl rand -hex 16)"
kubectl get pods,svc,ingress,hpa -n incidentdesk
helm list -n incidentdesk
```

The chart ([`helm/incidentdesk`](helm/incidentdesk)) renders:
- **Deployments**: backend and frontend, **2 replicas each** by default. Rolling updates use
  `maxUnavailable: 0`. Probes: startup and liveness on `/health`, readiness on `/ready`. Pods run
  non-root with a read-only root filesystem.
- **StatefulSet** PostgreSQL with a PVC from `volumeClaimTemplates`, plus a headless Service
- **ClusterIP Services** for backend (8000) and frontend (80 → 8080)
- **Ingress** (`ingressClassName: nginx`, host `incidentdesk.local`): **`/` → frontend, `/api` → backend**
- **HPA**: backend 2–5 replicas at 60% CPU (needs metrics-server and resource requests, both set)
- **PDB**, **ConfigMap**, **Secret**: no default password, the chart refuses to render without one
- Values files: [`values.yaml`](helm/incidentdesk/values.yaml) (prod-shaped),
  [`values-dev.yaml`](helm/incidentdesk/values-dev.yaml),
  [`values-ci.yaml`](helm/incidentdesk/values-ci.yaml), and
  [`values-prod.yaml`](helm/incidentdesk/values-prod.yaml) (TLS, existingSecret)

Plain manifests for the same objects are in [`k8s/`](k8s) (`k8s/99-apply.sh`).

**GitOps:** [`gitops/application-ci.yaml`](gitops/application-ci.yaml) is an Argo CD Application
that syncs `helm/incidentdesk` from this repo's `main` with auto-sync, prune and self-heal. In the
CI run, Argo CD deployed the chart into `incidentdesk-gitops`: application **Healthy**, all 5
pods Running. Its sync status ended **Unknown**, though, and the self-heal test (delete a Service
by hand) was not recreated within 90 s. See [log](demo/evidence/argocd.txt) and Known issues.

## 9. Observability

- The backend exposes **`/metrics`** via `prometheus-fastapi-instrumentator`:
  `http_requests_total`, `http_request_duration_seconds`, and the business counters.
- **Prometheus** ([`monitoring/prometheus-values.yaml`](monitoring/prometheus-values.yaml)) scrapes
  pods annotated `prometheus.io/scrape` (the chart adds these) plus kube-state-metrics, with 6
  alert rules ([`alert-rules.yml`](monitoring/alert-rules.yml)).
- **Grafana** ([`monitoring/grafana-values.yaml`](monitoring/grafana-values.yaml)) is provisioned
  from code with the Prometheus datasource and the *IncidentDesk golden signals* dashboard
  ([`dashboards/incidentdesk.json`](monitoring/dashboards/incidentdesk.json)): pods up, request
  rate, error ratio, p50/p95/p99 latency, CPU and memory per pod, HPA replicas, restarts.
- A ServiceMonitor template is in the chart (`metrics.serviceMonitor.enabled`) for clusters
  running kube-prometheus-stack.

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana-community https://grafana-community.github.io/helm-charts
helm upgrade --install prometheus prometheus-community/prometheus -n monitoring --create-namespace -f monitoring/prometheus-values.yaml
helm upgrade --install grafana grafana-community/grafana -n monitoring -f monitoring/grafana-values.yaml
kubectl -n monitoring port-forward svc/grafana 3000:80      # http://localhost:3000/d/incidentdesk
```

## 10. Troubleshooting lab

| Lab | Symptom | Diagnose with | Root cause / fix |
|---|---|---|---|
| [`broken-image.yaml`](troubleshooting/broken-image.yaml) | `ErrImagePull` / `ImagePullBackOff` | `kubectl describe pod`, `get events` | tag does not exist → `kubectl set image` to the CI SHA |
| [`broken-service.yaml`](troubleshooting/broken-service.yaml) | Service has **no endpoints** | `get endpoints`, `get pods --show-labels` | selector `component=api` ≠ pod label `backend` → fix the selector |
| [`01`–`06`](troubleshooting) Helm faults | rotated DB password, wrong readiness path, bad tag, HPA without requests, Service selector, Ingress port | see [`troubleshooting/README.md`](troubleshooting/README.md) | |

The first two run in CI on every deploy: break, observe, fix ([log](demo/evidence/troubleshooting.txt)).

---

## Evidence

All of this comes from [run #5](https://github.com/BinaryBhakti/incidentdesk-devops-capstone/actions/runs/38940190952).

| Rubric item | Evidence |
|---|---|
| pytest passing (`-v`) | [`demo/evidence/pytest.txt`](demo/evidence/pytest.txt) · ![](demo/screenshots/pytest.png) |
| Frontend build | [`demo/evidence/frontend-build.txt`](demo/evidence/frontend-build.txt) |
| Docker images, non-root | [`demo/evidence/docker-build.txt`](demo/evidence/docker-build.txt) |
| Trivy scan | [`demo/evidence/trivy-scan.txt`](demo/evidence/trivy-scan.txt) · ![](demo/screenshots/trivy-scan.png) |
| GHCR push (SHA tags) | [`demo/evidence/ghcr-push.txt`](demo/evidence/ghcr-push.txt) |
| Pipeline green | ![](demo/screenshots/github-actions-run.png) |
| Terraform plan / apply / destroy | [`plan`](demo/evidence/terraform-plan.txt) · [`apply`](demo/evidence/terraform-apply.txt) · [`destroy`](demo/evidence/terraform-destroy.txt) · ![](demo/screenshots/terraform-plan.png) |
| `kubectl get pods/svc/ingress/hpa`, `helm list` (HPA scaled backend 2 → 5 under load) | [`demo/evidence/kubectl-get-all.txt`](demo/evidence/kubectl-get-all.txt) · ![](demo/screenshots/kubectl-get-all.png) |
| App through the Ingress | ![](demo/screenshots/app-via-ingress.png) |
| `/metrics`, Prometheus targets UP (5/5 backend pods `up = 1`), live req/s per route, Grafana API + provisioned dashboard | [`backend-metrics.txt`](demo/evidence/backend-metrics.txt) · [`prometheus-grafana.txt`](demo/evidence/prometheus-grafana.txt) · ![](demo/screenshots/metrics-and-promql.png) |
| Argo CD (Healthy, sync Unknown; see Known issues) | [`demo/evidence/argocd.txt`](demo/evidence/argocd.txt) · ![](demo/screenshots/argocd.png) |
| Troubleshooting lab | [`demo/evidence/troubleshooting.txt`](demo/evidence/troubleshooting.txt) · ![](demo/screenshots/troubleshooting.png) |
| Terraform apply → destroy | ![](demo/screenshots/terraform-apply-destroy.png) |
| Commit history | ![](demo/screenshots/commit-history.png) |

## Known issues and limitations

- **No real AWS account.** Terraform targets real AWS by default, but it was executed against
  LocalStack in CI. The EKS cluster and node group appear in `terraform plan` and were **not
  created**, because EKS is LocalStack Pro-only. There is no AWS Console screenshot for the same
  reason. With credentials, `terraform apply` in `ap-south-1` creates everything (EKS takes about
  15 minutes and costs roughly $0.10/h for the control plane plus nodes and NAT). Run
  `terraform destroy` afterwards.
- **Kubernetes runs in kind inside the CI runner**, not EKS. The Helm chart is the same one you
  would deploy to EKS (swap the Ingress class for the AWS Load Balancer Controller there). The
  cluster exists only for the duration of the job, so the live demo is the Actions run and its
  artifacts.
- In-cluster PostgreSQL with a PVC is fine for a demo. For production, Amazon RDS (Multi-AZ,
  automated backups) is the better trade-off.
- The HPA scales on CPU only. In the evidence run the load test pushed the backend to 342% of
  its CPU request, and the HPA scaled it from 2 to 5 replicas (its maximum).
- **No Prometheus/Grafana UI screenshots.** Headless Chromium in CI loaded the IncidentDesk UI
  through the Ingress fine, but the Prometheus and Grafana web UIs never rendered (blank page /
  "failed to load its application files"), through both `port-forward` and the Ingress. What is
  proven instead: the Prometheus API shows every backend target `up = 1` with live per-route
  request rates, and the Grafana API (`/api/health`, `/api/search`) shows Grafana healthy with
  the *IncidentDesk — golden signals* dashboard provisioned. To get the screenshots, run the
  [observability commands](#9-observability) on any cluster and open the two UIs in a browser.
- **Argo CD:** it rendered and deployed the chart (Healthy, 5/5 pods Running), but the sync
  status settled on *Unknown* rather than *Synced*, and the hand-deleted Service was not
  recreated within 90 s. The step is `continue-on-error`, which is why the green run shows one
  error annotation. The root cause was not investigated before the deadline.
- Grafana runs with anonymous viewer access, a demo convenience. Disable it in any shared
  environment.

## Repository layout

```
backend/        FastAPI app, Alembic, pytest            frontend/     React + Vite, nginx
docker-compose.yml                                      k8s/          namespace + plain manifests
helm/incidentdesk/   Helm chart                         terraform/    VPC + EKS (+ LocalStack switch)
monitoring/     Prometheus/Grafana values, alerts, dashboard
gitops/         Argo CD Applications                    security/     Trivy, gitleaks, Semgrep, Bandit
troubleshooting/  broken manifests + Helm faults        scripts/      load test, CI screenshots
demo/           slides, video, screenshots, evidence    .github/workflows/ci.yml
```
