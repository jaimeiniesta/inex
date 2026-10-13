# Tests that hit the real INE API are excluded by default:
#
#   mix test --include integration   # Inex against the live API
#   mix test --only ineapir          # Inex vs. the official R package (requires Docker)
ExUnit.start(exclude: [:integration, :ineapir])
