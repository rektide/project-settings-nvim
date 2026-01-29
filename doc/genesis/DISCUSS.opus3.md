# nvim-project-config: Architecture Discussion Points

Open questions and design decisions requiring resolution before implementation.

---

## 1. Pipeline Completion Detection

**Problem**: The streaming pipeline design—where each stage calls `next_stage()` for each output—has no built-in "done" signal. Stages fan out: walk yields multiple directories, find_files yields multiple files per directory. How does the system know all branches are complete?

**Why counters don't work**: Fan-out creates a tree of async operations. A simple counter can't track when all leaves have completed without complex parent-child tracking.

**Generator-based approach**:

Each stage is a coroutine that yields results. The pipeline runner consumes yields and feeds them to the next stage, tracking completion naturally:

```lua
-- Stage as generator
function walk(ctx, input)
  return coroutine.create(function()
    for _, dir in ipairs(get_parents(input)) do
      coroutine.yield(dir)
    end
  end)
end

-- Pipeline runner
function run_pipeline(stages, ctx, initial_input)
  local function run_stage(stage_idx, input)
    if stage_idx > #stages then
      return -- Terminal: all stages complete for this branch
    end
    
    local stage = stages[stage_idx]
    local gen = stage(ctx, input)
    
    while true do
      local ok, value = coroutine.resume(gen)
      if not ok or coroutine.status(gen) == "dead" then
        break
      end
      run_stage(stage_idx + 1, value)  -- Recurse into next stage
    end
  end
  
  run_stage(1, initial_input)
  -- When run_stage(1, ...) returns, all branches complete
  if ctx.config.on_load then
    ctx.config.on_load(ctx)
  end
end
```

**Async variant with plenary**:

```lua
local async = require("plenary.async")

-- Async generator using channels
function walk_async(ctx, input, output_channel)
  async.run(function()
    for _, dir in ipairs(get_parents(input)) do
      output_channel:send(dir)
    end
    output_channel:close()
  end)
end

-- Runner consumes channel, spawns child stages
function run_stage_async(stage_idx, input, stages, ctx, done_callback)
  if stage_idx > #stages then
    done_callback()
    return
  end
  
  local channel = async.control.channel.mpsc()
  local pending = 0
  local stage_done = false
  
  stages[stage_idx](ctx, input, channel.tx)
  
  async.run(function()
    for value in channel.rx do
      pending = pending + 1
      run_stage_async(stage_idx + 1, value, stages, ctx, function()
        pending = pending - 1
        if stage_done and pending == 0 then
          done_callback()
        end
      end)
    end
    stage_done = true
    if pending == 0 then
      done_callback()
    end
  end)
end
```

**Recommendation**: Generator/coroutine pattern. Natural completion when generator exhausts. For async, use channels with completion tracking per-stage.

---

## 2. Clear Semantics

**Problem**: What exactly happens when `clear()` is called? Need to reset state for re-detection while preserving user configuration.

**What gets cleared** (proposed):
- `ctx.project_root`
- `ctx.project_name`
- `ctx.json` (merged JSON state)
- `ctx._files_loaded` (tracking table)

**What persists**:
- `ctx.config_dir`
- `ctx.config.*` (all user settings)
- Cache contents (separate concern)

**Implementation options**:

| Approach | Description | Pros | Cons |
|----------|-------------|------|------|
| Hardcoded | Explicit `ctx.project_root = nil` etc. | Fast, predictable | Brittle if fields added |
| Field list | `for _, field in ipairs(CLEARABLE_FIELDS) do ctx[field] = nil end` | Extensible | Still centralized knowledge |
| Event | Emit `on_clear`, stages/executors clean themselves | Decoupled | Stages must implement cleanup |
| Recreate | Build fresh context, copy config over | Clean slate | Loses any desirable state |

**Recommendation**: Field list + event hybrid. Clear known fields, then emit `on_clear` for custom cleanup:

