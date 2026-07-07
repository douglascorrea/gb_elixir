defmodule GbEmuWeb.Session do
  @moduledoc """
  Runtime browser-session options.

  The cookie lifetime intentionally follows `GbEmu.UploadStore.ttl_ms/0` so the
  same environment flag controls both the browser session and the uploaded-file
  retention window.
  """

  @behaviour Plug

  @base_options [
    store: :cookie,
    key: "_gb_emu_key",
    signing_salt: "pBcoQGmr",
    same_site: "Lax"
  ]

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    Plug.Session.call(conn, Plug.Session.init(session_options()))
  end

  def session_options do
    Keyword.put(@base_options, :max_age, session_max_age_seconds())
  end

  def session_max_age_seconds do
    GbEmu.UploadStore.ttl_ms()
    |> ceil_div(1000)
    |> max(0)
  end

  defp ceil_div(0, _denominator), do: 0
  defp ceil_div(numerator, denominator), do: div(numerator + denominator - 1, denominator)
end
