package storage

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"chronicle/internal/domain"
	"github.com/google/uuid"
	"gopkg.in/yaml.v3"
)

// ChronicleLayout manages the on-disk directory structure
type ChronicleLayout struct {
	Root string
}

// NewChronicleLayout creates a new layout manager for the given root path
func NewChronicleLayout(root string) *ChronicleLayout {
	return &ChronicleLayout{Root: root}
}

// EnsureDirectories creates all required directories if they don't exist
func (cl *ChronicleLayout) EnsureDirectories() error {
	dirs := []string{
		cl.SyncDir(),
		cl.LocksDir(),
		cl.NotebookRootDir(),
		cl.NotebookFoldersDir(),
		cl.MattersDir(),
		cl.CategoriesDir(),
		cl.LinksDir(),
		cl.ResourcesDir(),
	}

	for _, dir := range dirs {
		if err := os.MkdirAll(dir, 0755); err != nil {
			return fmt.Errorf("failed to create directory %s: %w", dir, err)
		}
	}

	// Create folders.json if it doesn't exist
	foldersPath := cl.NotebookFoldersIndexPath()
	if _, err := os.Stat(foldersPath); os.IsNotExist(err) {
		emptyFolders := map[string][]domain.NotebookFolder{"folders": {}}
		data, _ := json.MarshalIndent(emptyFolders, "", "  ")
		os.WriteFile(foldersPath, data, 0644)
	}

	// Create version marker
	versionPath := filepath.Join(cl.SyncDir(), "version.txt")
	if _, err := os.Stat(versionPath); os.IsNotExist(err) {
		os.WriteFile(versionPath, []byte("1"), 0644)
	}

	return nil
}

// Directory paths
func (cl *ChronicleLayout) SyncDir() string           { return filepath.Join(cl.Root, ".sync") }
func (cl *ChronicleLayout) LocksDir() string          { return filepath.Join(cl.Root, "locks") }
func (cl *ChronicleLayout) NotebookRootDir() string   { return filepath.Join(cl.Root, "notebook", "root") }
func (cl *ChronicleLayout) NotebookFoldersDir() string { return filepath.Join(cl.Root, "notebook", "folders") }
func (cl *ChronicleLayout) MattersDir() string        { return filepath.Join(cl.Root, "matters") }
func (cl *ChronicleLayout) CategoriesDir() string     { return filepath.Join(cl.Root, "categories") }
func (cl *ChronicleLayout) LinksDir() string          { return filepath.Join(cl.Root, "links") }
func (cl *ChronicleLayout) ResourcesDir() string      { return filepath.Join(cl.Root, "resources") }

// File paths
func (cl *ChronicleLayout) NotebookFoldersIndexPath() string { return filepath.Join(cl.Root, "notebook", "folders.json") }
func (cl *ChronicleLayout) InfoPath() string                  { return filepath.Join(cl.Root, "info.json") }
func (cl *ChronicleLayout) ManifestPath() string              { return filepath.Join(cl.SyncDir(), "manifest.json") }
func (cl *ChronicleLayout) PendingSyncPath() string           { return filepath.Join(cl.SyncDir(), "pending_sync.json") }
func (cl *ChronicleLayout) ConflictHistoryPath() string       { return filepath.Join(cl.SyncDir(), "conflict_history.json") }

// Matter paths
func (cl *ChronicleLayout) MatterDir(matterID string) string              { return filepath.Join(cl.MattersDir(), matterID) }
func (cl *ChronicleLayout) MatterMetadataPath(matterID string) string      { return filepath.Join(cl.MatterDir(matterID), "matter.json") }
func (cl *ChronicleLayout) MatterPhasesDir(matterID string) string         { return filepath.Join(cl.MatterDir(matterID), "phases") }
func (cl *ChronicleLayout) MatterPhaseDir(matterID, phaseID string) string { return filepath.Join(cl.MatterPhasesDir(matterID), phaseID) }

// Note paths
func (cl *ChronicleLayout) NotebookNotePath(noteID string) string                    { return filepath.Join(cl.NotebookRootDir(), noteID+".md") }
func (cl *ChronicleLayout) NotebookFolderNotePath(folderID, noteID string) string     { return filepath.Join(cl.NotebookFoldersDir(), folderID, noteID+".md") }
func (cl *ChronicleLayout) MatterNotePath(matterID, phaseID, noteID string) string    { return filepath.Join(cl.MatterPhaseDir(matterID, phaseID), noteID+".md") }

// Category path
func (cl *ChronicleLayout) CategoryPath(categoryID string) string { return filepath.Join(cl.CategoriesDir(), categoryID+".json") }

// Link path
func (cl *ChronicleLayout) LinkPath(linkID string) string { return filepath.Join(cl.LinksDir(), linkID+".json") }

