# Discussion Points: nvim-project-config Architecture

This document captures open architectural decisions and design questions that need resolution before implementation.

## 1. Pipeline Completion Detection

**Problem**: The current continuation-based pipeline has no explicit "done" signal. Stages call each other, but the initiator doesn't know when processing completes.

### Options

**A. Callback-based**
```lua
-- Initiator passes done callback
pipeline.run(context, initial_input, function(final_results)
  print("Pipeline complete")
end)

-- Last stage calls it
function execute_files(context, files, stage_num, done)
  -- Process all files
  done(collected_results)
end
```
*Pros*: Simple, explicit
*Cons*: Callback hell if nested, error handling unclear

**B. Promise-based (Plenary async)**
```lua
local async = require('plenary.async')

function pipeline.run(context, input)
  return async.run(function()
    -- Stages return values instead of calling next
    local result = stage1(context, input)
    result = stage2(context, result)
    return stage3(context, result)
  end)
end

-- Usage
async.run(function()
  local results = pipeline.run(ctx, input)
  print("Complete")
end)
```
*Pros*: Familiar async pattern, composable, error propagation via pcall
*Cons*: Requires restructuring to return values, not continuation-passing

**C. Event-based**
```lua
-- Emit completion event
pipeline.on('complete', function(results)
  print("Done")
end)

-- Last stage emits
function execute_files(context, files)
  -- Process
  pipeline.emit('complete', results)
end
```
*Pros*: Decoupled, multiple listeners possible
*Cons*: Harder to track, potential memory leaks with handlers

**D. Generator/Iterator pattern**
```lua
-- Stages yield results as they're ready
function walk_stage(context, start_path)
  coroutine.yield(directory1)
  coroutine.yield(directory2)
end

-- Consumer iterates
for dir in pipeline.run(ctx, path) do
  print("Got", dir)
end
print("Complete")
```
*Pros*: Streaming results, backpressure control
*Cons*: Complex to implement, Lua coroutine limitations

**Recommendation**: Option B (Promise-based) aligns with Plenary and Neovim's async model.

---

## 2. Clear/Reset Strategy

**Problem**: When watching is enabled and configs change, what state needs reset? How do we ensure a clean reload?

### Options

**A. Hardcoded Reset List**
```lua
function context.clear()
  context.project_root = nil
  context.project_name = nil
  context.json_data = {}
  context.dir_cache:clear()
  context.file_cache:clear()
end
```
*Pros*: Predictable, fast
*Cons*: Not extensible, custom stage data might persist incorrectly

**B. Event-based Reset**
```lua
context.on('before:clear', function(ctx)
  -- Custom stages register handlers
  ctx.custom_data = nil
end)

function context.clear()
  context.emit('before:clear', context)
  -- Then clear built-ins
end
```
*Pros*: Extensible, stages manage their own cleanup
*Cons*: More complex, handler ordering issues

**C. Fresh Instance**
```lua
function pipeline.reload(config)
  -- Create entirely new context
  local new_ctx = context.create(config)
  -- Replace reference
  state.context = new_ctx
  -- Run pipeline
  return pipeline.run(new_ctx, vim.fn.getcwd())
end
```
*Pros*: Guaranteed clean state, no stale references
*Cons*: Expensive, loses accumulated state

**D. Selective Reset Registry**
```lua
-- Stages register resettable fields
context.register_reset('project_root')
context.register_reset('json_data')

function context.clear()
  for _, field in ipairs(context.resettable_fields) do
    context[field] = nil
  end
end
```
*Pros*: Middle ground between hardcoded and event-based
*Cons*: Requires registration discipline

**Recommendation**: Option A for MVP, migrate to D if extensibility needed.

---

## 3. Stage Interface Design

**Problem**: What contract should stages follow? How do they communicate?

### Options

**A. Function with continuation**
```lua
function stage(context, input, stage_num, next_stage)
  local result = process(input)
  next_stage(context, result, stage_num + 1)
end
```
*Pros*: Direct control flow, can skip next stage
*Cons*: Tight coupling, harder to compose

