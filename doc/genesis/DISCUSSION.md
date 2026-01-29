# nvim-project-config: Discussion Document

This document summarizes key insights and open questions from reviewing multiple architectural proposals for `nvim-project-config`.

## Overview

We have **five README proposals** from different LLM models (Opus, GLM, K25, K2T, Opus2), each with companion DISCUSSION documents exploring design decisions, trade-offs, and open questions.

**Key finding:** All models independently converged on a **three-stage pipeline architecture**:

1. **Project Discovery** - Find project root and extract name
2. **Configuration Finding** - Locate config files in a configurable directory
3. **Execution** - Run discovered files through appropriate executors

This strong convergence suggests we've found the right abstraction for this problem.

## Technically Different: What Sets Each Proposal Apart?

### Opus (README.opus.md + DISCUSS.opus.md)

**What's unique:**
- **Cleanest terminology**: `detector` / `finder` / `executor` (most intuitive)
- **Most comprehensive discussion**: 499 lines exploring 10 major areas
- **Multiple mermaid diagrams**: Overview + detailed per-stage diagrams
- **Explicit configuration caching**: `cache_detection` toggle
- **Four error handling strategies**: Fail-fast, collect, isolate, graceful

**Strengths:**
- Architectural clarity - best separation of concerns
- Thorough exploration of trade-offs
- Strong emphasis on async throughout
- Clear visual documentation

**Notable technical insight:**
- Error handling framework with 4 distinct strategies, each suited to different use cases
- Configuration cache can be disabled for debugging

### GLM (README.glm.md + DISCUSS.glm.md)

**What's unique:**
- **Helper functions**: `or_matcher()`, `and_matcher()` for explicit composition
- **Strategy functions**: `walk_up_strategy()`, `walk_down_strategy()` as building blocks
- **API-first**: Clean `get_json()`/`set_json()` API with dot notation
- **"Recipes" section**: Common configuration patterns
- **53 questions**: Most thorough exploration of edge cases and "what if" scenarios

**Strengths:**
- Composability - helper functions make composition explicit
- Practical examples and recipes
- Strong focus on testing philosophy and ecosystem integration
- Excellent coverage of filesystem, performance, and monorepo concerns

**Notable technical insight:**
- Strategy functions can be composed like LEGO blocks
- Helper functions make complex matchers readable
- Recipes show 80/20 use cases clearly

### K25 (README-k25.md + DISCUSS.k25.md)

**What's unique:**
- **Strategy string presets**: `'walk_up'`, `'composite'`, `'simple'` - reduces boilerplate
- **Negation syntax**: `'not:node_modules'` for exclusion patterns
- **Default extension handler**: `default = { 'lua', 'vim' }` - catch-all fallback
- **Most detailed directory structure**: `discoverer/strategies/`, `finder/strategies/`, etc.
- **Question prioritization**: P0/P1/P2/P3 categories for implementation planning

**Strengths:**
- Ergonomics - presets make common cases trivial
- Consistent naming conventions
- Practical file structure for module organization
- Clear implementation roadmap

**Notable technical insight:**
- String presets make configuration declarative and readable
- Default extension handler simplifies routing
- Prioritizing questions helps focus implementation efforts

### K2T (README.k2t.md + DISCUSS.k2t.md)

**What's unique:**
- **Custom cache validation**: `validate_cache = function(file_path, cached_data) ... end` - ultimate flexibility
- **Test runner executor example**: Shows extensibility clearly
- **Metatable-based extension**: Professional extension pattern
- **Performance section**: Addresses startup time, memory, async boundaries
- **Excellent README UX analysis**: 10 specific improvements identified

**Strengths:**
- Extensibility - cache validation is power-user feature
- Performance-conscious - identifies real bottlenecks
- Practical README assessment with actionable recommendations
- Strong testing and development workflow guidance

**Notable technical insight:**
- Cache validation function allows custom invalidation logic
- Performance considerations should inform async strategy
- README UX is as important as code quality

### Opus2 (README-opus2.md)

**What's unique:**
- **Most pragmatic**: Production-ready, focused on implementable code
- **ASCII art diagram**: Quick visualization alongside mermaid
- **Modular exports**: `require("nvim-project-config.finders").simple` pattern
- **Simplified configuration**: Reduces complexity while maintaining flexibility
- **No discussion file**: Focus on working implementation

