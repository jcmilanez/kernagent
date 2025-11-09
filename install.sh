#!/usr/bin/env bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Configuration
IMAGE_NAME="kernagent"
INSTALL_DIR="/usr/local/bin"
WRAPPER_NAME="kernagent"
DOCKER_REGISTRY="ghcr.io/karib0u"  # GitHub Container Registry

# Interactive menu function with arrow key navigation
select_option() {
    local prompt="$1"
    shift
    local options=("$@")
    local selected=0
    local num_options=${#options[@]}

    # Hide cursor
    tput civis

    # Function to draw menu
    draw_menu() {
        echo -e "${BOLD}${prompt}${NC}"
        echo ""
        for i in "${!options[@]}"; do
            if [ $i -eq $selected ]; then
                echo -e "  ${GREEN}▶ ${options[$i]}${NC}"
            else
                echo -e "    ${options[$i]}"
            fi
        done
    }

    # Draw initial menu
    draw_menu

    # Read arrow keys
    while true; do
        read -rsn1 key

        # Handle multi-byte sequences (arrow keys)
        if [[ $key == $'\x1b' ]]; then
            read -rsn2 key
        fi

        case "$key" in
            '[A') # Up arrow
                ((selected--))
                if [ $selected -lt 0 ]; then
                    selected=$((num_options - 1))
                fi
                ;;
            '[B') # Down arrow
                ((selected++))
                if [ $selected -ge $num_options ]; then
                    selected=0
                fi
                ;;
            '') # Enter key
                break
                ;;
        esac

        # Clear previous menu and redraw
        for ((i=0; i<num_options+2; i++)); do
            tput cuu1
            tput el
        done
        draw_menu
    done

    # Show cursor again
    tput cnorm

    # Clear menu
    for ((i=0; i<num_options+2; i++)); do
        tput cuu1
        tput el
    done

    # Return selected index
    echo "$selected"
}

# Function to confirm or modify installation directory
confirm_install_dir() {
    echo ""
    echo -e "${CYAN}Installation Directory Configuration${NC}"
    echo -e "Default installation directory: ${BOLD}${INSTALL_DIR}${NC}"
    echo ""

    local options=("Use default (${INSTALL_DIR})" "Choose a different directory")
    local choice=$(select_option "Select installation directory option:" "${options[@]}")

    if [ "$choice" -eq 1 ]; then
        echo ""
        echo -e "${YELLOW}Enter custom installation directory:${NC}"
        read -e -p "> " custom_dir

        # Expand tilde
        custom_dir="${custom_dir/#\~/$HOME}"

        # Validate and create if needed
        if [ ! -d "$custom_dir" ]; then
            echo -e "${YELLOW}Directory does not exist. Create it? (y/n)${NC}"
            read -r response
            if [[ "$response" =~ ^[Yy]$ ]]; then
                mkdir -p "$custom_dir" || {
                    echo -e "${RED}✗ Failed to create directory${NC}"
                    exit 1
                }
                echo -e "${GREEN}✓ Directory created${NC}"
            else
                echo -e "${RED}✗ Installation cancelled${NC}"
                exit 1
            fi
        fi

        INSTALL_DIR="$custom_dir"
    fi

    echo -e "${GREEN}✓ Installation directory: ${INSTALL_DIR}${NC}"
    echo ""
}

