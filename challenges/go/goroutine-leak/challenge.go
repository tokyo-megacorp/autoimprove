package search

import (
	"context"
	"fmt"
	"sync"
	"time"
)

// Result represents a search result from a backend.
type Result struct {
	Backend string
	Items   []string
	Latency time.Duration
}

// Query simulates a search query to a backend.
// In a real implementation, this would call an actual backend service.
func Query(ctx context.Context, backend, query string) (Result, error) {
	// Simulate network latency
	select {
	case <-time.After(100 * time.Millisecond):
		return Result{
			Backend: backend,
			Items:   []string{fmt.Sprintf("result-%s-1", backend), fmt.Sprintf("result-%s-2", backend)},
			Latency: 100 * time.Millisecond,
		}, nil
	case <-ctx.Done():
		return Result{}, ctx.Err()
	}
}

// Search queries multiple backends and returns the first result.
// BUG: This function has a goroutine leak due to an unbuffered channel.
func Search(query string, backends []string) (Result, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	// BUG: goroutine leak
	ch := make(chan Result)
	var wg sync.WaitGroup

	for _, backend := range backends {
		wg.Add(1)
		go func(b string) {
			defer wg.Done()
			result, err := Query(ctx, b, query)
			if err == nil {
				ch <- result
			}
		}(backend)
	}

	// Return the first result and ignore the rest.
	// The remaining goroutines are blocked forever on ch <- result.
	select {
	case result := <-ch:
		return result, nil
	case <-ctx.Done():
		return Result{}, ctx.Err()
	}
	// Note: wg.Wait() is never called; goroutines leak
}

// SearchAll queries all backends and returns all results.
// This is the correct implementation that avoids the goroutine leak.
func SearchAll(query string, backends []string) ([]Result, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	// Use a buffered channel to prevent goroutines from blocking.
	ch := make(chan Result, len(backends))
	var wg sync.WaitGroup

	for _, backend := range backends {
		wg.Add(1)
		go func(b string) {
			defer wg.Done()
			result, err := Query(ctx, b, query)
			if err == nil {
				ch <- result
			}
		}(backend)
	}

	// Wait for all goroutines to complete in a separate goroutine.
	go func() {
		wg.Wait()
		close(ch)
	}()

	var results []Result
	for result := range ch {
		results = append(results, result)
	}
	return results, nil
}
