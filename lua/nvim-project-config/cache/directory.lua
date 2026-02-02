local async = require("plenary.async")
local uv = async.uv

local M = {}

local DirectoryCache = {}
DirectoryCache.__index = DirectoryCache

function M.new(opts)
  opts = opts or {}
  local self = setmetatable({}, DirectoryCache)
  self._cache = {}
  self._trust_mtime = opts.trust_mtime ~= false
  return self
end

-- Pure coroutine helper (must be called from within async context)
local function read_directory_coro(path)
  local fd = uv.fs_opendir(path, nil, 100)
  if not fd then
    return nil
  end

  local all_entries = {}

  while true do
    local entries = uv.fs_readdir(fd)
    if not entries then
      break
    end
    for _, entry in ipairs(entries) do
      table.insert(all_entries, entry)
    end
  end

  uv.fs_closedir(fd)
  return all_entries
end

-- Primary async API (call from within async.run or coroutine context)
function DirectoryCache:get_async(path)
  local stat = uv.fs_stat(path)
  if not stat or stat.type ~= "directory" then
    return nil
  end

  local current_mtime = stat.mtime.sec

  local cached = self._cache[path]
  if cached and self._trust_mtime and cached.mtime == current_mtime then
    return cached.entries
  end

  local entries = read_directory_coro(path)
  if entries then
    self._cache[path] = {
      path = path,
      entries = entries,
      mtime = current_mtime,
    }
  end

  return entries
end

-- Callback API (safe to call from non-async context)
function DirectoryCache:get(path, callback)
  async.run(function()
    return self:get_async(path)
  end, callback)
end

function DirectoryCache:invalidate(path)
  self._cache[path] = nil
end

function DirectoryCache:clear_all()
  self._cache = {}
end

return M
