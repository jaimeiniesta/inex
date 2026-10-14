# AGENTS.md

Instructions for AI coding agents working on this repository.

## Project

Inex is an Elixir client for the [INE JSON API](https://www.ine.es/dyngs/DAB/index.htm?cid=1099)
(`https://servicios.ine.es/wstempus/js/{ES|EN}/{FUNCTION}/{inputs}?params`). It returns either the
raw decoded JSON or Explorer data frames.

- **Reference implementation:** [ineapir](https://github.com/es-ine/ineapir), the official R
  package. When the API behaviour is unclear, check what ineapir does.
- **API reference:** the OpenAPI spec at
  `https://www.ine.es/OpenAPI/includes/files/{es,en}/wstempus.yaml`. It is incomplete; see the
  pitfalls below.
- Elixir `~> 1.18`. Use the built-in `JSON` module; do not add Jason.

## Commands

| Command | Purpose |
|---|---|
| `mix test` | Unit tests, offline (Req.Test stubs and recorded fixtures) |
| `mix test --include integration` | Also run invariant checks against the live INE API |
| `mix test --only ineapir` | Compare with the R package (needs Docker, see `test/ineapir/README.md`) |
| `mix format` | Format the code |
| `mix credo --strict` | Lint |
| `mix sobelow` | Security checks (config in `.sobelow-conf`) |
| `mix dialyzer` | Type checks (PLT in `priv/plts/`) |
| `mix docs` | Build the docs; must produce no warnings |
| `mix coveralls` | Coverage |

## Layout

| Path | Contents |
|---|---|
| `lib/inex/client.ex` | HTTP via Req: URL building, response normalization, pagination, telemetry |
| `lib/inex/utils.ex` | Private. Option schemas (NimbleOptions), translation of options into INE params, `fetch/5` |
| `lib/inex/filters.ex` | Variable/value filters and their shortcuts (`ccaa:`, `data_type:`...) |
| `lib/inex/data_frame.ex` | JSON → Explorer (`from_observations/1`, `to_wide/2`, `from_records/1`) |
| `lib/inex/{operations,series,tables,variables,...}.ex` | One module per INE entity, one function per INE function |
| `test/support/ine_case.ex` | `Inex.Case`: `stub_ine/1`, `assert_ine_request/1`, `fixture!/1` |
| `test/support/fixtures/` | Real API responses, trimmed |
| `test/integration_test.exs` | Live API tests (`:integration` tag) |
| `test/ineapir/` | Cross-check with ineapir: `Dockerfile`, `queries.R`, `cross_check_test.exs` |
| `livebooks/` | Example notebooks, also published as extras in the docs |

## Conventions

- **New endpoints:** call `Utils.fetch(FUNCTION, inputs, opts, @schema)`. Build the schema with
  `Utils.schema([...])` and document it with `#{NimbleOptions.docs(@schema)}`. Add the function to
  the endpoint list in its moduledoc, with a link to the INE docs.
- **Options use idiomatic English names, never raw INE parameter names.** `Utils.to_params/2`
  translates them:

  | Option | INE parameter |
  |---|---|
  | `last` | `nult` |
  | `detail` | `det` |
  | `friendly` / `metadata` | `tip` |
  | `periodicity` | `p` |
  | `classification` | `clasif` |
  | `observation_start` / `observation_end` / `dates` | `date` |
  | `filters` | `tv` (tables) or `g1..gN` (operations) |

- **Return values:**
  - Every function returns `{:ok, result} | {:error, %Inex.Error{}}`. Non-bang functions never
    raise.
  - Data frame functions return `{:ok, df}` and have a bang variant (`Utils.bang!/1`).
- **Raw responses are returned untouched,** keeping the INE's Spanish keys (`"COD"`, `"Nombre"`,
  `"Data"`...).
- **Public functions have `@spec`s and docs with examples.** Example outputs must be real: run the
  call against the live API before writing them.
- Code and docs are in English. INE names and values stay in Spanish.
- **Docs, README, CHANGELOG and livebooks:** update them together whenever the public API changes.

## INE API pitfalls

- **Errors often come with HTTP 200:**
  - An empty body means an unknown id.
  - Plain text means an unknown function (`NOFUNC`).
  - Invalid parameters give a 404 with Latin-1 HTML.
  - Unknown parameters and languages are silently ignored.

  `Inex.Client` normalizes all of these into `Inex.Error`.
- **Repeated params (`tv`, `g1`, `date`) are required for filters.** The query string is built by
  hand in `Client.build_url/4` because Req 0.7.0–0.7.3 drops duplicate keys. Do not move params to
  Req's `:params` option.
- **`DATOS_SERIE` and `DATOS_METADATAOPERACION` need `nult` or `date`.** Without them they return a
  404. `Utils.ensure_data_range/1` adds `date=18000101:`.
- **`Fecha` is epoch ms at midnight Madrid time.** Add 12 h before converting to a UTC date. It is
  missing in very old data and in PC-Axis/tpx tables, so the date is derived from the period
  labels instead.
- **Filters use the value `Id`, not its `Codigo`.** For example, the province of Madrid is
  `Id 29` with code `"28"`, and `Id 28` is Lugo. PC-Axis/tpx tables are filtered by text codes.
- **Series codes go stale without any warning.** Codes from the INE docs and tutorials (e.g.
  `IPC251852`, `EPA815`) stopped being updated, but they still return old data. Before using a
  code in docs, tests or livebooks, check the date of its last observation.
  - Current series: `IPC290750` (CPI annual change), `IPC290751` (CPI index), `EPA452434`
    (unemployment rate), `CNTR6654` (GDP annual growth).
  - Current tables: `76125`, `76136`, `65334`, `67822`.
- **Flash estimates ("Avance"):** only some series have the latest period. `last: 1` on a table may
  return series with empty `Data`.
- **Pagination:** the page size varies (10,000 series per page in `SERIES_OPERACION`) and an empty
  page returns `[]`. `page: :all` loops until it gets an empty page, with a limit of 1,000 pages.
- **Undocumented functions in use:** `OPERACIONES_TABLA`, `PERIODICIDAD_OPERACION`,
  `PERIODOS_PERIODICIDAD`, `UNIDADES`, `ESCALAS`.

## Testing

- **Unit tests never hit the network.** `config/test.exs` routes Req through `Req.Test`. Use
  `Inex.Case`, and assert both the result and the exact request (`assert_ine_request/1` returns
  the query params).
- **Fixtures:**
  - Capture them from the live API (e.g. with `curl`), trim them to the minimum, and save them as
    `test/support/fixtures/<function>_<input>[_variant].json` in lowercase.
  - Never hand-write fixture JSON.
- **Integration tests** check invariants (shapes, types, errors), not values, because the data
  changes with every INE release.
- **ineapir cross-check:** when you change anything that affects data frames (dates, periods,
  values, metadata columns, filters), add or adjust the query in `queries.R` and its comparison
  in `cross_check_test.exs`. ineapir's output is the ground truth; do not hand-code expected
  values. Set `INEAPIR_OUTPUT` to reuse a previous R run.
- **Livebooks** load Inex from Hex (`{:inex, "~> 0.1"}`). To try local changes, switch
  temporarily to `{:inex, path: Path.join(__DIR__, "..")}` (do not commit it). After changing the
  public API or an example, run every cell against the live API.

## Before finishing a change

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix sobelow
mix test
mix dialyzer
mix docs
```

If you touched `Client`, `DataFrame`, `Filters` or option translation, also run
`mix test --include integration --include ineapir`.

## Git

- Commit only when asked.
- Never open issues or pull requests on your own: a human must create and supervise them (see the
  "Contributing" section of the README).
- Do not add `Co-Authored-By` trailers or any other AI attribution to commit messages.
