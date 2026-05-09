# wali-ops

`wali-ops` is a small set of external modules for
[wali](https://github.com/milchinskiy/wali).

Modules are written as verbs. A task describes the operation it is about to run:

```lua
{
    id = "install-nginx",
    module = "ops.pkg.apt.install",
    args = { packages = { "nginx" }, no_install_recommends = true },
}
```

There is no generic `package` or `service` resource here. If a host uses APT,
use an APT module. If it uses systemd, use a systemd module. That keeps the
module behavior easy to read and close to the command that will actually run.

## Compatibility

This branch requires Wali `>=0.2.0 <0.3.0`. The modules check the running Wali
runtime with `require("wali").require_version(...)` when they are loaded, so an
incompatible Wali binary fails early and clearly.

## Using this repository from wali

Point a wali manifest at the `modules/` directory and choose a namespace:

```lua
modules = {
    {
        namespace = "ops",
        git = {
            url = "https://github.com/milchinskiy/wali-ops.git",
            ref = "master",
            path = "modules",
            depth = 1,
        },
    },
}
```

Then reference modules by path:

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

## Conventions

All paths are paths on the target host. Where a module validates a path, it
expects an absolute path. This applies to arguments such as `path`, `dest`,
`home`, `shell`, `source_dir`, and `service_dir`.

A `timeout` argument, when present, is passed to wali command execution. Use the
same timeout strings wali accepts, for example `10s` or `2m`.

Name validation is strict on purpose:

- package names must not be empty, contain whitespace/control characters, or
  start with `-`;
- service and unit names must not be empty, contain whitespace/control
  characters or `/`, or start with `-`;
- user and group names must not be empty, contain whitespace/control characters,
  contain `:` or `/`, or start with `-`.

`mode` is an octal string accepted by `wali.builtin.lib.mode_bits`, such as
`"0644"`. `owner` is an object in this form:

```lua
owner = { user = "root", group = "root" }
```

Either `user` or `group` may be omitted. Modules that expose `mode` and `owner`
apply them while writing the file. Some file modules also enforce them when the
file content already matches. Modules that do not expose these arguments never
perform metadata-only changes.

Command modules fail the task when validation, probing, or command execution
fails. Idempotent modules first check the current state with the target system's
own tools. Direct operations such as `update`, `upgrade`, `restart`, `reload`,
and `daemon_reload` report a change after the command succeeds.

## Module reference

### `ops.app.curl`

Downloads one URL with `curl`.

Requires: `curl`.

Arguments:

| Argument  | Required | Default      | Notes                                            |
| --------- | -------- | ------------ | ------------------------------------------------ |
| `url`     | yes      | —            | Non-empty URL. Control characters are rejected.  |
| `dest`    | yes      | —            | Absolute destination path.                       |
| `parents` | no       | `false`      | Create the destination parent directory first.   |
| `replace` | no       | `true`       | If `false` and `dest` exists, skip the download. |
| `timeout` | no       | host default | Timeout for the curl command.                    |
| `mode`    | no       | nil          | Mode applied after a successful download.        |
| `owner`   | no       | nil          | Owner applied after a successful download.       |

Behavior:

- Existing files are kept when `replace = false`; the task is skipped and no
  metadata changes are made in that case.
- Downloads are written to a temporary file in the destination directory and
  then renamed into place.
- Temporary files are removed after a failed download when possible.

Results:

- changed: the file was downloaded and moved into place;
- skipped: `dest` already existed and `replace = false`;
- error: invalid arguments, missing parent directory, failed curl command,
  failed rename, or failed metadata update.

### `ops.app.wget`

Same contract as `ops.app.curl`, but uses `wget`.

Requires: `wget`.

The command form is `wget --output-document <tmp> -- <url>`.

## File modules

These modules edit plain text. They do not try to understand INI, YAML, TOML,
JSON, shell syntax, or service-specific configuration formats.

### `ops.file.line`

Ensures one exact line exists in a file.

Arguments:

| Argument  | Required | Default | Notes                                                            |
| --------- | -------- | ------- | ---------------------------------------------------------------- |
| `path`    | yes      | —       | Absolute file path.                                              |
| `line`    | yes      | —       | Non-empty single line. `\n` and `\r` are rejected.               |
| `create`  | no       | `true`  | Create the file when missing.                                    |
| `parents` | no       | `false` | Create parent directories when creating the file.                |
| `mode`    | no       | nil     | Applied when the file is created, rewritten, or already correct. |
| `owner`   | no       | nil     | Applied when the file is created, rewritten, or already correct. |

Behavior:

- Matching is exact and line-based.
- Existing paths must be regular files.
- Missing files are created as `line .. "\n"` when `create = true`.
- When the line already exists, content is left alone and optional metadata is
  still checked.
- When appending, a missing trailing newline is added before the new line.

Results: changed when the file is created, the line is appended, or metadata
changes; unchanged when the line and metadata already match; error on invalid
input, missing file with `create = false`, non-file paths, or filesystem
failure.

### `ops.file.remove_line`

Removes exact line occurrences from an existing file.

Arguments:

| Argument     | Required | Default | Notes                                                                |
| ------------ | -------- | ------- | -------------------------------------------------------------------- |
| `path`       | yes      | —       | Absolute file path.                                                  |
| `line`       | yes      | —       | Non-empty single line. `\n` and `\r` are rejected.                   |
| `all`        | no       | `true`  | Remove all matches. If `false`, remove the first current match only. |
| `missing_ok` | no       | `true`  | Treat a missing file as unchanged.                                   |

Behavior:

- The module never creates files.
- The module never changes file mode or ownership.
- Matching is exact and line-based.
- `all = false` is a one-match operation. If more matching lines remain, a later
  apply can remove another one.
- Existing paths must be regular files.

Result data includes `{ removals = <count> }`. The result is changed when at
least one line is removed, unchanged when no line is removed, and an error on
invalid input, missing file with `missing_ok = false`, non-file paths, or
filesystem failure.

### `ops.file.replace`

Replaces literal text in an existing file.

Arguments:

| Argument  | Required | Default | Notes                                                                          |
| --------- | -------- | ------- | ------------------------------------------------------------------------------ |
| `path`    | yes      | —       | Absolute file path.                                                            |
| `find`    | yes      | —       | Non-empty literal text to search for.                                          |
| `replace` | yes      | —       | Literal replacement text. May be empty.                                        |
| `all`     | no       | `true`  | Replace all current matches. If `false`, replace only the first current match. |

Behavior:

- The module never creates files.
- The module never changes file mode or ownership.
- `find` is literal text, not a Lua pattern and not a regular expression.
- `all = false` is a one-match operation. If more matches remain, a later apply
  can replace another one.
- Existing paths must be regular files.

Result data includes `{ replacements = <count> }`. The result is changed when at
least one replacement is made, unchanged when `find` is absent, and an error on
invalid input, missing files, non-file paths, or filesystem failure.

### `ops.file.block`

Manages one marked block in a text file.

Arguments:

| Argument         | Required | Default | Notes                                                            |
| ---------------- | -------- | ------- | ---------------------------------------------------------------- |
| `path`           | yes      | —       | Absolute file path.                                              |
| `marker`         | yes      | —       | Non-empty single-line marker label.                              |
| `content`        | yes      | —       | Block content. May span multiple lines.                          |
| `comment_prefix` | no       | `#`     | Prefix for marker lines. Must be a single non-empty line.        |
| `create`         | no       | `true`  | Create the file when missing.                                    |
| `parents`        | no       | `false` | Create parent directories when creating the file.                |
| `mode`           | no       | nil     | Applied when the file is created, rewritten, or already correct. |
| `owner`          | no       | nil     | Applied when the file is created, rewritten, or already correct. |

With the default prefix, the generated block looks like this:

```text
# BEGIN <marker>
<content>
# END <marker>
```

Behavior:

- Missing files are created with just the generated block when `create = true`.
- Files without the block get the block appended. A missing trailing newline is
  added first.
- Files with exactly one begin marker followed by exactly one end marker have
  that range replaced.
- Files with missing, reversed, nested, or duplicated markers fail instead of
  guessing.
- `content` must not contain the generated begin or end marker line.

Result data includes `{ marker = <marker>, blocks = 1 }` for changed writes and
for a matching existing block. The module errors on invalid input, missing file
with `create = false`, non-file paths, corrupted markers, or filesystem failure.

### `ops.file.key_value`

Sets one simple key/value line.

Arguments:

| Argument         | Required | Default | Notes                                                                                           |
| ---------------- | -------- | ------- | ----------------------------------------------------------------------------------------------- |
| `path`           | yes      | —       | Absolute file path.                                                                             |
| `key`            | yes      | —       | Non-empty single-line key. Whitespace is rejected. With `separator = "="`, `=` is rejected too. |
| `value`          | yes      | —       | Single-line value. Empty string is allowed.                                                     |
| `separator`      | no       | `=`     | Either `=` or a single space (`" "`).                                                           |
| `comment_prefix` | no       | `#`     | Trimmed lines starting with this prefix are ignored. Empty string disables comment handling.    |
| `create`         | no       | `true`  | Create the file when missing.                                                                   |
| `parents`        | no       | `false` | Create parent directories when creating the file.                                               |
| `mode`           | no       | nil     | Applied when the file is created, rewritten, or already correct.                                |
| `owner`          | no       | nil     | Applied when the file is created, rewritten, or already correct.                                |

Behavior:

- With `separator = "="`, the desired line is `key=value`.
- With `separator = " "`, the desired line is `key value`.
- Leading whitespace before an active key is tolerated while matching, but the
  final line is normalized to the desired form.
- Commented lines are ignored and preserved.
- No active key: append the desired line.
- One active key with a different value: replace that line.
- One matching active key: leave content alone and still check optional
  metadata.
- More than one active key: fail, because silently choosing one would be unsafe.

Result data includes
`{ key = <key>, action = "added" | "updated" | "unchanged" }`. The module errors
on invalid input, missing file with `create = false`, duplicate active keys,
non-file paths, or filesystem failure.

## Package modules

Package modules are small wrappers around the named package manager. They do not
try to detect the distribution.

Install/remove modules probe package state first and can return unchanged.
Update/upgrade modules run the command directly and return changed after a
successful command.

Package result data has this shape:

```lua
{ action = "install" | "remove" | "update" | "upgrade", packages = { ... } }
```

Package-name validation is shared: names must be non-empty, contain no
whitespace or control characters, and must not start with `-`.

### APK

| Module                | Requires | Arguments                                         | Command behavior                                                                                   |
| --------------------- | -------- | ------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| `ops.pkg.apk.install` | `apk`    | `packages` required; `no_cache=false`; `timeout`  | Probe with `apk info -e <pkg>`. Install missing packages with `apk add [--no-cache] <missing...>`. |
| `ops.pkg.apk.remove`  | `apk`    | `packages` required; `timeout`                    | Probe with `apk info -e <pkg>`. Remove installed packages with `apk del <installed...>`.           |
| `ops.pkg.apk.update`  | `apk`    | `timeout`                                         | Run `apk update`.                                                                                  |
| `ops.pkg.apk.upgrade` | `apk`    | optional `packages`; `available=false`; `timeout` | Run `apk upgrade [--available] [packages...]`. Empty `packages = {}` is invalid.                   |

### APT

| Module                | Requires                | Arguments                                                         | Command behavior                                                                                                                                                                        |
| --------------------- | ----------------------- | ----------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ops.pkg.apt.install` | `apt-get`, `dpkg-query` | `packages` required; `no_install_recommends=false`; `timeout`     | Probe with `dpkg-query -W -f=${Status} <pkg>`. Install missing packages with `apt-get install -y [--no-install-recommends] -- <missing...>`.                                            |
| `ops.pkg.apt.remove`  | `apt-get`, `dpkg-query` | `packages` required; `purge=false`; `autoremove=false`; `timeout` | Probe with `dpkg-query`. Remove or purge installed packages. If something was removed and `autoremove=true`, run `apt-get autoremove -y`.                                               |
| `ops.pkg.apt.update`  | `apt-get`               | `timeout`                                                         | Run `apt-get update`.                                                                                                                                                                   |
| `ops.pkg.apt.upgrade` | `apt-get`               | optional `packages`; `dist=false`; `timeout`                      | Without `packages`, run `apt-get upgrade -y` or `apt-get dist-upgrade -y`. With `packages`, run `apt-get install --only-upgrade -y -- <packages...>`. Empty `packages = {}` is invalid. |

APT commands are run with `DEBIAN_FRONTEND=noninteractive`.

### pacman

| Module                   | Requires | Arguments                                                         | Command behavior                                                                                                                                     |
| ------------------------ | -------- | ----------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ops.pkg.pacman.install` | `pacman` | `packages` required; `refresh=false`; `timeout`                   | Probe with `pacman -Q <pkg>`. Install missing packages with `pacman -S` or `pacman -Sy`, always using `--noconfirm --needed`.                        |
| `ops.pkg.pacman.remove`  | `pacman` | `packages` required; `recursive=false`; `nosave=false`; `timeout` | Probe with `pacman -Q <pkg>`. Remove installed packages with `pacman -R` or `pacman -Rs`, always using `--noconfirm`; add `--nosave` when requested. |
| `ops.pkg.pacman.update`  | `pacman` | `timeout`                                                         | Run `pacman -Sy --noconfirm`.                                                                                                                        |
| `ops.pkg.pacman.upgrade` | `pacman` | optional `packages`; `timeout`                                    | Without `packages`, run `pacman -Syu --noconfirm`. With `packages`, run `pacman -S --noconfirm <packages...>`. Empty `packages = {}` is invalid.     |

### XBPS

| Module                 | Requires                     | Arguments                                         | Command behavior                                                                                    |
| ---------------------- | ---------------------------- | ------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| `ops.pkg.xbps.install` | `xbps-install`, `xbps-query` | `packages` required; `sync=false`; `timeout`      | Probe with `xbps-query <pkg>`. Install missing packages with `xbps-install -y [-S] <missing...>`.   |
| `ops.pkg.xbps.remove`  | `xbps-remove`, `xbps-query`  | `packages` required; `recursive=false`; `timeout` | Probe with `xbps-query <pkg>`. Remove installed packages with `xbps-remove -y [-R] <installed...>`. |
| `ops.pkg.xbps.update`  | `xbps-install`               | `timeout`                                         | Run `xbps-install -S`.                                                                              |
| `ops.pkg.xbps.upgrade` | `xbps-install`               | optional `packages`; `sync=false`; `timeout`      | Run `xbps-install -u -y [-S] [packages...]`. Empty `packages = {}` is invalid.                      |

## Service modules

Service modules validate service names and pass them to the selected service
manager. `start`, `stop`, `enable`, and `disable` are idempotent when the
backend has a simple status check. `restart`, `reload`, and `daemon_reload` are
direct operations and return changed after a successful command.

Service result data is usually:

```lua
{ service = <name>, action = <action> }
```

For systemd, the key is `unit` instead of `service`.

### systemd

Requires: `systemctl`.

| Module                              | Arguments                  | Behavior                                                                                               |
| ----------------------------------- | -------------------------- | ------------------------------------------------------------------------------------------------------ |
| `ops.service.systemd.start`         | `unit` required; `timeout` | If `systemctl is-active --quiet <unit>` succeeds, unchanged. Otherwise run `systemctl start <unit>`.   |
| `ops.service.systemd.stop`          | `unit` required; `timeout` | If `is-active` fails, unchanged. Otherwise run `systemctl stop <unit>`.                                |
| `ops.service.systemd.enable`        | `unit` required; `timeout` | If `systemctl is-enabled --quiet <unit>` succeeds, unchanged. Otherwise run `systemctl enable <unit>`. |
| `ops.service.systemd.disable`       | `unit` required; `timeout` | If `is-enabled` fails, unchanged. Otherwise run `systemctl disable <unit>`.                            |
| `ops.service.systemd.restart`       | `unit` required; `timeout` | Run `systemctl restart <unit>`.                                                                        |
| `ops.service.systemd.reload`        | `unit` required; `timeout` | Run `systemctl reload <unit>`.                                                                         |
| `ops.service.systemd.daemon_reload` | `timeout`                  | Run `systemctl daemon-reload`.                                                                         |

### dinit

Requires: `dinitctl`.

| Module                      | Arguments                     | Behavior                                                                                                  |
| --------------------------- | ----------------------------- | --------------------------------------------------------------------------------------------------------- |
| `ops.service.dinit.start`   | `service` required; `timeout` | If `dinitctl --quiet is-started <service>` succeeds, unchanged. Otherwise run `dinitctl start <service>`. |
| `ops.service.dinit.stop`    | `service` required; `timeout` | If `is-started` fails, unchanged. Otherwise run `dinitctl stop <service>`.                                |
| `ops.service.dinit.enable`  | `service` required; `timeout` | Run `dinitctl enable <service>`.                                                                          |
| `ops.service.dinit.disable` | `service` required; `timeout` | Run `dinitctl disable <service>`.                                                                         |
| `ops.service.dinit.restart` | `service` required; `timeout` | Run `dinitctl restart <service>`.                                                                         |

### runit: `sv` modules

Requires: `sv`.

| Module                      | Arguments                                                 | Behavior                                                                                                                |
| --------------------------- | --------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| `ops.service.runit.start`   | `service` required; `service_dir=/var/service`; `timeout` | Probe `sv status <service_dir>/<service>`. Output starting with `run:` is already active; otherwise run `sv up <path>`. |
| `ops.service.runit.stop`    | `service` required; `service_dir=/var/service`; `timeout` | Probe `sv status <path>`. Non-`run:` output is already inactive; otherwise run `sv down <path>`.                        |
| `ops.service.runit.restart` | `service` required; `service_dir=/var/service`; `timeout` | Run `sv restart <path>`.                                                                                                |

`service_dir` must be absolute. `service` is a name under that directory, not a
path.

### runit: symlink modules

| Module                      | Arguments                                                         | Behavior                                                                                                                                                    |
| --------------------------- | ----------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ops.service.runit.enable`  | `name` required; `source_dir=/etc/sv`; `service_dir=/var/service` | Create `<service_dir>/<name>` as a symlink to `<source_dir>/<name>`. If the expected symlink already exists, unchanged. If another path exists there, fail. |
| `ops.service.runit.disable` | `name` required; `service_dir=/var/service`                       | Remove `<service_dir>/<name>` if it is a symlink. Missing links are unchanged. Non-symlink paths fail.                                                      |

Enable/disable result data includes the link path. Enable also includes the
source path.

## Group modules

Group modules use `getent group` for existence checks and then call `groupadd`
or `groupdel`. They do not edit `/etc/group` directly.

### `ops.group.create`

Requires: `getent`, `groupadd`.

Arguments:

| Argument  | Required | Default      | Notes                                       |
| --------- | -------- | ------------ | ------------------------------------------- |
| `name`    | yes      | —            | Group name.                                 |
| `gid`     | no       | nil          | Passed as `--gid`. Must be zero or greater. |
| `system`  | no       | `false`      | Pass `--system`.                            |
| `timeout` | no       | host default | Command timeout.                            |

If `getent group <name>` succeeds, the result is unchanged. Existing groups are
not reconciled against `gid` or `system`. Otherwise the module runs `groupadd`
and returns changed. Result data is `{ group = <name> }`.

### `ops.group.remove`

Requires: `getent`, `groupdel`.

Arguments:

| Argument  | Required | Default      | Notes            |
| --------- | -------- | ------------ | ---------------- |
| `name`    | yes      | —            | Group name.      |
| `timeout` | no       | host default | Command timeout. |

If the group is already absent, the result is unchanged. Otherwise the module
runs `groupdel <name>` and returns changed. Result data is `{ group = <name> }`.

## User modules

User modules use `getent` for existence checks and then call `useradd`,
`userdel`, or `usermod`. They do not edit `/etc/passwd` directly.

### `ops.user.create`

Requires: `getent`, `useradd`.

Arguments:

| Argument      | Required | Default      | Notes                                                                                     |
| ------------- | -------- | ------------ | ----------------------------------------------------------------------------------------- |
| `name`        | yes      | —            | User name.                                                                                |
| `uid`         | no       | nil          | Passed as `--uid`.                                                                        |
| `group`       | no       | nil          | Primary group, passed as `--gid`.                                                         |
| `groups`      | no       | nil          | Supplementary groups, passed as comma-separated `--groups`.                               |
| `home`        | no       | nil          | Absolute path, passed as `--home-dir`.                                                    |
| `create_home` | no       | nil          | `true` passes `--create-home`; `false` passes `--no-create-home`; omitted passes neither. |
| `shell`       | no       | nil          | Absolute path, passed as `--shell`.                                                       |
| `comment`     | no       | nil          | Passed as `--comment`.                                                                    |
| `system`      | no       | `false`      | Pass `--system`.                                                                          |
| `timeout`     | no       | host default | Command timeout.                                                                          |

If `getent passwd <name>` succeeds, the result is unchanged. Otherwise the
module runs `useradd` and returns changed. Result data is `{ user = <name> }`.

### `ops.user.remove`

Requires: `getent`, `userdel`.

Arguments:

| Argument      | Required | Default      | Notes            |
| ------------- | -------- | ------------ | ---------------- |
| `name`        | yes      | —            | User name.       |
| `remove_home` | no       | `false`      | Pass `--remove`. |
| `force`       | no       | `false`      | Pass `--force`.  |
| `timeout`     | no       | host default | Command timeout. |

If the user is already absent, the result is unchanged. Otherwise the module
runs `userdel [--force] [--remove] <name>` and returns changed. Result data is
`{ user = <name> }`.

### `ops.user.update`

Requires: `getent`, `usermod`.

Arguments:

| Argument        | Required | Default      | Notes                                                       |
| --------------- | -------- | ------------ | ----------------------------------------------------------- |
| `name`          | yes      | —            | User name.                                                  |
| `uid`           | no       | nil          | Passed as `--uid`.                                          |
| `group`         | no       | nil          | Primary group, passed as `--gid`.                           |
| `groups`        | no       | nil          | Supplementary groups, passed as comma-separated `--groups`. |
| `append_groups` | no       | `false`      | Pass `--append`; requires `groups`.                         |
| `home`          | no       | nil          | Absolute path, passed as `--home`.                          |
| `move_home`     | no       | `false`      | Pass `--move-home`; requires `home`.                        |
| `shell`         | no       | nil          | Absolute path, passed as `--shell`.                         |
| `comment`       | no       | nil          | Passed as `--comment`.                                      |
| `lock`          | no       | `false`      | Pass `--lock`; mutually exclusive with `unlock`.            |
| `unlock`        | no       | `false`      | Pass `--unlock`; mutually exclusive with `lock`.            |
| `timeout`       | no       | host default | Command timeout.                                            |

At least one update option is required. The module fails if the user does not
exist. It does not inspect the current account fields; a successful `usermod` is
reported as changed. Result data is `{ user = <name> }`.

## Tests

The tests are black-box shell tests. They write temporary manifests, point wali
at this repository's `modules/` directory, and place fake
package/service/group/user commands at the front of `PATH`.

Run all tests with a wali binary on `PATH`:

```sh
tests/run.sh
```

Or provide the binary explicitly:

```sh
WALI_BIN=/path/to/wali tests/run.sh
```

The harness is POSIX `sh` and avoids Bash, Python, `jq`, and similar extras.
