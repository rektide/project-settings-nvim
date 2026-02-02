# Consumer Experience Analysis

## What the Coroutine Refactor Looks Like for Consumers

### With Full Coroutine Refactor (Recommended)

**Consumer code**:

```lua
local npc = require("nvim-project-config")
local async = require("plenary.async")

npc.setup()

-- Just use on_load - simple and clean
npc.setup({
  on_load = function(ctx)
    -- ctx.json already loaded, merged
    local formatter = ctx.json.formatter
    -- Do work
  end,
})

-- OR use load_await() - also clean
async.run(function()
  local ctx = npc.load_await()
  -- Values ready
end)
```

**✅ Zero change** - consumers already use these patterns.

---

### Internal Code Changes (Where the refactoring happens)

**Before (deadlocking)**:
```lua
-- In JSON executor (internal)
function json_executor(ctx, file_path)
  local entry = ctx.file_cache:get_async(file_path)  -- Deadlocks!
  -- ...
end
```

**After (works)**:
```lua
-- In JSON executor (internal)
function json_executor(ctx, file_path)
  local entry = ctx.file_cache:get(file_path)  -- Simple
  -- ...
end
```

**✅ Internal code becomes simpler** - not more complex.

---

## You're Right - Let's Fix This Differently

**Insight**: The issue is **entirely internal** to cache layer. Consumers shouldn't care.

### New Approach: Transparent Async Cache

**Design goal**: Make `get_async()` work from any context without coroutines.

---

## Fix Option 5: Internal Work Coroutine (Recommended)

### Concept

Spawn a single background coroutine for all cache work. Use mpsc channel for communication.

**No consumer changes needed**.

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
    _work_rx = nil,
  }, FileCache)

  -- Start background work coroutine
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
      local op = work_item.op
      local args = work_item.args

      if op == "read" then
        local path = args.path
        local tx = args.tx

        -- Do the read
        local stat, stat_err = uv.fs_stat(path)
        if stat_err or not stat then
          tx(nil)
        else
          local fd, open_err = uv.fs_open(path, "r", 438)
          if open_err or not fd then
            tx(nil)
          else
            local content, read_err = uv.fs_read(fd, stat.size, 0)
            uv.fs_close(fd)

            if read_err then
              tx(nil)
            else
              local entry = {
                path = path,
                content = content,
                mtime = stat.mtime.sec,
                json = nil,
              }
              self._cache[path] = entry
              tx(entry)
            end
          end
        end

      elseif op == "write" then
        local path = args.path
        local content = args.content
        local tx = args.tx

        local fd, open_err = uv.fs_open(path, "w", 438)
        if open_err or not fd then
          tx(false)
        else
          local _, write_err = uv.fs_write(fd, content, 0)
          uv.fs_close(fd)

          if write_err then
            tx(false)
          else
            local stat = uv.fs_stat(path)
            if stat and stat.mtime.sec then
              self._cache[path] = {
                path = path,
                content = content,
                mtime = stat.mtime.sec,
                json = args.json or nil,
              }
            end
            tx(true)
          end
        end
      end
    end
  end)
end

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
  -- This is now SAFE - tx and rx in same coroutine chain
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

-- ... rest of methods ...
```

### Consumer Experience

**Exactly the same as before**:

```lua
-- User code - ZERO changes
npc.setup({
  on_load = function(ctx)
    local formatter = ctx.json.formatter
  end,
})

-- Internal code - also works
function json_executor(ctx, file_path)
  local entry = ctx.file_cache:get_async(file_path)  -- Works!
  local content = entry.content
  -- ...
end
```

---

## Comparison of All Options

| Option | Consumer Changes | Internal Changes | Deadlocks? | Simplicity |
|--------|-------------------|------------------|--------------|-------------|
| 1. Full coroutine refactor | None (internal only) | High | ✅ No | ⚠️ Medium |
| **5. Background worker** | ✅ **None** | Medium | ✅ **No** | ✅ **Simple** |
| 2. Graceful fallback | None | Low (add pcall) | ⚠️ Masks | ⚠️ Medium |
| 3. Consumer must await | None | None | ⚠️ Works around | ⚠️ Complex for users |

---

## Recommendation: Background Worker (Option 5)

**Why**:

1. ✅ **Zero consumer impact** - API exactly the same
2. ✅ **Fixes root cause** - Proper async pattern
3. ✅ **Works everywhere** - Not coroutine-context dependent
4. ✅ **Clean internal code** - Single worker, clear data flow
5. ✅ **No coroutine bridging** - All in worker coroutine
6. ✅ **No API changes** - `_async()` methods work as expected

**Implementation complexity**: Medium (need worker pattern)
**Maintenance burden**: Low (single place to debug)
**Consumer burden**: **Zero**

---

## Background Worker Implementation Sketch

### Structure

```lua
FileCache
├── _cache          -- storage
├── _work_tx        -- send work to worker
├── _work_rx        -- receive results from worker
└── _start_worker()  -- spawn background coroutine

Worker Coroutine
├── Loop forever
├── Receive work item from mpsc channel
├── Process:
│   ├── "read" operation
│   │   ├── uv.fs_stat()
│   │   ├── uv.fs_open()
│   │   ├── uv.fs_read()
│   │   ├── Update _cache
│   │   └── tx(entry)
│   │
│   └── "write" operation
│       ├── uv.fs_open()
│       ├── uv.fs_write()
│       ├── Update _cache
│       └── tx(success)
│
└── Repeat
```

### Benefits

- All async I/O in single coroutine
- No cross-coroutine bridging
- Consumers get simple `get_async(path)` API
- Internal executors call `get_async()` normally
- No API changes
- No consumer education needed

---

## Final Recommendation

**Implement Option 5 (Background Worker)** because:

1. ✅ **Zero consumer impact** - Most important factor
2. ✅ **Fixes deadlock** - Solves the actual problem
3. ✅ **Clean internal architecture** - Worker pattern is clear
4. ✅ **No API breaking** - Existing `_async()` methods work
5. ✅ **Minimal code changes** - Only cache layer

This is the best balance of technical correctness and user experience.
