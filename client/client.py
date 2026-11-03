"""Client: calls the Inventory Service by its Kubernetes Service name (DNS),
never by an individual Pod IP. Prints which Pod answered each request."""
import json
import os
import time
import urllib.request

# "inventory-service" is resolved by cluster DNS to the Service's stable ClusterIP.
URL = os.environ.get("INVENTORY_URL", "http://inventory-service:80/items")
INTERVAL = float(os.environ.get("INTERVAL", "1"))

print(f"client starting, target = {URL}", flush=True)
n = 0
while True:
    n += 1
    try:
        with urllib.request.urlopen(URL, timeout=2) as r:
            body = json.load(r)
        print(f"req #{n}: OK served by pod={body['pod']}", flush=True)
    except Exception as e:  # keep running through failures/replacements
        print(f"req #{n}: ERROR {e}", flush=True)
    time.sleep(INTERVAL)
