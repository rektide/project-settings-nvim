# Cache Design Review

This document reviews and synthesizes caching approaches across all nvim-project-config proposals.

## Overview

All proposals agree on caching **JSON configuration** in memory with **mtime-based validation**. The differences lie in:
- Flexibility of cache validation logic
- Cache scope (single vs. multi-project)
- Cache invalidation strategies
- Performance considerations
- User control over caching behavior

## What Each Proposal Says About Caching

### Opus (README.opus.md + DISCUSS.opus.md)

**Caching Features:**

1. **Explicit configuration caching**
   ```lua
   executor = {
     execute = nil,  -- uses default composite executor
     json = {
       check_mtime = true,      -- Check mtime before reads/writes
       assume_dirty = true,      -- Fallback if mtime detection fails
     },
   }
   cache_detection = true,  -- Cache project detection per directory
   ```

2. **Four cache types identified** (DISCUSS.opus.md):

   | Cache Type | Key | Invalidated By |
   |------------|-----|----------------|
   | Project detection | directory path | `:NvimProjectConfigReload`? |
   | Found files | project name + config_dir | ??? |
   | JSON data | file path | mtime change |
   | Executed state | ??? | ??? |

3. **JSON executor behavior:**
   - Maintains in-memory cache
   - Checks file mtime before every read/write
   - Falls back to `assume_dirty = true` if mtime detection fails
   - Prevents stale data while handling filesystem limitations

4. **Validation questions** (DISCUSS.opus.md):
   - When should detection cache invalidate?
   - Should we watch the config directory for new files?
   - If `rad.lua` is deleted, should we un-apply its effects? (Notes: "Probably impossible")

**Strengths:**
- Clear separation of cache types
- Graceful degradation when mtime fails
- Explicit `cache_detection` toggle for debugging
- Identifies what needs caching vs. what doesn't

**Weaknesses:**
- No custom cache validation logic
- Cache invalidation for non-JSON caches is undefined
- No explicit API for cache management

---

### GLM (README.glm.md + DISCUSS.glm.md)

**Caching Features:**

1. **Simple cache enable/disable**
   ```lua
   json = {
     cache = {
       enabled = true,
       -- Graceful degradation: if mtime check fails, assumes dirty cache
     }
   }
   ```

2. **Graceful degradation:**
   - If mtime check fails, assumes dirty cache
   - Always reloads from disk in this case
   - Write operations update cache atomically

3. **Important questions raised** (DISCUSS.glm.md):

   **Question 14 (Dirty cache behavior):**
   - When `os.time()` precision is too coarse (or mtime fails entirely):
     - Always reload on read?
     - Always reload on write?
     - Both?
     - Expose a `force_reload` flag?

   **Question 45 (Memory footprint):**
   - JSON configs get cached. What's the expected size?
   - Do we need bounds or eviction?
   - What if someone configures 50 projects with large JSON files?

4. **No custom validation** - standard mtime check only

**Strengths:**
- Simple, easy to understand
- Graceful degradation handled
- Raises important questions about memory management

**Weaknesses:**
- No custom cache validation
- No eviction strategy discussed
- No explicit cache management API

---

### K25 (README-k25.md + DISCUSS.k25.md)

**Caching Features:**

1. **Configurable cache settings**
   ```lua
   executor = {
     executors = {
       json = {
         cache = {
           enabled = true,
           -- Check mtime before every read/write
           check_mtime = true,
           -- If mtime check fails (e.g., fs issues), assume dirty
           fallback_dirty = true,
         },
       }
     }
   }
   ```

2. **Fallback strategy:**
   - If mtime check fails: treat as dirty, reload every time
   - Prevents serving stale data

3. **Questions raised** (DISCUSS.k25.md):

   **Question 759:**
   - JSON cache eviction?
   - How to handle memory pressure?

**Strengths:**
- Clean configuration
- Clear fallback strategy
- Naming is explicit (`fallback_dirty`)

**Weaknesses:**
- No custom validation
- Eviction not designed
- No cache management API

---

### K2T (README.k2t.md + DISCUSS.k2t.md)

**Caching Features:**

