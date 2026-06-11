# Real-harness validation for the sync-agent-turns branch (#54)

Runs the ORIGINAL failure scenario (a page fetch that 404s) through the REAL
subzeroclaw binary + wrapper + engine — only the LLM is scripted. Proves the
three #53 failure modes are gone at the runtime level: the typed envelope
arrives inline in the same turn (no fabrication window), the final text is
auto-delivered (no forgettable send), and the `permanent` error type stops
retries (one ask, no loop).

## Run

```sh
# 1. build subzeroclaw anywhere (vendored cJSON or pkg-config libcjson)
make -C /path/to/subzeroclaw          # adjust CFLAGS/LDFLAGS for libcjson

# 2. from the genswarms repo root:
mkdir -p /tmp/szc-validate
cp /path/to/subzeroclaw/subzeroclaw /tmp/szc-validate/
python3 scripts/validate-sync-agent-turns/mock_llm.py \
  /tmp/szc-validate/ws "$PWD/swarm-msg" 18723 &
mix run scripts/validate-sync-agent-turns/validate.exs
```

Expected: `══ REAL-HARNESS VALIDATION PASSED ══` (9 checks).

Note: endpoint+key go through SERVER env (`SUBZEROCLAW_ENDPOINT`/`_API_KEY`,
set by validate.exs) — a per-agent `:api_key` does NOT reach the backend
(pre-existing: it isn't in agent_server's backend_keys despite the
EndpointPolicy doc; tracked separately).
