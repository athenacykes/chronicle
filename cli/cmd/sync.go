package cmd

import (
	"encoding/json"
	"fmt"
	"os"

	"chronicle/internal/storage"
	"chronicle/internal/sync"
	"github.com/spf13/cobra"
)

var syncCmd = &cobra.Command{
	Use:   "sync",
	Short: "WebDAV sync operations",
	Long:  `Sync with WebDAV server, check status, and manage sync conflicts.`,
}

var syncNowCmd = &cobra.Command{
	Use:   "now",
	Short: "Perform sync now",
	RunE: func(cmd *cobra.Command, args []string) error {
		rootPath, err := getStorageRoot()
		if err != nil {
			return err
		}

		cfg, err := loadConfig()
		if err != nil {
			return fmt.Errorf("failed to load config: %w", err)
		}

		if cfg.WebDAV.URL == "" {
			return fmt.Errorf("WebDAV not configured. Run 'chronicle config init'")
		}

		modeStr, _ := cmd.Flags().GetString("mode")
		mode := sync.SyncRunMode(modeStr)

		layout := storage.NewChronicleLayout(rootPath)
		client := sync.NewWebDAVClient(cfg.WebDAV.URL, cfg.WebDAV.Username, cfg.WebDAV.Password, false)
		engine := sync.NewEngine(client, layout, "cli", cfg.ClientID, cfg.WebDAV.RemotePath)

		options := sync.SyncRunOptions{
			Mode: mode,
			OnProgress: func(message string, progress float64) {
				if !jsonOutput {
					fmt.Printf("[%.0f%%] %s\n", progress*100, message)
				}
			},
		}

		result, err := engine.Sync(options)
		if err != nil {
			// Continue to show result even on error
		}

		if jsonOutput {
			data, _ := json.MarshalIndent(result, "", "  ")
			fmt.Println(string(data))
			if !result.Success {
				os.Exit(1)
			}
			return nil
		}

		fmt.Println()
		fmt.Println("=== Sync Result ===")
		fmt.Printf("Success:    %v\n", result.Success)
		fmt.Printf("Uploaded:   %d\n", result.Uploaded)
		fmt.Printf("Downloaded: %d\n", result.Downloaded)
		fmt.Printf("Deleted:    %d\n", result.Deleted)
		fmt.Printf("Conflicts:  %d\n", result.Conflicts)
		fmt.Printf("Duration:   %v\n", result.Duration)

		if len(result.Errors) > 0 {
			fmt.Println("\nErrors:")
			for _, e := range result.Errors {
				fmt.Printf("  - %s\n", e)
			}
		}

		if !result.Success {
			os.Exit(1)
		}

		return nil
	},
}

var syncStatusCmd = &cobra.Command{
	Use:   "status",
	Short: "Check sync status",
	RunE: func(cmd *cobra.Command, args []string) error {
		rootPath, err := getStorageRoot()
		if err != nil {
			return err
		}

		cfg, err := loadConfig()
		if err != nil {
			return fmt.Errorf("failed to load config: %w", err)
		}

		layout := storage.NewChronicleLayout(rootPath)
		client := sync.NewWebDAVClient(cfg.WebDAV.URL, cfg.WebDAV.Username, cfg.WebDAV.Password, false)
		engine := sync.NewEngine(client, layout, "cli", cfg.ClientID, cfg.WebDAV.RemotePath)

		status, err := engine.Status()
		if err != nil {
			return fmt.Errorf("failed to get status: %w", err)
		}

		if jsonOutput {
			data, _ := json.MarshalIndent(status, "", "  ")
			fmt.Println(string(data))
			return nil
		}

		fmt.Println("=== Sync Status ===")
		if status.LastSyncAt != nil {
			fmt.Printf("Last sync: %s\n", *status.LastSyncAt)
			fmt.Printf("Success:   %v\n", status.LastSyncSuccess)
		} else {
			fmt.Println("No sync has been performed yet")
		}

		return nil
	},
}

var syncBootstrapCmd = &cobra.Command{
	Use:   "bootstrap",
	Short: "Assess initial sync state",
	RunE: func(cmd *cobra.Command, args []string) error {
		rootPath, err := getStorageRoot()
		if err != nil {
			return err
		}

		cfg, err := loadConfig()
		if err != nil {
			return fmt.Errorf("failed to load config: %w", err)
		}

		if cfg.WebDAV.URL == "" {
			return fmt.Errorf("WebDAV not configured. Run 'chronicle config init'")
		}

		layout := storage.NewChronicleLayout(rootPath)
		client := sync.NewWebDAVClient(cfg.WebDAV.URL, cfg.WebDAV.Username, cfg.WebDAV.Password, false)
		engine := sync.NewEngine(client, layout, "cli", cfg.ClientID, cfg.WebDAV.RemotePath)

		assessment, err := engine.AssessBootstrap()
		if err != nil {
			return fmt.Errorf("bootstrap assessment failed: %w", err)
		}

		if jsonOutput {
			data, _ := json.MarshalIndent(assessment, "", "  ")
			fmt.Println(string(data))
			return nil
		}

		fmt.Println("=== Bootstrap Assessment ===")
		fmt.Printf("Local items:  %d\n", assessment.LocalItemCount)
		fmt.Printf("Remote items: %d\n", assessment.RemoteItemCount)
		fmt.Printf("Local has data:  %v\n", assessment.LocalHasData)
		fmt.Printf("Remote has data: %v\n", assessment.RemoteHasData)
		fmt.Println()
		fmt.Printf("Recommendation: %s\n", assessment.Recommendation)

		return nil
	},
}

func init() {
	rootCmd.AddCommand(syncCmd)
	syncCmd.AddCommand(syncNowCmd)
	syncCmd.AddCommand(syncStatusCmd)
	syncCmd.AddCommand(syncBootstrapCmd)

	// Sync now flags
	syncNowCmd.Flags().String("mode", "normal", "Sync mode: normal, force-apply-deletions, force-break-lock, recover-local-wins, recover-remote-wins")
}
