# Testing Strategy

This document outlines the testing strategy for nvim-project-config, covering all components that need testing.

## Test Framework

Using **plenary.nvim** test harness, located in:
- `.test-agent/plenary.nvim/` - Local copy of plenary.nvim
- Test files in `test/unit/` directory

Run tests with:
```bash
nvim --headless -c "PlenaryBustedDirectory test/unit/"
```

## Current Test Coverage

### ✅ Completed Tests
- `test/unit/matchers_spec.lua` - Full coverage of matchers module
  - `process()` - matcher type conversion
  - `any()` - OR logic for multiple matchers
  - `all()` - AND logic for multiple matchers
  - `not_()` - negation
  - `literal()` - exact basename matching
  - `pattern()` - Lua pattern matching
  - `fn()` - function wrapper

## Test Coverage Needed

### High Priority (Core Functionality)

#### 1. Cache Layer Tests (`test/unit/cache/`)

**FileCache** (`lua/nvim-project-config/cache/file.lua`):
- ✅ `get_async()` - Read file with caching
- ✅ `write_async()` - Write file and update cache
- ✅ `invalidate()` - Remove file from cache
- ✅ `clear_all()` - Clear entire cache
- ⚠️ `get()` - Internal callback-based read
- ⚠️ `write()` - Internal callback-based write
- Test mtime-based cache invalidation
- Test trust_mtime option
- Test cache entry structure (path, content, mtime, json field)
- Test async oneshot channel pattern

**DirectoryCache** (`lua/nvim-project-config/cache/directory.lua`):
- ⚠️ `get()` - Read directory asynchronously
- ✅ `invalidate()` - Remove directory from cache
- ✅ `clear_all()` - Clear entire cache
- ⚠️ `_get_async()` - Internal async read
- ⚠️ `_read_directory()` - Directory listing
- Test mtime-based cache invalidation
- Test trust_mtime option
- Test cache entry structure (path, entries, mtime)

#### 2. Pipeline Tests (`test/unit/pipeline_spec.lua`)

**Pipeline Core** (`lua/nvim-project-config/pipeline.lua`):
- ⚠️ `run()` - Execute pipeline stages
- ⚠️ `stop()` - Stop running pipeline
- ⚠️ DONE sentinel handling
- ⚠️ Channel creation and cleanup
- ⚠️ Error handling in stages
- ⚠️ Stage completion tracking
- ⚠️ on_load callback timing

#### 3. Stage Tests (`test/unit/stages/`)

**Walk Stage** (`lua/nvim-project-config/stages/walk.lua`):
- ⚠️ Walk upward from start directory
- ⚠️ Stop at filesystem root
- ⚠️ Matcher filtering
- ⚠️ Direction option ("up" only currently)
- ⚠️ Handle non-directory input paths

**Detect Stage** (`lua/nvim-project-config/stages/detect.lua`):
- ⚠️ String matcher (file/directory existence check)
- ⚠️ Table matcher (OR logic with existence checks)
- ⚠️ Function matcher
- ⚠️ on_match callback invocation
- ⚠️ Nil matcher (always true)

**Find Files Stage** (`lua/nvim-project-config/stages/find_files.lua`):
- ⚠️ Find project-named config files
- ⚠️ Find files in subdirectories
- ⚠️ Extension filtering
- ⚠️ Extension priority sorting (JSON > Lua > Vim)
- ⚠️ Config directory resolution
- ⚠️ Directory cache integration
- ⚠️ Handle missing project_name

**Execute Stage** (`lua/nvim-project-config/stages/execute.lua`):
- ⚠️ Route files by extension
- ⚠️ Sync executor execution
- ⚠️ Async executor execution
- ⚠️ Executor option lookup (async flag)
- ⚠️ Error handling with on_error callback
- ⚠️ Track loaded files in ctx._files_loaded

#### 4. Executor Tests (`test/unit/executors/`)

**Lua Executor** (`lua/nvim-project-config/executors/lua.lua`):
- ⚠️ Execute Lua file with dofile
- ⚠️ Error handling (propagate errors)

**Vim Executor** (`lua/nvim-project-config/executors/vim.lua`):
- ⚠️ Execute Vim script with :source
- ⚠️ Error handling (propagate errors)

**JSON Executor** (`lua/nvim-project-config/executors/json.lua`):
- ⚠️ `write_json()` - Write ctx.json to file
- ⚠️ File matching by project name (basename)
- ⚠️ File matching by parent directory
- ⚠️ Parse JSON and merge into ctx.json
- ⚠️ Async file cache integration
- ⚠️ Reactive table write trigger

#### 5. Integration Tests (`test/integration/`)

**Full Pipeline Flow**:
- ⚠️ End-to-end config loading from test fixtures
- ⚠️ Multiple config files for same project
- ⚠️ Config files in subdirectories
- ⚠️ Error handling throughout pipeline
- ⚠️ Cache behavior across loads

### Medium Priority (Supporting Features)

#### 6. Watcher Tests (`test/unit/watchers_spec.lua`)

**Watchers** (`lua/nvim-project-config/watchers.lua`):
- ⚠️ `setup_watchers()` - Setup config_dir, buffer, cwd watchers
- ⚠️ `teardown_watchers()` - Clean up all watchers
- ⚠️ Debounce timer behavior
- ⚠️ Config directory fs_event watcher
- ⚠️ Buffer BufEnter autocmd
- ⚠️ DirChanged autocmd
- ⚠️ Config_dir function resolution