1. **Custom cache validation function** - **MOST FLEXIBLE**
   ```lua
   executors = {
     json = {
       cache = {
         enabled = true,
         -- Check mtime before using cache
         check_mtime = true,
         -- If mtime check fails (e.g., fs issues), assume dirty
         fallback_dirty = true,
         -- UNIQUE: Custom validation function!
         validate_cache = function(file_path, cached_data)
           local stat = vim.loop.fs_stat(file_path)
           if not stat then return false end
           return cached_data._mtime == stat.mtime.sec
         end,
       },
       -- Access pattern: project_config.json.get('key.path')
       -- Writing: project_config.json.set('key.path', value)
       accessor = 'project_config.json',
     }
   }
   ```

2. **Configurable validation modes:**
   - `validate_cache = true` - Use default mtime check
   - `validate_cache = false` - Disable caching
   - `validate_cache = function` - Custom validation logic

3. **Explicit cache management API:**
   ```lua
   -- From README.k2t.md
   require('nvim-project-config').clear_cache()  -- Clear all caches
   ```

4. **Advanced caching considerations** (DISCUSS.k2t.md):

   **Question 5: Cache Invalidation Beyond JSON**

   Currently only JSON executor has mtime-based cache validation.

   **Expansion possibilities:**
   - Should lua/vim executors cache compiled chunks?
   - Cache directory listings for finder performance?
   - TTL-based eviction for memory-constrained environments?
   - Explicit cache API for users: `require(...).clear_cache('project-name')`
   - Should cache be project-specific or global?

5. **File structure supports caching:**
   ```
   executor/
     ├── cache.lua       # Cache management with validation
     └── json.lua        # JSON settings with cache
   ```

**Strengths:**
- **Most flexible** - custom validation function
- **Explicit cache API** - users can clear caches
- **Considers expansion** - caching beyond JSON, TTL eviction
- **Asks right questions** - project-specific vs. global cache
- **Test runner example** - shows extensibility

**Weaknesses:**
- More complex than others (though justified by flexibility)

---

### Opus2 (README-opus2.md)

**Caching Features:**

1. **Minimal caching discussion** - mentions but doesn't elaborate

2. **Programmatic JSON API** with implied caching:
   ```lua
   -- Read JSON config
   local settings = npc.get_json_config("rad-project")

   -- Read a nested value
   local servers = settings.lsp.servers

   -- Write a value (persists to disk)
   npc.set_json_config("rad-project", "lastOpenedFile", vim.fn.expand("%"))

   -- Modify existing values with a function
   npc.set_json_config("rad-project", "lsp.servers", function(servers)
     table.insert(servers, "tailwindcss")
     return servers
   end)
   ```

3. **Implied caching**:
   - "The JSON executor caches files in memory and checks modification time before each access"
   - "If the file changed on disk, it reloads automatically"
   - "If mtime tracking fails on your filesystem, it falls back to reloading on every access"

**Strengths:**
- Pragmatic, implementation-ready
- Clear programmatic API

**Weaknesses:**
- Least detailed about caching design
- No configuration options shown for caching
- No cache management API

---

## Comparison Summary

### Cache Flexibility

| Proposal | Validation | Custom Validation | Config Modes | Cache API |
|----------|-------------|-------------------|---------------|------------|
| Opus | mtime only | ❌ No | `check_mtime`, `assume_dirty` | ❌ No |
| GLM | mtime only | ❌ No | `cache.enabled` | ❌ No |
| K25 | mtime only | ❌ No | `enabled`, `check_mtime`, `fallback_dirty` | ❌ No |
| **K2T** | **mtime + custom function** | ✅ **Yes** | **`enabled`, `check_mtime`, `fallback_dirty`, `validate_cache`** | ✅ **`clear_cache()`** |
| Opus2 | mtime only | ❌ No | Implied, not configurable | ❌ No |

### Cache Scope

All proposals cache **per-project JSON**:

```lua
cache["my-project"] = {
  json_data = { ... },
  _mtime = 1234567890,
  _file_path = "/home/user/.config/nvim/projects/my-project.json"
}
```

**Open question from K2T (DISCUSS.k2t.md Question 5):**
> Should cache be project-specific or global?

Implication: Could be:
- `cache["my-project"]` (project-specific)
- `cache = { "my-project": {...}, "other-project": {...} }` (global multi-project cache)

### Cache Invalidation Strategies

