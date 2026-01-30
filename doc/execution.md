# Execution Model

This document describes the execution model used in nvim-project-config, including async patterns and pipeline architecture.

## Pipeline Execution

The configuration pipeline processes files through a series of stages using channels. The execute stage routes config files to extension-specific executors.

### Execute Stage

Located in `lua/nvim-project-config/stages/execute.lua`, the execute stage:

1. Receives file paths from the input channel
2. Determines the file extension
3. Looks up the appropriate executor from the router
4. Checks if the executor should run asynchronously
5. Executes the file and handles errors

### Async Execution Support

Executors can be marked as async using the `executors` configuration:

```lua
executors = {
  lua = { async = false },
  vim = { async = false },
  json = { async = true },
}
```

When an executor is marked async:

- `async.run()` wraps the executor call
- The executor runs in a coroutine
- File I/O operations use libuv async APIs
- The main Neovim event loop remains unblocked

When an executor is sync:

- The executor runs directly
- May use blocking operations
- Simpler error handling

### Error Handling

Errors from executors are caught with `pcall`. If an error occurs and `ctx.on_error` is set, the error handler is called via `vim.schedule()` to ensure it runs safely in the main thread.

## Oneshot Channel Pattern

The oneshot channel pattern converts callback-based async operations into coroutine-friendly async/await style code using plenary.async.

### Concept

`async.control.channel.oneshot()` creates a one-time communication channel with two ends:

- **tx (transmitter)**: Sends a single value
- **rx (receiver)**: Receives the value (coroutine-blocking)

### Usage Example

```lua
local async = require("plenary.async")

function FileCache:get_async(path)
  local tx, rx = async.control.channel.oneshot()
  
  -- Call callback-based API
  self:get(path, function(entry)
    tx(entry)  -- Transmit result
  end)
  
  return rx()  -- Await result (coroutine blocks here)
end
```

### How It Works

1. `oneshot()` creates a channel that can transmit exactly one value
2. The callback API is invoked, receiving the transmitter `tx`
3. The callback transmits the result when ready
4. The coroutine `rx()` call blocks until the value arrives
5. The value is returned directly to the caller

### Benefits

- **No nesting**: Avoids callback hell with synchronous-looking code
- **Coroutine-friendly**: Works naturally with plenary.async coroutines
- **Type-safe**: Clear separation of transmission and reception
- **Single-use**: Prevents bugs from multiple transmissions

### Application in nvim-project-config

The FileCache provides async wrappers:

```lua
-- Read file asynchronously
local entry = file_cache:get_async(path)

-- Write file asynchronously
local success = file_cache:write_async(path, data)
```

These are used by executors that need to perform async I/O:

```lua
local function json_executor(ctx, path)
  local entry = ctx.file_cache:get_async(path)
  local data = vim.json.decode(entry.content)
  -- ... process data ...
  ctx.file_cache:write_async(path, {content = vim.json.encode(new_data)})
end
```

## Filesystem Operations

All filesystem operations use libuv async APIs via `plenary.async.uv`:

- `uv.fs_stat()` - Get file metadata
- `uv.fs_open()` - Open file descriptors
- `uv.fs_read()` / `uv.fs_write()` - Read/write data
- `uv.fs_close()` - Close file descriptors
- `uv.fs_opendir()` / `uv.fs_readdir()` / `uv.fs_closedir()` - Directory operations

These operations never block the Neovim event loop when run in coroutines via `async.run()`.

## Cache Architecture

### FileCache

Stores file content with modification time tracking:

- `get_async(path)` - Read file with caching
- `write_async(path, data)` - Write file and update cache
- `invalidate(path)` - Remove file from cache
- `clear_all()` - Clear entire cache

Cache entries contain:
- `path` - File path
- `content` - File contents
- `mtime` - Modification time for invalidation
- `json` - Optional parsed JSON data

### DirectoryCache

Stores directory listings with modification time tracking:

- `get(path, callback)` - Read directory asynchronously
- `invalidate(path)` - Remove directory from cache
- `clear_all()` - Clear entire cache

## Performance Considerations

- Avoid `vim.schedule()` unless necessary - adds event loop tick overhead
- Use oneshot channels to convert callbacks to async/await style
- Prefer async I/O to avoid blocking Neovim
- Trust mtime by default for cache efficiency (configurable)