**B. Return value pattern**
```lua
function stage(context, input)
  return process(input)
end

-- Orchestrator handles flow
function pipeline.run(stages, context, input)
  for i, stage in ipairs(stages) do
    input = stage(context, input)
    if input == nil then break end
  end
  return input
end
```
*Pros*: Pure functions, easier to test, sequential flow obvious
*Cons*: Can't easily stream multiple outputs

**C. Object with lifecycle**
```lua
local Stage = {}

function Stage:new(name, processor)
  return setmetatable({
    name = name,
    process = processor,
    outputs = {}
  }, self)
end

function Stage:execute(context, input)
  self.outputs = self.process(context, input)
  return self.outputs
end
```
*Pros*: State tracking, extensible
*Cons*: Boilerplate, OOP complexity

**D. Middleware pattern**
```lua
function create_stage(processor)
  return function(context, input, next)
    local result = processor(context, input)
    if result then
      return next(context, result)
    end
  end
end

-- Compose
local pipeline = compose(
  walk_stage,
  detect_root_stage,
  find_files_stage,
  execute_files_stage
)
```
*Pros*: Expressive, functional, can short-circuit
*Cons*: Compose order is reversed from execution order (confusing)

**E. Generator/Iterator Pattern**
```lua
-- Stages yield outputs as they're produced
function walk_stage(context, start_path)
  local current = start_path
  while current do
    coroutine.yield(current)  -- Yield each directory
    current = vim.fn.fnamemodify(current, ":h")
  end
end

-- Orchestrator consumes generator
function pipeline.run(stages, context, input)
  local outputs = {}
  
  for _, stage in ipairs(stages) do
    local gen = coroutine.create(stage)
    local stage_outputs = {}
    
    while true do
      local ok, output = coroutine.resume(gen, context, input)
      if not ok then
        error(output)  -- Propagate error
      end
      if coroutine.status(gen) == "dead" then
        break
      end
      table.insert(stage_outputs, output)
    end
    
    outputs = stage_outputs
    input = outputs  -- Pass all outputs to next stage
  end
  
  return outputs
end
```
*Pros*: 
- True streaming: outputs flow as soon as ready
- Memory efficient for large result sets
- Backpressure control (consumer controls pace)
- Can short-circuit (stop consuming)
- Natural for walk operations producing multiple directories

*Cons*: 
- Lua coroutine limitations (no native async/await)
- Complex error handling across yield boundaries
- Harder to debug (non-linear execution)
- Requires all stages to handle array inputs

**Generator with Consumer Callback:**
```lua
-- Alternative: generator calls consumer directly
function walk_stage(context, start_path, consume)
  local current = start_path
  while current do
    if not consume(context, current) then
      break  -- Consumer signaled stop
    end
    current = vim.fn.fnamemodify(current, ":h")
  end
end

-- Pipeline orchestrator
function pipeline.run(stages, context, input)
  local results = {input}
  
  for _, stage in ipairs(stages) do
    local next_results = {}
    
    for _, item in ipairs(results) do
      stage(context, item, function(ctx, output)
        table.insert(next_results, output)
        return true  -- Continue yielding
      end)
    end
    
    results = next_results
  end
  
  return results
end
```
*Pros*: Simpler than pure generators, explicit control flow
*Cons*: Callback-based, still somewhat complex