| Strategy | Opus | GLM | K25 | K2T | Opus2 |
|----------|-------|-----|------|-----|--------|
| mtime check | ✅ | ✅ | ✅ | ✅ | ✅ |
| Fallback dirty | ✅ | ✅ | ✅ | ✅ | ✅ |
| Custom validation | ❌ | ❌ | ❌ | ✅ | ❌ |
| TTL-based eviction | ❌ | ❓ | ❓ | ❓ | ❌ |
| Manual clear | ❌ | ❌ | ❌ | ✅ | ❌ |
| Directory watching | ❓ | ❓ | ❓ | ❓ | ❌ |

✅ = Implemented
❌ = Not discussed/implied not supported
❓ = Questioned but not designed
❓ = Questioned but not designed

### Cache Management APIs

| API | Opus | GLM | K25 | **K2T** | Opus2 |
|-----|-------|-----|------|------|--------|
| `clear_cache()` | ❌ | ❌ | ❌ | ✅ | ❌ |
| `clear_cache('project')` | ❌ | ❌ | ❌ | ❓ | ❌ |
| `cache_enabled = false` | ✅ | ✅ | ✅ | ✅ | ❌ |
| `force_reload` flag | ❓ | ❓ | ❌ | ❌ | ❌ |

---

## Technical Analysis

### Mtime-Based Caching

**All proposals use mtime (modification time) for cache validation.**

**Why mtime?**
- Fast: Single `stat()` syscall
- Reliable: Filesystem updates mtime on write
- Simple: No content hashing needed

**Problems with mtime:**

1. **Precision issues** (GLM DISCUSS.glm.md Question 14):
   - Some filesystems have coarse `os.time()` precision (1 second)
   - Multiple writes within same second = same mtime
   - Can't detect rapid successive changes

2. **Filesystem limitations**:
   - Network filesystems may have sync delays
   - Some filesystems don't support mtime
   - mtime may not propagate immediately

3. **External changes**:
   - File changed by external editor (not Neovim)
   - mtime may not update immediately
   - Could serve stale data

**Mitigation across all proposals:**
- **Fallback dirty**: If mtime check fails, assume cache is dirty
- **Reload on access**: Always reload when in doubt

### Custom Cache Validation (K2T Only)

**K2T's `validate_cache` function is unique:**

```lua
validate_cache = function(file_path, cached_data)
  local stat = vim.loop.fs_stat(file_path)
  if not stat then return false end

  -- Default mtime check
  if cached_data._mtime ~= stat.mtime.sec then
    return false
  end

  -- CUSTOM: Could add hash validation
  local content = vim.fn.readfile(file_path)
  local hash = vim.fn.sha256(content)
  return cached_data._hash == hash
end
```

**What this enables:**

1. **Hash-based validation**:
   ```lua
   validate_cache = function(file_path, cached_data)
     local content = read_file(file_path)
     local hash = sha256(content)
     return cached_data._hash == hash
   end
   ```
   - More reliable than mtime
   - Detects content changes even if mtime unchanged
   - Performance cost: read file + hash computation

2. **Multi-source validation**:
   ```lua
   validate_cache = function(file_path, cached_data)
     -- Check mtime
     local stat = vim.loop.fs_stat(file_path)
     if cached_data._mtime ~= stat.mtime.sec then
       return false
     end

     -- Also check related files
     local deps = cached_data._dependencies or {}
     for _, dep in ipairs(deps) do
       local dep_stat = vim.loop.fs_stat(dep)
       if dep_stat and dep_stat.mtime.sec > cached_data._mtime then
         return false
       end
     end

     return true
   end
   ```

3. **Custom TTL logic**:
   ```lua
   validate_cache = function(file_path, cached_data)
     local stat = vim.loop.fs_stat(file_path)

     -- Invalidate if mtime changed
     if cached_data._mtime ~= stat.mtime.sec then
       return false
     end

     -- Also invalidate if older than TTL
     local age = os.time() - cached_data._loaded_at
     if age > (cached_data._ttl or 3600) then  -- 1 hour default
       return false
     end

     return true
   end
   ```

4. **Remote file checks**:
   ```lua
   validate_cache = function(file_path, cached_data)
     -- Local mtime check
     local stat = vim.loop.fs_stat(file_path)
     if cached_data._mtime ~= stat.mtime.sec then
       return false
     end

     -- Remote sync check (for distributed configs)
     local remote_mtime = check_remote_version(file_path)
     if remote_mtime > cached_data._mtime then
       return false
     end

     return true
   end
   ```