// Resource paths
func (cl *ChronicleLayout) NoteResourcesDir(noteID string) string { return filepath.Join(cl.ResourcesDir(), noteID) }

// Lock path
func (cl *ChronicleLayout) LockPath(clientType, clientID string) string {
	return filepath.Join(cl.LocksDir(), fmt.Sprintf("sync_%s_%s.json", clientType, clientID))
}

// NoteRepository handles note CRUD operations
type NoteRepository struct {
	layout *ChronicleLayout
}

// NewNoteRepository creates a new note repository
func NewNoteRepository(layout *ChronicleLayout) *NoteRepository {
	return &NoteRepository{layout: layout}
}

// NoteFrontmatter represents the YAML frontmatter in a note file
type NoteFrontmatter struct {
	ID               string   `yaml:"id"`
	MatterID         *string  `yaml:"matterId"`
	PhaseID          *string  `yaml:"phaseId"`
	NotebookFolderID *string  `yaml:"notebookFolderId"`
	Title            string   `yaml:"title"`
	CreatedAt        string   `yaml:"createdAt"`
	UpdatedAt        string   `yaml:"updatedAt"`
	Tags             []string `yaml:"tags"`
	IsPinned         bool     `yaml:"isPinned"`
	Attachments      []string `yaml:"attachments"`
}

// noteFile represents a parsed note file with frontmatter and content
type noteFile struct {
	Frontmatter NoteFrontmatter
	Content     string
}

// parseNoteFile parses a markdown file with YAML frontmatter
func parseNoteFile(path string) (*noteFile, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	content := string(data)
	var nf noteFile

	// Check for YAML frontmatter (starts with ---)
	if strings.HasPrefix(content, "---\n") {
		// Find end of frontmatter
		endIdx := strings.Index(content[4:], "\n---")
		if endIdx != -1 {
			frontmatterYAML := content[4 : 4+endIdx]
			if err := yaml.Unmarshal([]byte(frontmatterYAML), &nf.Frontmatter); err != nil {
				return nil, fmt.Errorf("failed to parse frontmatter: %w", err)
			}
			nf.Content = strings.TrimPrefix(content[4+endIdx+4:], "\n")
		}
	}

	return &nf, nil
}

// writeNoteFile writes a note to disk with YAML frontmatter
func writeNoteFile(path string, note *domain.Note) error {
	// Ensure directory exists
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return err
	}

	fm := NoteFrontmatter{
		ID:               note.ID,
		MatterID:         note.MatterID,
		PhaseID:          note.PhaseID,
		NotebookFolderID: note.NotebookFolderID,
		Title:            note.Title,
		CreatedAt:        note.CreatedAt,
		UpdatedAt:        note.UpdatedAt,
		Tags:             note.Tags,
		IsPinned:         note.IsPinned,
		Attachments:      note.Attachments,
	}

	// Build the file content
	var sb strings.Builder
	sb.WriteString("---\n")

	// Write ID
	sb.WriteString(fmt.Sprintf("id: \"%s\"\n", fm.ID))

	// Write MatterID
	if fm.MatterID != nil {
		sb.WriteString(fmt.Sprintf("matterId: \"%s\"\n", *fm.MatterID))
	} else {
		sb.WriteString("matterId: null\n")
	}

	// Write PhaseID
	if fm.PhaseID != nil {
		sb.WriteString(fmt.Sprintf("phaseId: \"%s\"\n", *fm.PhaseID))
	} else {
		sb.WriteString("phaseId: null\n")
	}

	// Write NotebookFolderID
	if fm.NotebookFolderID != nil {
		sb.WriteString(fmt.Sprintf("notebookFolderId: \"%s\"\n", *fm.NotebookFolderID))
	} else {
		sb.WriteString("notebookFolderId: null\n")
	}

	// Write title (escape special chars)
	title := strings.ReplaceAll(fm.Title, "\"", "\\\"")
	sb.WriteString(fmt.Sprintf("title: \"%s\"\n", title))

	sb.WriteString(fmt.Sprintf("createdAt: \"%s\"\n", fm.CreatedAt))
	sb.WriteString(fmt.Sprintf("updatedAt: \"%s\"\n", fm.UpdatedAt))

	// Write tags
	if len(fm.Tags) > 0 {
		sb.WriteString("tags: [")
		for i, tag := range fm.Tags {
			if i > 0 {
				sb.WriteString(", ")
			}
			sb.WriteString(fmt.Sprintf("\"%s\"", tag))
		}
		sb.WriteString("]\n")
	} else {
		sb.WriteString("tags: []\n")
	}

	sb.WriteString(fmt.Sprintf("isPinned: %v\n", fm.IsPinned))

	// Write attachments
	if len(fm.Attachments) > 0 {
		sb.WriteString("attachments: [")
		for i, att := range fm.Attachments {
			if i > 0 {
				sb.WriteString(", ")
			}
			sb.WriteString(fmt.Sprintf("\"%s\"", att))
		}
		sb.WriteString("]\n")
	} else {
		sb.WriteString("attachments: []\n")
	}

	sb.WriteString("---\n\n")
	sb.WriteString(note.Content)

	// Atomic write
	tempPath := path + ".tmp"
	if err := os.WriteFile(tempPath, []byte(sb.String()), 0644); err != nil {
		return err
	}

	return os.Rename(tempPath, path)
}

