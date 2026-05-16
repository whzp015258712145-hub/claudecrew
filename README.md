# ClaudeCrew — Multi-Agent Orchestrator for Claude Code

A Claude Code skill that orchestrates multiple AI agents to tackle large, decomposable tasks in parallel.

## How It Works

1. **Mother Agent** analyzes the task and decomposes it into fully decoupled subtasks
2. **Worker Agents** execute subtasks in parallel, each producing independent deliverables
3. **Reviewer Agents** audit each deliverable for bugs and spec compliance
4. **Fix → Review** loops iterate until all pass
5. **Chief Auditor** performs cross-module integration audit
6. **Final delivery** — all results assembled and verified

All coordination happens through a SPEC directory of markdown files. Agents never talk to each other — the Mother Agent owns the plan entirely.

## Usage

In Claude Code, trigger with:

```
/claudecrew <your task>
```

Or use keywords like: `claudecrew`, `orchestrate`, `distribute this`, `parallelize`

## File Structure

```
claudecrew/
├── SKILL.md              # Main skill definition (the agent orchestration protocol)
├── launch.sh             # Launch worker/reviewer agents in new terminal windows
├── wait-workers.sh       # Background polling for worker completion signals
└── references/
    └── spec-format.md    # Spec file format templates (REQUEST, DISPATCH, Worker, Reviewer, etc.)
```

## Requirements

- [Claude Code](https://claude.ai/claude-code) CLI with `-p` flag support
- No additional dependencies

## Example

Prompt: `开发一个豪华版贪吃蛇` (Develop a deluxe Snake game)

→ 3 Workers built `game-core.js`, `renderer.js`, and `index.html` in parallel
→ 3 Reviewers found 15 bugs across 3 rounds
→ Chief Auditor PASS
→ [Result](https://github.com/whzp015258712145-hub/deluxe-snake)

## License

MIT