**Why this wins:** Ultimate flexibility for advanced use cases without complicating simple cases.

---

## Cache Scope: Single vs. Multi-Project

### Current Consensus: Per-Project Cache

All proposals cache **one project's JSON at a time**:

```lua
cache = {
  ["current-project"] = {
    json_data = { lsp = { ... }, settings = { ... } },
    _mtime = 1234567890,
    _file_path = "/home/user/.config/nvim/projects/current-project.json"
  }
}
```

**This works for:**
- Single-project workflows
- Switching between projects (replace cache content)
- Simple mental model

**This doesn't support:**
- Simultaneous access to multiple project configs
- Monorepo patterns (root + package configs)
- Cross-project configuration inheritance

### Multi-Project Cache Design (Discussed but Not Implemented)

**Opus DISCUSS.opus.md (Question 1.9)** hints at multi-project context:

```lua
ctx.projects = {
  repo = "monorepo",
  package = "auth"
}
```

**K2T DISCUSS.k2t.md (Question 5)** asks:
> Should cache be project-specific or global?

**Multi-project cache would look like:**

```lua
cache = {
  ["monorepo"] = {
    json_data = { root_settings = { ... } },
    _mtime = 1234567890,
    _file_path = "/home/user/.config/nvim/projects/monorepo.json"
  },
  ["auth"] = {
    json_data = { package_settings = { ... } },
    _mtime = 1234567891,
    _file_path = "/home/user/.config/nvim/projects/auth.json"
  },
  ["monorepo-auth"] = {  -- Combined config
    json_data = { merged = { ... } },
    _mtime = 1234567892,
  }
}
```

**API for multi-project access:**

```lua
-- Access specific project's cache
npc.json("monorepo"):get("root_setting")
npc.json("auth"):get("package_setting")

-- Get all cached projects
local projects = npc.cached_projects()  -- { "monorepo", "auth" }

-- Clear specific project cache
npc.clear_cache("auth")
```

---

## Memory Management

### Concerns Raised

**GLM DISCUSS.glm.md (Question 45):**
> JSON configs get cached. What's the expected size?
> - Do we need bounds or eviction?
> - What if someone configures 50 projects with large JSON files?

**K2T DISCUSS.k2t.md (Question 5):**
> TTL-based eviction for memory-constrained environments?
> Explicit cache API for users: `require(...).clear_cache('project-name')`

### Eviction Strategies

| Strategy | Implementation | When to Use |
|----------|----------------|--------------|
| **TTL-based** | Remove cache entries older than X seconds | Memory-constrained environments, long-running sessions |
| **LRU** | Remove least-recently-used when cache is full | Many projects, limited memory |
| **Manual** | `clear_cache()` or `clear_cache('project')` | User-controlled cleanup |
| **Watch-based** | Unload cache for projects not used recently | Automatic memory management |
| **None (default)** | Keep all loaded project configs | Simple, may cause memory issues |

### Recommendation: Hybrid Approach

```lua
cache = {
  -- Per-project cache data
  projects = { },

  -- Cache management
  config = {
    max_size_mb = 10,          -- Soft limit
    ttl_seconds = 3600,         -- 1 hour TTL per project
    max_projects = 50,          -- Hard limit
    eviction_policy = "ttl",      -- "ttl", "lru", or "manual"
  }
}

-- When loading a project:
function load_project_cache(project_name)
  -- Check if already cached
  local cached = cache.projects[project_name]
  if cached and not cache_is_stale(cached) then
    return cached.json_data
  end

  -- Load from disk
  local json_data = load_json_file(project_name)

  -- Store in cache
  cache.projects[project_name] = {
    json_data = json_data,
    _mtime = get_mtime(project_name),
    _loaded_at = os.time(),
  }

  -- Apply eviction if needed
  apply_eviction_policy()

  return json_data
end

function cache_is_stale(cached)
  -- TTL check
  if config.ttl_seconds then
    local age = os.time() - cached._loaded_at
    if age > config.ttl_seconds then
      return true
    end
  end

  -- Mtime check
  local current_mtime = get_mtime(cached._file_path)
  if current_mtime ~= cached._mtime then
    return true
  end

  return false
end

function apply_eviction_policy()
  if config.eviction_policy == "ttl" then
    -- Remove entries older than TTL
    for name, data in pairs(cache.projects) do
      local age = os.time() - data._loaded_at
      if age > config.ttl_seconds then
        cache.projects[name] = nil
      end
    end

  elseif config.eviction_policy == "lru" then
    -- Remove least recently used when at limit
    local sorted = sort_by_last_access(cache.projects)
    while #sorted > config.max_projects do
      local to_remove = table.remove(sorted, 1)
      cache.projects[to_remove.name] = nil
    end
  end
end
```

