defmodule TwitterSpaceDL do
  @moduledoc """
  Twitter Space Audio Downloader
  """

  require Logger
  use GenServer

  @user_agent "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.1 Safari/605.1.15"
  @audio_space_metadata_endpoint "https://twitter.com/i/api/graphql/Uv5R_-Chxbn1FEkyUkSW2w/AudioSpaceById"

  def download(self_pid) do
    GenServer.call(self_pid, :download)
  end

  @impl true
  def init(%{from_space_url: url}) do
    ets_table = :ets.new(:buckets_registry, [:set, :protected])
    {:ok, %{space_id: from_space_url(url), ets_table: ets_table}}
  end

  @impl true
  def init(%{from_space_id: space_id}) when is_binary(space_id) do
    ets_table = :ets.new(:buckets_registry, [:set, :protected])
    {:ok, %{space_id: space_id, ets_table: ets_table}}
  end

  @impl true
  def handle_call(:download, _from, state = %{space_id: space_id, ets_table: ets_table}) do
    {:ok, meta} = metadata(space_id, ets_table)
    {:reply, meta, state}
  end

  defp from_space_url(url) when is_binary(url) do
    with [_, space_id | _] <- Regex.run(~r/spaces\/(\w+)/, url)
    do
      space_id
    else
      _ -> nil
    end
  end

  defp metadata(space_id, ets_table) when is_binary(space_id) do
    with [{"metadata", meta} | _] <- :ets.lookup(ets_table, "metadata")
    do
      meta
    else
      [] ->
        params = "?variables=%7B%22id%22%3A%22#{space_id}%22%2C%22isMetatagsQuery%22%3Atrue%2C%22withSuperFollowsUserFields%22%3Atrue%2C%22withBirdwatchPivots%22%3Afalse%2C%22withDownvotePerspective%22%3Afalse%2C%22withReactionsMetadata%22%3Afalse%2C%22withReactionsPerspective%22%3Afalse%2C%22withSuperFollowsTweetFields%22%3Atrue%2C%22withReplays%22%3Atrue%2C%22withScheduledSpaces%22%3Atrue%7D"
        get_url = @audio_space_metadata_endpoint <> params
        with %HTTPotion.Response{body: body, status_code: 200} <-
               HTTPotion.get(get_url, follow_redirects: true, headers: get_guest_header(ets_table)),
             meta = Jason.decode!(body),
             true <- :ets.insert(ets_table, {"metadata", meta})
        do
          meta
        else
          _ ->
            Logger.error("cannot fetch metadata for space #{space_id}")
            raise "metadata not available"
        end
    end
  end

  defp get_guest_header(ets_table) do
    with {:ok, guest_token} <- guest_token(ets_table)
    do
      [
        authorization: "Bearer AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA",
        "x-guest-token": "#{guest_token}"
      ]
    else
      [] ->
        true = guest_token(ets_table)
        get_guest_header(ets_table)
    end
  end

  defp guest_token(ets_table, retry_times \\ 5)
  defp guest_token(ets_table, retry_times) when retry_times >= 0 do
    with [{"guest_token", guest_token}|_] <- :ets.lookup(ets_table, "guest_token")
    do
      Logger.info("cached guest_token: #{guest_token}")
      {:ok, guest_token}
    else
      _ ->
        with %HTTPotion.Response{body: body, status_code: 200} <-
               HTTPotion.get("https://twitter.com/", follow_redirects: true, headers: ["User-Agent": @user_agent]),
             [_, guest_token_str | _] <- Regex.run(~r/gt=(\d{19})/, body),
             true <- :ets.insert(ets_table, {"guest_token", guest_token_str})
          do
          Logger.info("guest_token: #{guest_token_str}")
          {:ok, guest_token_str}
        else
          _ ->
            Logger.warn("guest_token not found, retrying... #{retry_times} times left")
            :timer.sleep(1000)
            guest_token(ets_table, retry_times - 1)
        end
    end
  end

  defp guest_token(_ets_table, retry_times) when retry_times < 0 do
    Logger.error("no guest_token found")
    raise "no guest_token found"
  end
end
