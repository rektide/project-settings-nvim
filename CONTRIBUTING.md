# Contributing to nvim-project-config

Development guidelines and architectural principles.

## Core Principles

### State Lives on Context

All mutable state belongs on `ctx`, never inside closures or module-level variables.

```lua
-- GOOD: State on ctx
function my_stage(ctx, input, output)
  ctx.my_stage_data = ctx.my_stage_data or {}
  table.insert(ctx.my_stage_data, input)
  output:send(input)
end

-- BAD: State in closure
local accumulated = {}
function my_stage(ctx, input, output)
  table.insert(accumulated, input)  -- Hidden state, survives clear()
  output:send(input)
end
```

**Why**: Clear semantics. When `clear()` is called, we nil out ctx fields. Closure state is invisible and persists incorrectly.

### Stages Are Stateless Factories

Stage constructors like `detect(opts)` return stateless functions. Configuration is captured, but no mutable state:

```lua
-- GOOD: opts captured, no mutable state
function detect(opts)
  return function(ctx, input, output)
    -- opts.matcher is config, immutable
    -- ctx.project_root is state, mutable
    if matches(input, opts.matcher) then
      opts.on_match(ctx, input)
    end
    output:send(input)
  end
end

-- BAD: mutable state in factory closure
function detect(opts)
  local seen = {}  -- Persists across clear()!
  return function(ctx, input, output)
    if not seen[input] then
      seen[input] = true
      -- ...
    end
  end
end
```

### Channels for Flow Control and Cancellation

Channels live on ctx. Closing them signals cancellation:

```lua
ctx.channels = {
  walk_out = async.control.channel.mpsc(),
  detect_out = async.control.channel.mpsc(),
  find_out = async.control.channel.mpsc(),
  -- execute is terminal, no output channel
}
```

Clear closes all channels:

```lua
function clear(ctx)
  -- Close channels to stop in-flight work
  for name, ch in pairs(ctx.channels or {}) do
    pcall(function() ch.tx:close() end)
  end
  
  -- Clear state fields
  ctx.project_root = nil
  ctx.project_name = nil
  ctx.json = nil
  ctx._last_project_json = nil
  ctx._files_loaded = nil
  ctx.channels = nil
  
  -- Notify listeners
  if ctx.on_clear then
    ctx.on_clear(ctx)
  end
end
```

New pipeline run creates fresh channels.

## Async Stage Pattern

Stages receive input channel, write to output channel, handle cancellation naturally:

```lua
local async = require("plenary.async")

function create_detect_stage(opts)
  return function(ctx, input_rx, output_tx)
    async.run(function()
      -- Iterate input channel
      -- Loop exits when channel closes (cancellation or upstream done)
      for path in input_rx:iter() do
        -- Async work is fine
        local target = path .. "/" .. opts.matcher
        local stat = async.uv.fs_stat(target)
        
        if stat then
          opts.on_match(ctx, path)
        end
        
        -- Forward to next stage
        -- Check if output still open (may have been closed by clear())
        local ok = pcall(function() output_tx:send(path) end)
        if not ok then
          break  -- Output closed, stop processing
        end
      end
      
      -- Done with all inputs, close our output
      pcall(function() output_tx:close() end)
    end)
  end
end
```

### Checking for Cancellation Mid-Work

For long-running operations, check channel state:

```lua
function create_walk_stage(opts)
  return function(ctx, input_rx, output_tx)
    async.run(function()
      for start_path in input_rx:iter() do
        local current = start_path
        
        while current ~= "/" do
          -- Check if we should stop
          if output_tx:is_closed() then
            return
          end
          
          -- Yield this directory
          local ok = pcall(function() output_tx:send(current) end)
          if not ok then return end
          
          -- Walk up
          current = vim.fn.fnamemodify(current, ":h")
        end
      end
      
      pcall(function() output_tx:close() end)
    end)
  end
end
```

## Pipeline Orchestration

The pipeline runner wires stages together:

```lua
function run_pipeline(ctx, stages, initial_input)
  -- Create fresh channels
  ctx.channels = {}
  local prev_rx = nil
  
  -- Create channel chain
  for i, stage in ipairs(stages) do
    local ch = async.control.channel.mpsc()
    ctx.channels[i] = ch
    
    if i == 1 then
      -- Seed first stage
      async.run(function()
        ch.tx:send(initial_input)
        ch.tx:close()
      end)
    end
    
    prev_rx = ch.rx
  end
  
  -- Wire stages: each reads from prev, writes to next
  for i, stage in ipairs(stages) do
    local input_rx = ctx.channels[i].rx
    local output_tx = ctx.channels[i + 1] and ctx.channels[i + 1].tx or nil
    
    if output_tx then
      stage(ctx, input_rx, output_tx)
    else
      -- Terminal stage, no output
      stage(ctx, input_rx, {
        send = function() end,
        close = function() end,
        is_closed = function() return true end,
      })
    end
  end
  
  -- Completion: when final channel closes (or use a done callback)
end
```

## Cache Guidelines

### Directory Cache

- Uses `vim.loop.fs_readdir` (single directory, not recursive)
- Cache key: directory path
- Invalidation: mtime comparison before returning cached value
- One entry = one directory's immediate children

```lua
function get(path)
  local stat = async.uv.fs_stat(path)
  local cached = cache[path]
  
  if cached and cached.mtime == stat.mtime.sec then
    return cached.entries
  end
  
  local entries = async.uv.fs_readdir(path)
  cache[path] = { entries = entries, mtime = stat.mtime.sec }
  return entries
end
```

### File Cache

- Stores: path, content, mtime, parsed data (e.g., `.json`)
- Write-through: writes update cache then disk
- On mtime mismatch: discard parsed data, reload content

## Testing

- Use `.test-agent/` for temporary test files
- Test stages in isolation with mock channels
- Test clear() actually stops in-flight work
- Test mtime invalidation with actual file modifications

## Code Style

- Async-first using `plenary.async`
- No blocking calls (`vim.fn.readfile` → `async.uv.fs_read`)
- Prefer early returns over deep nesting
- State on ctx, config in opts, no hidden module state
