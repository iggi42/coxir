defmodule Coxir.API do
  @moduledoc """
  Used to interact with Discord's API while
  keeping track of all the ratelimits.
  """

  alias Coxir.API.Base

  @table :rates

  @doc false
  def create_tables do
    :ets.new @table, [:set, :public, :named_table]
  end

  def request(method, route, body \\ "", options \\ [], headers \\ []) do
    route
    |> route_param
    |> route_limit
    |> case do
      nil ->
        Base.request(method, route, body, headers, options)
        |> response(route)
      limit ->
        Process.sleep(limit)
        request(method, route, body, options, headers)
    end
  end

  defp response({_atom, struct}, route) do
    struct
    |> case do
      %{headers: headers, status_code: code} ->
        route = route
        |> route_param

        header = &headers
        |> List.keyfind(&1, 0)
        |> case do
          nil -> nil
          tup -> elem(tup, 1)
        end

        reset = header.("X-RateLimit-Reset")
        |> case do
          nil -> nil
          value ->
            String.to_integer(value) * 1000
        end

        remaining = header.("X-RateLimit-Remaining")
        |> case do
          nil -> nil
          value ->
            String.to_integer(value)
        end

        header.("X-RateLimit-Global")
        |> case do
          nil -> :ok
          _global ->
            retry = header.("Retry-After")
            |> String.to_integer

            route = :global
            reset = current_time() + retry
            remaining = 0
        end

        if reset && remaining do
          remote = header.("Date")
          |> date_header

          offset = (remote - current_time())
          |> abs

          {route, remaining, reset + offset}
          |> update_limit
        end

        body = struct
        |> Map.get(:body)
        |> case do
          nil -> nil
          body ->
            Jason.decode!(body, keys: :atoms)
        end

        cond do
          code in [204] ->
            :ok
          code in [200, 201, 304] ->
            body
          true ->
            %{error: body, code: code}
        end
      %{reason: reason} ->
        %{error: reason}
    end
  end

  defp route_param(route) do
    ~r/\/(channels|guilds)\/([0-9]{15,})+/i
    |> Regex.run(route)
    |> case do
      [match, _route, _param] ->
        match
      nil ->
        route
    end
  end

  defp route_limit(route) do
    remaining = route
    |> count_limit
    |> case do
      false ->
        route = :global
        count_limit(route)
        |> case do
          false -> 0
          count -> count
        end
      count ->
        count
    end

    cond do
      remaining < 0 ->
        case :ets.lookup(@table, route) do
          [{_route, _remaining, reset}] ->
            left = reset - current_time()
            if left > 0 do
              left
            else
              :ets.delete(@table, route)
              nil
            end
        end
      true -> nil
    end
  end

  defp count_limit(route) do
    try do
      :ets.update_counter(@table, route, {2, -1})
    rescue
      _ -> false
    end
  end

  defp update_limit({route, remaining, reset}) do
    # update: {route, remaining, reset}
    # stored: {index, _remaining, saved}
    # when index == route and reset > saved -> update
    # replaces the stored limit info when both guards are met
    fun = \
    [{
      {:"$1", :"$2", :"$3"},
      [{
        :andalso,
        {:==, :"$1", route},
        {:>, :"$3", reset}
      }],
      [{
        {route, remaining, reset}
      }]
    }]
    try do
      :ets.select_replace(@table, fun)
    rescue
      _ -> \
      :ets.insert_new(@table, {route, remaining, reset})
    end
  end

  defp current_time do
    DateTime.utc_now
    |> DateTime.to_unix(:milliseconds)
  end

  defp date_header(header) do
    header
    |> String.to_charlist
    |> :httpd_util.convert_request_date
    |> :calendar.datetime_to_gregorian_seconds
    |> :erlang.-(62_167_219_200)
    |> :erlang.*(1000)
  end
end
