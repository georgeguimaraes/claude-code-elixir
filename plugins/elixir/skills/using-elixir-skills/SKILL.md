---
name: using-elixir-skills
description: Use when writing Elixir, Phoenix, or OTP code - routes to the correct thinking skill before any code is written
---

<EXTREMELY-IMPORTANT>
If you are about to write Elixir, Phoenix, or OTP code, you MUST invoke the relevant skill FIRST.

THIS IS NOT OPTIONAL. You cannot rationalize your way out of this.
</EXTREMELY-IMPORTANT>

## The Rule

```
Elixir/Phoenix/OTP code → Invoke skill FIRST → Then write code
```

## Skill Triggers

| Trigger Phrases | Skill to Invoke |
|-----------------|-----------------|
| code, implement, write, design, architecture, structure, pattern | `elixir-thinking` |
| LiveView, Plug, PubSub, mount, channel, socket, component | `phoenix-thinking` |
| context, schema, Ecto, changeset, preload, Repo, migration | `ecto-thinking` |
| GenServer, supervisor, Task, ETS, bottleneck, Broadway, Oban | `otp-thinking` |

## Red Flags

These thoughts mean STOP—invoke the skill:

| Thought | Reality |
|---------|---------|
| "I'll add a process to organize this" | Processes are for runtime, not organization. |
| "GenServer is the Elixir way" | GenServer is a bottleneck by design. |
| "I'll query in mount" | mount is called twice. |
| "Task.async is simpler" | Use Task.Supervisor in production. |
| "I know Elixir well enough" | These skills contain paradigm shifts. Invoke them. |
