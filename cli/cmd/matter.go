package cmd

import (
	"encoding/json"
	"fmt"
	"strings"

	"chronicle/internal/domain"
	"chronicle/internal/storage"
	"github.com/spf13/cobra"
)

var matterCmd = &cobra.Command{
	Use:   "matter",
	Short: "Manage matters",
	Long:  `Create, update, delete, and list matters (projects).`,
}

var matterListCmd = &cobra.Command{
	Use:   "list",
	Short: "List all matters",
	RunE: func(cmd *cobra.Command, args []string) error {
		rootPath, err := getStorageRoot()
		if err != nil {
			return err
		}

		layout := storage.NewChronicleLayout(rootPath)
		repo := storage.NewMatterRepository(layout)

		matters, err := repo.List()
		if err != nil {
			return fmt.Errorf("failed to list matters: %w", err)
		}

		// Filter by category if specified
		categoryID, _ := cmd.Flags().GetString("category-id")
		if categoryID != "" {
			var filtered []domain.Matter
			for _, m := range matters {
				if m.CategoryID != nil && *m.CategoryID == categoryID {
					filtered = append(filtered, m)
				}
			}
			matters = filtered
		}

		if jsonOutput {
			data, _ := json.MarshalIndent(matters, "", "  ")
			fmt.Println(string(data))
			return nil
		}

		if len(matters) == 0 {
			fmt.Println("No matters found")
			return nil
		}

		fmt.Printf("%-36s %-20s %-12s %s\n", "ID", "Title", "Status", "Pinned")
		fmt.Println(strings.Repeat("-", 90))
		for _, m := range matters {
			title := m.Title
			if len(title) > 18 {
				title = title[:15] + "..."
			}
			pinned := " "
			if m.IsPinned {
				pinned = "*"
			}
			fmt.Printf("%-36s %-20s %-12s %s\n", m.ID, title, m.Status, pinned)
		}

		return nil
	},
}

var matterGetCmd = &cobra.Command{
	Use:   "get <id>",
	Short: "Get a matter by ID",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		rootPath, err := getStorageRoot()
		if err != nil {
			return err
		}

		layout := storage.NewChronicleLayout(rootPath)
		repo := storage.NewMatterRepository(layout)

		matter, err := repo.GetByID(args[0])
		if err != nil {
			return fmt.Errorf("matter not found: %s", args[0])
		}

		if jsonOutput {
			data, _ := json.MarshalIndent(matter, "", "  ")
			fmt.Println(string(data))
			return nil
		}

		fmt.Printf("ID:          %s\n", matter.ID)
		fmt.Printf("Title:       %s\n", matter.Title)
		fmt.Printf("Description: %s\n", matter.Description)
		fmt.Printf("Status:      %s\n", matter.Status)
		fmt.Printf("Color:       %s\n", matter.Color)
		fmt.Printf("Icon:        %s\n", matter.Icon)
		fmt.Printf("Pinned:      %v\n", matter.IsPinned)
		fmt.Printf("Created:     %s\n", matter.CreatedAt)
		fmt.Printf("Updated:     %s\n", matter.UpdatedAt)
		if matter.CategoryID != nil {
			fmt.Printf("Category:    %s\n", *matter.CategoryID)
		}
		fmt.Printf("\nPhases (%d):\n", len(matter.Phases))
		for _, p := range matter.Phases {
			current := ""
			if matter.CurrentPhaseID != nil && *matter.CurrentPhaseID == p.ID {
				current = " (current)"
			}
			fmt.Printf("  %d. %s%s\n", p.Order, p.Name, current)
		}

		return nil
	},
}

var matterCreateCmd = &cobra.Command{
	Use:   "create",
	Short: "Create a new matter",
	RunE: func(cmd *cobra.Command, args []string) error {
		rootPath, err := getStorageRoot()
		if err != nil {
			return err
		}

		title, _ := cmd.Flags().GetString("title")
		if title == "" {
			return fmt.Errorf("--title is required")
		}

		description, _ := cmd.Flags().GetString("description")
		color, _ := cmd.Flags().GetString("color")
		icon, _ := cmd.Flags().GetString("icon")
		categoryID, _ := cmd.Flags().GetString("category-id")

		layout := storage.NewChronicleLayout(rootPath)
		repo := storage.NewMatterRepository(layout)

		var catIDPtr *string
		if categoryID != "" {
			catIDPtr = &categoryID
		}

		matter, err := repo.Create(title, description, catIDPtr, color, icon)
		if err != nil {
			return fmt.Errorf("failed to create matter: %w", err)
		}

		if jsonOutput {
			data, _ := json.MarshalIndent(matter, "", "  ")
			fmt.Println(string(data))
		} else {
			fmt.Printf("Created matter: %s (%s)\n", matter.Title, matter.ID)
		}

		return nil
	},
}

