package main

import (
	"io"
	"log"
	"net"
	"os"
	"strings"
	"time"
)

func copyConn(dst net.Conn, src net.Conn, done chan<- struct{}) {
	_, _ = io.Copy(dst, src)
	_ = dst.SetDeadline(time.Now())
	done <- struct{}{}
}

func handleClient(clientConn net.Conn, backend string) {
	defer clientConn.Close()

	remoteConn, err := net.DialTimeout("tcp", backend, 30*time.Second)
	if err != nil {
		log.Printf("connect to backend %s failed: %v", backend, err)
		return
	}
	defer remoteConn.Close()

	log.Printf("connected client to backend %s", backend)

	done := make(chan struct{}, 2)
	go copyConn(remoteConn, clientConn, done)
	go copyConn(clientConn, remoteConn, done)
	<-done
}

func backendAddress() string {
	backend := strings.TrimSpace(os.Getenv("BACKEND"))
	if backend != "" {
		return backend
	}

	host := strings.TrimSpace(os.Getenv("V2RAY_SERVER_IP"))
	if host == "" {
		return "gcpx.dev-zoom.buzz:700"
	}

	port := strings.TrimSpace(os.Getenv("V2RAY_SERVER_PORT"))
	if port == "" {
		port = "700"
	}

	if strings.Contains(host, ":") {
		return host
	}

	return net.JoinHostPort(host, port)
}

func main() {
	port := strings.TrimSpace(os.Getenv("PORT"))
	if port == "" {
		port = "8080"
	}

	backend := backendAddress()

	listenAddr := ":" + port
	listener, err := net.Listen("tcp", listenAddr)
	if err != nil {
		log.Fatalf("listen on %s failed: %v", listenAddr, err)
	}
	defer listener.Close()

	log.Printf("OVPN proxy listening on %s", listenAddr)
	log.Printf("backend: %s", backend)

	for {
		clientConn, err := listener.Accept()
		if err != nil {
			log.Printf("accept failed: %v", err)
			continue
		}

		go handleClient(clientConn, backend)
	}
}
