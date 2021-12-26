# TwspaceDL

Download Twitter Space Audio

## Dependency
- FFmpeg

## Example
Download by space url
```elixir
space = TwitterSpaceDL.new!(:space_url, "https://twitter.com/i/spaces/1OyJADqBEgDGb")
TwitterSpaceDL.download(space)
```

Download by space id and display ffmpeg output
```elixir
space = TwitterSpaceDL.new!(:space_id, "1OyJADqBEgDGb", show_ffmpeg_output: true)
TwitterSpaceDL.download(space)
```

Download by space id, use custom filename template and save to `download` directory
```elixir
space = TwitterSpaceDL.new!(:space_id, "1OyJADqBEgDGb",
  template: "space-%{title}-%{rest_id}-%{created_at}",
  save_dir: "./download")
TwitterSpaceDL.download(space)
```

Init by username, use custom filename template and use plugin module
```elixir
space = TwitterSpaceDL.new!(:user, "LaplusDarknesss",
  template: "space-%{title}-%{rest_id}",
  plugin_module: TwitterSpaceDL.Plugin.CLI)
# you can call this again to download new spaces (if space archive is available)
TwitterSpaceDL.download(space)
```

### Optional arguments
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

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `twspace_dl` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:twspace_dl, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/twspace_dl](https://hexdocs.pm/twspace_dl).