var matterUpdateCmd = &cobra.Command{
	Use:   "update <id>",
	Short: "Update a matter",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		rootPath, err := getStorageRoot()
		if err != nil {
			return err
		}

		layout := storage.NewChronicleLayout(rootPath)
		repo := storage.NewMatterRepository(layout)

		matter, err := repo.GetByID(args[0])
		if err != nil {
			return fmt.Errorf("matter not found: %s", args[0])
		}

		if cmd.Flags().Changed("title") {
			title, _ := cmd.Flags().GetString("title")
			matter.Title = title
		}
		if cmd.Flags().Changed("description") {
			description, _ := cmd.Flags().GetString("description")
			matter.Description = description
		}
		if cmd.Flags().Changed("color") {
			color, _ := cmd.Flags().GetString("color")
			matter.Color = color
		}
		if cmd.Flags().Changed("icon") {
			icon, _ := cmd.Flags().GetString("icon")
			matter.Icon = icon
		}
		if cmd.Flags().Changed("category-id") {
			categoryID, _ := cmd.Flags().GetString("category-id")
			var catIDPtr *string
			if categoryID != "" {
				catIDPtr = &categoryID
			}
			matter.CategoryID = catIDPtr
		}

		if err := repo.Update(matter); err != nil {
			return fmt.Errorf("failed to update matter: %w", err)
		}

		if jsonOutput {
			data, _ := json.MarshalIndent(matter, "", "  ")
			fmt.Println(string(data))
		} else {
			fmt.Printf("Updated matter: %s\n", matter.ID)
		}

		return nil
	},
}

var matterDeleteCmd = &cobra.Command{
	Use:   "delete <id>",
	Short: "Delete a matter and all its notes",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		rootPath, err := getStorageRoot()
		if err != nil {
			return err
		}

		layout := storage.NewChronicleLayout(rootPath)
		repo := storage.NewMatterRepository(layout)

		matter, err := repo.GetByID(args[0])
		if err != nil {
			return fmt.Errorf("matter not found: %s", args[0])
		}

		if !jsonOutput {
			fmt.Printf("Deleting matter: %s (%s)\n", matter.Title, matter.ID)
		}

		if err := repo.Delete(args[0]); err != nil {
			return fmt.Errorf("failed to delete matter: %w", err)
		}

		if jsonOutput {
			fmt.Println(`{"success": true}`)
		} else {
			fmt.Println("Deleted successfully")
		}

		return nil
	},
}

var matterPhasesCmd = &cobra.Command{
	Use:   "phases <id>",
	Short: "List phases for a matter",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		rootPath, err := getStorageRoot()
		if err != nil {
			return err
		}

		layout := storage.NewChronicleLayout(rootPath)
		repo := storage.NewMatterRepository(layout)

		matter, err := repo.GetByID(args[0])
		if err != nil {
			return fmt.Errorf("matter not found: %s", args[0])
		}

		if jsonOutput {
			data, _ := json.MarshalIndent(matter.Phases, "", "  ")
			fmt.Println(string(data))
			return nil
		}

		fmt.Printf("Phases for %s:\n\n", matter.Title)
		fmt.Printf("%-36s %-6s %s\n", "ID", "Order", "Name")
		fmt.Println(strings.Repeat("-", 70))
		for _, p := range matter.Phases {
			current := ""
			if matter.CurrentPhaseID != nil && *matter.CurrentPhaseID == p.ID {
				current = " *"
			}
			fmt.Printf("%-36s %-6d %s%s\n", p.ID, p.Order, p.Name, current)
		}

		return nil
	},
}

var matterAddPhaseCmd = &cobra.Command{
	Use:   "add-phase <matter-id>",
	Short: "Add a phase to a matter",
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
		repo := storage.NewMatterRepository(layout)

		phase, err := repo.AddPhase(args[0], name)
		if err != nil {
			return fmt.Errorf("failed to add phase: %w", err)
		}

		if jsonOutput {
			data, _ := json.MarshalIndent(phase, "", "  ")
			fmt.Println(string(data))
		} else {
			fmt.Printf("Added phase: %s (%s)\n", phase.Name, phase.ID)
		}

		return nil
	},
}

