package cmd

import (
	"encoding/json"
	"fmt"
	"strings"

	"chronicle/internal/storage"
	"github.com/spf13/cobra"
)

var categoryCmd = &cobra.Command{
	Use:   "category",
	Short: "Manage categories",
	Long:  `Create, update, delete, and list categories for organizing matters.`,
}

var categoryListCmd = &cobra.Command{
	Use:   "list",
	Short: "List all categories",
	RunE: func(cmd *cobra.Command, args []string) error {
		rootPath, err := getStorageRoot()
		if err != nil {
			return err
		}

		layout := storage.NewChronicleLayout(rootPath)
		repo := storage.NewCategoryRepository(layout)

		categories, err := repo.List()
		if err != nil {
			return fmt.Errorf("failed to list categories: %w", err)
		}

		if jsonOutput {
			data, _ := json.MarshalIndent(categories, "", "  ")
			fmt.Println(string(data))
			return nil
		}

		if len(categories) == 0 {
			fmt.Println("No categories found")
			return nil
		}

		fmt.Printf("%-36s %-20s %s\n", "ID", "Name", "Color")
		fmt.Println(strings.Repeat("-", 70))
		for _, c := range categories {
			name := c.Name
			if len(name) > 18 {
				name = name[:15] + "..."
			}
			fmt.Printf("%-36s %-20s %s\n", c.ID, name, c.Color)
		}

		return nil
	},
}

var categoryCreateCmd = &cobra.Command{
	Use:   "create",
	Short: "Create a new category",
	RunE: func(cmd *cobra.Command, args []string) error {
		rootPath, err := getStorageRoot()
		if err != nil {
			return err
		}

		name, _ := cmd.Flags().GetString("name")
		if name == "" {
			return fmt.Errorf("--name is required")
		}

		color, _ := cmd.Flags().GetString("color")
		icon, _ := cmd.Flags().GetString("icon")

		layout := storage.NewChronicleLayout(rootPath)
		repo := storage.NewCategoryRepository(layout)

		category, err := repo.Create(name, color, icon)
		if err != nil {
			return fmt.Errorf("failed to create category: %w", err)
		}

		if jsonOutput {
			data, _ := json.MarshalIndent(category, "", "  ")
			fmt.Println(string(data))
		} else {
			fmt.Printf("Created category: %s (%s)\n", category.Name, category.ID)
		}

		return nil
	},
}

var categoryUpdateCmd = &cobra.Command{
	Use:   "update <id>",
	Short: "Update a category",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		rootPath, err := getStorageRoot()
		if err != nil {
			return err
		}

		layout := storage.NewChronicleLayout(rootPath)
		repo := storage.NewCategoryRepository(layout)

		category, err := repo.GetByID(args[0])
		if err != nil {
			return fmt.Errorf("category not found: %s", args[0])
		}

		if cmd.Flags().Changed("name") {
			name, _ := cmd.Flags().GetString("name")
			category.Name = name
		}
		if cmd.Flags().Changed("color") {
			color, _ := cmd.Flags().GetString("color")
			category.Color = color
		}
		if cmd.Flags().Changed("icon") {
			icon, _ := cmd.Flags().GetString("icon")
			category.Icon = icon
		}

		if err := repo.Update(category); err != nil {
			return fmt.Errorf("failed to update category: %w", err)
		}

		if jsonOutput {
			data, _ := json.MarshalIndent(category, "", "  ")
			fmt.Println(string(data))
		} else {
			fmt.Printf("Updated category: %s\n", category.ID)
		}

		return nil
	},
}

var categoryDeleteCmd = &cobra.Command{
	Use:   "delete <id>",
	Short: "Delete a category",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		rootPath, err := getStorageRoot()
		if err != nil {
			return err
		}

		layout := storage.NewChronicleLayout(rootPath)
		repo := storage.NewCategoryRepository(layout)

		if err := repo.Delete(args[0]); err != nil {
			return fmt.Errorf("failed to delete category: %w", err)
		}

		if jsonOutput {
			fmt.Println(`{"success": true}`)
		} else {
			fmt.Println("Category deleted successfully")
		}

		return nil
	},
}

func init() {
	rootCmd.AddCommand(categoryCmd)
	categoryCmd.AddCommand(categoryListCmd)
	categoryCmd.AddCommand(categoryCreateCmd)
	categoryCmd.AddCommand(categoryUpdateCmd)
	categoryCmd.AddCommand(categoryDeleteCmd)

	// Create flags
	categoryCreateCmd.Flags().String("name", "", "Category name (required)")
	categoryCreateCmd.Flags().String("color", "#4C956C", "Color (hex)")
	categoryCreateCmd.Flags().String("icon", "folder", "Icon name")

	// Update flags
	categoryUpdateCmd.Flags().String("name", "", "New name")
	categoryUpdateCmd.Flags().String("color", "", "New color")
	categoryUpdateCmd.Flags().String("icon", "", "New icon")
}