**F. Streaming with Repeated Next-Stage Calls**
```lua
-- Stage calls next_stage multiple times, once per result
-- Enables true streaming without waiting for all results
function walk_stage(context, start_path, next_stage, stage_num)
  local current = start_path
  while current do
    -- Immediately pass result to next stage, don't wait
    next_stage(context, current, stage_num + 1)
    current = vim.fn.fnamemodify(current, ":h")
  end
end

-- Orchestrator manages flow with a counter to detect completion
function pipeline.run(stages, context, input, stage_num, on_complete)
  stage_num = stage_num or 1
  
  if stage_num > #stages then
    -- Pipeline complete
    if on_complete then on_complete() end
    return
  end
  
  local stage = stages[stage_num]
  local pending = 0
  local completed = false
  
  local function next_stage(ctx, output, next_num)
    pending = pending + 1
    vim.schedule(function()
      pipeline.run(stages, ctx, output, next_num, function()
        pending = pending - 1
        if completed and pending == 0 and on_complete then
          on_complete()
        end
      end)
    end)
  end
  
  -- Run current stage
  stage(context, input, next_stage, stage_num)
  completed = true
  
  -- If no async operations pending, complete immediately
  if pending == 0 and on_complete then
    on_complete()
  end
end

-- Usage with plenary async
local async = require('plenary.async')

async.run(function()
  local done = false
  pipeline.run(stages, context, vim.fn.getcwd(), 1, function()
    done = true
  end)
  
  -- Wait for completion
  vim.wait(10000, function() return done end)
end)
```
*Pros*:
- True streaming: results flow immediately to next stage
- Works well with async (uses callbacks + vim.schedule)
- No buffering: memory efficient for large result sets
- Stages can produce results at their own pace
- Backpressure: consumer controls via synchronous next_stage calls

*Cons*:
- Complex to track completion (need pending counter)
- Order not guaranteed if async operations complete out of order
- Error handling tricky (which result failed?)
- Callback-based (but manageable)

**Streaming with Async/Await Wrapper:**
```lua
-- Wrap streaming in async-friendly API
function pipeline.run_streaming(stages, context, input)
  return async.run(function()
    local results = {}
    local result_available = async.control.Condvar.new()
    
    local function collect_result(ctx, output)
      table.insert(results, output)
      result_available:notify()
    end
    
    -- Run pipeline with collector
    pipeline.run(stages, context, input, 1, function()
      result_available:notify()  -- Signal completion
    end)
    
    -- Consumer can process results as they arrive
    local processed = 0
    while true do
      while processed < #results do
        processed = processed + 1
        coroutine.yield(results[processed])
      end
      
      if pipeline.is_complete() then break end
      result_available:wait()
    end
  end)
end

-- Usage: process results as they stream in
for result in pipeline.run_streaming(stages, ctx, path) do
  print("Got:", result)
end
```
*Pros*: Best of both worlds - streaming internally, async/await externally
*Cons*: Complex implementation, requires Condvar or similar

**Recommendation**: Option F (Streaming with Repeated Calls) for the implementation. It provides true streaming without buffering, works with plenary async, and allows stages to chain without waiting. Use callbacks for completion tracking, or wrap in async iterators for consumer convenience.

---

## 4. Error Handling Strategy

**Problem**: What happens when a stage fails? How do errors propagate?

### Options

**A. Fail Fast (Default)**
```lua
function pipeline.run(stages, ctx, input)
  for _, stage in ipairs(stages) do
    local ok, result = pcall(stage, ctx, input)
    if not ok then
      error(string.format("Stage failed: %s", result))
    end
    input = result
  end
end
```
*Pros*: Simple, errors don't compound
*Cons*: One bad config breaks everything

**B. Collect and Continue**
```lua
function pipeline.run(stages, ctx, input)
  local errors = {}
  for _, stage in ipairs(stages) do
    local ok, result = pcall(stage, ctx, input)
    if ok then
      input = result
    else
      table.insert(errors, result)
      -- Continue with unchanged input or skip stage
    end
  end
  return input, errors
end
```
*Pros*: Resilient, partial success possible
*Cons*: Silent failures, unclear final state

**C. Stage-configurable**
```lua
stages = {
  {
    fn = walk_stage,
    on_error = "fail"  -- or "continue", "skip", function(err)
  }
}
```
*Pros*: Flexible per-stage behavior
*Cons*: Complex configuration

**D. Error boundary stages**
```lua
function with_error_handling(stage, handler)
  return function(ctx, input)
    local ok, result = pcall(stage, ctx, input)
    if not ok then
      return handler(ctx, input, result)
    end
    return result
  end
end
```
*Pros*: Composable, explicit
*Cons*: Verbose wrapping

