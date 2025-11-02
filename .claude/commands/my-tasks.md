---
description: Show tasks assigned to a specific role (default: eng1)
---

Display tasks assigned to a specific role. If no role is specified, show tasks for eng1.

Usage:
- `/my-tasks` - Show eng1's tasks
- `/my-tasks eng2` - Show eng2's tasks
- `/my-tasks pjm` - Show pjm's tasks

Run: `./scripts/core/task-manager.sh my-tasks <role>`

After running the command, summarize the assigned tasks for the user.
