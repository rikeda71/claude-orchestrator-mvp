---
description: Start the Claude Orchestrator system
---

Start the Claude Orchestrator system with all necessary components:

1. Run the startup script: `./scripts/start-system.sh`
2. Wait for sessions to initialize
3. Run health check: `./scripts/core/session-manager.sh health`

After the system starts, provide instructions on how to:
- Attach to sessions (tmux attach -t claude-pjm or claude-eng1)
- Create tasks
- Monitor progress

If the user wants to start with sample tasks, run: `./scripts/start-system.sh --with-samples`
