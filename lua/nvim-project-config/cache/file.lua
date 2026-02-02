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
  local fd = uv.fs_open(path, "w", 438)
  if not fd then
    return false, "Failed to open file"
  end

  local _, write_err = uv.fs_write(fd, content, 0)
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

-- Debounce timer
local write_debounce_ms = 100

-- Consumer coroutine - runs in async context, safe to use uv.fs_write
async.void(function()
  while true do
    -- Wait for a write request
    local write_req = receiver.recv()

    -- Debounce: wait for more changes
    async.util.sleep(write_debounce_ms)

    -- Collect all pending writes
    local pending = { write_req }
    local has_more = true
    while has_more do
      local req = receiver.recv_nowait()
      if req then
        table.insert(pending, req)
      else
        has_more = false
      end
    end

    -- Process all pending writes
    for _, req in ipairs(pending) do
      local ok, err = write_file(req.path, req.data)
      if not ok then
        vim.notify("Failed to write file: " .. req.path .. " - " .. tostring(err), vim.log.levels.ERROR)
      end
    end
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