**Recommendation**: Option A for file loading (critical path), Option B for file execution (some configs may fail).

---

## 5. JSON Write Target

**Problem**: When code calls `json.set(key, value)`, which file gets written?

### Options

**A. Project Root Only**
```lua
-- Always writes to config_dir/project_name.json
json.set("key", "value")  -- writes to projects/my-project.json
```
*Pros*: Predictable, single source of truth
*Cons*: Can't write to nested configs

**B. Most Specific Match**
```lua
-- Writes to deepest matching config file
-- If projects/myrepo/package.json exists, write there
-- Else write to projects/myrepo-package.json
```
*Pros*: Respects existing structure
*Cons*: Ambiguous if multiple files match

**C. Explicit Target**
```lua
json.set("key", "value", {target = "nested"})  -- Specify which config
```
*Pros*: Explicit control
*Cons*: API more complex

**D. Write to New File**
```lua
-- Always create project_name.json if not exists
-- Never modify existing nested configs
```
*Pros*: Non-destructive
*Cons*: Pollution if many nested configs

**E. Registry Pattern**
```lua
-- Register writable config files
json.register_writable("projects/my-project.json")
json.register_writable("projects/myrepo/package.json")

-- Write goes to first registered writable
json.set("key", "value")
```
*Pros*: Configurable, explicit
*Cons*: Requires registration

**Recommendation**: Option A (project root only) for MVP. Option E if multiple write targets needed later.

---

## 6. Cache Invalidation Granularity

**Problem**: How fine-grained should cache invalidation be? Check every file or batch checks?

### Options

**A. Global Timestamp**
```lua
-- Single mtime check for entire cache
if now - cache.last_check > interval then
  cache:invalidate_all()
end
```
*Pros*: Fast, simple
*Cons*: Over-invalidation, unnecessary reloads

**B. Per-Entry Check**
```lua
-- Check each cached item individually
for path, entry in pairs(cache) do
  local stat = vim.loop.fs_stat(path)
  if stat.mtime.sec > entry.mtime then
    cache[path] = nil
  end
end
```
*Pros*: Precise, minimal reloading
*Cons*: Expensive if many files cached

**C. Directory-level (Current Design)**
```lua
-- Directory cache: global check
-- File cache: per-entry check within directory
```
*Pros*: Balanced approach
*Cons*: Two different strategies

**D. Lazy Checking**
```lua
-- Don't check until file accessed
function cache.get(path)
  local entry = raw_cache[path]
  if entry then
    local stat = vim.loop.fs_stat(path)
    if stat.mtime.sec > entry.mtime then
      return nil  -- Force reload
    end
  end
  return entry
end
```
*Pros*: Check only what's needed
*Cons*: First access after change is slow

**E. Watch-based (inotify/fs_event)**
```lua
-- Use vim.loop.fs_event to watch files
-- Invalidate immediately on change
```
*Pros*: Instant invalidation, no polling
*Cons*: Platform differences, resource limits

**Recommendation**: Option C (directory global, file per-entry) with Option E as future enhancement.

---

## 7. Stage Concurrency Model

**Problem**: Should stages be able to process multiple items concurrently? What's the execution model?

### Options

**A. Sequential (Current)**
```lua
-- One item at a time through pipeline
for item in items do
  stage1(ctx, item)
  stage2(ctx, item)
  stage3(ctx, item)
end
```
*Pros*: Predictable, no race conditions
*Cons*: Slow for many items

**B. Stage-level Parallelism**
```lua
-- Stage processes all items in parallel
async.run(function()
  local tasks = {}
  for _, item in ipairs(items) do
    table.insert(tasks, async.wrap(stage, item))
  end
  await_all(tasks)
end)
```
*Pros*: Faster for independent items
*Cons*: Race conditions on shared context

**C. Pipeline Parallelism**
```lua
-- Items flow through stages like assembly line
-- Stage 2 can process item 1 while Stage 1 processes item 2
```
*Pros*: Maximum throughput
*Cons*: Complex buffering, memory overhead

