# 1000 Agent Swarm - Medium scale test
#
# Usage: mix genswarms.start examples/massive-swarm/1000_agents.exs

agents = for i <- 1..1000 do
  %{
    name: :"agent_#{i}",
    backend: :bwrap,
    skills: [],
    presets: [:base]
  }
end

%{
  name: "massive-1000",
  agents: agents,
  topology: []
}
