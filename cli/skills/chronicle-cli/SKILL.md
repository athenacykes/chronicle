---
name: chronicle-cli
description: |
  Guide for AI agents to interact with Chronicle notes via the CLI tool.
  Use this skill whenever the user wants to read, create, edit, move, search,
  or manage Chronicle notes, matters, notebook folders, or categories via command line.
  This includes tasks like "create a note", "list matters", "search notes",
  "move note to folder", "sync with WebDAV", "resolve conflicts", or any
  Chronicle-related data management. Also use for WebDAV sync operations,
  conflict resolution, and organizing notes into projects/matters.
---

# Chronicle CLI Skill

Guide for AI agents to interact with Chronicle notes via the CLI tool.

## When to Use

Use this skill when:
- User wants to create, read, update, or delete Chronicle notes
- User needs to manage matters (projects) and their phases
- User wants to organize notes into notebook folders
- User needs to categorize matters
- User wants to search across notes, matters, categories, or folders
- User needs to sync with WebDAV or resolve sync conflicts
- User mentions "chronicle" in the context of note-taking or project management

## Prerequisites

- `chronicle` binary must be in PATH
- Configuration must be initialized (`chronicle config init`)

## Core Concepts

### Entity Types

1. **Matters** - Projects/containers for notes with phases (Inbox, Processing, Active, Paused, Completed)
2. **Notes** - Markdown content with YAML frontmatter (title, tags, attachments)
3. **Notebook Folders** - Hierarchical folders for organizing notes outside matters
4. **Categories** - Labels for classifying matters

### Storage Locations

- Notes can be in: `notebook/root/`, `notebook/folders/<folderId>/`, or `matters/<matterId>/phases/<phaseId>/`
- Each note is a `.md` file with YAML frontmatter

## Command Reference

### Configuration

```bash
# Check if configured
chronicle config show --json

# Get storage root
chronicle config get storageRoot
```

### Matters (Projects)

```bash
# List all matters
chronicle matter list --json

# Get matter details
chronicle matter get <matter-id> --json

# Create a matter
chronicle matter create --title "Project Name" --description "..." --json

# Update matter
chronicle matter update <matter-id> --title "New Name" --json

# Set status
chronicle matter set-status <matter-id> active|paused|completed|archived

# List phases
chronicle matter phases <matter-id> --json

# Add phase
chronicle matter add-phase <matter-id> --name "Review" --json

# Set current phase
chronicle matter set-phase <matter-id> <phase-id>

# Pin/unpin matter
chronicle matter pin <matter-id>
chronicle matter pin <matter-id> --unpin

# Delete matter
chronicle matter delete <matter-id>
```

### Notes

```bash
# List notes (all, by matter, by folder, by tag)
chronicle note list --json
chronicle note list --matter-id <id> --phase-id <id> --json
chronicle note list --folder-id <id> --json
chronicle note list --tag <tag> --json

# Get note (content excluded by default)
chronicle note get <note-id> --json
chronicle note get <note-id> --include-content --json

# Create note
chronicle note create --title "Title" --content "Body" --json
chronicle note create --title "Title" --content "Body" --matter-id <id> --phase-id <id> --json
chronicle note create --title "Title" --content "Body" --folder-id <id> --tag tag1 --tag tag2 --json

# Update note
chronicle note update <note-id> --title "New Title" --content "New body" --json

# Move note between locations
chronicle note move <note-id> --folder-id <id>
chronicle note move <note-id> --matter-id <id> --phase-id <id>

# Pin/unpin note
chronicle note pin <note-id>
chronicle note pin <note-id> --unpin

# Delete note
chronicle note delete <note-id>
```

### Notebook Folders

```bash
# List folders
chronicle notebook list --json

# Create folder
chronicle notebook create --name "Folder Name" --json
chronicle notebook create --name "Subfolder" --parent-id <id> --json

# Rename folder
chronicle notebook rename <folder-id> --name "New Name" --json

# Delete folder (must be empty)
chronicle notebook delete <folder-id>
```

### Categories

```bash
# List categories
chronicle category list --json

# Create category
chronicle category create --name "Work" --color "#FF0000" --json

# Update category
chronicle category update <id> --name "New Name" --json

# Delete category
chronicle category delete <id>
```

