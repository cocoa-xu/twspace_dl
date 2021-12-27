defmodule TwitterSpaceDL do
  @moduledoc """
  Twitter Space Audio Downloader
  """

  require Logger
  use GenServer

  @user_agent "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.1 Safari/605.1.15"
  @audio_space_metadata_endpoint "https://twitter.com/i/api/graphql/Uv5R_-Chxbn1FEkyUkSW2w/AudioSpaceById"
  @live_video_stream_status_endpoint "https://twitter.com/i/api/1.1/live_video_stream/status/"
  @user_by_screen_name_endpoint "https://twitter.com/i/api/graphql/1CL-tn62bpc-zqeQrWm4Kw/UserByScreenName"
  @user_tweets_endpoint "https://twitter.com/i/api/graphql/jpCmlX6UgnPEZJknGKbmZA/UserTweets"

  @filename_template "%{title}"

  # ets table keys
  @filename "filename"
  @master_playlist "master_playlist"
  @dyn_url "dyn_url"
  @metadata "metadata"
  @guest_token "guest_token"

  @doc """
  New Twitter Space downloader

  - **source**: specify the space source
    - `:space_url`.

      For example, `"https://twitter.com/i/spaces/1OyJADqBEgDGb"`

    - `:space_id`.

      For example, `"1OyJADqBEgDGb"`

  - **opts**: keyword options
    - **show_ffmpeg_output**: forward FFmpeg output to IO.puts

      Default value: `false`

    - **save_dir**: set download directory

      Default value: `__DIR__`

    - **template**: filename template

      Default value: `"%{title}"`. Valid keys are:

      - `title`.
      - `created_at`.
      - `ended_at`.
      - `rest_id`.
      - `started_at`.
      - `total_participated`.
      - `total_replay_watched`.
      - `updated_at`.

    - **plugin_module**: name of the plugin module. The module should implement `TwitterSpaceDL.Plugin`

  **Return**: `pid`

  ## Example
  Download by space url
  ```elixir
  space = TwitterSpaceDL.new!(:space_url, "https://twitter.com/i/spaces/1OyJADqBEgDGb")
  # download synchronously
  TwitterSpaceDL.download(space)
  # download asynchronously
  TwitterSpaceDL.async_download(space)
  ```

  Download by space id and display ffmpeg output
  ```elixir
  space = TwitterSpaceDL.new!(:space_id, "1OyJADqBEgDGb", show_ffmpeg_output: true)
  # download synchronously
  TwitterSpaceDL.download(space)
  # download asynchronously
  TwitterSpaceDL.async_download(space)
  ```

  Download by space id, use custom filename template and save to `download` directory
  ```elixir
  space = TwitterSpaceDL.new!(:space_id, "1OyJADqBEgDGb",
    template: "space-%{title}-%{rest_id}-%{created_at}",
    save_dir: "./download")
  # download synchronously
  TwitterSpaceDL.download(space)
  # download asynchronously
  TwitterSpaceDL.async_download(space)
  ```

  Init by username, use custom filename template and use plugin module
  ```elixir
  space = TwitterSpaceDL.new!(:user, "LaplusDarknesss",
    template: "space-%{title}-%{rest_id}",
    plugin_module: TwitterSpaceDL.Plugin.CLI)

  # you can call this again to download new spaces (if space archive is available)
  # download synchronously
  TwitterSpaceDL.download(space)
  # download asynchronously
  TwitterSpaceDL.async_download(space)
  ```
  """
  def new!(source, source_arg, opts \\ default_opts()) do
    {:ok, pid} = new(source, source_arg, opts)
    pid
  end

  @doc """
  New Twitter Space downloader

  Please check `new!` for full information

  ## Example
  Download by space url
  ```elixir
  {:ok, space} = TwitterSpaceDL.new(:space_url, "https://twitter.com/i/spaces/1OyJADqBEgDGb")
  TwitterSpaceDL.download(space)
  ```
  """
  def new(source, source_arg, opts \\ default_opts())

  def new(:space_id, id, opts) do
    GenServer.start(__MODULE__, %{from_space_id: id, opts: sanitize_opts(opts)})
  end

  def new(:space_url, url, opts) do
    GenServer.start(__MODULE__, %{from_space_url: url, opts: sanitize_opts(opts)})
  end

  def new(:user, username, opts) do
    GenServer.start(__MODULE__, %{from_username: username, opts: sanitize_opts(opts)})
  end

  defp default_opts do
    [
      {:template, @filename_template},
      {:save_dir, __DIR__},
      {:show_ffmpeg_output, false}
    ]
  end

  defp sanitize_opts(opts) do
    default_opts()
    |> Enum.reduce([], fn {k, v}, acc ->
      value = opts[k] || v
      Keyword.put_new(acc, k, value)
    end)
  end

  defp ensure_ffmpeg do
    if nil == System.find_executable("ffmpeg") do
      raise "cannot find ffmpeg"
    end
  end

  @doc """
  Download Twitter Space audio recording
  """
  def download(self_pid) do
    ensure_ffmpeg()
    GenServer.call(self_pid, :download, :infinity)
  end

  @doc """
  Download Twitter Space audio recording asynchronously
  """
  def async_download(self_pid, callback_pid) do
    ensure_ffmpeg()
    GenServer.cast(self_pid, {:download, callback_pid})
  end

  @impl true
  def init(arg = %{from_space_url: url}) when is_binary(url) do
    opts = Map.get(arg, :opts, default_opts())
    {:ok, %{space_id: from_space_url(url), opts: opts}}
  end

  @impl true
  def init(arg = %{from_space_id: space_id}) when is_binary(space_id) do
    opts = Map.get(arg, :opts, default_opts())
    {:ok, %{space_id: space_id, opts: opts}}
  end

  @impl true
  def init(arg = %{from_username: username}) when is_binary(username) do
    opts = Map.get(arg, :opts, default_opts())
    {:ok, %{username: username, opts: opts}}
  end

  @impl true
  def handle_call(:download, _from, state = %{space_id: _space_id}) do
    {download_results, ets_table} = download_by_id(state)
    state = Map.put(state, :ets_table, ets_table)
    {:reply, download_results, state}
  end

  @impl true
  def handle_call(:download, _from, state = %{username: _username}) do
    case download_by_user(state)
    do
      {:ok, download_results, ets_table} ->
        state = Map.put(state, :ets_table, ets_table)
        {:reply, download_results, state}
      other ->
        {:reply, other, state}
    end
  end

  @impl true
  def handle_cast({:download, callback_pid}, state = %{space_id: space_id}) do
    self_pid = self()
    child = spawn(fn ->
      send(callback_pid, {self_pid, %{space_id: space_id}, download_by_id(state)})
    end)
    send(callback_pid, {self_pid, child})

    {:noreply, state}
  end

  @impl true
  def handle_cast({:download, callback_pid}, state = %{username: username}) do
    self_pid = self()
    child = spawn(fn ->
      send(callback_pid, {self_pid, %{username: username}, download_by_user(state)})
    end)
    send(callback_pid, {self_pid, child})

    {:noreply, state}
  end

  defp from_space_url(url) when is_binary(url) do
    with [_, space_id | _] <- Regex.run(~r/spaces\/(\w+)/, url) do
      space_id
    else
      _ ->
        msg = "cannot find space id from given url: #{url}"
        Logger.error(msg)
        raise msg
    end
  end

  defp ffmpeg_arg(input, output, title) do
    [
      "-hide_banner",
      "-y",
      "-stats",
      "-v",
      "warning",
      "-i",
      input,
      "-c",
      "copy",
      "-metadata",
      "title=#{title}",
      output
    ]
  end

  defp download_by_id(state = %{space_id: space_id, opts: opts}) do
    ets_table = case Map.get(state, :ets_table)
    do
        nil -> :ets.new(:twspace_dl, [:set, :protected])
        tab -> tab
    end
    template = opts[:template]
    save_dir = opts[:save_dir]
    File.mkdir_p!(save_dir)
    playlist = playlist_content(space_id, ets_table, opts)
    filename = filename(space_id, ets_table, template, opts)
    dyn_playlist = dyn_url(space_id, ets_table, opts)

    {:ok, %{data: %{audioSpace: %{metadata: %{state: space_state, title: title}}}}} =
      metadata(space_id, ets_table, opts)

    download_results = _download(
      System.find_executable("ffmpeg"),
      filename,
      playlist,
      dyn_playlist,
      title,
      space_state,
      save_dir,
      opts
    )

    {download_results, ets_table}
  end

  defp download_by_user(state = %{username: username, opts: opts}) do
    ets_table = case Map.get(state, :ets_table)
    do
      nil -> :ets.new(:twspace_dl, [:set, :protected])
      tab -> tab
    end
    with {:ok, %{data: %{user: %{result: %{rest_id: user_id}}}}} <-
           userinfo(username, ets_table, opts),
         {:ok, tweets} <- recent_tweets(user_id, ets_table, opts) do
      case Regex.scan(~r/https:\/\/twitter.com\/i\/spaces\/\w*/, tweets) do
        [] ->
          Logger.info("no space tweets found for user_id: #{user_id}")
          {:ok, [], ets_table}

        space_urls ->
          Logger.info("found #{Enum.count(space_urls)} space tweets for user_id: #{user_id}")

          space_urls =
            to_plugin_module(opts[:plugin_module], {:space_urls, 0}, space_urls, username, nil)

          total = Enum.count(space_urls)

          results =
            space_urls
            |> Enum.with_index(1)
            |> Enum.map(fn {[space_url], index} ->
              Logger.info("[#{index}/#{total}] user_id: #{user_id} url: #{space_url}")

              with {:ok, space} <- TwitterSpaceDL.new(:space_url, space_url, opts) do
                if Enum.count(:ets.lookup(ets_table, space_url)) == 0 do
                  ret = TwitterSpaceDL.download(space)

                  if ret == :ok do
                    :ets.insert(ets_table, {space_url, true})
                    {space_url, :ok}
                  else
                    {space_url, ret}
                  end
                else
                  Logger.info(
                    "[#{index}/#{total}] user_id: #{user_id} url: #{space_url}, already downloaded"
                  )

                  {space_url, :already_downloaded}
                end
              else
                ret -> {space_url, ret}
              end
            end)

          {:ok, results, ets_table}
      end
    else
      _ ->
        :ets.delete(ets_table)
        reason = "cannot find rest_id for user: #{username}"
        Logger.error(reason)
        {:error, reason}
    end
  end

  defp _download(
         ffmpeg,
         filename,
         playlist,
         dyn_playlist,
         title,
         space_state,
         save_dir,
         show_ffmpeg_output
       ) do
    m3u8_filename = write_playlist(filename, playlist)
    m4a_filename = filename <> ".m4a"
    m4a_live_filename = filename <> "_live.m4a"
    concat_txt = "#{title}-concat.txt"

    download_recorded =
      ffmpeg_arg(m3u8_filename, m4a_filename, title)
      |> List.insert_at(1, "-protocol_whitelist")
      |> List.insert_at(2, "file,https,tls,tcp")

    pipeline =
      if space_state == "Running" do
        {:ok, file} = File.open(concat_txt, [:write])
        save_dir_abs = Path.expand(save_dir)
        :ok = IO.binwrite(file, "file " <> Path.join(save_dir_abs, m4a_filename) <> "\n")
        :ok = IO.binwrite(file, "file " <> Path.join(save_dir_abs, m4a_live_filename) <> "\n")
        :ok = File.close(file)
        download_live = ffmpeg_arg(dyn_playlist, m4a_live_filename, title)

        merge_file =
          ffmpeg_arg(concat_txt, m4a_filename, title)
          |> List.insert_at(1, "-f")
          |> List.insert_at(2, "concat")
          |> List.insert_at(3, "-safe")
          |> List.insert_at(4, "0")

        [download_live, download_recorded, merge_file]
      else
        [download_recorded]
      end

    :ok = _download(ffmpeg, pipeline, show_ffmpeg_output)

    # cleanup
    if space_state == "Running" do
      File.rm!(concat_txt)
      File.rm!(m4a_live_filename)
    end

    :ok
  end

  defp _download(_ffmpeg, [], _show_ffmpeg_output), do: :ok

  defp _download(ffmpeg, [args | rest], show_ffmpeg_output) do
    port =
      Port.open(
        {:spawn_executable, ffmpeg},
        [:binary, :exit_status, args: args]
      )

    receive do
      {^port, {:exit_status, 0}} ->
        nil

      {^port, {:exit_status, status}} ->
        Logger.warn("ffmpeg exit with status: #{status}")

      {^port, {:data, stdout}} ->
        if show_ffmpeg_output, do: IO.puts(Regex.replace(~r/\n/, stdout, "\r\n"))
    end

    _download(ffmpeg, rest, show_ffmpeg_output)
  end

  defp filename(space_id, ets_table, template, opts) do
    with [[@filename, filename] | _] <- :ets.lookup(ets_table, @filename) do
      filename
    else
      [] ->
        {:ok, %{data: %{audioSpace: %{metadata: meta}}}} = metadata(space_id, ets_table, opts)

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
    format_template(
      rest,
      raw
      |> Regex.compile!()
      |> Regex.replace(template, Map.get(meta, String.to_atom(key), "")),
      meta
    )
  end

  defp write_playlist(formatted_filename, playlist) do
    output_filename = formatted_filename <> ".m3u8"
    {:ok, file} = File.open(output_filename, [:write])
    :ok = IO.binwrite(file, playlist)
    :ok = File.close(file)
    output_filename
  end

  defp playlist_content(space_id, ets_table, opts) do
    {:ok, playlist_url_str} = playlist_url(space_id, ets_table, opts)

    ret_val =
      with {:ok, master_url} = master_url(space_id, ets_table, opts),
           url_base = Regex.replace(~r/master_playlist.m3u8.*/, master_url, ""),
           %HTTPotion.Response{body: body, status_code: 200} <-
             HTTPotion.get(playlist_url_str, follow_redirects: true) do
        Regex.replace(~r/chunk_/, body, "#{url_base}chunk_")
      else
        _ ->
          reason = "cannot fetch playlist: #{playlist_url_str} for space_id: #{space_id}"
          Logger.error(reason)
          {:error, reason}
      end

    to_plugin_module(opts[:plugin_module], __ENV__.function, ret_val, nil, space_id)
  end

  defp playlist_url(space_id, ets_table, opts) do
    ret_val =
      with {:ok, master_playlist} = master_url(space_id, ets_table, opts),
           %HTTPotion.Response{body: body, status_code: 200} <-
             HTTPotion.get(master_playlist, follow_redirects: true),
           [_, _, _, suffix | _] <- String.split(body, "\n"),
           %URI{host: host} <- URI.parse(master_playlist),
           playlist <- "https://#{host}#{suffix}" do
        {:ok, playlist}
      else
        _ ->
          reason = "cannot get the playlist url"
          Logger.error(reason)
          {:error, reason}
      end

    to_plugin_module(opts[:plugin_module], __ENV__.function, ret_val, nil, space_id)
  end

  defp master_url(space_id, ets_table, opts) do
    ret_val =
      with [{@master_playlist, master_playlist} | _] <- :ets.lookup(ets_table, @master_playlist) do
        {:ok, master_playlist}
      else
        [] ->
          with {:ok, dyn_url} <- dyn_url(space_id, ets_table, opts),
               master_playlist <-
                 Regex.replace(
                   ~r/\/audio-space\/.*/,
                   dyn_url,
                   "/audio-space/master_playlist.m3u8"
                 ),
               true <- :ets.insert(ets_table, {@master_playlist, master_playlist}) do
            {:ok, master_playlist}
          else
            _ ->
              reason = "cannot get dyn_url"
              Logger.error(reason)
              {:error, reason}
          end
      end

    to_plugin_module(opts[:plugin_module], __ENV__.function, ret_val, nil, space_id)
  end

  defp dyn_url(space_id, ets_table, opts) do
    ret_val =
      with [{@dyn_url, dyn_url} | _] <- :ets.lookup(ets_table, @dyn_url) do
        {:ok, dyn_url}
      else
        [] ->
          {:ok, meta} = metadata(space_id, ets_table, opts)

          case meta do
            %{
              data: %{
                audioSpace: %{metadata: %{state: "Ended", is_space_available_for_replay: false}}
              }
            } ->
              reason = "Space has ended but it is not available for replay"
              Logger.error(reason)
              {:error, reason}

            %{
              data: %{
                audioSpace: %{
                  metadata: %{
                    state: "Ended",
                    is_space_available_for_replay: true,
                    media_key: media_key
                  }
                }
              }
            } ->
              status_url = @live_video_stream_status_endpoint <> media_key

              with %HTTPotion.Response{body: body, status_code: 200} <-
                     HTTPotion.get(status_url,
                       follow_redirects: true,
                       headers: [
                         authorization: get_authorization(opts),
                         cookie: "auth_token="
                       ]
                     ),
                   status <- Jason.decode!(body, keys: :atoms),
                   %{source: %{location: dyn_url}} <- status,
                   true <- :ets.insert(ets_table, {@dyn_url, dyn_url}) do
                {:ok, dyn_url}
              else
                _ ->
                  reason = "Space(#{space_id}) is not available"
                  Logger.error(reason)
                  {:error, reason}
              end
          end
      end

    to_plugin_module(opts[:plugin_module], __ENV__.function, ret_val, nil, space_id)
  end

  defp metadata(space_id, ets_table, opts) when is_binary(space_id) do
    ret_val =
      with [{@metadata, meta} | _] <- :ets.lookup(ets_table, @metadata) do
        {:ok, meta}
      else
        [] ->
          get_url =
            @audio_space_metadata_endpoint <>
              "?variables=" <>
              (%{
                 id: space_id,
                 isMetatagsQuery: false,
                 withSuperFollowsUserFields: true,
                 withBirdwatchPivots: false,
                 withDownvotePerspective: false,
                 withReactionsMetadata: false,
                 withReactionsPerspective: false,
                 withSuperFollowsTweetFields: true,
                 withReplays: true,
                 withScheduledSpaces: true
               }
               |> Jason.encode!()
               |> URI.encode(fn _ -> false end))

          with %HTTPotion.Response{body: body, status_code: 200} <-
                 HTTPotion.get(get_url,
                   follow_redirects: true,
                   headers: get_guest_header(ets_table, opts)
                 ),
               meta <- Jason.decode!(body, keys: :atoms),
               %{data: %{audioSpace: %{metadata: %{media_key: _media_key}}}} <- meta,
               true <- :ets.insert(ets_table, {@metadata, meta}) do
            {:ok, meta}
          else
            _ ->
              reason = "cannot fetch metadata for space #{space_id}: #{get_url}"
              Logger.error(reason)
              {:error, reason}
          end
      end

    to_plugin_module(opts[:plugin_module], __ENV__.function, ret_val, nil, space_id)
  end

  defp to_plugin_module(nil, _func, result, _username, _space_id), do: result

  defp to_plugin_module(plugin_module, {func_name, _}, result, username, space_id) do
    if plugin_module != nil and function_exported?(plugin_module, func_name, 3) do
      case apply(plugin_module, func_name, [result, username, space_id]) do
        {:ok, maybe_modified_result} -> maybe_modified_result
        {:stop, reason} -> exit({:by_plugin_module, reason})
        :stop -> exit({:by_plugin_module, nil})
      end
    else
      result
    end
  end

  defp userinfo(username, ets_table, opts) do
    get_url =
      @user_by_screen_name_endpoint <>
        "?variables=" <>
        (%{
           screen_name: username,
           withSafetyModeUserFields: true,
           withSuperFollowsUserFields: true,
           withNftAvatar: false
         }
         |> Jason.encode!()
         |> URI.encode(fn _ -> false end))

    ret_val =
      with %HTTPotion.Response{body: body, status_code: 200} <-
             HTTPotion.get(get_url,
               follow_redirects: true,
               headers: get_guest_header(ets_table, opts)
             ),
           {:ok, info} <- Jason.decode(body, keys: :atoms) do
        {:ok, info}
      else
        _ ->
          reason = "cannot fetch userinfo for user: #{username}"
          Logger.error(reason)
          {:error, reason}
      end

    to_plugin_module(opts[:plugin_module], __ENV__.function, ret_val, username, nil)
  end

  defp recent_tweets(user_id, ets_table, opts) do
    get_url =
      @user_tweets_endpoint <>
        "?variables=" <>
        (%{
           userId: user_id,
           count: 20,
           withTweetQuoteCount: true,
           includePromotedContent: true,
           withQuickPromoteEligibilityTweetFields: true,
           withSuperFollowsUserFields: true,
           withUserResults: true,
           withNftAvatar: false,
           withBirdwatchPivots: false,
           withReactionsMetadata: false,
           withReactionsPerspective: false,
           withSuperFollowsTweetFields: true,
           withVoice: true
         }
         |> Jason.encode!()
         |> URI.encode(fn _ -> false end))

    ret_val =
      with %HTTPotion.Response{body: body, status_code: 200} <-
             HTTPotion.get(get_url,
               follow_redirects: true,
               headers: get_guest_header(ets_table, opts)
             ) do
        {:ok, body}
      else
        _ ->
          reason = "cannot fetch recent tweets for user_id: #{user_id}"
          Logger.error(reason)
          {:error, reason}
      end

    to_plugin_module(opts[:plugin_module], __ENV__.function, ret_val, nil, nil)
  end

  defp get_authorization(opts) do
    auth =
      "Bearer AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA"

    to_plugin_module(opts[:plugin_module], __ENV__.function, auth, nil, nil)
  end

  defp get_guest_header(ets_table, opts) do
    ret_val =
      with {:ok, guest_token} <- guest_token(ets_table, opts) do
        [
          authorization: get_authorization(opts),
          "x-guest-token": "#{guest_token}"
        ]
      else
        [] ->
          true = guest_token(ets_table, opts)
          get_guest_header(ets_table, opts)
      end

    to_plugin_module(opts[:plugin_module], __ENV__.function, ret_val, nil, nil)
  end

  defp guest_token(ets_table, opts, retry_times \\ 5)

  defp guest_token(ets_table, opts, retry_times) when retry_times >= 0 do
    ret_val =
      with [{@guest_token, guest_token} | _] <- :ets.lookup(ets_table, @guest_token) do
        Logger.info("cached guest_token: #{guest_token}")
        {:ok, guest_token}
      else
        _ ->
          with %HTTPotion.Response{body: body, status_code: 200} <-
                 HTTPotion.get("https://twitter.com/",
                   follow_redirects: true,
                   headers: ["User-Agent": @user_agent]
                 ),
               [_, guest_token_str | _] <- Regex.run(~r/gt=(\d{19})/, body),
               true <- :ets.insert(ets_table, {@guest_token, guest_token_str}) do
            Logger.info("guest_token: #{guest_token_str}")
            {:ok, guest_token_str}
          else
            _ ->
              Logger.warn("guest_token not found, retrying... #{retry_times} times left")
              :timer.sleep(1000)
              guest_token(ets_table, opts, retry_times - 1)
          end
      end

    to_plugin_module(opts[:plugin_module], __ENV__.function, ret_val, nil, nil)
  end

  defp guest_token(_ets_table, _opts, retry_times) when retry_times < 0 do
    reason = "no guest_token found"
    Logger.error(reason)
    {:error, reason}
  end
end