# Function to configure LLM provider
configure_provider() {
    echo ""
    echo -e "${CYAN}LLM Provider Configuration${NC}"
    echo ""

    local providers=("OpenAI (GPT-4, GPT-3.5)" "Google (Gemini)" "Anthropic (Claude)" "Local (LM Studio, Ollama, etc.)" "Custom (Other provider)")
    local provider_choice=$(select_option "Select your LLM provider:" "${providers[@]}")

    local provider_name=""
    local base_url=""
    local api_key=""
    local model=""

    case $provider_choice in
        0) # OpenAI
            provider_name="OpenAI"
            base_url="https://api.openai.com/v1"
            echo -e "${GREEN}✓ Selected: OpenAI${NC}"
            echo ""
            echo -e "${YELLOW}Enter your OpenAI API key:${NC}"
            echo -e "${CYAN}(Get your key from: https://platform.openai.com/api-keys)${NC}"
            read -p "> " api_key
            echo ""
            echo -e "${YELLOW}Enter the model name:${NC}"
            echo -e "${CYAN}(Examples: gpt-4o, gpt-4-turbo, gpt-3.5-turbo)${NC}"
            read -p "> " model
            ;;
        1) # Google
            provider_name="Google"
            base_url="https://generativelanguage.googleapis.com/v1beta/openai/"
            echo -e "${GREEN}✓ Selected: Google (Gemini)${NC}"
            echo ""
            echo -e "${YELLOW}Enter your Google AI API key:${NC}"
            echo -e "${CYAN}(Get your key from: https://aistudio.google.com/app/apikey)${NC}"
            read -p "> " api_key
            echo ""
            echo -e "${YELLOW}Enter the model name:${NC}"
            echo -e "${CYAN}(Examples: gemini-1.5-pro, gemini-1.5-flash, gemini-2.0-flash-exp)${NC}"
            read -p "> " model
            ;;
        2) # Anthropic
            provider_name="Anthropic"
            base_url="https://api.anthropic.com/v1"
            echo -e "${GREEN}✓ Selected: Anthropic (Claude)${NC}"
            echo ""
            echo -e "${YELLOW}Enter your Anthropic API key:${NC}"
            echo -e "${CYAN}(Get your key from: https://console.anthropic.com/settings/keys)${NC}"
            read -p "> " api_key
            echo ""
            echo -e "${YELLOW}Enter the model name:${NC}"
            echo -e "${CYAN}(Examples: claude-3-5-sonnet-20241022, claude-3-opus-20240229)${NC}"
            read -p "> " model
            ;;
        3) # Local
            provider_name="Local"
            echo -e "${GREEN}✓ Selected: Local LLM${NC}"
            echo ""
            echo -e "${CYAN}${BOLD}Important:${NC}${CYAN} Since kernagent runs in a Docker container, you need to use${NC}"
            echo -e "${CYAN}a special URL to connect to services on your host machine.${NC}"
            echo ""
            echo -e "${YELLOW}Enter the base URL for your local LLM:${NC}"
            echo -e "${CYAN}Default: http://host.docker.internal:1234/v1${NC}"
            echo -e "${CYAN}(Press Enter to use default, or type your custom URL)${NC}"
            read -p "> " custom_url

            if [ -z "$custom_url" ]; then
                base_url="http://host.docker.internal:1234/v1"
            else
                base_url="$custom_url"
            fi

            echo ""
            echo -e "${YELLOW}Enter API key (optional, press Enter to skip):${NC}"
            echo -e "${CYAN}(Most local LLMs don't require an API key)${NC}"
            read -p "> " api_key

            if [ -z "$api_key" ]; then
                api_key="not-needed"
            fi

            echo ""
            echo -e "${YELLOW}Enter the model name:${NC}"
            echo -e "${CYAN}(Use the exact name from your local LLM server)${NC}"
            echo -e "${CYAN}(Examples: llama-3.2-3b-instruct, qwen2.5-coder:7b)${NC}"
            read -p "> " model
            ;;
        4) # Custom
            provider_name="Custom"
            echo -e "${GREEN}✓ Selected: Custom Provider${NC}"
            echo ""
            echo -e "${YELLOW}Enter the base URL (OpenAI-compatible endpoint):${NC}"
            echo -e "${CYAN}(Must support /v1/chat/completions endpoint)${NC}"
            read -p "> " base_url
            echo ""
            echo -e "${YELLOW}Enter your API key:${NC}"
            read -p "> " api_key
            echo ""
            echo -e "${YELLOW}Enter the model name:${NC}"
            read -p "> " model
            ;;
    esac

    # Create .env file
    echo ""
    echo -e "${BLUE}Creating configuration file...${NC}"
    cat > .env << ENV_EOF
# LLM Provider Configuration
# Provider: ${provider_name}
OPENAI_API_KEY=${api_key}
OPENAI_BASE_URL=${base_url}
OPENAI_MODEL=${model}

# Debug mode (set to "true" to enable verbose logging)
DEBUG=false
ENV_EOF

    echo -e "${GREEN}✓ Configuration saved to .env${NC}"
    echo ""
    echo -e "${CYAN}Configuration Summary:${NC}"
    echo -e "  Provider:  ${BOLD}${provider_name}${NC}"
    echo -e "  Base URL:  ${base_url}"
    echo -e "  Model:     ${model}"
    echo ""
}

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║    kernagent Installation Script      ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Check if we're in the kernagent repository
REPO_URL="https://github.com/Karib0u/kernagent.git"
TEMP_DIR=""

if [ ! -f "Dockerfile" ] || [ ! -f "docker-compose.yml" ]; then
    echo -e "${YELLOW}⚠ Not in kernagent repository, cloning...${NC}"
    TEMP_DIR=$(mktemp -d)
    echo "Cloning kernagent to ${TEMP_DIR}..."

    if ! command -v git &> /dev/null; then
        echo -e "${RED}✗ Git is not installed!${NC}"
        echo "Please install git or clone the repository manually:"
        echo "  git clone ${REPO_URL}"
        echo "  cd kernagent"
        echo "  bash install.sh"
        exit 1
    fi

    git clone "${REPO_URL}" "${TEMP_DIR}" || {
        echo -e "${RED}✗ Failed to clone repository${NC}"
        exit 1
    }

    cd "${TEMP_DIR}" || {
        echo -e "${RED}✗ Failed to enter repository directory${NC}"
        exit 1
    }
    echo -e "${GREEN}✓ Repository cloned${NC}"
