--- Find files stage for nvim-project-config pipeline
--- Finds config files based on project name and config directory
--- @module nvim-project-config.stages.find_files

local async = require("plenary.async")
local uv = async.uv

local EXTENSION_ORDER = { ".json", ".lua", ".vim" }

local function extension_priority(ext)
  for i, e in ipairs(EXTENSION_ORDER) do
    if e == ext then
      return i
    end
  end
  return #EXTENSION_ORDER + 1
end

local function collect_files_from_dir(dir_path, extensions, dir_cache)
  local files = {}
  local entries

  if dir_cache then
    entries = dir_cache:_get_async(dir_path)
  else
    local fd = uv.fs_opendir(dir_path, nil, 100)
    if not fd then
      return files
    end
    entries = {}
    while true do
      local batch = uv.fs_readdir(fd)
      if not batch then
        break
      end
      for _, entry in ipairs(batch) do
        table.insert(entries, entry)
      end
    end
    uv.fs_closedir(fd)
  end

  if not entries then
    return files
  end

  local ext_set = {}
  for _, ext in ipairs(extensions) do
    ext_set[ext] = true
  end

  for _, entry in ipairs(entries) do
    if entry.type == "file" then
      local ext = entry.name:match("(%.[^.]+)$")
      if ext and ext_set[ext] then
        table.insert(files, dir_path .. "/" .. entry.name)
      end
    end
  end

  return files
end

local function sort_files(files)
  table.sort(files, function(a, b)
    local ext_a = a:match("(%.[^.]+)$") or ""
    local ext_b = b:match("(%.[^.]+)$") or ""
    local prio_a = extension_priority(ext_a)
    local prio_b = extension_priority(ext_b)
    if prio_a ~= prio_b then
      return prio_a < prio_b
    end
    return a < b
  end)
end

--- Create a find_files stage
--- @param opts table|nil options
--- @param opts.extensions table list of extensions to look for (default: {".lua", ".vim", ".json"})
--- @return function async stage function(ctx, input_rx, output_tx)
local function find_files(opts)
  opts = opts or {}
  opts.extensions = opts.extensions or { ".lua", ".vim", ".json" }

  return function(ctx, input_rx, output_tx)
    local pipeline = require("nvim-project-config.pipeline")
    while true do
      if ctx._pipeline_stopped then
        return
      end
      
      local path = input_rx.recv()
      if path == nil or path == pipeline.DONE then
        break
      end

      local project_name = ctx.project_name
      if not project_name then
        goto continue
      end

      local config_dir = ctx.config_dir
      if type(config_dir) == "function" then
        config_dir = config_dir(ctx)
      end
      if not config_dir then
        goto continue
      end

      local collected = {}
      local parts = {}
      for part in project_name:gmatch("[^/]+") do
        table.insert(parts, part)
      end

      local path_segments = {}
      for i = 1, #parts do
        local segment = table.concat(parts, "/", 1, i)
        table.insert(path_segments, segment)
      end

      for _, segment in ipairs(path_segments) do
        for _, ext in ipairs(opts.extensions) do
          local file_path = config_dir .. "/" .. segment .. ext
          local err, stat = uv.fs_stat(file_path)
          if stat and stat.type == "file" then
            table.insert(collected, file_path)
          end
        end

        local dir_path = config_dir .. "/" .. segment
        local err, dir_stat = uv.fs_stat(dir_path)
        if dir_stat and dir_stat.type == "directory" then
          local dir_files = collect_files_from_dir(dir_path, opts.extensions, ctx.dir_cache)
          for _, f in ipairs(dir_files) do
            table.insert(collected, f)
          end
        end
      end

      sort_files(collected)

      for _, file_path in ipairs(collected) do
        if ctx._pipeline_stopped then
          return
        end
        output_tx.send(file_path)
      end

      ::continue::
    end
  end
end

return find_files
