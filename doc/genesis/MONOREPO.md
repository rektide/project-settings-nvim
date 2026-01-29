# Multi-Project and Monorepo Support Review

This document reviews and synthesizes multi-project and monorepo support approaches across all nvim-project-config proposals.

## Overview

All proposals focus on **single-project detection** by default, but several discuss **multi-project scenarios**:

1. **Monorepos**: Single repo with multiple packages (lerna, nx, pnpm workspaces)
2. **Nested projects**: Git repo inside another git repo (submodules, nested worktrees)
3. **Workspace management**: Multiple project roots in same directory
4. **Cross-project access**: Reading/writing configs for non-active projects

**Key challenges identified:**
- How to detect multiple projects simultaneously?
- How to name/identify multiple projects?
- Should configs cascade/inherit?
- What order should configs load in?
- How should cache handle multiple projects?

## What Each Proposal Says About Multi-Project/Monorepo

### Opus (README.opus.md + DISCUSS.opus.md)

**Monorepo Support Section (README.opus.md):**

1. **Project resolver with custom namer:**
   ```lua
   detector = {
     matchers = {
       function(path)
         -- Check for workspace-level marker
         return vim.fn.filereadable(path .. "/pnpm-workspace.yaml") == 1
       end,
     },
     namer = function(root)
       -- Use parent + child for monorepo packages
       local parent = vim.fn.fnamemodify(root, ":h:t")
       local child = vim.fn.fnamemodify(root, ":t")
       return parent .. "-" .. child
     end,
   }
   ```

2. **Strategy options:**
   - `"up"`: Walk from current directory toward root (default)
   - `"down"`: Walk from a known root downward (for monorepos)
   - Custom function for complex cases

3. **Walker implementation:**
   - Uses `plenary.async` for non-blocking directory traversal
   - Walks upward from current working directory by default
   - Applies matchers to identify project root

**Layered Detection Proposal (DISCUSS.opus.md Question 1.9):**

Most detailed discussion of multi-project detection across all proposals:

**Scenario:**
> User is in `~/src/monorepo/packages/auth/src/login.ts`

**Possible detections:**
- `monorepo` (has `.git`)
- `auth` (has `package.json`)
- `monorepo-auth` (combined naming)

**Questions asked:**
- Should we support detecting multiple project roots?
- Load configs for all of them? In what order?
- How does the namer work for nested projects?

**Proposed solution - Layered detection:**
```lua
detector = {
  layers = {
    { matchers = ".git", as = "repo" },
    { matchers = "package.json", as = "package" },
  }
}
-- Context becomes:
-- ctx.projects = {
--   repo = "monorepo",
--   package = "auth"
-- }

-- Loads in order:
-- 1. monorepo.lua  (from repo match)
-- 2. auth.lua       (from package match)
-- 3. monorepo-auth.lua  (combined?)
```

**Execution order questions:**
- Should configs load in detected order (repo → package)?
- Should we create combined config (`monorepo-auth`)?
- Should we support explicit priority?

**Strengths:**
- **Most comprehensive multi-project detection design**
- Clear layered detection model
- Explicit context structure for multiple projects
- Considers execution order and naming

**Weaknesses:**
- Just a proposal, not implemented in README
- Execution order is ambiguous
- Combined naming (`monorepo-auth`) needs more definition
- No cache design for multiple projects

---

### GLM (README.glm.md + DISCUSS.glm.md)

**Monorepo discussion (DISCUSS.glm.md):**

**Question 1.4: Nested repositories**
> If there's a git repo inside another git repo (e.g., monorepo with submodule), how do we decide which one represents "the project"?

**Options implied:**
- Choose outermost (root)
- Choose innermost (closest to cwd)
- Let user configure preference

**Question 1.16: Workspace managers**
> Should we detect and integrate with workspace managers like:
> - `projections.nvim` / `vim.projectionist`
> - Neovim's built-in workspace (`vim.lsp.buf.list_workspace_folders`)
> - tmuxinator / direnv / nix-shell integration?

**Implication:** Workspace detection could inform project detection.

**Question 3.12: Multi-project JSON access**

> **Multi-project JSON access**: Can/should users access JSON configs for *other* projects?
> - `project_config.get_json('other-project', 'path')`
> - Or keep the API scoped to current project only?

**Implication:** API *could* support cross-project access, but this is an open question.

**Strengths:**
- Identifies nested repository ambiguity
- Considers integration with workspace managers
- Asks about cross-project JSON access

