local async = require("plenary.async")

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

function DirectoryCache:get(path, callback)
  async.run(function()
    local entries = self:_get_async(path)
    if callback then
      callback(entries)
    end
  end)
end

function DirectoryCache:_get_async(path)
  local stat = async.uv.fs_stat(path)
  if not stat or stat.type ~= "directory" then
    return nil
  end

  local current_mtime = stat.mtime.sec

  local cached = self._cache[path]
  if cached and self._trust_mtime and cached.mtime == current_mtime then
    return cached.entries
  end

  local entries = self:_read_directory(path)
  if entries then
    self._cache[path] = {
      path = path,
      entries = entries,
      mtime = current_mtime,
    }
  end

  return entries
end

function DirectoryCache:_read_directory(path)
  local fd, err = async.uv.fs_opendir(path, nil, 100)
  if not fd then
    return nil
  end

  local all_entries = {}

  while true do
    local entries = async.uv.fs_readdir(fd)
    if not entries then
      break
    end
    for _, entry in ipairs(entries) do
      table.insert(all_entries, entry)
    end
  end

  async.uv.fs_closedir(fd)
  return all_entries
end

function DirectoryCache:invalidate(path)
  self._cache[path] = nil
end

function DirectoryCache:clear_all()
  self._cache = {}
end

return M
