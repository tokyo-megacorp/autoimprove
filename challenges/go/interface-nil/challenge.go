package logger

import (
	"fmt"
	"io"
	"os"
	"sync"
)

// Logger defines the interface for a logger.
type Logger interface {
	Log(level, msg string)
	Close() error
}

// FileLogger implements Logger by writing to a file.
type FileLogger struct {
	file *os.File
	mu   sync.Mutex
}

// Log writes a message with the given level to the file.
func (fl *FileLogger) Log(level, msg string) {
	fl.mu.Lock()
	defer fl.mu.Unlock()
	if fl.file != nil {
		fmt.Fprintf(fl.file, "[%s] %s\n", level, msg)
	}
}

// Close closes the underlying file.
func (fl *FileLogger) Close() error {
	fl.mu.Lock()
	defer fl.mu.Unlock()
	if fl.file != nil {
		return fl.file.Close()
	}
	return nil
}

// NoOpLogger is a no-op logger that discards all messages.
type NoOpLogger struct{}

// Log discards the message.
func (nl *NoOpLogger) Log(level, msg string) {}

// Close is a no-op.
func (nl *NoOpLogger) Close() error { return nil }

// NewLogger creates a new logger based on the given config.
// Supported configs: "file", "discard", "none".
//
// BUG: The "none" case returns a typed nil — the interface is non-nil but wraps a nil pointer.
func NewLogger(config string) (Logger, error) {
	switch config {
	case "file":
		file, err := os.OpenFile("/tmp/app.log", os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
		if err != nil {
			return nil, err
		}
		return &FileLogger{file: file}, nil
	case "discard":
		return &NoOpLogger{}, nil
	case "none":
		// BUG: typed nil — interface is non-nil but wraps nil pointer
		var fl *FileLogger
		return fl, nil
	default:
		return nil, fmt.Errorf("unknown logger config: %s", config)
	}
}

// Setup initializes a logger from the given config and uses it.
// This function will panic if the logger returned from NewLogger is "none"
// because the interface check does not catch the typed nil.
func Setup(config string) error {
	logger, err := NewLogger(config)
	if err != nil {
		return err
	}

	// BUG: This check always passes because the interface is non-nil,
	// even though it wraps a nil pointer. The next line will panic.
	if logger != nil {
		logger.Log("INFO", "Setup complete")
		if err := logger.Close(); err != nil {
			return err
		}
	}
	return nil
}

// Discard returns a properly initialized no-op logger.
// This is the correct way to handle the "no logging" case.
func Discard() Logger {
	return &NoOpLogger{}
}
