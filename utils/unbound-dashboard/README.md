# Unbound DNS Dashboard

轻量级 **Unbound DNS 实时可视化看板**，用 Go 编写，SQLite 存储。支持从 Unbound verbose-log 或 DNSTap socket 读取数据，提供 Top10 查询域名 / 拦截域名的仪表盘界面。

```
端口 : 9153
前端 : 内嵌 HTML（单文件部署）
后端 : REST API (JSON) + SQLite
数据源 : Unbound verbose-log 文件或 DNSTap Unix Socket
```

---

## 快速开始

```bash
# 1. 克隆
git clone https://github.com/LeisureLinux/adhole.git
cd adhole/utils/unbound-dashboard

# 2. 安装依赖
go mod download

# 3. 编译 (本机 amd64)
CGO_ENABLED=1 go build -o bins/unbound-dashboard ./cmd/

# 4. 运行
./unbound-dashboard \
    --port 9153 \
    --data-dir /tmp/unbound-data \
    --log-file /var/log/unbound-debug.log
```

访问 `http://<server>:9153` 即可看到仪表盘。

---

## 交叉编译：ARM64 (树莓派 / NanoPC 等)

### 前置条件：安装交叉编译工具链

在 **x86_64 开发机**上执行：

```bash
sudo apt update
sudo apt install gcc-aarch64-linux-gnu golang-go -y
```

确认工具链就绪：

```bash
which aarch64-linux-gnu-gcc    # 必须输出路径
aarch64-linux-gnu-gcc --version
```

### 交叉编译命令

```bash
cd /path/to/unbound-dashboard

GOOS=linux GOARCH=arm64 \
CGO_ENABLED=1 \
CC=aarch64-linux-gnu-gcc \
CXX=aarch64-linux-gnu-g++ \
GOCACHE=/tmp/.gocache \       # 可选：指定可写的 Go 构建缓存目录
go build -o bins/unbound-dashboard-arm64 ./cmd/
```

### 关键参数说明

| 参数 | 作用 |
|------|------|
| `GOOS=linux` | 目标操作系统：Linux |
| `GOARCH=arm64` | 目标架构：ARM64 / AArch64 |
| `CGO_ENABLED=1` | 启用 CGO（`go-sqlite3` 需要 C 编译器） |
| `CC=aarch64-linux-gnu-gcc` | 指定 ARM64 交叉 C 编译器 |
| `CXX=aarch64-linux-gnu-g++` | 指定 ARM64 交叉 C++ 编译器 |
| `GOCACHE=/tmp/.gocache` | 覆盖 Go 缓存位置（避免沙箱/只读文件系统报错） |

### 验证产物

```bash
file bins/unbound-dashboard-arm64
# 应输出: ELF 64-bit LSB executable, ARM aarch64 ...

scp bins/unbound-dashboard-arm64 user@raspberry-pi:/opt/unbound-dashboard/
```

---

## 配置参数

| Flag | 默认值 | 说明 |
|------|--------|------|
| `--addr` | `127.0.0.1` | HTTP 监听地址 |
| `--port` | `9153` | HTTP 监听端口 |
| `--data-dir` | `/tmp/unbound-data` | SQLite 数据库存放目录 |
| `--log-file` | _(空)_ | Unbound verbose-log 文件路径 |
| `--dnstap` | _(空)_ | DNSTap Unix Socket 路径 |
| `--ttl` | `90` | 数据保留天数 |

### 示例：生产环境启动

```bash
./unbound-dashboard \
    --addr 0.0.0.0 \
    --port 9153 \
    --data-dir /var/lib/unbound-dashboard \
    --log-file /var/log/unbound-debug.log
```

### Systemd 服务（推荐）

```ini
# /etc/systemd/system/unbound-dashboard.service
[Unit]
Description=Unbound DNS Dashboard
After=network.target unbound.service

[Service]
Type=simple
ExecStart=/opt/unbound-dashboard/unbound-dashboard-arm64 \
    --port 9153 \
    --data-dir /var/lib/unbound-dashboard \
    --log-file /var/log/unbound-debug.log
Restart=always
RestartSec=5
User=_unbound
Group=_unbound

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now unbound-dashboard
```

---

## 项目结构

```
unbound-dashboard/
├── cmd/main.go          # 入口：启动 HTTP server + ingestor goroutine
├── core/types.go        # Config / QueryRecord 类型定义
├── database/
│   └── database.go      # SQLite CRUD + Top-N 聚合查询
├── api/
│   └── handlers.go      # HTTP handler：/stats, /debug, / (HTML dashboard)
├── ingestor/
│   └── base.go          # Parser 接口 + LogReader / DNSTapReader 实现
└── web/                  # 静态资源（当前无外部文件，HTML 嵌入代码中）
```

---

## 最近修复记录

- **[v0.2]** 修复拦截图表为空问题：`RejectedQueries` 不再排除 NXDOMAIN，直接用 `blocked=1` 筛选
- **[v0.2]** 拦截图表与查询图表位置互换：拦截放上面，查询放下面
- **[v0.1]** 添加去重机制：`INSERT OR IGNORE` + UNIQUE 约束（同客户端同秒同域名只存一条）
- **[v0.1]** 修复 `ingestor/base.go` for 循环语法错误和未使用变量

---

## License

MIT