// noteFileToDomain converts a parsed note file to a domain Note
func noteFileToDomain(nf *noteFile) *domain.Note {
	return &domain.Note{
		ID:               nf.Frontmatter.ID,
		MatterID:         nf.Frontmatter.MatterID,
		PhaseID:          nf.Frontmatter.PhaseID,
		NotebookFolderID: nf.Frontmatter.NotebookFolderID,
		Title:            nf.Frontmatter.Title,
		Content:          nf.Content,
		CreatedAt:        nf.Frontmatter.CreatedAt,
		UpdatedAt:        nf.Frontmatter.UpdatedAt,
		Tags:             nf.Frontmatter.Tags,
		IsPinned:         nf.Frontmatter.IsPinned,
		Attachments:      nf.Frontmatter.Attachments,
	}
}

// Create creates a new note
func (r *NoteRepository) Create(title, content string, matterID, phaseID, notebookFolderID *string, tags []string) (*domain.Note, error) {
	note := &domain.Note{
		ID:               uuid.New().String(),
		MatterID:         matterID,
		PhaseID:          phaseID,
		NotebookFolderID: notebookFolderID,
		Title:            title,
		Content:          content,
		CreatedAt:        domain.NowISO(),
		UpdatedAt:        domain.NowISO(),
		Tags:             tags,
		IsPinned:         false,
		Attachments:      []string{},
	}

	var path string
	if notebookFolderID != nil {
		path = r.layout.NotebookFolderNotePath(*notebookFolderID, note.ID)
	} else if matterID != nil && phaseID != nil {
		path = r.layout.MatterNotePath(*matterID, *phaseID, note.ID)
	} else {
		path = r.layout.NotebookNotePath(note.ID)
	}

	if err := writeNoteFile(path, note); err != nil {
		return nil, err
	}

	return note, nil
}

// GetByID retrieves a note by ID (searches all locations)
func (r *NoteRepository) GetByID(noteID string) (*domain.Note, error) {
	// Search in notebook root
	path := r.layout.NotebookNotePath(noteID)
	if nf, err := parseNoteFile(path); err == nil {
		return noteFileToDomain(nf), nil
	}

	// Search in notebook folders
	folders, err := r.listNotebookFolders()
	if err == nil {
		for _, folder := range folders {
			path = r.layout.NotebookFolderNotePath(folder.ID, noteID)
			if nf, err := parseNoteFile(path); err == nil {
				return noteFileToDomain(nf), nil
			}
		}
	}

	// Search in matters
	matterDirs, err := os.ReadDir(r.layout.MattersDir())
	if err == nil {
		for _, matterDir := range matterDirs {
			if !matterDir.IsDir() {
				continue
			}
			matterID := matterDir.Name()
			phasesDir := r.layout.MatterPhasesDir(matterID)
			phaseDirs, err := os.ReadDir(phasesDir)
			if err != nil {
				continue
			}
			for _, phaseDir := range phaseDirs {
				if !phaseDir.IsDir() {
					continue
				}
				phaseID := phaseDir.Name()
				path = r.layout.MatterNotePath(matterID, phaseID, noteID)
				if nf, err := parseNoteFile(path); err == nil {
					return noteFileToDomain(nf), nil
				}
			}
		}
	}

	return nil, fmt.Errorf("note not found: %s", noteID)
}

// listNotebookFolders returns all notebook folders
func (r *NoteRepository) listNotebookFolders() ([]domain.NotebookFolder, error) {
	data, err := os.ReadFile(r.layout.NotebookFoldersIndexPath())
	if err != nil {
		return nil, err
	}

	var result struct {
		Folders []domain.NotebookFolder `json:"folders"`
	}
	if err := json.Unmarshal(data, &result); err != nil {
		return nil, err
	}

	return result.Folders, nil
}

