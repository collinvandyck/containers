package main

import (
	"context"
	"fmt"
	"time"

	"go.temporal.io/sdk/workflow"
)

func GreetingWorkflow(ctx workflow.Context, name string) (string, error) {
	ctx = workflow.WithActivityOptions(ctx, workflow.ActivityOptions{
		StartToCloseTimeout: 5 * time.Second,
	})
	var greeting string
	if err := workflow.ExecuteActivity(ctx, BuildGreeting, name).Get(ctx, &greeting); err != nil {
		return "", err
	}
	return greeting, nil
}

func BuildGreeting(_ context.Context, name string) (string, error) {
	return fmt.Sprintf("Hello, %s!", name), nil
}
