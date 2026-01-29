# nvim-project-config Architecture Discussion

## Technical Architecture Questions

### 1. Matcher API Standardization

Current design supports multiple matcher types interchangeably:
- String: `'*.lua'`
- Function: `function(path) return path:match('%.vim$') end`
- Table: `{ find = function(dir) end, extract_name = function(dir) end }`

**Questions**:
- Should we consolidate on a single, more powerful matcher interface?
- How do composite matchers combine results (AND vs OR logic)?
- Should matchers return scores/priorities for ambiguous matches?
- Is the flexibility worth the complexity for users reading config examples?

### 2. Composite Pattern Complexity

Nesting: `composite discovery → composite finder → composite executor`

**Concerns**:
- Is this nesting too deep for users to understand the execution flow?
- Should we provide simpler "mode" presets ("simple", "advanced")?
- Execution order in composites: sequential, parallel, or priority-based?
- Should we flatten by making the top-level API less configurable?

**Alternative approach**: Instead of nested composites, provide a linear pipeline where each stage is pluggable but not nested:
```
Discovery → Finder → Executor
   (one)       (one)      (one)
```

### 3. Context Object Immutability

Context flows through stages:
```
{cwd, config_dir} 
  → discovery 
    → {project_name, ...} 
      → finder 
        → {files, ...} 
          → executor
```

**Questions**:
- Should each stage receive a fresh copy (immutable) or mutate in place?
- How do we prevent downstream stages from corrupting upstream data?
- Should we freeze the context after each stage with `vim.deep_equal` checks?
- Benefits of immutability: easier debugging, predictable execution
- Costs: performance overhead, more complex implementation

### 4. Error Handling Strategy

**Failure scenarios**:
- Discovery finds no project
- Finder locates no config files
- Executor encounters syntax/runtime errors
- Cache validation fails (mtime unavailable)
- Malformed JSON config

**Questions**:
- Silent fallback vs loud errors: what's appropriate for each failure type?
- Should we emit error events for user customization?
- Retry mechanisms for transient failures?
- Should execution continue if one config file fails but others succeed?
- Error recovery: should we provide `:ProjectConfigReload` command?

**Proposed approach**:
- Discovery failure: warn, fallback to cwd as project name
- Finder failure: silent (no config is okay)
- Executor failure: error per-file, continue with others
- Cache failure: fallback to fresh load, warn if persistent

### 5. Cache Invalidation Beyond JSON

Currently only JSON executor has mtime-based cache validation.

**Expansion possibilities**:
- Should lua/vim executors cache compiled chunks?
- Cache directory listings for finder performance?
- TTL-based eviction for memory-constrained environments?
- Explicit cache API for users: `require(...).clear_cache('project-name')`
- Should cache be project-specific or global?

**JSON-specific concerns**:
- mtime check on every access adds stat syscall overhead
- For large JSON configs, worth it; for small ones, maybe not
- Make mtime validation configurable: `validate_cache = true | false | function`

### 6. Execution Order and Idempotency

When multiple config files are found:
- What order do they execute? (alphabetic, depth-first, priority-weighted)
- If both `rad.lua` and `rad.json` exist, which wins?
- Should we merge configs or last-writer-wins?
- How to handle partial failures in a batch?

**Proposed rules**:
1. Explicit order: `project_name.lua → project_name.vim → project_name.json`
2. Directory order: root configs first, then subdirectories alphabetically
3. Merge for settings (JSON), overwrite for scripts (Lua/Vim)
4. Continue executing remaining files if one fails

### 7. Auto-Loading vs Manual Trigger

**Options**:
1. **Auto-load on events**: VimEnter, DirChanged
2. **Explicit only**: provide `load()` function, user calls when needed
3. **Hybrid**: auto-load with option to disable: `{ auto_load = true }`

**Considerations**:
- Performance impact on startup: async helps but still I/O
- Race conditions with lazy-loading plugins
- User surprise factor: "magic" vs explicit
- Integration with session managers
- Monorepos: changing between packages in same repo

**Question**: Should auto-reload on DirChanged be default or opt-in?

### 8. Event System for Integration

Should we emit events for other plugins to hook into?

```lua
-- Potential events:
'ProjectConfig:DiscoveryComplete' { project_name, strategy, duration }
'ProjectConfig:FilesFound' { files, count }
'ProjectConfig:Executed' { succeeded = {}, failed = {} }
'ProjectConfig:CacheInvalid' { file_path, reason }
'ProjectConfig:Error' { stage, message }
```

