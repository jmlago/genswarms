# 10000 Agent Swarm - Full scale test
#
# Requires NixOS system configuration from nix/bwrap-module.nix
#
# Usage: mix genswarms.start examples/massive-swarm/10000_agents.exs

agents = for i <- 1..10000 do
  %{
    name: :"agent_#{i}",
    backend: :bwrap,
    skills: [],
    presets: [:base]
  }
end

%{
  name: "massive-10000",
  agents: agents,
  topology: []
}
