defmodule TwitterSpaceDL do
  @moduledoc """
  Twitter Space Audio Downloader
  """

  require Logger

  @user_agent "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.1 Safari/605.1.15"
  @audio_space_metadata_endpoint "https://twitter.com/i/api/graphql/jyQ0_DEMZHeoluCgHJ-U5Q/AudioSpaceById"

  def from_space_url(url) when is_binary(url) do
    with [_, space_id | _] <- Regex.run(~r/spaces\/(\w+)/, url)
    do
      %{space_id: space_id}
    else
      _ -> nil
    end
  end

  def guest_token(retry_times \\ 5) when retry_times >= 0 do
    with %HTTPotion.Response{body: body, status_code: 200} <-
           HTTPotion.get("https://twitter.com/", follow_redirects: true, headers: ["User-Agent": @user_agent]),
         [_, guest_token_str | _] <- Regex.run(~r/gt=(\d{19})/, body)
    do
      guest_token_str
    else
        _ ->
          :timer.sleep(1000)
          guest_token(retry_times - 1)
    end
  end

  def guest_token(retry_times) when retry_times < 0 do
    Logger.error("no guest_token found")
    raise "no guest_token found"
  end
end
