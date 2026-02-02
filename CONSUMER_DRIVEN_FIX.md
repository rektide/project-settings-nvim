# Proposed Fix: Consumer-Driven Async Handling

## Core Insight

Instead of fixing the cache layer's coroutine bridging complexity, we can:

1. **Document the limitation**: async cache deadlocks when used during pipeline execution
2. **Provide clear workarounds**: use `on_load` callback or `load_await()` promise
3. **Optional**: Add graceful fallback in executors when cache fails

---

## Approach 1: Documented Workaround (Minimal Changes)

### User Guidance

Add to README/API docs:

```lua
require("nvim-project-config").setup({
  on_load = function(ctx)
    -- Cache is now safe to use
    -- Pipeline has completed, all async operations done

    -- Use ctx.json for values
    if ctx.json and ctx.json.formatter then
      -- Do work
    end
  end,
})

-- OR use async/await pattern:

local async = require("plenary.async")
local npc = require("nvim-project-config")

npc.setup()

async.run(function()
  local awaiter = npc.load_await()
  local ctx = awaiter()

  -- Cache operations now safe
  -- Do work here
end)
```

### Document Limitation

```markdown
## Known Limitations

### Async Cache Deadlock

The async cache layer (`ctx.file_cache` and `ctx.dir_cache`) uses plenary's
oneshot channel pattern which can deadlock when called from within the pipeline's
async coroutine context.

**Symptoms**:
- JSON files may not load
- Errors: "Failed to read JSON file: [path]"
- `ctx.json` may be empty

**Workarounds**:

1. **Use `on_load` callback** - All async work is complete when this fires
2. **Use `load_await()`** - Wait for pipeline completion before accessing cache
3. **Disable cache** - Set `ctx.file_cache = nil` and `ctx.dir_cache = nil` after setup

Example:

```lua
npc.setup()

-- Option 1: Use callback
npc.setup({
  on_load = function(ctx)
    -- Safe to use ctx.json here
  end,
})

-- Option 2: Use promise
local async = require("plenary.async")
async.run(function()
  local ctx = npc.load_await()  -- Wait for completion
  -- Safe to use ctx.json here
end)

-- Option 3: Disable cache
npc.setup()
npc.ctx.file_cache = nil
npc.ctx.dir_cache = nil
npc.load()  -- Uses sync I/O, no deadlock
```

**Note**: This affects JSON files during initial load. After load completes,
cache can be used safely from user code (e.g., reactive writes).
```

---

## Approach 2: Graceful Fallback in Executors (Robust)

### JSON Executor Enhancement

```lua
local function json_executor(ctx, file_path)
  local content

  -- Try cache first, fallback to sync I/O on failure
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

  local ok, parsed = pcall(vim.json.decode, content)
  if not ok then
    error("Failed to parse JSON: " .. file_path .. " - " .. tostring(parsed))
  end

  local function deep_merge_into(target, source)
    for k, v in pairs(source) do
      if type(v) == "table" and type(target[k]) == "table" then
        deep_merge_into(target[k], v)
      else
        target[k] = v
      end
    end
  end

  if ctx.json then
    deep_merge_into(ctx.json, parsed)
  else
    ctx.json = parsed
  end

  if matches_project_name(file_path, ctx.project_name) then
    ctx._last_project_json = file_path
  end

  if ctx.file_cache and not entry then
    -- Cache was bypassed, try to cache it now
    local write_ok, _ = pcall(function()
      ctx.file_cache:write_async(file_path, {
        content = content,
      })
    end)
    if not write_ok then
      -- Ignore cache write failures
    end
  end

  if ctx.file_cache then
    local cached = ctx.file_cache._cache and ctx.file_cache._cache[file_path]
    if cached then
      cached.json = parsed
    end
  end
end
```

### Pros

- **User-transparent**: Works automatically, no user action needed
- **Graceful degradation**: Falls back to sync I/O on cache failure
- **Preserves cache**: Tries to cache after successful sync read
- **No breaking changes**: API remains same

### Cons

- More complex executor logic
- May mask underlying cache bug
- Cache still doesn't work during pipeline (just fails gracefully)

---

## Approach 3: Optional Cache Disable (Clean API)

### Setup Option

```lua
defaults = {
  -- ... existing options ...

  -- Allow users to disable cache
  disable_cache = false,
}

function M.setup(opts)
  -- ... existing setup ...

  if config.disable_cache then
    ctx.file_cache = nil
    ctx.dir_cache = nil
  end
  -- ... rest of setup ...
end
```

### Usage

```lua
require("nvim-project-config").setup({
  disable_cache = true,  -- Use sync I/O only
})

-- Or per-executor disable later
npc.ctx.file_cache = nil
```

### Pros

- Clean API
- Explicit opt-out
- Simple implementation

### Cons

- Still requires user to know about the issue
- Opt-in vs automatic

---

## Approach 4: Consumer Must Await (Recommended)

### Documentation Pattern

Document that cache is **pipeline-internal only**:

```markdown
## Context Reference

### ctx.file_cache and ctx.dir_cache

**Internal Use Only**

These cache objects are used internally by the pipeline stages during
configuration loading. They are **not intended for direct use** by
user code.

Use these patterns instead:

1. **Access loaded values via ctx.json**:
   ```lua
   npc.setup({
     on_load = function(ctx)
       -- Values already loaded, merged, and cached
       local formatter = ctx.json.formatter
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

**Why**: The cache layer uses an async coroutine pattern that deadlocks
when used during pipeline execution. User code should access the **results**
of the pipeline (ctx.json, ctx._files_loaded) rather than the
pipeline's internals (cache objects).
```

### Pros

- Clear API boundary (internal vs user-facing)
- No code changes needed
- Guides users to correct patterns

### Cons

- More restrictive than needed
- Might limit valid use cases

---

## Recommendation: Hybrid Approach

Combine **Approach 2 (graceful fallback)** + **Approach 4 (docs)**:

1. **Add graceful fallback** in executors (so it works automatically)
2. **Document cache as internal-only** (guides users to right patterns)
3. **Add troubleshooting section** to README with cache issues

### Implementation Checklist

- [ ] Add `pcall` wrapper around cache reads in JSON executor
- [ ] Add sync I/O fallback when cache fails
- [ ] Update README with "Known Limitations" section
- [ ] Document cache as "internal use only"
- [ ] Add troubleshooting section
- [ ] Update test to work with fallback behavior
- [ ] Consider adding `disable_cache` setup option

---

## Summary Table

| Approach | Changes Required | User Impact | Robustness |
|----------|-----------------|--------------|--------------|
| 1. Document workaround | Docs only | Must read docs | Low |
| 2. Graceful fallback | Executors only | Transparent | High |
| 3. Optional disable | Setup only | Must set option | Medium |
| 4. Document internal | Docs only | Can't use cache | Medium |
| **5. Hybrid (2+4)** | Executors + docs | **Transparent + guided** | **Very High** |

**Recommended**: **Hybrid (2 + 4)** - Graceful fallback in executors + clear documentation