// ListAll returns all notes
func (r *NoteRepository) ListAll() ([]domain.Note, error) {
	var notes []domain.Note

	// List notebook root notes
	entries, err := os.ReadDir(r.layout.NotebookRootDir())
	if err == nil {
		for _, entry := range entries {
			if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".md") {
				continue
			}
			path := filepath.Join(r.layout.NotebookRootDir(), entry.Name())
			if nf, err := parseNoteFile(path); err == nil {
				notes = append(notes, *noteFileToDomain(nf))
			}
		}
	}

	// List folder notes
	folders, _ := r.listNotebookFolders()
	for _, folder := range folders {
		folderDir := filepath.Join(r.layout.NotebookFoldersDir(), folder.ID)
		entries, err := os.ReadDir(folderDir)
		if err != nil {
			continue
		}
		for _, entry := range entries {
			if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".md") {
				continue
			}
			path := filepath.Join(folderDir, entry.Name())
			if nf, err := parseNoteFile(path); err == nil {
				notes = append(notes, *noteFileToDomain(nf))
			}
		}
	}

	// List matter notes
	matterDirs, _ := os.ReadDir(r.layout.MattersDir())
	for _, matterDir := range matterDirs {
		if !matterDir.IsDir() {
			continue
		}
		matterID := matterDir.Name()
		phasesDir := r.layout.MatterPhasesDir(matterID)
		phaseDirs, _ := os.ReadDir(phasesDir)
		for _, phaseDir := range phaseDirs {
			if !phaseDir.IsDir() {
				continue
			}
			phaseID := phaseDir.Name()
			phasePath := filepath.Join(phasesDir, phaseID)
			entries, _ := os.ReadDir(phasePath)
			for _, entry := range entries {
				if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".md") {
					continue
				}
				path := filepath.Join(phasePath, entry.Name())
				if nf, err := parseNoteFile(path); err == nil {
					notes = append(notes, *noteFileToDomain(nf))
				}
			}
		}
	}

	return notes, nil
}

// ListByMatterAndPhase returns notes in a specific matter phase
func (r *NoteRepository) ListByMatterAndPhase(matterID, phaseID string) ([]domain.Note, error) {
	var notes []domain.Note

	phaseDir := r.layout.MatterPhaseDir(matterID, phaseID)
	entries, err := os.ReadDir(phaseDir)
	if err != nil {
		return nil, err
	}

	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".md") {
			continue
		}
		path := filepath.Join(phaseDir, entry.Name())
		if nf, err := parseNoteFile(path); err == nil {
			notes = append(notes, *noteFileToDomain(nf))
		}
	}

	return notes, nil
}

// ListNotebookNotes returns notes in the notebook (optionally filtered by folder)
func (r *NoteRepository) ListNotebookNotes(folderID *string) ([]domain.Note, error) {
	var notes []domain.Note

	if folderID != nil {
		// List notes in specific folder
		folderDir := filepath.Join(r.layout.NotebookFoldersDir(), *folderID)
		entries, err := os.ReadDir(folderDir)
		if err != nil {
			return nil, err
		}
		for _, entry := range entries {
			if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".md") {
				continue
			}
			path := filepath.Join(folderDir, entry.Name())
			if nf, err := parseNoteFile(path); err == nil {
				notes = append(notes, *noteFileToDomain(nf))
			}
		}
	} else {
		// List unfiled notes in root
		entries, err := os.ReadDir(r.layout.NotebookRootDir())
		if err != nil {
			return nil, err
		}
		for _, entry := range entries {
			if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".md") {
				continue
			}
			path := filepath.Join(r.layout.NotebookRootDir(), entry.Name())
			if nf, err := parseNoteFile(path); err == nil {
				notes = append(notes, *noteFileToDomain(nf))
			}
		}
	}

	return notes, nil
}

// Update updates a note
func (r *NoteRepository) Update(note *domain.Note) error {
	// Find the note's current location
	existing, err := r.GetByID(note.ID)
	if err != nil {
		return err
	}

	// Determine new path based on updated location
	var newPath string
	if note.NotebookFolderID != nil {
		newPath = r.layout.NotebookFolderNotePath(*note.NotebookFolderID, note.ID)
	} else if note.MatterID != nil && note.PhaseID != nil {
		newPath = r.layout.MatterNotePath(*note.MatterID, *note.PhaseID, note.ID)
	} else {
		newPath = r.layout.NotebookNotePath(note.ID)
	}

	// Determine old path
	var oldPath string
	if existing.NotebookFolderID != nil {
		oldPath = r.layout.NotebookFolderNotePath(*existing.NotebookFolderID, existing.ID)
	} else if existing.MatterID != nil && existing.PhaseID != nil {
		oldPath = r.layout.MatterNotePath(*existing.MatterID, *existing.PhaseID, existing.ID)
	} else {
		oldPath = r.layout.NotebookNotePath(existing.ID)
	}

	// Update timestamp
	note.UpdatedAt = domain.NowISO()

	// If location changed, delete old file
	if oldPath != newPath {
		os.Remove(oldPath)
	}

	// Write to new location
	return writeNoteFile(newPath, note)
}

