local coop = require("coop")
local uv = require("coop.uv")
local MpscQueue = require("coop.mpsc-queue").MpscQueue

local FileCache = {}
FileCache.__index = FileCache

function FileCache.new(opts)
  opts = opts or {}
  return setmetatable({
    trust_mtime = opts.trust_mtime ~= false,
    _cache = {},
  }, FileCache)
end

local function read_file(path)
  local err, stat = uv.fs_stat(path)
  if err or not stat then
    return nil
  end

  local open_err, fd = uv.fs_open(path, "r", 438)
  if open_err or not fd then
    return nil
  end

  local read_err, content = uv.fs_read(fd, stat.size, 0)
  uv.fs_close(fd)

  if read_err or not content then
    return nil
  end

  return {
    path = path,
    content = content,
    mtime = stat.mtime.sec,
    json = nil,
  }
end

local function write_file(path, content)
  local err, fd = uv.fs_open(path, "w", 438)

  if err then
    return false, "Failed to open file: " .. tostring(err)
  end

  local write_err, bytes = uv.fs_write(fd, content, -1)
  uv.fs_close(fd)

  if write_err then
    return false, "Write error: " .. tostring(write_err)
  end

  local stat_err, stat = uv.fs_stat(path)
  return true, stat and stat.mtime.sec or nil
end

function FileCache:get_async(path)
  local cached = self._cache[path]

  if not cached or not self.trust_mtime then
    local entry = read_file(path)
    if entry then
      self._cache[path] = entry
    end
    return entry
  end

  local err, mtime = uv.fs_stat(path)
  if not err and mtime and mtime.mtime.sec == cached.mtime then
    return cached
  end

  local entry = read_file(path)
  if entry then
    self._cache[path] = entry
  else
    self._cache[path] = nil
  end
  return entry
end

local write_queue = MpscQueue.new()

coop.spawn(function()
  while true do
    local write_req = write_queue:pop()
    write_file(write_req.path, write_req.data)
  end
end)

function FileCache:write_async(path, data)
  local content
  if type(data) == "table" then
    content = data.content
  else
    content = data
  end

  if not content then
    return false
  end

  write_queue:push({ path = path, data = content })
  return true
end

return {
  new = FileCache.new,
  _queue_write = function(path, data)
    write_queue:push({ path = path, data = data })
  end,
}
