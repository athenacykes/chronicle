package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
)

var (
	// Global flags
	jsonOutput bool
	rootPath   string
)

var rootCmd = &cobra.Command{
	Use:   "chronicle",
	Short: "Chronicle CLI - manage your notes from the terminal",
	Long: `Chronicle CLI provides command-line access to your Chronicle notes.

The CLI operates on the same local storage and WebDAV sync contracts as the Flutter app,
allowing you to manage matters, notes, notebooks, and categories from the terminal.

Get started:
  chronicle config init    # Configure WebDAV sync and storage location
  chronicle matter list    # List all matters
  chronicle note list      # List all notes
  chronicle sync now       # Sync with WebDAV
`,
}

func Execute() error {
	return rootCmd.Execute()
}

func init() {
	rootCmd.PersistentFlags().BoolVar(&jsonOutput, "json", false, "Output in JSON format")
	rootCmd.PersistentFlags().StringVar(&rootPath, "root", "", "Chronicle storage root path (overrides config)")
}

// getStorageRoot returns the storage root path, checking flags and config
func getStorageRoot() (string, error) {
	if rootPath != "" {
		return rootPath, nil
	}

	// Check environment variable
	if envRoot := os.Getenv("CHRONICLE_STORAGE_ROOT"); envRoot != "" {
		return envRoot, nil
	}

	// Try to load from config
	cfg, err := loadConfig()
	if err != nil {
		return "", fmt.Errorf("storage root not configured. Run 'chronicle config init' or set --root flag")
	}

	if cfg.StorageRoot == "" {
		return "", fmt.Errorf("storage root not configured. Run 'chronicle config init' or set --root flag")
	}

	return cfg.StorageRoot, nil
}
