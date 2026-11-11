#!/usr/bin/env python3
"""评估 adhole.conf 拆分为国内/国外的工作量。

策略：
  1. 按域名首字符（0-9a-z）分组
  2. 每组随机取 N 个域名（默认 100）
  3. 用 DNS 解析出 IP
  4. 用 geoip-cn 判断 IP 是否在国内
  5. 统计国内/国外比例，估算总体工作量

用法：
  python3 estimate_split.py [--sample 100] [--conf path/to/adhole.conf]
"""
import argparse
import ipaddress
import json
import random
import re
import subprocess
import sys
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed


def load_geoip_cn(path="/var/tmp/geoip-cn.json"):
    """加载 geoip-cn IP 段，返回 ipaddress 网络列表。"""
    with open(path) as f:
        data = json.load(f)
    networks = []
    for rule in data.get("rules", []):
        for cidr in rule.get("ip_cidr", []):
            networks.append(ipaddress.ip_network(cidr, strict=False))
    return networks


def is_cn_ip(ip, cn_nets_v4, cn_nets_v6):
    """判断 IP 是否在国内。"""
    addr = ipaddress.ip_address(ip)
    if addr.version == 4:
        for net in cn_nets_v4:
            if addr in net:
                return True
    else:
        for net in cn_nets_v6:
            if addr in net:
                return True
    return False


def load_domains(conf_path):
    """从 unbound conf 提取域名，按首字符分组。"""
    groups = defaultdict(list)
    pattern = re.compile(r'local-zone:\s+"([^"]+)"')
    with open(conf_path) as f:
        for line in f:
            m = pattern.search(line)
            if m:
                domain = m.group(1)
                ch = domain[0].lower()
                groups[ch].append(domain)
    return groups


def resolve_domain(domain):
    """解析域名为 IP，返回 (domain, ip) 或 (domain, None)。"""
    try:
        result = subprocess.run(
            ["dig", "+short", "+time=2", "+tries=1", "A", domain],
            capture_output=True, text=True, timeout=5
        )
        ips = [l.strip() for l in result.stdout.strip().split("\n") if l.strip()]
        # 取第一个 IPv4
        for ip in ips:
            try:
                addr = ipaddress.ip_address(ip)
                if addr.version == 4:
                    return domain, ip
            except ValueError:
                continue
        return domain, None
    except Exception:
        return domain, None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sample", type=int, default=100, help="每组采样数")
    ap.add_argument("--conf", default="/var/tmp/adhole.conf", help="adhole.conf 路径")
    ap.add_argument("--geoip", default="/var/tmp/geoip-cn.json", help="geoip-cn.json 路径")
    args = ap.parse_args()

    print("加载 geoip-cn ...", file=sys.stderr)
    cn_nets = load_geoip_cn(args.geoip)
    cn_nets_v4 = [n for n in cn_nets if n.version == 4]
    cn_nets_v6 = [n for n in cn_nets if n.version == 6]
    print(f"  IPv4 段: {len(cn_nets_v4)}, IPv6 段: {len(cn_nets_v6)}", file=sys.stderr)

    print("加载域名 ...", file=sys.stderr)
    groups = load_domains(args.conf)
    total_domains = sum(len(v) for v in groups.values())
    print(f"  总域名: {total_domains}, 分组数: {len(groups)}", file=sys.stderr)

    # 采样
    sampled = []
    for ch in sorted(groups.keys()):
        domains = groups[ch]
        if len(domains) <= args.sample:
            sample = domains
        else:
            sample = random.sample(domains, args.sample)
        sampled.extend(sample)
    print(f"  采样总数: {len(sampled)}", file=sys.stderr)

    # 并发解析
    print("解析采样域名 ...", file=sys.stderr)
    results = {"cn": 0, "foreign": 0, "noip": 0}
    details = []

    with ThreadPoolExecutor(max_workers=50) as ex:
        futures = {ex.submit(resolve_domain, d): d for d in sampled}
        for i, fut in enumerate(as_completed(futures)):
            domain, ip = fut.result()
            if ip is None:
                results["noip"] += 1
                details.append((domain, None, "noip"))
            else:
                if is_cn_ip(ip, cn_nets_v4, cn_nets_v6):
                    results["cn"] += 1
                    details.append((domain, ip, "cn"))
                else:
                    results["foreign"] += 1
                    details.append((domain, ip, "foreign"))
            if (i + 1) % 500 == 0:
                print(f"  已处理 {i+1}/{len(sampled)}", file=sys.stderr)

    # 统计
    total = results["cn"] + results["foreign"] + results["noip"]
    print(f"\n=== 采样统计（共 {total} 个域名）===")
    print(f"  国内 (CN):     {results['cn']:6d}  ({results['cn']/total*100:.1f}%)")
    print(f"  国外:          {results['foreign']:6d}  ({results['foreign']/total*100:.1f}%)")
    print(f"  无法解析:      {results['noip']:6d}  ({results['noip']/total*100:.1f}%)")

    # 按首字符统计
    print("\n=== 按首字符统计 ===")
    ch_stats = defaultdict(lambda: {"cn": 0, "foreign": 0, "noip": 0})
    for domain, ip, label in details:
        ch = domain[0].lower()
        ch_stats[ch][label] += 1

    print(f"{'首字符':<8} {'总数':>8} {'国内':>8} {'国外':>8} {'无IP':>8} {'国内%':>8}")
    for ch in sorted(ch_stats.keys()):
        s = ch_stats[ch]
        t = s["cn"] + s["foreign"] + s["noip"]
        pct = s["cn"] / t * 100 if t else 0
        print(f"{ch:<8} {t:>8} {s['cn']:>8} {s['foreign']:>8} {s['noip']:>8} {pct:>7.1f}%")

    # 估算总体
    cn_ratio = results["cn"] / (results["cn"] + results["foreign"]) if (results["cn"] + results["foreign"]) else 0
    est_cn = int(total_domains * cn_ratio)
    est_foreign = total_domains - est_cn
    print(f"\n=== 估算（基于 {total} 采样）===")
    print(f"  总域名:        {total_domains}")
    print(f"  估算国内:      {est_cn}  ({cn_ratio*100:.1f}%)")
    print(f"  估算国外:      {est_foreign}  ({(1-cn_ratio)*100:.1f}%)")

    # 保存采样结果供人工检查
    out = "/var/tmp/split_estimate.json"
    with open(out, "w") as f:
        json.dump({"results": results, "details": details}, f)
    print(f"\n详细结果已保存: {out}")


if __name__ == "__main__":
    main()
