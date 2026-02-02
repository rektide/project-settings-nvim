# Async Write Channel Fix - Summary

## Problems Solved

### 1. uv.fs_open Hanging Forever
**Symptom:** Consumer coroutine would hang at `uv.fs_open()` and never process writes.

**Root Cause:** `plenary.async.uv` wrapper returns values in `(err, result)` order, NOT `(result, err)` like `vim.loop`.

**Fix:**
```lua
-- ❌ Wrong - this hangs!
local fd, err = uv.fs_open(path, "w", 438)

-- ✅ Correct
local err, fd = uv.fs_open(path, "w", 438)
if not err then
  -- Use fd
end
```

### 2. Multiple Setup Calls Causing Oneshot Error
**Symptom:** "Oneshot channel can only send once" error on startup/reload.

**Root Cause:** `npc.setup()` being called multiple times, creating multiple oneshot channels for same context.

**Fix:** Added `_initialized` guard to prevent re-initialization.

### 3. Reactive Table Data Inaccessible
**Symptom:** JSON files always empty, reactive data not written.

**Root Cause:** Lua 5.1 doesn't support `__pairs` metamethod, so `write_json()` couldn't iterate reactive table.

**Fix:** Added `_get_data()` method to expose internal data.

### 4. async.void() vs async.run() Confusion
**Insight:** `async.run()` expects a callback and is for one-off operations. `async.void()` is for fire-and-forget patterns like event handlers or long-running consumers.

**Pattern for Consumer:**
```lua
-- ✅ Correct for consumer that runs forever
async.void(function()
  while true do
    local data = receiver.recv()
    -- Process data
  end
end)()
```

## Key Learnings from plenary.nvim Investigation

1. **Always use `plenary.async.uv`** - Never `vim.loop` in async context
2. **Check return value order** - `plenary.async.uv` returns `(err, result)` 
3. **Choose right async starter**:
   - `async.run(fn, callback)` - One-off operations
   - `async.void(fn)` - Fire-and-forget, long-running consumers
4. **Lua 5.1 limitations** - No `__pairs`, need custom getters

## Files Changed

- `lua/nvim-project-config/cache/file.lua` - Async write channel implementation
- `lua/nvim-project-config/init.lua` - Setup guard, reactive table
- `lua/nvim-project-config/executors/json.lua` - Data access patterns

## Testing Verified

✅ Reactive writes work
✅ Async consumer processes writes without hanging
✅ JSON files persist correctly
✅ File recreation after deletion works
✅ No debug spam in production
✅ Can read back from reactive table

## Vital Insight: Print/Logging Works in Async Context

### Discovery
During debugging, I used `print()` statements inside the async consumer coroutine and they appeared in Neovim output immediately:

```lua
async.void(function()
  print("[NPC] Async write consumer started")  -- ✅ THIS WORKS!
  while true do
    local write_req = receiver.recv()
    print("[NPC] Got write request: " .. write_req.path)  -- ✅ THIS WORKS!
    write_file(write_req.path, write_req.data)
  end
end)()
```

### Why This Works
- `print()` is a **synchronous** operation that writes to stdout immediately
- It does **not yield** the coroutine
- It executes immediately in whatever context (async or sync)

### Why This Matters
1. **Debugging is possible** - We can add print() statements anywhere in async code
2. **Async context WAS working** - The coroutine wasn't dead, it was just stuck on uv functions
3. **Problem isolation** - Since print() worked, we knew the issue was specifically with uv.fs_open/fs_write

### What Failed
The async functions themselves:
```lua
local err, fd = uv.fs_open(path, "w", 438)  -- ❌ Hung here
```

This is because `plenary.async.uv` wrapper was being used incorrectly - wrong return value order meant it never properly opened the file.

### Debugging Pattern
```lua
-- ✅ Working pattern for debugging async code:
async.run(function()
  print("Step 1: Starting")  -- Immediate output
  local err, result = some_async_call()  -- Hangs here
  print("Step 2: Done")  -- Never prints if step 1 hangs
end, function() print("Callback") end)

-- If you see "Step 1" but not "Step 2", you know some_async_call() hung
-- If you never see "Callback", async.run() itself hung
```

### Key Takeaway
**Async coroutines in Neovim can use print() for debugging** - this makes debugging async issues much easier than I initially thought. The problem was never that we couldn't log - the problem was specific uv function calls with incorrect return value handling.

