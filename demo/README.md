# demo/

| File | What |
|---|---|
| [`presentation.mp4`](presentation.mp4) | **Presentation video**: slides first, then the live walkthrough ([script](VIDEO_SCRIPT.md)) |
| [`slides.pdf`](slides.pdf) | Slide deck, 11 slides (source: [`slides.html`](slides.html)) |
| [`screenshots/`](screenshots) | UI screenshots taken by headless Chromium inside the CI deploy job, plus terminal renders of the CI logs |
| [`evidence/`](evidence) | Raw logs downloaded from the GitHub Actions run artifacts (`evidence-test`, `evidence-build`, `evidence-terraform`, `evidence-deploy`) |

**Source run:** RUN_LINK

Terminal screenshots (`pytest.png`, `trivy-scan.png`, `terraform-plan.png`, `kubectl-get-all.png`)
are renders of the logs in `evidence/`. Those commands ran non-interactively on a GitHub
runner, so there was no terminal window to photograph. UI screenshots (`app-via-ingress.png`,
`prometheus-targets.png`, `grafana-dashboard.png`) are real browser captures from the same run.
