local async = require("plenary.async")
local uv = async.uv

local FileCache = {}
FileCache.__index = FileCache

function FileCache.new(opts)
  opts = opts or {}
  return setmetatable({
    trust_mtime = opts.trust_mtime ~= false,
    _cache = {},
  }, FileCache)
end

-- Async file helpers (must be called from coroutine context)
local function read_file_async(path)
  local stat = uv.fs_stat(path)
  if not stat then
    return nil
  end

  local fd = uv.fs_open(path, "r", 438)
  if not fd then
    return nil
  end

  local content = uv.fs_read(fd, stat.size, 0)
  uv.fs_close(fd)

  if not content then
    return nil
  end

  return {
    path = path,
    content = content,
    mtime = stat.mtime.sec,
    json = nil,
  }
end

local function write_file_async(path, content)
  local fd = uv.fs_open(path, "w", 438)
  if not fd then
    return false, nil
  end

  local _, write_err = uv.fs_write(fd, content, 0)
  uv.fs_close(fd)

  if write_err then
    return false, nil
  end

  local stat = uv.fs_stat(path)
  return true, stat and stat.mtime.sec or nil
end

local function get_mtime_async(path)
  local stat = uv.fs_stat(path)
  return stat and stat.mtime.sec or nil
end

-- Primary async API (call from within async.run or coroutine context)
function FileCache:get_async(path)
  local cached = self._cache[path]

  if not cached or not self.trust_mtime then
    local entry = read_file_async(path)
    if entry then
      self._cache[path] = entry
    end
    return entry
  end

  local mtime = get_mtime_async(path)
  if mtime and mtime == cached.mtime then
    return cached
  end

  local entry = read_file_async(path)
  if entry then
    self._cache[path] = entry
  else
    self._cache[path] = nil
  end
  return entry
end

function FileCache:write_async(path, data)
  local content = data.content
  if not content then
    return false
  end

  local ok, mtime = write_file_async(path, content)
  if ok and mtime then
    self._cache[path] = {
      path = path,
      content = content,
      mtime = mtime,
      json = data.json or nil,
    }
  end
  return ok
end

-- Callback API (safe to call from non-async context)
function FileCache:get(path, callback)
  async.run(function()
    return self:get_async(path)
  end, callback)
end

function FileCache:write(path, data, callback)
  async.run(function()
    return self:write_async(path, data)
  end, callback)
end

function FileCache:invalidate(path)
  self._cache[path] = nil
end

function FileCache:clear_all()
  self._cache = {}
end

return {
  new = FileCache.new,
}