**Use cases**:
- Statusline plugins showing current project
- Plugin managers loading project-specific plugins
- Logging/telemetry plugins
- Auto-save project state

**Questions**:
- Use vim custom events (`:h autocommand`) or custom callback registry?
- Sync vs async event handling?
- Should events be opt-in for performance?

**Alternative**: Provide hooks instead of events (see below)

### 9. Extension Lifecycle Hooks

Current design: replace whole strategies

**Alternative**: lifecycle hooks
```lua
require('nvim-project-config').setup({
  hooks = {
    pre_discovery = function(context) end,
    post_discovery = function(context) end,
    pre_execute = function(context, files) end,
    post_execute = function(context, results) end,
    on_error = function(stage, error) end
  }
})
```

**Tradeoffs**:
- Hooks: easier for small customizations, less power
- Strategies: more powerful, but steeper learning curve
- Can we support both? (hooks as simple wrapper over strategies)

**Question**: Should we provide both simple hooks for common cases and full strategy replacement for advanced cases?

### 10. Core File Formats vs Extensibility

Built-in support: lua, vim, json

**Questions**:
- Should we support yaml/toml out of the box? (adds dependencies)
- Plugin system for custom format executors?
- Format auto-detection beyond file extension? (shebang, content sniffing)
- Which formats are truly necessary for v1.0?

**Minimal approach**: Lua only for v1.0, vim/json as secondary, extensible for others

**Comprehensive approach**: All three built-in, documented extension API

### 11. Naming and Terminology

Current terms:
- "discovery" vs "project_discovery"
- "finder" vs "locator"
- "executor" vs "loader" vs "runner"
- "strategy" vs "provider"
- "matcher" vs "pattern" vs "predicate"

**Concern**: Consistent, clear naming reduces cognitive load

**Proposal**:
- `discovery` (stage 1): find project name
- `finder` (stage 2): locate config files
- `loader` (stage 3): load/execute configs
- `matcher`: pattern/function to match things
- `strategy`: composition pattern implementation

**Question**: Are these terms clear to Neovim plugin users?

### 12. Testing and Development Workflow

**Needs**:
- Unit tests for each strategy/executor
- Integration tests for full pipeline
- Test utilities for mocking file system
- Example projects in tests/fixtures/

**Questions**:
- Test coverage targets?
- CI strategy for plugin?
- Documentation examples that are verified by tests (doctest style)?
- Benchmarks for large monorepos?

**File system mocking**: Critical for reliable tests. Use `plenary.scandir` with test fixtures or mock at fs level?

### 13. Documentation Structure

README.k2t.md currently includes everything. Potential reorganization:

- README.md: User-facing overview, quick start, common patterns
- docs/architecture.md: Detailed design, mermaid diagrams
- docs/api.md: Auto-generated from docstrings
- docs/recipes.md: Common configurations
- CONTRIBUTING.md: Dev setup, testing, code style

**Question**: Separate user docs from architecture docs, or keep combined?

**Tradeoff**: Single comprehensive doc vs fragmented docs

### 14. Real-World Usage Patterns

What are the 3-5 most common use cases?

**Likely patterns**:
1. Project-specific settings (shiftwidth, tabstop)
2. Project commands (build, test, run)
3. Path/rtp modifications for project tools
4. LSP server configuration per-project
5. Git worktree detection

**Questions**:
- Should we optimize API for these patterns?
- Include "recipes" section with ready-to-use configs?
- Provide project templates?

**Example recipe**:
```lua
-- Node.js project detection
{
  project_discovery = {
    matchers = {
      { find = 'package.json', extract_name = function(dir) return vim.fn.json_decode(dir .. '/package.json').name end }
    }
  }
}
```

### 15. Performance Optimization Priorities

**Potential bottlenecks**:
- Filesystem walking (discovery): O(n) directory traversal
- Multiple stat calls (finder): one per potential config file
- Cache validation: stat on every JSON access
- Synchronous execution: blocks editor on slow configs

**Questions**:
- Which operations actually need async?
- Benchmarks for large projects (thousands of files)?
- Debounce/throttle for rapid directory changes?
- Incremental loading for monorepos?

