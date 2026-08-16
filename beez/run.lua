plugin = {}

local PLUGIN_NAME = "beez"
local PLUGIN_VERSION = "1.0.3"
local GIT_BINARY = "git"
local STATE_SCHEMA_VERSION = 1

local function trim(value)
  return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function starts_with(value, prefix)
  return tostring(value or ""):sub(1, #prefix) == prefix
end

local function read_proc_environ_value(name)
  if os ~= nil and type(os.getenv) == "function" then
    local current = os.getenv(tostring(name or ""))
    if current ~= nil and current ~= "" then
      return trim(current)
    end
  end

  local handle = io.open("/proc/self/environ", "rb")
  if handle == nil then
    return nil
  end
  local payload = handle:read("*a")
  handle:close()
  if payload == nil or payload == "" then
    return nil
  end

  local prefix = tostring(name or "") .. "="
  for entry in tostring(payload):gmatch("[^%z]+") do
    if starts_with(entry, prefix) then
      return trim(entry:sub(#prefix + 1))
    end
  end
  return nil
end

local function exec_run(context, command)
  if context ~= nil and context.exec ~= nil and type(context.exec.run) == "function" then
    return context.exec.run(command)
  end
  if reqpack ~= nil and reqpack.exec ~= nil and type(reqpack.exec.run) == "function" then
    return reqpack.exec.run(command)
  end
  return nil
end

local function run_command(context, command)
  local result = exec_run(context, command)
  if result ~= nil then
    return result.success == true, trim(result.stdout or ""), tonumber(result.exitCode) or 1
  end
  return run_shell(command)
end

local function join_path(...)
  local parts = {}
  for index = 1, select("#", ...) do
    local part = trim(select(index, ...))
    if part ~= "" then
      if #parts == 0 then
        parts[#parts + 1] = part:gsub("[/\\]+$", "")
      else
        parts[#parts + 1] = part:gsub("^[/\\]+", ""):gsub("[/\\]+$", "")
      end
    end
  end
  if #parts == 0 then
    return "."
  end
  return table.concat(parts, "/")
end

local function shell_quote(value)
  return "'" .. tostring(value or ""):gsub("'", "'\\''") .. "'"
end

local function run_shell(command)
  local handle = io.popen(command .. " 2>&1")
  if handle == nil then
    return false, "", 1
  end
  local output = handle:read("*a") or ""
  local ok, _, code = handle:close()
  if ok == true then
    return true, output, 0
  end
  return false, output, tonumber(code) or 1
end

local function shell_success(command)
  local success = run_shell(command)
  return success
end

local function read_file(path)
  local file = io.open(path, "rb")
  if file == nil then
    return nil
  end
  local content = file:read("*a") or ""
  file:close()
  return content
end

local function write_file(path, content)
  local parent = path:match("^(.*)/[^/]+$")
  if parent ~= nil and parent ~= "" then
    run_shell("mkdir -p " .. shell_quote(parent))
  end
  local file, err = io.open(path, "wb")
  if file == nil then
    return false, err
  end
  file:write(content or "")
  file:close()
  return true
end

local function decode_json(text)
  local index = 1
  local length = #text

  local function skip_whitespace()
    while index <= length and text:sub(index, index):match("%s") do
      index = index + 1
    end
  end

  local parse_value

  local function parse_string()
    index = index + 1
    local start_index = index
    while index <= length do
      local char = text:sub(index, index)
      if char == '"' then
        local value = text:sub(start_index, index - 1)
        index = index + 1
        return value
      end
      if char == "\\" then
        index = index + 2
      else
        index = index + 1
      end
    end
    error("unterminated json string")
  end

  local function parse_array()
    index = index + 1
    skip_whitespace()
    local items = {}
    if text:sub(index, index) == "]" then
      index = index + 1
      return items
    end
    while true do
      items[#items + 1] = parse_value()
      skip_whitespace()
      local char = text:sub(index, index)
      if char == "]" then
        index = index + 1
        return items
      end
      if char ~= "," then
        error("expected ',' in array")
      end
      index = index + 1
      skip_whitespace()
    end
  end

  local function parse_object()
    index = index + 1
    skip_whitespace()
    local object = {}
    if text:sub(index, index) == "}" then
      index = index + 1
      return object
    end
    while true do
      skip_whitespace()
      if text:sub(index, index) ~= '"' then
        error("expected object key")
      end
      local key = parse_string()
      skip_whitespace()
      if text:sub(index, index) ~= ":" then
        error("expected ':'")
      end
      index = index + 1
      object[key] = parse_value()
      skip_whitespace()
      local char = text:sub(index, index)
      if char == "}" then
        index = index + 1
        return object
      end
      if char ~= "," then
        error("expected ',' in object")
      end
      index = index + 1
    end
  end

  function parse_value()
    skip_whitespace()
    local char = text:sub(index, index)
    if char == '"' then
      return parse_string()
    end
    if char == "{" then
      return parse_object()
    end
    if char == "[" then
      return parse_array()
    end
    if char == "t" and text:sub(index, index + 3) == "true" then
      index = index + 4
      return true
    end
    if char == "f" and text:sub(index, index + 4) == "false" then
      index = index + 5
      return false
    end
    if char == "n" and text:sub(index, index + 3) == "null" then
      index = index + 4
      return nil
    end
    local start_index = index
    while index <= length and text:sub(index, index):match("[%d%+%-%.eE]") do
      index = index + 1
    end
    local number_text = text:sub(start_index, index - 1)
    if number_text ~= "" then
      return tonumber(number_text)
    end
    error("invalid json token")
  end

  local value = parse_value()
  return value
end

local function read_json_file(path)
  local content = read_file(path)
  if content == nil then
    return nil, "file not found: " .. path
  end
  local ok, value = pcall(decode_json, content)
  if not ok then
    return nil, "failed to parse json: " .. tostring(value)
  end
  return value
end

local function fetch_json(url, context)
  local target = trim(url)
  if starts_with(target, "file://") then
    return read_json_file(target:sub(8))
  end
  if starts_with(target, "/") then
    return read_json_file(target)
  end
  local ok, output, code = run_command(context, "curl -fsSL " .. shell_quote(target))
  if not ok then
    return nil, "failed to fetch " .. target .. " (exit " .. tostring(code) .. ")"
  end
  local ok_decode, value = pcall(decode_json, output)
  if not ok_decode then
    return nil, "failed to parse json from " .. target
  end
  return value
end

local function cache_home()
  local cache_home_env = read_proc_environ_value("XDG_CACHE_HOME")
  if cache_home_env ~= nil and cache_home_env ~= "" then
    return cache_home_env
  end
  local home = read_proc_environ_value("HOME")
  if home == nil or home == "" then
    return nil
  end
  return join_path(home, ".cache")
end

local function data_home()
  local data_home_env = read_proc_environ_value("XDG_DATA_HOME")
  if data_home_env ~= nil and data_home_env ~= "" then
    return data_home_env
  end
  local home = read_proc_environ_value("HOME")
  if home == nil or home == "" then
    return nil
  end
  return join_path(home, ".local/share")
end

local function plugin_dir(context)
  if context ~= nil and context.plugin ~= nil and trim(context.plugin.dir) ~= "" then
    return trim(context.plugin.dir)
  end
  local data = data_home()
  if data == nil then
    return nil
  end
  return join_path(data, "reqpack/plugins", PLUGIN_NAME)
end

local function state_paths(cache_root)
  return {
    cache_root = cache_root,
    plugins_root = join_path(cache_root, "plugins"),
    index_root = join_path(cache_root, "index"),
    installed_path = join_path(cache_root, "index", "installed.json"),
    catalog_cache_path = join_path(cache_root, "index", "catalog.json"),
  }
end

local function default_data_root()
  local cache = cache_home()
  if cache == nil then
    return nil
  end
  return join_path(cache, "beez")
end

local function split_plugin_id(plugin_id)
  local text = trim(plugin_id)
  local slash = text:find("/", 1, true)
  if slash == nil or slash == 1 or slash == #text then
    return nil, nil
  end
  return text:sub(1, slash - 1), text:sub(slash + 1)
end

local function plugin_install_path(paths, organization, name, version)
  return join_path(paths.plugins_root, organization, name, version)
end

local function plugin_script_path(paths, organization, name, version)
  return join_path(plugin_install_path(paths, organization, name, version), "beez_plugin.lua")
end

local function is_installed(paths, organization, name, version)
  return shell_success("test -f " .. shell_quote(plugin_script_path(paths, organization, name, version)))
end

local function load_installed_records(paths)
  local records = read_json_file(paths.installed_path)
  if records == nil or type(records) ~= "table" then
    return { schemaVersion = STATE_SCHEMA_VERSION, plugins = {} }
  end
  if records.plugins == nil then
    records.plugins = {}
  end
  return records
end

local function save_installed_records(paths, records)
  run_shell("mkdir -p " .. shell_quote(paths.index_root))
  local lines = {
    "{",
    '  "schemaVersion": ' .. STATE_SCHEMA_VERSION .. ",",
    '  "plugins": [',
  }
  for plugin_index, record in ipairs(records.plugins or {}) do
    lines[#lines + 1] = "    {"
    lines[#lines + 1] = string.format('      "id": %q,', record.id)
    lines[#lines + 1] = string.format('      "organization": %q,', record.organization)
    lines[#lines + 1] = string.format('      "name": %q,', record.name)
    lines[#lines + 1] = string.format('      "version": %q,', record.version)
    lines[#lines + 1] = string.format('      "path": %q,', record.path)
    lines[#lines + 1] = string.format('      "sourceType": %q', record.sourceType or "unknown")
    if plugin_index == #(records.plugins or {}) then
      lines[#lines + 1] = "    }"
    else
      lines[#lines + 1] = "    },"
    end
  end
  lines[#lines + 1] = "  ]"
  lines[#lines + 1] = "}"
  write_file(paths.installed_path, table.concat(lines, "\n") .. "\n")
end

local function upsert_installed(records, record)
  local updated = { schemaVersion = STATE_SCHEMA_VERSION, plugins = {} }
  local replaced = false
  for _, existing in ipairs(records.plugins or {}) do
    if existing.id == record.id then
      updated.plugins[#updated.plugins + 1] = record
      replaced = true
    else
      updated.plugins[#updated.plugins + 1] = existing
    end
  end
  if not replaced then
    updated.plugins[#updated.plugins + 1] = record
  end
  return updated
end

local function load_repository_config(context)
  local dir = plugin_dir(context)
  if dir == nil then
    return nil, "plugin directory unavailable"
  end
  local config = read_json_file(join_path(dir, "default-plugin-repositories.json"))
  if config == nil then
    return nil, "default-plugin-repositories.json not found"
  end
  return config
end

local function refresh_catalog(context, paths)
  local config, config_error = load_repository_config(context)
  if config == nil then
    return nil, config_error
  end

  local catalog = {}
  for _, repository in ipairs(config.repositories or {}) do
    if repository.enabled ~= false then
      local url = trim(repository.url)
      if url ~= "" then
        local payload, fetch_error = fetch_json(url, context)
        if payload == nil then
          return nil, fetch_error
        end
        for _, entry in ipairs(payload.plugins or {}) do
          catalog[#catalog + 1] = entry
        end
      end
    end
  end

  run_shell("mkdir -p " .. shell_quote(paths.index_root))
  return catalog
end

local function find_catalog_record(catalog, plugin_id, version)
  local wanted_version = trim(version)
  for _, entry in ipairs(catalog or {}) do
    if trim(entry.id) == trim(plugin_id) then
      if wanted_version == "" or trim(entry.version) == wanted_version then
        return entry
      end
    end
  end
  return nil
end

local function host_architecture()
  local ok, output = run_shell("uname -m")
  if not ok then
    return "x86_64"
  end
  local arch = trim(output)
  if arch == "amd64" then
    return "x86_64"
  end
  if arch == "arm64" then
    return "aarch64"
  end
  return arch
end

local function host_system()
  local ok, output = run_shell("uname -s")
  if not ok then
    return "linux"
  end
  local system = trim(output):lower()
  if system == "darwin" then
    return "macos"
  end
  return "linux"
end

local function select_index_package(index, plugin_id)
  local arch = host_architecture()
  local system = host_system()
  for _, entry in ipairs(index.packages or {}) do
    if trim(entry.name) == trim(plugin_id)
      and trim(entry.architecture) == arch
      and type(entry.system) == "table"
      and trim(entry.system[1]) == system then
      return entry
    end
  end
  return nil
end

local function download_file(url, destination, context)
  run_shell("mkdir -p " .. shell_quote(destination:match("^(.*)/[^/]+$") or "."))
  local ok, output, code = run_command(context, "curl -fL " .. shell_quote(url) .. " -o " .. shell_quote(destination))
  if not ok then
    return false, "download failed (" .. tostring(code) .. "): " .. trim(output)
  end
  return true
end

local function install_rqp_archive(context, archive_path)
  local command = "rqp --non-interactive install " .. shell_quote(archive_path)
  if context ~= nil and context.exec ~= nil and type(context.exec.run) == "function" then
    local result = context.exec.run(command)
    if not result.success then
      return false, trim(result.stderr ~= "" and result.stderr or result.stdout)
    end
    return true
  end
  local ok, output, code = run_shell(command)
  if not ok then
    return false, "rqp install failed (" .. tostring(code) .. "): " .. trim(output)
  end
  return true
end

local function is_repo_shorthand(value)
  local text = trim(value)
  return text:match("^[%w%-%._]+/[%w%-%._]+$") ~= nil
end

local function normalize_git_url(value)
  local text = trim(value)
  if starts_with(text, "github:") then
    local shorthand = text:sub(8)
    if is_repo_shorthand(shorthand) then
      return "https://github.com/" .. shorthand .. ".git"
    end
    return shorthand
  end
  if is_repo_shorthand(text) then
    return "https://github.com/" .. text .. ".git"
  end
  return text
end

local function parse_git_source(value)
  local text = trim(value)
  local subpath = ""
  local hash = text:find("#", 1, true)
  if hash ~= nil then
    subpath = trim(text:sub(hash + 1)):gsub("^[/\\]+", ""):gsub("[/\\]+$", "")
    text = trim(text:sub(1, hash - 1))
  end
  return normalize_git_url(text), subpath
end

local function append_git_subpath(source_url, subpath)
  local url, existing_subpath = parse_git_source(source_url)
  local resolved_subpath = trim(subpath)
  if resolved_subpath == "" then
    resolved_subpath = existing_subpath
  end
  if resolved_subpath == "" then
    return url
  end
  return url .. "#" .. resolved_subpath
end

local function copy_tree(source, destination)
  run_shell("mkdir -p " .. shell_quote(destination))
  local ok, output = run_shell("cp -R " .. shell_quote(join_path(source, ".")) .. " " .. shell_quote(destination))
  if not ok then
    return false, trim(output)
  end
  return true
end

local function git_clone_repository(git_url, clone_root, source_ref)
  local attempts = {}
  local wanted_ref = trim(source_ref)
  if wanted_ref ~= "" then
    attempts[#attempts + 1] = wanted_ref
    if not starts_with(wanted_ref, "v") then
      attempts[#attempts + 1] = "v" .. wanted_ref
    end
  end
  attempts[#attempts + 1] = ""

  local last_output = ""
  local last_code = 1
  for _, ref in ipairs(attempts) do
    run_shell("rm -rf " .. shell_quote(clone_root))
    local clone_command = GIT_BINARY .. " clone --depth 1 "
    if ref ~= "" then
      clone_command = clone_command .. "--branch " .. shell_quote(ref) .. " "
    end
    clone_command = clone_command .. shell_quote(git_url) .. " " .. shell_quote(clone_root)
    local ok, output, code = run_shell(clone_command)
    if ok then
      return true
    end
    last_output = output
    last_code = code
  end
  return false, last_output, last_code
end

local function read_beez_package_manifest(root)
  local manifest = read_json_file(join_path(root, "beez.package.json"))
  if manifest ~= nil then
    return manifest
  end
  if shell_success("test -f " .. shell_quote(join_path(root, "beez_plugin.lua"))) then
    return {
      organization = nil,
      name = nil,
      version = "0.0.0",
      entry = "beez_plugin.lua",
    }
  end
  return nil
end

local function install_from_git(context, paths, plugin_id, version, source_url, source_ref)
  local organization, name = split_plugin_id(plugin_id)
  if organization == nil then
    return false, "plugin id must use organization/name"
  end

  local git_url, subpath = parse_git_source(source_url)
  local temp_root = join_path(paths.index_root, "git")
  local clone_key = git_url:gsub("[^%w]+", "-"):gsub("^-+", ""):gsub("-+$", "")
  if clone_key == "" then
    clone_key = organization .. "-" .. name
  end
  local clone_root = join_path(temp_root, clone_key)
  run_shell("rm -rf " .. shell_quote(clone_root))
  run_shell("mkdir -p " .. shell_quote(temp_root))

  local ok, output, code = git_clone_repository(git_url, clone_root, source_ref)
  if not ok then
    return false, "git clone failed (" .. tostring(code) .. "): " .. trim(output)
  end

  local plugin_root = clone_root
  if subpath ~= "" then
    plugin_root = join_path(clone_root, subpath)
    if not shell_success("test -d " .. shell_quote(plugin_root)) then
      return false, "plugin path not found in repository: " .. subpath
    end
  end

  local manifest = read_beez_package_manifest(plugin_root)
  if manifest == nil then
    return false, "repository does not contain beez.package.json or beez_plugin.lua"
  end

  organization = trim(manifest.organization) ~= "" and trim(manifest.organization) or organization
  name = trim(manifest.name) ~= "" and trim(manifest.name) or name
  version = trim(version) ~= "" and trim(version) or trim(manifest.version)
  if version == "" then
    version = "0.0.0"
  end

  local install_root = plugin_install_path(paths, organization, name, version)
  run_shell("rm -rf " .. shell_quote(install_root))
  local copied, copy_error = copy_tree(plugin_root, install_root)
  if not copied then
    return false, copy_error
  end

  if not is_installed(paths, organization, name, version) then
    return false, "git install did not produce beez_plugin.lua"
  end

  return true, organization, name, version
end

local function install_from_index(context, paths, plugin_id, catalog_entry)
  local source = catalog_entry.source or {}
  if trim(source.type) ~= "" and trim(source.type) ~= "index" then
    return false, "catalog entry does not provide index source for " .. plugin_id
  end
  local index, fetch_error = fetch_json(trim(source.url), context)
  if index == nil then
    return false, fetch_error
  end
  local package_entry = select_index_package(index, plugin_id)
  if package_entry == nil then
    return false, "no package for host platform in index for " .. plugin_id
  end
  local temp_dir = join_path(paths.index_root, "downloads")
  local archive_name = package_entry.url:match("/([^/]+)$") or "plugin.rqp"
  local archive_path = join_path(temp_dir, archive_name)
  local downloaded, download_error = download_file(package_entry.url, archive_path, context)
  if not downloaded then
    return false, download_error
  end
  return install_rqp_archive(context, archive_path)
end

local function install_from_git_catalog(context, paths, plugin_id, catalog_entry)
  local source = catalog_entry.source or {}
  local url = trim(source.url)
  if url == "" then
    return false, "catalog git source requires url for " .. plugin_id
  end
  url = append_git_subpath(url, trim(source.path))
  local source_ref = trim(source.ref)
  if source_ref == "" then
    source_ref = trim(catalog_entry.version)
  end
  return install_from_git(context, paths, plugin_id, trim(catalog_entry.version), url, source_ref)
end

local function install_from_catalog_entry(context, paths, plugin_id, catalog_entry)
  local source = catalog_entry.source or {}
  local source_type = trim(source.type)
  if source_type == "git" then
    return install_from_git_catalog(context, paths, plugin_id, catalog_entry)
  end
  if source_type == "" or source_type == "index" then
    return install_from_index(context, paths, plugin_id, catalog_entry)
  end
  return false, "unsupported catalog source type for " .. plugin_id .. ": " .. source_type
end

local function parse_package_spec(pkg)
  local name = trim(pkg.name)
  local version = trim(pkg.version)
  local source = nil
  local source_path = ""
  if type(pkg.extraFields) == "table" then
    source = trim(pkg.extraFields.source)
    source_path = trim(pkg.extraFields.path or pkg.extraFields.sourcePath)
  end
  if (source == nil or source == "") and type(pkg.source) == "string" then
    source = trim(pkg.source)
  end
  if (source == nil or source == "") then
    local env_source = trim(read_proc_environ_value("BEEZ_PLUGIN_SOURCE") or "")
    if env_source ~= "" then
      source = env_source
    end
  end
  if source ~= nil and source ~= "" and source_path ~= "" then
    source = append_git_subpath(source, source_path)
  end
  return name, version, source
end

local function tx_begin(context, label)
  if context ~= nil and context.tx ~= nil and type(context.tx.begin_step) == "function" then
    context.tx.begin_step(label)
  end
end

local function tx_success(context)
  if context ~= nil and context.tx ~= nil and type(context.tx.success) == "function" then
    context.tx.success()
  end
end

local function tx_failed(context, message)
  if context ~= nil and context.tx ~= nil and type(context.tx.failed) == "function" then
    context.tx.failed(message)
  end
end

local function emit_event(context, name, payload)
  if context ~= nil and context.events ~= nil and type(context.events[name]) == "function" then
    context.events[name](payload)
  end
end

function plugin.getName()
  return PLUGIN_NAME
end

function plugin.getVersion()
  return PLUGIN_VERSION
end

function plugin.getRequirements()
  return {}
end

function plugin.getCategories()
  return { "Beez", "Build", "Plugins" }
end

function plugin.getSecurityMetadata()
  return {
    role = "package-manager",
    capabilities = { "exec", "network" },
    privilegeLevel = "user",
    writeScopes = {
      { kind = "user-home-subpath", value = ".cache/beez" },
      { kind = "user-home-subpath", value = ".local/share/reqpack/plugins/beez" },
    },
    networkScopes = { "github.com", "raw.githubusercontent.com" },
  }
end

function plugin.getMissingPackages(packages)
  local cache_root = default_data_root()
  if cache_root == nil then
    return packages or {}
  end
  local paths = state_paths(cache_root)
  local missing = {}
  for _, pkg in ipairs(packages or {}) do
    local plugin_id, version = parse_package_spec(pkg)
    local organization, name = split_plugin_id(plugin_id)
    if organization ~= nil and not is_installed(paths, organization, name, version) then
      missing[#missing + 1] = pkg
    end
  end
  return missing
end

function plugin.install(context, packages)
  tx_begin(context, "install beez plugins")

  local cache_root = default_data_root()
  if cache_root == nil then
    tx_failed(context, "cache directory unavailable")
    return false
  end
  local paths = state_paths(cache_root)
  local catalog, catalog_error = refresh_catalog(context, paths)
  if catalog == nil then
    tx_failed(context, catalog_error)
    return false
  end

  local records = load_installed_records(paths)
  local requested = plugin.getMissingPackages(packages)
  if #requested == 0 then
    tx_success(context)
    return true
  end

  for _, pkg in ipairs(requested) do
    local plugin_id, version, source = parse_package_spec(pkg)
    local organization, name = split_plugin_id(plugin_id)
    if organization == nil then
      tx_failed(context, "plugin id must use organization/name: " .. plugin_id)
      return false
    end

    local installed = false
    if source ~= nil and source ~= "" then
      local ok, err_or_org, git_name, git_version = install_from_git(context, paths, plugin_id, version, source, version)
      if not ok then
        tx_failed(context, err_or_org)
        return false
      end
      organization = err_or_org
      name = git_name
      version = git_version
      installed = true
    else
      local catalog_entry = find_catalog_record(catalog, plugin_id, version)
      if catalog_entry ~= nil then
        local source_type = trim((catalog_entry.source or {}).type)
        if source_type == "git" then
          local ok, err_or_org, git_name, git_version = install_from_git_catalog(context, paths, plugin_id, catalog_entry)
          if not ok then
            tx_failed(context, err_or_org)
            return false
          end
          organization = err_or_org
          name = git_name
          version = git_version
        else
          local ok, install_error = install_from_catalog_entry(context, paths, plugin_id, catalog_entry)
          if not ok then
            tx_failed(context, install_error)
            return false
          end
          version = trim(catalog_entry.version)
        end
        installed = true
      elseif starts_with(plugin_id, "github:") or is_repo_shorthand(plugin_id) then
        local ok, err_or_org, git_name, git_version = install_from_git(context, paths, plugin_id, version, plugin_id, version)
        if not ok then
          tx_failed(context, err_or_org)
          return false
        end
        organization = err_or_org
        name = git_name
        version = git_version
        plugin_id = organization .. "/" .. name
        installed = true
      end
    end

    if not installed then
      tx_failed(context, "plugin not found in catalog and no source provided: " .. plugin_id)
      return false
    end

    if not is_installed(paths, organization, name, version) then
      tx_failed(context, "plugin install did not produce expected files for " .. plugin_id)
      return false
    end

    records = upsert_installed(records, {
      id = organization .. "/" .. name,
      organization = organization,
      name = name,
      version = version,
      path = plugin_install_path(paths, organization, name, version),
      sourceType = source ~= "" and "git" or "index",
    })
    emit_event(context, "installed", { name = plugin_id, version = version })
  end

  save_installed_records(paths, records)
  tx_success(context)
  return true
end

function plugin.installLocal(context, path)
  tx_begin(context, "install local beez plugin")

  local cache_root = default_data_root()
  if cache_root == nil then
    tx_failed(context, "cache directory unavailable")
    return false
  end
  local paths = state_paths(cache_root)

  if trim(path):match("%.rqp$") then
    local ok, install_error = install_rqp_archive(context, path)
    if not ok then
      tx_failed(context, install_error)
      return false
    end
    tx_success(context)
    return true
  end

  local manifest = read_beez_package_manifest(path)
  if manifest == nil then
    tx_failed(context, "local path is not a beez plugin directory")
    return false
  end

  local organization = trim(manifest.organization)
  local name = trim(manifest.name)
  local version = trim(manifest.version)
  if organization == "" or name == "" then
    tx_failed(context, "beez.package.json requires organization and name")
    return false
  end
  if version == "" then
    version = "0.0.0"
  end

  local install_root = plugin_install_path(paths, organization, name, version)
  run_shell("rm -rf " .. shell_quote(install_root))
  local copied, copy_error = copy_tree(path, install_root)
  if not copied then
    tx_failed(context, copy_error)
    return false
  end

  local records = load_installed_records(paths)
  records = upsert_installed(records, {
    id = organization .. "/" .. name,
    organization = organization,
    name = name,
    version = version,
    path = install_root,
    sourceType = "local",
  })
  save_installed_records(paths, records)
  emit_event(context, "installed", { name = organization .. "/" .. name, version = version, localTarget = true })
  tx_success(context)
  return true
end

function plugin.remove(context, packages)
  tx_begin(context, "remove beez plugins")
  local cache_root = default_data_root()
  if cache_root == nil then
    tx_failed(context, "cache directory unavailable")
    return false
  end
  local paths = state_paths(cache_root)
  local records = load_installed_records(paths)

  for _, pkg in ipairs(packages or {}) do
    local plugin_id = trim(pkg.name)
    for index, record in ipairs(records.plugins) do
      if record.id == plugin_id then
        run_shell("rm -rf " .. shell_quote(record.path))
        table.remove(records.plugins, index)
        emit_event(context, "deleted", { name = plugin_id, version = record.version })
        break
      end
    end
  end

  save_installed_records(paths, records)
  tx_success(context)
  return true
end

function plugin.update(context, packages)
  return plugin.install(context, packages)
end

function plugin.list(context)
  local cache_root = default_data_root()
  if cache_root == nil then
    return {}
  end
  local records = load_installed_records(state_paths(cache_root))
  local items = {}
  for _, record in ipairs(records.plugins or {}) do
    items[#items + 1] = {
      name = record.id,
      version = record.version,
      description = "Installed Beez plugin",
      extraFields = { path = record.path, sourceType = record.sourceType },
    }
  end
  return items
end

function plugin.search(context, prompt)
  local cache_root = default_data_root()
  if cache_root == nil then
    return {}
  end
  local paths = state_paths(cache_root)
  local catalog, catalog_error = refresh_catalog(context, paths)
  if catalog == nil then
    return {}
  end

  local query = trim(prompt)
  local items = {}
  for _, entry in ipairs(catalog) do
    if query == ""
      or trim(entry.id):find(query, 1, true)
      or trim(entry.description or ""):find(query, 1, true) then
      items[#items + 1] = {
        name = entry.id,
        version = entry.version,
        description = entry.description or "",
        extraFields = { source = entry.source },
      }
    end
  end
  return items
end

function plugin.info(context, name)
  local plugin_id = trim(name)
  local cache_root = default_data_root()
  if cache_root == nil then
    return {}
  end
  local paths = state_paths(cache_root)
  local records = load_installed_records(paths)
  for _, record in ipairs(records.plugins or {}) do
    if record.id == plugin_id then
      return {
        name = record.id,
        version = record.version,
        description = "Installed Beez plugin",
        extraFields = { path = record.path, sourceType = record.sourceType },
      }
    end
  end

  local catalog, _ = refresh_catalog(context, paths)
  if catalog ~= nil then
    local entry = find_catalog_record(catalog, plugin_id, "")
    if entry ~= nil then
      return {
        name = entry.id,
        version = entry.version,
        description = entry.description or "",
        extraFields = { source = entry.source, tags = entry.tags },
      }
    end
  end
  return {}
end

function plugin.outdated(context)
  return {}
end

function plugin.init()
  local ok = run_shell("command -v " .. shell_quote(GIT_BINARY) .. " >/dev/null")
  return ok
end

function plugin.shutdown()
  return true
end

return plugin
