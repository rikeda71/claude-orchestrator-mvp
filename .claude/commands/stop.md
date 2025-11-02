---
description: Stop the Claude Orchestrator system gracefully
---

Gracefully stop the Claude Orchestrator system:

1. Run the shutdown script: `./scripts/stop-system.sh`
2. Verify all sessions are stopped: `tmux list-sessions | grep claude`

After stopping, confirm to the user that the system has been shut down successfully.
