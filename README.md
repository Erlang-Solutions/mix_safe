# SAFE - Security Analysis For Elixir
<br />
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
A Mix task that brings [SAFE](https://safe-docs.erlang-solutions.com/) security vulnerability scanning to Elixir/Mix projects.


## Installation

Add the plugin to your `mix.exs` dependencies:

```elixir
defp deps do
  [
    {:mix_safe, "~> 1.0", only: [:dev, :test], runtime: false}
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
| `sca`         | Scan dependencies for known vulnerabilities (Supply Chain Analysis) |
| `download`    | Download the SAFE binary without running a scan  |
| `version`     | Print the plugin version and the SAFE binary version |
| `help`        | Print usage information                          |

## Licensing

| Capability | License requirement | Cost |
|------------|---------------------|------|
| `fingerprint` + `analyse` | Requires a SAFE license | Free for open source projects |
| `sca` | No license required | Free for everyone |

The `analyse` phase (and the `fingerprint` step that feeds it) runs the full SAFE static analysis engine, which requires a SAFE license. The license is free for open source projects.

Dependency scanning via `sca` is completely free for everyone and needs no license.

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

**3. Scan dependencies for known vulnerabilities**

```
$ mix safe sca
* running SAFE SCA
* SAFE SCA complete - no vulnerabilities found
```

Options:

| Flag | Description | Default |
|------|-------------|---------|
| `--lock-file PATH` | Path to `mix.lock` or `rebar.lock` | auto-detected |
| `--advisories SOURCE` | Advisory source: GitHub URL, local dir, or git URL | `mirego/elixir-security-advisories` |
| `--ignore-file PATH` | Path to SCA ignore file | `.safe/sca_ignore.json` |
| `--warnings-as-errors` | Treat warnings (e.g. non-hex deps) as errors | off |

Exit codes: `0` clean, `1` error, `2` vulnerabilities found, `3` warnings treated as errors.

To suppress specific findings, create `.safe/sca_ignore.json`:

```json
{
  "ignored_dependencies": [
    {"package": "hackney", "advisory_ids": ["*"], "reason": "Not exploitable"},
    {"package": "oidcc", "advisory_ids": ["GHSA-xxxx-xxxx-xxxx"]}
  ],
  "ignored_non_hex_packages": ["my_git_dep", "my_path_dep"]
}
```

## Binary management

The SAFE binary is downloaded automatically on first use and stored at:

```
<project_root>/_build/safe/safe
```

The resolved version is pinned in `safe.lock` at the project root (commit this file to version control). On later runs the binary is not re-downloaded as long as the file is present.


### Skipping the download

```bash
mix safe download
```

Useful in CI pipelines where you want to cache the binary separately from the scan step.

## Configuration file

`mix safe fingerprint` generates `.safe/config.json` in the project root. 

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


## Exit codes

| Code | Meaning                              |
|------|--------------------------------------|
| `0`  | Success / no vulnerabilities found   |
| `1`  | Error (download failure, bad config, unsupported platform, …) |
| `2`  | Vulnerabilities found                |



## Related links

- [SAFE Documentation](https://safe-docs.erlang-solutions.com/)