**Strengths:**
- Pragmatism - shipping code vs endless design
- Simplified API without sacrificing power
- Modular design for easy extension
- Clear setup() → load() API separation

**Notable technical insight:**
- Simplicity often trumps theoretical flexibility
- Functions are more flexible than preset strings in practice
- Modular exports make the library approachable

## Notable Features I Liked From Each Document

### From Opus

1. **Detector/Finder/Executor terminology** - Most intuitive naming
2. **Multiple abstraction levels in diagrams** - Overview first, then details
3. **Explicit `cache_detection` toggle** - Useful for debugging
4. **Four error handling strategies** - Clear philosophical choices
5. **Context object contract** - Well-defined interface flowing through pipeline

### From GLM

1. **`or_matcher()` and `and_matcher()` helpers** - Makes composition explicit
2. **`walk_up_strategy()` functions** - Reusable building blocks
3. **API for JSON access** - `get_json()`/`set_json()` with dot notation
4. **"Recipes" section** - Shows common patterns
5. **Edge case exploration** - 53 questions covering real-world scenarios

### From K25

1. **Strategy string presets** - `'walk_up'`, `'composite'` are declarative
2. **Negation prefix** - `'not:node_modules'` for exclusion
3. **Default extension handler** - Simplifies routing
4. **Detailed file structure** - Clear module organization
5. **P0/P1/P2/P3 prioritization** - Practical implementation roadmap

### From K2T

1. **Custom cache validation function** - Ultimate flexibility for advanced users
2. **Test runner executor example** - Shows extensibility clearly
3. **Metatable-based extension** pattern - Professional approach
4. **Performance section** - Addresses real concerns
5. **README UX analysis** - 10 actionable improvements

### From Opus2

1. **Production-ready focus** - Implementable code vs design documents
2. **ASCII art diagram** - Quick visualization
3. **Modular exports** - Easy to consume and extend
4. **Simplified configuration** - Power without complexity
5. **setup() → load() API** - Clean mental model

## Unique or Very Good Technical Insights

### 1. Matcher Composition Approaches

**Problem:** How do we combine multiple matchers?

**Three solutions proposed:**

**Opus:** Implicit OR in lists
```lua
matchers = { '.git', '.jj', function(p) ... end }  -- Any match succeeds
```

**GLM:** Explicit helper functions
```lua
matchers = or_matcher({ '.git', '.jj' })
matchers = and_matcher({
  function(p) return p:match('%.lua$') end,
  function(p) return not p:match('%.spec%.lua$') end,
})
```

**K25:** Negation prefix
```lua
matchers = { '.git', 'not:node_modules' }  -- Negate with 'not:' prefix
```

**Insight:** All three work! Implicit OR is simplest, helpers are most explicit, negation is most expressive.

**Recommendation:** Support implicit OR (default) + negation (K25) + optional helpers (GLM) for complex cases.

---

### 2. Configuration Structure Evolution: Opus → Opus2

**Problem:** How much flexibility do we really need?

**Opus (v1):** Nested composites with many options
```lua
{
  detector = {
    strategy = 'up',
    matchers = { '.git' },
    fallback = function() return vim.fn.getcwd() end,
    namer = 'basename',
  },
  finder = {
    config_dir = function() ... end,
    find = function(ctx) ... end,  -- Composite finder function
    file_matchers = { ... },
  },
  executor = {
    execute = nil,  -- Uses default composite
    handlers = { lua = 'lua', vim = 'vim', json = 'json' },
    json = { check_mtime = true, assume_dirty = true },
  },
}
```

**Opus2 (v2):** Simplified functions
```lua
{
  project_name_finder = function()  -- Custom or default
    -- User provides full function
  end,
  finder = function(ctx)  -- Custom or default
    -- User calls simple(ctx, '.') + simple(ctx, project_name)
  end,
  executor_map = {  -- Simple routing map
    lua = require("nvim-project-config.executors").lua_vim,
    vim = require("nvim-project-config.executors").lua_vim,
    json = require("nvim-project-config.executors").json,
  },
}
```

