// Package api provides RESTful JSON endpoints.
package api

import (
	"fmt"
	"net/http"
	"encoding/json"
	"strings"
	"time"

	"unbound-dashboard/core"
	"unbound-dashboard/database"
)

type Handler struct {
	db  *database.Database
	cfg *core.Config
}

var startTime = time.Now()

func NewHandler(db *database.Database, cfg *core.Config) *Handler {
	return &Handler{db: db, cfg: cfg}
}

/* ================================================================== */
/*  /stats API                                                         */
/* ================================================================== */
func (h *Handler) HandleStats(w http.ResponseWriter, r *http.Request) {
	total := h.db.GetTotalQueries()
	blocked := h.db.GetBlockedQueries()
	topQ := h.db.TopQueries(10)
	topB := h.db.RejectedQueries(10)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"total_queries":   total,
		"blocked_queries": blocked,
		"uptime":          time.Since(startTime).Truncate(time.Second).String(),
		"top_queries":     topQ,
		"top_blocked":     topB,
	})
}

/* ================================================================== */
/*  / — Dashboard Landing Page                                         */
/* ================================================================== */
const cssStyle = `
<style>
body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;margin:0;background:#f5f6fa;color:#2d3436}
.container{max-width:1100px;margin:0 auto;padding:20px}
header{display:flex;justify-content:space-between;align-items:center;background:#fff;padding:24px;border-radius:16px;box-shadow:0 4px 20px rgba(0,0,0,.06);margin-bottom:24px}
.card{background:#fff;padding:24px;border-radius:16px;box-shadow:0 4px 20px rgba(0,0,0,.06);margin-bottom:24px}
h1{margin:0;font-size:1.6em;color:#2d3436}
h3{margin-top:0;font-size:1.15em;color:#636e72}
.row{display:flex;gap:20px;margin-bottom:24px}
.stat-box{flex:1;text-align:center;padding:20px;border:1px solid #dfe6e9;border-radius:12px;background:#fafafa}
.stat-val{font-size:2.4em;font-weight:700;color:#2d3436}
.stat-label{color:#b2bec3;margin-top:4px;font-size:.95em}
.chart-row{display:flex;align-items:center;margin-bottom:8px;font-size:.9em}
.chart-row .label{width:180px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;color:#636e72}
.chart-row .bar-wrap{flex:1;height:22px;background:#eee;border-radius:6px;overflow:hidden;margin:0 10px}
.chart-row .bar{height:100%;border-radius:6px;transition:width .4s ease}
.blue{background:linear-gradient(90deg,#0984e3,#74b9ff)}
.red{background:linear-gradient(90deg,#d63031,#ff7675)}
</style>
`

func (h *Handler) handleIndex(w http.ResponseWriter, r *http.Request) {
	total := h.db.GetTotalQueries()
	blocked := h.db.GetBlockedQueries()
	host := r.Host
	if host == "" { host = "localhost" }

	topQItems := h.db.TopQueries(10)
	topBItems := h.db.RejectedQueries(10)

	// Build HTML using Buffer to safely handle formatting
	var buf strings.Builder
	
	buf.WriteString(`<!DOCTYPE html>
<html lang="zh">
<head><meta charset="utf-8"><title>Unbound DNS Dashboard</title>`)
	buf.WriteString(cssStyle)
	buf.WriteString(`</head>
<body>
<div class="container">
<header>
<div><h1>🌲 Unbound DNS Dashboard</h1><small>Real-time visualization · Powered by Go</small></div>
<div style="text-align:right"><div id="clock"></div><small>` + host + `</small></div>
</header>

<div class="row">
<div class="stat-box"><div class="stat-val">` + fmt.Sprintf("%d", total) + `</div><div class="stat-label">总查询数</div></div>
<div class="stat-box"><div class="stat-val" style="color:#d63031">` + fmt.Sprintf("%d", blocked) + `</div><div class="stat-label">拦截/拒绝</div></div>
</div>

<div class="card">
<h3>Top 10 拦截域名</h3>
`)
	renderBarsToBuf(&buf, topBItems, "red")

	buf.WriteString(`</div>

<div class="card">
<h3>Top 10 查询域名</h3>
`)
	renderBarsToBuf(&buf, topQItems, "blue")

	buf.WriteString(`</div>
</div>
<script>setInterval(()=>document.getElementById('clock').innerText=new Date().toLocaleString(),1000)</script>
</body></html>`)

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	fmt.Fprint(w, buf.String())
}

