defmodule TwitterSpaceDL do
  @moduledoc """
  Twitter Space Audio Downloader
  """

  require Logger
  use GenServer

  @user_agent "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.1 Safari/605.1.15"
  @audio_space_metadata_endpoint "https://twitter.com/i/api/graphql/Uv5R_-Chxbn1FEkyUkSW2w/AudioSpaceById"
  @live_video_stream_status_endpoint "https://twitter.com/i/api/1.1/live_video_stream/status/"

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

  **Return**: `pid`

  ## Example
  Download by space url
  ```elixir
  space = TwitterSpaceDL.new(:space_url, "https://twitter.com/i/spaces/1OyJADqBEgDGb")
  TwitterSpaceDL.download(space)
  ```

  Download by space id
  ```elixir
  space = TwitterSpaceDL.new(:space_id, "1OyJADqBEgDGb")
  TwitterSpaceDL.download(space)
  ```

  Download by space id, use custom filename template and save to `download` directory
  ```elixir
  space = TwitterSpaceDL.new(:space_id, "1OyJADqBEgDGb", "space-%{title}-%{rest_id}-%{created_at}", "./download")
  TwitterSpaceDL.download(space)
  ```
  """
  def new(source, id, template \\ @filename_template, save_dir \\ __DIR__)

  def new(:space_id, id, template, save_dir) do
    :ok = File.mkdir_p!(save_dir)

    {:ok, pid} =
      GenServer.start(__MODULE__, %{from_space_id: id, template: template, save_dir: save_dir})

    pid
  end

  def new(:space_url, url, template, save_dir) do
    :ok = File.mkdir_p!(save_dir)

    {:ok, pid} =
      GenServer.start(__MODULE__, %{from_space_url: url, template: template, save_dir: save_dir})

    pid
  end

  @doc """
  Download Twitter Space audio recording
  """
  def download(self_pid) do
    if nil == System.find_executable("ffmpeg") do
      raise "cannot find ffmpeg"
    end

    GenServer.call(self_pid, :download, :infinity)
  end

  @impl true
  def init(arg = %{from_space_url: url}) do
    ets_table = :ets.new(:buckets_registry, [:set, :protected])
    template = Map.get(arg, :template, @filename_template)
    save_dir = Map.get(arg, :save_dir, __DIR__)

    {:ok,
     %{
       space_id: from_space_url(url),
       ets_table: ets_table,
       template: template,
       save_dir: save_dir
     }}
  end

  @impl true
  def init(arg = %{from_space_id: space_id}) when is_binary(space_id) do
    ets_table = :ets.new(:buckets_registry, [:set, :protected])
    template = Map.get(arg, :template, @filename_template)
    save_dir = Map.get(arg, :save_dir, __DIR__)
    {:ok, %{space_id: space_id, ets_table: ets_table, template: template, save_dir: save_dir}}
  end

  @impl true
  def handle_call(
        :download,
        _from,
        state = %{
          space_id: space_id,
          ets_table: ets_table,
          template: template,
          save_dir: save_dir
        }
      ) do
    playlist = playlist_content(space_id, ets_table)
    filename = filename(space_id, ets_table, template)
    dyn_playlist = dyn_url(space_id, ets_table)

    {:ok, %{data: %{audioSpace: %{metadata: %{state: space_state, title: title}}}}} =
      metadata(space_id, ets_table)

    {:reply,
     _download(
       System.find_executable("ffmpeg"),
       filename,
       playlist,
       dyn_playlist,
       title,
       space_state,
       save_dir
     ), state}
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

  defp _download(ffmpeg, filename, playlist, dyn_playlist, title, space_state, save_dir) do
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

    :ok = _download(ffmpeg, pipeline)

    # cleanup
    if space_state == "Running" do
      File.rm!(concat_txt)
      File.rm!(m4a_live_filename)
    end
  end

  defp _download(_ffmpeg, []), do: :ok

  defp _download(ffmpeg, [args | rest]) do
    port =
      Port.open(
        {:spawn_executable, ffmpeg},
        [:binary, :exit_status, args: args]
      )

    receive do
      {^port, {:exit_status, 0}} -> nil
      {^port, {:exit_status, status}} -> Logger.warn("ffmpeg exit with status: #{status}")
      {^port, {:data, stdout}} -> IO.puts(Regex.replace(~r/\n/, stdout, "\r\n"))
    end

    _download(ffmpeg, rest)
  end

  defp filename(space_id, ets_table, template) do
    with [[@filename, filename] | _] <- :ets.lookup(ets_table, @filename) do
      filename
    else
      [] ->
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

  defp playlist_content(space_id, ets_table) do
    {:ok, playlist_url_str} = playlist_url(space_id, ets_table)

    with {:ok, master_url} = master_url(space_id, ets_table),
         url_base = Regex.replace(~r/master_playlist.m3u8.*/, master_url, ""),
         %HTTPotion.Response{body: body, status_code: 200} <-
           HTTPotion.get(playlist_url_str, follow_redirects: true) do
      Regex.replace(~r/chunk_/, body, "#{url_base}chunk_")
    else
      _ ->
        msg = "cannot fetch playlist: #{playlist_url_str}"
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
         playlist <- "https://#{host}#{suffix}" do
      {:ok, playlist}
    else
      _ ->
        msg = "cannot get the playlist url"
        Logger.error(msg)
        :error
    end
  end

  defp master_url(space_id, ets_table) do
    with [{@master_playlist, master_playlist} | _] <- :ets.lookup(ets_table, @master_playlist) do
      {:ok, master_playlist}
    else
      [] ->
        with {:ok, dyn_url} <- dyn_url(space_id, ets_table),
             master_playlist <-
               Regex.replace(~r/\/audio-space\/.*/, dyn_url, "/audio-space/master_playlist.m3u8"),
             true <- :ets.insert(ets_table, {@master_playlist, master_playlist}) do
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
    with [{@dyn_url, dyn_url} | _] <- :ets.lookup(ets_table, @dyn_url) do
      {:ok, dyn_url}
    else
      [] ->
        {:ok, meta} = metadata(space_id, ets_table)

        case meta do
          %{
            data: %{
              audioSpace: %{metadata: %{state: "Ended", is_space_available_for_replay: false}}
            }
          } ->
            Logger.error("Space has ended but it is not available for replay")
            :error

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
                       authorization: get_authorization(),
                       cookie: "auth_token="
                     ]
                   ),
                 status <- Jason.decode!(body, keys: :atoms),
                 %{source: %{location: dyn_url}} <- status,
                 true <- :ets.insert(ets_table, {@dyn_url, dyn_url}) do
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
    with [{@metadata, meta} | _] <- :ets.lookup(ets_table, @metadata) do
      {:ok, meta}
    else
      [] ->
        params =
          "?variables=%7B%22id%22%3A%22#{space_id}%22%2C%22isMetatagsQuery%22%3Atrue%2C%22withSuperFollowsUserFields%22%3Atrue%2C%22withBirdwatchPivots%22%3Afalse%2C%22withDownvotePerspective%22%3Afalse%2C%22withReactionsMetadata%22%3Afalse%2C%22withReactionsPerspective%22%3Afalse%2C%22withSuperFollowsTweetFields%22%3Atrue%2C%22withReplays%22%3Atrue%2C%22withScheduledSpaces%22%3Atrue%7D"

        get_url = @audio_space_metadata_endpoint <> params

        with %HTTPotion.Response{body: body, status_code: 200} <-
               HTTPotion.get(get_url, follow_redirects: true, headers: get_guest_header(ets_table)),
             meta <- Jason.decode!(body, keys: :atoms),
             %{data: %{audioSpace: %{metadata: %{media_key: _media_key}}}} <- meta,
             true <- :ets.insert(ets_table, {@metadata, meta}) do
          IO.inspect(meta)
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
    with {:ok, guest_token} <- guest_token(ets_table) do
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
            guest_token(ets_table, retry_times - 1)
        end
    end
  end

  defp guest_token(_ets_table, retry_times) when retry_times < 0 do
    Logger.error("no guest_token found")
    raise "no guest_token found"
  end
end
