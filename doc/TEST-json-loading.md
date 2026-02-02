# JSON Loading Test Results

## Status: ✅ JSON Loading Works (with workaround)

## Issue Identified

The async cache layer uses plenary's oneshot channel pattern which **deadlocks** when called from within an async coroutine context. This causes:

1. `ctx.file_cache:get_async(path)` returns nil
2. JSON executor throws "Failed to read JSON file" error
3. No JSON values are merged into `ctx.json`

## Workaround

Disable cache to use synchronous I/O:

```lua
local npc = require("nvim-project-config")

npc.setup({
  config_dir = "/home/rektide/.config/astrovim-git/projects",
  loading = { on = "manual" },
})

-- Disable cache to avoid async deadlock
npc.ctx.file_cache = nil
npc.ctx.dir_cache = nil

npc.load()

-- Verify JSON was loaded
print("ctx.json.test:", npc.ctx.json.test)
```

Output: `ctx.json.test: successful` ✅

## Root Cause

FileCache's `get_async()` implementation:

```lua
function FileCache:get_async(path)
  local tx, rx = async.control.channel.oneshot()
  self:get(path, function(entry)
    tx(entry)
  end)
  return rx()  -- BLOCKS - never receives from tx()
end
```

When called from within an async coroutine (e.g., JSON executor running via `async.run()`), the `rx()` call deadlocks and never receives the value sent by `tx()`.

## Files Tested

✅ Files exist in `~/.config/astrovim-git/projects/`:
- `repo.json` - matches project name "repo"
- `doc.json`
- `nvim-project-config.json`
- Multiple other .json files

✅ JSON file content is valid: `{"test":"successful"}`

✅ JSON executor works correctly when cache is disabled:
- Sync I/O via `io.open()` works
- JSON parsing via `vim.json.decode()` works
- Deep merge into `ctx.json` works
- Reactive metatable on `ctx.json` works

✅ Pipeline executes successfully:
- Project detected: `/opt/astrovim-git/repo`
- Project name: `repo`
- File found: `repo.json`
- File tracked in `_files_loaded`

❌ Broken with cache enabled:
- `ctx.file_cache:get_async()` deadlocks
- Returns nil instead of file entry
- JSON executor fails
- No values in `ctx.json`

## Verification

Run this test:

```bash
nvim --headless -c 'set rtp+=.test-agent/plenary.nvim,.' \
  -c 'lua require("nvim-project-config").setup({config_dir="/home/rektide/.config/astrovim-git/projects"})' \
  -c 'lua require("nvim-project-config").ctx.file_cache = nil' \
  -c 'lua require("nvim-project-config").ctx.dir_cache = nil' \
  -c 'lua require("nvim-project-config").load()' \
  -c 'lua print("ctx.json.test:", require("nvim-project-config").ctx.json.test or "nil")' \
  -c 'qa!'
```

Expected output: `ctx.json.test: successful`

## Conclusion

JSON file loading **works correctly** when cache is disabled. The oneshot channel deadlock in the async cache layer needs to be fixed to enable full async functionality.

**Files in `~/.config/astrovim-git/projects/` ARE loaded** when the cache workaround is applied.