// Delete deletes a note
func (r *NoteRepository) Delete(noteID string) error {
	note, err := r.GetByID(noteID)
	if err != nil {
		return err
	}

	var path string
	if note.NotebookFolderID != nil {
		path = r.layout.NotebookFolderNotePath(*note.NotebookFolderID, note.ID)
	} else if note.MatterID != nil && note.PhaseID != nil {
		path = r.layout.MatterNotePath(*note.MatterID, *note.PhaseID, note.ID)
	} else {
		path = r.layout.NotebookNotePath(note.ID)
	}

	return os.Remove(path)
}

// Move moves a note to a new location
func (r *NoteRepository) Move(noteID string, matterID, phaseID, notebookFolderID *string) error {
	note, err := r.GetByID(noteID)
	if err != nil {
		return err
	}

	note.MatterID = matterID
	note.PhaseID = phaseID
	note.NotebookFolderID = notebookFolderID
	note.UpdatedAt = domain.NowISO()

	return r.Update(note)
}

// Search searches notes by title and content
func (r *NoteRepository) Search(query string) ([]domain.Note, error) {
	allNotes, err := r.ListAll()
	if err != nil {
		return nil, err
	}

	query = strings.ToLower(query)
	var results []domain.Note

	for _, note := range allNotes {
		if strings.Contains(strings.ToLower(note.Title), query) ||
			strings.Contains(strings.ToLower(note.Content), query) {
			results = append(results, note)
		}
	}

	return results, nil
}

// MatterRepository handles matter CRUD operations
type MatterRepository struct {
	layout *ChronicleLayout
}

// NewMatterRepository creates a new matter repository
func NewMatterRepository(layout *ChronicleLayout) *MatterRepository {
	return &MatterRepository{layout: layout}
}

// Create creates a new matter with default phases
func (r *MatterRepository) Create(title, description string, categoryID *string, color, icon string) (*domain.Matter, error) {
	id := uuid.New().String()
	now := domain.NowISO()

	matter := &domain.Matter{
		ID:          id,
		CategoryID:  categoryID,
		Title:       title,
		Description: description,
		Status:      domain.MatterStatusActive,
		Color:       color,
		Icon:        icon,
		CreatedAt:   now,
		UpdatedAt:   now,
		StartedAt:   &now,
		IsPinned:    false,
		Phases:      domain.DefaultPhases(id),
	}

	if matter.Color == "" {
		matter.Color = "#4C956C"
	}
	if matter.Icon == "" {
		matter.Icon = "description"
	}

	// Create matter directory
	if err := os.MkdirAll(r.layout.MatterPhasesDir(id), 0755); err != nil {
		return nil, err
	}

	// Create phase directories
	for _, phase := range matter.Phases {
		phaseDir := r.layout.MatterPhaseDir(id, phase.ID)
		if err := os.MkdirAll(phaseDir, 0755); err != nil {
			return nil, err
		}
	}

	// Save matter metadata
	if err := r.saveMatter(matter); err != nil {
		return nil, err
	}

	return matter, nil
}

// saveMatter saves matter metadata to disk
func (r *MatterRepository) saveMatter(matter *domain.Matter) error {
	path := r.layout.MatterMetadataPath(matter.ID)

	// Ensure directory exists
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return err
	}

	data, err := json.MarshalIndent(matter, "", "  ")
	if err != nil {
		return err
	}

	return os.WriteFile(path, data, 0644)
}

// loadMatter loads matter metadata from disk
func (r *MatterRepository) loadMatter(matterID string) (*domain.Matter, error) {
	path := r.layout.MatterMetadataPath(matterID)

	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	var matter domain.Matter
	if err := json.Unmarshal(data, &matter); err != nil {
		return nil, err
	}

	return &matter, nil
}

// GetByID retrieves a matter by ID
func (r *MatterRepository) GetByID(matterID string) (*domain.Matter, error) {
	return r.loadMatter(matterID)
}

// List returns all matters
func (r *MatterRepository) List() ([]domain.Matter, error) {
	entries, err := os.ReadDir(r.layout.MattersDir())
	if err != nil {
		return nil, err
	}

	var matters []domain.Matter
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		matter, err := r.loadMatter(entry.Name())
		if err != nil {
			continue
		}
		matters = append(matters, *matter)
	}

	return matters, nil
}

// Update updates a matter
func (r *MatterRepository) Update(matter *domain.Matter) error {
	matter.UpdatedAt = domain.NowISO()
	return r.saveMatter(matter)
}

// SetStatus updates a matter's status
func (r *MatterRepository) SetStatus(matterID string, status domain.MatterStatus) error {
	matter, err := r.loadMatter(matterID)
	if err != nil {
		return err
	}

	matter.Status = status
	matter.UpdatedAt = domain.NowISO()

	if status == domain.MatterStatusCompleted {
		now := domain.NowISO()
		matter.EndedAt = &now
	}

	return r.saveMatter(matter)
}

// SetCategory updates a matter's category
func (r *MatterRepository) SetCategory(matterID string, categoryID *string) error {
	matter, err := r.loadMatter(matterID)
	if err != nil {
		return err
	}

	matter.CategoryID = categoryID
	matter.UpdatedAt = domain.NowISO()

	return r.saveMatter(matter)
}

