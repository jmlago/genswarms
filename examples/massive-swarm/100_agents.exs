# 100 Agent Swarm - Quick scale test
#
# Usage: mix genswarms.start examples/massive-swarm/100_agents.exs

agents = for i <- 1..100 do
  %{
    name: :"agent_#{i}",
    backend: :bwrap,
    skills: [],
    presets: [:base]
  }
end

%{
  name: "massive-100",
  agents: agents,
  topology: []
}
