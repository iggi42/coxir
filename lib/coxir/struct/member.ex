defmodule Coxir.Struct.Member do
  use Coxir.Struct

  alias Coxir.Struct.{User, Channel}

  def pretty(struct) do
    struct
    |> replace(:user, &User.get/1)
    |> replace(:voice_id, &Channel.get/1)
  end

  def edit(%{id: id}, params),
    do: edit(id, params)

  def edit({guild, user}, params) do
    API.request(:patch, "guilds/#{guild}/members/#{user}", params)
  end

  def kick(%{id: id}),
    do: kick(id)

  def kick({guild, user}) do
    API.request(:delete, "guilds/#{guild}/members/#{user}")
  end

  def ban(%{id: id}, query),
    do: ban(id, query)

  def ban({guild, user}, query) do
    API.request(:put, "guilds/#{guild}/bans/#{user}", "", params: query)
  end

  def add_role(%{id: id}, role),
    do: add_role(id, role)

  def add_role({guild, user}, role) do
    API.request(:put, "guilds/#{guild}/members/#{user}/roles/#{role}")
  end

  def remove_role(%{id: id}, role),
    do: remove_role(id, role)

  def remove_role({guild, user}, role) do
    API.request(:delete, "guilds/#{guild}/members/#{user}/roles/#{role}")
  end
end
