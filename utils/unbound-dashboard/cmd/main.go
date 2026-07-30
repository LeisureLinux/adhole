// Package main is the entry point for Unbound Dashboard.
package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"unbound-dashboard/api"
	"unbound-dashboard/core"
	"unbound-dashboard/database"
	"unbound-dashboard/ingestor"
)

const Version = "v0.2.25.20260731073600"

func main() {
	cfg := core.LoadConfig()
	fmt.Printf("🚀 Starting Unbound Dashboard %s...\n", Version)
	fmt.Printf("   📂 Data Dir        : %s\n", cfg.DataDir)
	fmt.Printf("   🎧 Listen Address  : %s:%d\n", cfg.ListenAddr, cfg.Port)
	
	if cfg.DNSTapPath != "" {
		fmt.Printf("   🦐 DNSTap Socket   : %s\n", cfg.DNSTapPath)
	} else if cfg.LogFilePath != "" {
		fmt.Printf("   📄 Log File        : %s\n", cfg.LogFilePath)
	} else {
		fmt.Println("   ℹ️  Mode             : Mock Parser (no source configured)")
	}

	db, err := database.New(cfg.DataDir)
	if err != nil {
		log.Fatalf("❌ Database init failed: %v", err)
	}
	defer db.Close()

	var parser ingestor.Parser
	if cfg.DNSTapPath != "" {
		parser = ingestor.NewDnstapReader(cfg.DNSTapPath)
	} else if cfg.LogFilePath != "" {
		parser = ingestor.NewLogReader(cfg.LogFilePath)
	} else {
		parser = ingestor.NewMockParser()
	}

	// 启动数据摄入，错误直接打印到 stderr
	go func() {
		fmt.Println("🔄 正在启动数据摄入...")
		if err := parser.Start(db); err != nil {
			fmt.Printf("❌ 数据摄入错误: %v\n", err)
			log.Fatalf("Ingestor fatal error: %v", err)
		}
	}()

	handler := api.NewHandler(db, cfg)
	addr := fmt.Sprintf("%s:%d", cfg.ListenAddr, cfg.Port)
	server := &http.Server{
		Addr:    addr,
		Handler: handler.GetRouter(),
	}

	idleConnsClosed := make(chan struct{})
	go func() {
		sigint := make(chan os.Signal, 1)
		signal.Notify(sigint, syscall.SIGINT, syscall.SIGTERM)
		<-sigint
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		server.Shutdown(ctx)
		close(idleConnsClosed)
	}()

	fmt.Printf("✅ Dashboard starting at http://%s\n", addr)
	if err := server.ListenAndServe(); err != http.ErrServerClosed {
		log.Fatalf("Listen error: %v", err)
	}
	<-idleConnsClosed
}
