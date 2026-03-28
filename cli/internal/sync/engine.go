package sync

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"chronicle/internal/domain"
	"chronicle/internal/storage"
)

// Engine orchestrates WebDAV sync operations
type Engine struct {
	client     *WebDAVClient
	layout     *storage.ChronicleLayout
	clientType string
	clientID   string
	remotePath string
}

// NewEngine creates a new sync engine
func NewEngine(client *WebDAVClient, layout *storage.ChronicleLayout, clientType, clientID, remotePath string) *Engine {
	return &Engine{
		client:     client,
		layout:     layout,
		clientType: clientType,
		clientID:   clientID,
		remotePath: strings.TrimPrefix(remotePath, "/"),
	}
}

// AcquireLock attempts to acquire the sync lock
func (e *Engine) AcquireLock(force bool) error {
	lockPath := e.remoteLockPath()

	// Check if lock exists
	if e.client.Exists(lockPath) {
		if !force {
			// Try to read existing lock
			lockContent, err := e.client.Get(lockPath)
			if err == nil {
				lock, err := ParseLockFile(lockContent)
				if err == nil && !lock.IsStale() {
					return fmt.Errorf("sync lock held by %s/%s (use --force-break-lock to override)", lock.ClientType, lock.ClientID)
				}
			}
		}
	}

	// Create our lock
	lock := CreateLockFile(e.clientType, e.clientID)
	lockData, err := lock.ToJSON()
	if err != nil {
		return fmt.Errorf("failed to create lock: %w", err)
	}

	// Ensure locks directory exists
	locksDir := filepath.Join(e.remotePath, "locks")
	e.client.Mkdir(locksDir)

	if err := e.client.Put(lockPath, lockData); err != nil {
		return fmt.Errorf("failed to write lock: %w", err)
	}

	return nil
}

// ReleaseLock releases the sync lock
func (e *Engine) ReleaseLock() error {
	lockPath := e.remoteLockPath()
	return e.client.Delete(lockPath)
}

// remoteLockPath returns the remote path for the lock file
func (e *Engine) remoteLockPath() string {
	return filepath.Join(e.remotePath, "locks", fmt.Sprintf("sync_%s_%s.json", e.clientType, e.clientID))
}

