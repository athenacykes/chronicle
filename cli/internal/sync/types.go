package sync

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"chronicle/internal/storage"
)

// ManifestEntry represents a file entry in the sync manifest
type ManifestEntry struct {
	CanonicalPath string `json:"canonicalPath"`
	SourcePath    string `json:"sourcePath"`
	ContentHash   string `json:"contentHash"`
	Size          int64  `json:"size"`
	UpdatedAt     string `json:"updatedAt"`
	IsLegacyOrphan bool  `json:"isLegacyOrphan"`
}

// Manifest represents the sync manifest
type Manifest struct {
	Revision    string                   `json:"revision"`
	GeneratedAt string                   `json:"generatedAt"`
	Entries     map[string]ManifestEntry `json:"entries"`
}

// FileState represents the state of a file for sync purposes
type FileState struct {
	Path        string
	ContentHash string
	Size        int64
	UpdatedAt   time.Time
	Exists      bool
}

// SyncLock represents a sync lock file
type SyncLock struct {
	Type       string `json:"type"`
	ClientType string `json:"clientType"`
	ClientID   string `json:"clientID"`
	UpdatedTime int64 `json:"updatedTime"`
}

// SyncConflict represents a detected conflict
type SyncConflict struct {
	Path             string `json:"path"`
	OriginalPath     string `json:"originalPath"`
	ConflictDetected string `json:"conflictDetectedAt"`
	LocalDevice      string `json:"localDevice"`
	RemoteDevice     string `json:"remoteDevice"`
	LocalContentHash string `json:"localContentHash"`
	RemoteContentHash string `json:"remoteContentHash"`
	ConflictFingerprint string `json:"conflictFingerprint"`
}

// SyncResult represents the result of a sync operation
type SyncResult struct {
	Success         bool           `json:"success"`
	Uploaded        int            `json:"uploaded"`
	Downloaded      int            `json:"downloaded"`
	Deleted         int            `json:"deleted"`
	Conflicts       int            `json:"conflicts"`
	Errors          []string       `json:"errors"`
	Duration        time.Duration  `json:"duration"`
}

// SyncRunMode represents the sync run mode
type SyncRunMode string

const (
	SyncModeNormal              SyncRunMode = "normal"
	SyncModeForceApplyDeletions SyncRunMode = "force-apply-deletions"
	SyncModeForceBreakLock      SyncRunMode = "force-break-lock"
	SyncModeRecoverLocalWins    SyncRunMode = "recover-local-wins"
	SyncModeRecoverRemoteWins   SyncRunMode = "recover-remote-wins"
)

// SyncRunOptions contains options for a sync run
type SyncRunOptions struct {
	Mode       SyncRunMode
	OnProgress func(message string, progress float64)
}

// LoadManifest loads a manifest from disk
func LoadManifest(path string) (*Manifest, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	var manifest Manifest
	if err := json.Unmarshal(data, &manifest); err != nil {
		return nil, err
	}

	return &manifest, nil
}

// Save saves the manifest to disk
func (m *Manifest) Save(path string) error {
	data, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return err
	}

	return os.WriteFile(path, data, 0644)
}

// BuildManifest creates a manifest from the current local state
func BuildManifest(layout *storage.ChronicleLayout) (*Manifest, error) {
	files, err := layout.ScanDirectory(layout.Root)
	if err != nil {
		return nil, fmt.Errorf("failed to scan directory: %w", err)
	}

	entries := make(map[string]ManifestEntry)

	for _, file := range files {
		if file.IsDir {
			continue
		}

		// Normalize path separators for cross-platform compatibility
		canonicalPath := filepath.ToSlash(file.Path)

		entries[canonicalPath] = ManifestEntry{
			CanonicalPath: canonicalPath,
			SourcePath:    canonicalPath,
			ContentHash:   file.ContentHash,
			Size:          file.Size,
			UpdatedAt:     file.UpdatedAt.UTC().Format(time.RFC3339),
			IsLegacyOrphan: false,
		}
	}

	now := time.Now().UTC()
	return &Manifest{
		Revision:    fmt.Sprintf("%d", now.UnixMilli()),
		GeneratedAt: now.Format(time.RFC3339),
		Entries:     entries,
	}, nil
}

// LoadLocalState loads the local sync state
func LoadLocalState(path string) (*Manifest, error) {
	return LoadManifest(path)
}

