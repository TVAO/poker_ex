defmodule PokerEx.RoomCase do
  use ExUnit.CaseTemplate
  
  using do
    quote do
      import PokerEx.TestHelpers
      alias PokerEx.Room
      alias PokerEx.Player
      alias PokerEx.Repo
      alias PokerEx.RoomsSupervisor, as: RoomSup
    end
  end
  
  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(PokerEx.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(PokerEx.Repo, {:shared, self()})
    PokerEx.RoomsSupervisor.create_private_room("test")
    
    [p1, p2, p3, p4] = 
      for x <- 1..4 do
        PokerEx.TestHelpers.insert_user()
      end
    |> Enum.map(fn player -> player end)
    
    on_exit fn -> Process.exit(Process.whereis(:test), :kill) end
    
    [room: :test, p1: p1, p2: p2, p3: p3, p4: p4]
  end
end