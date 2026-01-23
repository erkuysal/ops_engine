#!/bin/bash
# core/utils.sh - Shared utility functions for OpsEngine

# Colors (reusable across all scripts)
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export CYAN='\033[0;36m'
export MAGENTA='\033[0;35m'
export BOLD='\033[1m'
export NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1" >&2
}

log_step() {
    echo -e "${CYAN}▶${NC} $1"
}

# Banner display
show_opsengine_banner() {
    clear
    echo -e "${CYAN}"
    echo "   ___                 _____             _             "
    echo "  / _ \\ ___  ___     | ____|_ __   __ _(_)_ __   ___  "
    echo " | | | | _ \\/ __|    |  _| | '_ \\ / _\` | | '_ \\ / _ \\ "
    echo " | |_| | (_) \\__ \\    | |___| | | | (_| | | | | |  __/ "
    echo "  \\___/ \\___/|___/    |_____|_| |_|\\__, |_|_| |_|\\___| "
    echo "                                   |___/               "
    echo -e "${NC}"
    echo -e "${BLUE}  Universal DevOps Toolkit${NC}"
    echo "================================="
}

# Check if command exists
command_exists() {
    command -v "$1" &>/dev/null
}

# Check if running with required privileges
check_sudo() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This operation requires sudo privileges"
        return 1
    fi
    return 0
}

# Detect OS
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
        echo "windows"
    else
        echo "unknown"
    fi
}

# Get compose command (docker compose vs docker-compose)
get_compose_command() {
    if command_exists docker && docker compose version &>/dev/null; then
        echo "docker compose"
    elif command_exists docker-compose; then
        echo "docker-compose"
    else
        echo ""
    fi
}

# Check if docker is available
check_docker() {
    if ! command_exists docker; then
        log_error "Docker is not installed"
        return 1
    fi
    
    if ! docker info &>/dev/null; then
        log_error "Docker daemon is not running"
        return 1
    fi
    
    return 0
}

# Parse docker-compose.yml for services
parse_compose_services() {
    local compose_file="${1:-docker-compose.yml}"
    
    if [ ! -f "$compose_file" ]; then
        return 1
    fi
    
    # Extract service names (simple grep approach)
    grep -E "^  [a-zA-Z0-9_-]+:" "$compose_file" | sed 's/://g' | sed 's/^  //g' | tr '\n' ',' | sed 's/,$//'
}

# Confirm action
confirm() {
    local prompt="${1:-Are you sure?}"
    local default="${2:-n}"
    
    if [ "$default" = "y" ] || [ "$default" = "Y" ]; then
        read -p "$prompt [Y/n]: " response
        response=${response:-y}
    else
        read -p "$prompt [y/N]: " response
        response=${response:-n}
    fi
    
    case "$response" in
        [yY][eE][sS]|[yY]) 
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Read input with default value
read_with_default() {
    local prompt="$1"
    local default="$2"
    local varname="$3"
    
    if [ -n "$default" ]; then
        read -p "$prompt [$default]: " value
        value=${value:-$default}
    else
        read -p "$prompt: " value
    fi
    
    eval "$varname='$value'"
}

# Create directory if it doesn't exist
ensure_dir() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        log_success "Created directory: $dir"
    fi
}

# Backup file
backup_file() {
    local file="$1"
    if [ -f "$file" ]; then
        local backup="${file}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$file" "$backup"
        log_info "Backed up to: $backup"
    fi
}

# Check if file exists and is not empty
file_not_empty() {
    [ -f "$1" ] && [ -s "$1" ]
}

# Trim whitespace
trim() {
    echo "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# Convert to uppercase
to_upper() {
    echo "$1" | tr '[:lower:]' '[:upper:]'
}

# Convert to lowercase
to_lower() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

# Get timestamp
timestamp() {
    date +"%Y-%m-%d_%H-%M-%S"
}

# Wait for user input
pause() {
    local message="${1:-Press Enter to continue...}"
    read -p "$message" -r
}

# Display a progress spinner
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while ps -p $pid > /dev/null 2>&1; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Check if value is in array
in_array() {
    local needle="$1"
    shift
    local item
    for item in "$@"; do
        if [ "$item" = "$needle" ]; then
            return 0
        fi
    done
    return 1
}

# Export functions
export -f log_info log_success log_warning log_error log_step
export -f show_opsengine_banner command_exists check_sudo detect_os
export -f get_compose_command check_docker parse_compose_services
export -f confirm read_with_default ensure_dir backup_file file_not_empty
export -f trim to_upper to_lower timestamp pause spinner in_array

# =============================================================================
# Phase-Aware UI Helpers (for three-phase module system)
# =============================================================================

# Display a phase header
# Usage: phase_header "SETUP" "SSL Certificate Module"
phase_header() {
    local phase="$1"
    local module="${2:-}"
    
    local phase_icon=""
    local phase_color=""
    
    case "$phase" in
        setup|SETUP)
            phase_icon="🔧"
            phase_color="$CYAN"
            phase="SETUP"
            ;;
        configure|CONFIGURE)
            phase_icon="⚙️"
            phase_color="$YELLOW"
            phase="CONFIGURE"
            ;;
        deploy|DEPLOY)
            phase_icon="🚀"
            phase_color="$GREEN"
            phase="DEPLOY"
            ;;
        complete|COMPLETE)
            phase_icon="✅"
            phase_color="$GREEN"
            phase="COMPLETE"
            ;;
        *)
            phase_icon="▶"
            phase_color="$BLUE"
            ;;
    esac
    
    echo ""
    echo -e "${phase_color}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${phase_color}║  ${phase_icon}  ${BOLD}${phase}${NC}${phase_color}$(printf '%*s' $((53 - ${#phase})) '')║${NC}"
    if [[ -n "$module" ]]; then
        echo -e "${phase_color}║     ${NC}${module}$(printf '%*s' $((55 - ${#module})) '')${phase_color}║${NC}"
    fi
    echo -e "${phase_color}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Display step progress
