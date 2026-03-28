package cmd

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"chronicle/internal/domain"
	"github.com/google/uuid"
	"github.com/spf13/cobra"
)

// configCmd is the parent command for config management
var configCmd = &cobra.Command{
	Use:   "config",
	Short: "Manage Chronicle CLI configuration",
	Long:  `Configure the Chronicle CLI including storage location and WebDAV sync settings.`,
}

// Config holds the CLI configuration
type Config struct {
	StorageRoot string             `json:"storageRoot"`
	WebDAV      domain.SyncConfig  `json:"webdav"`
	ClientID    string             `json:"clientId"`
}

// configInitCmd initializes the configuration interactively
var configInitCmd = &cobra.Command{
	Use:   "init",
	Short: "Initialize configuration interactively",
	Long:  `Sets up the Chronicle CLI by prompting for storage location and WebDAV credentials.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		reader := bufio.NewReader(os.Stdin)

		fmt.Println("=== Chronicle CLI Configuration ===")
		fmt.Println()

		// Storage root
		defaultRoot := filepath.Join(os.Getenv("HOME"), "Chronicle")
		fmt.Printf("Storage root [%s]: ", defaultRoot)
		storageRoot, _ := reader.ReadString('\n')
		storageRoot = strings.TrimSpace(storageRoot)
		if storageRoot == "" {
			storageRoot = defaultRoot
		}

		// Expand ~ to home directory
		if strings.HasPrefix(storageRoot, "~/") {
			storageRoot = filepath.Join(os.Getenv("HOME"), storageRoot[2:])
		}

		// WebDAV URL
		fmt.Print("WebDAV URL (e.g., https://example.com/webdav): ")
		webdavURL, _ := reader.ReadString('\n')
		webdavURL = strings.TrimSpace(webdavURL)

		// WebDAV username
		fmt.Print("WebDAV username: ")
		username, _ := reader.ReadString('\n')
		username = strings.TrimSpace(username)

		// WebDAV password
		fmt.Print("WebDAV password: ")
		password, _ := reader.ReadString('\n')
		password = strings.TrimSpace(password)

		// Remote path
		defaultRemotePath := "/chronicle"
		fmt.Printf("Remote path on WebDAV [%s]: ", defaultRemotePath)
		remotePath, _ := reader.ReadString('\n')
		remotePath = strings.TrimSpace(remotePath)
		if remotePath == "" {
			remotePath = defaultRemotePath
		}

		// Generate client ID
		clientID := uuid.New().String()

		cfg := Config{
			StorageRoot: storageRoot,
			WebDAV: domain.SyncConfig{
				URL:        webdavURL,
				Username:   username,
				Password:   password,
				RemotePath: remotePath,
			},
			ClientID: clientID,
		}

		if err := saveConfig(cfg); err != nil {
			return fmt.Errorf("failed to save config: %w", err)
		}

		// Create storage directory if it doesn't exist
		if err := os.MkdirAll(storageRoot, 0755); err != nil {
			return fmt.Errorf("failed to create storage directory: %w", err)
		}

		// Create info.json
		infoPath := filepath.Join(storageRoot, "info.json")
		if _, err := os.Stat(infoPath); os.IsNotExist(err) {
			info := map[string]interface{}{
				"version":   2,
				"createdAt": domain.NowISO(),
			}
			data, _ := json.MarshalIndent(info, "", "  ")
			os.WriteFile(infoPath, data, 0644)
		}

		fmt.Println()
		fmt.Println("Configuration saved successfully!")
		fmt.Printf("Storage root: %s\n", storageRoot)
		fmt.Printf("Client ID: %s\n", clientID)
		fmt.Println()
		fmt.Println("Next steps:")
		fmt.Println("  chronicle sync bootstrap    # Assess initial sync state")
		fmt.Println("  chronicle sync now          # Perform initial sync")

		return nil
	},
}

// configShowCmd shows current configuration
var configShowCmd = &cobra.Command{
	Use:   "show",
	Short: "Show current configuration",
	RunE: func(cmd *cobra.Command, args []string) error {
		cfg, err := loadConfig()
		if err != nil {
			return fmt.Errorf("no configuration found. Run 'chronicle config init'")
		}

		if jsonOutput {
			// Redact password for security
			cfg.WebDAV.Password = "***"
			data, _ := json.MarshalIndent(cfg, "", "  ")
			fmt.Println(string(data))
			return nil
		}

		fmt.Println("=== Chronicle Configuration ===")
		fmt.Printf("Storage root: %s\n", cfg.StorageRoot)
		fmt.Printf("Client ID: %s\n", cfg.ClientID)
		fmt.Println()
		fmt.Println("WebDAV Configuration:")
		fmt.Printf("  URL: %s\n", cfg.WebDAV.URL)
		fmt.Printf("  Username: %s\n", cfg.WebDAV.Username)
		fmt.Printf("  Password: %s\n", "***")
		fmt.Printf("  Remote path: %s\n", cfg.WebDAV.RemotePath)

		return nil
	},
}

// configGetCmd gets a specific config value
var configGetCmd = &cobra.Command{
	Use:   "get <key>",
	Short: "Get a configuration value",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		cfg, err := loadConfig()
		if err != nil {
			return fmt.Errorf("no configuration found")
		}

		key := args[0]
		switch key {
		case "storageRoot":
			fmt.Println(cfg.StorageRoot)
		case "webdav.url":
			fmt.Println(cfg.WebDAV.URL)
		case "webdav.username":
			fmt.Println(cfg.WebDAV.Username)
		case "webdav.remotePath":
			fmt.Println(cfg.WebDAV.RemotePath)
		case "clientId":
			fmt.Println(cfg.ClientID)
		default:
			return fmt.Errorf("unknown config key: %s", key)
		}

		return nil
	},
}

// configSetCmd sets a specific config value
var configSetCmd = &cobra.Command{
	Use:   "set <key> <value>",
	Short: "Set a configuration value",
	Args:  cobra.ExactArgs(2),
	RunE: func(cmd *cobra.Command, args []string) error {
		cfg, err := loadConfig()
		if err != nil {
			return fmt.Errorf("no configuration found. Run 'chronicle config init'")
		}

		key, value := args[0], args[1]
		switch key {
		case "storageRoot":
			cfg.StorageRoot = value
		case "webdav.url":
			cfg.WebDAV.URL = value
		case "webdav.username":
			cfg.WebDAV.Username = value
		case "webdav.password":
			cfg.WebDAV.Password = value
		case "webdav.remotePath":
			cfg.WebDAV.RemotePath = value
		default:
			return fmt.Errorf("unknown config key: %s", key)
		}

		if err := saveConfig(cfg); err != nil {
			return fmt.Errorf("failed to save config: %w", err)
		}

		fmt.Printf("Set %s = %s\n", key, value)
		return nil
	},
}

func init() {
	rootCmd.AddCommand(configCmd)
	configCmd.AddCommand(configInitCmd)
	configCmd.AddCommand(configShowCmd)
	configCmd.AddCommand(configGetCmd)
	configCmd.AddCommand(configSetCmd)
}

// getConfigPath returns the path to the config file
func getConfigPath() string {
	if envConfig := os.Getenv("CHRONICLE_CONFIG"); envConfig != "" {
		return envConfig
	}
	return filepath.Join(os.Getenv("HOME"), ".config", "chronicle", "config.json")
}

// loadConfig loads the configuration from disk
func loadConfig() (Config, error) {
	var cfg Config

	configPath := getConfigPath()
	data, err := os.ReadFile(configPath)
	if err != nil {
		return cfg, err
	}

	if err := json.Unmarshal(data, &cfg); err != nil {
		return cfg, err
	}

	return cfg, nil
}

// saveConfig saves the configuration to disk
func saveConfig(cfg Config) error {
	configPath := getConfigPath()
	configDir := filepath.Dir(configPath)

	if err := os.MkdirAll(configDir, 0755); err != nil {
		return err
	}

	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return err
	}

	return os.WriteFile(configPath, data, 0600)
}