```lua
function clear(ctx)
  for _, field in ipairs({ "project_root", "project_name", "json", "_files_loaded" }) do
    ctx[field] = nil
  end
  if ctx.config.on_clear then
    ctx.config.on_clear(ctx)
  end
end
```

---

## 3. Stage Function Signature

**Current**: `function(ctx, input, stage_num, next_stage)`

**Question**: Is passing `stage_num` explicitly worth the noise? Should `next_stage` hide boilerplate?

**Option A**: Keep explicit (current)
```lua
function walk(ctx, input, stage_num, next_stage)
  for _, dir in ipairs(parents) do
    next_stage(ctx, dir, stage_num + 1)
  end
end
```

**Option B**: Curried next
```lua
function walk(ctx, input, next)
  for _, dir in ipairs(parents) do
    next(dir)  -- ctx and stage tracking internal
  end
end
```

**Option C**: Pipeline controller pattern
```lua
function walk(pipeline, input)
  for _, dir in ipairs(parents) do
    pipeline:emit(dir)
  end
end
-- pipeline object holds ctx, stage info, next-stage dispatch
```

**Recommendation**: Option B for cleaner stage code. Stage number useful for debugging—could be `ctx._stage` or logged internally.

---

## 4. Nested Project Loading & Ordering

**Scenario**: Project at `~/src/big-repo/packages/frontend/`

Files that might load:
1. `projects/big-repo.lua`
2. `projects/big-repo.json`
3. `projects/big-repo/frontend.lua`
4. `projects/big-repo/frontend.json`
5. `projects/big-repo/frontend/init.lua`

**Questions**:

1. **Load all or most-specific?** 
   - Current design: Load all, merge with late wins
   - Alternative: Only most specific match

2. **Guaranteed order?**
   - Depth-first (all of `big-repo.*` before `big-repo/frontend.*`)?
   - Alphabetical within each tier?
   - Extension priority (`.json` before `.lua` so Lua can read JSON)?

3. **How is nesting detected?**
   - Walk yields multiple project names as it traverses?
   - Single `find_files` call that expands nesting internally?

**Recommendation**: 
- Load all matching files (composability)
- Order: breadth-first by path depth, then alphabetical, then extension (`.json` → `.lua` → `.vim`)
- This lets base config establish defaults, specific configs override, and Lua can always read the merged JSON

```
Load order for big-repo/frontend:
1. big-repo.json
2. big-repo.lua
3. big-repo.vim
4. big-repo/frontend.json
5. big-repo/frontend.lua
6. big-repo/frontend.vim
7. big-repo/frontend/init.json
8. big-repo/frontend/init.lua
...
```

---

## 5. JSON Write Target

**Problem**: When `json.set("key", value)` is called, which file receives the write?

**Scenario**: Loaded files:
- `projects/myproject.json` (base settings)
- `projects/myproject/local.json` (local overrides)

**Options**:

| Strategy | Write target | Pros | Cons |
|----------|--------------|------|------|
| First loaded | `myproject.json` | Predictable | Overwrites shared config |
| Last loaded | `myproject/local.json` | Writes to "override" file | May not exist yet |
| Most specific | Deepest matching project path | Intuitive locality | Complex resolution |
| Explicit | `ctx.json_write_target` set by config | Full control | User must configure |
| Create new | `myproject.local.json` (new file) | Never clobbers | File proliferation |

**Recommendation**: Follow the general rule that **last matching file wins**. Track the last JSON file that matches the project root name pattern.

The executor tracks `ctx._last_project_json` as it processes files. Files matching the project root name (e.g., `rad-project.json` or `rad-project/settings.json` for project `rad-project`) update this tracker. Writes go there.

