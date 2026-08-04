# Adhole — 轻量级家庭 DNS 广告拦截系统

A lightweight home network DNS ad-block system built on [Unbound](https://unbound.net/) and [NSD](https://www.nlnetlabs.nl/projects/nsd/).

---

## 🔍 简介 / Introduction

Adhole 从多个互联网开源黑名单源聚合域名数据，自动清洗去重，输出适配 Unbound `always_null` 语法的 Zone 配置文件。将其部署到家中 DNS 服务器即可实现全网设备的一站式广告和恶意网站拦截。

Adhole aggregates domain blocklists from multiple open-source internet sources, performs automatic cleanup and deduplication, then outputs an Unbound `always_null` Zone config file. Deploy it as your home DNS resolver to block ads and malicious sites for every device on your network.

| 特性 | Feature |
|------|---------|
| 🏠 **无管理面板** — 纯命令行，配置即所得 | No Web UI — CLI-only, config-as-code |
| 🔗 **基于 Unbound + NSD** — 高性能本地递归解析器 | Based on Unbound + NSD — high-performance local recursive resolver |
| 🌐 **多源聚合** — OISD、StevenBlack、威胁情报等数十个源 | Multi-source aggregation — OISD, StevenBlack, threat intel, and dozens more |
| 📦 **极致压缩** — zst 格式仅 11 MB | Ultra-compressed — only ~11 MB in zst format |
| ⚡ **零运维** — cron 自动拉取更新 | Zero-maintenance — cron auto-pulls updates |

---

## 🚀 快速开始 / Quick Start

### 方式一：Debian 原生安装（推荐 SBC / Raspberry Pi）

#### 方法一 / Method A — 从零搭建

```bash
# 1. 安装依赖包
sudo ./install_pkg.sh

# 2. 生成 Zone 文件并构建
./scripts/main.sh sync

# 3. 启动 DNS 服务
sudo ./setup_dns.sh
```

#### 方法二 / Method B — 一键脚本（极简）

如果你只想用最少的步骤跑起来，可以用我们准备好的 [一键安装脚本](https://github.com/LeisureLinux/bilibili/blob/master/scripts/adhole.sh)。

---

### 方式二：虚拟机镜像快速体验

#### VirtualBox (Windows / macOS)

1. [下载 VDI 镜像](https://github.com/LeisureLinux/adhole/releases/download/adhole/adhole-18.vdi.zip)
2. 解压后在 VirtualBox 中注册 `.vdi` 文件，新建虚拟机（桥接网络、1024MB 内存、1 核 CPU）
3. 默认登录：用户 `adhole`，密码为短主机名 `adhole-18`
4. 将路由器 DNS 指向此虚机 IP 即可生效

#### libvirt / KVM (Linux)

```bash
# 1. 下载 qcow2 镜像
wget https://github.com/LeisureLinux/adhole/releases/download/adhole/adhole-1.1.5_amd64.qcow2.zst

# 2. 解压
zstd -d adhole-1.1.5_amd64.qcow2.zst

# 3. 导入 VM（替换你的网络名称和 SSH 公钥路径）
virt-install --vcpu 1 --memory 2048 --name adhole \
  --osinfo detect=on,name=debian11 --network=default \
  --noautoconsole --import \
  --disk adhole-1.1.5_amd64.qcow2
```

默认账户：`debian` / `LeisureLinux`  
SSH 连接：`ssh debian@adhole.local`（需 avahi-daemon）或 `virsh net-dhcp-leases default` 查 IP

---

### 验证效果 / Verify

将目标机器或路由器的 DNS 指向 Adhole 服务器后测试：

```bash
# Linux/Mac
dig +short www.baidu.com @<adhole-ip>      # → 正常 IP
dig +short a.baidu.com @<adhole-ip>        # → 0.0.0.0（已拦截）

# Windows CMD
nslookup
server <adhole-ip>
www.baidu.com       # → 正常 IP
a.baidu.com         # → 0.0.0.0（已拦截）
```

---

## ⚙️ 架构概览 / Architecture

```
          Internet
             │
     ┌───────┴───────┐
     │    NSD        │ ← Root zone slave, runs on 127.0.0.1:1053
     │ (anti-hijack) │   Prevents ISP DNS hijacking
     └───────┬───────┘
             │
     ┌───────┴───────┐
     │    Unbound     │ ← Local resolver on 0.0.0.0:53
     │  + adhole.conf │   Forwards to NSD; intercepts ad domains
     └───────────────┘
             │
     ┌───────┴───────┐
     │   Your Devices │ ← Phones, PCs, IoT...
     └───────────────┘
```

- **NSD** 作为 root zone 从服务器运行在 `127.0.0.1:1053`，防止运营商劫持
- **Unbound** 监听 `0.0.0.0:53`，除 `local-zone` 配置的域名外全部转发给 NSD
- 本机使用 `127.0.0.1:53`（Unbound）作为本地 DNS 解析器

---

## 🔧 使用与配置 / Usage & Configuration

### 更新 Zone 文件

```bash
# 一键执行：build → upload → pull
./scripts/main.sh sync

# 也可分步执行
./scripts/main.sh build      # 抓取、清洗、生成 adhole.conf.zst
./scripts/main.sh upload     # 上传到 GitHub Release
./scripts/main.sh pull       # 拉取最新 zone 文件并重载
./scripts/main.sh pull ./custom.zst   # 从本地文件直接部署
```

详细说明请见 [scripts/README.md](scripts/README.md)。

### 定时更新 / Auto Update

编辑 crontab 实现每日自动更新：

```cron
# 每天凌晨 2:10 执行
10 2 * * * cd /path/to/adhole && ./scripts/main.sh pull >/dev/null 2>&1
```

首次使用前建议在终端手动执行一次，确认无误后再加入定时任务。

### WPAD — 代理自动发现

家中多设备且频繁切换 VPN？用 WPAD 让设备自动选择是否走代理：

```bash
sudo ./wpad/wpad.sh setup   # 添加 wpad.service + wpad.timer
```

客户端浏览器设置为「自动检测代理」，自动获取 `http://wpad.local/wpad.dat`。iOS 无需额外配置。

---

## 📂 项目结构 / Project Structure

```
adhole/
├── conf/                     # DNS 服务器配置
│   ├── nsd.conf              # NSD root zone slave 配置
│   └── unbound.conf          # Unbound 主配置
├── data/                     # 数据源与产出
│   ├── block_urls.txt        # HOSTS 格式黑名单源 URL
│   ├── threat_urls.txt       # 威胁情报源 URL（木马/钓鱼/间谍软件）
│   ├── text_urls.txt         # 文本格式黑名单源 URL
│   ├── adblock_urls.txt      # Adblock/uBlock 过滤列表源 URL（Brave）
│   ├── block_domains.txt     # 自定义封锁域名（每行一个）
│   ├── unblock_domains.txt   # 白名单排除项
│   └── result/               # 产出目录
│       ├── adhole.conf.zst   # 最终 Zone 配置（压缩版）
│       ├── adhole_status.txt # 各源状态摘要
│       └── grab_*.log        # 每次运行日志（保留 10 天）
├── scripts/                  # 构建管线与工具
│   ├── main.sh               # 入口：build → upload → pull 管线
│   ├── build_adhole.sh       # 核心引擎：抓取、清洗、去重、生成
│   ├── dns-op.sh             # DNS 操作辅助
│   ├── wpad-mgmt.sh          # WPAD 管理
│   ├── setup_dns.sh          # DNS 服务初始化
│   └── install_pkg.sh        # 依赖包安装
├── wpad/                     # WPAD 服务文件
│   ├── wpad.sh
│   ├── wpad.service
│   └── wpad.timer
├── utils/                    # 杂项工具
├── .proxy                    # HTTP/SOCKS 代理地址（可选）
├── LICENSE
└── README.md
```

---

## ✏️ 自定义数据源 / Customize Sources

所有数据源通过纯文本文件管理，无需修改脚本代码。

### 添加黑名单源

编辑 `data/block_urls.txt`（HOSTS 格式）或 `data/threat_urls.txt`（威胁情报/TXT）：

```txt
https://raw.githubusercontent.com/example/custom-list/master/hosts
```

> 💡 **Adblock / uBlock 过滤列表**：`data/adblock_urls.txt` 支持 Adblock Plus /
> uBlock 过滤列表（例如 Brave 的 `brave-lists`）。脚本只提取其中的整域名规则
> `||domain.tld^` 并转换为 Unbound `local-zone always_null`；URL 路径、`$domain=`、
> 元素隐藏 `##`、脚本 `##+js` 与白名单 `@@` 规则无法在 DNS 层表达，会被跳过。

### 添加本地封锁域名

编辑 `data/block_domains.txt`，每行一个域名：

```txt
ads.myapp.com
tracking.evil.net
```

### 添加白名单（排除项）

编辑 `data/unblock_domains.txt`，防止误杀正常业务：

```txt
as.weixin.qq.com
pandora.xiaomi.com
cm.bilibili.com
```

> 💡 欢迎提交 PR 分享你的自定义列表！Contribute your `block_domains.txt` or `unblock_domains.txt` via PR.

---

## 🛡️ 工作原理 / How It Works

```
┌───────────────────────────────────────────────────────┐
│ Step 1: Initialize                                     │
│ • Read proxy from ~/.proxy                             │
│ • Create cache dir $HOME/.cache/adhole                 │
│ • Clean logs older than 10 days                        │
└──────────────────────┬────────────────────────────────┘
                       ▼
┌───────────────────────────────────────────────────────┐
│ Step 2: Fetch Remote Sources                           │
│ • grab_oisd() → OISD UNBOUND list (cached 24h)        │
│ • block()     → HOSTS-format lists (retry ×3)          │
│ • block_text()→ Threat intel TXT files                 │
└──────────────────────┬────────────────────────────────┘
                       ▼
┌───────────────────────────────────────────────────────┐
│ Step 3: Parse & Clean                                  │
│ • Auto-detect hosts / local-zone / Adblock formats    │
│ • Remove IPs, blanks, comments                        │
│ • Normalize to: local-zone "domain" always_null       │
└──────────────────────┬────────────────────────────────┘
                       ▼
┌───────────────────────────────────────────────────────┐
│ Step 4: Merge & Filter                                 │
│ • Merge all sources + local block_domains.txt         │
│ • Exclude whitelist from unblock_domains.txt          │
│ • Lowercase + deduplicate + sort                      │
└──────────────────────┬────────────────────────────────┘
                       ▼
┌───────────────────────────────────────────────────────┐
│ Step 5: Validate & Output                              │
│ • Syntax check via unbound-checkconf                  │
│ • Compress to .zst (~11 MB)                           │
│ • Generate status summary                             │
└───────────────────────────────────────────────────────┘
```

**错误处理 / Error Handling**：任何抓取失败时立即退出（`exit 1`），不污染已有结果——没有干净的数据就不该写入输出的清单。

---

## ⚠️ 注意事项 / Important Notes

| 项目 | 说明 | Note |
|------|------|------|
| ❌ **DNSSEC** | 为减少问题已关闭 | Disabled to avoid resolution failures |
| 🔒 **防劫持** | NSD 作为 root server 避免运营商 DNS 劫持 | NSD acts as root to prevent ISP hijacking |
| 🌐 **代理** | 如需要翻墙下载黑名单，在 `~/.proxy` 中写明代理地址 | Put proxy info in `~/.proxy`: `socks5://IP:port` |
| 💾 **磁盘** | 推荐 ≥16GB SD 卡或存储空间 | ≥16GB recommended for SD card |
| 🌍 **语言** | DNS 本身是玄学！调试困难时有耐心 | DNS is tricky — be patient when debugging |

---

## 📋 端口与服务 / Services & Ports

| 服务 | 端口 | 绑定地址 | 说明 |
|------|------|----------|------|
| NSD | 1053 | 127.0.0.1 | root zone slave，对外不可见 |
| Unbound | 53 | 0.0.0.0 | 主 DNS 解析器，接受局域网查询 |

检查端口状态：

```bash
ss -tln | grep -E ':(53|1053)\b'
```

---

## ⚠️ 依赖 / Dependencies

| 包名 | Package | 用途 | 安装方法 |
|------|---------|------|---------|
| `curl` | — | HTTP 请求 | 系统自带 / Built-in |
| `zstd` | zst | 压缩/解压 | `apt install zstd` |
| `parallel` | parsort | 高性能排序 | `apt install parallel` |
| `dos2unix` | — | 换行符转换 | `apt install dos2unix` |
| `unbound` | unbound-checkconf | 配置校验 | `apt install unbound` |
| `gh` | GitHub CLI | Release 上传 | `apt install gh` |
| `sudo` | — | 权限提升 | 系统自带 / Built-in |

---

## 📄 License

MIT License — Use at your own will, no warranty.  
See [LICENSE](LICENSE) for details.

---

## 👤 Author

**LeisureLinux** (Albert Xu)  
Bilibili ID: LeisureLinux  
Email: albertxu@freelamp.com

[![GitHub Release](https://img.shields.io/github/v/release/LeisureLinux/adhole)](https://github.com/LeisureLinux/adhole/releases)
