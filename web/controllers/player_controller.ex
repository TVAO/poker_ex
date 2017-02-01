defmodule PokerEx.PlayerController do
  use PokerEx.Web, :controller
  plug :authenticate_player when action in [:index, :show]
  
  alias PokerEx.Player
  
  def new(conn, _params) do
    changeset = Player.changeset(%Player{})
    render conn, "new.html", changeset: changeset
  end
  
  def index(conn, _params) do
    players = Repo.all(PokerEx.Player)
    render conn, "index.html", players: players
  end
  
  def create(conn, %{"player" => player_params}) do
    player_params = Map.put(player_params, "chips", "1000")
    changeset = Player.registration_changeset(%Player{}, player_params)
    
    case Repo.insert(changeset) do
      {:ok, player} ->
        conn
        |> PokerEx.Auth.login(player)
        |> put_flash(:info, "#{player.name} created!")
        |> redirect(to: page_path(conn, :index))
      {:error, changeset} ->
        render(conn, "new.html", changeset: changeset)
    end
  end
  
end