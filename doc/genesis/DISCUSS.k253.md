# Adopting opus3 Architecture: Additions and Changes

If we adopt README.opus3.md as the base architecture, here are the main additions and modifications needed:

## What We'd Keep (opus3 Strengths)

1. **Callback-based streaming** - Their `(ctx, input, stage_num, next_stage)` interface achieves streaming without generator complexity
2. **File organization** - Clear `stages/`, `executors/`, `cache/` separation
3. **Caching strategy** - mtime-based invalidation, write-through file cache
4. **JSON handling** - Merge strategy, dot-notation access API
5. **Context lifecycle** - Explicit clear semantics

## What We'd Add

### 1. Pipeline Completion Detection

**Missing**: opus3 lists this as an open question. They don't specify how to know when pipeline is done.

**Add**: Counter-based tracking with callback
```lua
function pipeline.run(stages, ctx, input, on_complete)
  local pending = 0
  local completed = false
  
  local function next_stage(...)
    pending = pending + 1
    -- ... process stage
    pending = pending - 1
    if completed and pending == 0 then
      on_complete(ctx)
    end
  end
  
  stages[1](ctx, input, 1, next_stage)
  completed = true
  if pending == 0 then on_complete(ctx) end
end
```

### 2. Error Handling Strategy

**Missing**: opus3 doesn't specify error propagation. Stages could fail silently.

**Add**: Configurable per-stage error handling
```lua
stages = {
  {
    fn = walk_stage,
    on_error = "fail"  -- "fail" | "continue" | "skip" | function(err)
  }
}

-- In pipeline.run:
local ok, err = pcall(stage.fn, ctx, input, stage_num, next_stage)
if not ok then
  if stage.on_error == "fail" then
    error(err)
  elseif stage.on_error == "continue" then
    next_stage(ctx, input, stage_num + 1)  -- Continue with unchanged input
  end
end
```

### 3. Matcher Composition Utilities

**Partial**: opus3 mentions matchers but doesn't show implementation.

**Add**: Full implementation with `and`, `or`, `not` combinators
```lua
matchers.any(".git", ".hg", custom_fn)     -- OR
matchers.all(".git", matchers.not_(".hg")) -- AND + NOT
matchers.process(matcher)                   -- Normalize any type
```

### 4. Async/Await Wrapper

**Missing**: opus3 uses callbacks but doesn't provide async/await consumer API.

**Add**: Plenary async wrapper for cleaner consumption
```lua
function pipeline.run_async(stages, ctx, input)
  return async.run(function()
    local done = false
    local result = nil
    
    pipeline.run(stages, ctx, input, function(ctx)
      result = ctx
      done = true
    end)
    
    while not done do
      async.util.sleep(10)
    end
    return result
  end)
end
```

### 5. mtime Fallback Strategy

**Missing**: opus3 mentions "test mtime works" but doesn't specify fallback.

**Add**: Capability detection at startup
```lua
-- In cache initialization
local mtime_works = test_mtime()
if not mtime_works then
  config.cache.file.mtime_check = false
  config.cache.file.dirty_always = true  -- Assume dirty
end
```

### 6. File Watching Implementation

**Vague**: opus3 mentions `watch_directory` and `watch_buffer` but not how they work.

**Add**: Specific watcher implementation
```lua
-- Directory watcher using vim.loop.fs_event or polling
watchers.start_directory_watcher(config_dir, function()
  npc.clear()
  npc.load()
end)

-- Buffer watcher on BufEnter with debouncing
watchers.start_buffer_watcher(vim.debounce_fn(function()
  npc.load()
end, 100))
```

### 7. Nested Project Loading Order

**Underspecified**: opus3 says "deeper file wins" but doesn't specify loading order.

**Clarify**: Explicit load order guarantees
```lua
-- For project "myrepo/package":
1. projects/myrepo.lua              (repo-level defaults)
2. projects/myrepo/init.lua         (if directory form)
3. projects/myrepo-package.lua      (flattened form)
4. projects/myrepo/package.lua      (nested form)
5. projects/myrepo/package/*.lua    (wildcard)

-- Later files override earlier (last wins)
```

### 8. Executor Registration System

**Static**: opus3 shows hardcoded router mapping.

**Add**: Pluggable executor registration
```lua
-- Register custom executor
npc.register_executor("toml", {
  extensions = {".toml"},
  execute = function(ctx, file_path)
    -- Parse and apply TOML
  end
})

-- Auto-discovery from config
config.executors = {
  toml = require("custom.toml-executor"),
  yaml = require("custom.yaml-executor")
}
```

## What We'd Change

### 1. Stage Configuration Structure

**Current**: opus3 mixes stage functions and config at top level.

**Change**: Consistent stage config objects
```lua
-- opus3 style (inconsistent)
pipeline = {walk_fn, detect_fn, find_fn, exec_fn}
walk = {direction = "up"}
detect_root = {markers = {...}}

-- Better: unified stage configuration
stages = {
  walk = {
    fn = walk_stage,
    config = {direction = "up"}
  },
  detect_root = {
    fn = detect_root_stage,
    config = {markers = {...}}
  }
}
```

### 2. Context Mutability Boundaries

**Current**: opus3 allows free mutation.

**Change**: Conventions + validation
```lua
-- Prefix convention for stage data
ctx._walk_directories = {}  -- Private to walk stage
ctx._detect_root_found = false

-- Reserved fields (protected)
ctx.project_root   -- Set by detect_root
ctx.project_name   -- Set by detect_root
ctx.json          -- Set by json executor
```

### 3. Configuration Validation

**Missing**: opus3 doesn't validate config at setup.

**Add**: Schema validation
```lua
function setup(opts)
  local config = vim.tbl_deep_extend("keep", opts, defaults)
  validate_config(config)  -- Error on invalid options
  return config
end
```

### 4. Loading Modes

**Current**: opus3 has boolean `startup.enabled`.

**Extend**: Three explicit modes
```lua
startup = {
  mode = "startup"  -- "startup" | "lazy" | "manual"
  -- startup: load when plugin initializes
  -- lazy: load on first buffer enter
  -- manual: only when npc.load() called
}
```

## Summary Table

| Aspect | opus3 Status | Our Addition/Change |
|--------|--------------|---------------------|
| Streaming | ✅ Callback-based | Add completion tracking |
| File structure | ✅ Well organized | Keep as-is |
| Caching | ✅ mtime-based | Add fallback detection |
| Error handling | ❌ Open question | Add per-stage strategy |
| Matchers | ⚠️ Mentioned only | Full implementation |
| Async API | ❌ Callbacks only | Add async/await wrapper |
| Watchers | ⚠️ Mentioned only | Concrete implementation |
| Nested projects | ⚠️ Vague order | Explicit load order |
| Config validation | ❌ Missing | Add schema validation |
| Stage config | ⚠️ Inconsistent | Unified structure |

## Recommendation

Adopt opus3 architecture as base, then layer on:
1. Completion detection (immediate need)
2. Error handling strategy
3. Full matcher implementation
4. Async wrapper for consumer convenience
5. Concrete watcher implementation

The opus3 foundation is solid - we mainly need to fill in the "how" for their open questions and add quality-of-life improvements like async wrappers and validation.