package cmd

import (
	"encoding/json"
	"fmt"
	"strings"

	"chronicle/internal/domain"
	"chronicle/internal/storage"
	"github.com/spf13/cobra"
)

var noteCmd = &cobra.Command{
	Use:   "note",
	Short: "Manage notes",
	Long:  `Create, update, delete, and list notes.`,
}

var noteListCmd = &cobra.Command{
	Use:   "list",
	Short: "List notes",
	RunE: func(cmd *cobra.Command, args []string) error {
		rootPath, err := getStorageRoot()
		if err != nil {
			return err
		}

		layout := storage.NewChronicleLayout(rootPath)
		repo := storage.NewNoteRepository(layout)

		var notes []domain.Note

		// Check for filters
		matterID, _ := cmd.Flags().GetString("matter-id")
		phaseID, _ := cmd.Flags().GetString("phase-id")
		folderID, _ := cmd.Flags().GetString("folder-id")
		tagFilter, _ := cmd.Flags().GetString("tag")

		if matterID != "" && phaseID != "" {
			notes, err = repo.ListByMatterAndPhase(matterID, phaseID)
		} else if folderID != "" {
			folderIDPtr := &folderID
			notes, err = repo.ListNotebookNotes(folderIDPtr)
		} else {
			notes, err = repo.ListAll()
		}

		if err != nil {
			return fmt.Errorf("failed to list notes: %w", err)
		}

		// Apply tag filter
		if tagFilter != "" {
			var filtered []domain.Note
			for _, n := range notes {
				for _, t := range n.Tags {
					if t == tagFilter {
						filtered = append(filtered, n)
						break
					}
				}
			}
			notes = filtered
		}

		if jsonOutput {
			data, _ := json.MarshalIndent(notes, "", "  ")
			fmt.Println(string(data))
			return nil
		}

		if len(notes) == 0 {
			fmt.Println("No notes found")
			return nil
		}

		fmt.Printf("%-36s %-30s %s\n", "ID", "Title", "Location")
		fmt.Println(strings.Repeat("-", 100))
		for _, n := range notes {
			title := n.Title
			if len(title) > 28 {
				title = title[:25] + "..."
			}

			location := "notebook"
			if n.MatterID != nil && n.PhaseID != nil {
				location = fmt.Sprintf("matter:%s/%s", (*n.MatterID)[:8], (*n.PhaseID)[:8])
			} else if n.NotebookFolderID != nil {
				location = fmt.Sprintf("folder:%s", (*n.NotebookFolderID)[:8])
			}

			fmt.Printf("%-36s %-30s %s\n", n.ID, title, location)
		}

		return nil
	},
}

var noteGetCmd = &cobra.Command{
	Use:   "get <id>",
	Short: "Get a note by ID",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		rootPath, err := getStorageRoot()
		if err != nil {
			return err
		}

		layout := storage.NewChronicleLayout(rootPath)
		repo := storage.NewNoteRepository(layout)

		note, err := repo.GetByID(args[0])
		if err != nil {
			return fmt.Errorf("note not found: %s", args[0])
		}

		includeContent, _ := cmd.Flags().GetBool("include-content")

		if jsonOutput {
			if !includeContent {
				// Create a copy without content for compact output
				note.Content = ""
			}
			data, _ := json.MarshalIndent(note, "", "  ")
			fmt.Println(string(data))
			return nil
		}

		fmt.Printf("ID:          %s\n", note.ID)
		fmt.Printf("Title:       %s\n", note.Title)
		fmt.Printf("Created:     %s\n", note.CreatedAt)
		fmt.Printf("Updated:     %s\n", note.UpdatedAt)
		fmt.Printf("Pinned:      %v\n", note.IsPinned)
		fmt.Printf("Tags:        %v\n", note.Tags)

		if note.MatterID != nil {
			fmt.Printf("Matter:      %s\n", *note.MatterID)
		}
		if note.PhaseID != nil {
			fmt.Printf("Phase:       %s\n", *note.PhaseID)
		}
		if note.NotebookFolderID != nil {
			fmt.Printf("Folder:      %s\n", *note.NotebookFolderID)
		}

		if includeContent {
			fmt.Printf("\n--- Content ---\n%s\n", note.Content)
		}

		return nil
	},
}

