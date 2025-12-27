#!/bin/bash
# Hive Setup Script
# Initializes the .hive directory structure in your notes repo
#
# Usage: ./setup.sh [hive-dir]
# Example: ./setup.sh /path/to/notes/.hive

set -e

HIVE_DIR="${1:-.hive}"

echo "Setting up Hive in: $HIVE_DIR"

# Create directory structure
mkdir -p "$HIVE_DIR/workers"
mkdir -p "$HIVE_DIR/learnings"
mkdir -p "$HIVE_DIR/archive"

# Create projects.json if it doesn't exist
if [[ ! -f "$HIVE_DIR/projects.json" ]]; then
    cat > "$HIVE_DIR/projects.json" << 'EOF'
{
  "example-project": "/path/to/example-project",
  "another-project": "/path/to/another-project"
}
EOF
    echo "Created projects.json - edit this to add your projects"
else
    echo "projects.json already exists"
fi

# Create .gitignore for workers (transcripts can be large)
cat > "$HIVE_DIR/.gitignore" << 'EOF'
# Ignore worker transcripts (large files)
workers/*/transcript.jsonl

# Keep structure but ignore contents
workers/*

# But track the directory
!workers/.gitkeep
EOF

touch "$HIVE_DIR/workers/.gitkeep"

echo ""
echo "Hive initialized!"
echo ""
echo "Directory structure:"
find "$HIVE_DIR" -type f | head -20
echo ""
echo "Next steps:"
echo "1. Edit $HIVE_DIR/projects.json to add your projects"
echo "2. Ask Claude to 'spawn workers' or 'work on X and Y in parallel'"