// SetPinned updates a matter's pinned status
func (r *MatterRepository) SetPinned(matterID string, isPinned bool) error {
	matter, err := r.loadMatter(matterID)
	if err != nil {
		return err
	}

	matter.IsPinned = isPinned
	matter.UpdatedAt = domain.NowISO()

	return r.saveMatter(matter)
}

// Delete deletes a matter and all its notes
func (r *MatterRepository) Delete(matterID string) error {
	return os.RemoveAll(r.layout.MatterDir(matterID))
}

// AddPhase adds a phase to a matter
func (r *MatterRepository) AddPhase(matterID, name string) (*domain.Phase, error) {
	matter, err := r.loadMatter(matterID)
	if err != nil {
		return nil, err
	}

	// Find max order
	maxOrder := -1
	for _, phase := range matter.Phases {
		if phase.Order > maxOrder {
			maxOrder = phase.Order
		}
	}

	phase := domain.Phase{
		ID:       uuid.New().String(),
		MatterID: matterID,
		Name:     name,
		Order:    maxOrder + 1,
	}

	matter.Phases = append(matter.Phases, phase)
	matter.UpdatedAt = domain.NowISO()

	// Create phase directory
	phaseDir := r.layout.MatterPhaseDir(matterID, phase.ID)
	if err := os.MkdirAll(phaseDir, 0755); err != nil {
		return nil, err
	}

	if err := r.saveMatter(matter); err != nil {
		return nil, err
	}

	return &phase, nil
}

// SetCurrentPhase sets the current phase of a matter
func (r *MatterRepository) SetCurrentPhase(matterID, phaseID string) error {
	matter, err := r.loadMatter(matterID)
	if err != nil {
		return err
	}

	// Verify phase exists
	found := false
	for _, phase := range matter.Phases {
		if phase.ID == phaseID {
			found = true
			break
		}
	}
	if !found {
		return fmt.Errorf("phase not found: %s", phaseID)
	}

	matter.CurrentPhaseID = &phaseID
	matter.UpdatedAt = domain.NowISO()

	return r.saveMatter(matter)
}

// Search searches matters by title and description
func (r *MatterRepository) Search(query string) ([]domain.Matter, error) {
	allMatters, err := r.List()
	if err != nil {
		return nil, err
	}

	query = strings.ToLower(query)
	var results []domain.Matter

	for _, matter := range allMatters {
		if strings.Contains(strings.ToLower(matter.Title), query) ||
			strings.Contains(strings.ToLower(matter.Description), query) {
			results = append(results, matter)
		}
	}

	return results, nil
}

// CategoryRepository handles category CRUD operations
type CategoryRepository struct {
	layout *ChronicleLayout
}

// NewCategoryRepository creates a new category repository
func NewCategoryRepository(layout *ChronicleLayout) *CategoryRepository {
	return &CategoryRepository{layout: layout}
}

// Create creates a new category
func (r *CategoryRepository) Create(name, color, icon string) (*domain.Category, error) {
	now := domain.NowISO()

	category := &domain.Category{
		ID:        uuid.New().String(),
		Name:      name,
		Color:     color,
		Icon:      icon,
		CreatedAt: now,
		UpdatedAt: now,
	}

	if category.Color == "" {
		category.Color = "#4C956C"
	}
	if category.Icon == "" {
		category.Icon = "folder"
	}

	if err := r.saveCategory(category); err != nil {
		return nil, err
	}

	return category, nil
}

// saveCategory saves category to disk
func (r *CategoryRepository) saveCategory(category *domain.Category) error {
	path := r.layout.CategoryPath(category.ID)

	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return err
	}

	data, err := json.MarshalIndent(category, "", "  ")
	if err != nil {
		return err
	}

	return os.WriteFile(path, data, 0644)
}

// loadCategory loads category from disk
func (r *CategoryRepository) loadCategory(categoryID string) (*domain.Category, error) {
	path := r.layout.CategoryPath(categoryID)

	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	var category domain.Category
	if err := json.Unmarshal(data, &category); err != nil {
		return nil, err
	}

	return &category, nil
}

// GetByID retrieves a category by ID
func (r *CategoryRepository) GetByID(categoryID string) (*domain.Category, error) {
	return r.loadCategory(categoryID)
}

// List returns all categories
func (r *CategoryRepository) List() ([]domain.Category, error) {
	entries, err := os.ReadDir(r.layout.CategoriesDir())
	if err != nil {
		return nil, err
	}

	var categories []domain.Category
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".json") {
			continue
		}

		// Extract ID from filename
		id := strings.TrimSuffix(entry.Name(), ".json")
		category, err := r.loadCategory(id)
		if err != nil {
			continue
		}
		categories = append(categories, *category)
	}

	return categories, nil
}

