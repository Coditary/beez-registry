# beez-registry

Catalog of published Beez workflow plugins. The `beez` ReqPack package manager reads
`plugins.json` from this repository to discover installable plugins.

## Layout

```
beez-registry/
  plugins.json          # plugin catalog (id, version, description, source)
  beez-cli-index.json   # binary downloads for beez-cli
  README.md
```

The ReqPack plugin implementation for Beez is in a separate repository:
[Coditary/rqp-plugin-beez](https://github.com/Coditary/rqp-plugin-beez)

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

Official Coditary workflow plugins live in the monorepo
[Coditary/beez-plugins](https://github.com/Coditary/beez-plugins), organized as
`<letter>/beez-<name>/` (letter = first character after the `beez-` prefix).

`plugins.json` entries use:

```json
"source": {
  "type": "git",
  "url": "github:Coditary/beez-plugins",
  "path": "g/beez-go",
  "ref": "1.0.0"
}
```

Clang sub-packages use paths under `c/beez-clang/` (`clang`, `clang-format`, `clang-tidy`).

Third-party plugins can be added directly to `plugins.json` if they publish their own
release index, or via `source` in `build.lua` (`github:org/repo`) without a catalog entry.

### Monorepo install

Git catalog entries and `build.lua` sources support repository subdirectories:

Shorthand in `build.lua`: `source = "github:Coditary/beez-plugins#g/beez-go"`.

## PM configuration

Default repository URL (in Beez PM):

```
https://raw.githubusercontent.com/Coditary/beez-registry/main/plugins.json
```

Local checkout for development:

```
~/Dev/Coditary/beez-registry
```
