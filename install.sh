#!/bin/bash
# install.sh - Install OpsEngine system-wide
# Usage: ./install.sh [--uninstall] [--local]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Installation paths (XDG-compliant)
INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/opsengine"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opsengine"
BIN_DIR="/usr/local/bin"
LOCAL_BIN_DIR="$HOME/.local/bin"

# Script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Options
UNINSTALL=false
LOCAL_INSTALL=false
COMMAND_NAME="ops"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --uninstall|-u)
            UNINSTALL=true
            shift
            ;;
        --local|-l)
            LOCAL_INSTALL=true
            BIN_DIR="$LOCAL_BIN_DIR"
            shift
            ;;
        --name)
            COMMAND_NAME="$2"
            shift 2
            ;;
        --help|-h)
            cat <<EOF
OpsEngine Installer

Usage: ./install.sh [OPTIONS]

Options:
  --local, -l       Install to ~/.local/bin (no sudo required)
  --uninstall, -u   Remove OpsEngine installation
  --name NAME       Command name (default: ops)
  --help, -h        Show this help

Examples:
  ./install.sh                  # Install globally to /usr/local/bin
  ./install.sh --local          # Install to ~/.local/bin
  ./install.sh --uninstall      # Remove installation
  ./install.sh --name opsengine # Use 'opsengine' instead of 'ops'
EOF
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# =============================================================================
# Uninstall
# =============================================================================

if [[ "$UNINSTALL" == true ]]; then
    echo -e "${CYAN}${BOLD}Uninstalling OpsEngine...${NC}"
    echo ""
    
    # Remove symlink
    if [[ -L "$BIN_DIR/$COMMAND_NAME" ]]; then
        if [[ "$LOCAL_INSTALL" == true ]]; then
            rm -f "$BIN_DIR/$COMMAND_NAME"
        else
            sudo rm -f "$BIN_DIR/$COMMAND_NAME"
        fi
        echo -e "${GREEN}✓${NC} Removed $BIN_DIR/$COMMAND_NAME"
    fi
    
    # Remove installation directory
    if [[ -d "$INSTALL_DIR" ]]; then
        rm -rf "$INSTALL_DIR"
        echo -e "${GREEN}✓${NC} Removed $INSTALL_DIR"
    fi
    
    # Remove shell completions
    if [[ -f "/etc/bash_completion.d/ops" ]]; then
        sudo rm -f "/etc/bash_completion.d/ops"
        echo -e "${GREEN}✓${NC} Removed bash completions"
    fi
    
    if [[ -f "$HOME/.zfunc/_ops" ]]; then
        rm -f "$HOME/.zfunc/_ops"
        echo -e "${GREEN}✓${NC} Removed zsh completions"
    fi
    
    echo ""
    echo -e "${GREEN}${BOLD}OpsEngine uninstalled.${NC}"
    echo -e "${YELLOW}Note: Config files in $CONFIG_DIR were preserved.${NC}"
    exit 0
fi

# =============================================================================
# Install
# =============================================================================

echo -e "${CYAN}"
echo "   ___                 _____             _             "
echo "  / _ \ ___  ___     | ____|_ __   __ _(_)_ __   ___  "
echo " | | | | _ \/ __|    |  _| | '_ \ / _\` | | '_ \ / _ \ "
echo " | |_| | (_) \__ \    | |___| | | | (_| | | | | |  __/ "
echo "  \___/ \___/|___/    |_____|_| |_|\__, |_|_| |_|\___| "
echo "                                   |___/               "
echo -e "${NC}"
echo -e "${BLUE}${BOLD}OpsEngine Installer${NC}"
echo "================================="
echo ""

# Check for required tools
echo -e "${CYAN}Checking requirements...${NC}"

check_cmd() {
    if command -v "$1" &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $1"
        return 0
    else
        echo -e "  ${RED}✗${NC} $1 (optional)"
        return 1
    fi
}

check_cmd bash
check_cmd git || true
check_cmd docker || true
check_cmd curl || true

echo ""

# Create directories
echo -e "${CYAN}Creating directories...${NC}"
mkdir -p "$INSTALL_DIR"
mkdir -p "$CONFIG_DIR"
mkdir -p "$LOCAL_BIN_DIR"
echo -e "  ${GREEN}✓${NC} $INSTALL_DIR"
echo -e "  ${GREEN}✓${NC} $CONFIG_DIR"
echo ""

# Copy files
echo -e "${CYAN}Installing OpsEngine...${NC}"

