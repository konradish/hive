#!/bin/bash
# Hive Installation Script
# Installs the hive skill to ~/.claude/skills/hive
#
# Usage: ./install.sh [skill-dir]
# Example: ./install.sh ~/.claude/skills/hive

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="${1:-$HOME/.claude/skills/hive}"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}Installing Hive to: $SKILL_DIR${NC}"
echo ""

# Check dependencies
echo "Checking dependencies..."

if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}Warning: jq not found. Install with: sudo apt install jq${NC}"
fi

if ! command -v uuidgen &> /dev/null; then
    echo -e "${YELLOW}Warning: uuidgen not found. Install with: sudo apt install uuid-runtime${NC}"
fi

if ! command -v claude &> /dev/null; then
    echo -e "${YELLOW}Warning: claude not found in PATH. Make sure Claude Code CLI is installed.${NC}"
fi

# Create skill directory
mkdir -p "$SKILL_DIR"

# Copy skill files
if [[ -d "$SCRIPT_DIR/skills/hive" ]]; then
    echo "Copying skill files from local repo..."
    cp "$SCRIPT_DIR/skills/hive/"* "$SKILL_DIR/"
else
    echo "Downloading skill files..."
    REPO_URL="https://raw.githubusercontent.com/konradish/hive/main/skills/hive"
    for file in SKILL.md PROTOCOL.md worker-prompt.md spawn.sh status.sh monitor.sh cleanup.sh setup.sh; do
        curl -sSL "$REPO_URL/$file" -o "$SKILL_DIR/$file"
    done
fi

# Make scripts executable
chmod +x "$SKILL_DIR/"*.sh

echo ""
echo -e "${GREEN}Hive installed successfully!${NC}"
echo ""
echo "Files installed to: $SKILL_DIR"
ls -la "$SKILL_DIR"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "1. Initialize .hive in your orchestration repo:"
echo "   bash $SKILL_DIR/setup.sh /path/to/notes/.hive"
echo ""
echo "2. Edit projects.json with your project paths:"
echo "   vim /path/to/notes/.hive/projects.json"
echo ""
echo "3. Add hive enforcement to your CLAUDE.md (see examples/claude-md-snippet.md)"
echo ""
echo "4. Ask Claude: 'spawn a worker to fix the bug in my-project'"
