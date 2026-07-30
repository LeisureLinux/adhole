// Package core provides type definitions and configuration management.
package core

import (
	"flag"
	"fmt"
	"os"
)

// Config holds application-wide settings.
type Config struct {
	ListenAddr   string // HTTP listener address
	Port         int    // HTTP listen port (default 9153)
	DataDir      string // SQLite data directory path
	DNSTapPath   string // DNSTap socket/file path
	LogFilePath  string // Fallback unbound log file path
	CacheTTLDays int    // Data retention days
}

// QueryRecord represents a parsed DNS query event.
type QueryRecord struct {
	Timestamp    float64 // Unix epoch seconds
	ClientIP     string  // Client IP address
	Domain       string  // Queried domain name
	QType        string  // Query type (A, AAAA, CNAME...)
	Response     string  // Parsed response
	RCode        string  // Response code (NOERROR, NXDOMAIN...)
	CacheHit     bool    // Was resolved from cache
	Blocked      bool    // Was blocked
	BlockReason  string  // Reason for blocking
	DNSSECStatus string  // DNSSEC status (SECURE, INSECURE...)
}

// LoadConfig parses command line flags and returns a config instance.
func LoadConfig() *Config {
	cfg := &Config{
		ListenAddr:   "127.0.0.1",
		Port:         9153,
		DataDir:      "/var/lib/unbound-dashboard",
		CacheTTLDays: 90,
	}

	flag.StringVar(&cfg.ListenAddr, "addr", cfg.ListenAddr, "HTTP listen address")
	flag.IntVar(&cfg.Port, "port", cfg.Port, "HTTP listen port")
	flag.StringVar(&cfg.DataDir, "data-dir", cfg.DataDir, "Directory for database storage")
	flag.StringVar(&cfg.DNSTapPath, "dnstap", "", "Path to DNSTap socket or file")
	flag.StringVar(&cfg.LogFilePath, "log-file", "", "Fallback path to verbose log")
	flag.IntVar(&cfg.CacheTTLDays, "ttl", cfg.CacheTTLDays, "Days to keep logs")

	flag.Parse()

	if err := os.MkdirAll(cfg.DataDir, 0755); err != nil {
		fmt.Fprintf(os.Stderr, "❌ Failed to create data dir %s: %v\n", cfg.DataDir, err)
		os.Exit(1)
	}

	return cfg
}
