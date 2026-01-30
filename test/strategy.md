# Testing Strategy

This document outlines the testing strategy for nvim-project-config, covering all components that need testing.

## Test Framework

Using **plenary.nvim** test harness, located in:
- `.test-agent/plenary.nvim/` - Local copy of plenary.nvim
- Test files in `test/unit/` directory

Run tests with:
```bash
npm test              # Unit tests
npm run test:integration  # Integration tests
npm run test:all         # All tests
```

## Current Test Coverage (As of latest commit)

### ✅ Completed Tests

**Total: 8 test files, ~60+ tests**

1. `test/unit/matchers_spec.lua` - 17 tests - ✅ ALL PASSING
   - `process()` - matcher type conversion
   - `any()` - OR logic for multiple matchers
   - `all()` - AND logic for multiple matchers
   - `not_()` - negation
   - `literal()` - exact basename matching
   - `pattern()` - Lua pattern matching
   - `fn()` - function wrapper

2. `test/unit/cache/file_spec.lua` - ✅ PASSING
   - Cache structure (_cache table, trust_mtime option)
   - `clear_all()` - Removes all cached entries
   - `invalidate()` - Removes specific entry from cache
   - Cache entry structure (path, content, mtime, json field)

3. `test/unit/cache/directory_spec.lua` - ✅ PASSING
   - Cache structure (_cache table, _trust_mtime option)
   - `clear_all()` - Removes all cached entries
   - `invalidate()` - Removes specific entry from cache
   - Cache entry structure (path, entries, mtime)

4. `test/unit/stages/walk_spec.lua` - 6 tests - ✅ ALL PASSING
   - Upward traversal from start directory
   - Stops at filesystem root
   - Matcher filtering (string and function)
   - Non-directory input handling
   - Pipeline stopped handling

5. `test/unit/stages/detect_spec.lua` - ~10 tests - ⚠️ PARTIAL (7/10 passing)
   - String matcher (file/directory existence check)
   - Table matcher (OR logic with existence checks)
   - Function matcher (⚠️ async timeout issues)
   - Nil matcher (⚠️ async timeout issues)
   - on_match callback (⚠️ async timeout issues)
   - Pipeline flow and DONE signal
   - Pipeline stopped handling

6. `test/unit/stages_and_executors_spec.lua` - 10 tests - ✅ ALL PASSING
   - Executor routing by extension
   - Executor options (async flag)
   - Lua executor function signature
   - Vim executor function signature
   - JSON executor (write_json, executor function)
   - Pipeline core (DONE, run, stop functions)

7. `test/unit/watchers_spec.lua` - 8 tests - ✅ ALL PASSING
   - setup_watchers() function
   - teardown_watchers() function
   - Watcher configuration handling
   - Debounce timer
   - Config_dir watcher (skip when disabled)
   - Buffer watcher (skip when disabled)
   - CWD watcher (skip when disabled)
   - Teardown cleanup

8. `test/integration/basic_spec.lua` - 12 tests - ✅ ALL PASSING
   - Main module loading (setup, load, clear functions)
   - Cache creation (FileCache, DirectoryCache)
   - JSON reactive table (set/get values)
   - Stage creation (walk, detect, find_files, execute)
   - Matchers module exports

## Test Coverage Needed

### High Priority (Core Functionality)

#### 1. Cache Layer Tests (PARTIALLY COMPLETE)

**FileCache** (`lua/nvim-project-config/cache/file.lua`):
- ✅ Structure tests
- ✅ clear_all()
- ✅ invalidate()
- ✅ trust_mtime option
- ✅ Cache entry structure
- ⚠️ `get()` - Internal callback-based read (async timeout issues)
- ⚠️ `write()` - Internal callback-based write (async timeout issues)
- ⚠️ `get_async()` - Async file read with oneshot channel
- ⚠️ `write_async()` - Async file write with oneshot channel
- ⚠️ Mtime-based cache invalidation tests

**DirectoryCache** (`lua/nvim-project-config/cache/directory.lua`):
- ✅ Structure tests
- ✅ clear_all()
- ✅ invalidate()
- ✅ trust_mtime option
- ✅ Cache entry structure
- ⚠️ `get()` - Callback-based read (async timeout issues)
- ⚠️ `_get_async()` - Internal async read (async timeout issues)
- ⚠️ `_read_directory()` - Directory listing (async timeout issues)
- ⚠️ Mtime-based cache invalidation tests

#### 2. Pipeline Tests (BASIC STRUCTURE COMPLETE)

**Pipeline Core** (`lua/nvim-project-config/pipeline.lua`):
- ✅ DONE sentinel
- ✅ run() function signature
- ✅ stop() function signature
- ⚠️ `run()` - Execute pipeline stages (needs integration test)
- ⚠️ `stop()` - Stop running pipeline (needs integration test)
- ⚠️ Channel creation and cleanup
- ⚠️ Error handling in stages
- ⚠️ Stage completion tracking
- ⚠️ on_load callback timing

