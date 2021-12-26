defmodule TwitterSpaceDL do
  @moduledoc """
  Twitter Space Audio Downloader
  """

  require Logger
  use GenServer

  @user_agent "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.1 Safari/605.1.15"
  @audio_space_metadata_endpoint "https://twitter.com/i/api/graphql/Uv5R_-Chxbn1FEkyUkSW2w/AudioSpaceById"
  @live_video_stream_status_endpoint "https://twitter.com/i/api/1.1/live_video_stream/status/"

  # ets table keys
  @filename "filename"
  @filename_template "%{title}"
  @master_playlist "master_playlist"
  @dyn_url "dyn_url"
  @metadata "metadata"
  @guest_token "guest_token"

  def download(self_pid) do
    GenServer.call(self_pid, :download)
  end

  @impl true
  def init(arg = %{from_space_url: url}) do
    ets_table = :ets.new(:buckets_registry, [:set, :protected])
    template = Map.get(arg, :template, @filename_template)
    {:ok, %{space_id: from_space_url(url), ets_table: ets_table, template: template}}
  end

  @impl true
  def init(arg = %{from_space_id: space_id}) when is_binary(space_id) do
    ets_table = :ets.new(:buckets_registry, [:set, :protected])
    template = Map.get(arg, :template, @filename_template)
    {:ok, %{space_id: space_id, ets_table: ets_table, template: template}}
  end

  @impl true
  def handle_call(:download, _from, state = %{space_id: space_id, ets_table: ets_table}) do
    playlist = playlist_content(space_id, ets_table)
    {:reply, playlist, state}
  end

  defp from_space_url(url) when is_binary(url) do
    with [_, space_id | _] <- Regex.run(~r/spaces\/(\w+)/, url)
    do
      space_id
    else
      _ -> nil
    end
  end

  defp filename(space_id, ets_table, template) do
    with [[@filename, filename] | _] <- :ets.lookup(ets_table, @filename)
    do
      filename
    else
      {:ok, %{data: %{audioSpace: %{metadata: meta}}}} = metadata(space_id, ets_table)
      filename =
        ~r/\%\{(\w*)\}/
        |> Regex.scan(template)
        |> format_template(template, meta)
      true = :ets.insert(ets_table, {@filename, filename})
      filename
    end
  end

  defp format_template([], template, _meta), do: template
  defp format_template([[raw, key] | rest], template, meta) do
    format_template(rest,
      raw
      |> Regex.compile!()
      |> Regex.replace(template, Map.get(meta, String.to_atom(key), "")))
  end

  defp playlist_content(space_id, ets_table) do
    with {:ok, playlist_url} = playlist_url(space_id, ets_table),
         {:ok, master_url} = master_url(space_id, ets_table),
         url_base = Regex.replace(~r/master_playlist.m3u8.*/, master_url, ""),
         %HTTPotion.Response{body: body, status_code: 200} <-
           HTTPotion.get(playlist_url, follow_redirects: true)
    do
      Regex.replace(~r/chunk_/, body, "#{url_base}chunk_")
    else
      _ ->
        msg = "cannot fetch playlist: #{playlist_url}"
        Logger.error(msg)
        raise msg
    end
  end

  defp playlist_url(space_id, ets_table) do
    with {:ok, master_playlist} = master_url(space_id, ets_table),
         %HTTPotion.Response{body: body, status_code: 200} <-
           HTTPotion.get(master_playlist, follow_redirects: true),
         [_, _, _, suffix | _] <- String.split(body, "\n"),
         %URI{host: host} <- URI.parse(master_playlist),
         playlist <- "https://#{host}#{suffix}",
         true <- :ets.insert(ets_table, {@playlist_url, playlist})
    do
      {:ok, playlist}
    else
      _ ->
        msg = "cannot get the playlist url"
        Logger.error(msg)
        :error
    end
  end

  defp master_url(space_id, ets_table) do
    with [{@master_playlist, master_playlist} | _] <- :ets.lookup(ets_table, @master_playlist)
    do
      {:ok, master_playlist}
    else
      [] ->
        with {:ok, dyn_url} <- dyn_url(space_id, ets_table),
             master_playlist <- Regex.replace(~r/\/audio-space\/.*/, dyn_url, "/audio-space/master_playlist.m3u8"),
             true <- :ets.insert(ets_table, {@master_playlist, master_playlist})
        do
          {:ok, master_playlist}
        else
          _ ->
            msg = "cannot get dyn_url"
            Logger.error(msg)
            raise msg
        end
    end
  end

  defp dyn_url(space_id, ets_table) do
    with [{@dyn_url, dyn_url} | _] <- :ets.lookup(ets_table, @dyn_url)
    do
      {:ok, dyn_url}
    else
       [] ->
         {:ok, meta} = metadata(space_id, ets_table)
         case meta do
           %{data: %{audioSpace: %{metadata: %{state: "Ended", is_space_available_for_replay: false}}}} ->
             Logger.error("Space has ended but it is not available for replay")
             :error
           %{data: %{audioSpace: %{metadata: %{state: "Ended", is_space_available_for_replay: true, media_key: media_key}}}} ->
             status_url = @live_video_stream_status_endpoint <> media_key
             with %HTTPotion.Response{body: body, status_code: 200} <-
                    HTTPotion.get(status_url, follow_redirects: true, headers: [
                      authorization: get_authorization(),
                      cookie: "auth_token="
                    ]),
                  status <- Jason.decode!(body, keys: :atoms),
                  %{source: %{location: dyn_url}} <- status,
                  true <- :ets.insert(ets_table, {@dyn_url, dyn_url})
               do
               {:ok, dyn_url}
             else
               _ ->
                 Logger.error("Space is not available")
                 :error
             end
         end
    end
  end

  defp metadata(space_id, ets_table) when is_binary(space_id) do
    with [{@metadata, meta} | _] <- :ets.lookup(ets_table, @metadata)
    do
      {:ok, meta}
    else
      [] ->
        params = "?variables=%7B%22id%22%3A%22#{space_id}%22%2C%22isMetatagsQuery%22%3Atrue%2C%22withSuperFollowsUserFields%22%3Atrue%2C%22withBirdwatchPivots%22%3Afalse%2C%22withDownvotePerspective%22%3Afalse%2C%22withReactionsMetadata%22%3Afalse%2C%22withReactionsPerspective%22%3Afalse%2C%22withSuperFollowsTweetFields%22%3Atrue%2C%22withReplays%22%3Atrue%2C%22withScheduledSpaces%22%3Atrue%7D"
        get_url = @audio_space_metadata_endpoint <> params
        with %HTTPotion.Response{body: body, status_code: 200} <-
               HTTPotion.get(get_url, follow_redirects: true, headers: get_guest_header(ets_table)),
             meta <- Jason.decode!(body, keys: :atoms),
             %{data: %{audioSpace: %{metadata: %{media_key: media_key}}}} <- meta,
             true <- :ets.insert(ets_table, {@metadata, meta})
        do
          {:ok, meta}
        else
          _ ->
            Logger.error("cannot fetch metadata for space #{space_id}")
            raise "metadata not available"
        end
    end
  end

  defp get_authorization do
    "Bearer AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA"
  end

  defp get_guest_header(ets_table) do
    with {:ok, guest_token} <- guest_token(ets_table)
    do
      [
        authorization: get_authorization(),
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
    with [{@guest_token, guest_token}|_] <- :ets.lookup(ets_table, @guest_token)
    do
      Logger.info("cached guest_token: #{guest_token}")
      {:ok, guest_token}
    else
      _ ->
        with %HTTPotion.Response{body: body, status_code: 200} <-
               HTTPotion.get("https://twitter.com/", follow_redirects: true, headers: ["User-Agent": @user_agent]),
             [_, guest_token_str | _] <- Regex.run(~r/gt=(\d{19})/, body),
             true <- :ets.insert(ets_table, {@guest_token, guest_token_str})
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
