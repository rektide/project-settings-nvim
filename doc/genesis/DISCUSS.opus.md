# Discussion: nvim-project-config Architecture & UX

This document captures open questions for refining the architecture and developer experience.

---

## 1. Core Architecture Questions

### 1.1 Context Object Lifecycle

The context object flows through all three stages. What should its contract be?

```lua
-- Option A: Immutable context, each stage returns new data
local detection = detector.detect(path)
local files = finder.find({ project_name = detection.name, config_dir = ... })
local results = executor.execute(files)

-- Option B: Mutable context, stages enrich it
local ctx = Context.new(path)
detector.detect(ctx)   -- adds ctx.root, ctx.name
finder.find(ctx)       -- adds ctx.files
executor.execute(ctx)  -- adds ctx.loaded, ctx.json_cache
```

**Trade-offs:**
- Immutable: Easier to test, no hidden state, parallelizable
- Mutable: Less ceremony, executors can see what other executors loaded

**Question:** Should the context be available to user config scripts? If so, what should they be able to read/write?

---

### 1.2 Execution Order & Priority

When multiple config files are found:

```
~/.config/nvim/projects/
├── rad.lua           # (1) base-level project file
├── rad.json          # (2) base-level JSON settings  
└── rad/
    ├── init.lua      # (3) subdir entry point
    ├── lsp.lua       # (4) subdir module
    └── settings.json # (5) subdir JSON
```

**Questions:**
- What order should these execute? `1 → 2 → 3 → 4 → 5`? Or JSON always last?
- Should `rad/lsp.lua` auto-load, or only if `rad/init.lua` requires it?
- Is there a "priority" field for explicit ordering?
- Should we support `rad/init.lua` returning a table of what to load?

```lua
-- rad/init.lua option: explicit control
return {
  load = { "lsp", "keymaps" },  -- only these, in order
  -- or
  skip = { "experimental" },    -- everything except these
}
```

---

### 1.3 Finder Composition Model

Current design: composite finder calls simple finder twice. But what about:

**Alternative A: Pipeline**
```lua
finder = {
  pipeline = {
    { dir = ".", matchers = { "{project}.lua", "{project}.json" } },
    { dir = "{project}", matchers = { "init.lua", "*.lua" } },
  }
}
```

**Alternative B: Single finder with glob**
```lua
finder = {
  patterns = {
    "{config_dir}/{project}.lua",
    "{config_dir}/{project}.json",
    "{config_dir}/{project}/**/*.lua",
  }
}
```

**Questions:**
- Is the composite pattern adding value, or just complexity?
- Should globs be first-class? (`**/*.lua` in project subdir)
- How do we handle ordering when globs return multiple files?

---

### 1.4 Executor Routing

Current: extension-based routing to handlers.

```lua
handlers = {
  lua = "lua",
  vim = "vim", 
  json = "json",
}
```

**Questions:**
- Should a file be able to match multiple handlers? (e.g., `settings.lua.json` template?)
- What about handlers that preprocess? (e.g., fennel → lua)
- Should handlers be able to veto execution? (e.g., "only run if condition X")

```lua
-- Possible: handler as object
handlers = {
  lua = {
    executor = "lua",
    condition = function(ctx, file) 
      return not file:match("_disabled") 
    end,
  },
}
```

---

### 1.5 Error Handling Strategy

When things go wrong:

```lua
-- Scenario: rad.lua has syntax error, rad.json is valid
```

**Options:**
1. **Fail-fast**: Stop on first error, report it
2. **Collect**: Run everything, collect all errors, report at end
3. **Isolate**: Each file runs in pcall, failures logged but don't stop others
4. **Graceful**: Syntax errors stop that file, runtime errors are caught per-call

