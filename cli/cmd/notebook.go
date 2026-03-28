package cmd

import (
	"encoding/json"
	"fmt"
	"strings"

	"chronicle/internal/storage"
	"github.com/spf13/cobra"
)

var notebookCmd = &cobra.Command{
	Use:   "notebook",
	Short: "Manage notebook folders",
	Long:  `Create, rename, delete, and list notebook folders.`,
}

var notebookListCmd = &cobra.Command{
	Use:   "list",
	Short: "List notebook folders",
	RunE: func(cmd *cobra.Command, args []string) error {
		rootPath, err := getStorageRoot()
		if err != nil {
			return err
		}

		layout := storage.NewChronicleLayout(rootPath)
		repo := storage.NewNotebookRepository(layout)

		folders, err := repo.ListFolders()
		if err != nil {
			return fmt.Errorf("failed to list folders: %w", err)
		}

		if jsonOutput {
			data, _ := json.MarshalIndent(folders, "", "  ")
			fmt.Println(string(data))
			return nil
		}

		if len(folders) == 0 {
			fmt.Println("No folders found")
			return nil
		}

		fmt.Printf("%-36s %-20s %s\n", "ID", "Name", "Parent")
		fmt.Println(strings.Repeat("-", 80))
		for _, f := range folders {
			name := f.Name
			if len(name) > 18 {
				name = name[:15] + "..."
			}
			parent := "-"
			if f.ParentID != nil {
				parent = (*f.ParentID)[:8] + "..."
			}
			fmt.Printf("%-36s %-20s %s\n", f.ID, name, parent)
		}

		return nil
	},
}

var notebookCreateCmd = &cobra.Command{
	Use:   "create",
	Short: "Create a notebook folder",
	RunE: func(cmd *cobra.Command, args []string) error {
		rootPath, err := getStorageRoot()
		if err != nil {
			return err
		}

		name, _ := cmd.Flags().GetString("name")
		if name == "" {
			return fmt.Errorf("--name is required")
		}

		parentID, _ := cmd.Flags().GetString("parent-id")
		var parentIDPtr *string
		if parentID != "" {
			parentIDPtr = &parentID
		}

		layout := storage.NewChronicleLayout(rootPath)
		repo := storage.NewNotebookRepository(layout)

		folder, err := repo.CreateFolder(name, parentIDPtr)
		if err != nil {
			return fmt.Errorf("failed to create folder: %w", err)
		}

		if jsonOutput {
			data, _ := json.MarshalIndent(folder, "", "  ")
			fmt.Println(string(data))
		} else {
			fmt.Printf("Created folder: %s (%s)\n", folder.Name, folder.ID)
		}

		return nil
	},
}

var notebookRenameCmd = &cobra.Command{
	Use:   "rename <id>",
	Short: "Rename a notebook folder",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		rootPath, err := getStorageRoot()
		if err != nil {
			return err
		}

		name, _ := cmd.Flags().GetString("name")
		if name == "" {
			return fmt.Errorf("--name is required")
		}

		layout := storage.NewChronicleLayout(rootPath)
		repo := storage.NewNotebookRepository(layout)

		folder, err := repo.RenameFolder(args[0], name)
		if err != nil {
			return fmt.Errorf("failed to rename folder: %w", err)
		}

		if jsonOutput {
			data, _ := json.MarshalIndent(folder, "", "  ")
			fmt.Println(string(data))
		} else {
			fmt.Printf("Renamed folder to: %s\n", folder.Name)
		}

		return nil
	},
}

var notebookDeleteCmd = &cobra.Command{
	Use:   "delete <id>",
	Short: "Delete a notebook folder (must be empty)",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		rootPath, err := getStorageRoot()
		if err != nil {
			return err
		}

		layout := storage.NewChronicleLayout(rootPath)
		repo := storage.NewNotebookRepository(layout)

		if err := repo.DeleteFolder(args[0]); err != nil {
			return fmt.Errorf("failed to delete folder: %w", err)
		}

		if jsonOutput {
			fmt.Println(`{"success": true}`)
		} else {
			fmt.Println("Folder deleted successfully")
		}

		return nil
	},
}

func init() {
	rootCmd.AddCommand(notebookCmd)
	notebookCmd.AddCommand(notebookListCmd)
	notebookCmd.AddCommand(notebookCreateCmd)
	notebookCmd.AddCommand(notebookRenameCmd)
	notebookCmd.AddCommand(notebookDeleteCmd)

	// Create flags
	notebookCreateCmd.Flags().String("name", "", "Folder name (required)")
	notebookCreateCmd.Flags().String("parent-id", "", "Parent folder ID")

	// Rename flags
	notebookRenameCmd.Flags().String("name", "", "New name (required)")
}
