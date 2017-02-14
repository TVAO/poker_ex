defmodule PokerEx.PlayersChannel do
	use Phoenix.Channel
	alias PokerEx.Player
	alias PokerEx.Room
	alias PokerEx.Endpoint
	alias PokerEx.Repo
	alias PokerEx.PlayerView
	# alias PokerEx.Presence  -> Implement presence tracking logic later
	
	intercept ["new_msg"]

	def join("players:lobby", message, socket) do
		send(self(), {:after_join, message})
		player_name = Repo.get(Player, socket.assigns[:player_id]).name
		{:ok, %{name: player_name}, socket}
	end
	def join("players:" <> room_id, %{"type" => "private"}, socket) do
		send(self(), {:after_join_private_room, room_id})
		socket = assign(socket, :room_type, :private)
		players = room_id |> atomize() |> Room.player_list()
		{:ok, %{players: players}, socket}
	end
	def join("players:" <> room_id, params, socket) do
		send(self(), {:after_join_room, room_id, params})
		players = room_id |> atomize() |> Room.player_list()
		{:ok, %{players: players}, socket}
	end
	
	def handle_info({:after_join, _message}, socket) do
		player = Repo.get(Player, socket.assigns[:player_id]).name
		broadcast! socket, "welcome_player", %{player: player}
		
		{:noreply, socket}
	end
	
	def handle_info({:after_join_room, room_id, _params}, socket) do
		socket = assign(socket, :room, room_id)
		player = Repo.get(Player, socket.assigns[:player_id])
		
		room_id
		|> atomize()
		|> Room.join(player)
		
		players = 
			room_id 
			|> atomize() 
			|> Room.player_list()
		
		seating = 
			case Room.state(room_id |> atomize()).seating do
				s when is_list(s) -> Enum.map(s, fn {name, pos} -> %{name: name, position: pos} end)
				[] -> nil
				{name, pos} -> %{name: name, position: pos} 
			end
		
		broadcast! socket, "room_joined", 
			%{player: PlayerView.render("show.json", %{player: player}), room_id: room_id}
			|> Map.merge(PlayerView.render("index.json", %{players: players}))
		broadcast! socket, "player_joined", %{player: player.name, seating: seating}

		{:noreply, socket}
	end
	
	def handle_info({:after_join_private_room, room_id}, socket) do
		socket = assign(socket, :room, room_id)
		player = Repo.get(Player, socket.assigns[:player_id])
		room = Room.state(room_id |> atomize())
	
		push(socket, "private_room_join", PokerEx.RoomView.render("room.json", %{room: room}))
		{:noreply, socket}
	end
	
	def handle_info({:game_begin, {player, _seat}, hands}, socket) do
		hands = Enum.map(hands, 
			fn {name, hand} -> 
				cards = Enum.map(hand, fn card -> Map.from_struct(card) end)
				%{player: name, hand: cards}
			end)
		Endpoint.broadcast("room:" <> socket.assigns.room, "game_began", %{active: player, hands: hands})
		{:noreply, socket}
	end
	
	#####################
	# INCOMING MESSAGES #
	#####################
	
	def handle_in("new_msg", %{"body" => body}, socket) do
		broadcast!(socket, "new_msg", %{body: body})
		{:noreply, socket}
	end
	
	def handle_in("get_num_players", _, socket) do
		for x <- 1..10 do
			room = :"room_#{x}"
			length = length(Room.state(room).seating)
			broadcast! socket, "update_num_players", %{room: room, length: length}
		end
		{:noreply, socket}
	end
	
	def handle_in("add_player", %{"player" => name, "room" => title}, socket) do
		case Repo.get_by(Player, name: name) do
			%Player{} = pl -> pl
				private_room = Repo.get_by(PokerEx.PrivateRoom, title: title) |> PokerEx.PrivateRoom.preload()
				changeset = 
					PokerEx.PrivateRoom.changeset(private_room)
					|> PokerEx.PrivateRoom.remove_invitee(private_room.invitees, pl)
					|> PokerEx.PrivateRoom.put_invitee_in_participants(private_room.participants, pl)
				case Repo.update(changeset) do
					{:ok, _priv_room} -> 
						title |> atomize() |> Room.join(pl)
						push(socket, "add_player_success", %{})
						push socket, "join_room_success", %{}
					{:error, reason} -> push socket, "error_on_room_join", %{reason: reason}
					_ -> push socket, "error_on_room_join", %{}
				end
			{:error, reason} -> push socket, "error_on_room_join", %{reason: reason}
			_ -> push socket, "error_on_room_join", %{}
		end
		{:noreply, socket}
	end
	
	def handle_in("start_game", %{"room" => roomTitle}, socket) do
		room = roomTitle |> atomize()
		case length(Room.state(room).seating) > 1 do
			false -> 
				# Ignore request if seating <= 1
				{:noreply, socket}
			true ->
				Room.start(room)
				room = Room.state(room)
				broadcast(socket, "started_game", PokerEx.RoomView.render("room.json", %{room: room}))
				{:noreply, socket}
		end
	end
	
	def handle_in("player_raised", %{"amount" => amount, "player" => player}, socket) do
		{amount, _} = Integer.parse(amount)
		Room.raise(socket.assigns.room |> atomize(), get_player_by_name(player), amount)
		{:noreply, socket}
	end
	
	def handle_in("player_called", %{"player" => player}, socket) do
		Room.call(socket.assigns.room |> atomize(), get_player_by_name(player))
		{:noreply, socket}
	end
	
	def handle_in("player_folded", %{"player" => player}, socket) do
		Room.fold(socket.assigns.room |> atomize(), get_player_by_name(player))
		{:noreply, socket}
	end
	
	def handle_in("player_checked", %{"player" => player}, socket) do
		Room.check(socket.assigns.room |> atomize(), get_player_by_name(player))
		{:noreply, socket}
	end
	
	# TODO: Implement "remove_player" message
	
	#####################
	# Outgoing Messages #
	#####################
	
	def handle_out("new_msg", payload, socket) do
		push socket, "new_msg", payload
		{:noreply, socket}
	end
	
	#############
	# Terminate #
	#############
	
	def terminate(_message, socket) do
		case socket.assigns[:room_type] do
			:private ->
				broadcast!(socket, "clear_table", %{player: Repo.get(Player, socket.assigns[:player_id]).name})
				{:shutdown, :left}
			_ ->
				room_id = socket.assigns[:room]
				player = Repo.get(Player, socket.assigns[:player_id])
				room_id
					|> atomize()
					|> Room.leave(player)
				broadcast! socket, "player_left", %{body: player.name}
				{:shutdown, :left}	
		end
	end
	
	#####################
	# Utility functions #
	#####################
	
	defp atomize(str) when is_binary(str), do: String.to_atom(str)
	defp atomize(_), do: :error
	
	defp get_player_by_name(name) when is_binary(name) do
		Repo.get_by(Player, name: name)
	end
	defp get_player_by_name(_), do: :error
end