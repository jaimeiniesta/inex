import Config

# Route every request through Req.Test stubs (see test/support/ine_case.ex).
# Integration tests (`mix test --include integration`) override this.
config :inex, req_options: [plug: {Req.Test, Inex.Client}, retry: false]

config :logger, level: :warning
