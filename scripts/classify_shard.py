#!/usr/bin/env python3
"""classify_shard.py — GitHub Actions 用的【无状态分片】分类器。

与 classify_domains.py 的区别：
  * 不读写 domain-state.tsv（每次 runner 都是干净的），不做 nx 过期重试
  * 只处理分给自己的那 1/N 域名，输出  domain<TAB>category  TSV
  * 境外 runner 直连公共 UDP DNS，不用 +https（DoH 是为绕国内劫持设计的）
  * 不会触碰家里 wpad-02 / VPS 的 DNS —— 避免 2026-11-02 全家断网事故

用法：
  classify_shard.py --conf data/result/adhole.conf \
      --shard 0/5 --qps 40 --workers 40 --out shard-0.tsv \
      --geoip data/state/geoip-cn.json
"""
import argparse
import ipaddress
import json
import re
import subprocess
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

DOMAIN_RE = re.compile(r'^local-zone:\s+"([^"]+)"\s+always_null', re.M)
# 境外 runner 直接可用；必要时可用 --dns 覆盖
DNS_POOL = ["8.8.8.8", "1.1.1.1", "223.5.5.5", "119.29.29.29"]


def log(m):
    print(f"[{time.strftime('%H:%M:%S')}] {m}", flush=True)


def load_geoip(path):
    d = json.load(open(path))
    nets = []
    for r in d.get("rules", []):
        for c in r.get("ip_cidr", []):
            try:
                n = ipaddress.ip_network(c, strict=False)
                if n.version == 4:
                    nets.append(n)
            except ValueError:
                pass
    log(f"  geoip-cn: {len(nets)} IPv4 段")
    return nets


def is_cn(ip, nets):
    try:
        a = ipaddress.ip_address(ip)
    except ValueError:
        return False
    return a.version == 4 and any(a in n for n in nets)


def resolve_one(domain, dns, timeout=4):
    try:
        r = subprocess.run(
            ["dig", "+short", "+time=%d" % (timeout - 1), "+tries=1",
             "A", domain, "@" + dns],
            capture_output=True, text=True, timeout=timeout)
        for l in r.stdout.strip().splitlines():
            l = l.strip().rstrip(".")
            if l and l[0].isdigit():
                try:
                    return str(ipaddress.ip_address(l))
                except ValueError:
                    pass
    except Exception:
        pass
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--conf", required=True)
    ap.add_argument("--shard", required=True, help="形如 0/5")
    ap.add_argument("--qps", type=int, default=40)
    ap.add_argument("--workers", type=int, default=40)
    ap.add_argument("--out", required=True)
    ap.add_argument("--geoip", required=True)
    ap.add_argument("--dns", action="append", help="可多次指定，覆盖默认 DNS 池")
    a = ap.parse_args()

    i, n = (int(x) for x in a.shard.split("/"))
    assert 0 <= i < n and n > 0, "bad --shard"

    domains = sorted(set(DOMAIN_RE.findall(
        Path(a.conf).read_text(errors="ignore"))))
    mine = domains[i::n]                      # 稳定、均匀、可复现的切片
    log(f"  shard {i}/{n}: 总 {len(domains)} → 本片 {len(mine)} 域名")

    nets = load_geoip(a.geoip)
    pool = a.dns or DNS_POOL
    cyc = __import__("itertools").cycle(pool)

    interval = 1.0 / a.qps
    lock = threading.Lock()
    next_slot = [time.monotonic()]

    def work(d):
        with lock:
            now = time.monotonic()
            wait = next_slot[0] - now
            next_slot[0] = (next_slot[0] + interval) if wait > 0 else (now + interval)
        if wait > 0:
            time.sleep(wait)
        ip = resolve_one(d, next(cyc))
        cat = "cn" if (ip and is_cn(ip, nets)) else ("noncn" if ip else "nx")
        return d, cat

    done = 0
    t0 = time.time()
    with open(a.out, "w") as f, ThreadPoolExecutor(max_workers=a.workers) as ex:
        futs = [ex.submit(work, d) for d in mine]
        for fu in as_completed(futs):
            d, cat = fu.result()
            f.write(f"{d}\t{cat}\n")
            done += 1
            if done % 10000 == 0:
                log(f"  {done}/{len(mine)}  ({time.time()-t0:.0f}s)")
    log(f"  shard {i}/{n} 完成: {done} 条 → {a.out}  用时 {time.time()-t0:.0f}s")


if __name__ == "__main__":
    main()
