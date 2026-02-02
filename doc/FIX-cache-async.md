# Cache Async Deadlock: Comprehensive Analysis and Fix Strategy

## Table of Contents

1. [Problem Statement](#problem-statement)
2. [Root Cause](#root-cause)
3. [Impact Analysis](#impact-analysis)
4. [Solution Options](#solution-options)
   - [Option 1: Sync I/O Fallback](#option-1-sync-io-fallback)
   - [Option 2: Full Coroutine Refactor](#option-2-full-coroutine-refactor)
   - [Option 3: Graceful Fallback](#option-3-graceful-fallback)
   - [Option 4: Document as Internal Only](#option-4-document-as-internal-only)
   - [Option 5: Background Worker](#option-5-background-worker)
5. [Comparison Matrix](#comparison-matrix)
6. [Recommendation](#recommendation)
7. [Implementation Guide](#implementation-guide)
8. [Migration Notes](#migration-notes)
9. [**Resolution: Coroutine-First Refactor (Implemented)**](#resolution-coroutine-first-refactor-implemented)

---

## Problem Statement

### Symptom

JSON configuration files fail to load when using the async cache layer:

```
Error: Failed to read JSON file: /path/to/config.json
```

Result: `ctx.json` remains empty, no values are merged.

### When It Occurs

- During initial project configuration load
- When pipeline executes stages asynchronously
- Specifically when `ctx.file_cache:get_async()` is called

### What Works

- JSON executor works correctly with sync I/O (cache disabled)
- Reactive metatable works (all 32 tests passing)
- Pipeline execution works (86 tests total passing)
- The issue is **isolated to the cache layer's async implementation**

---

## Root Cause

### The Deadlock

```lua
function FileCache:get_async(path)
  -- 1. Create oneshot channel
  local tx, rx = async.control.channel.oneshot()

  -- 2. Call callback-based get()
  self:get(path, function(entry)
    -- This callback spawns INNER coroutines via async.run()
    tx(entry)  -- 3. Transmitter called from INNER coroutine
  end)

  -- 4. Yield OUTER coroutine waiting for rx()
  return rx()  -- DEADLOCK: outer coroutine never receives from inner tx
end

function FileCache:get(path, callback)
  -- Callback spawns inner coroutines
  read_file_async(path, function(entry)
    callback(entry)  -- Calls back to get()'s callback
  end)
end

function read_file_async(path, callback)
  async.run(function()  -- INNER coroutine
    local entry = read_sync(path)
    callback(entry)
  end)
end
```

### Why Oneshot Fails

Plenary's `async.control.channel.oneshot()` creates a one-time communication channel:

- `tx(value)` - sends a value
- `rx()` - blocks until value is received, then returns it

**Critical constraint**: The transmitter and receiver **must be in the same coroutine context** for proper operation.

In our case:
1. `get_async()` runs in **outer coroutine A** (from pipeline)
2. Creates oneshot with `tx_A`, `rx_A`
3. Calls `rx_A` - yields coroutine A waiting
4. `get()` spawns **inner coroutine B** via `async.run()`
5. Coroutine B runs, calls callback
6. Callback calls `tx_A(entry)` from coroutine B
7. **Problem**: `tx_A` was created in coroutine A, but called from coroutine B
8. Coroutine A's `rx_A` is blocked waiting for transmission
9. Coroutine A never resumes because `tx_A`→`rx_A` link doesn't bridge across coroutines

**Result**: Deadlock - coroutine A yields forever waiting.

---

## Impact Analysis

### Severity: High

- Prevents JSON config files from loading entirely
- Data loss: user's JSON configuration is silently ignored
- No user-facing workaround except disabling cache entirely

### Affected Components

| Component | Affected | Why |
|----------|-----------|-------|
| `FileCache:get_async()` | ✅ Yes | Calls callback that spawns coroutines |
| `FileCache:write_async()` | ✅ Yes | Same pattern |
| `DirectoryCache:get_async()` | ✅ Yes | Same pattern |
| JSON executor | ✅ Yes (when using cache) | Calls `get_async()` |
| `find_files` stage | ✅ Yes | Calls `get_async()` |
| User code using cache | ⚠️  Potentially | If called during pipeline |

### Not Affected

- ✅ Reactive metatable (works correctly)
- ✅ Pipeline orchestration (works correctly)
- ✅ Sync I/O fallback (works correctly)
- ✅ `on_load` callback (fires correctly)
- ✅ `load_await()` promise (works correctly)

---

## Solution Options

---

## Option 1: Sync I/O Fallback

### Concept

Remove `async.run()` from internal helpers. Let callers decide async vs sync.

### Implementation

```lua
function FileCache:get_async(path)
  -- Just do sync I/O directly
  local cached = self._cache[path]

  if not cached or not self.trust_mtime then
    local entry = self:read_sync(path)
    if entry then
      self._cache[path] = entry
    end
    return entry
  end

  local stat = uv.fs_stat(path)
  if stat and stat.mtime.sec == cached.mtime then
    return cached
  end

  local entry = self:read_sync(path)
  if entry then
    self._cache[path] = entry
  else
    self._cache[path] = nil
  end
  return entry
end

local function read_sync(path)
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
```

### Consumer Impact

```lua
-- ZERO changes required - same API
local async = require("plenary.async")
local npc = require("nvim-project-config")

npc.setup()

-- User can still wrap in async.run() if they want non-blocking
async.run(function()
  local entry = ctx.file_cache:get_async(path)
  -- Works! get_async() just does sync I/O
  -- async.run() provides non-blocking context
end)
```

### Pros

| Aspect | Rating |
|--------|---------|
| **Simplicity** | ✅ Very simple - minimal changes |
| **Consumer changes** | ✅ None |
| **API stability** | ✅ No breaking changes |
| **Implementation effort** | ✅ Low - just remove async.run() |
| **Risk** | ⚠️ Low - well-understood pattern |

### Cons

| Aspect | Rating |
|--------|---------|
| **Performance** | ⚠️ Medium - blocks during I/O |
| **Async semantics** | ❌ Poor - `get_async()` name is misleading |
| **Scalability** | ❌ Poor - doesn't leverage async I/O |

---

## Option 2: Full Coroutine Refactor

### Concept

Remove all callback patterns. Make all cache methods **coroutine-native**.

Since API compatibility is **not a concern** (pre-release), we can break the API.

### Implementation

#### FileCache

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

-- Async wrapper - deprecated for compatibility
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

-- Async wrapper - deprecated
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

#### DirectoryCache (similar refactor)

```lua
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
  -- Remove callback-based version entirely
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
```

### Consumer Impact

```lua
-- Minimal changes required - just need to be in coroutine context
local async = require("plenary.async")
local npc = require("nvim-project-config")

npc.setup()

-- Option 1: Use on_load callback (simplest)
npc.setup({
  on_load = function(ctx)
    -- ctx.json already loaded and merged
    local formatter = ctx.json.formatter
    -- Do work here
  end,
})

-- Option 2: Use load_await()
async.run(function()
  local ctx = npc.load_await()
  -- Values ready
end)

-- Option 3: Direct cache access (in coroutine)
async.run(function()
  -- Pipeline runs in coroutine context
  -- Executors can call ctx.file_cache:get(path) directly
  npc.load()
end)
```

### Pros

| Aspect | Rating |
|--------|---------|
| **Best practices** | ✅ Excellent - coroutine-native async |
| **Performance** | ✅ Optimal - no blocking |
| **Clean architecture** | ✅ Excellent - no callback hell |
| **No deadlocks** | ✅ Guaranteed - same coroutine context |
| **Future-proof** | ✅ Follows Lua async best practices |

### Cons

| Aspect | Rating |
|--------|---------|
| **Consumer changes** | ⚠️ Medium - need to be in coroutine |
| **API breaking** | ⚠️ Yes (but acceptable pre-release) |
| **Implementation effort** | ⚠️ Medium - refactor cache layer |
| **Call site updates** | ⚠️ Medium - update all cache usage |

---

## Option 3: Graceful Fallback

### Concept

Wrap cache calls in `pcall()`. On failure, fall back to sync I/O transparently.

### Implementation

```lua
local function json_executor(ctx, file_path)
  local content

  if ctx.file_cache then
    local entry = nil
    local cache_ok, cache_err = pcall(function()
      entry = ctx.file_cache:get_async(file_path)
    end)

    if not cache_ok or not entry then
      -- Cache failed (likely deadlock), use sync I/O
      vim.schedule(function()
        vim.notify(
          "Cache read failed, using sync I/O: " .. file_path,
          vim.log.levels.WARN
        )
      end)

      local fd, err = io.open(file_path, "r")
      if not fd then
        error("Failed to read JSON file: " .. file_path .. " - " .. tostring(err))
      end
      content = fd:read("*a")
      fd:close()
    else
      content = entry.content
    end
  else
    local fd, err = io.open(file_path, "r")
    if not fd then
      error("Failed to read JSON file: " .. file_path .. " - " .. tostring(err))
    end
    content = fd:read("*a")
    fd:close()
  end

  -- ... rest of JSON parsing and merging ...
end
```

### Consumer Impact

```lua
-- ZERO changes required
npc.setup({
  on_load = function(ctx)
    local formatter = ctx.json.formatter
    -- Works transparently
  end,
})
```

### Pros

| Aspect | Rating |
|--------|---------|
| **Consumer changes** | ✅ None - transparent fallback |
| **API stability** | ✅ No breaking changes |
| **Robustness** | ✅ High - always works even if cache fails |
| **Implementation effort** | ✅ Low - just add pcall wrapper |

### Cons

| Aspect | Rating |
|--------|---------|
| **Root cause** | ❌ Doesn't fix - masks the issue |
| **Technical debt** | ⚠️ High - workaround becomes permanent |
| **Maintenance burden** | ⚠️ High - always have to support broken cache |
| **Performance** | ⚠️ Medium - sync fallback on every cache miss |

---

## Option 4: Document as Internal Only

### Concept

Mark cache objects as **pipeline-internal only**. Document that users should not access them directly.

### Implementation

Add to README:

```markdown
## Context Reference

### ctx.file_cache and ctx.dir_cache

**⚠️ Internal Use Only**

These cache objects are used internally by pipeline stages during
configuration loading. They are **not intended for direct use** by
user code.

**Why**: The cache layer uses an async coroutine pattern that deadlocks when
called from within the pipeline's async context.

**Use These Patterns Instead**:

1. **Access loaded values via ctx.json**:
   ```lua
   npc.setup({
     on_load = function(ctx)
       local formatter = ctx.json.formatter
       -- Values already loaded, merged, and cached
     end,
   })
   ```

2. **Use load_await() to wait for completion**:
   ```lua
   local async = require("plenary.async")
   async.run(function()
     local ctx = npc.load_await()
     -- Values ready
   end)
   ```

3. **File I/O for external files**:
   Use plenary async directly or standard vim.uv/fs functions.

**Accessing cache directly may cause deadlocks**. The `on_load` callback
or `load_await()` promise ensures all async work completes before you access
configuration values.
```

### Consumer Impact

```lua
-- Required changes - must use documented patterns

-- OLD (may deadlock):
local entry = ctx.file_cache:get_async(file_path)

-- NEW (works):
npc.setup({
  on_load = function(ctx)
    local formatter = ctx.json.formatter
  end,
})
```

### Pros

| Aspect | Rating |
|--------|---------|
| **API clarity** | ✅ Clear - internal vs user-facing |
| **Implementation effort** | ✅ None - just documentation |
| **Code changes** | ✅ None |
| **Educates users** | ✅ Guides to correct patterns |

### Cons

| Aspect | Rating |
|--------|---------|
| **Restrictive** | ❌ Blocks valid use cases unnecessarily |
| **Workaround** | ⚠️ Doesn't fix actual problem |
| **User burden** | ⚠️ High - must learn new patterns |
| **Limitation** | ⚠️ Prevents legitimate cache usage |

---

## Option 5: Background Worker (Recommended)

### Concept

Spawn a single **background coroutine** that handles all cache operations. Use mpsc channel for request/response communication.

### Key Insight

The deadlock occurs because:
1. `get_async()` creates oneshot in coroutine A
2. `get()` spawns coroutine B
3. Coroutine A yields waiting, coroutine B calls `tx()`

**Solution**: Create a **single worker coroutine** that:
- Runs forever
- Receives work requests via mpsc channel
- Performs I/O
- Sends responses via oneshot channels

**Why this works**: All cache operations now happen in the same coroutine (the worker), eliminating cross-coroutine bridging.

### Implementation

```lua
local async = require("plenary.async")
local uv = async.uv

local FileCache = {}
FileCache.__index = FileCache

function FileCache.new(opts)
  opts = opts or {}

  local self = setmetatable({
    trust_mtime = opts.trust_mtime ~= false,
    _cache = {},
    _work_tx = nil,
  }, FileCache)

  -- Start background worker coroutine
  self:_start_worker()

  return self
end

function FileCache:_start_worker()
  local work_tx, work_rx = async.control.channel.mpsc()

  self._work_tx = work_tx
  self._work_rx = work_rx

  -- Background worker handles all operations
  async.run(function()
    while true do
      local work_item = work_rx()

      if not work_item then
        break  -- Worker terminated
      end

      local op = work_item.op
      local args = work_item.args
      local tx = args.tx

      if op == "read" then
        self:_do_read(tx, args.path)
      elseif op == "write" then
        self:_do_write(tx, args.path, args.content, args.json)
      elseif op == "invalidate" then
        self:_do_invalidate(tx, args.path)
      elseif op == "clear_all" then
        self:_do_clear_all(tx)
      end
    end
  end)
end

-- Work operations (all in worker coroutine)
function FileCache:_do_read(tx, path)
  local stat, stat_err = uv.fs_stat(path)
  if stat_err or not stat then
    tx(nil)
    return
  end

  local fd, open_err = uv.fs_open(path, "r", 438)
  if open_err or not fd then
    tx(nil)
    return
  end

  local content, read_err = uv.fs_read(fd, stat.size, 0)
  uv.fs_close(fd)

  if read_err then
    tx(nil)
    return
  end

  local entry = {
    path = path,
    content = content,
    mtime = stat.mtime.sec,
    json = nil,
  }

  -- Update cache
  self._cache[path] = entry
  tx(entry)
end

function FileCache:_do_write(tx, path, content, json)
  local fd, open_err = uv.fs_open(path, "w", 438)
  if open_err or not fd then
    tx(false)
    return
  end

  local _, write_err = uv.fs_write(fd, content, 0)
  uv.fs_close(fd)

  if write_err then
    tx(false)
    return
  end

  local stat = uv.fs_stat(path)
  if stat and stat.mtime.sec then
    self._cache[path] = {
      path = path,
      content = content,
      mtime = stat.mtime.sec,
      json = json,
    }
  end

  tx(true)
end

function FileCache:_do_invalidate(tx, path)
  self._cache[path] = nil
  tx(true)
end

function FileCache:_do_clear_all(tx)
  self._cache = {}
  tx(true)
end

-- Public API methods
function FileCache:get_async(path)
  -- Create oneshot for this specific request
  local tx, rx = async.control.channel.oneshot()

  -- Send work to background worker
  self._work_tx.send({
    op = "read",
    path = path,
    tx = tx,
  })

  -- Yield and wait for result
  -- SAFE: tx and rx are in same chain now
  return rx()
end

function FileCache:write_async(path, data)
  local content = data.content
  if not content then
    local tx, rx = async.control.channel.oneshot()
    self._work_tx.send({
      op = "write",
      path = path,
      content = content,
      json = data.json or nil,
      tx = tx,
      false,  -- immediate failure
    })
    return rx()
  end

  local tx, rx = async.control.channel.oneshot()

  self._work_tx.send({
    op = "write",
    path = path,
    content = content,
    json = data.json or nil,
    tx = tx,
  })

  return rx()
end

function FileCache:invalidate(path)
  -- Fire and forget - no result needed
  self._work_tx.send({
    op = "invalidate",
    path = path,
  })
end

function FileCache:clear_all()
  -- Fire and forget
  self._work_tx.send({
    op = "clear_all",
  })
end
```

### Architecture Diagram

```
Caller (Coroutine A)               Worker (Coroutine B)
        |                                 |
        |  get_async(path)                |
        |------------> send work -------->|
        |                                 |
        |                                 | 1. Receive work
        |                                 | 2. Do I/O
        |  <------- oneshot tx --------|
        |  oneshot rx                   |
        |<--------- receive result -------|
        |                                 | 3. Send entry
        V                                 V
```

**Key**: All cache operations happen in Coroutine B. Oneshot channels connect A and B.

### Consumer Impact

```lua
-- ZERO changes required - API exactly the same
npc.setup({
  on_load = function(ctx)
    -- ctx.json already loaded and merged
    local formatter = ctx.json.formatter
  end,
})

-- Internal code also works unchanged
function json_executor(ctx, file_path)
  local entry = ctx.file_cache:get_async(file_path)  -- Just works!
  local content = entry.content
  -- ...
end
```

### Pros

| Aspect | Rating |
|--------|---------|
| **Consumer changes** | ✅ **None** - most important factor |
| **API stability** | ✅ **None** - no breaking changes |
| **Fixes root cause** | ✅ **Yes** - proper async pattern |
| **Works everywhere** | ✅ **Yes** - not coroutine-context dependent |
| **Clean architecture** | ✅ **Yes** - clear worker pattern |
| **No deadlocks** | ✅ **Guaranteed** - single coroutine context |
| **Performance** | ✅ **Optimal** - proper async I/O |

### Cons

| Aspect | Rating |
|--------|---------|
| **Implementation complexity** | ⚠️ Medium - need worker pattern |
| **Code size** | ⚠️ Larger - adds worker infrastructure |
| **Async complexity** | ⚠️ Medium - mpsc channels |

---

## Comparison Matrix

| Option | Consumer Changes | API Breaking | Performance | Simplicity | Fixes Root Cause | Implementation Effort |
|--------|------------------|--------------|-------------|--------------|-------------------|---------------------|
| **1. Sync I/O** | ✅ None | ⚠️ Blocks | ✅ Simple | ⚠️ No (bypass) | ✅ Low |
| **2. Coroutine Refactor** | ⚠️ Medium | ⚠️ Yes* | ⚠️ Medium | ✅ Yes | ⚠️ Medium |
| **3. Graceful Fallback** | ✅ None | ✅ No | ⚠️ Medium | ❌ No (masks) | ✅ Low |
| **4. Document Internal** | ⚠️ Must change patterns | ✅ No | ✅ No | ❌ No (hides) | ✅ None |
| **5. Background Worker** | ✅ **None** | ✅ **Yes** | ⚠️ Medium | ✅ **Yes** | ⚠️ Medium |

\*API breaking is acceptable (pre-release)

---

## Recommendation

### Primary: Background Worker (Option 5)

**Because**:

1. ✅ **Zero consumer impact** - Most important factor
   - Users already use correct patterns (`on_load`, `load_await()`)
   - Internal executors call `get_async()` normally
   - No user code changes required

2. ✅ **Fixes root cause** - Not a workaround
   - Proper async pattern with single worker coroutine
   - No cross-coroutine bridging issues
   - Clean architecture

3. ✅ **No API breaks** - Maintains compatibility
   - Existing `_async()` methods work as documented
   - Internal code unchanged except cache layer

4. ✅ **Works everywhere** - Context-independent
   - Doesn't depend on being in specific coroutine
   - Works from user code after pipeline completes
   - Works during pipeline execution

### Secondary: Document Correct Patterns (Option 4)

While implementing Option 5, also add documentation:

1. Clarify that `ctx.file_cache` and `ctx.dir_cache` are **pipeline-internal**
2. Emphasize `on_load` callback as primary way to access loaded config
3. Document `load_await()` for async/await pattern
4. Add troubleshooting section for cache issues

This provides best-of-both-worlds:
- Option 5 fixes the technical problem
- Option 4 educates users and prevents misuse

---

## Implementation Guide

### Phase 1: Implement Background Worker

1. **Update FileCache**
   - Add `_work_tx` and `_work_rx` fields
   - Implement `_start_worker()` method
   - Implement work methods: `_do_read()`, `_do_write()`, `_do_invalidate()`, `_do_clear_all()`
   - Update `get_async()` to use oneshot pattern with worker
   - Update `write_async()` to use oneshot pattern with worker
   - Update `invalidate()` and `clear_all()` to send work messages

2. **Update DirectoryCache**
   - Apply same pattern as FileCache
   - Replace `_read_directory_coro()` with worker-based read
   - Use mpsc for all operations

3. **Testing**
   - Test cache reads work in all contexts
   - Test cache writes work in all contexts
   - Test invalidation works
   - Test no deadlocks occur

### Phase 2: Update Documentation

1. **README.md**
   - Add "Cache Internal Use Only" section
   - Document `on_load` callback pattern
   - Document `load_await()` pattern
   - Add troubleshooting section

2. **API Documentation**
   - Add deprecation notices to callback-based methods (if keeping them)
   - Document worker implementation (for transparency)

### Phase 3: Tests

1. **Add integration test**
   ```lua
   it("loads JSON files from astrovim-git/projects", function()
     -- Verify actual JSON files load correctly
   end)
   ```

2. **Update existing tests**
   - Ensure tests pass with new cache implementation
   - Add tests for worker behavior
   - Test edge cases (cache hit, miss, invalidate)

### Phase 4: Migration (If needed)

1. **No user migration needed** - API unchanged
2. **Internal call sites** - already use correct patterns:
   - JSON executor calls `get_async()` - unchanged
   - find_files stage calls `get_async()` - unchanged
   - All work in pipeline context (async.run())

---

## Migration Notes

### For Users: No Changes Required

```lua
-- Your existing code continues to work:
npc.setup({
  on_load = function(ctx)
    -- This still works perfectly
  end,
})

async.run(function()
  local ctx = npc.load_await()
  -- This still works perfectly
end)
```

### For Internal Code: Minimal Changes Required

Only cache layer needs changes. Call sites unchanged:

```lua
// JSON executor - NO CHANGES NEEDED
function json_executor(ctx, file_path)
  // This works the same after fix:
  local entry = ctx.file_cache:get_async(file_path)
  // ...
end

// find_files stage - NO CHANGES NEEDED
// Uses ctx.file_cache:get_async() - works same after fix
```

### Backward Compatibility

- ✅ **Full backward compatibility** - Public API unchanged
- ✅ `get_async()` methods continue to work
- ✅ `write_async()` methods continue to work
- ✅ All existing tests pass

---

## Testing Checklist

### Unit Tests

- [ ] FileCache read operations (new cache hit)
- [ ] FileCache read operations (cache hit, mtime valid)
- [ ] FileCache read operations (cache hit, mtime invalid)
- [ ] FileCache write operations
- [ ] FileCache invalidate
- [ ] FileCache clear_all
- [ ] DirectoryCache operations (same set)
- [ ] Background worker coroutine lifecycle
- [ ] Multiple concurrent requests

### Integration Tests

- [ ] JSON files load from real config directory
- [ ] Values merge into ctx.json correctly
- [ ] Reactive writes to ctx.json work
- [ ] No deadlocks in any scenario
- [ ] Cache invalidation works correctly

### Regression Tests

- [ ] All existing 86 tests still pass
- [ ] on_load callback fires correctly
- [ ] load_await() promise resolves correctly
- [ ] Pipeline completes successfully

---

## Summary

### The Problem

Cache layer's `get_async()` uses oneshot channels across coroutine boundaries, causing deadlocks when called during pipeline execution.

### The Solution

Implement **Option 5 (Background Worker)**:

| Dimension | Outcome |
|-----------|----------|
| Consumer impact | ✅ Zero changes |
| API stability | ✅ Fully backward compatible |
| Root cause | ✅ Fixed properly |
| Performance | ✅ Optimal async I/O |
| Architecture | ✅ Clean worker pattern |
| Deadlocks | ✅ Eliminated |

### Why This Choice

1. **Most important factor addressed**: Consumer experience unchanged
2. **Technical correctness**: Proper async pattern, not workaround
3. **Clean architecture**: Single worker coroutine, clear separation
4. **No API breaks**: Pre-release means we can refactor cleanly
5. **Future-proof**: Follows Lua async best practices

### Next Steps

1. Implement background worker pattern in FileCache
2. Implement background worker pattern in DirectoryCache
3. Update documentation with cache internal-use warnings
4. Add integration test for JSON loading
5. Verify all existing tests pass
6. Run integration test on real config directory

---

## References

Related analysis documents:

- `CONSUMER_DRIVEN_FIX.md` - Consumer-focused options and workarounds
- `FIX_COROUTINE_REFACTOR.md` - Full coroutine refactor details
- `CONSUMER_EXPERIENCE_ANALYSIS.md` - Consumer experience comparison
- `JSON_LOADING_TEST.md` - Test results showing the issue

---

## Resolution: Coroutine-First Refactor (Implemented)

### Revised Diagnosis

The original analysis focused on oneshot channels not bridging across coroutines. While directionally correct, the **actual root cause** was simpler:

**`async.uv.fs_*` functions are plenary-wrapped async functions that yield inside coroutines—but they were being called from within callback chains that weren't in a coroutine context.**

The old `read_file_async()` helper had this signature:

```lua
local function read_file_async(path, callback)
  local stat = uv.fs_stat(path)  -- ← This YIELDS, needs coroutine context!
  ...
  callback(entry)
end
```

Despite the callback-style signature, it used `async.uv.fs_stat()` which **yields**. When `get()` called this from a plain callback (not inside `async.run()`), the yield failed.

### The Fix

**Option 2 (Coroutine-First)** was implemented—simpler than Option 5 (Background Worker) and equally effective.

The pattern:

1. Make `get_async()`/`write_async()` **pure coroutine functions** that use `async.uv.*` directly
2. Make callback-based `get()`/`write()` thin wrappers that call `async.run()` to create coroutine context

#### FileCache (after fix)

```lua
-- Pure coroutine helpers (must be called from within async context)
local function read_file_coro(path)
  local stat = uv.fs_stat(path)
  if not stat then return nil end

  local fd = uv.fs_open(path, "r", 438)
  if not fd then return nil end

  local content = uv.fs_read(fd, stat.size, 0)
  uv.fs_close(fd)

  if not content then return nil end

  return {
    path = path,
    content = content,
    mtime = stat.mtime.sec,
    json = nil,
  }
end

-- Primary async API (call from within async.run or coroutine context)
function FileCache:get_async(path)
  local cached = self._cache[path]

  if not cached or not self.trust_mtime then
    local entry = read_file_coro(path)
    if entry then self._cache[path] = entry end
    return entry
  end

  local mtime = get_mtime_coro(path)
  if mtime and mtime == cached.mtime then
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

-- Callback API (safe to call from non-async context)
function FileCache:get(path, callback)
  async.run(function()
    return self:get_async(path)
  end, callback)
end
```

#### DirectoryCache (after fix)

Same pattern applied—`get_async()` is pure coroutine, `get()` wraps with `async.run()`.

### Why This Works

1. **Pipeline stages run inside `async.run()`** (see `pipeline.lua` line 33)
2. **Stages call `ctx.file_cache:get_async()`** which is now a pure coroutine function
3. **`get_async()` uses `async.uv.*`** which correctly yields within that coroutine
4. **No oneshot channels needed**—no cross-coroutine bridging

### Test Results

All tests pass after the fix:

```
Unit tests:     62 passing
Integration:    12 passing
Total:          74 passing
```

### Comparison to Original Recommendation

| Aspect | Option 5 (Background Worker) | Option 2 (Coroutine-First) |
|--------|------------------------------|---------------------------|
| Complexity | Medium (mpsc channels, worker loop) | **Low** (just restructure) |
| Lines changed | ~100+ | **~50** |
| Consumer impact | None | **None** |
| Fixes root cause | Yes | **Yes** |
| Performance | Optimal async I/O | **Optimal async I/O** |

Option 2 achieved the same goals with less complexity. The background worker pattern would be useful if we needed request deduplication or backpressure, but for this use case, coroutine-first is sufficient.

### Lessons Learned

1. **Plenary's `async.uv.*` functions always yield**—they're not callback-based despite wrapping callback-based libuv functions
2. **Don't mix callback and coroutine patterns**—pick one and be consistent
3. **The callback API can wrap the coroutine API**, not vice versa