fi

# Check if Docker is installed
echo -e "${BLUE}[1/6]${NC} Checking for Docker..."
if ! command -v docker &> /dev/null; then
    echo -e "${RED}✗ Docker is not installed!${NC}"
    echo "Please install Docker first: https://docs.docker.com/get-docker/"
    exit 1
fi
echo -e "${GREEN}✓ Docker found${NC}"

# Check if Docker daemon is running
echo -e "${BLUE}[2/7]${NC} Checking Docker daemon..."
if ! docker info &> /dev/null; then
    echo -e "${RED}✗ Docker daemon is not running!${NC}"
    echo "Please start Docker and try again."
    exit 1
fi
echo -e "${GREEN}✓ Docker daemon running${NC}"

# Interactive installation directory selection
confirm_install_dir

# Build or pull the Docker image
echo -e "${BLUE}[3/7]${NC} Setting up Docker image..."
PULLED_FROM_REGISTRY=false

if [ -n "$DOCKER_REGISTRY" ]; then
    echo "Pulling pre-built image from registry..."
    if docker pull "${DOCKER_REGISTRY}/${IMAGE_NAME}:latest"; then
        # Successfully pulled from registry, tag it with local name
        docker tag "${DOCKER_REGISTRY}/${IMAGE_NAME}:latest" "${IMAGE_NAME}:latest"
        PULLED_FROM_REGISTRY=true
    else
        # Pull failed, build locally instead
        echo -e "${YELLOW}⚠ Pull failed, building locally instead...${NC}"
        docker build -t "${IMAGE_NAME}:latest" .
    fi
else
    echo "Building Docker image (this may take several minutes)..."
    docker build -t "${IMAGE_NAME}:latest" .
fi

echo -e "${GREEN}✓ Docker image ready${NC}"

# Create CLI wrapper script
echo -e "${BLUE}[4/7]${NC} Creating CLI wrapper..."
WRAPPER_SCRIPT=$(cat << 'WRAPPER_EOF'
#!/usr/bin/env bash

# kernagent - Docker-based binary analysis CLI
# This wrapper transparently runs kernagent in a Docker container

set -e

IMAGE_NAME="kernagent"
DOCKER_REGISTRY="ghcr.io/karib0u"  # GitHub Container Registry

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check if Docker is running
if ! docker info &> /dev/null 2>&1; then
    echo -e "${RED}Error: Docker daemon is not running${NC}" >&2
    echo "Please start Docker and try again." >&2
    exit 1
fi

# Parse arguments to find binary path
BINARY_PATH=""
DOCKER_ARGS=()
KERNAGENT_ARGS=()

# Collect environment variables
ENV_ARGS=()
if [ -n "$OPENAI_API_KEY" ]; then
    ENV_ARGS+=("-e" "OPENAI_API_KEY=$OPENAI_API_KEY")
fi
if [ -n "$OPENAI_BASE_URL" ]; then
    ENV_ARGS+=("-e" "OPENAI_BASE_URL=$OPENAI_BASE_URL")
fi
if [ -n "$OPENAI_MODEL" ]; then
    ENV_ARGS+=("-e" "OPENAI_MODEL=$OPENAI_MODEL")
fi

# Load .env file if it exists in current directory
if [ -f .env ]; then
    ENV_ARGS+=("--env-file" ".env")
fi

# Parse arguments
for arg in "$@"; do
    # Check if this looks like a file path
    if [ -f "$arg" ] || [[ "$arg" == *.exe ]] || [[ "$arg" == *.bin ]] || [[ "$arg" == *.dll ]] || [[ "$arg" == *.so ]] || [[ "$arg" == *.elf ]]; then
        BINARY_PATH="$arg"
    fi
    KERNAGENT_ARGS+=("$arg")
done

# Determine volume mount strategy
if [ -n "$BINARY_PATH" ]; then
    # Get absolute path of the binary
    BINARY_ABS=$(cd "$(dirname "$BINARY_PATH")" && pwd)/$(basename "$BINARY_PATH")
    BINARY_DIR=$(dirname "$BINARY_ABS")
    BINARY_NAME=$(basename "$BINARY_ABS")

    # Mount the directory containing the binary
    VOLUME_ARGS=("-v" "${BINARY_DIR}:/data")

    # Replace the binary path in arguments with /data/filename
    NEW_ARGS=()
    for arg in "${KERNAGENT_ARGS[@]}"; do
        if [ "$arg" == "$BINARY_PATH" ]; then
            NEW_ARGS+=("/data/${BINARY_NAME}")
        else
            NEW_ARGS+=("$arg")
        fi
    done
    KERNAGENT_ARGS=("${NEW_ARGS[@]}")
else
    # No binary path detected, mount current directory
    VOLUME_ARGS=("-v" "$(pwd):/data")
fi

# Check if image exists locally, otherwise try to pull from registry
if ! docker image inspect "${IMAGE_NAME}" &> /dev/null; then
    if [ -n "$DOCKER_REGISTRY" ]; then
        echo -e "${YELLOW}Local image not found, attempting to pull from ${DOCKER_REGISTRY}...${NC}" >&2
        if docker pull "${DOCKER_REGISTRY}/${IMAGE_NAME}:latest" &> /dev/null; then
            docker tag "${DOCKER_REGISTRY}/${IMAGE_NAME}:latest" "${IMAGE_NAME}"
        else
            echo -e "${RED}Failed to pull image from registry${NC}" >&2
            echo "Run the install script again or build manually with: docker build -t ${IMAGE_NAME} ." >&2
            exit 1
        fi
    else
        echo -e "${YELLOW}Warning: kernagent Docker image not found${NC}" >&2
        echo "Run the install script again or build manually with: docker build -t ${IMAGE_NAME} ." >&2
        exit 1
    fi
fi

# Run the Docker container
exec docker run --rm \
    "${VOLUME_ARGS[@]}" \
    "${ENV_ARGS[@]}" \
    "${IMAGE_NAME}" \
    "${KERNAGENT_ARGS[@]}"
WRAPPER_EOF
)

