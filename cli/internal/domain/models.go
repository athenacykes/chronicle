package domain

import (
	"time"
)

// Note represents a Chronicle note
type Note struct {
	ID               string   `json:"id" yaml:"id"`
	MatterID         *string  `json:"matterId" yaml:"matterId"`
	PhaseID          *string  `json:"phaseId" yaml:"phaseId"`
	NotebookFolderID *string  `json:"notebookFolderId" yaml:"notebookFolderId"`
	Title            string   `json:"title" yaml:"title"`
	Content          string   `json:"-" yaml:"-"` // Not stored in frontmatter
	CreatedAt        string   `json:"createdAt" yaml:"createdAt"`
	UpdatedAt        string   `json:"updatedAt" yaml:"updatedAt"`
	Tags             []string `json:"tags" yaml:"tags"`
	IsPinned         bool     `json:"isPinned" yaml:"isPinned"`
	Attachments      []string `json:"attachments" yaml:"attachments"`
}

// MatterStatus represents the status of a matter
type MatterStatus string

const (
	MatterStatusActive    MatterStatus = "active"
	MatterStatusPaused    MatterStatus = "paused"
	MatterStatusCompleted MatterStatus = "completed"
	MatterStatusArchived  MatterStatus = "archived"
)

// Phase represents a phase within a matter
type Phase struct {
	ID       string `json:"id"`
	MatterID string `json:"matterId"`
	Name     string `json:"name"`
	Order    int    `json:"order"`
}

// Matter represents a Chronicle matter (project)
type Matter struct {
	ID              string       `json:"id"`
	CategoryID      *string      `json:"categoryId"`
	Title           string       `json:"title"`
	Description     string       `json:"description"`
	Status          MatterStatus `json:"status"`
	Color           string       `json:"color"`
	Icon            string       `json:"icon"`
	CreatedAt       string       `json:"createdAt"`
	UpdatedAt       string       `json:"updatedAt"`
	StartedAt       *string      `json:"startedAt"`
	EndedAt         *string      `json:"endedAt"`
	IsPinned        bool         `json:"isPinned"`
	Phases          []Phase      `json:"phases"`
	CurrentPhaseID  *string      `json:"currentPhaseId"`
}

// Category represents a category for organizing matters
type Category struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	Color     string `json:"color"`
	Icon      string `json:"icon"`
	CreatedAt string `json:"createdAt"`
	UpdatedAt string `json:"updatedAt"`
}

// NotebookFolder represents a folder in the notebook
type NotebookFolder struct {
	ID        string  `json:"id"`
	Name      string  `json:"name"`
	ParentID  *string `json:"parentId"`
	CreatedAt string  `json:"createdAt"`
	UpdatedAt string  `json:"updatedAt"`
}

// NoteLink represents a bidirectional link between notes
type NoteLink struct {
	ID           string `json:"id"`
	SourceNoteID string `json:"sourceNoteId"`
	TargetNoteID string `json:"targetNoteId"`
	Context      string `json:"context"`
	CreatedAt    string `json:"createdAt"`
}

// SyncConfig represents WebDAV sync configuration
type SyncConfig struct {
	URL        string `json:"url"`
	Username   string `json:"username"`
	Password   string `json:"password"`
	RemotePath string `json:"remotePath"`
}

// SyncStatus represents the status of a sync operation
type SyncStatus struct {
	LastSyncAt      *string `json:"lastSyncAt"`
	LastSyncSuccess bool    `json:"lastSyncSuccess"`
	LastError       *string `json:"lastError"`
}

// Conflict represents a sync conflict
type Conflict struct {
	Path             string `json:"path"`
	OriginalPath     string `json:"originalPath"`
	ConflictDetected string `json:"conflictDetectedAt"`
	LocalDevice      string `json:"localDevice"`
	RemoteDevice     string `json:"remoteDevice"`
	LocalContentHash string `json:"localContentHash"`
	RemoteContentHash string `json:"remoteContentHash"`
}

// NowISO returns the current time in ISO 8601 format
func NowISO() string {
	return time.Now().UTC().Format(time.RFC3339Nano)
}

// DefaultPhases returns the default phases for a new matter
func DefaultPhases(matterID string) []Phase {
	return []Phase{
		{ID: "inbox", MatterID: matterID, Name: "Inbox", Order: 0},
		{ID: "processing", MatterID: matterID, Name: "Processing", Order: 1},
		{ID: "active", MatterID: matterID, Name: "Active", Order: 2},
		{ID: "paused", MatterID: matterID, Name: "Paused", Order: 3},
		{ID: "completed", MatterID: matterID, Name: "Completed", Order: 4},
	}
}
