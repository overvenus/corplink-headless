package main

import (
	"log"
	"net"
	"os"

	"github.com/armon/go-socks5"
)

func main() {
	listenAddr := os.Getenv("SOCKS5_LISTEN_ADDR")
	if listenAddr == "" {
		listenAddr = "0.0.0.0:1080"
	}

	server, err := socks5.New(&socks5.Config{})
	if err != nil {
		log.Fatalf("failed to create socks5 server: %v", err)
	}
	listener, err := net.Listen("tcp", listenAddr)
	if err != nil {
		log.Fatalf("failed to listen on %s: %v", listenAddr, err)
	}

	log.Printf("socks5 server listening on %s", listenAddr)
	if err := server.Serve(listener); err != nil {
		log.Fatalf("socks5 server stopped: %v", err)
	}
}