**Tradeoff**: Complexity vs performance

### 16. API Design Patterns

Consistent patterns used throughout:
- Functions that accept single value or list: `matchers = '*.lua'` or `matchers = { '*.lua', '*.vim' }`
- String or function: `config_dir = "/path"` or `config_dir = function() return vim.fn.stdpath(...) end`
- Matcher type polymorphism: string pattern, function, table

**Questions**:
- Does this flexibility justify implementation complexity?
- Should we use a validation library (like `lua-cjson` schemas) or hand-roll?
- Error messages when types mismatch: how helpful?

### 17. Dependency Management

**Core dependency**: plenary.nvim (for async, path utils, scanning)

**Optional dependencies**:
- yaml.nvim (for yaml support)
- toml.nvim (for toml support)
- json5.nvim (for json5 comments)

**Questions**:
- Should we support these formats out of the box if deps exist?
- Lazy-load format parsers only when needed?
- Version compatibility guarantees?

**Alternative**: Keep zero optional deps, provide extension points for users to add formats

### 18. Discovery vs Config Dir Cyclic Dependency

Problem: `config_dir` function receives context, but context needs `config_dir` to be created

```lua
-- circular definition:
context = { config_dir = function(context) end } -- need context to get config_dir!
```

**Solutions**:
1. Resolve `config_dir` before creating context (special case)
2. Don't pass context to `config_dir` function (only pass cwd)
3. Make config_dir static (not a function)

**Question**: Which approach is most intuitive?

Current README suggests: `config_dir = function()` (no args), so option 3 or variant of 1

### 19. Monorepo and Workspace Support

**Requirements**:
- Single repo, multiple packages (lerna, nx, pnpm workspaces)
- Root config + package-specific overrides
- Config inheritance/composition

**Questions**:
- How does discovery handle `root → package` directory changes?
- Should config cascade like CSS? (package config extends root config)
- API for workspace root detection separate from project detection?

**Example**:
```
monorepo/
  .git
  nvim-project.lua  -- root config
  packages/
    frontend/
      nvim-project.lua  -- extends root
    backend/
      nvim-project.lua  -- extends root
```

### 20. JSON Configuration Structure

JSON configs are loaded and cached, but what's the structure?

**Options**:
1. Flat key-value: `{ "shiftwidth": 2, "tabstop": 2 }`
2. Namespaced: `{ "settings": { ... }, "commands": { ... } }`
3. Free-form: user-defined structure, we just provide access

**Questions**:
- Should we interpret JSON or just load it?
- Auto-apply settings? Or provide explicit API to access?
- JSON schema validation?

Current README suggests #3 (free-form) with programmatic access: `project_config.get_json('project-name').settings.shiftwidth`

## README Ergonomics and Developer Experience

### First Contact Assessment: README.k2t.md

The README is often the first (and sometimes only) documentation developers read. How effective is it as an introduction?

#### What Works Well

1. **Immediate clarity**: Opening line "Load project-specific configuration dynamically in Neovim" is clear
2. **Problem-solution fit**: Explains the three-stage pipeline with concrete example
3. **Visual architecture**: Mermaid diagram shows flow at a glance
4. **Comprehensive config**: Full default config shows all options in one place
5. **Layered detail**: Short intro → basic config → detailed architecture
6. **Real examples**: Shows actual Lua code, not just signatures
7. **API reference**: Clear function signatures and context object

#### Areas for Improvement

1. **Cognitive load**: Comprehensive default config is overwhelming for first-time users
   - Solution: Show minimal config first, then link to full reference
   - Tradeoff: More clicks vs overwhelming first impression

2. **Too much, too soon**: Architecture diagrams appear before basic usage
   - Many users just want `setup()` and go
   - Should we have a "Quick Start" section before architecture?

3. **Finding information**: Single long file makes it hard to find specific topics
   - Table of contents helps but still requires scrolling
   - Consider: collapse/expand sections or separate files?

4. **Example-to-code ratio**: More examples, less explanation of internals
   - Users learn by copying patterns
   - Recipe-based documentation might be more effective

5. **Terminology overload**: "Discovery", "Finder", "Executor", "Strategy", "Matcher"
   - Many new concepts at once
   - Should we introduce concepts gradually with examples?

6. **Decision paralysis**: Too many configuration options shown at once
   - Leads to "I need to understand all of this before I start"
   - Progressive disclosure: start simple, show advanced later