// Update updates a category
func (r *CategoryRepository) Update(category *domain.Category) error {
	category.UpdatedAt = domain.NowISO()
	return r.saveCategory(category)
}

// Delete deletes a category
func (r *CategoryRepository) Delete(categoryID string) error {
	return os.Remove(r.layout.CategoryPath(categoryID))
}

// Search searches categories by name
func (r *CategoryRepository) Search(query string) ([]domain.Category, error) {
	allCategories, err := r.List()
	if err != nil {
		return nil, err
	}

	query = strings.ToLower(query)
	var results []domain.Category

	for _, category := range allCategories {
		if strings.Contains(strings.ToLower(category.Name), query) {
			results = append(results, category)
		}
	}

	return results, nil
}

// NotebookRepository handles notebook folder operations
type NotebookRepository struct {
	layout *ChronicleLayout
}

// NewNotebookRepository creates a new notebook repository
func NewNotebookRepository(layout *ChronicleLayout) *NotebookRepository {
	return &NotebookRepository{layout: layout}
}

// loadFoldersIndex loads the folders.json file
func (r *NotebookRepository) loadFoldersIndex() ([]domain.NotebookFolder, error) {
	data, err := os.ReadFile(r.layout.NotebookFoldersIndexPath())
	if err != nil {
		return nil, err
	}

	var result struct {
		Folders []domain.NotebookFolder `json:"folders"`
	}
	if err := json.Unmarshal(data, &result); err != nil {
		return nil, err
	}

	return result.Folders, nil
}

// saveFoldersIndex saves the folders.json file
func (r *NotebookRepository) saveFoldersIndex(folders []domain.NotebookFolder) error {
	result := struct {
		Folders []domain.NotebookFolder `json:"folders"`
	}{Folders: folders}

	data, err := json.MarshalIndent(result, "", "  ")
	if err != nil {
		return err
	}

	return os.WriteFile(r.layout.NotebookFoldersIndexPath(), data, 0644)
}

// CreateFolder creates a new notebook folder
func (r *NotebookRepository) CreateFolder(name string, parentID *string) (*domain.NotebookFolder, error) {
	now := domain.NowISO()

	folder := &domain.NotebookFolder{
		ID:        uuid.New().String(),
		Name:      name,
		ParentID:  parentID,
		CreatedAt: now,
		UpdatedAt: now,
	}

	folders, err := r.loadFoldersIndex()
	if err != nil {
		folders = []domain.NotebookFolder{}
	}

	folders = append(folders, *folder)

	// Create folder directory
	folderDir := filepath.Join(r.layout.NotebookFoldersDir(), folder.ID)
	if err := os.MkdirAll(folderDir, 0755); err != nil {
		return nil, err
	}

	if err := r.saveFoldersIndex(folders); err != nil {
		return nil, err
	}

	return folder, nil
}

// GetFolderByID retrieves a folder by ID
func (r *NotebookRepository) GetFolderByID(folderID string) (*domain.NotebookFolder, error) {
	folders, err := r.loadFoldersIndex()
	if err != nil {
		return nil, err
	}

	for _, folder := range folders {
		if folder.ID == folderID {
			return &folder, nil
		}
	}

	return nil, fmt.Errorf("folder not found: %s", folderID)
}

// ListFolders returns all folders
func (r *NotebookRepository) ListFolders() ([]domain.NotebookFolder, error) {
	return r.loadFoldersIndex()
}

// RenameFolder renames a folder
func (r *NotebookRepository) RenameFolder(folderID, name string) (*domain.NotebookFolder, error) {
	folders, err := r.loadFoldersIndex()
	if err != nil {
		return nil, err
	}

	var found *domain.NotebookFolder
	for i := range folders {
		if folders[i].ID == folderID {
			folders[i].Name = name
			folders[i].UpdatedAt = domain.NowISO()
			found = &folders[i]
			break
		}
	}

	if found == nil {
		return nil, fmt.Errorf("folder not found: %s", folderID)
	}

	if err := r.saveFoldersIndex(folders); err != nil {
		return nil, err
	}

	return found, nil
}

// DeleteFolder deletes a folder (must be empty)
func (r *NotebookRepository) DeleteFolder(folderID string) error {
	// Check if folder has notes
	folderDir := filepath.Join(r.layout.NotebookFoldersDir(), folderID)
	entries, err := os.ReadDir(folderDir)
	if err == nil && len(entries) > 0 {
		return fmt.Errorf("folder is not empty")
	}

	folders, err := r.loadFoldersIndex()
	if err != nil {
		return err
	}

	// Remove folder from index
	newFolders := make([]domain.NotebookFolder, 0, len(folders)-1)
	found := false
	for _, folder := range folders {
		if folder.ID == folderID {
			found = true
			continue
		}
		newFolders = append(newFolders, folder)
	}

	if !found {
		return fmt.Errorf("folder not found: %s", folderID)
	}

	if err := r.saveFoldersIndex(newFolders); err != nil {
		return err
	}

	// Remove folder directory
	os.Remove(folderDir)

	return nil
}