---

## Cache Beyond JSON

### Question: What Else Should Be Cached?

**K2T DISCUSS.k2t.md (Question 5) asks:**

1. **Should lua/vim executors cache compiled chunks?**
   - Lua: `loadfile()` vs. `dofile()` - does Lua cache compiled bytecode?
   - Vim: `vim.cmd.source()` - does Vim cache?
   - Benefit: Faster reload, but may mask file changes

2. **Should we cache directory listings for finder performance?**
   - Directory walking calls `scandir()` multiple times
   - Cache could prevent repeated scans
   - Trade-off: Memory vs. I/O

3. **Should we cache project detection results?**
   - **Opus**: `cache_detection = true` caches per directory
   - Benefit: Avoid re-walking directory tree
   - Invalidates on `:NvimProjectConfigReload` or directory change

### Recommendation: Multi-Layer Caching

```lua
cache = {
  -- Layer 1: Project detection (directory → project name)
  detection = {
    ["/home/user/src/my-project"] = {
      project_name = "my-project",
      project_root = "/home/user/src/my-project",
      _cached_at = 1234567890,
    }
  },

  -- Layer 2: File discovery (project name + config_dir → file list)
  files = {
    ["my-project+/home/user/.config/nvim/projects"] = {
      files = { "/home/user/.config/nvim/projects/my-project.lua", ... },
      _cached_at = 1234567891,
    }
  },

  -- Layer 3: JSON data (file path → parsed data)
  json = {
    ["/home/user/.config/nvim/projects/my-project.json"] = {
      json_data = { ... },
      _mtime = 1234567892,
    }
  },

  -- Layer 4: Execution state (what files executed, when)
  executed = {
    ["my-project"] = {
      files = { "my-project.lua", "my-project.json" },
      executed_at = 1234567893,
    }
  }
}
```

**Cache invalidation strategy:**

| Cache Layer | Invalidated By | TTL? |
|-----------|---------------|------|
| Detection | Directory change, explicit reload | Yes (30 minutes) |
| Files | Config directory change, file addition/deletion | Yes (5 minutes) |
| JSON | mtime change, explicit clear | Yes (1 hour, or mtime) |
| Executed | Reload, explicit clear | No |

---

## Recommended Cache Architecture

### Core Design

```lua
local M = {}

-- Cache storage
M._cache = {
  projects = {},        -- project_name → cache data
  files = {},           -- file_path → cache data
  detection = {},       -- directory_path → project_name
}

-- Cache configuration
M._config = {
  json = {
    enabled = true,
    check_mtime = true,
    fallback_dirty = true,
    validate_cache = nil,  -- Custom validation function
  },
  detection = {
    enabled = true,
    ttl_seconds = 1800,  -- 30 minutes
  },
  files = {
    enabled = true,
    ttl_seconds = 300,    -- 5 minutes
  },
  eviction = {
    policy = "ttl",        -- "ttl", "lru", "manual"
    max_projects = 50,
    max_size_mb = 10,
  }
}

-- Public API for JSON cache
function M.get_json(project_name)
  return M._project_cache(project_name, "json")
end

function M.set_json(project_name, key_path, value)
  M._ensure_project_cache(project_name, "json")
  -- ... implementation
end

-- Cache management
function M.clear_cache(project_name)
  if project_name then
    M._cache.projects[project_name] = nil
  else
    M._cache.projects = {}
  end
end

function M.clear_all()
  M._cache = {
    projects = {},
    files = {},
    detection = {},
  }
end

function M.invalidate_project(project_name)
  -- Mark as dirty, reload on next access
  local cached = M._cache.projects[project_name]
  if cached then
    cached._dirty = true
  end
end

-- Internal: get or create project cache
function M._project_cache(project_name, cache_type)
  local cached = M._cache.projects[project_name]

  -- Check if cache exists and valid
  if cached and not M._is_stale(cached) then
    return cached.data[cache_type]
  end

  -- Load from disk
  local data = M._load_from_disk(project_name, cache_type)

  -- Store in cache
  if not cached then
    cached = {
      data = {},
      _loaded_at = os.time(),
    }
    M._cache.projects[project_name] = cached
  end

  cached.data[cache_type] = data
  cached._loaded_at = os.time()

  -- Apply eviction if needed
  M._apply_eviction()

  return data
end

-- Internal: check if cache is stale
function M._is_stale(cached)
  -- Check custom validation if configured
  if M._config.json.validate_cache then
    local valid = M._config.json.validate_cache(cached._file_path, cached)
    if not valid then
      return true
    end
  end

  -- Check dirty flag
  if cached._dirty then
    return true
  end

  -- Check TTL
  local age = os.time() - cached._loaded_at
  if age > (M._config[cache_type].ttl_seconds or 3600) then
    return true
  end

  -- Check mtime if configured
  if M._config.json.check_mtime then
    local current_mtime = M._get_mtime(cached._file_path)
    if current_mtime ~= cached._mtime then
      return true
    end
  end

  return false
end
```

