// Package ingestor defines interfaces for parsing DNS logs.
package ingestor

import (
	"fmt"
	"os"
	"time"

	"unbound-dashboard/core"
	"unbound-dashboard/database"
)

// Parser interface for different data sources (logs, dnstap).
type Parser interface {
	Start(db *database.Database) error
	GetPath() string
}

// LogReader implements log parsing for standard unbound verbose logs.
type LogReader struct {
	path string
}

// NewLogReader creates a new parser for text logs.
func NewLogReader(path string) *LogReader {
	return &LogReader{path: path}
}

// GetPath returns the log file path.
func (r *LogReader) GetPath() string {
	return r.path
}

// Start begins listening to the log file (placeholder for production implementation).
func (r *LogReader) Start(db *database.Database) error {
	if r.path == "" {
		fmt.Println("⚠️  No log file configured.")
		return nil
	}

	f, err := os.Open(r.path)
	if err != nil {
		return fmt.Errorf("failed to open log %s: %w", r.path, err)
	}
	defer f.Close()

	fmt.Printf("📥 Watching log file: %s\n", r.path)
	// Here we would use tailer/tail package or io.Reader
	for {
		// Placeholder for reading lines
		time.Sleep(5 * time.Second) 
	}
}

// InsertRecord inserts a parsed query record into the database.
func (r *LogReader) InsertRecord(db *database.Database, record core.QueryRecord) error {
	return db.InsertRecord(record)
}

// MockParser is a no-op parser used when no log source is configured.
type MockParser struct{}

func NewMockParser() *MockParser {
	return &MockParser{}
}

func (m *MockParser) GetPath() string {
	return "none"
}

func (m *MockParser) Start(db *database.Database) error {
	fmt.Println("ℹ️  No log source configured; mock parser active.")
	select {} // block forever to keep goroutine alive
}