// Search searches folders by name
func (r *NotebookRepository) Search(query string) ([]domain.NotebookFolder, error) {
	allFolders, err := r.loadFoldersIndex()
	if err != nil {
		return nil, err
	}

	query = strings.ToLower(query)
	var results []domain.NotebookFolder

	for _, folder := range allFolders {
		if strings.Contains(strings.ToLower(folder.Name), query) {
			results = append(results, folder)
		}
	}

	return results, nil
}

// ComputeHash computes the SHA256 hash of content
func ComputeHash(content []byte) string {
	hash := sha256.Sum256(content)
	return hex.EncodeToString(hash[:])
}

// ComputeStringHash computes the SHA256 hash of a string
func ComputeStringHash(content string) string {
	return ComputeHash([]byte(content))
}

// ListConflictFiles returns all conflict files in the storage
func (cl *ChronicleLayout) ListConflictFiles() ([]string, error) {
	var conflicts []string

	// Regex to match conflict files: <name>.conflict.<timestamp>.<clientId>.<ext>
	conflictRegex := regexp.MustCompile(`\.conflict\.\d+\.[^.]+\.[^.]+$`)

	err := filepath.Walk(cl.Root, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return nil // Skip files we can't access
		}
		if info.IsDir() {
			// Skip .sync and locks directories
			name := info.Name()
			if name == ".sync" || name == "locks" {
				return filepath.SkipDir
			}
			return nil
		}

		if conflictRegex.MatchString(info.Name()) {
			// Get relative path
			relPath, _ := filepath.Rel(cl.Root, path)
			conflicts = append(conflicts, relPath)
		}

		return nil
	})

	return conflicts, err
}

// ParseConflictFile parses a conflict file and extracts metadata
func ParseConflictFile(content string) (*domain.Conflict, error) {
	// Simple parser for conflict file frontmatter
	if !strings.HasPrefix(content, "---\n") {
		return nil, fmt.Errorf("invalid conflict file format")
	}

	endIdx := strings.Index(content[4:], "\n---")
	if endIdx == -1 {
		return nil, fmt.Errorf("invalid conflict file format")
	}

	frontmatter := content[4 : 4+endIdx]

	var conflict domain.Conflict
	lines := strings.Split(frontmatter, "\n")
	for _, line := range lines {
		parts := strings.SplitN(line, ":", 2)
		if len(parts) != 2 {
			continue
		}
		key := strings.TrimSpace(parts[0])
		value := strings.Trim(strings.TrimSpace(parts[1]), `"`)

		switch key {
		case "originalPath":
			conflict.OriginalPath = value
		case "conflictDetectedAt":
			conflict.ConflictDetected = value
		case "localDevice":
			conflict.LocalDevice = value
		case "remoteDevice":
			conflict.RemoteDevice = value
		case "localContentHash":
			conflict.LocalContentHash = value
		case "remoteContentHash":
			conflict.RemoteContentHash = value
		}
	}

	return &conflict, nil
}

// FileInfo represents file metadata for sync
type FileInfo struct {
	Path        string
	ContentHash string
	Size        int64
	UpdatedAt   time.Time
	IsDir       bool
}

// ScanDirectory recursively scans a directory and returns all file info
func (cl *ChronicleLayout) ScanDirectory(dir string) ([]FileInfo, error) {
	var files []FileInfo

	ignoredPaths := map[string]bool{
		".sync": true,
		"locks": true,
	}

	err := filepath.Walk(dir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return nil
		}

		// Get relative path
		relPath, err := filepath.Rel(dir, path)
		if err != nil {
			return nil
		}

		// Skip ignored directories
		parts := strings.Split(relPath, string(filepath.Separator))
		if len(parts) > 0 && ignoredPaths[parts[0]] {
			if info.IsDir() {
				return filepath.SkipDir
			}
			return nil
		}

		// Skip conflict files and temp files
		if strings.Contains(info.Name(), ".conflict.") || strings.HasSuffix(info.Name(), ".tmp") {
			return nil
		}

		// Skip root directory itself
		if relPath == "." {
			return nil
		}

		fileInfo := FileInfo{
			Path:      relPath,
			Size:      info.Size(),
			UpdatedAt: info.ModTime(),
			IsDir:     info.IsDir(),
		}

		// Compute hash for files
		if !info.IsDir() {
			content, err := os.ReadFile(path)
			if err == nil {
				fileInfo.ContentHash = ComputeHash(content)
			}
		}

		files = append(files, fileInfo)
		return nil
	})

	return files, err
}
