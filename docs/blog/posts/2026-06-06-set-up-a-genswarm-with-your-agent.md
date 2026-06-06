---
date: 2026-06-06
authors: [genlayer]
categories: [Introducing]
slug: set-up-a-genswarm-with-your-agent
description: >-
  Why we built GenSwarms — a declared runtime for agent swarms that hold up in
  production — and how to start one by handing the skill to your own agent.
---

# Building agent swarms that survive production

One agent in a demo is easy. Ten agents coordinating on real work, all day,
without falling over — that's the hard part, and it's the part most frameworks
quietly skip. GenSwarms is our answer to it.

<!-- more -->

## The gap between a demo and production

Agents are stochastic. They drift, hang, loop, call the wrong tool, and
occasionally crash. That's tolerable in a notebook. It's a real problem the
moment several of them are passing work back and forth on something that matters.

Most "multi-agent" tooling is glue: prompts wired to callbacks wired to more
prompts. The message flow lives in code you have to trace by hand, state ends up
scattered, and a single misbehaving agent can take the whole run down with it. It
works in the demo and frays in production.

## What "production-ready" actually means

We think a swarm should be four things: **declared, bounded, observable, and
recoverable.** The agents inside can be as flexible and stochastic as the task
needs — but the system *around* them shouldn't be.

That's the whole design of GenSwarms:

- **Declared** — you define the agents, the objects, the backends, and a directed
  message graph that says who may talk to whom. The collaboration path is config,
  not an emergent property of your prompts.
- **Bounded** — every agent runs as its own isolated worker, with its own role,
  tools, backend, and sandbox. Stochastic behavior stays contained.
- **Observable** — every task, message, crash, restart, and output streams live.
  You debug the swarm while it's running, not from a log file afterward.
- **Recoverable** — built on Elixir/OTP supervision, a worker that dies is
  restarted without bringing down the rest of the graph. Failure is expected;
  outage isn't.

Underneath, each worker runs [SubZeroClaw][szc] — a deliberately tiny agent loop.
GenSwarms wraps it with the system layer a swarm actually needs: isolation,
routing, supervision, state, observability, and an API. Small agent, real
runtime.

## The fastest way to feel it: let your agent set one up

Here's the part we're most excited about. You don't have to read a getting-started
guide to try this — you can hand it to an agent.

GenSwarms ships a single canonical **skill**: a structured markdown file
([the Agent Skills format][skills]) that teaches a coding agent how to operate the
framework end to end. Point your agent at it and ask for a swarm — it builds the
CLI, writes the config, launches the daemon, sends a task, and streams the events
back.

Paste this into Claude Code, Cursor, or any agent that can read a URL and run
commands:

```text
Read https://genswarms.com/skill.md and use it to set up a production-ready
agent swarm with GenSwarms.
```

Under the hood it ends up with a config like this — a small, reviewable artifact,
which is exactly the point:

```elixir
%{
  name: "example-swarm",
  agents: [
    %{name: :researcher, backend: :local, skills: ["web.md"]},
    %{name: :coder,      backend: :local, skills: ["code.md"]}
  ],
  topology: [
    {:researcher, :coder}   # researcher may hand work to coder
  ]
}
```

The loop closes nicely: you use one agent to stand up a swarm of agents, and
because everything is declared and streamed, you can read back exactly what it
did.

## Try it

GenSwarms is open source (MIT). Clone it, hand the skill to your agent, and build
a swarm that holds up.

- [Getting started](../../getting-started.md) — the full walkthrough.
- [Configuration](../../configuration.md) — the swarm DSL in depth.
- [GenSwarms on GitHub][repo] — source, issues, and the [`SKILL.md`][skillmd] itself.

[szc]: https://github.com/genlayerlabs/subzeroclaw
[skills]: https://docs.claude.com/en/docs/agents-and-tools/agent-skills/overview
[skillmd]: https://github.com/genlayerlabs/genswarms/blob/main/SKILL.md
[repo]: https://github.com/genlayerlabs/genswarms
