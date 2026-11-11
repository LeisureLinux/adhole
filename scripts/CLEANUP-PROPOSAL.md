# scripts/ 清理建议 — 2026-11-11

本清单由「当前 CI + 本机分发链路实际引用」反推。**尚未删除任何文件**，等你确认。

## 必须保留（14 个）

- `scripts/README.md` — 原 main.sh 管线 / 历史参考
- `scripts/build_adhole.sh` — CI 直接调用
- `scripts/classify_shard.py` — CI 直接调用
- `scripts/compile-geo-domestic.py` — CI 直接调用
- `scripts/dns-op.sh` — 原 main.sh 管线 / 历史参考
- `scripts/estimate_split.py` — 原 main.sh 管线 / 历史参考
- `scripts/fetch-state-from-gh.sh` — 本机 cron 调用
- `scripts/gen-domestic-domains.sh` — CI 直接调用
- `scripts/install_pkg.sh` — 原 main.sh 管线 / 历史参考
- `scripts/main.sh` — 原 main.sh 管线 / 历史参考
- `scripts/merge-adhole-tables.sh` — 原 main.sh 管线 / 历史参考
- `scripts/merge_shards.py` — CI 直接调用
- `scripts/setup_dns.sh` — 原 main.sh 管线 / 历史参考
- `scripts/wpad-mgmt.sh` — 原 main.sh 管线 / 历史参考

## 建议删除（38 个，全部 untracked）

均为 2026-10-30~11-02 wpad-02 DNS 大改造期间的临时部署脚本、配置备份、审计产物；
现网配置以各主机 /etc 为准，CI 与本机 cron 都不再引用它们。

- `scripts/DEPLOY-CHECKLIST.md`
- `scripts/WPAD-DNS-RUNBOOK.md`
- `scripts/check-dns-tunnel.sh`
- `scripts/classify_domains.py`
- `scripts/deploy-adblock-full.sh`
- `scripts/deploy-doh-mail2.sh`
- `scripts/deploy-vps.sh`
- `scripts/deploy-wpad-dns-failover.sh`
- `scripts/deploy-wpad-dns-fix.sh`
- `scripts/deploy-wpad.sh`
- `scripts/dnsdist-doh.conf`
- `scripts/doh-audit-report.md`
- `scripts/doh-audit.py`
- `scripts/doh-loadtest.sh`
- `scripts/dohlog.py`
- `scripts/dohtest.py`
- `scripts/dot-ssh-tunnel.service`
- `scripts/make-ios-doh-profile.py`
- `scripts/make-vps-bundle.sh`
- `scripts/nftables-singbox-gw.nft`
- `scripts/nginx-doh.conf`
- `scripts/on-v6-prefix-change.sh`
- `scripts/ra-steer-v2.py`
- `scripts/ra-steer-v2.service`
- `scripts/refresh-phone6-set.sh`
- `scripts/sing-box.json`
- `scripts/switch-gateway.sh`
- `scripts/switch-local-proxy.sh`
- `scripts/unbound-dnsproxy.conf`
- `scripts/unbound-doh-foreign.conf`
- `scripts/unbound-doh-foreign.service`
- `scripts/unbound-doh.conf`
- `scripts/unbound-domestic.conf`
- `scripts/unbound-domestic.service`
- `scripts/v25-local-deploy.sh`
- `scripts/validate-mobileconfig.py`
- `scripts/vps-nsd.conf`
- `scripts/vps-unbound.conf`

## 执行（确认后）

```bash
cd ~/mygithub/adhole
# 先备份到 /var/tmp（本机临时目录）
tar czf /var/tmp/adhole-scripts-legacy-20261111.tgz -T <(printf "%s\n" \
  scripts/DEPLOY-CHECKLIST.md scripts/WPAD-DNS-RUNBOOK.md scripts/check-dns-tunnel.sh scripts/classify_domains.py scripts/deploy-adblock-full.sh scripts/deploy-doh-mail2.sh scripts/deploy-vps.sh scripts/deploy-wpad-dns-failover.sh scripts/deploy-wpad-dns-fix.sh scripts/deploy-wpad.sh scripts/dnsdist-doh.conf scripts/doh-audit-report.md scripts/doh-audit.py scripts/doh-loadtest.sh scripts/dohlog.py scripts/dohtest.py scripts/dot-ssh-tunnel.service scripts/make-ios-doh-profile.py scripts/make-vps-bundle.sh scripts/nftables-singbox-gw.nft scripts/nginx-doh.conf scripts/on-v6-prefix-change.sh scripts/ra-steer-v2.py scripts/ra-steer-v2.service scripts/refresh-phone6-set.sh scripts/sing-box.json scripts/switch-gateway.sh scripts/switch-local-proxy.sh scripts/unbound-dnsproxy.conf scripts/unbound-doh-foreign.conf scripts/unbound-doh-foreign.service scripts/unbound-doh.conf scripts/unbound-domestic.conf scripts/unbound-domestic.service scripts/v25-local-deploy.sh scripts/validate-mobileconfig.py scripts/vps-nsd.conf scripts/vps-unbound.conf)
# 再删除
rm -f scripts/DEPLOY-CHECKLIST.md scripts/WPAD-DNS-RUNBOOK.md scripts/check-dns-tunnel.sh scripts/classify_domains.py scripts/deploy-adblock-full.sh scripts/deploy-doh-mail2.sh scripts/deploy-vps.sh scripts/deploy-wpad-dns-failover.sh scripts/deploy-wpad-dns-fix.sh scripts/deploy-wpad.sh scripts/dnsdist-doh.conf scripts/doh-audit-report.md scripts/doh-audit.py scripts/doh-loadtest.sh scripts/dohlog.py scripts/dohtest.py scripts/dot-ssh-tunnel.service scripts/make-ios-doh-profile.py scripts/make-vps-bundle.sh scripts/nftables-singbox-gw.nft scripts/nginx-doh.conf scripts/on-v6-prefix-change.sh scripts/ra-steer-v2.py scripts/ra-steer-v2.service scripts/refresh-phone6-set.sh scripts/sing-box.json scripts/switch-gateway.sh scripts/switch-local-proxy.sh scripts/unbound-dnsproxy.conf scripts/unbound-doh-foreign.conf scripts/unbound-doh-foreign.service scripts/unbound-doh.conf scripts/unbound-domestic.conf scripts/unbound-domestic.service scripts/v25-local-deploy.sh scripts/validate-mobileconfig.py scripts/vps-nsd.conf scripts/vps-unbound.conf
```
