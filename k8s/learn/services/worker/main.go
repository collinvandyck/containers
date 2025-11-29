package main

import (
	"context"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/go-redis/redis/v8"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"net/http"
)

var (
	jobsProcessed = promauto.NewCounter(prometheus.CounterOpts{
		Name: "worker_jobs_processed_total",
		Help: "Total number of jobs processed",
	})
	jobProcessingDuration = promauto.NewHistogram(prometheus.HistogramOpts{
		Name:    "worker_job_processing_duration_seconds",
		Help:    "Duration of job processing",
		Buckets: prometheus.DefBuckets,
	})
)

func main() {
	ctx := context.Background()

	redisAddr := getEnv("REDIS_ADDR", "redis:6379")
	queueName := getEnv("QUEUE_NAME", "jobs")
	metricsPort := getEnv("METRICS_PORT", "9090")

	// Start metrics server
	go func() {
		http.Handle("/metrics", promhttp.Handler())
		log.Printf("Starting metrics server on port %s", metricsPort)
		if err := http.ListenAndServe(":"+metricsPort, nil); err != nil {
			log.Fatal(err)
		}
	}()

	// Connect to Redis
	rdb := redis.NewClient(&redis.Options{
		Addr: redisAddr,
	})
	defer rdb.Close()

	log.Printf("Connected to Redis at %s", redisAddr)
	log.Printf("Waiting for jobs on queue '%s'", queueName)

	// Handle graceful shutdown
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-sigChan:
			log.Println("Shutting down gracefully...")
			return
		case <-ticker.C:
			// Poll for jobs
			result, err := rdb.BLPop(ctx, 1*time.Second, queueName).Result()
			if err == redis.Nil {
				// No jobs available
				continue
			} else if err != nil {
				log.Printf("Error polling queue: %v", err)
				continue
			}

			// Process job
			job := result[1]
			processJob(job)
		}
	}
}

func processJob(job string) {
	start := time.Now()
	log.Printf("Processing job: %s", job)

	// Simulate work
	time.Sleep(2 * time.Second)

	duration := time.Since(start).Seconds()
	jobProcessingDuration.Observe(duration)
	jobsProcessed.Inc()

	log.Printf("Job completed in %.2fs", duration)
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}
