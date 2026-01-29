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

local function read_file_async(path, callback)
  async.run(function()
    local stat, stat_err = uv.fs_stat(path)
    if stat_err or not stat then
      callback(nil)
      return
    end

    local fd, open_err = uv.fs_open(path, "r", 438)
    if open_err or not fd then
      callback(nil)
      return
    end

    local content, read_err = uv.fs_read(fd, stat.size, 0)
    uv.fs_close(fd)

    if read_err then
      callback(nil)
      return
    end

    callback({
      path = path,
      content = content,
      mtime = stat.mtime.sec,
      json = nil,
    })
  end)
end

local function write_file_async(path, content, callback)
  async.run(function()
    local fd, open_err = uv.fs_open(path, "w", 438)
    if open_err or not fd then
      callback(false)
      return
    end

    local _, write_err = uv.fs_write(fd, content, 0)
    uv.fs_close(fd)

    if write_err then
      callback(false)
      return
    end

    local stat = uv.fs_stat(path)
    callback(true, stat and stat.mtime.sec or nil)
  end)
end

local function get_mtime_async(path, callback)
  async.run(function()
    local stat = uv.fs_stat(path)
    callback(stat and stat.mtime.sec or nil)
  end)
end

function FileCache:get(path, callback)
  local cached = self._cache[path]

  if not cached or not self.trust_mtime then
    read_file_async(path, function(entry)
      if entry then
        self._cache[path] = entry
      end
      callback(entry)
    end)
    return
  end

  get_mtime_async(path, function(mtime)
    if mtime and mtime == cached.mtime then
      callback(cached)
    else
      read_file_async(path, function(entry)
        if entry then
          self._cache[path] = entry
        else
          self._cache[path] = nil
        end
        callback(entry)
      end)
    end
  end)
end

function FileCache:write(path, data, callback)
  local content = data.content
  if not content then
    callback(false)
    return
  end

  write_file_async(path, content, function(success, mtime)
    if success and mtime then
      self._cache[path] = {
        path = path,
        content = content,
        mtime = mtime,
        json = data.json or nil,
      }
    end
    callback(success)
  end)
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
