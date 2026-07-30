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

func main() {
	cfg := core.LoadConfig()
	db, err := database.New(cfg.DataDir)
	if err != nil {
		log.Fatalf("❌ Database init failed: %v", err)
	}
	defer db.Close()

	var parser ingestor.Parser
	if cfg.DNSTapPath != "" {
		parser = ingestor.NewLogReader("") 
		log.Println("⚠️  DNSTap mode not implemented yet.")
	} else if cfg.LogFilePath != "" {
		parser = ingestor.NewLogReader(cfg.LogFilePath)
	} else {
		log.Println("ℹ️  Using internal mock parser.")
		parser = ingestor.NewMockParser()
	}

	go func() {
		if err := parser.Start(db); err != nil {
			log.Printf("Ingestor error: %v", err)
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