**Insight:** Iteration shows simplicity trumps theoretical flexibility.

**Recommendation:** Provide both - presets for common cases, functions for advanced users.

---

### 3. File Deduplication Problem

**Problem:** Composite finder runs multiple finders, possibly returning the same file twice.

**Example:**
```
config_dir/rad-project.lua    # Found by finder 1 (base dir)
config_dir/rad-project/      # Found by finder 2 (subdir)
config_dir/rad-project/rad-project.lua  # Wait, is this duplicate?
```

**K25 DISCUSS.k25.md (Question 2.4):**
> When composite finder merges results from multiple finders:
> - How do we handle duplicate files found by different finders?
> - Keep first occurrence? Last? Error?
> - Should order matter for execution?

**Insight:** This is a real edge case that could cause duplicate execution.

**Recommendation:** Deduplicate by file path, keeping first occurrence in execution order.

---

### 4. README Cognitive Load Problem

**Problem:** Showing full default configuration first overwhelms users.

**K2T DISCUSS.k2t.md (README UX Assessment):**
> 1. **Cognitive load**: Comprehensive default config is overwhelming for first-time users
>    - Solution: Show minimal config first, then link to full reference
> 2. **Too much, too soon**: Architecture diagrams appear before basic usage
>    - Many users just want `setup()` and go

**Proposed structure:**
```
1. Quick Start (3 lines to working)
2. Before/After comparison (visual transformation)
3. Common use cases (3-5 real examples)
4. How it works (high-level, no diagrams)
5. Configuration (minimal first, link to full)
6. Architecture (optional deep dive, collapsed)
```

**Insight:** Progressive disclosure is key to user adoption.

**Recommendation:** Restructure README with quick start first, architecture later (or separate file).

---

### 5. Async Boundary Questioning

**Problem:** Should everything be async, or just filesystem operations?

**All models questioned this independently:**

| Operation | Async? | Reason |
|-----------|---------|---------|
| Directory walking | ✓ | I/O intensive, many stat calls |
| File reading (JSON) | ✓ | I/O bound |
| Script execution | ✗ | Lua/Vim is synchronous by nature |
| Cache validation | ? | Single stat call - async overhead may not be worth it |
| Context creation | ✗ | Pure computation, no I/O |

**Insight:** Async adds complexity. Only use it where it actually helps.

**Recommendation:** Async for filesystem I/O, sync for computation and script execution.

---

### 6. Context Object Mutability

**Problem:** Should context be immutable (safer) or mutable (more flexible)?

**Opus DISCUSS.opus.md (Question 1.1):**
> **Trade-offs:**
> - Immutable: Easier to test, no hidden state, parallelizable
> - Mutable: Less ceremony, executors can see what other executors loaded

**Immutable benefits:**
- ✓ Easier to test - predictable behavior
- ✓ No hidden state mutations
- ✓ Parallelizable (if we ever go async per stage)
- ✗ More ceremony - need to return new context

**Mutable benefits:**
- ✓ Less ceremony - modify in place
- ✓ Executors can see what other executors loaded
- ✗ Harder to test - mutations can happen anywhere
- ✗ Hidden state - hard to trace bugs

**Insight:** This is a fundamental design decision affecting entire architecture.

**Recommendation:** Mutable - flexibility is more valuable for a user-facing library. Document that core fields should be treated as read-only.

---

### 7. Monorepo Configuration Cascading

**Problem:** In a monorepo, should configs cascade like CSS?

**GLM DISCUSS.glm.md (Question 1.4):**
> Workspace managers: Should we detect and integrate with workspace managers like projections.nvim?

**Example structure:**
```
monorepo/
  .git
  nvim-project.lua  # Root config (common settings)
  packages/
    frontend/
      nvim-project.lua  # Frontend-specific (extends root?)
    backend/
      nvim-project.lua  # Backend-specific (extends root?)
```

**Options:**
1. **No cascading**: Each package is independent project
2. **Explicit extends**: `extends = "monorepo"` in package config
3. **Implicit inheritance**: Package configs automatically extend root
4. **Merged execution**: Execute root config, then package config

**Insight:** Real-world usage pattern that needs consideration.

**Recommendation:** Support explicit extends syntax for monorepo users. Keep it optional - not all monorepos want cascading.

