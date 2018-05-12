defmodule PokerEx.GameEngine.Seating do
  alias PokerEx.Player
  @capacity 6

  @type seat_number :: 0..6 | :empty
  @type arrangement :: [{String.t(), seat_number}] | []

  @type t :: %__MODULE__{
          arrangement: arrangement
        }

  defstruct arrangement: []

  defdelegate decode(value), to: PokerEx.GameEngine.Decoders.Seating

  def new do
    %__MODULE__{}
  end

  @spec join(PokerEx.GameEngine.Impl.t(), Player.t()) :: t()
  def join(%{seating: seating}, player) do
    with true <- length(seating.arrangement) < @capacity,
         false <- player.name in Enum.map(seating.arrangement, fn {name, _pos} -> name end) do
      {:ok, update_state(seating, [{:insert_player, player}])}
    else
      false ->
        {:error, :room_full}

      true ->
        {:error, :already_joined}
    end
  end

  @spec leave(PokerEx.GameEngine.Impl.t(), Player.name()) :: t()
  def leave(%{seating: seating}, player) do
    Map.put(
      seating,
      :arrangement,
      Enum.reject(seating.arrangement, fn {name, _} ->
        name == player
      end)
    )
  end

  @spec cycle(PokerEx.GameEngine.Impl.t()) :: t()
  def cycle(%{seating: seating}) do
    [hd | tail] = seating.arrangement
    %__MODULE__{seating | arrangement: tail ++ [hd]}
  end

  @spec is_player_seated?(PokerEx.GameEngine.Impl.t(), Player.name()) :: boolean
  def is_player_seated?(%{seating: %{arrangement: arrangement}}, player) do
    player in Enum.map(arrangement, fn {name, _} -> name end)
  end

  defp update_state(seating, updates) do
    Enum.reduce(updates, seating, &update(&1, &2))
  end

  defp update({:insert_player, player}, %{arrangement: arrangement} = seating) do
    new_arrangement =
      case Enum.drop_while(0..length(arrangement), fn num ->
             num in Enum.map(arrangement, fn {_, seat_num} -> seat_num end)
           end) do
        [] ->
          insert_player_at(arrangement, player.name, length(arrangement))

        [head | _] ->
          insert_player_at(arrangement, player.name, head)
      end

    Map.put(seating, :arrangement, new_arrangement)
  end

  defp insert_player_at(arrangement, player, missing_index) do
    case Enum.find_index(arrangement, fn {_, seat_num} -> seat_num == missing_index - 1 end) do
      nil ->
        case Enum.find_index(arrangement, fn {_, seat} -> seat == missing_index + 1 end) do
          nil ->
            [{player, missing_index}] ++ arrangement

          index ->
            {front, back} = Enum.split(arrangement, index)
            front ++ [{player, missing_index}] ++ back
        end

      index ->
        {front, back} = Enum.split(arrangement, index + 1)
        front ++ [{player, missing_index}] ++ back
    end
  end
end
