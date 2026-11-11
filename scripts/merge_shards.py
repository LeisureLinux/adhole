#!/usr/bin/env python3
"""merge_shards.py — 合并各分片 TSV，导出 adhole cn/noncn/full 三份 conf。

输入：shard-*.tsv（每行 domain<TAB>category，category ∈ cn/noncn/nx）
输出：data/state/{adhole-cn.conf, adhole-noncn.conf, adhole-full.conf}
      + domestic-domains.txt 由本机 gen-domestic-domains.sh 生成（依赖 geosite，不在 CI 做）
"""
import argparse
import time
from pathlib import Path

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--shards", required=True, help="glob，如 'artifacts/*/shard-*.tsv'")
    ap.add_argument("--out", required=True)
    ap.add_argument("--min-domains", type=int, default=100000,
                    help="合并结果少于此数则拒绝导出（防分片不全）")
    a = ap.parse_args()

    import glob
    files = sorted(glob.glob(a.shards, recursive=True))
    if not files:
        raise SystemExit(f"ERROR: 没有匹配的分片: {a.shards}")

    cat = {}
    for fp in files:
        n = 0
        for line in Path(fp).read_text(errors="ignore").splitlines():
            if "\t" not in line:
                continue
            d, c = line.rsplit("\t", 1)
            if c in ("cn", "noncn", "nx"):
                cat[d] = c
                n += 1
        print(f"  {fp}: {n} 条")
    if len(cat) < a.min_domains:
        raise SystemExit(f"ERROR: 合并结果仅 {len(cat)} 条，疑似分片不全，拒绝导出")

    out = Path(a.out); out.mkdir(parents=True, exist_ok=True)
    hdr = ("# Syntax: unbound\n# Source: GitHub Actions adhole classify (stateless shards)\n"
           f"# UpdateTime: {time.strftime('%Y-%m-%dT%H:%M:%S%z')}\n")
    counts = {"cn": 0, "noncn": 0, "nx": 0}
    with (out / "adhole-cn.conf").open("w") as fc, \
         (out / "adhole-noncn.conf").open("w") as fn, \
         (out / "adhole-full.conf").open("w") as ff:
        for p in (fc, fn, ff):
            p.write(hdr)
        ff.write(f"# 条目数: {sum(1 for c in cat.values() if c != 'nx')}\n")
        for d in sorted(cat):
            c = cat[d]; counts[c] += 1
            if c == "cn":
                fc.write(f'local-zone: "{d}" always_null\n')
                ff.write(f'local-zone: "{d}" always_null\n')
            elif c == "noncn":
                fn.write(f'local-zone: "{d}" always_null\n')
                ff.write(f'local-zone: "{d}" always_null\n')
    print(f"  合并 {len(files)} 分片 / {len(cat)} 域名 → cn={counts['cn']} "
          f"noncn={counts['noncn']} nx={counts['nx']}")
    for n in ("adhole-cn.conf", "adhole-noncn.conf", "adhole-full.conf"):
        p = out / n
        print(f"  {p}: {p.stat().st_size} bytes")

if __name__ == "__main__":
    main()