```lua
-- During JSON executor processing
function process_json(ctx, file_path)
  local content = cache.file.get(file_path)
  ctx.json = vim.tbl_deep_extend("force", ctx.json or {}, content.json)
  
  -- Track last file matching project root name pattern
  local basename = vim.fn.fnamemodify(file_path, ":t:r")
  local parent = vim.fn.fnamemodify(file_path, ":h:t")
  if basename == ctx.project_name or parent == ctx.project_name then
    ctx._last_project_json = file_path
  end
end

function get_write_target(ctx)
  if ctx._last_project_json then
    return ctx._last_project_json
  end
  -- Fallback: create at project level
  return ctx.config_dir .. "/" .. ctx.project_name .. ".json"
end
```

**Open question**: Should writes be batched/debounced or immediate?

---

## 6. mtime Reliability Detection

**Problem**: Some filesystems or edge cases may not provide reliable mtime. Need fallback to "assume dirty" cache strategy.

**Detection approaches**:

| Approach | When | Mechanism |
|----------|------|-----------|
| Startup probe | Once on `setup()` | Write temp file, stat, compare |
| Per-path | First access to each path | Stat before/after read |
| Exception-based | On mtime mismatch | Catch and flag |
| Config flag | User setting | `cache.trust_mtime = false` |

**Recommendation**: Startup probe + config override:

```lua
function probe_mtime_reliability()
  local tmp = os.tmpname()
  local f = io.open(tmp, "w")
  f:write("test")
  f:close()
  
  local stat1 = vim.loop.fs_stat(tmp)
  vim.loop.sleep(10)  -- Ensure time passes
  
  f = io.open(tmp, "w")
  f:write("test2")
  f:close()
  
  local stat2 = vim.loop.fs_stat(tmp)
  os.remove(tmp)
  
  return stat2.mtime.sec > stat1.mtime.sec or stat2.mtime.nsec > stat1.mtime.nsec
end
```

If probe fails, set `ctx._mtime_reliable = false` and caches always re-read.

**Fallback behavior**: When mtime is unreliable, caches operate in "assume dirty" mode:
- Directory cache re-scans on every access
- File cache re-reads on every access
- JSON parsed fields (`.json`) are regenerated each time
- Performance degrades but correctness preserved

This is a last-resort mode. Users on problematic filesystems (some network mounts, FUSE) can also force it via config:

```lua
require("nvim-project-config").setup({
  cache = {
    trust_mtime = false,  -- Force assume-dirty mode
  }
})
```

---

## 7. Watcher Granularity

**`watch_directory`**: Watch config directory for changes.

- Use `vim.loop.fs_event` on config dir
- Debounce (100ms?) to batch rapid changes
- On change: `clear()` then `load()`

**`watch_buffer`**: Reload when project context might change.

**Trigger options**:

| Event | When fires | Appropriate? |
|-------|------------|--------------|
| `BufEnter` | Every buffer switch | Too noisy |
| `DirChanged` | `cd` or `lcd` | Yes, direct relevance |
| `VimEnter` | Startup | Covered by `startup.enabled` |
| `BufReadPost` | File opened | Only if cwd changed |

**Recommendation**: 
- `watch_buffer` triggers on `DirChanged` only
- Debounce with 50ms to handle rapid directory traversal
- Compare `cwd` to last-loaded project root; skip if same

```lua
if opts.startup.watch_buffer then
  vim.api.nvim_create_autocmd("DirChanged", {
    callback = function()
      vim.defer_fn(function()
        local cwd = vim.fn.getcwd()
        if cwd ~= ctx._last_cwd then
          ctx._last_cwd = cwd
          npc.clear()
          npc.load()
        end
      end, 50)
    end
  })
end
```

---

## 8. Error Handling & Boundaries

**Question**: When a stage or executor fails, what happens?

**Failure points**:
1. Walk can't read directory (permissions)
2. Detect root matcher throws
3. Find files can't scan config dir
4. Execute: Lua file has syntax error
5. Execute: JSON is malformed
6. Cache: mtime stat fails

**Options**:

