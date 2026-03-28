#!/bin/bash
#
# Chronicle CLI Package Script
# Builds and packages the CLI for distribution to Linux AMD64 servers
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI_DIR="$SCRIPT_DIR"
DIST_DIR="$CLI_DIR/dist"

# Version (use date if not specified)
VERSION="${VERSION:-$(date +"%Y.%m.%d")}"
DIST_NAME="chronicle-cli-${VERSION}-linux-amd64"
DIST_PATH="$DIST_DIR/$DIST_NAME"

log_info "Chronicle CLI Package Script"
log_info "Version: $VERSION"
log_info "Target: linux/amd64"
echo ""

# Clean previous builds
clean_builds() {
    log_step "Cleaning previous builds..."
    rm -f "$CLI_DIR/chronicle"
    rm -f "$CLI_DIR/chronicle-linux"
    rm -rf "$DIST_PATH"
    log_info "Clean complete"
}

# Check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites..."

    if ! command -v go &> /dev/null; then
        log_error "Go is not installed. Please install Go 1.21 or later."
        exit 1
    fi

    GO_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
    log_info "Found Go version: $GO_VERSION"

    # Check for required files
    if [ ! -f "$CLI_DIR/go.mod" ]; then
        log_error "go.mod not found. Are you in the right directory?"
        exit 1
    fi

    if [ ! -f "$CLI_DIR/skills/chronicle-cli/SKILL.md" ]; then
        log_error "SKILL.md not found at expected location"
        exit 1
    fi

    log_info "Prerequisites check passed"
}

# Download dependencies
download_deps() {
    log_step "Downloading dependencies..."
    cd "$CLI_DIR"
    go mod tidy
    go mod download
    log_info "Dependencies ready"
}

# Build the binary
build_binary() {
    log_step "Building binary for linux/amd64..."
    cd "$CLI_DIR"

    # Build with optimizations
    GOOS=linux GOARCH=amd64 go build \
        -ldflags="-s -w -X main.version=$VERSION" \
        -o chronicle-linux

    if [ ! -f "$CLI_DIR/chronicle-linux" ]; then
        log_error "Build failed - binary not found"
        exit 1
    fi

    BINARY_SIZE=$(ls -lh "$CLI_DIR/chronicle-linux" | awk '{print $5}')
    log_info "Build successful: chronicle-linux ($BINARY_SIZE)"
}

# Run tests if available
run_tests() {
    log_step "Running tests..."
    cd "$CLI_DIR"

    if go test ./... 2>/dev/null; then
        log_info "All tests passed"
    else
        log_warn "No tests found or tests failed (continuing anyway)"
    fi
}

# Create distribution package
create_package() {
    log_step "Creating distribution package..."

    mkdir -p "$DIST_PATH"

    # Copy binary
    cp "$CLI_DIR/chronicle-linux" "$DIST_PATH/chronicle"
    chmod +x "$DIST_PATH/chronicle"

    # Copy skill
    mkdir -p "$DIST_PATH/skills/chronicle-cli"
    cp "$CLI_DIR/skills/chronicle-cli/SKILL.md" "$DIST_PATH/skills/chronicle-cli/"

    # Create install script
    cat > "$DIST_PATH/install.sh" << 'INSTALL_SCRIPT'
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
INSTALL_SCRIPT
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

## Uninstall

\`\`\`bash
sudo rm /usr/local/bin/chronicle
rm -rf ~/.openclaw/workspace/skills/chronicle-cli
\`\`\`
EOF

    # Create tarball
    cd "$DIST_DIR"
    tar -czf "${DIST_NAME}.tar.gz" "$DIST_NAME"

    # Create checksum
    if command -v sha256sum &> /dev/null; then
        sha256sum "${DIST_NAME}.tar.gz" > "${DIST_NAME}.tar.gz.sha256"
    elif command -v shasum &> /dev/null; then
        shasum -a 256 "${DIST_NAME}.tar.gz" > "${DIST_NAME}.tar.gz.sha256"
    fi

    log_info "Package created: $DIST_DIR/${DIST_NAME}.tar.gz"
}

# Print summary
print_summary() {
    echo ""
    log_info "Packaging complete!"
    echo ""
    echo "Distribution files:"
    echo "  - $DIST_DIR/${DIST_NAME}.tar.gz"
    if [ -f "$DIST_DIR/${DIST_NAME}.tar.gz.sha256" ]; then
        echo "  - $DIST_DIR/${DIST_NAME}.tar.gz.sha256"
    fi
    echo ""
    echo "To install on server:"
    echo "  1. Copy $DIST_NAME.tar.gz to server"
    echo "  2. tar -xzf $DIST_NAME.tar.gz"
    echo "  3. cd $DIST_NAME"
    echo "  4. ./install.sh"
    echo ""
    echo "Or use the full install.sh which can also build from source:"
    echo "  ./install.sh dist  # Creates distribution"
    echo "  ./install.sh install  # Builds and installs locally"
}

# Main function
main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Package Chronicle CLI for Linux AMD64 distribution"
                echo ""
                echo "Options:"
                echo "  -h, --help     Show this help message"
                echo "  --version      Set version (default: date-based)"
                echo "  --skip-tests   Skip running tests"
                echo ""
                echo "Environment variables:"
                echo "  VERSION        Package version"
                exit 0
                ;;
            --version)
                VERSION="$2"
                DIST_NAME="chronicle-cli-${VERSION}-linux-amd64"
                DIST_PATH="$DIST_DIR/$DIST_NAME"
                shift 2
                ;;
            --skip-tests)
                SKIP_TESTS=1
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    # Run packaging steps
    clean_builds
    check_prerequisites
    download_deps
    build_binary

    if [ -z "$SKIP_TESTS" ]; then
        run_tests
    fi

    create_package
    print_summary
}

main "$@"
