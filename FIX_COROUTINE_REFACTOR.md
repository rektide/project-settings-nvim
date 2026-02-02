# Consumer-Driven Async Handling (API Breaks OK)

## Updated Context

**Important**: Since this has not been released yet, **API compatibility is not a concern**.

We should choose the **best technical solution** rather than workarounds.

---

## Root Cause (Recap)

```lua
function FileCache:get_async(path)
  local tx, rx = async.control.channel.oneshot()
  self:get(path, function(entry)  -- Callback spawns inner coroutine
    tx(entry)
  end)
  return rx()  -- BLOCKS - outer coroutine waiting for inner coroutine
end

function FileCache:get(path, callback)
  read_file_async(path, function(entry)  -- Calls async.run() internally
    callback(entry)
  end)
end
```

Problem: `rx()` yields OUTER coroutine, `tx()` called from INNER coroutine. Oneshot channels don't bridge across coroutines.

---

## Recommended Fix: Full Coroutine Refactor (Option 2)

Since API breaks are OK, refactor cache layer to be **fully coroutine-based**.

### Implementation

```lua
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

-- =============================================================================
-- READ OPERATIONS (Coroutines only - no callbacks)
-- =============================================================================

local function read_file_coro(path)
  local stat, stat_err = uv.fs_stat(path)
  if stat_err or not stat then
    return nil
  end

  local fd, open_err = uv.fs_open(path, "r", 438)
  if open_err or not fd then
    return nil
  end

  local content, read_err = uv.fs_read(fd, stat.size, 0)
  uv.fs_close(fd)

  if read_err then
    return nil
  end

  return {
    path = path,
    content = content,
    mtime = stat.mtime.sec,
    json = nil,
  }
end

-- Main get method - MUST be called from coroutine
function FileCache:get(path)
  local cached = self._cache[path]

  if not cached or not self.trust_mtime then
    local entry = read_file_coro(path)
    if entry then
      self._cache[path] = entry
    end
    return entry
  end

  local stat = uv.fs_stat(path)
  if not stat then
    self._cache[path] = nil
    return nil
  end

  if stat.mtime.sec == cached.mtime then
    return cached
  end

  local entry = read_file_coro(path)
  if entry then
    self._cache[path] = entry
  else
    self._cache[path] = nil
  end
  return entry
end

-- Async wrapper - wraps get() for compatibility with existing calls
-- DEPRECATED: Users should call get() directly from within async.run()
function FileCache:get_async(path)
  return self:get(path)
end

-- =============================================================================
-- WRITE OPERATIONS (Coroutines only)
-- =============================================================================

local function write_file_coro(path, content)
  local fd, open_err = uv.fs_open(path, "w", 438)
  if open_err or not fd then
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

function FileCache:write(path, data)
  local content = data.content
  if not content then
    return false
  end

  local success, mtime = write_file_coro(path, content)
  if success and mtime then
    self._cache[path] = {
      path = path,
      content = content,
      mtime = mtime,
      json = data.json or nil,
    }
  end
  return success
end

-- Async wrapper for compatibility
-- DEPRECATED: Users should call write() directly from within async.run()
function FileCache:write_async(path, data)
  return self:write(path, data)
end

-- =============================================================================
-- CACHE MANAGEMENT
-- =============================================================================

function FileCache:invalidate(path)
  self._cache[path] = nil
end

function FileCache:clear_all()
  self._cache = {}
end

-- =============================================================================
-- EXPORT
-- =============================================================================

return {
  new = FileCache.new,
}
```

### Required Changes to Callers

**JSON Executor**:

```lua
local function json_executor(ctx, file_path)
  -- OLD (doesn't work):
  local entry = ctx.file_cache:get_async(file_path)

  -- NEW (works):
  local entry = ctx.file_cache:get(file_path)
  -- OR just rely on pipeline being in async context:
  local entry = ctx.file_cache:get(file_path)

  if not entry then
    error("Failed to read JSON file: " .. file_path)
  end
  local content = entry.content

  -- ... rest of executor ...
end
```

**Directory Cache** (similar refactor):

```lua
function DirectoryCache:get(path)
  -- Remove callback-based version
  -- Use coroutine-based read directly
  local cached = self._cache[path]

  if not cached then
    local entry = read_dir_coro(path)
    if entry then
      self._cache[path] = entry
    end
    return entry
  end

  -- ... mtime check logic ...
end
```

---

## DirectoryCache Full Refactor

