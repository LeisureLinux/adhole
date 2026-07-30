# Adhole — 家庭网络 DNS 广告拦截清单生成工具
# Adhole — Home Network DNS Ad-block List Generator

## 📖 简介 / Introduction

Adhole 从多个互联网开源黑名单源聚合域名数据，自动清洗去重，输出适配 [Unbound](https://nlnetlabs.nl/projects/unbound/about/) `always_null` 语法的 `adhole.conf.zst` 文件。将其放入 Unbound 配置即可屏蔽全家设备的广告和恶意网站。

Adhole aggregates domain blocklists from multiple open-source internet sources, performs automatic cleanup and deduplication, then outputs an `adhole.conf.zst` file in Unbound `always_null` syntax. Drop it into your Unbound config to block ads and malicious sites for all devices on your home network.

---

## 🚀 快速开始 / Quick Start

```bash
git clone https://github.com/LeisureLinux/adhole.git
cd adhole/data
./adhole.sh
```

执行后将在 `data/result/` 下生成 `adhole.conf.zst`。

The script generates `data/result/adhole.conf.zst` after execution.

### 参数 / Options

| 参数 | 说明 / Description |
|------|-------------------|
| `-h, --help` | 显示帮助 / Show help |
| `-D, --download-only` | 仅下载刷新缓存，跳过上传 GitHub Release | Download only, skip upload to GitHub Release |

### 代理设置 / Proxy

如需通过代理访问外网，在 `$HOME/.proxy` 文件中写入代理地址：

To use a proxy, create `$HOME/.proxy` with:
```
socks5://192.168.x.x:1080
```

脚本会自动检测并启用代理，并在首次运行时检查连通性。

The script auto-detects the proxy and verifies connectivity at startup.

---

## 📂 文件说明 / File Structure

| 文件 | 中文说明 | English Description |
|------|---------|---------------------|
| `adhole.sh` | 主脚本，负责抓取、清洗、去重、生成最终清单 | Main script: fetch, clean, deduplicate, output |
| `block_urls.txt` | Hosts 格式黑名单源的 URL 列表（经 `block()` 处理） | HOSTS-format blacklist URLs (processed by `block()`) |
| `threat_urls.txt` | 威胁情报源 URL 列表，包含木马/钓鱼/间谍软件（经 `block_text()` 处理） | Threat intelligence URLs: malware/phishing/spyware (processed by `block_text()`) |
| `text_urls.txt` | 更多文本格式的黑名单源（目前默认跳过） | Additional text-format blocklist sources (skipped by default) |
| `block_domains.txt` | 本地自定义封锁域名，每行一个，以 `#` 开头为注释 | Custom local block domains, one per line, `#` for comments |
| `unblock_domains.txt` | 本地自定义白名单域名（排除项），防止误杀正常服务 | Local whitelist / exclusion list to prevent false positives |
| `result/adhole.conf` | 生成的 Unbound 配置文件（未压缩） | Generated Unbound config (uncompressed) |
| `result/adhole.conf.zst` | 压缩版，直接用于部署 | Compressed version for deployment |
| `result/grab_*.log` | 每次运行的抓取日志，保留最近 10 天 | Per-run logs, kept for 10 days |
| `result/adhole_status.txt` | 本次运行所有源的状态摘要 | Summary of all source statuses for this run |

---

## ⚙️ 工作流程 / Workflow

```
┌─────────────────────────────────────────────────┐
│  1. 启动 & 初始化                                │
│     Start & Initialize                          │
│  - 读取 ~/.proxy 代理设置                        │
│  - 创建缓存目录 $HOME/.cache/adhole              │
│  - 清理 10 天以上的旧日志                         │
└──────────────────┬──────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────┐
│  2. 抓取远程源                                  │
│     Fetch Remote Sources                        │
│  ┌─────────────┐ ┌──────────┐ ┌──────────────┐ │
│  │ grab_oisd() │ │ block()  │ │ block_text() │ │
│  │ OISD UNBOUND │ │ HOSTS格式 │ │ 威胁情报/TXT  │ │
│  └──────┬──────┘ └────┬─────┘ └──────┬───────┘ │
│         │             │              │          │
│         └──────┬──────┴──────────────┘          │
│                ▼                                 │
│       缓存命中？跳过 / Cache hit? Skip            │
│       TTL = 24小时 / Cache 24h                   │
└──────────────────┬──────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────┐
│  3. 解析 & 清洗                                  │
│     Parse & Clean                               │
│  - 自动识别 hosts / local-zone / Adblock 等格式  │
│  - 去除 IP、空行、注释                           │
│  - 标准化为 unbound local-zone 语法              │
└──────────────────┬──────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────┐
│  4. 合并 & 过滤                                  │
│     Merge & Filter                              │
│  - 合并所有源 + 本地 block_domains.txt           │
│  - 排除 unblock_domains.txt 中的白名单域名        │
│  - 全小写 + 去重排序                             │
└──────────────────┬──────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────┐
│  5. 验证 & 输出                                  │
│     Validate & Output                           │
│  - 用 unbound-checkconf 校验语法                 │
│  - 压缩为 .zst                                   │
│  - 生成 status.txt 状态摘要                       │
│  - （可选）上传至 GitHub Release                  │
└─────────────────────────────────────────────────┘
```

---

## 🛡️ 错误处理 / Error Handling

**关键变更**: 任何 curl 抓取失败时，脚本会立即退出 (`exit 1`)，而非继续处理不完整的数据。这确保了最终域名清单的完整性——没有抓到正确的数据，就不应该污染已有的结果。

**Key Change**: If any curl command fails (`block()`, `block_text()`, `grab_oisd()`), the script exits immediately with code 1 instead of continuing with partial results. This preserves the integrity of the final domain list — no incomplete data should pollute the output.

- `block()` — 重试 3 次（间隔 5 秒），全部失败则退出
- `block_text()` — 不重试，失败即退出  
- `grab_oisd()` — 不重试，失败即退出
- 代理检查 — Google 不可达则退出

---

## 🔧 自定义源 / Customize Sources

### 添加新的黑名单源
Edit `block_urls.txt` or `threat_urls.txt`:
```txt
https://example.com/blocklist.txt
```

### 添加本地封锁域名
编辑 `block_domains.txt`，每行一个域名：
```txt
ads.example.com
tracker.evil.net
```

### 添加白名单（排除项）
编辑 `unblock_domains.txt`，例如保留微信功能：
```txt
as.weixin.qq.com
```

---

## 📦 部署 / Deploy

```bash
# 解压到 Unbound 配置目录
zst -d adhole.conf.zst

# 在 unbound.conf 中包含
server:
    include: "/etc/unbound/adhole.conf"
```

或者下载最新 release:
```bash
wget https://github.com/LeisureLinux/adhole/releases/download/adhole/adhole.conf.zst
```

---

## ⚠️ 依赖 / Dependencies

| 包名 | 用途 | 安装方法 |
|------|------|---------|
| `curl` | HTTP 请求 | 系统自带 |
| `zstd` (zst) | 压缩/解压 | `apt install zstd` / `pacman -S zstd` |
| `parallel` (parsort) | 高性能排序 | `apt install parallel` |
| `dos2unix` | 换行符转换 | 通常随 curl 一起 |
| `unbound` (unbound-checkconf) | 配置文件验证 | `apt install unbound` |

---

## 📄 License

MIT License — Use at your own will, no warranty.
See [LICENSE](../LICENSE) for details.

---

## 👤 Author

**LeisureLinux** (Albert Xu)  
Bilibili ID: LeisureLinux  
Email: albertxu@freelamp.com