var noteCreateCmd = &cobra.Command{
	Use:   "create",
	Short: "Create a new note",
	RunE: func(cmd *cobra.Command, args []string) error {
		rootPath, err := getStorageRoot()
		if err != nil {
			return err
		}

		title, _ := cmd.Flags().GetString("title")
		content, _ := cmd.Flags().GetString("content")
		matterID, _ := cmd.Flags().GetString("matter-id")
		phaseID, _ := cmd.Flags().GetString("phase-id")
		folderID, _ := cmd.Flags().GetString("folder-id")
		tags, _ := cmd.Flags().GetStringArray("tag")

		layout := storage.NewChronicleLayout(rootPath)
		repo := storage.NewNoteRepository(layout)

		// Convert empty strings to nil
		var matterIDPtr, phaseIDPtr, folderIDPtr *string
		if matterID != "" {
			matterIDPtr = &matterID
		}
		if phaseID != "" {
			phaseIDPtr = &phaseID
		}
		if folderID != "" {
			folderIDPtr = &folderID
		}

		// Validate: either matter+phase or folder or neither (notebook root)
		if matterIDPtr != nil && phaseIDPtr == nil {
			return fmt.Errorf("--phase-id is required when --matter-id is specified")
		}
		if matterIDPtr == nil && phaseIDPtr != nil {
			return fmt.Errorf("--matter-id is required when --phase-id is specified")
		}
		if matterIDPtr != nil && folderIDPtr != nil {
			return fmt.Errorf("cannot specify both matter/phase and folder")
		}

		note, err := repo.Create(title, content, matterIDPtr, phaseIDPtr, folderIDPtr, tags)
		if err != nil {
			return fmt.Errorf("failed to create note: %w", err)
		}

		if jsonOutput {
			data, _ := json.MarshalIndent(note, "", "  ")
			fmt.Println(string(data))
		} else {
			fmt.Printf("Created note: %s (%s)\n", note.Title, note.ID)
		}

		return nil
	},
}

var noteUpdateCmd = &cobra.Command{
	Use:   "update <id>",
	Short: "Update a note",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		rootPath, err := getStorageRoot()
		if err != nil {
			return err
		}

		layout := storage.NewChronicleLayout(rootPath)
		repo := storage.NewNoteRepository(layout)

		note, err := repo.GetByID(args[0])
		if err != nil {
			return fmt.Errorf("note not found: %s", args[0])
		}

		if cmd.Flags().Changed("title") {
			title, _ := cmd.Flags().GetString("title")
			note.Title = title
		}
		if cmd.Flags().Changed("content") {
			content, _ := cmd.Flags().GetString("content")
			note.Content = content
		}

		// Handle location change
		if cmd.Flags().Changed("matter-id") || cmd.Flags().Changed("phase-id") || cmd.Flags().Changed("folder-id") {
			matterID, _ := cmd.Flags().GetString("matter-id")
			phaseID, _ := cmd.Flags().GetString("phase-id")
			folderID, _ := cmd.Flags().GetString("folder-id")

			var matterIDPtr, phaseIDPtr, folderIDPtr *string
			if matterID != "" {
				matterIDPtr = &matterID
			}
			if phaseID != "" {
				phaseIDPtr = &phaseID
			}
			if folderID != "" {
				folderIDPtr = &folderID
			}

			note.MatterID = matterIDPtr
			note.PhaseID = phaseIDPtr
			note.NotebookFolderID = folderIDPtr
		}

		if err := repo.Update(note); err != nil {
			return fmt.Errorf("failed to update note: %w", err)
		}

		if jsonOutput {
			data, _ := json.MarshalIndent(note, "", "  ")
			fmt.Println(string(data))
		} else {
			fmt.Printf("Updated note: %s\n", note.ID)
		}

		return nil
	},
}

var noteDeleteCmd = &cobra.Command{
	Use:   "delete <id>",
	Short: "Delete a note",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		rootPath, err := getStorageRoot()
		if err != nil {
			return err
		}

		layout := storage.NewChronicleLayout(rootPath)
		repo := storage.NewNoteRepository(layout)

		if !jsonOutput {
			fmt.Printf("Deleting note: %s\n", args[0])
		}

		if err := repo.Delete(args[0]); err != nil {
			return fmt.Errorf("failed to delete note: %w", err)
		}

		if jsonOutput {
			fmt.Println(`{"success": true}`)
		} else {
			fmt.Println("Deleted successfully")
		}

		return nil
	},
}

