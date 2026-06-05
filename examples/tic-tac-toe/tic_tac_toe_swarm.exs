# Tic-Tac-Toe Swarm
#
# Two agents playing tic-tac-toe through a game object.
# The game object validates moves and manages turn-taking.
#
# Topology:
#   player_x <-> game <-> player_o
#
# To start: mix genswarms.start examples/tic-tac-toe/tic_tac_toe_swarm.exs

# Load the game object handler (only compiles if not already loaded)
Code.require_file("objects/game.ex", __DIR__)

# Build absolute paths for skills
skills_dir = Path.join(__DIR__, "skills")

%{
  name: "tic-tac-toe",

  agents: [
    %{
      name: :player_x,
      backend: {:docker, "szc-agent-code:latest", %{memory_limit: "512m"}},
      skills: [Path.join(skills_dir, "player_x.md")],
      model: "minimax/minimax-m2.7"
    },
    %{
      name: :player_o,
      backend: {:docker, "szc-agent-code:latest", %{memory_limit: "512m"}},
      skills: [Path.join(skills_dir, "player_o.md")],
      model: "minimax/minimax-m2.7"
    }
  ],

  objects: [
    %{
      name: :game,
      handler: TicTacToe.Objects.Game,
      config: %{}
    }
  ],

  topology: [
    {:player_x, :game},
    {:game, :player_x},
    {:player_o, :game},
    {:game, :player_o}
  ],

  options: %{
    log_level: :info
  }
}