# Copy all files to installation directory
cp -r "$SCRIPT_DIR"/* "$INSTALL_DIR/"

# Remove install script from installation (not needed after install)
rm -f "$INSTALL_DIR/install.sh"

echo -e "  ${GREEN}✓${NC} Copied to $INSTALL_DIR"

# Create the main 'ops' command wrapper
cat > "$INSTALL_DIR/ops" <<'WRAPPER_EOF'
#!/bin/bash
# OpsEngine - Universal DevOps CLI
# This is the main entry point

# Find installation directory
OPSENGINE_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/opsengine"

if [[ ! -d "$OPSENGINE_HOME" ]]; then
    echo "Error: OpsEngine not found at $OPSENGINE_HOME"
    echo "Please reinstall: https://github.com/user/opsengine"
    exit 1
fi

# Execute main script
exec "$OPSENGINE_HOME/opsengine" "$@"
WRAPPER_EOF

chmod +x "$INSTALL_DIR/ops"
chmod +x "$INSTALL_DIR/opsengine"

# Create symlink in PATH
echo -e "${CYAN}Creating command symlink...${NC}"

if [[ "$LOCAL_INSTALL" == true ]]; then
    ln -sf "$INSTALL_DIR/ops" "$BIN_DIR/$COMMAND_NAME"
    echo -e "  ${GREEN}✓${NC} Created $BIN_DIR/$COMMAND_NAME"
else
    if sudo ln -sf "$INSTALL_DIR/ops" "$BIN_DIR/$COMMAND_NAME" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Created $BIN_DIR/$COMMAND_NAME"
    else
        echo -e "  ${YELLOW}⚠${NC} Could not create /usr/local/bin symlink, using ~/.local/bin"
        BIN_DIR="$LOCAL_BIN_DIR"
        ln -sf "$INSTALL_DIR/ops" "$BIN_DIR/$COMMAND_NAME"
        echo -e "  ${GREEN}✓${NC} Created $BIN_DIR/$COMMAND_NAME"
    fi
fi
echo ""

# Install shell completions
echo -e "${CYAN}Installing shell completions...${NC}"

# Create completions directory in install dir
mkdir -p "$INSTALL_DIR/completions"

# Bash completions
cat > "$INSTALL_DIR/completions/ops.bash" <<'BASH_COMP'
# OpsEngine bash completion

_ops_completions() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]}"
    
    # Main modules
    local modules="cert build deploy network service version"
    local phases="setup configure deploy run resume status reset help"
    local global_cmds="init status resume help version"
    
    case "${COMP_CWORD}" in
        1)
            COMPREPLY=($(compgen -W "$modules $global_cmds --help --version" -- "$cur"))
            ;;
        2)
            case "$prev" in
                cert|build|deploy|network|service|version)
                    COMPREPLY=($(compgen -W "$phases" -- "$cur"))
                    ;;
            esac
            ;;
    esac
}

complete -F _ops_completions ops
BASH_COMP

# Zsh completions
cat > "$INSTALL_DIR/completions/_ops" <<'ZSH_COMP'
#compdef ops

_ops() {
    local -a modules phases global_cmds
    
    modules=(
        'cert:SSL/TLS certificate management'
        'build:Build Docker images'
        'deploy:Deploy services'
        'network:Docker network management'
        'service:Service lifecycle management'
        'version:Version management'
    )
    
    phases=(
        'setup:Check prerequisites'
        'configure:Configure settings'
        'deploy:Execute operation'
        'run:Run all phases'
        'resume:Resume blocked operation'
        'status:Show current state'
        'reset:Reset to initial state'
        'help:Show help'
    )
    
    global_cmds=(
        'init:Initialize project'
        'status:Show all module states'
        'resume:Resume blocked modules'
        'help:Show help'
        'version:Show version'
    )
    
    case "${#words[@]}" in
        2)
            _describe 'module' modules
            _describe 'command' global_cmds
            ;;
        3)
            case "${words[2]}" in
                cert|build|deploy|network|service|version)
                    _describe 'phase' phases
                    ;;
            esac
            ;;
    esac
}

_ops "$@"
ZSH_COMP

# Try to install system-wide bash completions
if [[ -d "/etc/bash_completion.d" ]] && [[ "$LOCAL_INSTALL" == false ]]; then
    if sudo cp "$INSTALL_DIR/completions/ops.bash" "/etc/bash_completion.d/ops" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Installed system bash completions"
    fi
fi

# Install user-level zsh completions
mkdir -p "$HOME/.zfunc"
cp "$INSTALL_DIR/completions/_ops" "$HOME/.zfunc/_ops"
echo -e "  ${GREEN}✓${NC} Installed zsh completions to ~/.zfunc"

echo ""

# Create default global config if not exists
if [[ ! -f "$CONFIG_DIR/config.yaml" ]]; then
    echo -e "${CYAN}Creating default configuration...${NC}"
    cat > "$CONFIG_DIR/config.yaml" <<CONFIG_EOF
# OpsEngine Global Configuration
# User preferences and defaults

# Default values for new projects
defaults:
  docker_registry: dockerhub
  editor: \${EDITOR:-nano}
  log_level: info
  
# UI preferences
ui:
  colors: true
  unicode: true
  
# Module defaults
modules:
  cert:
    email: ""
    staging: false
  build:
    push: true
    no_cache: false
CONFIG_EOF
    echo -e "  ${GREEN}✓${NC} Created $CONFIG_DIR/config.yaml"
    echo ""
fi

# Check PATH
echo -e "${CYAN}Checking PATH...${NC}"
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    echo -e "  ${YELLOW}⚠${NC} $BIN_DIR is not in your PATH"
    echo ""
    echo -e "  Add this to your shell profile (~/.bashrc or ~/.zshrc):"
    echo -e "  ${CYAN}export PATH=\"\$PATH:$BIN_DIR\"${NC}"
    echo ""
else
    echo -e "  ${GREEN}✓${NC} $BIN_DIR is in PATH"
fi

# Zsh fpath notice
if [[ -n "$ZSH_VERSION" ]] || [[ "$SHELL" == *"zsh"* ]]; then
    echo ""
    echo -e "${CYAN}For zsh completions, add to ~/.zshrc:${NC}"
    echo -e "  ${CYAN}fpath=(~/.zfunc \$fpath)${NC}"
    echo -e "  ${CYAN}autoload -Uz compinit && compinit${NC}"
fi

echo ""
echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  ✅ OpsEngine installed successfully!${NC}"
echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Get started:"
echo -e "    ${CYAN}$COMMAND_NAME --help${NC}          Show help"
echo -e "    ${CYAN}$COMMAND_NAME init${NC}            Initialize a project"
echo -e "    ${CYAN}$COMMAND_NAME cert run${NC}        Run SSL certificate setup"
echo ""
echo -e "  Documentation:"
echo -e "    ${BLUE}$INSTALL_DIR/GUIDES.md${NC}"
echo ""