---

### 8. JSON API Design Comparison

**Problem:** What's the most ergonomic API for programmatic JSON access?

**Opus:** Module instance per project
```lua
local settings = require("nvim-project-config").json("my-project")
settings:get("formatOnSave")
settings:set("formatOnSave", true)
```

**GLM:** Direct methods on main module
```lua
local project_config = require('nvim-project-config')
project_config.get_json('my-project', 'lsp.formatOnSave')
project_config.set_json('my-project', 'lsp.formatOnSave', true)
```

**K25:** Global accessor
```lua
local json = require('nvim-project-config').json
json.get('editor.tabSize')
json.set('editor.tabSize', 4)
```

**Insight:** Different ergonomics for different mental models.

**Recommendation:** Use Opus/K25 pattern - module-based API is cleanest and most composable.

---

### 9. Error Handling: Four Philosophies

**Problem:** When things go wrong, what should we do?

**Opus DISCUSS.opus.md (Question 1.5):**
> **Options:**
> 1. **Fail-fast**: Stop on first error, report immediately
> 2. **Collect**: Run everything, collect all errors, report at end
> 3. **Isolate**: Each file runs in pcall, failures logged but don't stop others
> 4. **Graceful**: Syntax errors stop that file, runtime errors caught per-call

**Use cases for each:**

| Strategy | Best for |
|----------|-----------|
| Fail-fast | Development/debugging - catch errors immediately |
| Collect | Batch processing - see all issues at once |
| Isolate | Production - one bad file shouldn't break everything |
| Graceful | Mixed - syntax is fatal, runtime is recoverable |

**Insight:** Error handling philosophy should be configurable or adaptive.

**Recommendation:** Isolate per file - this is a user-facing library, one bad config shouldn't break entire plugin.

---

### 10. Performance Bottlenecks Identified

**Problem:** What could slow this down?

**K2T DISCUSS.k2t.md (Performance Section):**
> **Potential bottlenecks:**
> - Filesystem walking (discovery): O(n) directory traversal
> - Multiple stat calls (finder): one per potential config file
> - Cache validation: stat on every JSON access
> - Synchronous execution: blocks editor on slow configs

**Mitigation strategies:**

| Bottleneck | Mitigation |
|-----------|-------------|
| Directory walking | Async traversal, cache results per directory |
| Multiple stat calls | Batch stats where possible |
| Cache validation | Optional async, batch checks |
| Sync execution | Not much to do - Lua/Vim is synchronous |

**Insight:** Performance considerations should drive async strategy.

**Recommendation:** Async for filesystem operations, sync for execution. Cache directory listings for finder.

## Which Document Do I Like Most Overall?

### First Place: Opus (README.opus.md + DISCUSS.opus.md)

**Why:**
1. **Best terminology** - detector/finder/executor is clearest
2. **Most comprehensive** - 499 lines exploring 10 major areas
3. **Multiple diagrams** - Overview + detailed per-stage
4. **Strong discussion** - Four error handling strategies, context lifecycle, async boundaries
5. **Consistent patterns** - Composite pattern used throughout

**Quote:**
> The architecture follows a **pipeline pattern** with three distinct stages:
> 1. Project Discovery
> 2. Configuration Discovery
> 3. Execution

This is exactly the right level of abstraction.

### Second Place: K25 (README-k25.md + DISCUSS.k25.md)

**Why:**
1. **Most implementable** - Detailed file structure, P0/P1/P2/P3 priorities
2. **Best ergonomics** - String presets reduce boilerplate
3. **Practical insights** - File deduplication, execution order, negation syntax
4. **Clear roadmap** - Prioritization helps focus implementation

**Quote:**
> By extension: string | function | (string | function)[]
> This is a common pattern for all matching we want to use throughout

Shows consistent API design throughout.

### Third Place: K2T (README.k2t.md + DISCUSS.k2t.md)

**Why:**
1. **Extensibility focus** - Custom cache validation, metatable patterns
2. **Performance conscious** - Addresses real bottlenecks
3. **Excellent README UX** - 10 actionable improvements
4. **Test runner example** - Shows extensibility clearly

**Quote:**
> Cache validation: function(file_path, cached_data) -> boolean

