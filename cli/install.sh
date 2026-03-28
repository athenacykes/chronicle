#!/bin/bash
#
# Chronicle CLI Installation Script
# Builds and installs Chronicle CLI for OpenClaw/AI Agent usage
#

set -e

# Configuration
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
OPENCLAW_SKILLS_DIR="${OPENCLAW_SKILLS_DIR:-$HOME/.openclaw/workspace/skills}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI_DIR="$SCRIPT_DIR"
DIST_DIR="$CLI_DIR/dist"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    if ! command -v go &> /dev/null; then
        log_error "Go is not installed. Please install Go 1.21 or later."
        exit 1
    fi

    GO_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
    log_info "Found Go version: $GO_VERSION"

    log_info "Prerequisites check passed"
}

# Build the binary
build_binary() {
    log_info "Building Chronicle CLI for linux/amd64..."

    cd "$CLI_DIR"

    # Clean previous builds
    rm -f chronicle chronicle-linux

    # Download dependencies
    log_info "Downloading dependencies..."
    go mod tidy

    # Build for linux/amd64
    GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o chronicle-linux

    if [ ! -f "$CLI_DIR/chronicle-linux" ]; then
        log_error "Build failed - binary not found"
        exit 1
    fi

    log_info "Build successful: chronicle-linux ($(ls -lh "$CLI_DIR/chronicle-linux" | awk '{print $5}'))"
}

