# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

`AGENTS.md` (repo root) holds the binding coding, testing, lint, commit and PR rules, and `tests/unit/AGENTS.md` holds the unit test rules. Read them before editing. `ARCHITECTURE.md` has request-flow diagrams and the translation-layer file map. Read a directory's `AGENTS.md` before editing files in it.

## Commands

Python env is managed with `uv`. Make targets wrap everything.

- `make bootstrap`: provision a fresh clone or worktree (uv sync with proxy extras, prisma generate, dashboard `npm install`, copies `.env` from the main worktree)
- `make check`: CI-equivalent lint on staged files (or the diff vs the base branch if nothing is staged). Output is logged to a file under `.git`, so grep that log instead of re-running. It queues for machine-wide slots, so let it wait
- `make lint`, `make lint-ruff`, `make lint-basedpyright`, `make format`: individual lint pieces (line length is 120)
- `make test-unit`: all of `tests/unit`. Matrix targets like `make test-unit-llms` and `make test-unit-proxy-core` mirror the CI groups
- Single test: `uv run --no-sync pytest tests/unit/path/to/test_file.py::test_name -x -vv`
- Run the proxy: `python litellm/proxy/proxy_cli.py --config litellm/proxy/dev_config.yaml --detailed_debug --reload --use_v2_migration_resolver` (port 4000). Admin UI dev server: `npm run dev` in `ui/litellm-dashboard` (port 3000)
- Prisma client: `uv run prisma generate --schema litellm/proxy/schema.prisma`
- Default branch for PRs: `python3 scripts/default_branch.py --branch`. Pull before starting work and branch off the default branch with a `litellm_` prefix and no `/`

## Architecture

Two layers. The SDK (`litellm/`) does provider calls, and the AI Gateway (`litellm/proxy/`) wraps it with auth, rate limits, budgets, spend tracking and routing.

SDK flow: `main.py` (`completion`/`acompletion` etc.) -> `utils.get_llm_provider()` -> `llms/custom_httpx/llm_http_handler.py` (`BaseLLMHTTPHandler`, the central HTTP orchestrator) -> per-provider `Config` classes in `llms/{provider}/.../transformation.py` (subclasses of `BaseConfig` in `llms/base_llm/`, implementing `transform_request` / `transform_response`). Provider behavior changes belong in the transformation file, not in the handler. Streaming is in `litellm_core_utils/streaming_handler.py`, and logging callbacks live in `integrations/` and `litellm_core_utils/litellm_logging.py`.

Gateway flow: `proxy/proxy_server.py` -> `proxy/auth/user_api_key_auth.py` -> hooks in `proxy/hooks/` (rate limiter, etc.) -> `proxy/route_llm_request.py` -> `router.py` (load balancing, fallbacks, cooldowns, strategies in `router_strategy/`) -> SDK. Spend is computed in `cost_calculator.py`, attached via `_hidden_params["response_cost"]`, and queued by `proxy/db/db_spend_update_writer.py` to be flushed to Postgres by a background job.

Cross-cutting points that span files:
- Many API surfaces (chat completions, Anthropic `/v1/messages`, Responses API, passthrough) each have their own endpoint dir under `proxy/` and their own translation files, so a feature usually has to be checked across several paths. Look for a shared helper (e.g. `litellm_core_utils/prompt_templates/factory.py`) before writing per-surface parsing
- Persisted entities are Pydantic models in `litellm/models/`, re-exported from `proxy/_types.py`, with data access in `litellm/repositories/`
- Prices and capabilities come from `model_prices_and_context_window.json` (backup copy under `litellm/`). Treat it as the source for the latest model in a family
- DB schema is `schema.prisma`. Migrations run synchronously at proxy boot, so they must be schema-only (no `UPDATE`/`DELETE`/`INSERT ... SELECT`)
- Other top-level dirs: `ui/litellm-dashboard` (Next.js admin UI), `litellm-rust` (Rust extension, tested via `make test-rust-extension`), `litellm-proxy-extras`, `helm`, `terraform`, `docker`

## Tests

`tests/unit/` mirrors `litellm/` by path, and a changed file's tests are found by that path. Name files `test_<filename>.py`, but match the sibling files already in the directory. Extend the mapped test file for bug fixes. Unit tests are in-process with no network, no dependence on the clock, and no patching of our own code. End-to-end tests go in `tests/e2e/`. Provider translation tests live in `tests/llm_translation/`.

## Gotchas

- Lint gates (ruff strict, type discipline, test quality, openapi docs, basedpyright) compare per-rule counts against the merge-base, so a branch may not increase any rule's count. `reportAny`/`reportExplicitAny` share a fixed cap in `ANY_CAPS` in `scripts/type_check_gate.py`. Never raise it on a feature branch
- Suppressions must name the exact rule and give a reason (`# pyright: ignore[rule]  # reason`). `# type: ignore` is banned
- New code follows the style in `AGENTS.md`: `Final` on every variable, frozen pydantic models and dataclasses, `ReadOnly` TypedDict fields, no mutation, no `Any`, failures as values, and no comments unless required
- `ARCHITECTURE.md` still references an `enterprise/` directory that was removed from the repo, so verify paths there before relying on them
- Commit and push when done, using conventional commit messages
