defmodule Safe.HttpClient.Hackney do
  @moduledoc false
  @behaviour Safe.HttpClient

  def get(url) do
    uri = URI.parse(url)
    host = to_charlist(uri.host)

    ssl_options = [
      verify: :verify_peer,
      cacerts: :certifi.cacerts(),
      depth: 3,
      server_name_indication: host,
      customize_hostname_check: [
        {:match_fun, :public_key.pkix_verify_hostname_match_fun(:https)}
      ]
    ]

    opts = [
      recv_timeout: 60_000,
      connect_timeout: 10_000,
      ssl_options: ssl_options,
      follow_redirect: true,
      max_redirect: 3
    ]

    case :hackney.request(:get, url, [], "", opts) do
      {:ok, 200, _headers, ref} ->
        :hackney.body(ref)

      {:ok, code, _headers, ref} ->
        :hackney.skip_body(ref)
        {:error, {:http_error, code}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end
end
