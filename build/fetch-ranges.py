#!/usr/bin/env python3
"""Resume one release-asset download using disjoint, independently resumable HTTP ranges."""
import concurrent.futures as cf
import datetime
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

url, name, total = sys.argv[1:]
dest = Path(name)
total = int(total)
if dest.is_file():
    sys.exit(0)
part = Path(name+'.part')
part.touch(exist_ok=True)
chunks = Path(name+'.ranges')
chunks.mkdir(exist_ok=True)
seed_file = chunks / 'seed'
if not seed_file.exists():
    stem = chunks / 'seed.tmp'
    stem.write_text(str(part.stat().st_size))
    stem.replace(seed_file)
seed = int(seed_file.read_text())
if not 0 <= seed <= part.stat().st_size <= total:
    raise RuntimeError('inconsistent download lengths')
width = 8 * 1024**2
registered = part.stat().st_size
ranges = [(i, min(i+width,total)-1) for i in range(seed,total,width)]

def download(bounds):
    lo, hi = bounds
    out = chunks / str(lo)
    tmp = chunks / f'{lo}.tmp'
    headers = chunks / f'{lo}.headers'
    failures = 0
    if hi < registered:
        return
    out.touch(exist_ok=True)
    while (start := lo + out.stat().st_size) <= hi:
        tmp.write_bytes(b'')
        headers.write_bytes(b'')
        result = subprocess.run(['curl', '-fsSL', '--connect-timeout','15','--max-time','110',
            '--speed-time','17','--speed-limit','70000', '-r',f'{start}-{hi}',
            '-D',str(headers),'-w','%{http_code}',url,'-o',str(tmp)], capture_output=True)
        n = tmp.stat().st_size
        expect = rf'^content-range:\s*bytes {start}-{hi}/{total}\s*$'.encode()
        if result.stdout == b'206' and 0 < n <= hi-start+1 and re.search(expect, headers.read_bytes(), re.I|re.M):
            with out.open('ab') as writer, tmp.open('rb') as reader:
                shutil.copyfileobj(reader, writer, 1024**2)
            failures = 0
        else:
            failures += 1
            if failures == 7:
                raise RuntimeError(f'failed at {start}-{hi}: {result.returncode} {result.stderr.decode().strip()}')
            time.sleep(failures)
    tmp.unlink(missing_ok=True)
    headers.unlink(missing_ok=True)
    print(f'{datetime.datetime.now().astimezone().isoformat(timespec="seconds")} verified range {lo}-{hi}', flush=True)

# Different ranges only; no second full download. Keep partial range data after interruptions.
with cf.ThreadPoolExecutor(max_workers=6) as pool:
    pending = {pool.submit(download, r): r for r in ranges if r[1] >= registered}
    for future in cf.as_completed(pending):
        future.result()
with part.open('ab') as writer:
    for lo, hi in ranges:
        if hi < registered:
            continue
        with (chunks/str(lo)).open('rb') as reader:
            reader.seek(max(registered-lo,0))
            shutil.copyfileobj(reader, writer, 1024**2)
        writer.flush()
        (chunks/str(lo)).unlink()
    writer.flush()
    os.fsync(writer.fileno())
assert part.stat().st_size == total
part.replace(dest)
shutil.rmtree(chunks)