**D. Configurable per-Stage**
```lua
stages = {
  { fn = walk_stage, parallel = false },
  { fn = find_files_stage, parallel = true },
}
```
*Pros*: Optimal for each stage
*Cons*: Complexity

**Recommendation**: Option A (sequential) for correctness, revisit if performance issues arise.

---

## 8. Context Mutability Boundaries

**Problem**: Context is mutable, but what should stages be allowed to modify?

### Options

**A. Free Mutation**
```lua
-- Stages can modify anything in context
context.project_root = "/new/path"
context.custom_data = {foo = "bar"}
```
*Pros*: Flexible
*Cons*: Hard to debug, unintended side effects

**B. Namespaced by Stage**
```lua
-- Each stage gets its own namespace
context.stages.walk.directories = {...}
context.stages.detect_root.root = "/path"
```
*Pros*: Isolation, clear ownership
*Cons*: Verbose, rigid

**C. Explicit API**
```lua
-- Context provides setter methods
context:set_project_root("/path")
context:set_json_data({...})
```
*Pros*: Validation, hooks, controlled access
*Cons*: More code, less flexible

**D. Immutable Snapshots**
```lua
-- Context is frozen, stages return new context
function stage(ctx, input)
  local new_ctx = vim.deepcopy(ctx)
  new_ctx.project_root = "/path"
  return new_ctx, output
end
```
*Pros*: Pure functions, time-travel debugging
*Cons*: Expensive copying, memory overhead

**Recommendation**: Option A with naming conventions (`_stage_` prefix for stage-specific data).

---

## 9. Matcher Performance

**Problem**: Matchers may be called frequently (every directory in walk). How to optimize?

### Options

**A. Compile Once**
```lua
-- Compile matchers at setup time
local compiled = compile_matcher(config.matcher)

function walk(ctx, dir)
  if compiled(dir) then
    -- Match
  end
end
```
*Pros*: Fast execution
*Cons*: Setup time overhead

**B. Cache Results**
```lua
-- Cache matcher results by path
local match_cache = {}

function matches(path)
  if match_cache[path] ~= nil then
    return match_cache[path]
  end
  local result = matcher(path)
  match_cache[path] = result
  return result
end
```
*Pros*: Avoids re-evaluating same paths
*Cons*: Memory usage, cache invalidation

**C. Lazy Evaluation**
```lua
-- Only evaluate matchers when needed
-- Skip if already have project_root
if not ctx.project_root then
  evaluate_matchers()
end
```
*Pros*: Minimal work
*Cons*: Conditional logic spread throughout

**D. Index-based**
```lua
-- Build index of known project roots
-- O(1) lookup instead of walking
local root_index = load_root_index()

function find_root(path)
  return root_index[path] or walk_and_find(path)
end
```
*Pros*: Fast for known projects
*Cons*: Index maintenance, stale data

**Recommendation**: Option A (compile at setup) + Option B (cache results).

---

## Summary of Recommendations

| Decision | Recommendation | Rationale |
|----------|---------------|-----------|
| Pipeline completion | Promise-based (Option B) | Fits Plenary async model |
| Clear strategy | Hardcoded list (Option A) | Simple, can extend later |
| Stage interface | Return values (Option B) | Pure functions, testable |
| Error handling | Context-dependent | Fail fast for load, continue for execute |
| JSON write target | Project root only (Option A) | Predictable MVP behavior |
| Cache invalidation | Hybrid (Option C) | Balanced performance/correctness |
| Concurrency | Sequential (Option A) | Correctness first |
| Context boundaries | Free mutation with conventions | Flexibility |
| Matcher performance | Compile + cache | Speed |

---

## Next Steps

1. Review and approve/discuss each decision
2. Identify which decisions block implementation start
3. Create implementation plan prioritizing core pipeline
4. Draft stage interfaces and contracts
5. Prototype with simple walk + detect_root stages