var noteMoveCmd = &cobra.Command{
	Use:   "move <id>",
	Short: "Move a note to a different location",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		rootPath, err := getStorageRoot()
		if err != nil {
			return err
		}

		matterID, _ := cmd.Flags().GetString("matter-id")
		phaseID, _ := cmd.Flags().GetString("phase-id")
		folderID, _ := cmd.Flags().GetString("folder-id")

		var matterIDPtr, phaseIDPtr, folderIDPtr *string
		if matterID != "" {
			matterIDPtr = &matterID
		}
		if phaseID != "" {
			phaseIDPtr = &phaseID
		}
		if folderID != "" {
			folderIDPtr = &folderID
		}

		layout := storage.NewChronicleLayout(rootPath)
		repo := storage.NewNoteRepository(layout)

		if err := repo.Move(args[0], matterIDPtr, phaseIDPtr, folderIDPtr); err != nil {
			return fmt.Errorf("failed to move note: %w", err)
		}

		if jsonOutput {
			fmt.Println(`{"success": true}`)
		} else {
			fmt.Println("Note moved successfully")
		}

		return nil
	},
}

var notePinCmd = &cobra.Command{
	Use:   "pin <id>",
	Short: "Pin/unpin a note",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		rootPath, err := getStorageRoot()
		if err != nil {
			return err
		}

		layout := storage.NewChronicleLayout(rootPath)
		repo := storage.NewNoteRepository(layout)

		note, err := repo.GetByID(args[0])
		if err != nil {
			return fmt.Errorf("note not found: %s", args[0])
		}

		unpin, _ := cmd.Flags().GetBool("unpin")
		note.IsPinned = !unpin

		if err := repo.Update(note); err != nil {
			return fmt.Errorf("failed to update note: %w", err)
		}

		if jsonOutput {
			fmt.Println(`{"success": true}`)
		} else {
			if unpin {
				fmt.Println("Note unpinned")
			} else {
				fmt.Println("Note pinned")
			}
		}

		return nil
	},
}

func init() {
	rootCmd.AddCommand(noteCmd)
	noteCmd.AddCommand(noteListCmd)
	noteCmd.AddCommand(noteGetCmd)
	noteCmd.AddCommand(noteCreateCmd)
	noteCmd.AddCommand(noteUpdateCmd)
	noteCmd.AddCommand(noteDeleteCmd)
	noteCmd.AddCommand(noteMoveCmd)
	noteCmd.AddCommand(notePinCmd)

	// List flags
	noteListCmd.Flags().String("matter-id", "", "Filter by matter ID")
	noteListCmd.Flags().String("phase-id", "", "Filter by phase ID")
	noteListCmd.Flags().String("folder-id", "", "Filter by notebook folder ID")
	noteListCmd.Flags().String("tag", "", "Filter by tag")

	// Get flags
	noteGetCmd.Flags().Bool("include-content", true, "Include note content in output")

	// Create flags
	noteCreateCmd.Flags().String("title", "", "Note title")
	noteCreateCmd.Flags().String("content", "", "Note content (markdown)")
	noteCreateCmd.Flags().String("matter-id", "", "Matter ID (requires --phase-id)")
	noteCreateCmd.Flags().String("phase-id", "", "Phase ID (requires --matter-id)")
	noteCreateCmd.Flags().String("folder-id", "", "Notebook folder ID")
	noteCreateCmd.Flags().StringArray("tag", []string{}, "Tags (can be specified multiple times)")

	// Update flags
	noteUpdateCmd.Flags().String("title", "", "New title")
	noteUpdateCmd.Flags().String("content", "", "New content")
	noteUpdateCmd.Flags().String("matter-id", "", "Matter ID (requires --phase-id)")
	noteUpdateCmd.Flags().String("phase-id", "", "Phase ID (requires --matter-id)")
	noteUpdateCmd.Flags().String("folder-id", "", "Notebook folder ID")

	// Move flags
	noteMoveCmd.Flags().String("matter-id", "", "Matter ID (requires --phase-id)")
	noteMoveCmd.Flags().String("phase-id", "", "Phase ID (requires --matter-id)")
	noteMoveCmd.Flags().String("folder-id", "", "Notebook folder ID")

	// Pin flags
	notePinCmd.Flags().Bool("unpin", false, "Unpin the note")
}
