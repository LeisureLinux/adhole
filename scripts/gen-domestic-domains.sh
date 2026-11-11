#!/usr/bin/env bash
# gen-domestic-domains.sh — 生成「国内域名」清单，供 mail2 的 dnsdist 做 split-horizon
#
# 输出：data/state/domestic-domains.txt（每行一个域名，不带尾点）
# 用途：mail2 的 dnsdist 用 SuffixMatchNodeRule 匹配该清单，
#       命中的走 cn 池（腾讯 DoT → 国内 CDN 节点），
#       其余走默认池（Cloudflare DoT → 墙外干净递归）。
#
# 来源：geosite-cn 的 domain_suffix（8762 条）
#     + 有国内 CDN 节点、应走腾讯的境外服务（apple.com / microsoft.com 等）
#
# ⚠️ geosite-cn 是 sing-box rule_set（wpad 上的 srs），源在
#    /etc/sing-box/rule-set/geosite-cn.srs；用 sing-box rule-set decompile 导出。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_DIR="$SCRIPT_DIR/../data/state"
OUT="$STATE_DIR/domestic-domains.txt"
GEOSITE="${GEOSITE:-/tmp/gs-live.json}"

[[ -f "$GEOSITE" ]] || { echo "ERROR: 缺少 $GEOSITE（先 sing-box rule-set decompile geosite-cn.srs）"; exit 1; }

python3 - "$GEOSITE" "$OUT" <<'PY'
import json, sys
src, out = sys.argv[1], sys.argv[2]
d = json.load(open(src))
zones = set()
for r in d.get("rules", []):
    for s in r.get("domain_suffix", []):
        z = s.lstrip(".").rstrip(".").lower()
        if z:
            zones.add(z)
# 有国内 CDN 节点、应走腾讯（国内节点）的境外服务
zones.update("""apple.com icloud.com apple.com.cn mzstatic.com itunes.apple.com microsoft.com
microsoftonline.com live.com office.com office365.com windowsupdate.com
microsoftonline.cn qq.com tencent.com myqcloud.com weixin.qq.com mp.weixin.qq.com aliyun.com
alibaba.com alipay.com taobao.com tmall.com jd.com bilibili.com zhihu.com
csdn.net cnblogs.com 163.com 126.com sina.com.cn sina.cn sohu.com ifeng.com
cctv.com youku.com iqiyi.com meituan.com pinduoduo.com ctrip.com xiaomi.com
huawei.com oppo.com vivo.com lenovo.com adobe.com""".split())
zones = sorted(z for z in zones if z and " " not in z)
with open(out, "w") as f:
    f.write("\n".join(zones) + "\n")
print(f"已生成 {out}: {len(zones)} 条")
PY
