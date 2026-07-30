// Package database provides storage abstraction over SQLite.
package database

import (
	"database/sql"
	"fmt"

	"unbound-dashboard/core"

	_ "github.com/mattn/go-sqlite3" // SQLite driver
)

// Database handles all persistence operations.
type Database struct {
	conn *sql.DB
}

// New initializes the database connection and creates necessary tables.
func New(dataDir string) (*Database, error) {
	dbPath := fmt.Sprintf("%s/dashboard.db", dataDir)
	conn, err := sql.Open("sqlite3", dbPath+"?_journal_mode=WAL&_busy_timeout=5000")
	if err != nil {
		return nil, fmt.Errorf("failed to open database: %w", err)
	}

	// Create queries table
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
		dnssec_status TEXT DEFAULT ''
	);

	-- Index for efficient sorting by time and filtering
	CREATE INDEX IF NOT EXISTS idx_ts ON query_log(timestamp DESC);
	CREATE INDEX IF NOT EXISTS idx_client ON query_log(client_ip);
	CREATE INDEX IF NOT EXISTS idx_domain ON query_log(domain);
	CREATE INDEX IF NOT EXISTS idx_blocked ON query_log(blocked);
	`

	if _, err := conn.Exec(createSQL); err != nil {
		conn.Close()
		return nil, fmt.Errorf("failed to create tables: %w", err)
	}

	fmt.Println("✅ Database initialized successfully")
	return &Database{conn: conn}, nil
}

// InsertRecord adds a new DNS query record to the store.
func (db *Database) InsertRecord(record core.QueryRecord) error {
	stmt := `INSERT INTO query_log 
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
func (db *Database) Close() {
	if db.conn != nil {
		db.conn.Close()
	}
}

// GetStats fetches summary statistics for the dashboard.
func (db *Database) GetStats() map[string]int64 {
	stats := make(map[string]int64)
	rows, _ := db.conn.Query(`SELECT COUNT(*), COUNT(CASE WHEN blocked THEN 1 END) FROM query_log`)
	var total, blocked int64
	if rows.Next() {
		rows.Scan(&total, &blocked)
	}
	stats["TotalQueries"] = total
	stats["BlockedQueries"] = blocked
	return stats
}
