defmodule GbEmuWeb.SessionTest do
  use ExUnit.Case, async: false

  alias GbEmuWeb.Session

  setup do
    previous_ttl = System.get_env("GB_EMU_UPLOAD_TTL_MS")

    on_exit(fn ->
      if previous_ttl do
        System.put_env("GB_EMU_UPLOAD_TTL_MS", previous_ttl)
      else
        System.delete_env("GB_EMU_UPLOAD_TTL_MS")
      end
    end)
  end

  test "session cookie max age follows the upload retention flag" do
    System.put_env("GB_EMU_UPLOAD_TTL_MS", "1500")

    assert Session.session_max_age_seconds() == 2
    assert Keyword.fetch!(Session.session_options(), :max_age) == 2
  end
end
