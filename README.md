<h1>
<picture style="margin-right: 15px; float: left;">
  <source
    media="(prefers-color-scheme: dark)"
    srcset="https://security-audit-logo.s3.eu-central-1.amazonaws.com/image_safe_logo_dark.png"
    width="170px"
    align="left"
  />
  <source
    media="(prefers-color-scheme: light)"
    srcset="https://security-audit-logo.s3.eu-central-1.amazonaws.com/image_safe_logo_light.png"
    width="170px"
    align="left"
  />
  <img
    src="https://security-audit-logo.s3.eu-central-1.amazonaws.com/image_safe_logo_light.png"
    alt="Security Audit For Erlang and Elixir"
    width="170px"
    align="left"
  />
</picture>
  Security Analysis For Elixir
</h1>

A Mix task that brings [SAFE](https://safe-docs.erlang-solutions.com/) security vulnerability scanning to Elixir/Mix projects. It mirrors the behaviour of the [SAFE rebar3 plugin](https://github.com/erlang-solutions/safe-rebar-plugin), using Elixir idioms throughout.

## Installation

Add the plugin to your `mix.exs` dependencies:

```elixir
defp deps do
  [
    {:safe_mix_plugin, "~> 1.0", only: [:dev, :test], runtime: false}
  ]
end
```

Then fetch dependencies:

```bash
mix deps.get
```

## Usage

```bash
mix safe <subcommand> [options]
```

### Subcommands

| Subcommand    | Description                                      |
|---------------|--------------------------------------------------|
| `fingerprint` | Run the SAFE fingerprint phase                   |
| `analyse`     | Run the SAFE analysis phase                      |
| `download`    | Download the SAFE binary without running a scan  |
| `version`     | Print the plugin version and the SAFE binary version |
| `help`        | Print usage information                          |

## Typical workflow

**1. Fingerprint your project**

```
$ mix safe fingerprint
* checking your project's structure
* Discovered 1 app(s): [:my_app]
{
  "output": ["stdio", "file"],
  "version": "1.1",
  "project": {
    "name": "my_app",
    "apps": [{"name": "my_app", "app_file": "mix.exs", "additional_includes": []}],
    "paths": ["_build/dev/lib/my_app/ebin"]
  }
}
Would you like to proceed with this configuration? [y/N]: y
* running SAFE fingerprint
* SAFE fingerprint complete
```

**2. Analyse for vulnerabilities**

```
$ mix safe analyse
* Using config from .safe/config.json
* running SAFE analysis
* SAFE analysis complete - no vulnerabilities found
```

**3. Check versions**

```
$ mix safe version
* safe-mix-plugin version: 1.0.0
* SAFE version: 1.5.1
```

## Binary management

The SAFE binary is downloaded automatically on first use and stored at:

```
<project_root>/_build/safe/safe
```

The resolved version is pinned in `safe.lock` at the project root (commit this file to version control). On subsequent runs the binary is not re-downloaded as long as the file is present.

The version constraint is `~> 1.5.0` (patch-level lock).

### Skipping the download

```bash
mix safe download
```

Useful in CI pipelines where you want to cache the binary separately from the scan step.

## Configuration file

`mix safe fingerprint` generates `.safe/config.json` in the project root. The format is identical to the rebar3 plugin so the file can be shared across both tools.

```json
{
  "output": ["stdio", "file"],
  "version": "1.1",
  "project": {
    "name": "my_app",
    "apps": [
      {
        "name": "my_app",
        "app_file": "mix.exs",
        "additional_includes": []
      }
    ],
    "paths": ["_build/dev/lib/my_app/ebin"]
  }
}
```

You can edit this file before re-running. If it exists when `mix safe fingerprint` is called, the plugin will ask whether to reuse it.

## Umbrella projects

Umbrella projects are supported. Each child app under `apps/` contributes one entry to the `apps` list, and `paths` is set to the longest common prefix of all child ebin directories.

## Debug logging

All debug output is written to `_build/safe/safe.log` via Elixir's `Logger`. The console is not cluttered with debug lines. To raise the log level in your project during development, add the following to `config/config.exs`:

```elixir
config :logger, level: :debug
```

The log file is created alongside the SAFE binary at `_build/safe/safe.log`.

## Exit codes

| Code | Meaning                              |
|------|--------------------------------------|
| `0`  | Success / no vulnerabilities found   |
| `1`  | Error (download failure, bad config, unsupported platform, …) |
| `2`  | Vulnerabilities found                |

## Supported platforms

| Platform      | Architecture |
|---------------|-------------|
| Linux         | x86_64      |
| macOS         | x86_64      |

Windows is not yet supported.

## Related links

- [SAFE Documentation](https://safe-docs.erlang-solutions.com/)
- [SAFE rebar3 plugin](https://github.com/erlang-solutions/safe-rebar-plugin)
- [Mix.Task documentation](https://hexdocs.pm/mix/Mix.Task.html)
