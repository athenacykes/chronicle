package cmd

import (
	"encoding/json"
	"fmt"
	"strings"

	"chronicle/internal/storage"
	"github.com/spf13/cobra"
)

var searchCmd = &cobra.Command{
	Use:   "search <query>",
	Short: "Search across all entities",
	Long:  `Search for matters, notes, categories, and notebook folders by title, name, or content.`,
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		rootPath, err := getStorageRoot()
		if err != nil {
			return err
		}

		query := args[0]
		entityType, _ := cmd.Flags().GetString("type")
		limit, _ := cmd.Flags().GetInt("limit")

		layout := storage.NewChronicleLayout(rootPath)

		type SearchResult struct {
			Type string      `json:"type"`
			ID   string      `json:"id"`
			Name string      `json:"name"`
			Data interface{} `json:"data"`
		}

		var results []SearchResult

		// Search matters
		if entityType == "" || entityType == "matter" {
			matterRepo := storage.NewMatterRepository(layout)
			matters, err := matterRepo.Search(query)
			if err == nil {
				for _, m := range matters {
					results = append(results, SearchResult{
						Type: "matter",
						ID:   m.ID,
						Name: m.Title,
						Data: m,
					})
				}
			}
		}

		// Search notes
		if entityType == "" || entityType == "note" {
			noteRepo := storage.NewNoteRepository(layout)
			notes, err := noteRepo.Search(query)
			if err == nil {
				for _, n := range notes {
					results = append(results, SearchResult{
						Type: "note",
						ID:   n.ID,
						Name: n.Title,
						Data: n,
					})
				}
			}
		}

		// Search categories
		if entityType == "" || entityType == "category" {
			categoryRepo := storage.NewCategoryRepository(layout)
			categories, err := categoryRepo.Search(query)
			if err == nil {
				for _, c := range categories {
					results = append(results, SearchResult{
						Type: "category",
						ID:   c.ID,
						Name: c.Name,
						Data: c,
					})
				}
			}
		}

		// Search notebook folders
		if entityType == "" || entityType == "notebook" {
			notebookRepo := storage.NewNotebookRepository(layout)
			folders, err := notebookRepo.Search(query)
			if err == nil {
				for _, f := range folders {
					results = append(results, SearchResult{
						Type: "notebook",
						ID:   f.ID,
						Name: f.Name,
						Data: f,
					})
				}
			}
		}

		// Apply limit
		if limit > 0 && len(results) > limit {
			results = results[:limit]
		}

		if jsonOutput {
			data, _ := json.MarshalIndent(results, "", "  ")
			fmt.Println(string(data))
			return nil
		}

		if len(results) == 0 {
			fmt.Println("No results found")
			return nil
		}

		fmt.Printf("Found %d result(s) for '%s':\n\n", len(results), query)
		fmt.Printf("%-10s %-36s %s\n", "Type", "ID", "Name")
		fmt.Println(strings.Repeat("-", 90))
		for _, r := range results {
			name := r.Name
			if len(name) > 40 {
				name = name[:37] + "..."
			}
			fmt.Printf("%-10s %-36s %s\n", r.Type, r.ID, name)
		}

		return nil
	},
}

func init() {
	rootCmd.AddCommand(searchCmd)

	searchCmd.Flags().String("type", "", "Filter by type: matter, note, category, notebook")
	searchCmd.Flags().Int("limit", 0, "Limit number of results (0 = no limit)")
}
