# Hive - Multi-Instance Claude Code Orchestration

Coordinate multiple Claude Code instances to work on tasks in parallel across different projects.

## What is Hive?

Hive is an orchestration pattern for Claude Code that enables:

- **Parallel work** across multiple projects simultaneously
- **Two-way communication** between orchestrator and workers
- **Context isolation** - each worker operates in its project's context with access to that project's CLAUDE.md, git history, and tooling
- **Knowledge capture** - workers park their sessions for institutional knowledge transfer

## Why Use Hive?

When working from a central notes/orchestration repo, you need to make changes across multiple projects. Direct editing is dangerous:

```bash
# Anti-pattern: Orchestrator directly editing another repo
ssh prod-server "sed -i 's/old/new/g' /opt/stack/compose.yaml"  # Breaks things!
```

The problem: The orchestrator lacks context about the target project's architecture, git history, and deployment patterns.

**Hive solves this** by spawning workers that:
- Operate in the target project's directory
- Have access to the project's CLAUDE.md and git history
- Can investigate what changed before making fixes
- Park their knowledge for future sessions

## Architecture

```
orchestrator (your notes repo)
    │
    ├── .hive/
    │   ├── projects.json           # Project path registry
    │   ├── workers/<project>-<uuid>/
    │   │   ├── status.json         # Worker writes here
    │   │   ├── task.md             # Original assignment
    │   │   ├── session-id          # UUID for resume
    │   │   └── transcript.jsonl    # Full output log
    │   └── learnings/              # Cross-project knowledge
    │
    └── spawns workers ──►  project-a/  (worker operates here)
                            project-b/  (another worker here)
```

## Installation

### Option 1: Install Skill Only (Recommended)

Copy the skill to your Claude Code skills directory:

```bash
# Clone the repo
git clone https://github.com/konradish/hive.git /tmp/hive

# Copy skill files
mkdir -p ~/.claude/skills/hive
cp /tmp/hive/skill/* ~/.claude/skills/hive/

# Make scripts executable
chmod +x ~/.claude/skills/hive/*.sh
```

### Option 2: Use Install Script

```bash
curl -sSL https://raw.githubusercontent.com/konradish/hive/main/install.sh | bash
```

### Setup Your Orchestration Directory

In your notes/orchestration repo:

```bash
# Initialize .hive directory
bash ~/.claude/skills/hive/setup.sh /path/to/notes/.hive

# Edit projects.json with your project paths
vim /path/to/notes/.hive/projects.json
```

## Usage

### Basic: Spawn a Single Worker

```bash
User: "Spawn a worker to fix the auth bug in my-project"

Claude (orchestrator):
1. Creates worker directory
2. Spawns worker in my-project context
3. Monitors for status changes
4. Reports results when done
```

### Parallel: Multiple Workers

```bash
User: "Work on project-a and project-b in parallel"

Claude:
1. Spawns worker for project-a
2. Spawns worker for project-b
3. Monitors both
4. Handles questions from either
5. Collects results
```

### Using Shell Scripts Directly

```bash
# Setup (first time)
bash ~/.claude/skills/hive/setup.sh .hive

# Spawn a worker
bash ~/.claude/skills/hive/spawn.sh my-project "Fix the auth bug" .hive

# Check all worker statuses
bash ~/.claude/skills/hive/status.sh .hive

# Monitor for changes (real-time)
bash ~/.claude/skills/hive/monitor.sh .hive

# Cleanup done/failed workers
bash ~/.claude/skills/hive/cleanup.sh .hive --archive
```

## Worker Communication Protocol

Workers communicate via `status.json`:

### Status Types

| Status | Meaning | Orchestrator Action |
|--------|---------|---------------------|
| `working` | Task in progress | Wait |
| `need_input` | Question for orchestrator | Answer and resume |
| `done` | Task complete | Collect results |
| `error` | Something went wrong | Debug or retry |
| `context_full` | Context limit reached | Park and spawn fresh |

### Example: Need Input

```json
{
  "status": "need_input",
  "question": "Should I add rate limiting?",
  "options": ["Yes, 100 req/min", "No", "Make it configurable"]
}
```

Orchestrator resumes with:
```bash
claude --resume <session-id> -p "Yes, add rate limiting at 100 req/min"
```

## Configuration

### projects.json

Register your projects:

```json
{
  "my-app": "/path/to/my-app",
  "my-api": "/path/to/my-api",
  "infra": "/path/to/infra"
}
```

### CLAUDE.md Integration

Add the hive enforcement rule to your global CLAUDE.md:

```markdown
## Cross-Project Work (Hive Enforcement)

**CRITICAL: When working from notes repo on other project repos, ALWAYS use hive workers.**

### The Rule:
- NEVER directly SSH, edit files, or run commands in other repos
- ALWAYS spawn a hive worker to operate in that repo's context
- Workers have access to git history, project CLAUDE.md, and full repo context

### Correct Pattern:
/hive spawn my-project "Investigate and fix the auth bug"
```

See `examples/claude-md-snippet.md` for the full snippet.

## Best Practices

### Do

- **Spawn workers for cross-project changes** - They have the right context
- **Let workers investigate first** - They can check git history
- **Park valuable sessions** - Capture institutional knowledge
- **Use descriptive task prompts** - Workers operate with limited context

### Don't

- **Don't make direct changes** - Orchestrator lacks project context
- **Don't guess** - Workers should ask via `need_input`
- **Don't skip commits** - Workers should commit before marking done
- **Don't reuse session IDs** - Always generate fresh UUIDs

## Requirements

- Claude Code CLI (`claude`)
- `jq` for JSON parsing
- `uuidgen` for generating worker IDs
- `inotifywait` (optional, for real-time monitoring)

## Files

```
hive/
├── README.md                    # This file
├── install.sh                   # Installation script
├── skill/
│   ├── SKILL.md                 # Main orchestration instructions
│   ├── PROTOCOL.md              # Detailed status.json protocol
│   ├── worker-prompt.md         # Template for worker instructions
│   ├── spawn.sh                 # Spawn a single worker
│   ├── status.sh                # Check worker statuses
│   ├── monitor.sh               # Real-time monitoring
│   ├── cleanup.sh               # Archive/delete workers
│   └── setup.sh                 # Initialize .hive directory
├── docs/
│   └── automation-patterns.md   # Advanced patterns
└── examples/
    ├── projects.json            # Example project registry
    └── claude-md-snippet.md     # CLAUDE.md addition
```

## Related

- [Claude Code Documentation](https://docs.anthropic.com/en/docs/claude-code)
- [Claude Code Hooks](https://docs.anthropic.com/en/docs/claude-code/hooks)

## License

MIT