**Weaknesses:**
- No monorepo detection design proposed
- No configuration inheritance model
- No execution order discussion
- Just questions, no solutions

---

### K25 (README-k25.md + DISCUSS.k25.md)

**Monorepo support (README-k25.md):**

**Minimal mention in configuration:**

```lua
-- Context object can hold custom data
context = {
  -- Your custom data here
  -- e.g., workspace_root, environment, etc.
}
```

**Implied:** User could manually populate `context.workspace_root` in monorepo case.

**Nested project handling (DISCUSS.k25.md Question 2.2):**

> **Question 2.2**: Simple finder file scanning
> - How do we handle nested project structures?

**Implication:** Finder should handle multiple config levels.

**No specific monorepo detection design proposed.**

**Strengths:**
- Context object can hold workspace metadata
- Considers nested project structures

**Weaknesses:**
- No monorepo detection mechanism
- No inheritance model
- No execution order discussion

---

### K2T (README.k2t.md + DISCUSS.k2t.md)

**Monorepo and workspace support (DISCUSS.k2t.md Question 19):**

**Most detailed monorepo requirements across all proposals:**

**Requirements:**
- Single repo, multiple packages (lerna, nx, pnpm workspaces)
- Root config + package-specific overrides
- Config inheritance/composition

**Questions:**
- How does discovery handle `root → package` directory changes?
- Should config cascade like CSS? (package config extends root config)
- API for workspace root detection separate from project detection?

**Example monorepo structure:**
```
monorepo/
  .git
  nvim-project.lua  -- Root config (common settings)
  packages/
    frontend/
      nvim-project.lua  -- Extends root
    backend/
      nvim-project.lua  -- Extends root
```

**Inheritance model proposed:**
```lua
-- Package config extends root config
packages/frontend/nvim-project.lua:
-- Access root settings
local root = require('nvim-project-config').get_project('monorepo')
root:get('common_setting')

-- Override specific settings
vim.opt.shiftwidth = 4  -- Overrides root's value
```

**Discovery changes considerations:**
- When user navigates from `monorepo/` to `monorepo/packages/frontend/`, detection changes
- Should we auto-reload configs?
- Should we keep root config loaded?

**Performance consideration (Question 4.6):**

> Should we watch for config directory changes for new files?
> - Performance impact?
> - Debouncing/throttling?
> - Opt-in or default?

**Strengths:**
- **Best monorepo requirements definition**
- **Clear inheritance model** (package extends root, like CSS)
- Explicit directory structure example
- Considers navigation changes between root and packages
- Discusses file watching for monorepo

**Weaknesses:**
- No implementation in README
- Inheritance model is just a proposal
- No cache design for multiple projects

---

### Opus2 (README-opus2.md)

**No monorepo or multi-project discussion.**

**Implied support:**
- Custom `project_name_finder` function could implement monorepo detection
- Standard JSON API would work for any detected project

**Strengths:**
- Flexible enough to support custom detection

**Weaknesses:**
- No monorepo discussion at all
- No built-in support considered

---

## Comparison Summary

### Multi-Project Detection

| Proposal | Detection Method | Context Structure | Implementation |
|----------|----------------|------------------|----------------|
| **Opus** | **Layered detection** with `as` labels | `ctx.projects = { repo, package }` | 📋 **Proposal only** |
| GLM | Nested repo question only | Not discussed | 📋 **Question only** |
| K25 | Context can hold workspace_root | Not discussed | 📋 **Implied only** |
| **K2T** | Root + package detection | Not discussed | 📋 **Requirements defined** |
| Opus2 | Custom function | Not discussed | ✅ **Flexible, but manual** |

### Config Inheritance Model

| Proposal | Inheritance | Example | Status |
|----------|-------------|---------|--------|
| Opus | Load multiple configs in order | `monorepo.lua → auth.lua → monorepo-auth.lua` | 📋 Proposed order, not how to merge |
| GLM | Not discussed | - | ❓ Not addressed |
| K25 | Not discussed | - | ❓ Not addressed |
| **K2T** | **CSS-like inheritance** | `root config → package config (extends/overrides)` | 📋 **Best model proposed** |
| Opus2 | Not discussed | - | ❓ Not addressed |

### Cross-Project JSON Access

