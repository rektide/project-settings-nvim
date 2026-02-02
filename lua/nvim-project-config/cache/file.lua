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
  vim.notify("write_file: " .. path .. " (len: " .. #content .. ")", vim.log.levels.INFO)

  local fd = uv.fs_open(path, "w", 438)
  if not fd then
    return false, "Failed to open file"
  end

  local result, err = uv.fs_write(fd, content, 0)
  vim.notify("uv.fs_write: result=" .. tostring(result) .. " err=" .. tostring(err), vim.log.levels.INFO)
  uv.fs_close(fd)

  if err then
    return false, "Write error: " .. tostring(err)
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
  vim.notify("Async write consumer started", vim.log.levels.INFO)
  while true do
    -- Wait for a write request (blocks in async context)
    vim.notify("Waiting for write request...", vim.log.levels.INFO)
    local write_req = receiver.recv()
    vim.notify("Got write request: " .. write_req.path, vim.log.levels.INFO)

    -- Write the file (safe because we're in async coroutine)
    local ok, err = write_file(write_req.path, write_req.data)
    if not ok then
      vim.notify("Failed to write file: " .. write_req.path .. " - " .. tostring(err), vim.log.levels.ERROR)
    end
  end
end)()

-- Queue function - NON-ASYNC, safe to call from __newindex
local function queue_write(path, data)
  vim.notify("queue_write: " .. path .. " (len: " .. #data .. ")", vim.log.levels.INFO)
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
