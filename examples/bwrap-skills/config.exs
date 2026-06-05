# Bwrap Skills Test - Verify skills are loaded in bwrap sandbox
#
# Usage: mix genswarms.start examples/bwrap-skills/config.exs
#        mix genswarms.task bwrap-skills agent_1 "What is the secret number?"

%{
  name: "bwrap-skills",
  agents: [
    %{
      name: :agent_1,
      backend: :bwrap,
      skills: ["secret.md"],
      presets: [:base],
      model: "minimax/minimax-m2.7"
    }
  ],
  topology: []
}