| Proposal | API Support | Example |
|----------|------------|---------|
| Opus | Implied by layered context | `npc.json("monorepo"):get(...)` |
| GLM | ❓ Questioned | `project_config.get_json('other-project', 'path')` |
| K25 | Not discussed | - |
| **K2T** | ❓ Questioned | `require('nvim-project-config').get_project('monorepo')` |
| Opus2 | Standard JSON API | `npc.get_json_config("other-project")` |

### Monorepo Navigation

| Proposal | Root → Package Navigation | Auto-Reload | File Watching |
|----------|-------------------------|-------------|---------------|
| Opus | Not discussed | Not discussed | Not discussed |
| GLM | Not discussed | Not discussed | Not discussed |
| K25 | Not discussed | Not discussed | Not discussed |
| **K2T** | ✅ **Discussed explicitly** | ✅ **Questioned** | ✅ **Questioned** |
| Opus2 | Not discussed | Not discussed | Not discussed |

---

## Technical Analysis

### Multi-Project Detection Approaches

#### Approach 1: Layered Detection (Opus)

**Design:**
```lua
detector = {
  layers = {
    { matchers = ".git", as = "repo" },
    { matchers = "package.json", as = "package" },
  }
}

-- Result:
ctx.projects = {
  repo = "monorepo",
  package = "auth"
}
```

**How it works:**
1. Walk up directories
2. Match first layer (e.g., `.git`) → mark as "repo"
3. Continue walking and match second layer (e.g., `package.json`) → mark as "package"
4. Stop when no more matches or root reached

**Strengths:**
- Clear mental model
- Multiple projects detected in single pass
- Flexible layer configuration

**Weaknesses:**
- Order of layers determines priority
- What if multiple files match same layer?
- What if layers conflict (e.g., two `.git` directories)?

---

#### Approach 2: Separate Discovery + Workspace Detection (Implied by K2T)

**Design:**
```lua
-- Stage 1: Detect current project (as today)
local current_project = detect_current(cwd)

-- Stage 2: Detect workspace root (new)
local workspace_root = detect_workspace(current_project)

-- Stage 3: Load both configs
load_project_config(current_project)
load_workspace_config(workspace_root)
```

**How it works:**
1. Detect project for current directory (e.g., `auth`)
2. Walk up from project to find workspace root (e.g., `monorepo`)
3. Load both `auth.lua` and `monorepo.lua`
4. Apply inheritance (package extends workspace)

**Strengths:**
- Separates concerns (project vs. workspace)
- Workspace can have its own discovery logic
- Clear separation of responsibilities

**Weaknesses:**
- Two detection passes (performance)
- More complex code

---

#### Approach 3: Custom Project Name Extractor (Opus README)

**Design:**
```lua
detector = {
  matchers = { function(path)
    return vim.fn.filereadable(path .. "/pnpm-workspace.yaml") == 1
  end},
  namer = function(root)
    -- Create combined name
    local parent = vim.fn.fnamemodify(root, ":h:t")
    local child = vim.fn.fnamemodify(root, ":t")
    return parent .. "-" .. child
  end,
}
```

**How it works:**
1. Detect project root with custom matcher
2. Extract combined name from directory structure
3. Load single config (`monorepo-auth.lua`)

**Strengths:**
- Simple, single project model
- Works with existing detection logic

**Weaknesses:**
- Doesn't detect both root and package separately
- No inheritance model
- User must implement custom logic

---

### Config Inheritance Models

#### Model 1: CSS-Like Inheritance (K2T) 🏅

**Design:**
```lua
-- Root config (monorepo/nvim-project.lua)
vim.opt.shiftwidth = 2

-- Package config (packages/frontend/nvim-project.lua)
-- Option 1: Extend root
local root = require('nvim-project-config').get_project('monorepo')
vim.opt.shiftwidth = root:get('shiftwidth')  -- Inherit

-- Override specific setting
vim.opt.tabstop = 4  -- Override root's value

-- Option 2: Explicit extends syntax
return {
  extends = "monorepo",
  overrides = {
    shiftwidth = 4,
    tabstop = 4,
  }
}
```

**Execution order:**
1. Load `monorepo.lua` (root config)
2. Load `packages/frontend/nvim-project.lua` (package config)
3. Package config can access root via `get_project()`
4. Apply package overrides on top of root

**Strengths:**
- **Clear inheritance model** (CSS-like)
- Package explicitly extends root
- Easy to understand
- Supports deep hierarchies (root → package → subpackage)

