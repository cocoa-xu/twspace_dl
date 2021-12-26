defmodule TwitterSpaceDL.Plugin do
  defmacro __using__(_opts) do
    quote do
      @behaviour TwitterSpaceDL.Plugin
    end
  end

  @callback get_authorization(String.t(), String.t() | nil, String.t() | nil) ::
              {:ok, String.t()} | {:stop, String.t()} | :stop
  @callback guest_token(
              {:ok, String.t()} | {:error, String.t()},
              String.t() | nil,
              String.t() | nil
            ) ::
              {:ok, String.t()} | {:stop, String.t()} | :stop
  @callback get_guest_header(term, String.t() | nil, String.t() | nil) ::
              {:ok, term} | {:stop, String.t()} | :stop

  # callback sequence if init by username
  # - get_authorization.
  # - guest_token.
  # - get_guest_header.
  # - userinfo.
  # - recent_tweets.
  # - space_urls. You can manually reject/add some urls. The output will be handled individually.
  @callback userinfo(term, String.t() | nil, String.t() | nil) ::
              {:ok, term} | {:stop, String.t()} | :stop
  @callback recent_tweets(term, String.t() | nil, String.t() | nil) ::
              {:ok, term} | {:stop, String.t()} | :stop
  @callback space_urls(term, String.t() | nil, String.t() | nil) ::
              {:ok, term} | {:stop, String.t()} | :stop

  # callback sequence if init by single space url/id
  # - get_authorization.
  # - guest_token.
  # - get_guest_header.
  # - metadata.
  # - dyn_url.
  # - master_url.
  # - playlist_url.
  # - playlist_content.
  @callback metadata(term, String.t() | nil, String.t() | nil) ::
              {:ok, term} | {:stop, String.t()} | :stop
  @callback dyn_url(term, String.t() | nil, String.t() | nil) ::
              {:ok, term} | {:stop, String.t()} | :stop
  @callback master_url(term, String.t() | nil, String.t() | nil) ::
              {:ok, term} | {:stop, String.t()} | :stop
  @callback playlist_url(term, String.t() | nil, String.t() | nil) ::
              {:ok, term} | {:stop, String.t()} | :stop
  @callback playlist_content(term, String.t() | nil, String.t() | nil) ::
              {:ok, term} | {:stop, String.t()} | :stop

  @optional_callbacks get_authorization: 3,
                      guest_token: 3,
                      get_guest_header: 3,
                      userinfo: 3,
                      recent_tweets: 3,
                      space_urls: 3,
                      metadata: 3,
                      dyn_url: 3,
                      master_url: 3,
                      playlist_url: 3,
                      playlist_content: 3
end
