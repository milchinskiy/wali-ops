# wali-ops

Small, practical external modules for
[wali](https://github.com/milchinskiy/wali) host automation.

`wali-ops` is intentionally imperative and verb-oriented. A task says what it
does:

```lua
{
    id = "install-nginx",
    module = "ops.pkg.apt.install",
    args = { packages = { "nginx" }, no_install_recommends = true },
}
```

The modules are not a declarative resource model. They are small operations
built on top of wali's public Lua module API and target-host primitives.

## Use as a wali module source

```lua
modules = {
    {
        namespace = "ops",
        git = {
            url = "https://example.invalid/your/wali-ops.git",
            ref = "main",
            path = "modules",
            depth = 1,
        },
    },
}
```

Then use modules by their path under `modules/`:

```lua
tasks = {
    {
        id = "apt-update",
        module = "ops.pkg.apt.update",
        args = {},
    },
    {
        id = "install-curl",
        module = "ops.pkg.apt.install",
        depends_on = { "apt-update" },
        args = { packages = { "curl" } },
    },
    {
        id = "start-nginx",
        module = "ops.service.systemd.start",
        args = { unit = "nginx.service" },
    },
}
```

## Common behavior model

All modules return wali apply results. Command-oriented modules report command
changes; file-oriented modules return filesystem changes from wali host
filesystem primitives. All modules fail the task by raising an error when
validation, probing, command execution, or filesystem mutation fails.

General conventions:

- All paths are target-host paths unless explicitly stated otherwise.
- Path arguments named `path`, `dest`, `home`, `shell`, `source_dir`, or
  `service_dir` must be absolute where the module validates them.
- `timeout` is a wali command timeout string such as `10s` or `2m`. If omitted,
  wali's host command timeout applies.
- Package names must be non-empty, must not contain whitespace or control
  characters, and must not start with `-`.
- Service/unit names must be non-empty, must not contain whitespace, control
  characters, or `/`, and must not start with `-`.
- User/group names must be non-empty, must not contain whitespace, control
  characters, `:`, or `/`, and must not start with `-`.
- `mode` is an octal string accepted by `wali.builtin.lib.mode_bits`, for
  example `"0644"`.
- `owner` is `{ user = "name-or-id", group = "name-or-id" }`; either field may
  be omitted.
- Modules that expose `mode`/`owner` may apply those metadata changes when the
  file already exists and content is already correct. Use
  `wali.builtin.permissions` for standalone metadata management.
- Modules that do not expose `mode`/`owner` never perform metadata-only changes.

For command modules, successful command execution reports an `updated` command
result unless the module first proves that the requested operation is already
satisfied. Idempotent modules use target commands such as `dpkg-query`,
`pacman -Q`, `systemctl is-active`, `getent passwd`, etc. Explicit operations
such as `upgrade`, `update`, `restart`, `reload`, and `daemon_reload` always
report `updated` after successful command execution.

## App modules

### `ops.app.curl`

Download one URL to a target-host file using `curl`.

Requires: `curl`.

Arguments:

| Argument         | Type                    | Default      | Description                                                                       |
| ---------------- | ----------------------- | ------------ | --------------------------------------------------------------------------------- |
| `url`            | string, required        | —            | URL passed to curl. Must be non-empty and must not contain control characters.    |
| `dest`           | absolute path, required | —            | Destination file path on the target host.                                         |
| `create_parents` | boolean                 | `false`      | Create the destination parent directory before downloading.                       |
| `replace`        | boolean                 | `true`       | Replace an existing destination. If `false` and `dest` exists, no command is run. |
| `timeout`        | string                  | host default | Command timeout for curl.                                                         |
| `mode`           | string                  | nil          | Optional mode applied after a successful download.                                |
| `owner`          | object                  | nil          | Optional owner applied after a successful download.                               |

Behavior:

- If `replace = false` and `dest` exists, the module returns unchanged and does
  not apply `mode`/`owner`.
- Otherwise it optionally creates the parent directory, downloads to a temporary
  file in the destination directory, renames the temporary file to `dest`, then
  applies `mode`/`owner` if provided.
- On curl or filesystem failure, it attempts to remove the temporary file before
  failing.

Results:

- Changed: download and rename completed; data is
  `{ url = <url>, dest = <dest> }`; message is `downloaded file`.
- Unchanged: destination already exists and `replace = false`.
- Error: invalid input, missing parent when `create_parents = false`, curl
  failure, rename failure, chmod/chown failure, or temporary file cleanup
  failure that escapes wali filesystem handling.

### `ops.app.wget`

Download one URL to a target-host file using `wget`.

Requires: `wget`.

Arguments, behavior, results, and corner cases are the same as `ops.app.curl`,
except the download command is `wget --output-document <tmp> -- <url>`.

## File text modules

The file modules operate on plain UTF-8 text. They are intentionally simple and
literal. They do not parse INI, YAML, TOML, JSON, shell syntax, or
service-specific configuration formats.

### `ops.file.line`

Append an exact line to a text file when that line is missing.

Arguments:

| Argument         | Type                    | Default | Description                                                                                 |
| ---------------- | ----------------------- | ------- | ------------------------------------------------------------------------------------------- |
| `path`           | absolute path, required | —       | Target file path.                                                                           |
| `line`           | string, required        | —       | Exact line to ensure. Must be non-empty and single-line; `\n` and `\r` are rejected.        |
| `create`         | boolean                 | `true`  | Create the file if it is missing.                                                           |
| `create_parents` | boolean                 | `false` | Create parent directories when creating the file.                                           |
| `mode`           | string                  | nil     | Optional mode for a created or rewritten file; also enforced when the line already exists.  |
| `owner`          | object                  | nil     | Optional owner for a created or rewritten file; also enforced when the line already exists. |

Behavior:

- Exact-line matching is literal and line-based.
- Existing files must be regular files.
- If the file is missing and `create = true`, the file is created with
  `line .. "\n"`.
- If the file exists and already contains the exact line, content is unchanged;
  optional metadata is still enforced.
- If the file exists and does not contain the line, the line is appended. A
  missing trailing newline is normalized before appending.

Results:

- Changed: file created, line appended, or metadata changed.
- Unchanged: line already exists and no metadata change is required.
- Error: invalid path/line/mode/owner, missing file with `create = false`,
  non-regular path, failed read/write/chmod/chown.

### `ops.file.remove_line`

Remove exact matching line occurrences from an existing text file.

Arguments:

| Argument     | Type                    | Default | Description                                                                          |
| ------------ | ----------------------- | ------- | ------------------------------------------------------------------------------------ |
| `path`       | absolute path, required | —       | Target file path.                                                                    |
| `line`       | string, required        | —       | Exact line to remove. Must be non-empty and single-line; `\n` and `\r` are rejected. |
| `all`        | boolean                 | `true`  | Remove all matching lines. If `false`, remove only the first current match.          |
| `missing_ok` | boolean                 | `true`  | Treat a missing file as unchanged instead of failing.                                |

Behavior:

- The module never creates files.
- The module never changes file metadata; use `wali.builtin.permissions` for
  metadata changes.
- Matching is exact and line-based.
- `all = false` is intentionally not globally idempotent when multiple matching
  lines remain. Each apply removes one current match.
- Existing paths must be regular files.

Results:

- Changed: at least one line was removed; data is `{ removals = <count> }`.
- Unchanged: file is missing and `missing_ok = true`, or no exact line was
  found; data is `{ removals = 0 }`.
- Error: invalid path/line, missing file with `missing_ok = false`, non-regular
  path, failed read/write.

### `ops.file.replace`

Replace literal text in an existing text file.

Arguments:

| Argument  | Type                    | Default | Description                                                                             |
| --------- | ----------------------- | ------- | --------------------------------------------------------------------------------------- |
| `path`    | absolute path, required | —       | Target file path.                                                                       |
| `find`    | string, required        | —       | Literal text to find. Must be non-empty.                                                |
| `replace` | string, required        | —       | Literal replacement text. May be empty.                                                 |
| `all`     | boolean                 | `true`  | Replace all current occurrences. If `false`, replace only the first current occurrence. |

Behavior:

- The module never creates files.
- The module never changes file metadata; use `wali.builtin.permissions` for
  metadata changes.
- Matching is literal byte/string matching, not Lua pattern matching and not
  regular expressions.
- `all = false` is intentionally not globally idempotent when multiple matches
  remain. Each apply replaces one current match.
- Existing paths must be regular files.

Results:

- Changed: at least one replacement was made; data is
  `{ replacements = <count> }`.
- Unchanged: `find` was not present; data is `{ replacements = 0 }`.
- Error: invalid path/find, missing file, non-regular path, failed read/write.

### `ops.file.block`

Create or replace one marked managed block in a text file.

Arguments:

| Argument         | Type                    | Default | Description                                                                                   |
| ---------------- | ----------------------- | ------- | --------------------------------------------------------------------------------------------- |
| `path`           | absolute path, required | —       | Target file path.                                                                             |
| `marker`         | string, required        | —       | Marker label used in generated begin/end lines. Must be non-empty and single-line.            |
| `content`        | string, required        | —       | Managed block content. May be multi-line. A missing final newline is added inside the block.  |
| `comment_prefix` | string                  | `#`     | Prefix used for marker lines. Must be non-empty and single-line.                              |
| `create`         | boolean                 | `true`  | Create the file if it is missing.                                                             |
| `create_parents` | boolean                 | `false` | Create parent directories when creating the file.                                             |
| `mode`           | string                  | nil     | Optional mode for a created or rewritten file; also enforced when the block already matches.  |
| `owner`          | object                  | nil     | Optional owner for a created or rewritten file; also enforced when the block already matches. |

Generated marker form with the default prefix:

```text
# BEGIN <marker>
<content>
# END <marker>
```

Behavior:

- If the file is missing and `create = true`, the file is created with exactly
  the generated block.
- If the file exists and contains no generated block, the generated block is
  appended. A missing trailing newline in the original file is normalized before
  the append.
- If the file contains exactly one begin marker followed by exactly one end
  marker, that range is replaced.
- If the existing block already matches, content is unchanged; optional metadata
  is still enforced.
- If markers are incomplete, reversed, nested, or duplicated, the module fails
  instead of guessing.
- `content` must not contain the generated begin or end marker text.

Results:

- Changed: file created, block appended/replaced, or metadata changed; data is
  `{ marker = <marker>, blocks = 1 }`.
- Unchanged: one existing block already matches and no metadata change is
  required; data contains the marker and existing block count.
- Error: invalid path/marker/comment prefix/mode/owner, missing file with
  `create = false`, non-regular path, marker corruption/duplication, failed
  read/write/chmod/chown.

### `ops.file.key_value`

Create or update one simple key/value line in a text file.

Arguments:

| Argument         | Type                    | Default | Description                                                                                                       |
| ---------------- | ----------------------- | ------- | ----------------------------------------------------------------------------------------------------------------- |
| `path`           | absolute path, required | —       | Target file path.                                                                                                 |
| `key`            | string, required        | —       | Key name. Must be non-empty, single-line, contain no whitespace, and must not contain `=` when `separator = "="`. |
| `value`          | string, required        | —       | Value text. May be empty but must be single-line.                                                                 |
| `separator`      | string                  | `=`     | Either `=` or a single space (`" "`).                                                                             |
| `comment_prefix` | string                  | `#`     | Lines whose trimmed form starts with this prefix are ignored. May be empty to disable comment handling.           |
| `create`         | boolean                 | `true`  | Create the file if it is missing.                                                                                 |
| `create_parents` | boolean                 | `false` | Create parent directories when creating the file.                                                                 |
| `mode`           | string                  | nil     | Optional mode for a created or rewritten file; also enforced when the key already matches.                        |
| `owner`          | object                  | nil     | Optional owner for a created or rewritten file; also enforced when the key already matches.                       |

Behavior:

- With `separator = "="`, the desired line is `key=value`.
- With `separator = " "`, the desired line is `key value`.
- Leading whitespace before an active key is tolerated during matching, but the
  rewritten line is normalized to the desired form.
- Commented lines are ignored and preserved.
- If no active key is present, the desired line is appended.
- If exactly one active key is present with a different value, that line is
  replaced.
- If exactly one active key is already equal to the desired line, content is
  unchanged; optional metadata is still enforced.
- If more than one active key is present, the module fails to avoid silently
  choosing one.

Results:

- Changed: file created, key added, key updated, or metadata changed; data is
  `{ key = <key>, action = "added" | "updated" | "unchanged" }`.
- Unchanged: active key already matches and no metadata change is required; data
  action is `"unchanged"`.
- Error: invalid path/key/value/separator/comment prefix/mode/owner, missing
  file with `create = false`, duplicate active keys, non-regular path, failed
  read/write/chmod/chown.

## Package modules

Package modules are thin wrappers around the system package manager. They
intentionally do not auto-detect distributions and do not expose a generic
declarative package resource. Choose the module that matches the target host.

All install/remove modules are idempotent when their package-query command gives
reliable output. Update/upgrade modules are explicit operations and report
`updated` after successful command execution.

Result data for package modules is:

```lua
{ action = "install" | "remove" | "update" | "upgrade", packages = { ... } }
```

### APK (`ops.pkg.apk.*`)

| Module                | Requires | Arguments                                                                          | Command behavior                                                                                                   | Results and corner cases                                                                                                                     |
| --------------------- | -------- | ---------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `ops.pkg.apk.install` | `apk`    | `packages` required list; `no_cache` boolean default `false`; `timeout`            | Probes each package with `apk info -e <name>`. Installs missing packages with `apk add [--no-cache] <missing...>`. | Unchanged when all packages are installed. Updated when any package is missing. Fails on invalid package names or failed `apk add`.          |
| `ops.pkg.apk.remove`  | `apk`    | `packages` required list; `timeout`                                                | Probes with `apk info -e <name>`. Removes installed packages with `apk del <installed...>`.                        | Unchanged when all packages are absent. Updated when any package is installed. Fails on invalid package names or failed `apk del`.           |
| `ops.pkg.apk.update`  | `apk`    | `timeout`                                                                          | Runs `apk update`.                                                                                                 | Always updated on command success. Fails on command failure.                                                                                 |
| `ops.pkg.apk.upgrade` | `apk`    | `packages` optional non-empty list; `available` boolean default `false`; `timeout` | Runs `apk upgrade [--available] [packages...]`.                                                                    | Always updated on command success. If `packages` is omitted, upgrades generally according to apk defaults. Empty `packages = {}` is invalid. |

### APT (`ops.pkg.apt.*`)

| Module                | Requires                | Arguments                                                                                                  | Command behavior                                                                                                                                                                                                                           | Results and corner cases                                                                                                                                    |
| --------------------- | ----------------------- | ---------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ops.pkg.apt.install` | `apt-get`, `dpkg-query` | `packages` required list; `no_install_recommends` boolean default `false`; `timeout`                       | Probes each package with `dpkg-query -W -f=${Status} <name>`. Installs missing packages with `apt-get install -y [--no-install-recommends] -- <missing...>`.                                                                               | Unchanged when all packages report `install ok installed`. Updated when any package is missing. Fails on invalid package names or failed `apt-get install`. |
| `ops.pkg.apt.remove`  | `apt-get`, `dpkg-query` | `packages` required list; `purge` boolean default `false`; `autoremove` boolean default `false`; `timeout` | Probes with `dpkg-query`. Removes installed packages with `apt-get remove -y -- <installed...>` or purges with `apt-get purge -y -- <installed...>`. If `autoremove = true`, runs `apt-get autoremove -y` after a successful remove/purge. | Unchanged when all packages are absent. Updated when any package is installed. `autoremove` is not run when no package removal was needed.                  |
| `ops.pkg.apt.update`  | `apt-get`               | `timeout`                                                                                                  | Runs `apt-get update`.                                                                                                                                                                                                                     | Always updated on command success. Fails on command failure.                                                                                                |
| `ops.pkg.apt.upgrade` | `apt-get`               | `packages` optional non-empty list; `dist` boolean default `false`; `timeout`                              | With packages, runs `apt-get install --only-upgrade -y -- <packages...>`. Without packages and `dist = true`, runs `apt-get dist-upgrade -y`. Without packages and `dist = false`, runs `apt-get upgrade -y`.                              | Always updated on command success. Empty `packages = {}` is invalid.                                                                                        |

### Pacman (`ops.pkg.pacman.*`)

| Module                   | Requires | Arguments                                                                                                  | Command behavior                                                                                                                                                                                   | Results and corner cases                                                                                                          |
| ------------------------ | -------- | ---------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `ops.pkg.pacman.install` | `pacman` | `packages` required list; `refresh` boolean default `false`; `timeout`                                     | Probes each package with `pacman -Q <name>`. Installs missing packages with `pacman -S --noconfirm --needed <missing...>` or `pacman -Sy --noconfirm --needed <missing...>` when `refresh = true`. | Unchanged when all packages are installed. Updated when any package is missing. Fails on invalid package names or failed install. |
| `ops.pkg.pacman.remove`  | `pacman` | `packages` required list; `recursive` boolean default `false`; `nosave` boolean default `false`; `timeout` | Probes with `pacman -Q <name>`. Removes installed packages with `pacman -R --noconfirm [--recursive] [--nosave] <installed...>`.                                                                   | Unchanged when all packages are absent. Updated when any package is installed.                                                    |
| `ops.pkg.pacman.update`  | `pacman` | `timeout`                                                                                                  | Runs `pacman -Sy --noconfirm`.                                                                                                                                                                     | Always updated on command success. Fails on command failure.                                                                      |
| `ops.pkg.pacman.upgrade` | `pacman` | `packages` optional non-empty list; `timeout`                                                              | With packages, runs `pacman -S --noconfirm <packages...>`. Without packages, runs `pacman -Syu --noconfirm`.                                                                                       | Always updated on command success. Empty `packages = {}` is invalid.                                                              |

### XBPS (`ops.pkg.xbps.*`)

| Module                 | Requires                     | Arguments                                                                     | Command behavior                                                                                                  | Results and corner cases                                                        |
| ---------------------- | ---------------------------- | ----------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| `ops.pkg.xbps.install` | `xbps-install`, `xbps-query` | `packages` required list; `sync` boolean default `false`; `timeout`           | Probes each package with `xbps-query <name>`. Installs missing packages with `xbps-install -y [-S] <missing...>`. | Unchanged when all packages are installed. Updated when any package is missing. |
| `ops.pkg.xbps.remove`  | `xbps-remove`, `xbps-query`  | `packages` required list; `recursive` boolean default `false`; `timeout`      | Probes with `xbps-query <name>`. Removes installed packages with `xbps-remove -y [-R] <installed...>`.            | Unchanged when all packages are absent. Updated when any package is installed.  |
| `ops.pkg.xbps.update`  | `xbps-install`               | `timeout`                                                                     | Runs `xbps-install -S`.                                                                                           | Always updated on command success. Fails on command failure.                    |
| `ops.pkg.xbps.upgrade` | `xbps-install`               | `packages` optional non-empty list; `sync` boolean default `false`; `timeout` | Runs `xbps-install -y -u [-S] [packages...]`.                                                                     | Always updated on command success. Empty `packages = {}` is invalid.            |

## Service modules

Service modules are backend-specific. They do not abstract across init systems.
Choose the service manager explicitly.

### systemd (`ops.service.systemd.*`)

All systemd modules require `systemctl`. The common arguments are `unit`
(required string) and `timeout` (optional string), except `daemon_reload`, which
only accepts `timeout`.

| Module                              | Behavior                                                                                          | Results and corner cases                                                                                                                               |
| ----------------------------------- | ------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `ops.service.systemd.start`         | Runs `systemctl is-active --quiet <unit>` first. If inactive, runs `systemctl start <unit>`.      | Unchanged when already active. Updated when `start` succeeds. Fails on invalid unit or command failure. Data is `{ unit = <unit>, action = "start" }`. |
| `ops.service.systemd.stop`          | Runs `systemctl is-active --quiet <unit>` first. If active, runs `systemctl stop <unit>`.         | Unchanged when already inactive. Updated when `stop` succeeds. Data action is `"stop"`.                                                                |
| `ops.service.systemd.enable`        | Runs `systemctl is-enabled --quiet <unit>` first. If not enabled, runs `systemctl enable <unit>`. | Unchanged when already enabled. Updated when `enable` succeeds. Data action is `"enable"`.                                                             |
| `ops.service.systemd.disable`       | Runs `systemctl is-enabled --quiet <unit>` first. If enabled, runs `systemctl disable <unit>`.    | Unchanged when already disabled. Updated when `disable` succeeds. Data action is `"disable"`.                                                          |
| `ops.service.systemd.restart`       | Runs `systemctl restart <unit>`.                                                                  | Always updated on command success. Data action is `"restart"`.                                                                                         |
| `ops.service.systemd.reload`        | Runs `systemctl reload <unit>`.                                                                   | Always updated on command success. Data action is `"reload"`.                                                                                          |
| `ops.service.systemd.daemon_reload` | Runs `systemctl daemon-reload`.                                                                   | Always updated on command success. Data action is `"daemon_reload"`.                                                                                   |

### dinit (`ops.service.dinit.*`)

All dinit modules require `dinitctl`. Common arguments are `service` (required
string) and `timeout` (optional string).

| Module                      | Behavior                                                                                             | Results and corner cases                                                                                           |
| --------------------------- | ---------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `ops.service.dinit.start`   | Runs `dinitctl --quiet is-started <service>` first. If not started, runs `dinitctl start <service>`. | Unchanged when already active. Updated when `start` succeeds. Data is `{ service = <service>, action = "start" }`. |
| `ops.service.dinit.stop`    | Runs `dinitctl --quiet is-started <service>` first. If started, runs `dinitctl stop <service>`.      | Unchanged when already inactive. Updated when `stop` succeeds. Data action is `"stop"`.                            |
| `ops.service.dinit.enable`  | Runs `dinitctl enable <service>`.                                                                    | Always updated on command success. Data action is `"enable"`.                                                      |
| `ops.service.dinit.disable` | Runs `dinitctl disable <service>`.                                                                   | Always updated on command success. Data action is `"disable"`.                                                     |
| `ops.service.dinit.restart` | Runs `dinitctl restart <service>`.                                                                   | Always updated on command success. Data action is `"restart"`.                                                     |

### runit (`ops.service.runit.*`)

There are two groups of runit modules: `sv` command modules and symlink
enable/disable modules.

#### `sv` modules

Modules: `ops.service.runit.start`, `ops.service.runit.stop`,
`ops.service.runit.restart`.

Requires: `sv`.

Arguments:

| Argument      | Type             | Default        | Description                                                                             |
| ------------- | ---------------- | -------------- | --------------------------------------------------------------------------------------- |
| `service`     | string, required | —              | Service name under `service_dir`. Must be a safe service name and must not contain `/`. |
| `service_dir` | absolute path    | `/var/service` | Active runit service directory.                                                         |
| `timeout`     | string           | host default   | Command timeout.                                                                        |

Behavior:

- `start` probes `sv status <service_dir>/<service>` and treats output starting
  with `run:` as already active. Otherwise it runs `sv up <path>`.
- `stop` probes `sv status <path>` and treats output not starting with `run:` as
  already inactive. Otherwise it runs `sv down <path>`.
- `restart` runs `sv restart <path>` without a pre-check.

Results:

- `start`/`stop` may be unchanged or updated depending on the status probe.
- `restart` is always updated on command success.
- Data is `{ service = <service>, action = "start" | "stop" | "restart" }`.
- Errors include invalid service/service_dir or failed `sv` command.

#### Symlink modules

Modules: `ops.service.runit.enable`, `ops.service.runit.disable`.

Arguments:

| Module                      | Arguments                                                                                                                | Behavior                                                                  | Results and corner cases                                                                                                                                                                                                             |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `ops.service.runit.enable`  | `name` required string; `source_dir` absolute path default `/etc/sv`; `service_dir` absolute path default `/var/service` | Creates symlink `<service_dir>/<name>` pointing to `<source_dir>/<name>`. | Unchanged if the expected symlink already exists. Updated when symlink is created. Fails if the target path exists and is not the expected symlink. Data is `{ service = <name>, source = <source>, link = <link> }` when unchanged. |
| `ops.service.runit.disable` | `name` required string; `service_dir` absolute path default `/var/service`                                               | Removes symlink `<service_dir>/<name>`.                                   | Unchanged if the link is absent. Updated when symlink is removed. Fails if the path exists and is not a symlink. Data is `{ service = <name>, link = <link> }` when unchanged.                                                       |

`name` must not contain `/`.

## User modules

User modules are thin wrappers around `getent`, `useradd`, `userdel`, and
`usermod`. They do not parse `/etc/passwd` directly.

### `ops.user.create`

Create a local user account when it does not already exist.

Requires: `getent`, `useradd`.

Arguments:

| Argument      | Type             | Default      | Description                                                                               |
| ------------- | ---------------- | ------------ | ----------------------------------------------------------------------------------------- |
| `name`        | string, required | —            | User name.                                                                                |
| `uid`         | integer          | nil          | Passed as `--uid`.                                                                        |
| `group`       | string           | nil          | Primary group, passed as `--gid`.                                                         |
| `groups`      | list of strings  | nil          | Supplementary groups, passed as comma-separated `--groups`.                               |
| `home`        | absolute path    | nil          | Home directory, passed as `--home-dir`.                                                   |
| `create_home` | boolean          | nil          | `true` passes `--create-home`; `false` passes `--no-create-home`; omitted passes neither. |
| `shell`       | absolute path    | nil          | Login shell, passed as `--shell`.                                                         |
| `comment`     | string           | nil          | GECOS/comment, passed as `--comment`.                                                     |
| `system`      | boolean          | `false`      | Pass `--system`.                                                                          |
| `timeout`     | string           | host default | Command timeout.                                                                          |

Behavior and results:

- Probes with `getent passwd <name>`.
- If the user exists, returns unchanged with data `{ user = <name> }`.
- If absent, runs `useradd` with the requested options and returns updated with
  data `{ user = <name> }`.
- Fails on invalid names/paths or command failure.

### `ops.user.remove`

Remove a local user account when it exists.

Requires: `getent`, `userdel`.

Arguments:

| Argument      | Type             | Default      | Description      |
| ------------- | ---------------- | ------------ | ---------------- |
| `name`        | string, required | —            | User name.       |
| `remove_home` | boolean          | `false`      | Pass `--remove`. |
| `force`       | boolean          | `false`      | Pass `--force`.  |
| `timeout`     | string           | host default | Command timeout. |

Behavior and results:

- Probes with `getent passwd <name>`.
- If absent, returns unchanged with data `{ user = <name> }`.
- If present, runs `userdel [--force] [--remove] <name>` and returns updated
  with data `{ user = <name> }`.
- Fails on invalid names or command failure.

### `ops.user.update`

Update an existing local user account.

Requires: `getent`, `usermod`.

Arguments:

| Argument        | Type             | Default      | Description                                                 |
| --------------- | ---------------- | ------------ | ----------------------------------------------------------- |
| `name`          | string, required | —            | User name.                                                  |
| `uid`           | integer          | nil          | Passed as `--uid`.                                          |
| `group`         | string           | nil          | Primary group, passed as `--gid`.                           |
| `groups`        | list of strings  | nil          | Supplementary groups, passed as comma-separated `--groups`. |
| `append_groups` | boolean          | `false`      | Pass `--append`; requires `groups`.                         |
| `home`          | absolute path    | nil          | Home directory, passed as `--home`.                         |
| `move_home`     | boolean          | `false`      | Pass `--move-home`; requires `home`.                        |
| `shell`         | absolute path    | nil          | Login shell, passed as `--shell`.                           |
| `comment`       | string           | nil          | GECOS/comment, passed as `--comment`.                       |
| `lock`          | boolean          | `false`      | Pass `--lock`. Mutually exclusive with `unlock`.            |
| `unlock`        | boolean          | `false`      | Pass `--unlock`. Mutually exclusive with `lock`.            |
| `timeout`       | string           | host default | Command timeout.                                            |

Behavior and results:

- Requires at least one update option besides `name`/`timeout`.
- Probes with `getent passwd <name>` and fails if the user does not exist.
- Runs `usermod` with the requested options and returns updated with data
  `{ user = <name> }`.
- This module does not attempt to determine whether requested fields already
  match the current account. A successful `usermod` is reported as updated.
- Fails on invalid names/paths, mutually exclusive `lock`/`unlock`, missing
  dependent options, absent user, or command failure.

## Tests

`wali-ops` tests are black-box shell tests. They create temporary manifests,
point wali at this repository's `modules/` directory, and prepend fake target
commands to `PATH` so command arguments and idempotence branches can be checked
without touching the host package or service manager.

Run them with a wali binary on `PATH`:

```sh
tests/run.sh
```

Or point the harness at an explicit binary:

```sh
WALI_BIN=/path/to/wali tests/run.sh
```

The harness is written for POSIX `sh` and avoids Bash, Python, `jq`, and other
non-essential test dependencies.
