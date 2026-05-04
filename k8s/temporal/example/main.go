package main

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"log"
	"os"
	"time"

	"go.temporal.io/sdk/client"
	"go.temporal.io/sdk/worker"
)

const taskQueue = "greeting"

func main() {
	name := "world"
	if len(os.Args) > 1 {
		name = os.Args[1]
	}

	c, err := connect()
	if err != nil {
		log.Fatalf("connect: %v", err)
	}
	defer c.Close()

	w := worker.New(c, taskQueue, worker.Options{})
	w.RegisterWorkflow(GreetingWorkflow)
	w.RegisterActivity(BuildGreeting)
	if err := w.Start(); err != nil {
		log.Fatalf("worker start: %v", err)
	}
	defer w.Stop()

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	run, err := c.ExecuteWorkflow(ctx, client.StartWorkflowOptions{
		TaskQueue: taskQueue,
	}, GreetingWorkflow, name)
	if err != nil {
		log.Fatalf("execute: %v", err)
	}
	log.Printf("started workflow id=%s run=%s", run.GetID(), run.GetRunID())

	var greeting string
	if err := run.Get(ctx, &greeting); err != nil {
		log.Fatalf("result: %v", err)
	}
	fmt.Println(greeting)
}

func connect() (client.Client, error) {
	addr := envOr("TEMPORAL_ADDRESS", "temporal.5xx.engineer:443")
	certPath := envOr("TEMPORAL_TLS_CERT", os.ExpandEnv("$HOME/.temporal/laptop/tls.crt"))
	keyPath := envOr("TEMPORAL_TLS_KEY", os.ExpandEnv("$HOME/.temporal/laptop/tls.key"))
	caPath := envOr("TEMPORAL_TLS_CA", os.ExpandEnv("$HOME/.temporal/laptop/ca.crt"))
	serverName := envOr("TEMPORAL_TLS_SERVER_NAME", "temporal.5xx.engineer")

	cert, err := tls.LoadX509KeyPair(certPath, keyPath)
	if err != nil {
		return nil, fmt.Errorf("load client cert: %w", err)
	}
	caBytes, err := os.ReadFile(caPath)
	if err != nil {
		return nil, fmt.Errorf("read ca: %w", err)
	}
	pool := x509.NewCertPool()
	if !pool.AppendCertsFromPEM(caBytes) {
		return nil, fmt.Errorf("ca file did not contain a usable PEM block")
	}
	return client.Dial(client.Options{
		HostPort:  addr,
		Namespace: "default",
		ConnectionOptions: client.ConnectionOptions{
			TLS: &tls.Config{
				Certificates: []tls.Certificate{cert},
				RootCAs:      pool,
				ServerName:   serverName,
			},
		},
	})
}

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
