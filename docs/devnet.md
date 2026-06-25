# Devnet Runtime

## Entrypoint (`devnet-entrypoint.sh`)

The `aleo-devnet` image uses a wrapper entrypoint with **three-way branching**:

| Docker invocation | Args received | Entrypoint behavior |
|---|---|---|
| `docker run <image>` | none (`CMD []`) | Env-driven: builds `leo devnet` command from env vars |
| `docker run <image> devnet --custom` | `devnet --custom` | Explicit args: runs `leo devnet --custom` with log forwarding |
| `docker run <image> new my_project` | `new my_project` | Passthrough: `exec leo new my_project` (no wrapper) |

## Environment Variables

Only used in the env-driven path (i.e., no args passed to `docker run`):

| Variable | Default | Description |
|---|---|---|
| `STORAGE` | `/aleo/data` | Blockchain data directory |
| `VERBOSITY` | `4` | Log verbosity 0-4 |
| `NUM_VALIDATORS` | `4` | Number of validators |
| `NUM_CLIENTS` | `1` | Number of clients |
| `CLEAR_STORAGE` | `no` | `yes` to clear storage on start |
| `SNARKOS_FEATURES` | `test_network` | snarkOS features flag |
| `LOG_WAIT_SECONDS` | `5` | Wait before tailing logs |
| `LOG_POLL_INTERVAL` | `3` | Seconds between log file discovery |
| `LOG_FORWARDING` | `false` | Forward snarkOS logs to container stdout: `true`/`false` |

## Log Forwarding

When `LOG_FORWARDING=true`, dynamically discovers snarkOS log files in `/tmp` and `${STORAGE}`, tails them to container stdout with `tail -F` (handles rotation), and emits informational wrapper messages. The default is `LOG_FORWARDING=false`, which suppresses log tailing and informational wrapper messages (errors/shutdown messages still emitted).

## Graceful Shutdown

Traps SIGTERM/SIGINT/SIGQUIT, sends SIGTERM to the `leo` process, waits up to 30s, then SIGKILL.

## Snapshot Images

Generated snapshot Dockerfiles (`build-publish-deployment-snapshot.sh` and CI workflow) are minimal:

- `FROM ghcr.io/sealance-io/aleo-devnet:${DEVNET_VERSION}`
- `COPY --chown=leo:leo ./devnet/data /aleo/data` (pre-deployed blockchain state only)
- **No CMD or ENTRYPOINT override** — inherits base image's `CMD []` + entrypoint wrapper

This means snapshot images are fully configurable via `-e` env vars, just like the base image. Passing explicit args on `docker run` overrides this as expected.

## Snapshot Build Flow

1. Clone `sealance-io/compliant-transfer-aleo` at specified commit (SSH with fallback)
2. `npm ci --ignore-scripts` + `npm run postinstall` + `npm run build` + `npm run compile`
3. Start devnet container with volume mounted at `/aleo/data` (only captures ledger state, not runtime files)
4. Generate `CONSENSUS_VERSION_HEIGHTS=0,1,2,...,N-1` to accelerate reaching target consensus version (default target: `16`, default heights: `0..15`)
5. Poll `http://localhost:3030/testnet/consensus_version` until >= target (max 100 retries, 5s apart)
6. Deploy programs via `npm run deploy:devnet`
7. **Pre-shutdown verification**: Query REST API for each program in `required-programs.txt` (retries up to 10x)
8. Stop container, extract only `/aleo/data` to `./devnet/data/` (script uses alpine cp from volume; CI uses `docker cp`)
9. Build multi-arch image (version-tag only) from generated Dockerfile
10. **Post-build E2E verification**: Boot the built image per-platform (amd64 + arm64), wait for REST API, re-verify all required programs
11. **Retag as latest**: `docker buildx imagetools create` (same digest, no rebuild) — only after E2E passes

## Snapshot Build Validation

Three-layer verification prevents publishing snapshots with missing programs:

| Layer | When | What |
|---|---|---|
| **Volume narrowing** | Container run | Mount only `/aleo/data`, not `/aleo` — excludes `devnet-entrypoint.sh` and `snarkos` from capture |
| **Pre-shutdown check** | After `deploy:devnet`, before stop | REST API query per program with retries |
| **Post-build E2E** | After image build, before latest tag | Boot image per-platform, verify programs are queryable |

**`required-programs.txt`** (repo root): One program ID per line (`#` comments and blank lines ignored). Both the script and CI workflow read this file as the default. Override with `--required-programs` (script) or `required-programs` input (CI).

**Fail-closed policy**: Publish flows (`--skip-push=false`) **require** a non-empty program list. If `required-programs.txt` is missing/empty and no override is provided, the build aborts. Local-only builds (`--skip-push`) warn but continue without verification.
