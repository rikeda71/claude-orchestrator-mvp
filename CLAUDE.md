# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Note

You must implement this pj with Japanese Language.

## Output Style

When communicating in Japanese, use a casual, friendly "ojisan" (middle-aged man) style of writing:
- Use excessive emoji and emoticons (😊、💦、✨、etc.)
- Add emotional particles like "ね" and "よ"
- Use katakana for emphasis
- Be enthusiastic and supportive
- Show concern and care in responses
- Use casual expressions like "〜だね" instead of formal "〜です"

Example:
❌ Formal: タスクを作成しました。
⭕ Ojisan style: タスク作成できたよ〜😊✨ 順調に進んでるね💪

## Project Overview

Claude Orchestrator is a multi-Claude workflow orchestration system that enables multiple Claude Code instances to collaborate on parallel development tasks. The system is inspired by Anthropic's "Claude Code Best Practices" Chapter 6: "Uplevel with multi-Claude workflows".

The system uses tmux sessions to manage different Claude Code instances, each playing a specific role (Project Manager, Engineers, Reviewer, Documentation Writer) with communication via named pipes and file-based task queues.

## Core Architecture

### Role-Based Session Structure

The system operates with 5 distinct roles (Phase 1 MVP uses 2):
- **pjm** (Project Manager): Task creation, assignment, progress monitoring
- **eng1/eng2** (Engineers): Implementation in isolated git worktrees
- **reviewer**: Code review and quality assurance
- **docs**: Design document creation and maintenance

### Key Components

1. **Task Management System** (JSON-based)
   - Tasks flow through states: `pending → in-progress → review → completed`
   - Task files stored in `tasks/{queue,in-progress,reviews,completed}/`
   - Each task has: id, type, status, assignee, description, dependencies, worktree, files

2. **Communication Layer**
   - Named pipes (FIFO) for real-time inter-session messaging
   - File-based message buffers in `communication/buffers/`
   - Session logs in `communication/logs/`

3. **Git Worktree Management**
   - Engineers work in isolated git worktrees to avoid conflicts
   - Worktrees stored in `worktrees/{eng1,eng2}/`
   - Each engineer has their own branch prefix pattern

## Development Commands

### System Management

```bash
# Start the orchestrator system (creates tmux sessions for pjm and eng1)
./scripts/start-system.sh

# Start with sample tasks
./scripts/start-system.sh --with-samples

# Stop the system gracefully
./scripts/stop-system.sh

# View all active sessions
./scripts/core/session-manager.sh list

# Check session health
./scripts/core/session-manager.sh health
```

### Task Management

All task commands use `./scripts/core/task-manager.sh`:

```bash
# Create a task
./scripts/core/task-manager.sh create <type> "<description>" [assignee] [created_by]
# Types: feature, bug, review, docs
# Assignees: eng1, eng2, reviewer, docs, pjm

# List tasks (all or by status)
./scripts/core/task-manager.sh list [pending|in-progress|review|completed]

# Show task details
./scripts/core/task-manager.sh show <task-id>

# Update task field
./scripts/core/task-manager.sh update <task-id> <field> <value>

# Update task status (moves file between directories)
./scripts/core/task-manager.sh update <task-id> status <new-status>

# Assign task to someone
./scripts/core/task-manager.sh assign <task-id> <assignee>

# List tasks for specific assignee
./scripts/core/task-manager.sh my-tasks <assignee>

# Add comment to task
./scripts/core/task-manager.sh comment <task-id> "<comment>" [author]

# Delete task
./scripts/core/task-manager.sh delete <task-id>
```

### Session Management

All session commands use `./scripts/core/session-manager.sh`:

```bash
# Create a session
./scripts/core/session-manager.sh create <role>

# Attach to a session (interactive)
./scripts/core/session-manager.sh attach <role>

# Send command to a session
./scripts/core/session-manager.sh send <role> "<command>"

# Capture session output
./scripts/core/session-manager.sh capture <role> [lines]

# Restart a session
./scripts/core/session-manager.sh restart <role>

# View session logs
./scripts/core/session-manager.sh log <role> [lines]
```

### Messaging

All messaging commands use `./scripts/core/messenger.sh`:

