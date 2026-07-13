defmodule GBEmulings.PolicyTest do
  use ExUnit.Case, async: true

  @policy Path.expand("../../docs/roms.md", __DIR__)

  test "documents lawful ROM use, upload retention, boot ROMs, and trademarks" do
    policy = File.read!(@policy)

    assert policy =~ "# ROM, BIOS, and Trademark Policy"
    assert policy =~ "Do not commit or redistribute commercial game ROMs"
    assert policy =~ "GB_EMU_UPLOAD_TTL_MS"
    assert policy =~ "256 bytes"
    assert policy =~ "not affiliated with, sponsored by, or endorsed by Nintendo"
  end
end
