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
