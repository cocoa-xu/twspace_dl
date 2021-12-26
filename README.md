# TwspaceDl

Download Twitter Space Audio

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