```lua
local async = require("plenary.async")
local uv = async.uv

local DirectoryCache = {}
DirectoryCache.__index = DirectoryCache

function DirectoryCache.new(opts)
  opts = opts or {}
  return setmetatable({
    trust_mtime = opts.trust_mtime ~= false,
    _cache = {},
  }, DirectoryCache)
end

local function read_dir_coro(path)
  local stat, stat_err = uv.fs_stat(path)
  if stat_err or not stat then
    return nil
  end

  local fd, open_err = uv.fs_opendir(path)
  if open_err or not fd then
    return nil
  end

  local entries = {}
  local entry, err = uv.fs_readdir(fd)
  while entry do
    table.insert(entries, entry)
    entry, err = uv.fs_readdir(fd)
  end
  uv.fs_closedir(fd)

  if err then
    return nil
  end

  return {
    path = path,
    entries = entries,
    mtime = stat.mtime.sec,
  }
end

function DirectoryCache:get(path)
  local cached = self._cache[path]

  if not cached then
    local entry = read_dir_coro(path)
    if entry then
      self._cache[path] = entry
    end
    return entry
  end

  local stat = uv.fs_stat(path)
  if not stat then
    self._cache[path] = nil
    return nil
  end

  if stat.mtime.sec == cached.mtime then
    return cached
  end

  local entry = read_dir_coro(path)
  if entry then
    self._cache[path] = entry
  else
    self._cache[path] = nil
  end
  return entry
end

-- Async wrapper (deprecated)
function DirectoryCache:get_async(path)
  return self:get(path)
end

function DirectoryCache:invalidate(path)
  self._cache[path] = nil
end

function DirectoryCache:clear_all()
  self._cache = {}
end

return {
  new = DirectoryCache.new,
}
```

---

## Pipeline Changes

**Execute Stage**:

```lua
-- Remove async.run() wrappers around executors
-- Let plenary's async.run() in pipeline.run() handle it

function execute.stage(ctx, rx, tx)
  while true do
    local file_path = rx()

    if file_path == pipeline.DONE then
      break
    end

    local ext = vim.fn.fnamemodify(file_path, ":e")
    local executor = ctx.executors[ext]

    if executor then
      local is_async = ctx.executors[ext] and ctx.executors[ext].async

      if is_async then
        -- Already in coroutine context from pipeline.run()
        executor(ctx, file_path)
      else
        -- Sync executor, run directly
        executor(ctx, file_path)
      end
    end

    ctx._files_loaded = ctx._files_loaded or {}
    ctx._files_loaded[file_path] = true
  end
end
```

---

## Advantages of Full Coroutine Refactor

✅ **Best Practices**:
- No callback pattern in async code
- All I/O is coroutine-native
- Works perfectly with plenary async

✅ **Clean Architecture**:
- No callback hell
- No oneshot channel complexity
- Clear error handling

✅ **No Deadlock Issues**:
- Everything runs in same coroutine context
- No cross-coroutine bridging
- Simple flow

✅ **Performance**:
- Most efficient - minimal overhead
- No unnecessary sync/blocking

✅ **API Clarity**:
- `get(path)` - returns entry (must be in coroutine)
- `write(path, data)` - returns success (must be in coroutine)
- Clear intent

---

## Migration Guide

For Users (minimal impact):

Most users don't use cache directly. They use:

```lua
npc.setup({
  on_load = function(ctx)
    -- ctx.json already loaded, merge done
    -- No cache access needed
  end,
})
```

For Internal Code (file_cache/dir_cache):

**Before**:
```lua
-- Callback pattern (broken)
ctx.file_cache:get_async(path, function(entry)
  if entry then
    -- use entry
  end
end)
```

**After**:
```lua
-- Coroutine pattern (works)
local entry = ctx.file_cache:get(path)
if entry then
  -- use entry
end
```

---

## Implementation Checklist

- [ ] Refactor `FileCache` to remove all callbacks
- [ ] Refactor `DirectoryCache` to remove all callbacks
- [ ] Remove `async.run()` from all internal helpers
- [ ] Keep `get_async()` and `get_async()` as deprecated wrappers
- [ ] Update JSON executor to call `get()` directly
- [ ] Update find_files stage to use `get()` directly
- [ ] Update tests to work with new API
- [ ] Document new API in README
- [ ] Update examples in README to show coroutine pattern
- [ ] Add deprecation notices to old methods

---

## Comparison: Refactor vs Previous Options

| Aspect | Coroutine Refactor | Graceful Fallback | Consumer-Awaits |
|--------|-------------------|-------------------|------------------|
| **Fixes root cause?** | ✅ Yes | ⚠️ Masks it | ⚠️ Works around |
| **API changes?** | ✅ Breaking (OK - pre-release) | ✅ None | ✅ None |
| **Performance?** | ✅ Optimal | ⚠️ Sync fallback | ⚠️ Awaits pipeline |
| **Code complexity?** | ⚠️ Medium refactoring | ⚠️ Adds fallbacks | ✅ Low (docs only) |
| **Future-proof?** | ✅ Best practices | ❌ Hides bug | ⚠️ Temporary |
| **Maintenance burden?** | ✅ Lower long-term | ⚠️ Higher (workarounds) | ❌ Highest (user burden) |

---

## Recommendation

**Implement Full Coroutine Refactor** because:

1. ✅ **API breaks are acceptable** - Pre-release, no compatibility concerns
2. ✅ **Best technical solution** - Proper async patterns, no deadlocks
3. ✅ **Clean architecture** - No callback complexity
4. ✅ **Solves root cause** - Doesn't just mask the bug
5. ✅ **Better long-term** - Follows Lua async best practices

**Secondary**: Document that executors run in coroutine context, so they can:
- Use `uv.fs_*()` directly (no need for wrappers)
- Use `get()` / `write()` methods on cache objects
- Not worry about async wrapping (pipeline handles it)
