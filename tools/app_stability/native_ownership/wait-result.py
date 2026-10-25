import argparse
import json
import time
import urllib.request

p=argparse.ArgumentParser();p.add_argument('status',choices=['waiting','passed']);p.add_argument('--timeout',type=int,default=240);a=p.parse_args()
until=time.monotonic()+a.timeout
while time.monotonic()<until:
    try:
        with urllib.request.urlopen('http://127.0.0.1:8767/status',timeout=5) as r:d=json.load(r)
        if d['status']=='failed':raise SystemExit('native ownership case failed: '+str(d.get('failures')))
        if d['status']==a.status:
            print(json.dumps({'status':d['status'],'passed':len(d.get('passed',[]))}));break
    except (OSError,ValueError):pass
    time.sleep(1)
else:raise SystemExit('native ownership result timed out')
