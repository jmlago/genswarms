# Observability

Genswarm exposes everything that happens in a swarm through a **single event
spine**. Understanding that spine is the key to building any dashboard, monitor,
or alerting on top of the framework.

## The one rule

> Every observable **state transition** emits a `:telemetry` event — and nothing
> else logs it. A telemetry bridge funnels those into `LogStore`, which both
> **persists** them (ETS + SQLite) and **streams** them over WebSocket.

A transition is logged in exactly one place: its `emit_telemetry/2,3` call. The
emitter never also calls `LogStore.log` for the same moment — that was the old
duplication, now removed. `LogStore.log` is reserved for **diagnostics/IO that
have no transition event**: backend container ops, raw agent stdout, received
messages, config-load failures. Those are single-source, so they never double up
with the bridge.

The bridge derives the log `level` from the event name (see below). When the
level depends on the outcome (a partial swarm start, an unexpected agent exit),
the emitter passes `level:` in the telemetry metadata to set it explicitly; the
bridge strips that key before persisting, so it never leaks into the payload.

```
emit_telemetry(:agent_started, ...)            ← emitters (swarm_manager, agent_server, …)
        │  [:genswarm, :agent, :agent_started]
        ▼
Genswarm.Observability.TelemetryBridge          ← single :telemetry handler
        │  LogStore.log(:info, :agent, :agent_started, "agent fixer_1 started", …)
        ▼
Genswarm.Observability.LogStore
        ├── ETS ring buffer        → LogStore.query / GET /api/events (fast, in-node)
        ├── SQLite                 → cross-process / `swarm events` CLI
        └── PubSub {:log_event, e} → SwarmChannel "event" / "log_entry" push (live)
```

To make a new transition observable, **emit a telemetry event** under
`[:genswarm, <domain>, <event>]` and add it to
`Genswarm.Observability.TelemetryBridge` `known_events/0` (and the table below).
Nothing else — no controller, no broadcast, no LogStore call at the call site.

## Event taxonomy

`level` is derived from the event name (`*error*`/`*failed*` → `:error`,
`*invalid*`/`*not_found*`/`*full*` → `:warning`, otherwise `:info`).
`category` is the telemetry domain (`:router` is normalized to `:routing`).

| Domain (category) | Event | Level | Meaning |
|---|---|---|---|
| `swarm` | `swarm_started` | info | swarm finished starting (metadata `:status` = `running`/`error`) |
| `swarm` | `swarm_stopped` | info | swarm torn down |
| `agent` | `agent_started` | info | agent process up |
| `agent` | `agent_stopped` | info | agent process exited (metadata `:exit_status`) |
| `agent` | `agent_error` | error | agent backend/runtime error |
| `agent` | `agent_added` | info | agent added to a running swarm |
| `agent` | `agent_removed` | info | agent removed from a running swarm |
| `agent` | `task_sent` | info | task delivered to an agent |
| `object` | `object_started` | info | object handler initialized |
| `object` | `object_stopped` | info | object handler stopped |
| `object` | `object_error` | error | object handler crashed/errored |
| `object` | `object_added` | info | object added to a running swarm |
| `object` | `object_removed` | info | object removed from a running swarm |
| `routing` | `message_routed` | info | direct message routed (`:from`, `:to`) |
| `routing` | `message_delivered` | info | message delivered to target inbox |
| `routing` | `message_broadcast` | info | broadcast routed (`:from`) |
| `routing` | `invalid_route` | warning | message rejected by topology |

Every event carries `:swarm` in its metadata; agent/object events also carry
`:agent`/`:object` (lifted to dedicated columns by `LogStore`). Remaining
metadata is kept JSON-friendly in the event's `metadata` blob.

## Reading the stream

**Snapshot (current state)** — bootstrap a view, then follow the live stream:

| Endpoint | Returns |
|---|---|
| `GET /api/swarms/:name` | swarm status, agents, objects, counts |
| `GET /api/swarms/:name/topology` | topology adjacency |
| `GET /api/swarms/:name/objects` | objects + lifecycle state |
| `GET /api/swarms/:name/objects/:object_name` | one object's live domain state (generic introspection) |
| `GET /api/swarms/:name/agents/:agent_name` | one agent's status |

**History (what happened)** — backed by the spine above:

| Endpoint | Returns |
|---|---|
| `GET /api/events` | recent events, filterable by `level`/`category`/`event_type` |
| `GET /api/swarms/:name/events` | events for one swarm |
| `GET /api/swarms/:name/agents/:agent_name/events` | events for one agent |

**Live (WebSocket `swarm:<name>` channel)** — push messages:

