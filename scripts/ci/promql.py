"""Print the result of a PromQL instant query as a small table (used by the CI deploy job).

usage: python promql.py 'QUERY' label1,label2,...
"""

import json
import sys
import urllib.parse
import urllib.request

query, labels = sys.argv[1], sys.argv[2].split(",")
url = "http://prometheus.local/api/v1/query?" + urllib.parse.urlencode({"query": query})
data = json.load(urllib.request.urlopen(url, timeout=20))["data"]["result"]
for r in data:
    m = r["metric"]
    cols = [f"{m.get(label, ''):<45}" for label in labels]
    print(" ".join(cols), "value =", r["value"][1])
if not data:
    print("(no series)")