**Weaknesses:**
- Package config must explicitly extend root
- Requires API to access other projects
- Circular dependencies possible?

---

#### Model 2: Sequential Loading (Opus)

**Design:**
```lua
-- ctx.projects = { repo = "monorepo", package = "auth" }

-- Execution order:
-- 1. Load monorepo.lua
-- 2. Load auth.lua
-- 3. (Optional) Load monorepo-auth.lua

-- No inheritance - just sequential application
```

**How it works:**
1. Load repo config first
2. Load package config second
3. Package config overrides repo config (standard Neovim behavior)
4. Optional combined config for fine-grained control

**Strengths:**
- Simple, no explicit inheritance
- Natural Neovim config behavior (later files override earlier)
- No special API needed

**Weaknesses:**
- Package can't explicitly extend root
- Can't query root settings
- Combined config needs more design

---

#### Model 3: Explicit Merging

**Design:**
```lua
-- Root config (monorepo/nvim-project.lua)
return {
  settings = {
    shiftwidth = 2,
    tabstop = 2,
  }
}

-- Package config (packages/frontend/nvim-project.lua)
return {
  extends = "monorepo",
  settings = {
    shiftwidth = 4,  -- Merge and override
    tabstop = 4,     -- Merge and override
    format_on_save = true,  -- New setting
  }
}

-- Executor merges:
-- {
--   shiftwidth = 4,  -- Override
--   tabstop = 4,     -- Override
--   format_on_save = true,  -- New
-- }
```

**How it works:**
1. Load root config
2. Load package config with `extends` field
3. Deep merge package settings into root settings
4. Apply merged config

**Strengths:**
- Explicit inheritance via `extends`
- Deep merging of settings
- Clear override model

**Weaknesses:**
- Requires merging logic
- Complex for nested settings
- Different from standard Neovim behavior

---

### Navigation Behavior in Monorepo

**Scenario:** User navigates from `monorepo/` to `monorepo/packages/frontend/`

**What should happen:**

**Option 1: Reload on directory change**
```lua
vim.api.nvim_create_autocmd('DirChanged', {
  callback = function()
    local new_project = detect(vim.fn.getcwd())
    load_project_config(new_project)
  end,
})
```

**Behavior:**
- When entering `packages/frontend/`:
  - Detect `frontend` project
  - Detect `monorepo` workspace root
  - Load both configs

**Strengths:**
- Automatic
- User doesn't think about it

**Weaknesses:**
- Could reload too frequently
- Performance impact
- May reload unnecessarily

---

**Option 2: Only reload if project changes**
```lua
local last_project = nil

vim.api.nvim_create_autocmd('DirChanged', {
  callback = function()
    local new_project = detect(vim.fn.getcwd())
    if new_project ~= last_project then
      load_project_config(new_project)
      last_project = new_project
    end
  end,
})
```

**Behavior:**
- When entering `packages/frontend/`:
  - Project changes from `monorepo` to `frontend`
  - Reload configs

**Strengths:**
- Reduces unnecessary reloads
- Better performance

**Weaknesses:**
- More complex logic
- May miss workspace config changes

---

**Option 3: Cache multiple projects, don't reload**

```lua
-- In monorepo/, detect and cache:
ctx = {
  projects = {
    repo = "monorepo",
  }
}

-- In packages/frontend/, detect and append:
ctx = {
  projects = {
    repo = "monorepo",      -- Already cached
    package = "frontend",    -- New
  }
}

-- Don't reload, just use cache
```

**Behavior:**
- Cache persists across directory changes
- Only reload if forced (e.g., `:NvimProjectConfigReload`)

**Strengths:**
- Best performance
- Simple

**Weaknesses:**
- Stale configs possible
- User must manually reload

---

## Recommended Monorepo Support Design

### Core Approach: Separate Project + Workspace Detection

