defmodule PokerEx.TableManager do
	use GenServer
	
	alias PokerEx.Room
	alias PokerEx.TableState, as: State
	
	@name :table_manager
	
	def start_link(players) do
		GenServer.start_link(__MODULE__, [players], name: @name)
	end
	
	#######################
	# Interface functions #
	#######################
	
	def seat_player(player) do
		GenServer.cast(@name, {:seat_player, player})
	end
	
	def remove_player(player) do
		GenServer.call(@name, {:remove_player, player})
	end
	
	def start_round do
		GenServer.call(@name, :start_round)
	end
	
	def advance do
		GenServer.call(@name, :advance)
	end
	
	def get_active do
		GenServer.call(@name, :get_active)
	end
	
	def get_big_blind do
		GenServer.call(@name, :get_big_blind)
	end
	
	def get_small_blind do
		GenServer.call(@name, :get_small_blind)
	end
	
	def get_all_in do
		GenServer.call(@name, :get_all_in)
	end
	
	def players_only do
		GenServer.call(@name, :players_only)
	end
	
	def fold(player) do
		GenServer.call(@name, {:fold, player})
	end
	
	def all_in(player) do
		GenServer.cast(@name, {:all_in, player})
	end
	
	def clear_round do
		GenServer.call(@name, :clear_round)
	end
	
	def reset_turns do
		GenServer.call(@name, :reset_turns)
	end
	
	def	fetch_data do
		GenServer.call(@name, :fetch_data)
	end
	
	#############
	# Callbacks #
	#############
	
	def init([players]) do
		send(self(), {:setup, players})
		{:ok, %State{}}
	end
	
	
			########################
			# Seating and removing #
			########################
	
	def handle_cast({:seat_player, player}, data) do
		seat_number = length(data.seating)
		seating = [{player, seat_number}|Enum.reverse(data.seating)] |> Enum.reverse
		update = %State{ data | seating: seating, length: length(seating)}
		{:noreply, update}
	end
	
	def handle_call({:remove_player, player}, _from, %State{seating: seating, active: active, current_player: cp, next_player: np} = data) do
		new_seating = Enum.map(seating, fn {pl, _} -> pl end) |> Enum.reject(fn pl -> pl == player end) |> Enum.with_index
		case active do
			[] ->
				update = %State{ data | seating: new_seating}
				{:reply, update, update}
			_ ->
				[head|tail] = active
				update = %State{ data | seating: new_seating, active: tail, current_player: hd(tail)}
				{:reply, update, update}
		end
	end
		
			#####################
			# Position tracking #
			#####################
			
	def handle_call(:start_round, _from, %State{seating: seating, big_blind: nil, small_blind: nil} = data) do
		# Remove any players who have run out of chips
		[{big_blind, 0}, {small_blind, 1}|rest] = seating
		
		case length(rest) do
			x when x >= 2 ->
				[current, next|_] = rest
				update = %State{ data | active: rest ++ [{small_blind, 1}, {big_blind, 0}], current_player: current, next_player: next,
					big_blind: big_blind, small_blind: small_blind, current_big_blind: 0, current_small_blind: 1
				}
				{:reply, update, update}
			x when x == 1 ->
				[current|_] = rest
				update = %State{ data | active: rest ++ [{small_blind, 1}, {big_blind, 0}], current_player: current, next_player: {small_blind, 1},
					big_blind: big_blind, small_blind: small_blind, current_big_blind: 0, current_small_blind: 1
				}
				{:reply, update, update}
			x when x == 0 ->
				update = %State{ data | active: [{small_blind, 1}, {big_blind, 0}], current_player: {small_blind, 1}, next_player: {big_blind, 0},
					big_blind: big_blind, small_blind: small_blind, current_big_blind: 0, current_small_blind: 1
				}
				{:reply, update, update}
		end
	end
	
	def handle_call(:start_round, _from, %State{seating: seating} = data) do
		out_of_chips = PokerEx.AppState.players |> Enum.map(
			fn %PokerEx.Player{name: name, chips: chips} -> 
				if chips == 0, do: name, else: nil
			end
			)
		seating = Enum.reject(seating, fn {player, _} -> player in out_of_chips end)
		[{big_blind, num}, {small_blind, num2}|_rest] = seating
		
		current_player = 
			case Enum.any?(seating, fn {_, seat} -> seat > num2 end) do
				true -> Enum.find(seating, fn {_, seat} ->  seat == num2 + 1 end)
				_ -> Enum.find(seating, fn {_, seat} -> seat == 0 end)
			end
		
		next_player = 
			case current_player do
				{_, 0} -> Enum.find(seating, fn {_, seat} -> seat == 1 end)
				_ -> 
					if Enum.any?(seating, fn {_, seat} -> seat > num2 + 1 end) do
						Enum.find(seating, fn {_, seat} -> seat == num2 + 2 end)
					else
						Enum.find(seating, fn {_, seat} -> seat == 0 end)
					end
			end
		
		update = %State{ data | active: seating, current_player: current_player, next_player: next_player,
				big_blind: big_blind, small_blind: small_blind, current_big_blind: num, current_small_blind: num2
			}
		{:reply, update, update}
	end
	
	def handle_call(:advance, _from, %State{active: active, all_in: all_in} = data) do
		leader_all_in? = hd(active) in all_in
		case length(active) do
			x when x >= 3 ->
				[current, next, on_deck|_rest] = active
				[head|tail] = active
				update = %State{ data | current_player: next, next_player: on_deck}
				update = if leader_all_in?, do: %State{ update | active: tail}, else: %State{ update | active: tail ++ [head]}
				{:reply, "#{inspect(next)} is up", update}
			x when x == 2 ->
				[current, next] = active
				update = %State{ data | current_player: next, next_player: current}
				update = if leader_all_in?, do: %State{ update | active: [next]}, else: %State{ update | active: [next, current]}
				{:reply, "#{inspect(next)} is up", update}
			x when x == 1 ->
				{:reply, "Cannot advance. Only one player is active", data}
			x when x == 0 ->
				{:reply, data, data}
		end
	end
	
	def handle_call(:reset_turns, _from, data) do
		update = first_turn(data)
		next_player = next_player(update, update.current_player)
		update = %State{ update | next_player: next_player}
		{:reply, update, update}
	end
	
			################
			# Player calls #
			################
	
	def handle_call({:fold, player}, _from, %State{active: active, current_player: {pl, _}} = data) when player == pl do
		[current|rest] = active
		[head|tail] = rest
		case length(tail) do
			x when x >= 1 ->
				update = %State{ data | active: rest, current_player: head, next_player: hd(tail)}
				{:reply, update, update}
			_ ->
				update = %State{ data | active: rest, current_player: head, next_player: nil}
				{:reply, update, update}
		end
	end
	
	def handle_call({:fold, _}, _, _), do: raise "Illegal operation"
	
	def handle_cast({:all_in, player}, %State{active: active, current_player: {pl, seat}, all_in: ai} = data) do
		update = %State{ data | all_in: ai ++ [{player, seat}]}
		{:noreply, update}
	end
	
			#########
			# Clear #
			#########
	
	def handle_call(:clear_round, _from, %State{seating: seating, small_blind: sb, current_small_blind: csb} = state) do
		[head|tail] = seating
		{new_sb, new_csb} = next_seated(state, {sb, csb})
		update = %State{seating: tail ++ [head], big_blind: sb, current_big_blind: csb, small_blind: new_sb, current_small_blind: new_csb}
		{:reply, update, update}
	end
	
			#################
			# Data fetchers #
			#################
			
	def handle_call(:get_active, _from, %State{active: active} = data) do
		{:reply, active, data}
	end
			
	def handle_call(:fetch_data, _from, data), do: {:reply, data, data}
	
	def handle_call(:get_big_blind, _from, %State{big_blind: big_blind} = data) do
		{:reply, big_blind, data}
	end
	
	def handle_call(:get_small_blind, _from, %State{small_blind: small_blind} = data) do
		{:reply, small_blind, data}
	end
	
	def handle_call(:get_all_in, _from, %State{all_in: all_in} = data) do
		{:reply, all_in, data}
	end
	
	def handle_call(:players_only, _from, %State{active: active} = data) do
		players = for {player, _} <- active, do: player
		{:reply, players, data}
	end
	
			#########
			# Setup #
			#########
			
	def handle_info({:setup, players}, _state) do
		data = %State{seating: Enum.with_index(players)}
		{:noreply, data}
	end
	
			#############
			# Catch all #
			#############
	
	def handle_info(event_content, data) do
		IO.puts "\nReceived unknown message: \n"
		IO.inspect(event_content)
		IO.inspect(data)
		IO.puts "\n"
		{:noreply, data}
	end
	
	#####################
	# Utility functions #
	#####################
	
	defp next_player(%State{active: active, next_player: {_player, seat}}) do
			case Enum.drop_while(active, fn {_, num} -> num <= seat end) do
				[] -> List.first(active)
				[{pl, s}|_rest] -> {pl, s}
				_ -> raise ArgumentError
			end
	end
	
	defp next_player(%State{active: active}, {_player, seat}) do
			case Enum.drop_while(active, fn {_, num} -> num <= seat end) do
				[] -> List.first(active)
				[{pl, s}|_rest] -> {pl, s}
				_ -> raise "Something went wrong"
			end
	end
	
	defp next_seated(%State{seating: seating}, {_player, seat}) do
			case Enum.drop_while(seating, fn {_, num} -> num <= seat end) do
				[] -> List.first(seating)
				[{pl, s}|_rest] -> {pl, s}
				_ -> raise "Something went wrong"
			end
	end
	
	defp first_turn(%State{active: active, big_blind: big_blind} = state) do
		case Enum.find(active, fn {pl, _num} -> big_blind == pl end) do
			true -> %State{ state | current_player: {big_blind, state.current_big_blind}}
			_ -> %State{ state | current_player: next_player(state, {big_blind, state.current_big_blind})}
		end
	end
end