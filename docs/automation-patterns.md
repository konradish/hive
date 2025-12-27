# Claude Code Automation Patterns

Patterns and practices for effective Claude Code orchestration.

## External Orchestration: n8n + SSH Pattern

*Use workflow automation tools as the orchestrator, Claude Code as the intelligent worker.*

### Architecture

```
n8n (Orchestrator)
  - Handles triggers (webhooks, Slack, schedule)
  - Manages logic flow and routing
  - Stores session IDs for memory
         │ SSH Node
         v
Host Machine (Worker)
  - Claude Code installed + authenticated
  - Access to local files, projects, tools
  - Custom Skills available
```

**Why SSH over API wrappers?** Claude Code via SSH gets:
- Full filesystem access
- System tools (network checks, Python scripts, Docker)
- Custom Skills
- Session persistence via `--session-id`

### Critical Flags for Automation

```bash
claude \
  -p "Your prompt here" \              # Headless/print mode
  --dangerously-skip-permissions \     # No permission prompts
  --session-id {{ $json.uuid }}        # Maintain conversation memory
```

### Session Memory Pattern

Standard CLI executions are stateless. For multi-turn conversations (like Slack threads):

1. **Generate UUID** (JavaScript node):
   ```javascript
   return { uuid: crypto.randomUUID() }
   ```

2. **Pass to Claude Code** via `--session-id`

3. **Reuse same UUID** for follow-up messages in the thread

### Use Cases

- **IT Support Bot**: Slack -> Claude diagnoses -> runs network checks -> responds
- **Project Automation**: Webhook -> Claude updates files -> commits -> deploys
- **Scheduled Tasks**: Cron -> Claude analyzes logs -> sends alerts

---

## High-Alpha Playbook: Explore -> Plan -> Execute

*Elevating Claude from code generator to AI development partner*

### The Three-Step Process

**1. EXPLORE: Build Deep Context**
```
> Prepare to discuss the architecture of this project.
> Read through [key_file_1.md], [key_file_2.ts], and the /context directory.
> Do not write any code yet. Summarize your understanding.
```
*Spend tokens on understanding, not re-writing flawed code.*

**2. PLAN: Architect Before You Code**
- Generate initial plan with testable PRs
- **"My Developer" Critique**: Fork context, prompt: *"My junior developer wrote this plan. Give feedback. How can we improve it?"*
- Identify "Blast Radius": List every file that needs modification
- Define tests FIRST (TDD): Write test names before implementation

**3. EXECUTE: Let It Rip**
- Use auto-runs for speed
- Watch mode for critical sections
- Execute one PR at a time; use different context for review

### Context Architecture

- **Hierarchical CLAUDE.md**: Root + specialized per-directory
- **Reference, don't repeat**: Link to examples, style guides in `/context`
- **Automated review standards**: Embed criteria in CLAUDE.md

---

## The Holodeck: Counterfactual Engineering

*Testing whether documentation changes actually improve agent behavior*

### The Problem

```
Task A (Fail) -> Update Docs -> Task B (Success)
```
**Logical fallacy**: You assume the doc update fixed it. But maybe Task B was just easier.

### The Solution

```
Task A (Fail) -> Update Docs -> Re-run Task A (in Simulation) -> Task A (Success)
```
*This confirms causality. Turns Operations into Data Science.*

### VCR Architecture (Record/Replay)

Claude Code captures sessions to `~/.claude/projects/<project>/<session-id>.jsonl`

**Three Modes:**

| Mode | Behavior |
|------|----------|
| **Record** | Normal operation; Claude logs everything |
| **Replay** | Returns recorded outputs; detects divergence |
| **Simulate** | LLM generates outputs for commands not in trace |

**Counterfactual Testing Workflow:**
1. Capture failure session (already logged)
2. Extract trace: `jq 'select(.message.content[]?.type == "tool_use")' session.jsonl > trace.jsonl`
3. Fix documentation
4. Replay with new docs against old trace
5. Observe: Does agent diverge? Does it find the issue?

**Victory Condition**: Agent behavior improves with same inputs + better docs.

---

## Anti-Patterns

### Over-automation
Don't automate judgment calls that need human review.

### Silent failures
Always surface errors visibly; hooks should fail loud.

### Quota blindness
Headless mode consumes Max quota; batch appropriately.

### Permission skipping
Avoid `--dangerously-skip-permissions` outside containers.

### Direct cross-project editing
Never edit files in other repos without spawning a worker in that context.

---

## Community Patterns

- **GitButler Integration**: Auto-commits work into lanes per session via hooks
- **viwo-cli**: Docker + git worktrees for safer `--dangerously-skip-permissions` usage
- **RIPER Workflow**: Enforced phase separation (Research, Innovate, Plan, Execute, Review)
- **Skill Auto-Selection**: Hooks that activate appropriate skills based on context

---

## Sources

- [Claude Code Hooks Reference](https://docs.anthropic.com/en/docs/claude-code/hooks)
- [Anthropic Best Practices](https://www.anthropic.com/engineering/claude-code-best-practices)
- [Awesome Claude Code](https://github.com/hesreallyhim/awesome-claude-code)