func (h *Handler) GetRouter() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/stats", h.HandleStats)
	mux.HandleFunc("/debug", h.HandleDebug)
	mux.HandleFunc("/", h.handleIndex)
	return mux
}

// renderBarsToBuf renders chart bars into the buffer safely
func renderBarsToBuf(buf *strings.Builder, items []database.StatItem, cls string) {
	maxV := maxVal(items)
	if maxV == 0 {
		buf.WriteString(`<p style="color:#b2bec3">暂无数据</p>`)
		return
	}
	for _, it := range items {
		width := int(float64(it.Value) / float64(maxV) * 100)
		buf.WriteString(`<div class="chart-row"><span class="label" title="`)
		buf.WriteString(it.Name)
		buf.WriteString(`">`)
		buf.WriteString(it.Name)
		buf.WriteString(`</span><div class="bar-wrap"><div class="bar ` + cls + `" style="width:`)
		buf.WriteString(fmt.Sprintf("%d", width))
		buf.WriteString(`%%"></div></div><span class="val">`)
		buf.WriteString(fmt.Sprintf("%d", it.Value))
		buf.WriteString(`</span></div>`)
	}
}

func maxVal(items []database.StatItem) int64 {
	var m int64
	for _, it := range items { if it.Value > m { m = it.Value } }
	return m
}


// HandleDebug provides runtime debugging information including DB connection details.
func (h *Handler) HandleDebug(w http.ResponseWriter, r *http.Request) {
	dataDir := h.cfg.DataDir
	
	sourceType := "unknown"
	dsn := "none"
	if h.cfg.DNSTapPath != "" {
		sourceType = "DNSTap Socket"
		dsn = h.cfg.DNSTapPath
	} else if h.cfg.LogFilePath != "" {
		sourceType = "Log File"
		dsn = h.cfg.LogFilePath
	} else {
		sourceType = "In-Memory/Default"
		dsn = dataDir + "/dashboard.db"
	}

	total := h.db.GetTotalQueries()
	blocked := h.db.GetBlockedQueries()
	
	rows, err := h.db.GetConn().Query("SELECT domain, qtype, rcode, response FROM query_log ORDER BY id DESC LIMIT 5")
	var lastRecords []string
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var d, qt, rc, res string
			if err := rows.Scan(&d, &qt, &rc, &res); err == nil {
				lastRecords = append(lastRecords, fmt.Sprintf("[%s] %s (%s) -> %s", rc, d, qt, res))
			}
		}
	}
	
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	fmt.Fprintf(w, "== Unbound Dashboard Debug Info ==\n\n")
	fmt.Fprintf(w, "Data Source Type : %s\n", sourceType)
	fmt.Fprintf(w, "Connection Path  : %s\n", dsn)
	fmt.Fprintf(w, "Storage Location : %s/dashboard.db\n", dataDir)
	fmt.Fprintf(w, "\n--- Statistics ---\n")
	fmt.Fprintf(w, "Total Queries    : %d\n", total)
	fmt.Fprintf(w, "Blocked Queries  : %d\n", blocked)
	fmt.Fprintf(w, "\n--- Last 5 Records Ingested ---\n")
	if len(lastRecords) > 0 {
		for _, rec := range lastRecords {
			fmt.Fprintf(w, "  %s\n", rec)
		}
	} else {
		fmt.Fprintln(w, "  (No records found in database yet)")
	}
}
