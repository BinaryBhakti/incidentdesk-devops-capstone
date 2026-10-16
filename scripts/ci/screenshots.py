"""Headless-Chromium screenshots of the running stack (used by the CI deploy job).

usage: python screenshots.py OUT_DIR
Expects incidentdesk.local, prometheus.local and grafana.local resolving to the NGINX Ingress.
"""

import sys
from pathlib import Path

from playwright.sync_api import sync_playwright

out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)

SHOTS = [
    # name, url, text to wait for (proves the page rendered real data), extra settle ms
    ("app-via-ingress", "http://incidentdesk.local/", "IncidentDesk", 3000),
    ("prometheus-targets", "http://prometheus.local/targets?search=incidentdesk", "incidentdesk", 5000),
    (
        "prometheus-query-up",
        "http://prometheus.local/query?g0.expr=up%7Bnamespace%3D%22incidentdesk%22%7D&g0.tab=table",
        None,
        4000,
    ),
    ("grafana-dashboard", "http://grafana.local/d/incidentdesk?orgId=1&from=now-15m&to=now&kiosk", "Request rate", 12000),
]

with sync_playwright() as p:
    browser = p.chromium.launch()
    page = browser.new_page(viewport={"width": 1600, "height": 1000}, device_scale_factor=1)
    for name, url, wait_text, settle in SHOTS:
        try:
            page.goto(url, wait_until="networkidle", timeout=60000)
            if wait_text:
                page.get_by_text(wait_text).first.wait_for(timeout=30000)
            page.wait_for_timeout(settle)
            page.screenshot(path=str(out / f"{name}.png"), full_page=name.startswith("prometheus"))
            print(f"saved {name}.png  <- {url}")
        except Exception as exc:  # one broken page must not lose the others
            print(f"FAILED {name}: {exc}")
    browser.close()