# Usage: step_progress 2 5 "Checking nginx installation"
step_progress() {
    local current="$1"
    local total="$2"
    local message="$3"
    
    local bar_width=30
    local filled=$((current * bar_width / total))
    local empty=$((bar_width - filled))
    
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    
    echo -e "${CYAN}[${current}/${total}]${NC} ${bar} ${message}"
}

# Display a guidance box for manual steps
# Usage: guidance_box "Title" "Instructions" "Resume command"
guidance_box() {
    local title="$1"
    local instructions="$2"
    local resume_cmd="${3:-}"
    
    echo ""
    echo -e "${YELLOW}┌──────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${YELLOW}│  ⚠️   ${BOLD}${title}${NC}${YELLOW}$(printf '%*s' $((46 - ${#title})) '')│${NC}"
    echo -e "${YELLOW}├──────────────────────────────────────────────────────────────┤${NC}"
    
    # Print instructions line by line
    while IFS= read -r line; do
        local visible_len=${#line}
        if [[ $visible_len -gt 60 ]]; then
            line="${line:0:57}..."
            visible_len=60
        fi
        echo -e "${YELLOW}│${NC}  ${line}$(printf '%*s' $((60 - visible_len)) '')${YELLOW}│${NC}"
    done <<< "$(echo -e "$instructions")"
    
    if [[ -n "$resume_cmd" ]]; then
        echo -e "${YELLOW}├──────────────────────────────────────────────────────────────┤${NC}"
        echo -e "${YELLOW}│${NC}  ${GREEN}When done, run:${NC}$(printf '%*s' 44 '')${YELLOW}│${NC}"
        echo -e "${YELLOW}│${NC}  ${CYAN}${resume_cmd}${NC}$(printf '%*s' $((60 - ${#resume_cmd})) '')${YELLOW}│${NC}"
    fi
    
    echo -e "${YELLOW}└──────────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

# Display a success box
# Usage: success_box "Operation completed!" "Details here"
success_box() {
    local title="$1"
    local details="${2:-}"
    
    echo ""
    echo -e "${GREEN}┌──────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${GREEN}│  ✅  ${BOLD}${title}${NC}${GREEN}$(printf '%*s' $((46 - ${#title})) '')│${NC}"
    
    if [[ -n "$details" ]]; then
        echo -e "${GREEN}├──────────────────────────────────────────────────────────────┤${NC}"
        while IFS= read -r line; do
            local visible_len=${#line}
            if [[ $visible_len -gt 60 ]]; then
                line="${line:0:57}..."
                visible_len=60
            fi
            echo -e "${GREEN}│${NC}  ${line}$(printf '%*s' $((60 - visible_len)) '')${GREEN}│${NC}"
        done <<< "$(echo -e "$details")"
    fi
    
    echo -e "${GREEN}└──────────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

# Display an info box
# Usage: info_box "Title" "Content"
info_box() {
    local title="$1"
    local content="${2:-}"
    
    echo ""
    echo -e "${BLUE}┌──────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│  ℹ️   ${BOLD}${title}${NC}${BLUE}$(printf '%*s' $((46 - ${#title})) '')│${NC}"
    
    if [[ -n "$content" ]]; then
        echo -e "${BLUE}├──────────────────────────────────────────────────────────────┤${NC}"
        while IFS= read -r line; do
            local visible_len=${#line}
            if [[ $visible_len -gt 60 ]]; then
                line="${line:0:57}..."
                visible_len=60
            fi
            echo -e "${BLUE}│${NC}  ${line}$(printf '%*s' $((60 - visible_len)) '')${BLUE}│${NC}"
        done <<< "$(echo -e "$content")"
    fi
    
    echo -e "${BLUE}└──────────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

# Export new UI functions
export -f phase_header step_progress guidance_box success_box info_box