**Questions:**
- What's the right default?
- Should JSON loading errors be fatal? (Can't read settings = bad state)
- How do we surface errors? `vim.notify`? Quickfix? Virtual text at project root?

---

### 1.6 JSON Cache Semantics

The JSON executor caches parsed data and validates via mtime.

**Questions:**
- **Scope**: One cache per project, or per JSON file?
- **Write semantics**: 
  - `set()` writes immediately to disk?
  - Or batch writes with explicit `save()`?
  - Or write-on-exit?
- **Conflict resolution**: If file changed externally AND we have pending writes?
- **Schema**: Should we support JSON schema validation?
- **Defaults**: Merge user JSON with defaults from Lua config?

```lua
-- Possible defaults pattern
local settings = npc.json("rad", {
  defaults = {
    formatOnSave = true,
    tabWidth = 2,
  }
})
settings:get("formatOnSave")  -- returns true even if not in JSON file
```

---

### 1.7 Async Boundaries

Using plenary.async throughout—but where exactly?

**Option A: Fully async pipeline**
```lua
async.void(function()
  local ctx = await(detector.detect(path))
  local files = await(finder.find(ctx))
  await(executor.execute(ctx, files))
end)()
```

**Option B: Async at I/O only**
```lua
-- Detection: sync (fast directory checks)
-- Finding: sync (just fs.scandir)
-- Execution: async (file reads, especially JSON)
```

**Option C: Configurable**
```lua
setup({
  async = true,        -- or false for sync mode
  -- or granular:
  async = {
    detect = false,    -- detection is fast enough
    find = false,
    execute = true,    -- execution benefits most
  }
})
```

**Questions:**
- What actually benefits from async? (File I/O? Lua execution? Neither?)
- Does async complicate the mental model for users writing configs?
- Should user configs be able to `await`?

---

### 1.8 Caching & Invalidation

Multiple caches in play:

| Cache | Key | Invalidated by |
|-------|-----|----------------|
| Project detection | directory path | ??? |
| Found files | project name + config_dir | ??? |
| JSON data | file path | mtime change |
| Executed state | ??? | ??? |

**Questions:**
- When should detection cache invalidate? Only on `:NvimProjectConfigReload`?
- Should we watch the config directory for new files?
- If `rad.lua` is deleted, should we un-apply its effects? (Probably impossible)

---

### 1.9 Multi-Project / Monorepo

User is in `~/src/monorepo/packages/auth/src/login.ts`.

**Possible detections:**
- `monorepo` (has `.git`)
- `auth` (has `package.json`)
- `monorepo-auth` (combined)

**Questions:**
- Should we support detecting multiple project roots?
- Load configs for all of them? In what order?
- How does the namer work for nested projects?

```lua
-- Possible: layered detection
detector = {
  layers = {
    { matchers = ".git", as = "repo" },
    { matchers = "package.json", as = "package" },
  }
}
-- ctx.projects = { repo = "monorepo", package = "auth" }
-- Loads: monorepo.lua, then auth.lua, then monorepo-auth.lua?
```

---

### 1.10 Hot Reload & File Watching

**Questions:**
- Should we watch config files and auto-reload on save?
- What about watching the project root markers? (Switching branches might change project)
- Use `vim.loop.fs_event` or poll?
- Performance implications of watching many paths?

---

## 2. API Design Questions

### 2.1 Setup vs Lazy Initialization

```lua
-- Option A: Explicit setup required
require("nvim-project-config").setup(config)

-- Option B: Lazy, setup optional
local npc = require("nvim-project-config")
npc.detect()  -- uses defaults, or prior setup()
```

**Question:** Should unconfigured use error or use defaults?

---

### 2.2 Programmatic Access

What should users be able to query at runtime?

```lua
local npc = require("nvim-project-config")

npc.current()           -- current project context?
npc.is_loaded("rad")    -- check if project loaded?
npc.projects()          -- list all detected projects?
npc.config_files("rad") -- list what was loaded?
```

---

### 2.3 Hooks / Events

Current: User autocmds on `User NvimProjectConfigLoaded`.

**Alternative: Callback-based**
```lua
setup({
  on_detect = function(ctx) ... end,
  on_load = function(ctx, files) ... end,
  on_error = function(err, ctx) ... end,
})
```

**Alternative: Both**
- Callbacks for plugin authors
- Autocmds for user configs

---

### 2.4 Commands

What commands should exist?

```vim
:NvimProjectConfig              " Show current project info
:NvimProjectConfigReload        " Force reload
:NvimProjectConfigEdit          " Open project config (create if missing)
:NvimProjectConfigList          " List all project configs
:NvimProjectConfigDisable       " Temporarily disable for session
```

**Questions:**
- Command naming: `NvimProjectConfig*` vs `ProjectConfig*` vs `PC*`?
- Should `:edit` create from template?

---

## 3. Developer Experience & README Questions

The README is the first contact. These questions help refine it:

### 3.1 First Impression

- Does the opening sentence clearly convey what this does?
- Is "project-specific configuration" understood, or do we need examples first?
- Should we lead with a GIF/screenshot showing it in action?

### 3.2 Cognitive Load

- Is the three-stage model (detect → find → execute) intuitive?
- Are we introducing too many concepts at once?
- Should we have a "Quick Start" that hides complexity, with "Advanced" sections later?

Current flow:
1. Short intro
2. Architecture diagram
3. Full config

**Alternative flow:**
1. Short intro
2. "Just works" example
3. "Customize detection" 
4. "Customize finding"
5. "Customize execution"
6. Full architecture for contributors

### 3.3 Configuration UX

The default config block is large. Questions:

- Is showing the full elaborated config helpful or overwhelming?
- Should we show minimal config first, then build up?
- Are the config keys discoverable? (`detector.matchers` vs `root_markers`?)
- Should config be validated with helpful error messages?

### 3.4 Terminology

Are these terms clear?

| Term | Meaning | Alternatives? |
|------|---------|---------------|
| Detector | Finds project root | Resolver? Locator? |
| Walker | Traverses directories | Scanner? Traverser? |
| Matcher | Pattern that matches | Marker? Pattern? Predicate? |
| Finder | Locates config files | Locator? Scanner? Discoverer? |
| Executor | Runs config files | Loader? Runner? Applier? |
| Context | State object | Config? State? Session? |

**Specific confusion:** "Matcher" is used for both project detection (`.git`) and file finding (`*.lua`). Should we differentiate?

- `root_markers` for project detection
- `file_patterns` for config finding

### 3.5 Examples & Recipes

- Are the current recipes useful?
- What common scenarios are missing?
- Should we have a `examples/` directory with full configs?

**Possible additions:**
- LSP per-project config
- Formatter/linter overrides
- Project-specific keymaps
- Team-shared configs (checked into repo)

### 3.6 Comparison / Positioning

- Should we compare to alternatives? (`exrc`, `vim-localrc`, `direnv`)
- What's our unique value prop in one sentence?
- Are we competing with or complementing `.nvim.lua` / `exrc`?

### 3.7 Onboarding Flow

What's the ideal first-time experience?

1. Install plugin
2. ???
3. Working project config

**Questions:**
- Should we prompt to create first config on install?
- Should we detect common project types and suggest configs?
- Is there a `:NvimProjectConfigInit` wizard?

### 3.8 Discoverability

- How does a user know what config options exist?
- Should we have `:help nvim-project-config` with full docs?
- Inline Lua annotations for LSP hover?
- Link to a generated docs site?

### 3.9 Trust Model

Project configs execute arbitrary Lua. 

- Should we mention security considerations?
- Is there a "safe mode" that only loads JSON?
- Should configs in `~/.config` be trusted differently than configs in project repo?

---

## 4. Naming & Branding

### 4.1 Plugin Name

Current: `nvim-project-config`

**Alternatives:**
- `project-settings.nvim` (clearer?)
- `projectrc.nvim` (shorter)
- `workspace.nvim` (VSCode familiar, but overloaded)
- `autoconfig.nvim` (describes behavior)

### 4.2 Lua Namespace

```lua
require("nvim-project-config")  -- matches plugin name
require("project-config")       -- shorter
require("pconfig")              -- very short
```

---

## 5. Scope Questions

### 5.1 What's Out of Scope?

Should we explicitly NOT do:

- [ ] Session management
- [ ] Project switching UI (telescope picker)
- [ ] Git integration
- [ ] Task running
- [ ] Environment variable loading (that's direnv)

### 5.2 What Might Be In Scope Later?

- [ ] Project templates
- [ ] Config inheritance (`_base.lua`)
- [ ] Remote/shared configs
- [ ] Config encryption (for secrets)

---

## Next Steps

Priority questions to resolve:

1. **Context lifecycle** — Mutable or immutable?
2. **Execution order** — How do multiple files sequence?
3. **Terminology** — Rename matcher to avoid confusion?
4. **README structure** — Quick start first, or architecture first?
5. **Error handling** — Fail-fast or isolated?

Once these are answered, we can solidify the file structure and begin implementation.