// Sync performs a bidirectional sync
func (e *Engine) Sync(options SyncRunOptions) (*SyncResult, error) {
	startTime := time.Now()
	result := &SyncResult{
		Success: true,
		Errors:  []string{},
	}

	// Progress callback helper
	progress := func(msg string, pct float64) {
		if options.OnProgress != nil {
			options.OnProgress(msg, pct)
		}
	}

	progress("Acquiring lock...", 0.05)

	// Handle special modes
	forceBreakLock := options.Mode == SyncModeForceBreakLock
	recoverLocalWins := options.Mode == SyncModeRecoverLocalWins
	recoverRemoteWins := options.Mode == SyncModeRecoverRemoteWins
	forceDeletions := options.Mode == SyncModeForceApplyDeletions

	// Acquire lock
	if err := e.AcquireLock(forceBreakLock); err != nil {
		result.Success = false
		result.Errors = append(result.Errors, err.Error())
		return result, err
	}
	defer e.ReleaseLock()

	progress("Scanning local files...", 0.1)

	// Ensure remote directories exist
	progress("Checking remote directories...", 0.15)
	e.ensureRemoteDirectories()

	// Load manifests
	progress("Loading sync manifests...", 0.2)

	localManifest, _ := LoadManifest(e.layout.ManifestPath())
	if localManifest == nil {
		localManifest = &Manifest{Entries: make(map[string]ManifestEntry)}
	}

	remoteManifest, err := e.loadRemoteManifest()
	if err != nil {
		// No remote manifest yet - will create one
		remoteManifest = &Manifest{Entries: make(map[string]ManifestEntry)}
	}

	// Handle recovery modes
	if recoverLocalWins {
		progress("Recovery mode: pushing local state to remote...", 0.3)
		return e.pushAllToRemote(result, progress)
	}

	if recoverRemoteWins {
		progress("Recovery mode: pulling remote state to local...", 0.3)
		return e.pullAllFromRemote(result, progress)
	}

	// Scan local files
	localFiles, err := e.layout.ScanDirectory(e.layout.Root)
	if err != nil {
		result.Success = false
		result.Errors = append(result.Errors, fmt.Sprintf("failed to scan local files: %v", err))
		return result, err
	}

	// Scan remote files
	progress("Scanning remote files...", 0.3)
	remoteFiles, err := e.client.ListFilesRecursive(e.remotePath)
	if err != nil {
		// Remote might be empty - that's OK
		remoteFiles = []storage.FileInfo{}
	}

	// Filter out sync metadata from remote files
	var filteredRemoteFiles []storage.FileInfo
	for _, f := range remoteFiles {
		parts := strings.Split(f.Path, "/")
		if len(parts) > 0 && parts[0] == ".sync" {
			continue
		}
		if len(parts) > 0 && parts[0] == "locks" {
			continue
		}
		filteredRemoteFiles = append(filteredRemoteFiles, f)
	}
	remoteFiles = filteredRemoteFiles

	// Compute hashes for remote files
	progress("Computing remote file hashes...", 0.35)
	for i := range remoteFiles {
		remotePath := filepath.Join(e.remotePath, remoteFiles[i].Path)
		content, err := e.client.Get(remotePath)
		if err == nil {
			remoteFiles[i].ContentHash = storage.ComputeHash(content)
		}
	}

	// Plan sync operations
	progress("Planning sync operations...", 0.4)
	operations := Plan(localFiles, remoteFiles, localManifest, remoteManifest)

	// Check deletion safety
	if !forceDeletions {
		deleteCount := 0
		for _, op := range operations {
			if op.Type == "delete-local" {
				deleteCount++
			}
		}

		// Safety check: if more than 20% of files would be deleted, abort
		if len(localFiles) > 0 && float64(deleteCount)/float64(len(localFiles)) > 0.2 {
			result.Success = false
			result.Errors = append(result.Errors, fmt.Sprintf(
				"deletion safety triggered: %d files (%.0f%%) would be deleted. Use --force-apply-deletions to override",
				deleteCount, float64(deleteCount)/float64(len(localFiles))*100,
			))
			return result, fmt.Errorf("deletion safety triggered")
		}
	}

	// Load conflict history for deduplication
	conflictHistory, _ := LoadConflictHistory(e.layout.ConflictHistoryPath())

	// Execute operations
	totalOps := len(operations)
	for i, op := range operations {
		progressPct := 0.5 + (float64(i) / float64(totalOps) * 0.4)

		switch op.Type {
		case "upload":
			progress(fmt.Sprintf("Uploading %s...", op.Path), progressPct)
			if err := e.uploadFile(op.Path); err != nil {
				result.Errors = append(result.Errors, fmt.Sprintf("upload %s: %v", op.Path, err))
			} else {
				result.Uploaded++
			}

		case "download":
			progress(fmt.Sprintf("Downloading %s...", op.Path), progressPct)
			if err := e.downloadFile(op.Path); err != nil {
				result.Errors = append(result.Errors, fmt.Sprintf("download %s: %v", op.Path, err))
			} else {
				result.Downloaded++
			}

		case "delete-local":
			progress(fmt.Sprintf("Deleting local %s...", op.Path), progressPct)
			if err := e.deleteLocalFile(op.Path); err != nil {
				result.Errors = append(result.Errors, fmt.Sprintf("delete local %s: %v", op.Path, err))
			} else {
				result.Deleted++
			}

		case "conflict":
			progress(fmt.Sprintf("Handling conflict for %s...", op.Path), progressPct)

			// Check if we've already seen this conflict
			fingerprint := ComputeConflictFingerprint(op.Path, op.LocalHash, op.RemoteHash)
			if !conflictHistory.HasConflict(fingerprint) {
				if err := e.handleConflict(op.Path, op.LocalHash, op.RemoteHash); err != nil {
					result.Errors = append(result.Errors, fmt.Sprintf("conflict %s: %v", op.Path, err))
				} else {
					result.Conflicts++
					conflictHistory.AddConflict(fingerprint)
				}
			}
		}
	}

	// Cleanup old conflict entries
	conflictHistory.Cleanup()
	conflictHistory.Save(e.layout.ConflictHistoryPath())

	// Update local manifest
	progress("Updating sync manifest...", 0.9)
	newManifest, _ := BuildManifest(e.layout)
	newManifest.Save(e.layout.ManifestPath())

	// Upload manifest to remote
	progress("Uploading manifest...", 0.95)
	e.uploadManifest(newManifest)

	progress("Sync complete", 1.0)

	result.Duration = time.Since(startTime)

	if len(result.Errors) > 0 {
		result.Success = false
	}

	return result, nil
}

// ensureRemoteDirectories creates necessary remote directories
func (e *Engine) ensureRemoteDirectories() {
	dirs := []string{
		e.remotePath,
		filepath.Join(e.remotePath, ".sync"),
		filepath.Join(e.remotePath, "locks"),
		filepath.Join(e.remotePath, "notebook"),
		filepath.Join(e.remotePath, "notebook", "root"),
		filepath.Join(e.remotePath, "notebook", "folders"),
		filepath.Join(e.remotePath, "matters"),
		filepath.Join(e.remotePath, "categories"),
		filepath.Join(e.remotePath, "links"),
		filepath.Join(e.remotePath, "resources"),
	}

	for _, dir := range dirs {
		e.client.Mkdir(dir)
	}
}