Ultimate flexibility for advanced users.

### Fourth Place: GLM (README.glm.md + DISCUSS.glm.md)

**Why:**
1. **Great composability** - Helper functions make patterns explicit
2. **API-focused** - Clean get_json()/set_json() interface
3. **Edge case exploration** - 53 questions covering real scenarios
4. **Recipes section** - Shows common patterns

**Quote:**
> or_matcher({ '.lua', '.vim' })
> and_matcher({ pattern1, pattern2 })

Makes complex matchers readable.

### Fifth Place: Opus2 (README-opus2.md)

**Why:**
1. **Most pragmatic** - Production-ready, shipping code
2. **Simplified API** - Power without complexity
3. **Modular exports** - Easy to consume and extend

**Quote:**
> finder = function(ctx)
>   local simple = require("nvim-project-config.finders").simple
>   return {
>     simple(ctx, "."),
>     simple(ctx, ctx.project_name),
>   }
> end

Simple, flexible, implementable.

**Note:** Opus2 is actually very good - it's just more focused on implementation than design exploration.

## Key Questions for Decision-Making

### Must Decide Before Implementation

1. **Context mutability** - Mutable or immutable?
2. **Error handling** - Fail-fast, isolate, or graceful?
3. **Async boundaries** - Which operations must be async?
4. **Configuration structure** - Nested composites or simplified functions?
5. **Matcher composition** - Implicit OR, helpers, or negation?

### Important for API Design

1. **Terminology** - detector/finder/executor or project_resolver/config_finder/executor?
2. **Strategy vs function** - String presets or full function replacement?
3. **JSON API shape** - Module instance or direct methods?
4. **Config directory resolution** - Function receives context or no args?
5. **Extension routing** - Default handler or explicit only?

### Nice to Have (Can Iterate)

1. **Monorepo support** - Cascading configs, workspace detection
2. **Additional file formats** - YAML, TOML, JSON5
3. **File watching** - Auto-reload on config changes
4. **Performance optimizations** - Directory listing cache, batch stats
5. **Plugin ecosystem** - Event system, hook points

### Documentation Critical

1. **README structure** - Progressive disclosure, quick start first
2. **Common examples** - 3-5 real use cases
3. **Before/after** - Visual transformation showing value
4. **Architecture separate** - Deep dive in ARCHITECTURE.md
5. **API reference** - Generated or manually maintained

## Recommendation: Hybrid Approach

Combine the best features from all proposals:

### From Opus:
- Use detector/finder/executor terminology
- Multiple diagrams at different abstraction levels
- Four error handling strategies (choose one, support others via config)
- Explicit configuration caching toggle

### From GLM:
- Helper functions for matcher composition (`or_matcher`, `and_matcher`)
- API for JSON access with dot notation
- "Recipes" section showing common patterns
- Edge case exploration in documentation

### From K25:
- Strategy string presets (`'walk_up'`, `'composite'`, `'simple'`)
- Negation syntax (`'not:node_modules'`)
- Default extension handler
- P0/P1/P2/P3 implementation priorities

### From K2T:
- Custom cache validation function for advanced users
- Performance section addressing real concerns
- README UX improvements (progressive disclosure)
- Metatable-based extension pattern

### From Opus2:
- Pragmatic, implementation-ready code
- Modular exports for easy consumption
- Simplified API without sacrificing flexibility
- setup() → load() API separation

## Summary

**Consensus:** Three-stage pipeline architecture is correct approach.

**Divergence:** Terminology, configuration structure, and ergonomics vary.

**Best of each:**
- Opus: Architectural clarity and comprehensive discussion
- GLM: Composability and API design
- K25: Ergonomics and implementation roadmap
- K2T: Extensibility and performance
- Opus2: Pragmatism and simplicity

**Next steps:**
1. Merge best features into unified specification
2. Prototype core pipeline with tests
3. Iterate on API based on real usage
4. Refine README with progressive disclosure
5. Document decisions in ARCHITECTURE.md

**My vote:** Start with Opus's detector/finder/executor terminology, adopt K25's strategy strings for ergonomics, include GLM's helper functions for power users, and follow Opus2's pragmatic approach to implementation.
