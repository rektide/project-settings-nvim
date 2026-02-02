local async = require("plenary.async")
local channel = async.control.channel
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

-- ============================================================================
-- ASYNC FILE OPERATIONS (Must be called from coroutine context)
-- ============================================================================

local function read_file(path)
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

local function write_file(path, content)
  -- plenary.async.uv returns (err, fd) NOT (fd, err)!
  local err, fd = uv.fs_open(path, "w", 438)

  if err then
    return false, "Failed to open file: " .. tostring(err)
  end

  -- uv.fs_write also returns (err, bytes_written)
  local write_err, write_result = uv.fs_write(fd, content, -1)
  uv.fs_close(fd)

  if write_err then
    return false, "Write error: " .. tostring(write_err)
  end

  local stat = uv.fs_stat(path)
  return true, stat and stat.mtime.sec or nil
end

-- ============================================================================
-- ASYNC READ CACHE (Reads from coroutine, safe async)
-- ============================================================================

function FileCache:get_async(path)
  local cached = self._cache[path]

  if not cached or not self.trust_mtime then
    local entry = read_file(path)
    if entry then
      self._cache[path] = entry
    end
    return entry
  end

  local mtime = uv.fs_stat(path)
  if mtime and mtime.mtime.sec == cached.mtime then
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

-- ============================================================================
-- ASYNC WRITE CHANNEL (Bridges non-async to async for file writes)
-- ============================================================================

-- Create MPSC channel for write requests
local sender, receiver = channel.mpsc()

-- Consumer coroutine - runs in async context, safe to use uv.fs_write
-- Each write is processed individually; the channel handles the async boundary
async.void(function()
  while true do
    -- Wait for a write request (blocks in async context)
    local write_req = receiver.recv()

    -- Write the file (safe because we're in async coroutine)
    write_file(write_req.path, write_req.data)
   end
end)()

-- Queue function - NON-ASYNC, safe to call from __newindex
local function queue_write(path, data)
  sender.send({ path = path, data = data })
end

-- ============================================================================
-- WRITE ASYNC (Queues write, returns immediately)
-- ============================================================================

function FileCache:write_async(path, data)
  -- Queue the write (non-async, safe from any context)
  local content
  if type(data) == "table" then
    content = data.content
  else
    content = data
  end

  if not content then
    return false
  end

  queue_write(path, content)
  return true
end

return {
  new = FileCache.new,
  -- Queue function exposed for direct access if needed
  _queue_write = queue_write,
}