// loadRemoteManifest loads the manifest from remote
func (e *Engine) loadRemoteManifest() (*Manifest, error) {
	remoteManifestPath := filepath.Join(e.remotePath, ".sync", "manifest.json")
	content, err := e.client.Get(remoteManifestPath)
	if err != nil {
		return nil, err
	}

	var manifest Manifest
	if err := json.Unmarshal(content, &manifest); err != nil {
		return nil, err
	}

	return &manifest, nil
}

// uploadManifest uploads the manifest to remote
func (e *Engine) uploadManifest(manifest *Manifest) error {
	remoteManifestPath := filepath.Join(e.remotePath, ".sync", "manifest.json")
	data, err := json.MarshalIndent(manifest, "", "  ")
	if err != nil {
		return err
	}
	return e.client.Put(remoteManifestPath, data)
}

// uploadFile uploads a file to WebDAV
func (e *Engine) uploadFile(localPath string) error {
	fullLocalPath := filepath.Join(e.layout.Root, localPath)
	content, err := os.ReadFile(fullLocalPath)
	if err != nil {
		return err
	}

	remotePath := filepath.Join(e.remotePath, localPath)

	// Ensure parent directory exists
	parentDir := filepath.Dir(remotePath)
	e.ensureRemotePath(parentDir)

	return e.client.Put(remotePath, content)
}

// downloadFile downloads a file from WebDAV
func (e *Engine) downloadFile(remotePath string) error {
	fullRemotePath := filepath.Join(e.remotePath, remotePath)
	content, err := e.client.Get(fullRemotePath)
	if err != nil {
		return err
	}

	localPath := filepath.Join(e.layout.Root, remotePath)

	// Ensure parent directory exists
	if err := os.MkdirAll(filepath.Dir(localPath), 0755); err != nil {
		return err
	}

	return os.WriteFile(localPath, content, 0644)
}

// deleteLocalFile deletes a local file
func (e *Engine) deleteLocalFile(localPath string) error {
	fullPath := filepath.Join(e.layout.Root, localPath)
	return os.Remove(fullPath)
}

// handleConflict handles a sync conflict (remote wins, local saved as conflict)
func (e *Engine) handleConflict(path, localHash, remoteHash string) error {
	// Download remote version
	remoteContent, err := e.client.Get(filepath.Join(e.remotePath, path))
	if err != nil {
		return fmt.Errorf("failed to download remote version: %w", err)
	}

	// Read local version
	localPath := filepath.Join(e.layout.Root, path)
	localContentBytes, err := os.ReadFile(localPath)
	if err != nil {
		return fmt.Errorf("failed to read local version: %w", err)
	}

	// Save conflict file
	conflictContent := CreateConflictFile(
		path,
		string(localContentBytes),
		e.clientType+"-"+e.clientID[:8],
		localHash,
		remoteHash,
		e.clientID,
	)

	conflictPath := localPath + ".conflict." + time.Now().UTC().Format("20060102150405") + "." + e.clientID[:8] + filepath.Ext(path)
	if err := os.WriteFile(conflictPath, []byte(conflictContent), 0644); err != nil {
		return fmt.Errorf("failed to write conflict file: %w", err)
	}

	// Overwrite local with remote
	if err := os.WriteFile(localPath, remoteContent, 0644); err != nil {
		return fmt.Errorf("failed to write remote version: %w", err)
	}

	return nil
}

// pushAllToRemote pushes all local files to remote (recover local wins)
func (e *Engine) pushAllToRemote(result *SyncResult, progress func(string, float64)) (*SyncResult, error) {
	localFiles, err := e.layout.ScanDirectory(e.layout.Root)
	if err != nil {
		result.Success = false
		result.Errors = append(result.Errors, fmt.Sprintf("failed to scan local files: %v", err))
		return result, err
	}

	total := len(localFiles)
	for i, file := range localFiles {
		if file.IsDir {
			continue
		}

		progressPct := float64(i) / float64(total)
		progress(fmt.Sprintf("Uploading %s...", file.Path), progressPct)

		if err := e.uploadFile(file.Path); err != nil {
			result.Errors = append(result.Errors, fmt.Sprintf("upload %s: %v", file.Path, err))
		} else {
			result.Uploaded++
		}
	}

	// Update and upload manifest
	newManifest, _ := BuildManifest(e.layout)
	newManifest.Save(e.layout.ManifestPath())
	e.uploadManifest(newManifest)

	progress("Recovery complete - local state pushed to remote", 1.0)

	return result, nil
}

