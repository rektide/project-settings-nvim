local coop = require("coop")
local uv = require("coop.uv")

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

local function read_directory_coro(path)
  local err, fd = uv.fs_opendir(path, 100)
  if err or not fd then
    return nil
  end

  local all_entries = {}

  while true do
    local readdir_err, entries = uv.fs_readdir(fd)
    if readdir_err or not entries then
      break
    end
    for _, entry in ipairs(entries) do
      table.insert(all_entries, entry)
    end
  end

  uv.fs_closedir(fd)
  return all_entries
end

function DirectoryCache:get_async(path)
  local err, stat = uv.fs_stat(path)
  if err or not stat or stat.type ~= "directory" then
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

function DirectoryCache:get(path, callback)
  local future = coop.Future.new()
  local task = coop.spawn(function()
    local result = self:get_async(path)
    if callback then
      callback(result)
    end
    future:complete(result)
  end)
  return task
end

function DirectoryCache:invalidate(path)
  self._cache[path] = nil
end

function DirectoryCache:clear_all()
  self._cache = {}
end

return M