### Features

1. **Flexible validation**
   - Default: mtime check
   - Optional: custom `validate_cache` function
   - Optional: TTL-based expiration

2. **Multi-project cache**
   - `cache.projects[project_name]` structure
   - Support for multiple simultaneous project configs

3. **Manual cache management**
   - `clear_cache(project_name)` - clear specific project
   - `clear_all()` - clear all caches
   - `invalidate_project(project_name)` - mark as dirty

4. **Eviction policies**
   - TTL-based: Remove old entries
   - LRU-based: Remove least recently used
   - Manual: User-controlled only

5. **Graceful degradation**
   - If mtime fails, assume dirty
   - If custom validation fails, fall back to reload
   - If cache errors, disable caching temporarily

---

## Summary

### Best Cache Design: K2T

**Why:**
- Most flexible with custom `validate_cache` function
- Explicit cache management API (`clear_cache()`)
- Considers advanced scenarios (TTL eviction, cache scope)
- Metatable-based extension pattern for power users

**Key features to adopt:**
1. Custom validation function
2. Explicit cache management API
3. Configurable TTL
4. Multi-project cache structure
5. Eviction policies (TTL, LRU, manual)

### What Others Got Right

**Opus:**
- Clear cache type separation (detection, files, JSON, executed)
- Explicit `cache_detection` toggle

**GLM:**
- Raises important memory management questions
- Graceful degradation design

**K25:**
- Clean, explicit naming (`fallback_dirty`)
- Consistent with mtime-first approach

**Opus2:**
- Pragmatic, implementation-ready
- Simple programmatic API

### Recommended Implementation

1. **Start with K2T's design**
   - Custom `validate_cache` function
   - `clear_cache()` API
   - Multi-project cache structure

2. **Add Opus's cache type separation**
   - Separate caches for detection, files, JSON, executed
   - Each with own TTL and invalidation logic

3. **Add GLM's memory management**
   - Configurable TTL
   - Eviction policies (TTL, LRU)
   - Max project limits

4. **Add K25's explicit configuration**
   - Clean naming
   - `fallback_dirty` flag
   - `check_mtime` boolean

5. **Keep Opus2's simplicity**
   - Programmatic API
   - Pragmatic implementation

### Configuration Interface

```lua
require('nvim-project-config').setup({
  executor = {
    json = {
      cache = {
        enabled = true,
        check_mtime = true,
        fallback_dirty = true,
        -- K2T's custom validation
        validate_cache = function(file_path, cached_data)
          -- Custom logic
          return true or false
        end,
      }
    }
  },

  cache = {
    detection = {
      enabled = true,
      ttl_seconds = 1800,  -- 30 minutes
    },
    eviction = {
      policy = "ttl",        -- "ttl", "lru", or "manual"
      max_projects = 50,
      max_size_mb = 10,
      ttl_seconds = 3600,   -- 1 hour default for JSON
    }
  }
})
```

### Public API

```lua
local npc = require('nvim-project-config')

-- JSON cache access
npc.get_json('project-name')
npc.set_json('project-name', 'key.path', value)

-- Cache management
npc.clear_cache('project-name')  -- Clear specific
npc.clear_cache()              -- Clear all
npc.cached_projects()           -- List cached projects

-- Cache status
npc.cache_stats()  -- { count, size_mb, stale_count }
```
