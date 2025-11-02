---
description: Check system and session health
---

Perform a comprehensive health check of the Claude Orchestrator system:

1. Run session health check: `./scripts/core/session-manager.sh health`
2. List active sessions: `./scripts/core/session-manager.sh list`
3. Check message statistics: `./scripts/core/messenger.sh stats`
4. Show task queue summary: `./scripts/core/task-manager.sh list`

After running all checks, provide a summary of the system status to the user.