// SaveLocalState saves the local sync state
func SaveLocalState(manifest *Manifest, path string) error {
	return manifest.Save(path)
}

// ConflictHistoryEntry represents an entry in the conflict history
type ConflictHistoryEntry struct {
	Fingerprint string `json:"fingerprint"`
	ResolvedAt  string `json:"resolvedAt"`
}

// ConflictHistory manages deduplication of conflicts
type ConflictHistory struct {
	Entries []ConflictHistoryEntry `json:"entries"`
}

// LoadConflictHistory loads the conflict history from disk
func LoadConflictHistory(path string) (*ConflictHistory, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return &ConflictHistory{Entries: []ConflictHistoryEntry{}}, nil
		}
		return nil, err
	}

	var history ConflictHistory
	if err := json.Unmarshal(data, &history); err != nil {
		return nil, err
	}

	return &history, nil
}

// Save saves the conflict history to disk
func (h *ConflictHistory) Save(path string) error {
	data, err := json.MarshalIndent(h, "", "  ")
	if err != nil {
		return err
	}

	return os.WriteFile(path, data, 0644)
}

// HasConflict checks if a conflict fingerprint is in history
func (h *ConflictHistory) HasConflict(fingerprint string) bool {
	for _, entry := range h.Entries {
		if entry.Fingerprint == fingerprint {
			return true
		}
	}
	return false
}

// AddConflict adds a conflict to history
func (h *ConflictHistory) AddConflict(fingerprint string) {
	h.Entries = append(h.Entries, ConflictHistoryEntry{
		Fingerprint: fingerprint,
		ResolvedAt:  time.Now().UTC().Format(time.RFC3339),
	})
}

// Cleanup removes old entries (keeps last 100)
func (h *ConflictHistory) Cleanup() {
	if len(h.Entries) > 100 {
		h.Entries = h.Entries[len(h.Entries)-100:]
	}
}

// ComputeConflictFingerprint computes a unique fingerprint for a conflict
func ComputeConflictFingerprint(path, localHash, remoteHash string) string {
	content := fmt.Sprintf("%s|%s|%s", path, localHash, remoteHash)
	return storage.ComputeStringHash(content)
}

// SyncOperation represents a single sync operation
type SyncOperation struct {
	Type     string // upload, download, delete, conflict
	Path     string
	LocalHash  string
	RemoteHash string
}

// Plan creates a sync plan by comparing local and remote states
func Plan(localFiles []storage.FileInfo, remoteFiles []storage.FileInfo, localManifest, remoteManifest *Manifest) []SyncOperation {
	var ops []SyncOperation

	// Build lookup maps
	localMap := make(map[string]storage.FileInfo)
	for _, f := range localFiles {
		localMap[f.Path] = f
	}

	remoteMap := make(map[string]storage.FileInfo)
	for _, f := range remoteFiles {
		key := filepath.ToSlash(f.Path)
		remoteMap[key] = f
	}

	// Check for files to download or conflicts
	for remotePath, remoteFile := range remoteMap {
		remoteHash := remoteFile.ContentHash

		if localFile, exists := localMap[remotePath]; exists {
			localHash := localFile.ContentHash

			if localHash != remoteHash {
				// Potential conflict - check if both changed from last sync
				localChanged := hasFileChanged(remotePath, localHash, localManifest)
				remoteChanged := hasFileChanged(remotePath, remoteHash, remoteManifest)

				if localChanged && remoteChanged {
					ops = append(ops, SyncOperation{
						Type:       "conflict",
						Path:       remotePath,
						LocalHash:  localHash,
						RemoteHash: remoteHash,
					})
				} else if remoteChanged {
					ops = append(ops, SyncOperation{
						Type:       "download",
						Path:       remotePath,
						RemoteHash: remoteHash,
					})
				}
			}
		} else {
			// File exists remotely but not locally - download
			ops = append(ops, SyncOperation{
				Type:       "download",
				Path:       remotePath,
				RemoteHash: remoteHash,
			})
		}
	}

	// Check for files to upload or delete
	for localPath, localFile := range localMap {
		localHash := localFile.ContentHash

		if _, exists := remoteMap[localPath]; !exists {
			// Check if file was in remote manifest (deleted remotely) or is new
			if wasDeletedRemotely(localPath, remoteManifest) {
				// Remote deleted, check if local changed
				if hasFileChanged(localPath, localHash, localManifest) {
					// Local has changes, upload
					ops = append(ops, SyncOperation{
						Type:      "upload",
						Path:      localPath,
						LocalHash: localHash,
					})
				} else {
					// Safe to delete locally
					ops = append(ops, SyncOperation{
						Type: "delete-local",
						Path: localPath,
					})
				}
			} else {
				// New file - upload
				ops = append(ops, SyncOperation{
					Type:      "upload",
					Path:      localPath,
					LocalHash: localHash,
				})
			}
		} else if hasFileChanged(localPath, localHash, localManifest) {
			// File exists on both sides but local changed
			// Only upload if remote hasn't changed (handled above)
			remoteFile := remoteMap[localPath]
			if remoteFile.ContentHash == getManifestHash(localPath, remoteManifest) {
				ops = append(ops, SyncOperation{
					Type:      "upload",
					Path:      localPath,
					LocalHash: localHash,
				})
			}
		}
	}

	return ops
}

