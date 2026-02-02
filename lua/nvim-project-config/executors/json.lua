--- JSON file executor for nvim-project-config
--- @module nvim-project-config.executors.json

local async = require("plenary.async")

--- Write ctx.json to the last project-named JSON file
--- @param ctx table pipeline context with json data and _last_project_json path
--- @return boolean success
local function write_json(ctx)
  -- Compute expected path if not set (happens when file is deleted)
  if not ctx._last_project_json then
    if not ctx.project_name or not ctx.config_dir then
      return false
    end
    ctx._last_project_json = ctx.config_dir .. "/" .. ctx.project_name .. ".json"
  end

  -- Get raw data from reactive table
  local raw_json
  if ctx.json and type(ctx.json._get_data) == "function" then
    raw_json = ctx.json._get_data()
  else
    -- Fallback for non-reactive tables
    raw_json = {}
    for k, v in pairs(ctx.json or {}) do
      raw_json[k] = v
    end
  end

  local encoded = vim.json.encode(raw_json)

  if ctx.file_cache then
    local success = ctx.file_cache:write_async(ctx._last_project_json, {
      content = encoded,
    })
    return success
  end

  return false
end

--- Check if file matches project name (basename or parent dir)
--- @param file_path string
--- @param project_name string
--- @return boolean
local function matches_project_name(file_path, project_name)
  if not project_name then
    return false
  end
  local basename = vim.fn.fnamemodify(file_path, ":t:r")
  if basename == project_name then
    return true
  end
  local parent = vim.fn.fnamemodify(file_path, ":h:t")
  return parent == project_name
end

--- Execute a JSON config file
--- @param ctx table pipeline context
--- @param file_path string absolute path to the JSON file
local function json_executor(ctx, file_path)
  local content

  if ctx.file_cache then
    local entry = ctx.file_cache:get_async(file_path)
    if not entry then
      -- File doesn't exist yet - set up path for future writes and skip loading
      if matches_project_name(file_path, ctx.project_name) then
        ctx._last_project_json = file_path
      end
      return
    end
    content = entry.content
  else
    local fd, err = io.open(file_path, "r")
    if not fd then
      error("Failed to read JSON file: " .. file_path .. " - " .. tostring(err))
    end
    content = fd:read("*a")
    fd:close()
  end

  local ok, parsed = pcall(vim.json.decode, content)
  if not ok then
    error("Failed to parse JSON: " .. file_path .. " - " .. tostring(parsed))
  end

  local function deep_merge_into(target, source)
    for k, v in pairs(source) do
      if type(v) == "table" and type(target[k]) == "table" then
        deep_merge_into(target[k], v)
      else
        target[k] = v
      end
    end
  end

  -- Merge into existing reactive table, don't replace it
  -- This preserves the reactive behavior
  if ctx.json then
    deep_merge_into(ctx.json, parsed)
  else
    ctx.json = parsed
  end

  if matches_project_name(file_path, ctx.project_name) then
    ctx._last_project_json = file_path
  end
  
  -- Set _last_project_json even if file doesn't exist yet
  -- This ensures reactive writes can create new files
  if not ctx._last_project_json and matches_project_name(file_path, ctx.project_name) then
    ctx._last_project_json = file_path
  end

  if ctx.file_cache then
    local cached = ctx.file_cache._cache and ctx.file_cache._cache[file_path]
    if cached then
      cached.json = parsed
    end
  end
end

return {
  executor = json_executor,
  write_json = write_json,
}