# Write wrapper to temp file
TMP_WRAPPER="/tmp/${WRAPPER_NAME}-$$"
echo "$WRAPPER_SCRIPT" > "$TMP_WRAPPER"
chmod +x "$TMP_WRAPPER"
echo -e "${GREEN}✓ CLI wrapper created${NC}"

# Install wrapper
echo -e "${BLUE}[5/7]${NC} Installing to ${INSTALL_DIR}/${WRAPPER_NAME}..."
if [ -w "$INSTALL_DIR" ]; then
    mv "$TMP_WRAPPER" "${INSTALL_DIR}/${WRAPPER_NAME}"
else
    echo "Need sudo permission to install to ${INSTALL_DIR}..."
    sudo mv "$TMP_WRAPPER" "${INSTALL_DIR}/${WRAPPER_NAME}"
    sudo chmod +x "${INSTALL_DIR}/${WRAPPER_NAME}"
fi
echo -e "${GREEN}✓ Installed to ${INSTALL_DIR}/${WRAPPER_NAME}${NC}"

# Setup configuration
echo -e "${BLUE}[6/7]${NC} LLM Configuration..."
if [ ! -f .env ]; then
    configure_provider
else
    echo ""
    echo -e "${YELLOW}Existing .env file found. Would you like to reconfigure? (y/N)${NC}"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        configure_provider
    else
        echo -e "${GREEN}✓ Using existing configuration${NC}"
    fi
fi

# Final verification
echo -e "${BLUE}[7/7]${NC} Verifying installation..."
if command -v "${WRAPPER_NAME}" &> /dev/null || [ -x "${INSTALL_DIR}/${WRAPPER_NAME}" ]; then
    echo -e "${GREEN}✓ kernagent is ready to use${NC}"
else
    echo -e "${YELLOW}⚠ Note: You may need to add ${INSTALL_DIR} to your PATH${NC}"
    echo -e "${YELLOW}  Add this to your ~/.bashrc or ~/.zshrc:${NC}"
    echo -e "${YELLOW}  export PATH=\"${INSTALL_DIR}:\$PATH\"${NC}"
fi

# Success message
echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Installation completed successfully!  ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}${BOLD}Installation Summary:${NC}"
echo -e "  Installed to:  ${BOLD}${INSTALL_DIR}/${WRAPPER_NAME}${NC}"
if [ -f .env ]; then
    echo -e "  Configuration: ${BOLD}.env file created${NC}"
fi
echo ""
echo -e "${CYAN}${BOLD}Quick Start:${NC}"
echo "  ${WRAPPER_NAME} --help"
echo "  ${WRAPPER_NAME} summary /path/to/binary.exe"
echo "  ${WRAPPER_NAME} ask /path/to/binary.exe \"What does this do?\""
echo "  ${WRAPPER_NAME} oneshot /path/to/sample.bin"
echo ""
echo -e "${CYAN}${BOLD}How it works:${NC}"
echo "  • Runs in a Docker container with Ghidra pre-installed"
echo "  • Automatically mounts directories containing your binaries"
echo "  • Loads configuration from .env files in your working directory"
echo "  • Connects to your configured LLM provider"
echo ""
echo -e "${YELLOW}Tip: You can place a .env file in any directory where you work with binaries${NC}"

# Cleanup temporary directory if created
if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
    echo ""
    echo "Cleaning up temporary files..."
    cd /
    rm -rf "$TEMP_DIR"
fi
