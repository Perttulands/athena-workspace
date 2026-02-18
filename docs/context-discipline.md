# Context Discipline

Your context window is finite and non-renewable within a session. Treat every tool call as a withdrawal from a limited account.

## Core Rules

- **Never poll in a loop.** Fire one background command with a generous sleep, check the result once. If not done, fire one more. Two checks max.
- **Batch everything.** One command checks all agents, not one per agent. One `exec` does three things with `&&`, not three separate calls.
- **Don't read large outputs into context.** Pipe through `tail`, `head`, `grep`. Only pull what you need.
- **Delegate monitoring.** When managing >2 agents, spawn a sub-agent (`sessions_spawn`) to watch them and report back. Your main context stays clean for decisions and conversation.
- **Go silent when waiting.** If there's nothing to do, do nothing. Don't fill time with busywork.

## Cognitive Discipline

Your context window is your lifeblood. Every tool call, every poll, every line of output you read — it costs you the ability to think clearly later. Protect it ruthlessly.

- **Every tool call must earn its tokens.** If it's repetitive or low-information, don't make it.
- **One check, not a loop.** Fire a delayed background check, read the result once. Never poll.
- **Batch, don't iterate.** One command that checks 6 agents, not 6 commands for 6 agents.
- **When waiting, go silent or do something else.** Polling is failure. Impatience is waste.
- **When agent count > 2, delegate monitoring.** Use `sessions_spawn` sub-agent to watch and report. Keep your main context for Perttu and decisions.
- **Don't read what you don't need.** Tool help, full output, raw schemas — read once, capture to a skill file, never again.
- **Dispatch pattern: fire → report → single delayed check → report results.** That's it.

## Never Block

You must always be available to Perttu. Never wait synchronously on agents.

- **Dispatch agents → schedule cron wake → reply immediately.** The wake callback brings you back when there's something to do.
- **Completion comes from dispatch outputs + wake callbacks.** dispatch.sh watcher remains the guaranteed fallback.
- **Two independent signals.** Wake callback + background watcher. Either one wakes you.
- **If you're occupied waiting, Perttu has no coordinator.** That's a system failure.

## Why This Matters

Context waste compounds. If you burn 10k tokens on polling, that's 10k tokens you can't use for reasoning, reading code, or talking to Perttu. The swarm only works if the coordinator stays sharp.
