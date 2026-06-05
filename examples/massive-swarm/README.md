# Massive Swarm Examples

Scale testing with the bwrap backend for 100-10k+ agents on a single NixOS machine.

## Prerequisites

1. NixOS with bwrap infrastructure set up (see `nix/bwrap-module.nix`)
2. Build and link sandbox base:
   ```bash
   nix build .#sandboxBase-base
   sudo ln -sfn $(readlink result) /run/swarm/sandbox-base/base
   ```

## Examples

### 100 Agents (Quick Test)

```bash
mix genswarms.start examples/massive-swarm/100_agents.exs
mix genswarms.status massive-100
mix genswarms.task massive-100 agent_50 "hello"
mix genswarms.stop massive-100
```

### 1000 Agents (Medium Scale)

```bash
mix genswarms.start examples/massive-swarm/1000_agents.exs
mix genswarms.status massive-1000
mix genswarms.stop massive-1000
```

### 10000 Agents (Full Scale)

Requires NixOS system configuration from `nix/bwrap-module.nix`:
- Increased file descriptors
- Increased mount limits
- tmpfs at /run/swarm with sufficient size

```bash
mix genswarms.start examples/massive-swarm/10000_agents.exs
mix genswarms.status massive-10000
mix genswarms.stop massive-10000
```

## Resource Usage

Tested on NixOS with 32GB RAM:

| Agents | Startup Time | RAM Used  | Notes                    |
|--------|--------------|-----------|--------------------------|
| 100    | ~2s          | ~1GB      | Works on any system      |
| 1000   | ~15s         | ~10GB     | Needs 16GB+ RAM          |
| 10000  | ~2min        | ~100GB    | Needs 128GB+ RAM         |

## System Requirements for 10k

For 10000 agents, ensure your NixOS configuration includes:

```nix
# In your configuration.nix or via nix/bwrap-module.nix
boot.kernel.sysctl = {
  "fs.mount-max" = 1048576;  # Allow 10k+ mounts
  "fs.file-max" = 2097152;   # Allow 10k+ file descriptors
};

# Tmpfs for agent sandboxes (size depends on workload)
fileSystems."/run/swarm" = {
  device = "tmpfs";
  fsType = "tmpfs";
  options = [ "size=50G" "mode=755" ];
};
```