# Create distribution package
create_distribution() {
    log_info "Creating distribution package..."

    mkdir -p "$DIST_DIR"

    # Create version string
    VERSION=$(date +"%Y.%m.%d")
    DIST_NAME="chronicle-cli-${VERSION}-linux-amd64"
    DIST_PATH="$DIST_DIR/$DIST_NAME"

    rm -rf "$DIST_PATH"
    mkdir -p "$DIST_PATH"

    # Copy binary
    cp "$CLI_DIR/chronicle-linux" "$DIST_PATH/chronicle"
    chmod +x "$DIST_PATH/chronicle"

    # Copy skill
    mkdir -p "$DIST_PATH/skills/chronicle-cli"
    cp "$CLI_DIR/skills/chronicle-cli/SKILL.md" "$DIST_PATH/skills/chronicle-cli/"

    # Create install script
    cat > "$DIST_PATH/install.sh" << 'EOF'
#!/bin/bash
# Chronicle CLI Post-Build Installation Script

set -e

INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
OPENCLAW_SKILLS_DIR="${OPENCLAW_SKILLS_DIR:-$HOME/.openclaw/workspace/skills}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Detect if we need sudo
NEED_SUDO=false
if [ ! -w "$INSTALL_DIR" ] && [ "$INSTALL_DIR" = "/usr/local/bin" ]; then
    NEED_SUDO=true
    log_warn "Need sudo access to install to $INSTALL_DIR"
fi

# Install binary
install_binary() {
    log_info "Installing chronicle binary to $INSTALL_DIR..."

    if [ "$NEED_SUDO" = true ]; then
        sudo cp "$SCRIPT_DIR/chronicle" "$INSTALL_DIR/chronicle"
        sudo chmod +x "$INSTALL_DIR/chronicle"
    else
        mkdir -p "$INSTALL_DIR"
        cp "$SCRIPT_DIR/chronicle" "$INSTALL_DIR/chronicle"
        chmod +x "$INSTALL_DIR/chronicle"
    fi

    log_info "Binary installed successfully"
}

# Install skill
install_skill() {
    log_info "Installing OpenClaw skill to $OPENCLAW_SKILLS_DIR..."

    SKILL_DIR="$OPENCLAW_SKILLS_DIR/chronicle-cli"
    mkdir -p "$SKILL_DIR"

    cp "$SCRIPT_DIR/skills/chronicle-cli/SKILL.md" "$SKILL_DIR/"

    log_info "Skill installed to: $SKILL_DIR"
}

# Verify installation
verify_installation() {
    log_info "Verifying installation..."

    if command -v chronicle &> /dev/null; then
        log_info "chronicle found in PATH"
        chronicle --help | head -5
    elif [ -f "$INSTALL_DIR/chronicle" ]; then
        log_warn "chronicle installed but not in PATH"
        log_info "Add to your shell profile: export PATH=\"$INSTALL_DIR:\$PATH\""
        "$INSTALL_DIR/chronicle" --help | head -5
    else
        log_error "Installation verification failed"
        exit 1
    fi

    if [ -f "$OPENCLAW_SKILLS_DIR/chronicle-cli/SKILL.md" ]; then
        log_info "Skill installed successfully"
    else
        log_warn "Skill not found at expected location"
    fi
}

# Main installation
main() {
    log_info "Installing Chronicle CLI..."

    install_binary
    install_skill
    verify_installation

    echo ""
    log_info "Installation complete!"
    echo ""
    echo "Next steps:"
    echo "  1. Run 'chronicle config init' to configure WebDAV sync"
    echo "  2. Run 'chronicle sync bootstrap' to assess initial state"
    echo "  3. Run 'chronicle sync now' to perform initial sync"
    echo ""
    echo "OpenClaw users: The chronicle-cli skill is now available at"
    echo "  $OPENCLAW_SKILLS_DIR/chronicle-cli/"
}

main "$@"
EOF
    chmod +x "$DIST_PATH/install.sh"

    # Create README
    cat > "$DIST_PATH/README.md" << EOF
# Chronicle CLI Distribution

Version: $VERSION
Platform: Linux AMD64

## Contents

- \`chronicle\` - The CLI binary
- \`skills/chronicle-cli/SKILL.md\` - OpenClaw skill documentation
- \`install.sh\` - Installation script

## Quick Install

\`\`\`bash
./install.sh
\`\`\`

## Manual Install

\`\`\`bash
# Install binary
sudo cp chronicle /usr/local/bin/

# Install skill
mkdir -p ~/.openclaw/workspace/skills/chronicle-cli
cp skills/chronicle-cli/SKILL.md ~/.openclaw/workspace/skills/chronicle-cli/
\`\`\`

## Configuration

\`\`\`bash
chronicle config init  # Interactive setup
\`\`\`
EOF

    # Create tarball
    cd "$DIST_DIR"
    tar -czf "${DIST_NAME}.tar.gz" "$DIST_NAME"

    log_info "Distribution created: $DIST_DIR/${DIST_NAME}.tar.gz"
    log_info "Extract and run ./install.sh to install"

    # Return the dist path for the installer
    echo "$DIST_PATH"
}

# Install binary to system
install_binary() {
    log_info "Installing binary to $INSTALL_DIR..."

    if [ ! -w "$INSTALL_DIR" ] && [ ! -d "$INSTALL_DIR" ]; then
        if [ "$INSTALL_DIR" = "/usr/local/bin" ]; then
            log_warn "Need sudo access to install to $INSTALL_DIR"
            sudo cp "$CLI_DIR/chronicle-linux" "$INSTALL_DIR/chronicle"
            sudo chmod +x "$INSTALL_DIR/chronicle"
        else
            mkdir -p "$INSTALL_DIR"
            cp "$CLI_DIR/chronicle-linux" "$INSTALL_DIR/chronicle"
            chmod +x "$INSTALL_DIR/chronicle"
        fi
    else
        cp "$CLI_DIR/chronicle-linux" "$INSTALL_DIR/chronicle"
        chmod +x "$INSTALL_DIR/chronicle"
    fi

    log_info "Binary installed to $INSTALL_DIR/chronicle"
}

# Install skill to OpenClaw
install_skill() {
    log_info "Installing OpenClaw skill to $OPENCLAW_SKILLS_DIR..."

    SKILL_DIR="$OPENCLAW_SKILLS_DIR/chronicle-cli"
    mkdir -p "$SKILL_DIR"

    cp "$CLI_DIR/skills/chronicle-cli/SKILL.md" "$SKILL_DIR/"

    log_info "Skill installed to: $SKILL_DIR/SKILL.md"
}

# Verify installation
verify_installation() {
    log_info "Verifying installation..."

    if [ -f "$INSTALL_DIR/chronicle" ]; then
        log_info "Binary found at $INSTALL_DIR/chronicle"
        "$INSTALL_DIR/chronicle" --help | head -5
    else
        log_error "Binary not found at $INSTALL_DIR/chronicle"
        exit 1
    fi

    if [ -f "$OPENCLAW_SKILLS_DIR/chronicle-cli/SKILL.md" ]; then
        log_info "Skill found at $OPENCLAW_SKILLS_DIR/chronicle-cli/SKILL.md"
    else
        log_warn "Skill not found at expected location"
    fi
}

# Print usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS] [COMMAND]

Chronicle CLI Build and Installation Script

Commands:
    build       Build the linux/amd64 binary only
    dist        Build and create distribution package
    install     Build and install locally (default)
    uninstall   Remove installed binary and skill

Options:
    -h, --help              Show this help message
    --install-dir PATH      Installation directory for binary (default: /usr/local/bin)
    --skills-dir PATH       OpenClaw skills directory (default: ~/.openclaw/workspace/skills)

Examples:
    $0                      Build and install locally
    $0 build                Build only
    $0 dist                 Create distribution package
    $0 install              Same as default
    $0 uninstall            Remove installation
    $0 --install-dir ~/.local/bin install

EOF
}

# Uninstall
uninstall() {
    log_info "Uninstalling Chronicle CLI..."

    if [ -f "$INSTALL_DIR/chronicle" ]; then
        if [ ! -w "$INSTALL_DIR" ]; then
            sudo rm "$INSTALL_DIR/chronicle"
        else
            rm "$INSTALL_DIR/chronicle"
        fi
        log_info "Binary removed from $INSTALL_DIR"
    fi

    if [ -d "$OPENCLAW_SKILLS_DIR/chronicle-cli" ]; then
        rm -rf "$OPENCLAW_SKILLS_DIR/chronicle-cli"
        log_info "Skill removed from $OPENCLAW_SKILLS_DIR"
    fi

    log_info "Uninstallation complete"
}

# Main function
main() {
    COMMAND="install"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            --install-dir)
                INSTALL_DIR="$2"
                shift 2
                ;;
            --skills-dir)
                OPENCLAW_SKILLS_DIR="$2"
                shift 2
                ;;
            build|dist|install|uninstall)
                COMMAND="$1"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    log_info "Chronicle CLI Installer"
    log_info "Install directory: $INSTALL_DIR"
    log_info "Skills directory: $OPENCLAW_SKILLS_DIR"
    echo ""

    case $COMMAND in
        build)
            check_prerequisites
            build_binary
            log_info "Build complete: $CLI_DIR/chronicle-linux"
            ;;
        dist)
            check_prerequisites
            build_binary
            DIST_PATH=$(create_distribution)
            log_info "Distribution ready: $DIST_PATH"
            ;;
        install)
            check_prerequisites
            build_binary
            install_binary
            install_skill
            verify_installation
            echo ""
            log_info "Installation complete!"
            echo ""
            echo "Next steps:"
            echo "  1. Run 'chronicle config init' to configure WebDAV sync"
            echo "  2. Run 'chronicle sync bootstrap' to assess initial state"
            echo "  3. Run 'chronicle sync now' to perform initial sync"
            ;;
        uninstall)
            uninstall
            ;;
    esac
}

main "$@"