// hasFileChanged checks if a file has changed from the manifest
func hasFileChanged(path, currentHash string, manifest *Manifest) bool {
	if manifest == nil || manifest.Entries == nil {
		return true // No manifest means file is new
	}

	entry, exists := manifest.Entries[path]
	if !exists {
		return true // Not in manifest means file is new
	}

	return entry.ContentHash != currentHash
}

// wasDeletedRemotely checks if a file was in remote manifest but no longer exists remotely
func wasDeletedRemotely(path string, remoteManifest *Manifest) bool {
	if remoteManifest == nil || remoteManifest.Entries == nil {
		return false
	}

	_, exists := remoteManifest.Entries[path]
	return exists
}

// getManifestHash gets the hash from a manifest entry
func getManifestHash(path string, manifest *Manifest) string {
	if manifest == nil || manifest.Entries == nil {
		return ""
	}

	entry, exists := manifest.Entries[path]
	if !exists {
		return ""
	}

	return entry.ContentHash
}

// CreateLockFile creates a sync lock file
func CreateLockFile(clientType, clientID string) *SyncLock {
	return &SyncLock{
		Type:        "sync",
		ClientType:  clientType,
		ClientID:    clientID,
		UpdatedTime: time.Now().UnixMilli(),
	}
}

// ToJSON serializes the lock to JSON
func (l *SyncLock) ToJSON() ([]byte, error) {
	return json.MarshalIndent(l, "", "  ")
}

// ParseLockFile parses a lock file from JSON
func ParseLockFile(data []byte) (*SyncLock, error) {
	var lock SyncLock
	if err := json.Unmarshal(data, &lock); err != nil {
		return nil, err
	}
	return &lock, nil
}

// IsStale checks if a lock is stale (older than 5 minutes)
func (l *SyncLock) IsStale() bool {
	lockTime := time.UnixMilli(l.UpdatedTime)
	return time.Since(lockTime) > 5*time.Minute
}

// CreateConflictFile creates a conflict file with metadata
func CreateConflictFile(originalPath, localContent, localDevice string, localHash string, remoteHash string, clientID string) string {
	fingerprint := ComputeConflictFingerprint(originalPath, localHash, remoteHash)

	var sb strings.Builder
	sb.WriteString("---\n")
	sb.WriteString(fmt.Sprintf("conflictType: \"note\"\n"))
	sb.WriteString(fmt.Sprintf("originalPath: \"%s\"\n", originalPath))
	sb.WriteString(fmt.Sprintf("conflictDetectedAt: \"%s\"\n", time.Now().UTC().Format(time.RFC3339)))
	sb.WriteString(fmt.Sprintf("localDevice: \"%s\"\n", localDevice))
	sb.WriteString(fmt.Sprintf("remoteDevice: \"unknown\"\n"))
	sb.WriteString(fmt.Sprintf("localContentHash: \"%s\"\n", localHash))
	sb.WriteString(fmt.Sprintf("remoteContentHash: \"%s\"\n", remoteHash))
	sb.WriteString(fmt.Sprintf("conflictFingerprint: \"%s\"\n", fingerprint))
	sb.WriteString("---\n\n")
	sb.WriteString(fmt.Sprintf("# [CONFLICT] %s\n\n", originalPath))
	sb.WriteString("This file contains local changes that conflicted with a remote update.\n\n")
	sb.WriteString(localContent)

	return sb.String()
}