| Strategy | Behavior | Pros | Cons |
|----------|----------|------|------|
| Fail fast | Stop pipeline, call `on_error` | Clear failure signal | One bad file breaks all |
| Isolate per-file | Log error, continue with other files | Resilient | Partial config state |
| Retry | Exponential backoff for transient errors | Handles flaky FS | Complexity, delay |
| Collect | Gather all errors, report at end | Complete picture | User sees delayed errors |

**Recommendation**: Isolate per-file for execute stage, fail-fast for infrastructure stages:

```lua
-- Execute stage
function execute(ctx, file_path, stage_num, next_stage)
  local ok, err = pcall(function()
    run_executor(ctx, file_path)
  end)
  
  if not ok then
    if ctx.config.on_error then
      ctx.config.on_error(err, ctx, file_path)
    else
      vim.notify("nvim-project-config: " .. file_path .. ": " .. err, vim.log.levels.WARN)
    end
  end
  
  -- Continue pipeline regardless (no next_stage call needed for execute, it's terminal)
end
```

---

## 9. Matcher Normalization

**Current design**: Matchers accept string | pattern | function | table (OR'd).

**Questions**:

1. **When is normalization done?** At config time or match time?
2. **How to distinguish string from pattern?** Lua patterns use `%`, but `.git` could be literal or pattern.
3. **Should we support regex?** Via `vim.regex()`?

**Recommendation**: Normalize at config time, treat strings as literal (exact match), require explicit pattern wrapper:

```lua
local M = require("nvim-project-config.matchers")

-- These are equivalent:
M.literal(".git")     -- Explicit literal
".git"                -- String = literal by default

-- Pattern requires wrapper:
M.pattern("%.lua$")   -- Lua pattern
M.regex([[\.lua$]])   -- Vim regex (optional)

-- Normalized form (internal):
{
  type = "literal" | "pattern" | "regex" | "function",
  value = <string or function>,
  match = function(input) -> boolean
}
```

---

## 10. Cache Scope & Lifetime

**Question**: Are caches global (across all nvim-project-config instances) or per-setup?

**Scenarios**:
- User calls `setup()` twice with different configs
- Multiple projects open in splits with different cwds
- `:cd` changes project context

**Options**:

| Scope | Lifetime | Pros | Cons |
|-------|----------|------|------|
| Global singleton | Neovim session | Shared efficiency | Config collision |
| Per-setup | Until next `setup()` | Isolated | Memory if setup() called often |
| Per-context | Per load/clear cycle | Fresh each time | No caching benefit |

**Recommendation**: Global singleton with namespaced entries:

```lua
-- Cache key includes relevant context
local cache_key = config_dir .. ":" .. path
_G._nvim_project_config_cache[cache_key] = entry
```

This allows cache sharing when config is identical, isolation when different.

---

## Summary: Decisions Needed

| # | Topic | Recommended Resolution |
|---|-------|------------------------|
| 1 | Pipeline completion | Generator/coroutine pattern with channel-based async |
| 2 | Clear semantics | Field list + on_clear event |
| 3 | Stage signature | Curried next, hide stage_num |
| 4 | Nested loading order | All files, breadth-first, json→lua→vim |
| 5 | JSON write target | Last matching project-root-named file wins |
| 6 | mtime reliability | Startup probe + config override + assume-dirty fallback |
| 7 | Watcher triggers | DirChanged only, debounced |
| 8 | Error handling | Isolate per-file in execute, fail-fast elsewhere |
| 9 | Matcher normalization | Config-time, strings literal, pattern wrapper |
| 10 | Cache scope | Global singleton, namespaced keys |

---

## Next Steps

1. Finalize decisions on above points
2. Define TypeScript/Lua types for core structures (Context, Stage, Matcher, CacheEntry)
3. Implement cache layer first (foundation for everything)
4. Build pipeline orchestration with counter-based completion
5. Implement stages in order: walk → detect_root → find_files → execute
6. Add watchers last (optional enhancement)
