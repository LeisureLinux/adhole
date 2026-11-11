#!/usr/bin/env python3
"""compile-geo-domestic.py — 由 domestic-domains.txt 生成 sing-box rule-set 源 JSON。

CI 里接着用 `sing-box rule-set compile` 编成 .srs。
本机 06:52 的旧 cron 里那段 inline python 就是这段逻辑，现搬到 CI。
"""
import json, sys
from pathlib import Path

src, out = sys.argv[1], sys.argv[2]
domains = [l.strip() for l in Path(src).read_text().splitlines() if l.strip()]
data = {"version": 3, "rules": [{"domain_suffix": domains}]}
Path(out).write_text(json.dumps(data, ensure_ascii=False))
print(f"  {out}: {len(domains)} 条")
