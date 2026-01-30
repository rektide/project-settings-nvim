# Async Testing Challenges

## Problem Description

Testing async code with plenary.nvim and plenary.async has proven challenging due to:

### 1. Timeout Issues
- Tests hang indefinitely when using `async.run()` with callback-based APIs
- Simple tests with `done()` callbacks work fine (see `matchers_spec.lua`)
- Tests combining `async.run()` and `done()` timeout after 30 seconds

### 2. Async/Await Pattern Complexity
- `async.run()` starts a coroutine but doesn't block
- Callback-based APIs (like `FileCache:get()` with callback) don't integrate well with plenary's test harness
- `async.util.sleep()` doesn't help with callback completion

### 3. Oneshot Channel Pattern Testing
- `get_async()` uses `async.control.channel.oneshot()` to convert callbacks to async/await
- Tests need to verify this pattern works correctly
- Testing requires both callback-based and async-based variants

### 4. Test Harness Integration
- `require('plenary.test_harness').test_directory()` runs tests headless
- Individual file tests work: `require('plenary.test_harness').test_file('test/unit/matchers_spec.lua')`
- Directory tests hang when async operations are involved

### 5. Mocking and Cleanup
- File I/O operations need temp directories
- Async cleanup with `uv.fs_unlink()` and `uv.fs_rmdir()` is complex
- Callback-based cleanup doesn't integrate well with `after_each()`

## What Works

### Simple Callback Tests
```lua
it("reads file content and caches entry", function(done)
  local test_file = tmp_dir .. "/test.lua"
  write_file(test_file, "vim.opt.test = true")

  file_cache:get(test_file, function(entry)
    assert.is_not_nil(entry)
    assert.equals(test_file, entry.path)
    assert.equals("vim.opt.test = true", entry.content)
    assert.is_not_nil(entry.mtime)
    done()
  end)
end)
```

### Non-Async Tests
```lua
it("has _cache table", function()
  assert.is_not_nil(file_cache._cache)
  assert.equals("table", type(file_cache._cache))
end)
```

## What Doesn't Work (or times out)

### Async Run with Done
```lua
it("reads file with async/await", function(done)
  local test_file = tmp_dir .. "/test.lua"
  write_file(test_file, "vim.opt.test = true")

  async.run(function()
    local entry = file_cache:get_async(test_file)
    assert.is_not_nil(entry)
    assert.equals("vim.opt.test = true", entry.content)
    done()  -- This never gets called, test times out
  end)
end)
```

### Async Operations in before_each/after_each
```lua
before_each(function()
  tmp_dir = "/tmp/npc-test-" .. vim.loop.os_getpid()
  uv.fs_mkdir(tmp_dir, 493)  -- This may not complete before tests run
  file_cache = require("nvim-project-config.cache.file").new()
end)
```

## Root Causes

1. **Non-blocking async**: `async.run()` returns immediately, test completes before coroutine finishes
2. **No await mechanism**: Plenary's test harness doesn't wait for coroutines to complete
3. **Callback hell**: Mixing callback-based APIs with async/await is complex
4. **Test timing**: `done()` callback may fire before async operations complete

## Potential Solutions

### 1. Use plenary.async's testing utilities
```lua
a.it("async test", function()
  local entry = file_cache:get_async(test_file)
  assert.is_not_nil(entry)
end)
```
- Need to check if `a.it()` exists in plenary.nvim
- This is the "proper" way to write async tests

### 2. Wrap async.run() with promise-like behavior
```lua
local function await_async(fn)
  local done = false
  local result, err

  async.run(function()
    result, err = fn()
    done = true
  end)

  while not done do
    async.util.sleep(1)
  end

  if err then
    error(err)
  end
  return result
end
```

### 3. Use only callback-based APIs in tests
- Avoid `get_async()` and `write_async()`
- Test oneshot pattern indirectly through callback-based methods
- Less coverage of async pattern, but tests pass

### 4. Mock async operations
- Replace `plenary.async.uv` with synchronous mocks
- Test logic without real async I/O
- Doesn't test actual async behavior

## Current Approach

For now, focusing on:
1. **Non-async tests**: Cache structure, clear_all, invalidate, options
2. **Callback-based tests**: Test actual file/directory operations with `done()`
3. **Defer async testing**: Once non-async tests pass, investigate plenary's async test utilities

This gives us:
- Coverage of cache structure and management
- Coverage of file I/O through callback-based APIs
- Working test suite without timeouts

Missing:
- Direct testing of `get_async()` / `write_async()` methods
- Testing of oneshot channel pattern
- Testing of async/await behavior

## Next Steps

1. Complete non-async and callback-based tests for FileCache and DirectoryCache
2. Research plenary.nvim's async test utilities (check `ASYNC.md`)
3. Write proper async tests once pattern is understood
4. Consider integrating a test utility like `a.it()` if available
