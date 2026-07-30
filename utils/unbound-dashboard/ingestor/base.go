// Package ingestor defines interfaces for parsing DNS logs.
package ingestor

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"regexp"
	"strings"
	"time"

	"unbound-dashboard/core"
	"unbound-dashboard/database"
)

/* ================================================================== */
/*  Parser interface                                                   */
/* ================================================================== */

type Parser interface {
	Start(db *database.Database) error
	GetPath() string
}

/* ------------------------------------------------------------------ */
/*  MockParser                                                         */
/* ------------------------------------------------------------------ */

type MockParser struct{}

func NewMockParser() *MockParser          { return &MockParser{} }
func (m *MockParser) GetPath() string     { return "none" }
func (m *MockParser) Start(db *database.Database) error {
	fmt.Println("ℹ️  No log source configured; using mock parser.")
	select {}
}

/* ------------------------------------------------------------------ */
/*  LogReader: real-time tailer of unbound verbose-log                 */
/* ------------------------------------------------------------------ */

type LogReader struct {
	path        string
	syslogRe    *regexp.Regexp
	queryOnlyRe *regexp.Regexp
}

func NewLogReader(path string) *LogReader {
	return &LogReader{
		path:        path,
		// 匹配 Debian/Ubuntu syslog 格式: date host[pid]: level: ip domain QTYPE IN RCODE rest
		syslogRe:    regexp.MustCompile(`^(\w+\s+\d+\s+[\d:]+)\s+(\S+)\[(\d+:\d+)\]\s+(\w+):\s+(\S+)\s+(\S+)\s+(\S+)\s+IN\s+(\S+)\s+(.*)$`),
		// 匹配无返回码的行: date host[pid]: level: ip domain QTYPE IN
		queryOnlyRe: regexp.MustCompile(`^(\w+\s+\d+\s+[\d:]+)\s+(\S+)\[(\d+:\d+)\]\s+(\w+):\s+(\S+)\s+(\S+)\s+(\S+)\s+IN$`),
	}
}

func (r *LogReader) GetPath() string      { return r.path }

// Start implements a two-phase ingestion strategy:
// 1. Scan existing content to catch up history.
// 2. Poll-based tail (Stat → Seek → read new lines).
func (r *LogReader) Start(db *database.Database) error {
	if r.path == "" {
		fmt.Println("⚠️  No log file configured.")
		return nil
	}

	f, err := os.Open(r.path)
	if err != nil {
		return fmt.Errorf("open log %s: %w", r.path, err)
	}
	defer f.Close()


	lineNum := 0
	matchedCount := 0
	scanner := bufio.NewScanner(f)
	buf := make([]byte, 0, 1<<20) // 1 MB buffer
	scanner.Buffer(buf, 4<<20)

	// Phase 1: Read all existing lines
	for scanner.Scan() {
		line := scanner.Text()
		lineNum++

		rec := r.parseLine(line)
		if rec != nil {
			matchedCount++
			_ = db.InsertRecord(*rec)
		}
	}

	// Check for errors during scan (ignoring io.EOF is normal)
	if err := scanner.Err(); err != nil && err != io.EOF {
		return fmt.Errorf("scan log: %w", err)
	}


	// Phase 2: Poll-based tail — Stat the file every 2 seconds and read only new bytes.

	// Record current position (end of file after history scan)
	currentOffset, err := f.Seek(0, 2)
	if err != nil {
		return fmt.Errorf("seek end for tailing: %w", err)
	}
	var lastSize int64 = currentOffset // also keep track via Stat for size change detection

	for {
		st, err := f.Stat()
		if err != nil {
			time.Sleep(2 * time.Second)
			continue
		}

		newSize := st.Size()

		// Handle logrotate: if file was truncated or replaced, reset offset
		if newSize < lastSize {
			currentOffset = 0
		}
		lastSize = newSize

		readBytes := newSize - currentOffset
		if readBytes <= 0 {
			// Nothing new, wait and poll again
			time.Sleep(2 * time.Second)
			continue
		}

		// File has grown — read from where we left off until end
		f.Seek(currentOffset, 0)
		
		tailScanner := bufio.NewScanner(f)
		tailBuf := make([]byte, 0, 1<<20)
		tailScanner.Buffer(tailBuf, 4<<20)

		linesThisBatch := 0
		for tailScanner.Scan() {
			line := tailScanner.Text()
			rec := r.parseLine(line)
			if rec != nil {
				_ = db.InsertRecord(*rec)
				linesThisBatch++
			}
		}
		if tailScanner.Err() != nil && tailScanner.Err() != io.EOF {
			fmt.Printf("❌ Scanner error: %v\n", tailScanner.Err())
		}

		// Advance our offset by how many bytes Scanner consumed
		currentOffset += readBytes
		if linesThisBatch > 0 {
		}

		time.Sleep(2 * time.Second)
	}
}

func (r *LogReader) parseLine(line string) *core.QueryRecord {
	var m []string
	
	// --- Pattern 1: Full line with RCODE -----------------------------
	if m = r.syslogRe.FindStringSubmatch(line); len(m) > 8 {
		rcode := strings.TrimSpace(m[8])
		
		rec := &core.QueryRecord{
			Domain:    strings.TrimSuffix(m[6], "."),
			ClientIP:  m[5],
			QType:     m[7],
			RCode:     rcode,
			Response:  "Reply",
			Timestamp: float64(time.Now().Unix()),
		}
		
		if rcode != "NOERROR" && rcode != "SERVFAIL" && rcode != "FORMERR" && rcode != "" {
			rec.Blocked = true
			rec.BlockReason = rcode
		}
		
		return rec
	}
	
	// --- Pattern 2: Query only without RCODE -------------------------
	if m = r.queryOnlyRe.FindStringSubmatch(line); len(m) > 7 {
		return &core.QueryRecord{
			Domain:    strings.TrimSuffix(m[6], "."),
			ClientIP:  m[5],
			QType:     m[7],
			Response:  "Query",
			Timestamp: float64(time.Now().Unix()),
		}
	}
	
	return nil
}