```lua
local M = {}

-- Stage 1: Detect current project
function M.detect_project(cwd)
  -- Walk up looking for markers
  local project_root, project_name = walk_up_and_match(cwd, { '.git', 'package.json' })
  if not project_root then
    return nil  -- No project found
  end

  return {
    name = project_name,
    root = project_root,
    type = "project",
  }
end

-- Stage 2: Detect workspace (optional)
function M.detect_workspace(project)
  -- Walk up from project looking for workspace markers
  local workspace_root, workspace_name = walk_up_and_match(
    project.root,
    { 'pnpm-workspace.yaml', 'lerna.json', 'nx.json' }
  )

  if not workspace_root then
    return nil  -- No workspace
  end

  return {
    name = workspace_name,
    root = workspace_root,
    type = "workspace",
  }
end

-- Stage 3: Build context with both
function M.build_context(cwd)
  local project = M.detect_project(cwd)
  if not project then
    return { cwd = cwd }
  end

  local workspace = M.detect_workspace(project)

  local ctx = {
    cwd = cwd,
    project = project,
    workspace = workspace,
  }

  -- Computed name for combined access
  if workspace then
    ctx.combined_name = workspace.name .. "-" .. project.name
  else
    ctx.combined_name = project.name
  end

  return ctx
end

return M
```

### Config Loading with Inheritance

```lua
-- Load configs in order
function M.load_configs(ctx)
  local loaded = {}

  -- Load workspace config first (if exists)
  if ctx.workspace then
    local workspace_config = M.load_project_config(ctx.workspace)
    loaded.workspace = workspace_config
  end

  -- Load project config
  local project_config = M.load_project_config(ctx.project)
  loaded.project = project_config

  -- Support inheritance in project config
  if loaded.project and loaded.workspace then
    -- Add workspace to context for inheritance
    loaded.project._parent_workspace = loaded.workspace
  end

  return loaded
end

-- Load project config (supports inheritance)
function M.load_project_config(project_info)
  local config_path = M.get_config_path(project_info.name)

  -- Check if config exists
  if not vim.loop.fs_stat(config_path) then
    return nil
  end

  -- Load and execute config
  local config = dofile(config_path)

  -- If config has `extends` field, load parent
  if type(config) == 'table' and config.extends then
    local parent_name = config.extends
    local parent_config = M.load_project_config({ name = parent_name })

    -- Deep merge parent into config
    config = deep_merge(parent_config, config)

    -- Remove extends field to avoid recursion
    config.extends = nil
  end

  return config
end
```

### Inheritance Models

#### Model A: Explicit `extends` (Recommended)

```lua
-- packages/frontend/nvim-project.lua
return {
  extends = "monorepo",
  -- Workspace settings (inherited)
  -- Project overrides
  lsp = {
    servers = { "tsserver", "eslint" },  -- Override or extend
  },
  settings = {
    shiftwidth = 4,  -- Override monorepo's 2
  },
}
```

**API for accessing inherited values:**
```lua
local ctx = require('nvim-project-config').get_context()

-- Access workspace config
local workspace = ctx.workspace_config

-- Access project config
local project = ctx.project_config

-- Get inherited value (checks workspace then project)
local get_inherited = function(path)
  local value = get_nested(project, path)
  if value == nil then
    value = get_nested(workspace, path)
  end
  return value
end
```

**Strengths:**
- Explicit inheritance
- Easy to understand
- Supports deep hierarchies

---

#### Model B: Manual Extension (Alternative)

```lua
-- packages/frontend/nvim-project.lua
-- Manually load and extend workspace config
local workspace = require('nvim-project-config').get_project_config('monorepo')

return {
  -- Inherit from workspace
  lsp = workspace.lsp or {},
  settings = workspace.settings or {},

  -- Override specific values
  settings = {
    shiftwidth = 4,  -- Override
  },
}
```

**Strengths:**
- No special infrastructure needed
- User has full control

---

### API for Multi-Project Access

```lua
local M = {}

-- Get current project config
function M.get_config()
  return M._current_context.project_config
end

-- Get specific project config (by name)
function M.get_project_config(project_name)
  -- Check cache first
  if M._cached_configs[project_name] then
    return M._cached_configs[project_name]
  end

  -- Load from disk
  local config_path = M.get_config_path(project_name)
  if not vim.loop.fs_stat(config_path) then
    return nil
  end

  local config = dofile(config_path)

  -- Cache it
  M._cached_configs[project_name] = config

  return config
end

-- Get all loaded/cached projects
function M.list_projects()
  local projects = {}

  if M._current_context.project then
    table.insert(projects, M._current_context.project.name)
  end

  if M._current_context.workspace then
    table.insert(projects, M._current_context.workspace.name)
  end

  -- Add any other cached projects
  for name, _ in pairs(M._cached_configs) do
    table.insert(projects, name)
  end

  return projects
end

return M
```

---

## Monorepo Configuration

