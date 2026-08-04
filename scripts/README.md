# Adhole — Build & Release Pipeline

Adhole 的构建与发布管线，包含**域名清单生成**、**GitHub Release 上传**、以及**设备端拉取重载**三步流水线。

---

## 📂 文件说明 / File Structure

| 文件 | 说明 |
|------|------|
| **`main.sh`** | **入口脚本**，统一的命令行接口（原名 `release.sh`），负责构建 → 上传 → 拉取的管线调度 |
| **`build_adhole.sh`** | 核心引擎，负责从多源抓取黑名单、清洗去重、生成 `adhole.conf.zst` |
| `dns-op.sh` | DNS 操作辅助脚本 |
| `wpad-mgmt.sh` | WPAD 规则管理脚本 |
| `setup_dns.sh` | DNS 环境初始化脚本 |
| `install_pkg.sh` | 依赖包安装脚本 |

---

## 🚀 用法 / Usage

### 管线命令（通过 `main.sh`）

```bash
cd /path/to/adhole

# 一步到位：构建 → 上传 → 拉取重载
./scripts/main.sh sync

# 分步执行
./scripts/main.sh build     # 运行 build_adhole.sh 生成 adhole.conf.zst
./scripts/main.sh upload    # 将产物上传到 GitHub Release
./scripts/main.sh pull      # 从 GitHub 拉取并重载 Unbound
./scripts/main.sh pull ./local/file.zst   # 直接解压部署本地文件
./scripts/main.sh help      # 显示帮助
```

### 子命令 / Subcommands

| 命令 | 说明 |
|------|------|
| `build` | 调用 `build_adhole.sh`，抓取所有黑名单源，生成 `data/result/adhole.conf.zst` |
| `upload` | 将 `adhole.conf.zst` + `adhole_status.txt` 上传到 GitHub Release |
| `pull [file]` | 下载最新 zone 文件，解压到 `/etc/unbound/adhole/`，自动重载 Unbound；支持指定本地文件直接部署 |
| `sync` | 全链路：`build` → `upload` → `pull` |

---

## ⚙️ 前置条件 / Prerequisites

| 项目 | 用途 | 备注 |
|------|------|------|
| `gh` (GitHub CLI) | 上传 Release 资产 | 需提前 `gh auth login` |
| `curl` / `zstd` | HTTP 请求、压缩解压 | 系统自带或 `apt install curl zstd` |
| `sudo` 权限 | 写入 `/etc/unbound/adhole/`、重载 Unbound | `pull` 和 `deploy` 需要 |
| `~/.proxy` | 代理配置（可选） | 写入 `socks5://IP:port`，脚本自动读取 |

---

## 🔄 工作原理 / How It Works

### 第一步：抓取远程源

```
┌─────────────────────────────────────────────────────┐
│  1. 启动 & 初始化                                    │
│     Start & Initialize                              │
│  - 读取 ~/.proxy 代理设置                            │
│  - 创建缓存目录 $HOME/.cache/adhole                  │
│  - 清理 10 天以上的旧日志                             │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│  2. 抓取远程黑名单源                                  │
│     Fetch Remote Sources                            │
│                                                     │
│  ┌──────────────┐  ┌────────────┐  ┌─────────────┐ │
│  │ grab_oisd()  │  │  block()   │  │ block_text()│ │
│  │ OISD UNBOUND │  │ HOSTS格式  │  │ 威胁情报/TXT │ │
│  └──────┬───────┘  └─────┬──────┘  └──────┬──────┘ │
│         └────────┬───────┴────────────────┘        │
│                  ▼                                   │
│           缓存命中？跳过（TTL = 24h）                  │
└──────────────────┬─────────────────────────────────┘
```

### 第二步：解析 & 清洗

- 自动识别 hosts / local-zone / Adblock 等黑名单格式
- 去除 IP 地址、空行、注释
- 标准化为 `unbound local-zone "domain" always_null` 语法

### 第三步：合并 & 过滤

1. 合并所有远程源 + 本地 `block_domains.txt` 自定义封锁域名
2. 排除 `unblock_domains.txt` 中的白名单域名（防误杀）
3. 全小写 + 去重排序

### 第四步：验证 & 输出

- `unbound-checkconf` 校验语法正确性
- 压缩为 `.zst` 节省空间
- 生成 `adhole_status.txt` 状态摘要

```
最终产出：data/result/adhole.conf.zst  （可直接用于 Unbound）
```

---

## 🛡️ 错误处理 / Error Handling

任何抓取失败时，脚本立即退出（`exit 1`），不污染已有结果：

| 函数 | 策略 |
|------|------|
| `block()` | 重试 3 次（间隔 5 秒），全部失败则退出 |
| `block_text()` | 不重试，失败即退出 |
| `grab_oisd()` | 不重试，失败即退出 |
| `grab_adblock()` | 不重试，失败即退出（Adblock/uBlock 列表） |
| 代理检查 | Google 不可达则退出 |

---

## 🔧 数据来源 / Customize Sources

所有数据源配置文件位于项目根目录 `data/` 下：

### 添加黑名单源

编辑 `data/block_urls.txt`（HOSTS 格式）或 `data/threat_urls.txt`（威胁情报）：

```txt
https://example.com/blocklist.txt
```

> 💡 **Adblock / uBlock 过滤列表**：`data/adblock_urls.txt` 支持 Adblock Plus /
> uBlock 格式（例如 Brave `adblock-lists` 的 `brave-lists`）。脚本仅提取整域名规则
> `||domain.tld^` 转成 Unbound `local-zone always_null`；URL 路径、`$domain=`、
> 元素隐藏 `##`、脚本 `##+js` 及白名单 `@@` 规则无法在 DNS 层表达，自动跳过。

### 添加本地封锁域名

编辑 `data/block_domains.txt`，每行一个域名：

```txt
ads.example.com
tracker.evil.net
```

### 添加白名单（排除项）

编辑 `data/unblock_domains.txt`，防止误杀正常服务：

```txt
as.weixin.qq.com
pandora.xiaomi.com
```

---

## ⚠️ 依赖 / Dependencies

| 包名 | 用途 | 安装方法 |
|------|------|---------|
| `curl` | HTTP 请求 | 系统自带 |
| `zstd` / `zst` | 压缩/解压 | `apt install zstd` |
| `parallel` (parsort) | 高性能排序 | `apt install parallel` |
| `dos2unix` | 换行符转换 | 通常随 curl 一起 |
| `unbound` (unbound-checkconf) | 配置文件验证 | `apt install unbound` |

---

## 👤 Author

**LeisureLinux** (Albert Xu)  
Email: albertxu@freelamp.com

See [LICENSE](../LICENSE) for details.
