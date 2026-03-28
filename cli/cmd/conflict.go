package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"chronicle/internal/storage"
	"github.com/spf13/cobra"
)

var conflictCmd = &cobra.Command{
	Use:   "conflict",
	Short: "Manage sync conflicts",
	Long:  `List, view, and resolve sync conflicts.`,
}

var conflictListCmd = &cobra.Command{
	Use:   "list",
	Short: "List all conflicts",
	RunE: func(cmd *cobra.Command, args []string) error {
		rootPath, err := getStorageRoot()
		if err != nil {
			return err
		}

		layout := storage.NewChronicleLayout(rootPath)

		conflictPaths, err := layout.ListConflictFiles()
		if err != nil {
			return fmt.Errorf("failed to list conflicts: %w", err)
		}

		if jsonOutput {
			type ConflictInfo struct {
				Path         string `json:"path"`
				OriginalPath string `json:"originalPath"`
				DetectedAt   string `json:"detectedAt"`
			}

			var results []ConflictInfo
			for _, path := range conflictPaths {
				fullPath := filepath.Join(rootPath, path)
				content, err := os.ReadFile(fullPath)
				if err != nil {
					continue
				}

				conflict, err := storage.ParseConflictFile(string(content))
				if err != nil {
					results = append(results, ConflictInfo{Path: path})
					continue
				}

				results = append(results, ConflictInfo{
					Path:         path,
					OriginalPath: conflict.OriginalPath,
					DetectedAt:   conflict.ConflictDetected,
				})
			}

			data, _ := json.MarshalIndent(results, "", "  ")
			fmt.Println(string(data))
			return nil
		}

		if len(conflictPaths) == 0 {
			fmt.Println("No conflicts found")
			return nil
		}

		fmt.Printf("Found %d conflict(s):\n\n", len(conflictPaths))
		fmt.Printf("%-50s %s\n", "Conflict File", "Original")
		fmt.Println(strings.Repeat("-", 100))

		for _, path := range conflictPaths {
			displayPath := path
			if len(displayPath) > 48 {
				displayPath = "..." + displayPath[len(displayPath)-45:]
			}

			fullPath := filepath.Join(rootPath, path)
			content, err := os.ReadFile(fullPath)
			originalPath := "unknown"
			if err == nil {
				conflict, err := storage.ParseConflictFile(string(content))
				if err == nil {
					originalPath = conflict.OriginalPath
				}
			}

			if len(originalPath) > 45 {
				originalPath = originalPath[:42] + "..."
			}

			fmt.Printf("%-50s %s\n", displayPath, originalPath)
		}

		return nil
	},
}

var conflictShowCmd = &cobra.Command{
	Use:   "show <path>",
	Short: "Show conflict details",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		rootPath, err := getStorageRoot()
		if err != nil {
			return err
		}

		conflictPath := args[0]
		if !strings.Contains(conflictPath, ".conflict.") {
			// Try to find the conflict file for this original path
			layout := storage.NewChronicleLayout(rootPath)
			allConflicts, _ := layout.ListConflictFiles()
			for _, c := range allConflicts {
				if strings.Contains(c, conflictPath) {
					conflictPath = c
					break
				}
			}
		}

		fullPath := filepath.Join(rootPath, conflictPath)
		content, err := os.ReadFile(fullPath)
		if err != nil {
			return fmt.Errorf("conflict file not found: %s", conflictPath)
		}

		conflict, err := storage.ParseConflictFile(string(content))
		if err != nil {
			return fmt.Errorf("failed to parse conflict file: %w", err)
		}

		if jsonOutput {
			data, _ := json.MarshalIndent(conflict, "", "  ")
			fmt.Println(string(data))
			return nil
		}

		fmt.Println("=== Conflict Details ===")
		fmt.Printf("Path:               %s\n", conflictPath)
		fmt.Printf("Original Path:      %s\n", conflict.OriginalPath)
		fmt.Printf("Detected At:        %s\n", conflict.ConflictDetected)
		fmt.Printf("Local Device:       %s\n", conflict.LocalDevice)
		fmt.Printf("Remote Device:      %s\n", conflict.RemoteDevice)
		fmt.Printf("Local Content Hash: %s\n", conflict.LocalContentHash)
		fmt.Printf("Remote Content Hash: %s\n", conflict.RemoteContentHash)

		fmt.Println("\nTo resolve:")
		fmt.Printf("  chronicle conflict resolve %s --accept local   # Keep local version\n", conflictPath)
		fmt.Printf("  chronicle conflict resolve %s --accept remote  # Keep remote version\n", conflictPath)

		return nil
	},
}

var conflictResolveCmd = &cobra.Command{
	Use:   "resolve <path>",
	Short: "Resolve a conflict",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		rootPath, err := getStorageRoot()
		if err != nil {
			return err
		}

		accept, _ := cmd.Flags().GetString("accept")
		if accept != "local" && accept != "remote" {
			return fmt.Errorf("--accept must be 'local' or 'remote'")
		}

		conflictPath := args[0]
		if !strings.Contains(conflictPath, ".conflict.") {
			// Try to find the conflict file for this original path
			layout := storage.NewChronicleLayout(rootPath)
			allConflicts, _ := layout.ListConflictFiles()
			for _, c := range allConflicts {
				if strings.Contains(c, conflictPath) {
					conflictPath = c
					break
				}
			}
		}

		fullConflictPath := filepath.Join(rootPath, conflictPath)
		content, err := os.ReadFile(fullConflictPath)
		if err != nil {
			return fmt.Errorf("conflict file not found: %s", conflictPath)
		}

		conflict, err := storage.ParseConflictFile(string(content))
		if err != nil {
			return fmt.Errorf("failed to parse conflict file: %w", err)
		}

		originalPath := filepath.Join(rootPath, conflict.OriginalPath)

		if accept == "local" {
			// Extract content from conflict file (after the second ---)
			parts := strings.SplitN(string(content), "---\n", 3)
			if len(parts) >= 3 {
				localContent := parts[2]
				// Remove the conflict header line
				lines := strings.SplitN(localContent, "\n", 2)
				if len(lines) > 1 {
					localContent = lines[1]
				}

				if err := os.WriteFile(originalPath, []byte(localContent), 0644); err != nil {
					return fmt.Errorf("failed to write local version: %w", err)
				}
			}
		}
		// For "remote", do nothing - the remote version is already in the original file

		// Delete conflict file
		if err := os.Remove(fullConflictPath); err != nil {
			return fmt.Errorf("failed to remove conflict file: %w", err)
		}

		if jsonOutput {
			fmt.Println(`{"success": true}`)
		} else {
			fmt.Printf("Conflict resolved: kept %s version\n", accept)
		}

		return nil
	},
}

func init() {
	rootCmd.AddCommand(conflictCmd)
	conflictCmd.AddCommand(conflictListCmd)
	conflictCmd.AddCommand(conflictShowCmd)
	conflictCmd.AddCommand(conflictResolveCmd)

	conflictResolveCmd.Flags().String("accept", "", "Accept 'local' or 'remote' version (required)")
}
