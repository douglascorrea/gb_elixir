import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/gb_emu start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :gb_emu, GbEmuWeb.Endpoint, server: true
end

port = String.to_integer(System.get_env("PORT", "4000"))

config :gb_emu, GbEmuWeb.Endpoint, http: [port: port]

if config_env() == :prod do
  parse_ipv4 = fn value ->
    parts =
      value
      |> String.split(".")
      |> Enum.map(fn part ->
        case Integer.parse(part) do
          {octet, ""} when octet in 0..255 -> octet
          _ -> raise "BIND_IP must be an IPv4 address, got: #{inspect(value)}"
        end
      end)

    case parts do
      [a, b, c, d] -> {a, b, c, d}
      _ -> raise "BIND_IP must be an IPv4 address, got: #{inspect(value)}"
    end
  end

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  parse_check_origin = fn
    nil, host ->
      ["//#{host}"]

    value, host ->
      value
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> case do
        [] -> ["//#{host}"]
        origins -> origins
      end
  end

  check_origin = parse_check_origin.(System.get_env("PHX_CHECK_ORIGIN"), host)

  config :gb_emu, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  bind_ip = parse_ipv4.(System.get_env("BIND_IP", "127.0.0.1"))

  config :gb_emu, GbEmuWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Bind to loopback by default so Nginx remains the public edge.
      # Set BIND_IP=0.0.0.0 for container or direct public binding.
      ip: bind_ip,
      port: port
    ],
    secret_key_base: secret_key_base,
    check_origin: check_origin

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :gb_emu, GbEmuWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :gb_emu, GbEmuWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :gb_emu, GbEmu.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://swoosh.hexdocs.pm/Swoosh.html#module-installation for details.
end