### Search

```bash
# Search all entities
chronicle search "keyword" --json

# Search specific type
chronicle search "keyword" --type note --json
chronicle search "keyword" --type matter --json
chronicle search "keyword" --type category --json
chronicle search "keyword" --type notebook --json

# Limit results
chronicle search "keyword" --limit 10 --json
```

### WebDAV Sync

```bash
# Check sync status
chronicle sync status --json

# Assess bootstrap state
chronicle sync bootstrap --json

# Sync now
chronicle sync now --json

# Sync with recovery mode
chronicle sync now --mode recover-local-wins --json
chronicle sync now --mode recover-remote-wins --json
```

### Conflict Resolution

```bash
# List conflicts
chronicle conflict list --json

# Show conflict details
chronicle conflict show <path> --json

# Resolve conflict (keep local or remote)
chronicle conflict resolve <path> --accept local
chronicle conflict resolve <path> --accept remote
```

## Workflows

### Create a New Project with Notes

1. Create matter: `chronicle matter create --title "Project X" --json`
2. Get phases: `chronicle matter phases <matter-id> --json`
3. Create note in phase: `chronicle note create --title "Idea" --content "..." --matter-id <id> --phase-id <id> --json`

### Organize Existing Notes

1. List all notes: `chronicle note list --json`
2. Create folder: `chronicle notebook create --name "Archive" --json`
3. Move notes: `chronicle note move <note-id> --folder-id <folder-id>`

### Find and Update Content

1. Search: `chronicle search "keyword" --type note --json`
2. Get full content: `chronicle note get <note-id> --include-content --json`
3. Update: `chronicle note update <note-id> --content "new content" --json`

### Sync Workflow

1. Check status: `chronicle sync status --json`
2. If never synced: `chronicle sync bootstrap --json`
3. Sync: `chronicle sync now --json`
4. Handle conflicts if any: `chronicle conflict list --json`

## JSON Output Format

All `--json` commands return structured JSON for easy parsing.

### Matter
```json
{
  "id": "uuid",
  "title": "Title",
  "description": "...",
  "status": "active",
  "color": "#4C956C",
  "phases": [...],
  "currentPhaseId": "..."
}
```

### Note
```json
{
  "id": "uuid",
  "title": "Title",
  "matterId": "...",
  "phaseId": "...",
  "notebookFolderId": null,
  "content": "...",
  "tags": ["tag1"],
  "isPinned": false
}
```

### Search Result
```json
[
  {
    "type": "note",
    "id": "uuid",
    "name": "Title",
    "data": {...}
  }
]
```

## Error Handling

Always check exit codes:
- `0` = Success
- `1` = Error (check stderr)

Common errors:
- Configuration not initialized
- Storage root not found
- Entity not found (UUID)
- Conflict file exists
- Sync lock held by another client

## Best Practices

1. **Always use `--json`** for programmatic access - output is machine-readable
2. **Use search first** to find entities before operating on them
3. **Get before update** - retrieve current state, modify, then update
4. **Handle conflicts** after sync - check `chronicle conflict list`
5. **Sync after batch operations** - minimize sync frequency for multiple changes
6. **Validate UUIDs** - all IDs are UUID format (36 chars with dashes)

## File Format Reference

### Note YAML Frontmatter
```yaml
---
id: "uuid"
matterId: "uuid" | null
phaseId: "uuid" | null
notebookFolderId: "uuid" | null
title: "Title"
createdAt: "2024-01-15T10:30:00.000Z"
updatedAt: "2024-01-15T14:20:00.000Z"
tags: ["tag1", "tag2"]
isPinned: false
attachments: ["resources/..."]
---
```

### Matter JSON Structure
```json
{
  "id": "uuid",
  "categoryId": "uuid|null",
  "title": "Title",
  "description": "...",
  "status": "active|paused|completed|archived",
  "color": "#4C956C",
  "icon": "description",
  "createdAt": "...",
  "updatedAt": "...",
  "phases": [
    {"id": "uuid", "name": "Phase", "order": 0}
  ],
  "currentPhaseId": "uuid"
}
```