7. **Missing pain point connection**: Doesn't explicitly list problems it solves
   - "Tired of manual project switching?"
   - "Need different settings per client project?"
   - Connect emotionally to developer frustrations

8. **No "aha!" moment**: No section that makes developer think "This is exactly what I needed!"
   - Show transformation: before/after code
   - Specific use case walkthrough (React project, Node project, etc.)

9. **Assumed knowledge**: Assumes users know about plenary, Neovim Lua API, stdpath
   - Links to external resources?
   - Brief explanation of prerequisites?

10. **No immediate gratification**: No "try it now" section
    - Quick copy-paste to see it work
    - Example project config they can use immediately

### Suggested README Structure Improvements

#### Current Structure
```
- Intro (short)
- Longer intro with example
- Architecture diagram
- Configuration (full default)
- File structure
- Detailed architecture (more diagrams)
- API reference
- Usage examples
- Extending
- Performance
- Requirements
- Installation
```

#### Proposed Structure
```
- One-liner description + badges
- Quick Start (3 lines to working)
- Before/After comparison (visual transformation)
- Common use cases (3-5 real examples)
- How it works (high-level, no diagrams)
- Configuration (minimal first, link to full)
- Architecture (optional deep dive, collapsed)
- API Reference (link to separate docs)
- Recipes (copy-paste solutions)
- Installation
- Contributing/Development
```

#### Key Changes

1. **Quick Start section** (before everything else):
   ```lua
   -- Install: { 'rektide/nvim-project-config', dependencies = { 'plenary.nvim' } }
   require('nvim-project-config').setup() -- Done!
   -- Now create: ~/.config/nvim/projects/my-project.lua
   ```

2. **Before/After** showing actual pain solved:
   ```lua
   -- Before: Manual conditionals
   if vim.fn.getcwd():match('rad%-project') then
     vim.opt.shiftwidth = 2
   end
   
   -- After: Automatic per-project config
   -- File: ~/.config/nvim/projects/rad-project.lua
   vim.opt.shiftwidth = 2
   ```

3. **Use case examples** early on:
   - Node.js project with npm commands
   - Python with venv activation
   - Monorepo with root + package configs
   - Git worktree detection

4. **Progressive configuration disclosure**:
   - Show minimal working config
   - Link to "Full Configuration Reference" (separate section or file)
   - Add "Common Patterns" subsection with popular configs

5. **Visual separation**:
   - Use collapsible sections for advanced topics
   - Clear visual hierarchy: quick start → basics → advanced → internals
   - Icons or badges showing section difficulty level

### User Testing Questions

To evaluate README effectiveness, we should ask:

1. **Time to first success**: How long from reading README to working config?
2. **Understanding of concepts**: Can user explain what discovery/finder/executor do?
3. **Configuration confidence**: Can user customize without re-reading entire README?
4. **Troubleshooting ability**: When it doesn't work, does README help diagnose?
5. **Feature discovery**: Do users find advanced features (hooks, custom strategies)?

### Minimal README Experiment

**Hypothesis**: A shorter README with just Quick Start, 3 examples, and link to full docs would have better user satisfaction than comprehensive single-page README.

**Test**: Create both versions, get feedback from 5-10 Neovim users

**Metrics**:
- Setup completion rate
- Time to first working config
- Support questions asked
- User-reported confidence level

## Discussion Priorities

Given limited time and complexity budget, which questions should we tackle first?

**Suggested priority order**:

1. **P0 - Blockers**: Must decide before implementation starts
   - Auto-load behavior (affects core design)
   - Error handling strategy (affects user experience)
   - Context immutability (affects code architecture)

2. **P1 - Important**: Significantly impacts API and usability
   - Matcher API standardization
   - Configuration structure (minimal vs full in README)
   - Event/hooks system

3. **P2 - Nice to have**: Enhancements that don't block v1
   - Monorepo support
   - Additional file formats
   - Cache strategies beyond JSON
   - Performance optimizations

4. **P3 - Documentation**: README ergonomics and developer experience
   - Restructure for progressive disclosure
   - Add quick start and recipes
   - Separate user docs from architecture docs

**What matters most to you for the first version?**

Which of these topics resonates most with your vision? Are there other concerns not listed here? Should we start with a minimal viable design or design for the full vision from day one?