| Push | Source |
|---|---|
| `event`, `log_entry` | `LogStore` (the whole taxonomy above, after `subscribe_events`/`subscribe_logs`) |
| `agent_output` | agent stdout |
| `agent_status` | agent state transition |
| `message_routed`, `message_broadcast` | router |
| `swarm_started`, `swarm_stopped` | swarm lifecycle |
| `agent_added`, `agent_removed`, `topology_changed` | dynamic mutations |

**CLI (`swarm events`)** — reads the spine too, no extra wiring:

```bash
swarm events                 # recent events across all swarms
swarm events -s my-swarm     # one swarm
swarm events --category routing   # filter by category (backend|routing|agent|object|swarm|system)
swarm events --errors        # errors only
swarm events --follow        # stream in real time
```

The CLI is a **cross-process** consumer: swarms run as separate daemon OS
processes, so the CLI can't read their in-node ETS. It reads the `events` table
in `.swarm/swarms.db` instead — which `LogStore` writes to on every `log/5` via
`persist_to_sqlite/7` → `SwarmRegistry.log_event`. Because the telemetry bridge
feeds `LogStore`, the daemon's full event taxonomy lands in that table
automatically, and `swarm events` surfaces it with **no CLI changes**. (The
`--category` values map 1:1 to the taxonomy above.)

This is the payoff of a single spine: feeding `LogStore` from the bridge improved
the CLI, the REST `/api/events` endpoints, and the WS stream at once — none of
them needed to be touched.

## Deployment topologies (one node vs. many daemons)

This matters because a BEAM's in-memory machinery (PubSub, the process `Registry`,
the ETS `LogStore`) is **node-local** — invisible from another OS process. Two
shapes:

**Co-located** — the swarm runs in the same BEAM as the Phoenix endpoint (e.g.
started in-process via `POST /api/swarms`). Live PubSub, the WS stream, and the
live snapshot endpoints all work directly. Nothing special needed.

**Monitor + daemons** — the usual shape at scale: each swarm runs as its own
daemon (`swarm start`, its own BEAM), and a separate monitor/API node observes
all of them. Here the only thing the processes share is the SQLite `events` table.
So observability crosses processes like this:

```
daemon swarm A ─┐  emit_telemetry → LogStore → SQLite events  ┐
daemon swarm B ─┤                                             ├─►  shared .swarm/swarms.db
daemon swarm C ─┘                                             ┘
                                                              │
                          monitor / API node ───── EventRelay polls `events_since` ──┐
                                                              │                       │
                          REST /api/events  ── reads SQLite ──┤                       ▼
                          WS swarm:<name>    ◄─ EventRelay re-broadcasts {:log_event} onto
                                                 the same LogStore PubSub topics → SwarmChannel push
```

- **`GET /api/events`** (and the swarm/agent variants) read SQLite, so they
  surface **every** swarm, daemon or in-process.
- **`Genswarm.Observability.EventRelay`** runs on the monitor node (started by
  `start_web_server/1`). It tails new SQLite rows every ~500ms and re-broadcasts
  them onto the in-node PubSub topics, so the existing `SwarmChannel` pushes them
  to WS clients live — **no clustering required**. Latency ≈ the poll interval
  (set `config :genswarm, :event_relay, false` to disable).
- A WS client gets recent history from the **snapshot on subscribe** (also read
  from SQLite) and the live tail from the relay.

> Run the relay only on a monitor node that does **not** host swarms in-process.
> There the in-node `LogStore` never broadcasts swarm events (they happen in the
> daemons), so the relay is the sole live source — no double-delivery.

### Still node-local (known limits)

- **Live process-state pulls** (`GET /objects/:name`, `/agents/:name`) call into
  the in-node `Registry`, so they only reach swarms in the **same** BEAM. For
  daemon swarms, rely on the event stream (and `GET /swarms/:name`, which has a
  SQLite fallback) instead of synchronous state pulls.
- **Object internal state** changes don't emit events (only object lifecycle
  does), so a live object-state feed isn't available — poll `GET /objects/:name`
  in a co-located setup, or have the object emit on change.
- Want true sub-second push or cross-host fan-out without polling? Swap
  `Phoenix.PubSub` to its **Redis adapter** — the single spine means only the
  transport changes, not the emitters, bridge, or channel.

## Building a dashboard

A dashboard is a **consumer**, not framework code (the project is API-first and
headless by design — no HTML ships here):

1. Bootstrap from the snapshot endpoints (status + topology + objects).
2. Open the `swarm:<name>` channel, `subscribe_events` for the taxonomy, and
   patch the view from the push stream.
3. Domain-specific concepts (e.g. user "sessions", conversation transcripts) live
   in the consumer and read from the consumer's own store — the framework stays
   generic and exposes only the generic object state via the introspection
   endpoint above.
