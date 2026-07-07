defmodule GbEmuWeb.UploadSessionController do
  use GbEmuWeb, :controller

  alias GbEmu.UploadStore
  alias GbEmuWeb.UploadSession

  def keepalive(conn, _params) do
    session_id =
      conn.assigns[:upload_session_id] || get_session(conn, UploadSession.session_key())

    if is_binary(session_id) do
      UploadStore.touch_session(session_id)
    end

    send_resp(conn, :no_content, "")
  end
end