#### 3. Stage Tests (WALK COMPLETE, DETECT PARTIAL)

**Walk Stage** - ✅ COMPLETE (6/6 passing)

**Detect Stage** - ⚠️ PARTIAL (7/10 passing)
  - String matcher ✅
  - Table matcher ✅
  - Function matcher ⚠️ (async timeout)
  - Nil matcher ⚠️ (async timeout)
  - on_match callback ⚠️ (async timeout)
  - Pipeline flow ✅
  - Pipeline stopped ✅

**Find Files Stage**:
- ⚠️ Find project-named config files
- ⚠️ Find files in subdirectories
- ⚠️ Extension filtering
- ⚠️ Extension priority sorting (JSON > Lua > Vim)
- ⚠️ Config directory resolution
- ⚠️ Directory cache integration
- ⚠️ Handle missing project_name

**Execute Stage**:
- ✅ Function signature tests
- ⚠️ Route files by extension (needs integration test)
- ⚠️ Sync executor execution
- ⚠️ Async executor execution
- ⚠️ Error handling with on_error callback
- ⚠️ Track loaded files in ctx._files_loaded

#### 4. Executor Tests (SIGNATURES COMPLETE)

**Lua Executor**:
- ✅ Function signature
- ⚠️ Execute Lua file with dofile
- ⚠️ Error handling

**Vim Executor**:
- ✅ Function signature
- ⚠️ Execute Vim script with :source
- ⚠️ Error handling

**JSON Executor**:
- ✅ write_json() function
- ✅ executor function
- ⚠️ Write ctx.json to file
- ⚠️ File matching by project name
- ⚠️ Parse JSON and merge
- ⚠️ Async file cache integration
- ⚠️ Reactive table write trigger

#### 5. Integration Tests (BASIC COMPLETE)

**Full Pipeline Flow**:
- ✅ Module loading
- ✅ Cache creation
- ✅ Stage creation
- ✅ Matchers exports
- ✅ JSON reactive table basic ops
- ⚠️ End-to-end config loading from test fixtures
- ⚠️ Multiple config files
- ⚠️ Config files in subdirectories
- ⚠️ Error handling throughout pipeline
- ⚠️ Cache behavior across loads

### Medium Priority (Supporting Features)

#### 6. Watcher Tests (COMPLETE ✅)

All 8 watcher tests passing - setup, teardown, configuration handling

#### 7. Reactive Table Tests (BASIC COMPLETE)

**Reactive Table** (`lua/nvim-project-config/init.lua:make_reactive_table`):
- ✅ Basic set/get operations
- ⚠️ Get values via __index
- ⚠️ Set values via __newindex
- ⚠️ Trigger on_change callback on set
- ⚠️ Nested table reactivity
- ⚠️ __pairs iteration

#### 8. Main Module Tests (BASIC COMPLETE)

**Main Module** (`lua/nvim-project-config/init.lua`):
- ✅ setup(), load(), clear() functions
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

## Key Testing Challenges

### Async Testing Issues

See `doc/DIFFICULTY-async-test.md` for detailed challenges:

1. **Timeout Issues** - Tests hang indefinitely with `async.run()`
2. **Async/Await Pattern Complexity** - Callback-based APIs don't integrate well
3. **Oneshot Channel Pattern** - Testing requires both callback and async variants
4. **Test Harness Integration** - `require('plenary.test_harness').test_directory()` hangs with async
5. **Mocking and Cleanup** - Async cleanup with `uv.fs_unlink()` is complex

**Current Approach:**
- Focus on non-async and callback-based tests
- Test structure and basic operations
- Defer full async testing until plenary async utilities are better understood

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

## Running Tests

```bash
# All unit tests
npm test

# All integration tests
npm run test:integration

# Specific test file
nvim --headless -c "set rtp+=.test-agent/plenary.nvim,." -c "lua require('plenary.test_harness').test_file('test/unit/matchers_spec.lua')" -c 'q!'
```

## TODO from README

From README TODO section:
- ✅ File/directory cache not fully integrated - NOW FIXED (async I/O implemented)
- ✅ Watchers not tested - NOW TESTED (8/8 passing)
- ✅ commit tests - NOW IN PROGRESS

## Priority Order

1. **High** - Cache tests (✅ COMPLETE, non-async)
2. **High** - Stage tests (✅ walk, ⚠️ detect partial)
3. **High** - Executor tests (✅ signatures, ⚠️ execution needs work)
4. **High** - Integration tests (✅ basic, ⚠️ end-to-end needs work)
5. **Medium** - Pipeline tests (✅ basic, ⚠️ execution needs work)
6. **Medium** - Watcher tests (✅ COMPLETE 8/8)
7. **Medium** - Reactive table tests (✅ basic, ⚠️ deep testing needed)
8. **Low** - Main module tests (✅ basic, ⚠️ execution needs work)
9. **Low** - Edge case tests (⚠️ NOT STARTED)
