# demo/

| File | What |
|---|---|
| [`presentation.mp4`](presentation.mp4) | **Presentation video** (5 min 54 s, 1080p, narrated): walks through all 13 slides, including the CI evidence screenshots. Narration is synthesized speech (macOS voice) from a script written for this project |
| [`presentation.pptx`](presentation.pptx) | **PowerPoint deck**, 13 slides with real CI screenshots and speaker notes |
| [`slides.pdf`](slides.pdf) | Shorter PDF version, 11 slides (source: [`slides.html`](slides.html)) |
| [`screenshots/`](screenshots) | UI screenshots taken by headless Chromium inside the CI deploy job, plus terminal renders of the CI logs |
| [`evidence/`](evidence) | Raw logs downloaded from the GitHub Actions run artifacts (`evidence-test`, `evidence-build`, `evidence-terraform`, `evidence-deploy`) |

**Source run:** [run #5](https://github.com/BinaryBhakti/incidentdesk-devops-capstone/actions/runs/38940190952): all 5 jobs green

Terminal screenshots (`pytest.png`, `trivy-scan.png`, `terraform-plan.png`, `kubectl-get-all.png`)
are renders of the logs in `evidence/`. Those commands ran non-interactively on a GitHub
runner, so there was no terminal window to photograph. `app-via-ingress.png` is a real headless-Chromium capture from the same run. `github-actions-run.png` and
`commit-history.png` are headless-Chrome captures of the public GitHub pages. The Prometheus and Grafana UIs
did not render in CI; see Known issues in the root README.
