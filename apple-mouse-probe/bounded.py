"""Bound one child command on the isolated macOS test runner."""
import os, signal, subprocess, sys, time
limit=float(sys.argv[1]); args=sys.argv[2:]
print('BEGIN',args,'limitSeconds',limit,flush=True)
p=subprocess.Popen(args,start_new_session=True)
try:
    code=p.wait(timeout=limit)
except subprocess.TimeoutExpired:
    print('TIMEOUT',args,flush=True)
    os.killpg(p.pid,signal.SIGTERM)
    try:p.wait(timeout=5)
    except subprocess.TimeoutExpired:
        os.killpg(p.pid,signal.SIGKILL);p.wait()
    code=124
print('END',args,'exitCode',code,flush=True)
raise SystemExit(code)