// pullAllFromRemote pulls all remote files to local (recover remote wins)
func (e *Engine) pullAllFromRemote(result *SyncResult, progress func(string, float64)) (*SyncResult, error) {
	remoteFiles, err := e.client.ListFilesRecursive(e.remotePath)
	if err != nil {
		result.Success = false
		result.Errors = append(result.Errors, fmt.Sprintf("failed to list remote files: %v", err))
		return result, err
	}

	// Filter out sync metadata
	var filteredFiles []storage.FileInfo
	for _, f := range remoteFiles {
		parts := strings.Split(f.Path, "/")
		if len(parts) > 0 && (parts[0] == ".sync" || parts[0] == "locks") {
			continue
		}
		filteredFiles = append(filteredFiles, f)
	}

	total := len(filteredFiles)
	for i, file := range filteredFiles {
		progressPct := float64(i) / float64(total)
		progress(fmt.Sprintf("Downloading %s...", file.Path), progressPct)

		if err := e.downloadFile(file.Path); err != nil {
			result.Errors = append(result.Errors, fmt.Sprintf("download %s: %v", file.Path, err))
		} else {
			result.Downloaded++
		}
	}

	// Update local manifest
	newManifest, _ := BuildManifest(e.layout)
	newManifest.Save(e.layout.ManifestPath())

	progress("Recovery complete - remote state pulled to local", 1.0)

	return result, nil
}

// ensureRemotePath ensures a remote path exists by creating parent directories
func (e *Engine) ensureRemotePath(remotePath string) {
	parts := strings.Split(remotePath, "/")
	currentPath := ""
	for _, part := range parts {
		if part == "" {
			continue
		}
		if currentPath == "" {
			currentPath = part
		} else {
			currentPath = currentPath + "/" + part
		}
		e.client.Mkdir(currentPath)
	}
}

// Status returns the current sync status
func (e *Engine) Status() (*domain.SyncStatus, error) {
	// Check if manifest exists
	_, err := os.Stat(e.layout.ManifestPath())
	if err != nil {
		return &domain.SyncStatus{
			LastSyncAt:      nil,
			LastSyncSuccess: false,
		}, nil
	}

	// Load manifest to get last sync time
	manifest, err := LoadManifest(e.layout.ManifestPath())
	if err != nil {
		return nil, err
	}

	lastSyncAt := manifest.GeneratedAt

	return &domain.SyncStatus{
		LastSyncAt:      &lastSyncAt,
		LastSyncSuccess: true,
	}, nil
}

// BootstrapAssessment provides information for initial sync setup
type BootstrapAssessment struct {
	LocalItemCount  int  `json:"localItemCount"`
	RemoteItemCount int  `json:"remoteItemCount"`
	RemoteHasData   bool `json:"remoteHasData"`
	LocalHasData    bool `json:"localHasData"`
	Recommendation  string `json:"recommendation"`
}

// AssessBootstrap analyzes local and remote state to provide sync guidance
func (e *Engine) AssessBootstrap() (*BootstrapAssessment, error) {
	// Count local items
	localFiles, err := e.layout.ScanDirectory(e.layout.Root)
	if err != nil {
		return nil, fmt.Errorf("failed to scan local files: %w", err)
	}

	localCount := 0
	for _, f := range localFiles {
		if !f.IsDir {
			localCount++
		}
	}

	// Count remote items
	remoteFiles, err := e.client.ListFilesRecursive(e.remotePath)
	remoteCount := 0
	if err == nil {
		for _, f := range remoteFiles {
			parts := strings.Split(f.Path, "/")
			if len(parts) > 0 && (parts[0] == ".sync" || parts[0] == "locks") {
				continue
			}
			if !f.IsDir {
				remoteCount++
			}
		}
	}

	assessment := &BootstrapAssessment{
		LocalItemCount:  localCount,
		RemoteItemCount: remoteCount,
		RemoteHasData:   remoteCount > 0,
		LocalHasData:    localCount > 0,
	}

	// Provide recommendation
	switch {
	case localCount == 0 && remoteCount == 0:
		assessment.Recommendation = "Both local and remote are empty. Ready to start fresh."
	case localCount == 0 && remoteCount > 0:
		assessment.Recommendation = "Remote has data but local is empty. Run 'chronicle sync now --mode recover-remote-wins' to download."
	case localCount > 0 && remoteCount == 0:
		assessment.Recommendation = "Local has data but remote is empty. Run 'chronicle sync now' to upload."
	case localCount > 0 && remoteCount > 0:
		assessment.Recommendation = "Both local and remote have data. Run 'chronicle sync now' to merge (conflicts will be handled)."
	}

	return assessment, nil
}