```lua
require('nvim-project-config').setup({
  -- Detection configuration
  detector = {
    -- Project markers (for current directory)
    project_matchers = {
      '.git',
      'package.json',
      'Cargo.toml',
    },

    -- Workspace markers (walk up from project)
    workspace_matchers = {
      'pnpm-workspace.yaml',
      'lerna.json',
      'nx.json',
      'turbo.json',
    },

    -- Naming strategy
    namer = function(project, workspace)
      if workspace then
        return workspace.name .. "-" .. project.name
      else
        return project.name
      end
    end,
  },

    -- Inheritance model
    inheritance = {
      enabled = true,        -- Enable workspace inheritance
      deep_merge = true,       -- Deep merge workspace config into project
      fallback_to_workspace = true,  -- Use workspace value if project doesn't override
    }
  },

  -- Auto-reload on directory change
  auto_reload = {
    enabled = true,
    on_dir_changed = true,      -- Reload when changing directories
    on_file_changed = false,    -- Watch config files for changes
    debounce_ms = 500,          -- Debounce rapid changes
  },

  -- Multi-project cache
  cache = {
    multiple_projects = true,    -- Cache multiple projects
    max_cached_projects = 20,  -- Limit cache size
    ttl_seconds = 3600,        -- 1 hour TTL
  }
})
```

---

## Summary

### Best Monorepo Design: K2T

**Why:**
- **Most comprehensive requirements definition**
- **Best inheritance model** (CSS-like, package extends workspace)
- **Explicit directory structure example**
- **Considers navigation scenarios**
- **Discusses file watching for auto-reload**

**Key features to adopt:**
1. Separate project + workspace detection
2. CSS-like inheritance model (`extends` field)
3. Explicit API to access other projects
4. Auto-reload on directory change (with debounce)
5. Multi-project caching

### What Others Got Right

**Opus:**
- Layered detection model (`ctx.projects = { repo, package }`)
- Execution order consideration
- Custom naming strategy for combined names

**GLM:**
- Identifies nested repository ambiguity
- Asks about workspace manager integration
- Questions cross-project JSON access

**K25:**
- Context object can hold workspace metadata
- Considers nested project structures

### Recommended Implementation

1. **Start with K2T's requirements**
   - Root config + package-specific overrides
   - Config inheritance/composition

2. **Add Opus's layered detection**
   - `ctx.projects = { repo, package }` structure
   - Multiple projects detected in single pass

3. **Add inheritance models**
   - **Recommended**: Explicit `extends` field in config
   - **Alternative**: Manual extension API

4. **Add multi-project API**
   - `get_project_config(project_name)` - access any project
   - `list_projects()` - list all cached projects
   - Context includes both project and workspace

5. **Add auto-reload logic**
   - Reload on DirChanged (with debounce)
   - Support manual reload command
   - Optional file watching

6. **Add multi-project caching**
   - Cache configs for multiple projects
   - TTL-based eviction
   - Manual cache clearing

### Example Usage

```lua
-- In monorepo/packages/frontend/
require('nvim-project-config').setup({
  detector = {
    workspace_matchers = { 'pnpm-workspace.yaml' },
    inheritance = {
      enabled = true,
      deep_merge = true,
    }
  }
})

-- packages/frontend/nvim-project.lua
return {
  extends = "monorepo",
  lsp = {
    servers = { "tsserver", "eslint" },  -- Extends or overrides workspace
  },
  settings = {
    shiftwidth = 4,  -- Overrides workspace's 2
    tabstop = 4,
  },
}

-- In Lua code:
local ctx = require('nvim-project-config').get_context()
-- ctx.project = { name = "frontend", root = "...", type = "project" }
-- ctx.workspace = { name = "monorepo", root = "...", type = "workspace" }
-- ctx.combined_name = "monorepo-frontend"

-- Access workspace config
local workspace_config = ctx.workspace_config

-- Access project config (with inheritance applied)
local project_config = ctx.project_config

-- Access other project configs
local other_config = require('nvim-project-config').get_project_config('backend')
```

---

## Open Questions

1. **Inheritance depth**: Support unlimited nesting (workspace → project → subproject)?
2. **Circular dependencies**: Detect and warn about circular `extends`?
3. **Performance**: How to handle large monorepos with 100+ packages?
4. **Conflicting settings**: What if both workspace and project set same key to different types?
5. **Workspace isolation**: Should workspace configs be isolated from each other?
6. **Discovery priority**: Which takes precedence if both project and workspace markers found at same level?

These questions can be addressed during implementation and iteration.
