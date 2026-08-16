# beez-registry

Catalog of published Beez workflow plugins. The `beez` ReqPack package manager reads
`plugins.json` from this repository to discover installable plugins.

## Layout

```
beez-registry/
  plugins.json    # plugin catalog (id, version, description, source)
  README.md
```

## How discovery works

1. `beez` PM loads `default-plugin-repositories.json` (bundled with the PM).
2. The default repository points at `plugins.json` in this repo (raw GitHub URL).
3. Each catalog entry references a Beez release asset: `plugins/index.json`.
4. The release index lists platform-specific `.rqp` packages with download URLs and hashes.

```
plugins.json (this repo)
    └── source.url → Beez release plugins/index.json
            └── packages[].url → coditary-<plugin>-<version>-<platform>-<arch>.rqp
```

## Adding or updating plugins

Official Coditary plugins are developed in [Coditary/Beez](https://github.com/Coditary/Beez)
under `plugins/coditary/<name>/<version>/`.

After changing plugin sources in Beez, refresh this catalog:

```bash
cd ../Beez
lua scripts/ci/sync_plugin_catalog.lua
```

Review the diff in `../beez-registry/plugins.json`, commit, and push.

Third-party plugins can be added directly to `plugins.json` if they publish their own
release index, or via `source` in `build.lua` (`github:org/repo`) without a catalog entry.

Standalone plugin repos are bootstrapped under `~/Dev/Coditary/beez-plugins/` from the
Beez monorepo (`lua scripts/ci/bootstrap_standalone_plugins.lua`). Suggested naming:
`Coditary/beez-plugin-<name>`.

Clang plugins use the shared monorepo `Coditary/beez-clang` (see `lua scripts/ci/bootstrap_beez_clang_monorepo.lua`).

### Monorepo install

Git catalog entries and `build.lua` sources support repository subdirectories:

```json
"source": {
  "type": "git",
  "url": "github:Coditary/beez-clang",
  "path": "clang-format",
  "ref": "1.0.0"
}
```

Shorthand in `build.lua`: `source = "github:Coditary/beez-clang#clang-format"`.

## PM configuration

Default repository URL (in Beez PM):

```
https://raw.githubusercontent.com/Coditary/beez-registry/main/plugins.json
```

Local checkout for development:

```
~/Dev/Coditary/beez-registry
```
