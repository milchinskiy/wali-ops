# wali-ops

Small, practical external modules for
[wali](https://github.com/milchinskiy/wali) host automation.

`wali-ops` intentionally keeps modules imperative and verb-oriented. A task says
what it does:

```lua
{
    id = "install-nginx",
    module = "ops.pkg.apt.install",
    args = { packages = { "nginx" }, no_install_recommends = true },
}
```

## Using as a wali module source

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

## Layout

```text
modules/
  app/              explicit download helpers around curl/wget
  file/             small text-file operations
  pkg/              verb-oriented package-manager operations
  service/          verb-oriented service-manager operations
  user/             local user account operations
```
