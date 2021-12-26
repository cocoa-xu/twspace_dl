defmodule TwitterSpaceDL.Plugin do
  defmacro __using__(_opts) do
    quote do
      @behaviour TwitterSpaceDL.Plugin
    end
  end

  @callback get_authorization(String.t()) :: {:ok, String.t()} | {:stop, String.t()} | :stop
  @callback guest_token({:ok, String.t()} | {:error, String.t()}) ::
              {:ok, String.t()} | {:stop, String.t()} | :stop
  @callback get_guest_header(term) :: {:ok, term} | {:stop, String.t()} | :stop

  # callback sequence if init by username
  # - get_authorization.
  # - guest_token.
  # - get_guest_header.
  # - userinfo.
  # - recent_tweets.
  # - space_urls. You can manually reject/add some urls. The output will be handled individually.
  @callback userinfo(term) :: {:ok, term} | {:stop, String.t()} | :stop
  @callback recent_tweets(term) :: {:ok, term} | {:stop, String.t()} | :stop
  @callback space_urls(term) :: {:ok, term} | {:stop, String.t()} | :stop

  # callback sequence if init by single space url/id
  # - get_authorization.
  # - guest_token.
  # - get_guest_header.
  # - metadata.
  # - dyn_url.
  # - master_url.
  # - playlist_url.
  # - playlist_content.
  @callback metadata(term) :: {:ok, term} | {:stop, String.t()} | :stop
  @callback dyn_url(term) :: {:ok, term} | {:stop, String.t()} | :stop
  @callback master_url(term) :: {:ok, term} | {:stop, String.t()} | :stop
  @callback playlist_url(term) :: {:ok, term} | {:stop, String.t()} | :stop
  @callback playlist_content(term) :: {:ok, term} | {:stop, String.t()} | :stop

  @optional_callbacks get_authorization: 1,
                      guest_token: 1,
                      get_guest_header: 1,
                      userinfo: 1,
                      recent_tweets: 1,
                      space_urls: 1,
                      metadata: 1,
                      dyn_url: 1,
                      master_url: 1,
                      playlist_url: 1,
                      playlist_content: 1
end