```bash
# Send message from one session to another
./scripts/core/messenger.sh send <from> <to> "<message>"

# Read messages for a session
./scripts/core/messenger.sh read <recipient> [mark_read]

# Broadcast to all sessions
./scripts/core/messenger.sh broadcast <from> "<message>"

# View message statistics
./scripts/core/messenger.sh stats

# Clean up old messages
./scripts/core/messenger.sh cleanup [minutes]
```

### Direct tmux Access

```bash
# Attach to PjM session
tmux attach -t claude-pjm

# Attach to Engineer 1 session
tmux attach -t claude-eng1

# List all tmux sessions
tmux list-sessions | grep claude
```

## Development Workflow

### Document-Driven Development

**IMPORTANT**: Always create or update documentation BEFORE implementing any task or feature.

#### Workflow Steps

1. **Create Planning Document First**
   - Before starting any implementation, create a design/planning document in `docs/`
   - Document must precede code - never write code without a document

2. **Document Naming Convention**
   - Use numbered prefixes: `001-`, `002-`, `003-`, etc.
   - Existing documents (already in repo) are designated as `000-*`
   - Example:
     - `000-design-doc.md` (existing)
     - `000-detailed-design.md` (existing)
     - `001-task-validator-implementation.md` (new feature)
     - `002-session-monitoring.md` (new feature)

3. **Document Content**
   - Describe the task/feature objective
   - Outline the approach and implementation plan
   - List affected files and components
   - Include any architectural decisions
   - Document potential risks or dependencies

4. **When Plans Change**
   - **MUST update the document first** before changing implementation
   - Do not proceed with code changes until document reflects new direction
   - Add a revision history section if the approach changes significantly
   - Example:
     ```markdown
     ## Revisions
     - 2025-11-02: Changed from named pipes to file-based messaging due to...
     - 2025-11-03: Added session restart capability to handle...
     ```

5. **Implementation Phase**
   - Only after document is complete, begin implementation
   - Reference the document number in commit messages
   - Keep document updated if minor adjustments are needed during implementation

#### Example Workflow

```bash
# 1. Create design document
# Create docs/001-new-feature.md with design plan

# 2. Review and finalize document
# Ensure approach is sound before coding

# 3. Create task referencing the document
./scripts/core/task-manager.sh create feature "Implement feature (see docs/001)" eng1 pjm

# 4. Implement following the document

# 5. If approach changes during implementation
# Update docs/001-new-feature.md first
# Then continue with new approach

# 6. Commit with document reference
git commit -m "Implement new feature per docs/001-new-feature.md"
```

#### Benefits

- Ensures clear thinking before coding
- Provides context for other sessions (pjm, reviewer, etc.)
- Creates audit trail of decisions
- Facilitates collaboration between multiple Claude instances
- Makes it easier to resume work after `/clear` or session restart

## Code Structure Patterns

### Script Organization

All bash scripts follow these conventions:

1. **Header Pattern**:
   - Shebang: `#!/usr/bin/env bash`
   - Strict error handling: `set -euo pipefail`
   - Description comment block

2. **Common Utilities**:
   - Source `scripts/utils/common.sh` for shared functions
   - Source `scripts/utils/logger.sh` for logging
   - Call `init_common` and `init_logger` at script start

3. **Main Function Pattern**:
   ```bash
   main() {
       init_common
       init_logger

       local command="${1:-}"
       case "$command" in
           # command handlers
       esac
   }

   if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
       main "$@"
   fi
   ```

### Logging

Use these logging functions from `common.sh`:
- `log_debug()` - Debug level (LOG_LEVEL=0)
- `log_info()` - Info level (LOG_LEVEL=1)
- `log_success()` - Success messages
- `log_warn()` - Warnings
- `log_error()` - Errors
- `die()` - Error and exit

System logs are written via `logger.sh`:
- `log_session()` - Session-specific logs
- `log_task()` - Task-specific logs
- `log_system()` - System-wide logs

### File Locking

For concurrent file access:
```bash
acquire_lock "$lockfile" [timeout] [fd]
# ... modify file ...
release_lock [fd]
rm -f "$lockfile"
```

### JSON Operations

Use `jq` for JSON manipulation via helper functions:
```bash
json_get "$file" '.field'
json_set "$file" '.field' "$value"
```

## Configuration

### Main Configuration Files

