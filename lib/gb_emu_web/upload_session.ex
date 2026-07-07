defmodule GbEmuWeb.UploadSession do
  @moduledoc """
  Ensures each browser has a signed upload session id.
  """

  import Plug.Conn

  @session_key "upload_session_id"
  @refreshed_key "upload_session_refreshed_at"

  def session_key, do: @session_key

  def init(opts), do: opts

  def call(conn, _opts) do
    session_id =
      get_session(conn, @session_key) ||
        Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

    conn
    |> assign(:upload_session_id, session_id)
    |> put_session(@session_key, session_id)
    |> put_session(@refreshed_key, System.system_time(:second))
  end
end