#### 7. Reactive Table Tests (`test/unit/reactive_spec.lua`)

**Reactive Table** (`lua/nvim-project-config/init.lua:make_reactive_table`):
- ⚠️ Get values via __index
- ⚠️ Set values via __newindex
- ⚠️ Trigger on_change callback on set
- ⚠️ Nested table reactivity
- ⚠️ __pairs iteration

#### 8. Main Module Tests (`test/unit/init_spec.lua`)

**Main Module** (`lua/nvim-project-config/init.lua`):
- ⚠️ `setup()` - Initialize context and watchers
- ⚠️ `load()` - Run pipeline with start_dir
- ⚠️ `clear()` - Stop pipeline and reset state
- ⚠️ `deep_merge()` - Config merging
- ⚠️ Default pipeline creation
- ⚠️ Config_dir function resolution
- ⚠️ Loading on "startup" vs "lazy"

### Low Priority (Edge Cases)

#### 9. Edge Case Tests

- ⚠️ Empty config directory
- ⚠️ Missing project root markers
- ⚠️ Invalid JSON files
- ⚠️ Lua/Vim files with syntax errors
- ⚠️ Concurrent pipeline runs
- ⚠️ Pipeline stop during execution
- ⚠️ File system errors during I/O
- ⚠️ Large config files
- ⚠️ Deep nested directory structures
- ⚠️ Project names with special characters

## Test Fixtures

Located in `test/fixture/`:

**Projects** (`test/fixture/projects/`):
- `fake-project.lua` - Simple Lua config
- `my-fake-package.lua` - Config matched by package.json
- Create additional fixtures for testing:
  - `fake-project.vim`
  - `fake-project.json`
  - `subdir/nested.lua`
  - `syntax-error.lua`
  - `invalid.json`

**Package Files** (`test/fixture/fake-project/`):
- `package.json` - For project name detection

## Test Utilities

Create `test/utils/helpers.lua`:

```lua
local M = {}

-- Create temporary directory with test files
function M.setup_test_fixtures(files)
  -- implementation
end

-- Cleanup temporary directory
function M.cleanup_test_fixtures(dir)
  -- implementation
end

-- Wait for async operations
function M.await(promise)
  -- implementation
end

-- Spy on function calls
function M.spy(fn)
  -- implementation
end

return M
```

## Mocking Strategy

Since this is a Neovim plugin, we need to mock:

1. **File System Operations** - Mock `plenary.async.uv` functions
2. **Vim Functions** - Mock `vim.fn.*`, `vim.cmd.*`, `vim.api.*`
3. **Async Operations** - Use plenary's built-in async test helpers
4. **File Cache/Directory Cache** - Use real implementations with temp files

## Running Tests

### Unit Tests
```bash
nvim --headless -c "PlenaryBustedDirectory test/unit/"
```

### Integration Tests
```bash
nvim --headless -c "PlenaryBustedDirectory test/integration/"
```

### Specific Test File
```bash
nvim --headless -c "PlenaryBustedFile test/unit/matchers_spec.lua"
```

### With Coverage (requires luacov)
```bash
LUACOV_CONFIG=test/.luacov nvim --headless -c "PlenaryBustedDirectory test/unit/"
luacov-report
```

## Test Organization

```
test/
├── unit/
│   ├── cache/
│   │   ├── file_spec.lua
│   │   └── directory_spec.lua
│   ├── stages/
│   │   ├── walk_spec.lua
│   │   ├── detect_spec.lua
│   │   ├── find_files_spec.lua
│   │   └── execute_spec.lua
│   ├── executors/
│   │   ├── lua_spec.lua
│   │   ├── vim_spec.lua
│   │   └── json_spec.lua
│   ├── pipeline_spec.lua
│   ├── watchers_spec.lua
│   ├── reactive_spec.lua
│   ├── init_spec.lua
│   └── matchers_spec.lua (existing)
├── integration/
│   ├── full_pipeline_spec.lua
│   └── async_io_spec.lua
├── fixture/
│   ├── projects/
│   └── fake-project/
└── utils/
    └── helpers.lua
```

## CI/CD Integration

Add GitHub Actions workflow (`.github/workflows/test.yml`):

```yaml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: rhysd/action-setup-vim@v1
        with:
          neovim: true
          version: stable
      - run: nvim --headless -c "PlenaryBustedDirectory test/unit/"
      - run: nvim --headless -c "PlenaryBustedDirectory test/integration/"
```

## TODO from README

From README TODO section:
- ✅ File/directory cache not fully integrated - NOW FIXED (async I/O implemented)
- ⚠️ Watchers not tested - See Watcher Tests section above
- ⚠️ commit tests - This document

## Priority Order

1. **High** - Cache tests (foundation for everything)
2. **High** - Stage tests (individual components)
3. **High** - Executor tests (execution logic)
4. **High** - Integration tests (end-to-end flow)
5. **Medium** - Pipeline tests (orchestration)
6. **Medium** - Watcher tests (optional feature)
7. **Medium** - Reactive table tests (JSON feature)
8. **Low** - Main module tests (mostly integration)
9. **Low** - Edge case tests (completeness)

## Key Testing Challenges

1. **Async/Await** - Use plenary's async test helpers
2. **File System** - Use temporary directories for isolation
3. **Vim State** - Mock vim functions to avoid side effects
4. **Channel Communication** - Test timing and synchronization
5. **Cache Invalidation** - Test with actual file modifications
6. **Error Propagation** - Test error paths through async layers