var matterSetPhaseCmd = &cobra.Command{
	Use:   "set-phase <matter-id> <phase-id>",
	Short: "Set the current phase for a matter",
	Args:  cobra.ExactArgs(2),
	RunE: func(cmd *cobra.Command, args []string) error {
		rootPath, err := getStorageRoot()
		if err != nil {
			return err
		}

		layout := storage.NewChronicleLayout(rootPath)
		repo := storage.NewMatterRepository(layout)

		if err := repo.SetCurrentPhase(args[0], args[1]); err != nil {
			return fmt.Errorf("failed to set phase: %w", err)
		}

		if jsonOutput {
			fmt.Println(`{"success": true}`)
		} else {
			fmt.Println("Phase updated successfully")
		}

		return nil
	},
}

var matterSetStatusCmd = &cobra.Command{
	Use:   "set-status <id> <status>",
	Short: "Set matter status (active, paused, completed, archived)",
	Args:  cobra.ExactArgs(2),
	RunE: func(cmd *cobra.Command, args []string) error {
		rootPath, err := getStorageRoot()
		if err != nil {
			return err
		}

		status := domain.MatterStatus(args[1])
		if status != domain.MatterStatusActive &&
			status != domain.MatterStatusPaused &&
			status != domain.MatterStatusCompleted &&
			status != domain.MatterStatusArchived {
			return fmt.Errorf("invalid status: %s (must be active, paused, completed, or archived)", args[1])
		}

		layout := storage.NewChronicleLayout(rootPath)
		repo := storage.NewMatterRepository(layout)

		if err := repo.SetStatus(args[0], status); err != nil {
			return fmt.Errorf("failed to set status: %w", err)
		}

		if jsonOutput {
			fmt.Println(`{"success": true}`)
		} else {
			fmt.Printf("Status set to: %s\n", status)
		}

		return nil
	},
}

var matterPinCmd = &cobra.Command{
	Use:   "pin <id>",
	Short: "Pin a matter",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		rootPath, err := getStorageRoot()
		if err != nil {
			return err
		}

		layout := storage.NewChronicleLayout(rootPath)
		repo := storage.NewMatterRepository(layout)

		isPinned := !cmd.Flags().Changed("unpin")

		if err := repo.SetPinned(args[0], isPinned); err != nil {
			return fmt.Errorf("failed to %s matter: %w", map[bool]string{true: "pin", false: "unpin"}[isPinned], err)
		}

		if jsonOutput {
			fmt.Println(`{"success": true}`)
		} else {
			if isPinned {
				fmt.Println("Matter pinned")
			} else {
				fmt.Println("Matter unpinned")
			}
		}

		return nil
	},
}

func init() {
	rootCmd.AddCommand(matterCmd)
	matterCmd.AddCommand(matterListCmd)
	matterCmd.AddCommand(matterGetCmd)
	matterCmd.AddCommand(matterCreateCmd)
	matterCmd.AddCommand(matterUpdateCmd)
	matterCmd.AddCommand(matterDeleteCmd)
	matterCmd.AddCommand(matterPhasesCmd)
	matterCmd.AddCommand(matterAddPhaseCmd)
	matterCmd.AddCommand(matterSetPhaseCmd)
	matterCmd.AddCommand(matterSetStatusCmd)
	matterCmd.AddCommand(matterPinCmd)

	// List flags
	matterListCmd.Flags().String("category-id", "", "Filter by category ID")

	// Create flags
	matterCreateCmd.Flags().String("title", "", "Matter title (required)")
	matterCreateCmd.Flags().String("description", "", "Matter description")
	matterCreateCmd.Flags().String("category-id", "", "Category ID")
	matterCreateCmd.Flags().String("color", "#4C956C", "Color (hex)")
	matterCreateCmd.Flags().String("icon", "description", "Icon name")

	// Update flags
	matterUpdateCmd.Flags().String("title", "", "New title")
	matterUpdateCmd.Flags().String("description", "", "New description")
	matterUpdateCmd.Flags().String("category-id", "", "Category ID (empty to remove)")
	matterUpdateCmd.Flags().String("color", "", "Color (hex)")
	matterUpdateCmd.Flags().String("icon", "", "Icon name")

	// Add-phase flags
	matterAddPhaseCmd.Flags().String("name", "", "Phase name (required)")

	// Pin flags
	matterPinCmd.Flags().Bool("unpin", false, "Unpin instead of pin")
}
