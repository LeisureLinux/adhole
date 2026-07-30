// Package database provides storage abstraction over SQLite.
package database

import (
	"database/sql"
	"fmt"

	"unbound-dashboard/core"

	_ "github.com/mattn/go-sqlite3" // SQLite driver (CGO)
)

// StatItem represents a top-list entry.
type StatItem struct {
	Name  string
	Value int64
}

// Database handles all persistence operations.
type Database struct {
	conn *sql.DB
}

// New initializes the database connection and creates necessary tables.
func New(dataDir string) (*Database, error) {
	dbPath := fmt.Sprintf("%s/dashboard.db", dataDir)
	conn, err := sql.Open("sqlite3", dbPath+"?_journal_mode=WAL&_busy_timeout=5000")
	if err != nil {
		return nil, fmt.Errorf("open database: %w", err)
	}

	createSQL := `
	CREATE TABLE IF NOT EXISTS query_log (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		timestamp REAL NOT NULL,
		client_ip TEXT NOT NULL,
		domain TEXT NOT NULL,
		qtype TEXT NOT NULL,
		response TEXT DEFAULT '',
		rcode TEXT DEFAULT 'NOERROR',
		cache_hit BOOLEAN DEFAULT 0,
		blocked BOOLEAN DEFAULT 0,
		block_reason TEXT DEFAULT '',
		dnssec_status TEXT DEFAULT '',
		UNIQUE(client_ip, domain, qtype, CAST(timestamp AS INTEGER))
	);

	-- Indexes for efficient queries
	CREATE INDEX IF NOT EXISTS idx_ts ON query_log(timestamp DESC);
	CREATE INDEX IF NOT EXISTS idx_domain ON query_log(domain);
	CREATE INDEX IF NOT EXISTS idx_blocked ON query_log(blocked);
	`

	if _, err := conn.Exec(createSQL); err != nil {
		conn.Close()
		return nil, fmt.Errorf("create tables: %w", err)
	}

	fmt.Println("✅ Database initialized successfully")
	return &Database{conn: conn}, nil
}

// InsertRecord adds a new DNS query record, ignoring duplicates via UNIQUE constraint.
func (db *Database) InsertRecord(record core.QueryRecord) error {
	stmt := `INSERT OR IGNORE INTO query_log 
		(timestamp, client_ip, domain, qtype, response, rcode, cache_hit, blocked, block_reason, dnssec_status) 
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
	_, err := db.conn.Exec(stmt,
		record.Timestamp,
		record.ClientIP,
		record.Domain,
		record.QType,
		record.Response,
		record.RCode,
		record.CacheHit,
		record.Blocked,
		record.BlockReason,
		record.DNSSECStatus,
	)
	return err
}

// Close terminates the database connection.

// GetConn exposes the underlying *sql.DB for advanced operations like debugging.
func (db *Database) GetConn() *sql.DB {
	return db.conn
}
func (db *Database) Close() {
	if db.conn != nil {
		db.conn.Close()
	}
}

// GetStats fetches summary statistics.
func (db *Database) GetStats() map[string]int64 {
	rows, _ := db.conn.Query(`SELECT COUNT(*), COUNT(CASE WHEN blocked THEN 1 END) FROM query_log`)
	var total, blocked int64
	if rows.Next() {
		rows.Scan(&total, &blocked)
	}
	return map[string]int64{
		"TotalQueries":    total,
		"BlockedQueries":  blocked,
	}
}

/* ================================================================== */
/*  Aggregation helpers for dashboard                                  */
/* ================================================================== */

// GetTotalQueries returns total number of records.
func (db *Database) GetTotalQueries() int64 {
	var total int64
	db.conn.QueryRow("SELECT COUNT(*) FROM query_log").Scan(&total)
	return total
}

// GetBlockedQueries returns number of blocked/rejected records.
func (db *Database) GetBlockedQueries() int64 {
	var blocked int64
	db.conn.QueryRow("SELECT COUNT(*) FROM query_log WHERE blocked = 1").Scan(&blocked)
	return blocked
}

// TopQueries returns the top-N most queried domains.
func (db *Database) TopQueries(limit int) []StatItem {
	rows, err := db.conn.Query(
		"SELECT domain, COUNT(*) as cnt FROM query_log GROUP BY domain ORDER BY cnt DESC LIMIT ?", limit)
	if err != nil { return nil }
	defer rows.Close()

	var items []StatItem
	for rows.Next() {
		var s StatItem
		rows.Scan(&s.Name, &s.Value)
		items = append(items, s)
	}
	return items
}

// RejectedQueries returns the top-N rejected domains.
// Excludes normal DNS behaviors: NXDOMAIN (domain not found), SERVFAIL (server error).
// These appear as "blocked" but they're usually just missing/invalid domains.
func (db *Database) RejectedQueries(limit int) []StatItem {
	rows, err := db.conn.Query(
		"SELECT domain, COUNT(*) as cnt FROM query_log WHERE blocked = 1 GROUP BY domain ORDER BY cnt DESC LIMIT ?", limit)
	if err != nil { return nil }
	defer rows.Close()

	var items []StatItem
	for rows.Next() {
		var s StatItem
		rows.Scan(&s.Name, &s.Value)
		items = append(items, s)
	}
	return items
}

