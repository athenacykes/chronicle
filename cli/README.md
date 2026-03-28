# Chronicle CLI

A command-line interface for Chronicle that operates on the same local storage and WebDAV sync contracts as the Flutter app.

## Features

- **CRUD operations**: Matters, Notes, Notebooks (folders), and Categories
- **WebDAV sync**: Bidirectional sync with conflict resolution
- **Search**: Unified search across all entity types
- **Conflict resolution**: View and resolve sync conflicts
- **AI-friendly**: JSON output support for easy parsing by scripts and AI agents

## Installation

```bash
# Build for current platform
go build -o chronicle

# Build for Linux AMD64
GOOS=linux GOARCH=amd64 go build -o chronicle-linux
```

## Quick Start

```bash
# Initialize configuration (interactive)
chronicle config init

# Configure WebDAV settings
# - Storage root: where local files are stored
# - WebDAV URL: your WebDAV server URL
# - Username/Password: WebDAV credentials
# - Remote path: path on WebDAV server

# Check initial sync state
chronicle sync bootstrap

# Perform initial sync
chronicle sync now
```

## Commands

### Configuration

```bash
chronicle config init          # Interactive setup
chronicle config show          # Show current config
chronicle config get <key>     # Get config value
chronicle config set <key> <value>  # Set config value
```

### Matters

```bash
chronicle matter list                          # List all matters
chronicle matter list --category-id <id>       # Filter by category
chronicle matter get <id>                      # Get matter details
chronicle matter create --title "Project X"    # Create matter
chronicle matter update <id> --title "New Name"
chronicle matter delete <id>
chronicle matter set-status <id> active|paused|completed|archived
chronicle matter pin <id>                      # Pin matter
chronicle matter pin <id> --unpin              # Unpin matter

# Phases
chronicle matter phases <id>                   # List phases
chronicle matter add-phase <id> --name "Review"
chronicle matter set-phase <matter-id> <phase-id>
```

### Notes

```bash
chronicle note list                            # List all notes
chronicle note list --matter-id <id> --phase-id <id>
chronicle note list --folder-id <id>
chronicle note list --tag <tag>
chronicle note get <id> --include-content
chronicle note create --title "My Note" --content "Body"
chronicle note create --title "Matter Note" --content "..." --matter-id <id> --phase-id <id>
chronicle note create --title "Folder Note" --content "..." --folder-id <id>
chronicle note update <id> --title "New Title" --content "New content"
chronicle note move <id> --folder-id <id>
chronicle note delete <id>
chronicle note pin <id>
```

### Notebook Folders

```bash
chronicle notebook list
chronicle notebook create --name "My Folder"
chronicle notebook create --name "Subfolder" --parent-id <id>
chronicle notebook rename <id> --name "New Name"
chronicle notebook delete <id>
```

### Categories

```bash
chronicle category list
chronicle category create --name "Work" --color "#FF0000"
chronicle category update <id> --name "New Name"
chronicle category delete <id>
```

### Search

```bash
chronicle search "keyword"                     # Search all entities
chronicle search "keyword" --type note         # Search only notes
chronicle search "keyword" --type matter       # Search only matters
```

### Sync

```bash
chronicle sync bootstrap                       # Assess sync state
chronicle sync status                          # Check last sync
chronicle sync now                             # Normal sync
chronicle sync now --mode force-apply-deletions
chronicle sync now --mode force-break-lock
chronicle sync now --mode recover-local-wins   # Push local to remote
chronicle sync now --mode recover-remote-wins  # Pull remote to local
```

### Conflicts

```bash
chronicle conflict list                        # List all conflicts
chronicle conflict show <path>                 # Show conflict details
chronicle conflict resolve <path> --accept local
chronicle conflict resolve <path> --accept remote
```

## JSON Output

All commands support `--json` flag for machine-readable output:

```bash
chronicle matter list --json
chronicle note get <id> --json
chronicle search "keyword" --json
```

## Storage Format

The CLI uses the same storage format as the Chronicle Flutter app:

- **Notes**: Markdown files with YAML frontmatter
- **Matters**: JSON metadata with embedded phases
- **Categories**: JSON files
- **Notebook Folders**: JSON index + directory structure

Storage layout:
```
<storage_root>/
├── .sync/              # Sync metadata
├── notebook/
│   ├── root/          # Unfiled notes
│   └── folders/       # Folder notes
├── matters/           # Matter directories
├── categories/        # Category JSON files
└── info.json          # Storage metadata
```

## WebDAV Sync

The sync protocol:

1. Acquires a lock on the server
2. Compares local and remote file hashes
3. Uploads new/changed local files
4. Downloads new/changed remote files
5. Detects conflicts (both sides changed)
6. Resolves conflicts (remote wins, local saved as `.conflict.<timestamp>.<id>.ext`)
7. Updates manifest on both sides

Conflict files contain:
- Original file metadata
- Conflict detection timestamp
- Content hashes
- The local version of the content

## Environment Variables

```bash
CHRONICLE_CONFIG         # Path to config file (default: ~/.config/chronicle/config.json)
CHRONICLE_STORAGE_ROOT   # Override storage root path
```

## License

Same as the main Chronicle project.