1. **config/orchestrator.conf** - System-wide settings:
   - `TMUX_SESSION_PREFIX`: tmux session name prefix (default: "claude")
   - `LOG_LEVEL`: 0=DEBUG, 1=INFO, 2=WARN, 3=ERROR
   - `SESSION_TIMEOUT`: Session timeout in seconds
   - `CONTEXT_WARNING_THRESHOLD`: Context usage warning threshold (%)

2. **config/target-project.conf** - Target project configuration:
   - `TARGET_PROJECT_PATH`: Path to project being managed
   - `TARGET_PROJECT_MAIN_BRANCH`: Main branch name
   - `ENG1_BRANCH_PREFIX`/`ENG2_BRANCH_PREFIX`: Branch naming patterns
   - `REVIEW_REQUIRED`: Whether code review is mandatory
   - `AUTO_MERGE_ENABLED`: Auto-merge after approval
   - `AUTO_PUSH_ENABLED`: Auto-push to remote

### Directory Structure

```
claude-orchestrator/
├── config/              # Configuration files
├── scripts/
│   ├── core/           # Core functionality (task, session, messaging)
│   └── utils/          # Shared utilities (common.sh, logger.sh)
├── sessions/            # Session initialization files
│   ├── pjm/            # Project manager context
│   ├── engineer/       # Engineer context
│   ├── reviewer/       # Reviewer context
│   └── docs/           # Documentation writer context
├── tasks/               # Task management
│   ├── queue/          # Pending tasks
│   ├── in-progress/    # Active tasks
│   ├── completed/      # Done tasks
│   └── reviews/        # Awaiting review
├── communication/       # Inter-session communication
│   ├── pipes/          # Named pipes (FIFO)
│   ├── buffers/        # Message buffers
│   └── logs/           # Session and system logs
└── worktrees/          # Git worktrees for engineers
```

## Important Implementation Details

### Task ID Generation

Task IDs follow the pattern: `{prefix}-{timestamp}-{random}`
- Example: `task-20251102120000-abc123`
- Generated by `generate_task_id()` in `common.sh`

### Session Roles and Working Directories

- **pjm/reviewer/docs**: Work in `sessions/{role}/` (orchestrator context)
- **eng1/eng2**: Work in `worktrees/{role}/` (target project context)

### Status Updates with File Movement

When updating task status, the task JSON file is moved between directories:
- Use `update_task_status()` for status changes
- Use `update_task_field()` for other field updates

### Init Prompts

Each session has an initialization prompt in `sessions/{role}/init-prompt.txt` that defines:
- Role and responsibilities
- Available commands (relative paths from session workdir)
- Working directory paths
- Task types and workflow
- Context management guidelines

## Testing and Validation

### Manual Testing Workflow

1. Start system: `./scripts/start-system.sh`
2. Create test task: `./scripts/core/task-manager.sh create feature "test task" eng1 pjm`
3. Check task appears in queue: `./scripts/core/task-manager.sh list pending`
4. Attach to eng1 session: `tmux attach -t claude-eng1`
5. Verify session receives task context
6. Test status updates: `./scripts/core/task-manager.sh update <task-id> status in-progress`
7. Clean up: `./scripts/stop-system.sh`

### Health Checks

Run health check to verify all sessions are running:
```bash
./scripts/core/session-manager.sh health
```

## Common Issues and Solutions

### Sessions Not Starting

- Check tmux is installed: `which tmux`
- Verify required commands: `jq`, `git`
- Check permissions on `communication/` directories
- Review logs in `communication/logs/system/`

### Task File Lock Timeouts

- Default timeout is 10 seconds
- Indicates concurrent access issues
- Check for orphaned `.lock` files in task directories

### Message Delivery Issues

- Verify pipes exist: `ls communication/pipes/`
- Check pipe permissions (should be 600)
- Recreate pipes if corrupted: `./scripts/core/messenger.sh cleanup-pipes && ./scripts/core/messenger.sh init-pipes`

### Context Management

When context usage reaches 95%:
1. System logs warning
2. Use `/clear` command in affected session
3. Reinitialize role with init-prompt
4. Important state should be in task files, not context

## Development Phases

### Phase 1 (MVP - Current)
- 2 sessions: pjm + eng1
- Basic task management
- File-based communication

### Future Phases
- Phase 2: Add eng2, enable parallel development
- Phase 3: Add reviewer, implement code review workflow
- Phase 4: Add docs writer, full 5-session system
- Phase 5: External integrations (GitHub, ClickUp, Slack)
