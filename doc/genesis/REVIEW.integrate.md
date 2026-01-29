# nvim-project-config: Integration Review

This document compares and synthesizes the architecture proposals from multiple LLM models for the `nvim-project-config` project.

## Executive Summary

All models converged on a **three-stage pipeline architecture**:

1. **Project Discovery** - Find project root and extract project name
2. **Configuration Finding** - Locate config files in a configurable directory
3. **Execution** - Run discovered files through appropriate executors

Key commonalities across all proposals:
- Use of **plenary.nvim** for async operations
- **Composite pattern** for finders and executors
- **Matcher flexibility** (string/function/list polymorphism)
- **mtime-based caching** for JSON configuration
- **Context object** flowing through all stages

## Technical Differences by Proposal

### 1. Opus (README.opus.md & DISCUSS.opus.md)

**Architecture Highlights:**
- Clean separation: `detector` / `finder` / `executor` terminology
- Detailed mermaid diagrams at multiple abstraction levels
- Strong emphasis on async throughout using `plenary.async`

**Unique Features:**
- **Composite finder pattern**: Two simple finders (base dir + project subdir) with reusable matcher
- **Explicit matcher table format** with `find` and `extract_name` fields
- Detailed caching strategy with `cache_detection` option
- Comprehensive error handling discussion (4 strategies considered)

**Configuration Structure:**
```lua
{
  detector = { strategy, matchers, fallback, namer },
  finder = { config_dir, find, file_matchers },
  executor = { execute, handlers, json }
}
```

**Discussion Depth:**
- 499 lines covering 10 major topic areas
- Strong focus on context lifecycle, execution order, async boundaries
- 50 numbered questions across architecture, UX, API design, and philosophy

### 2. GLM (README.glm.md & DISCUSS.glm.md)

**Architecture Highlights:**
- Uses `project_resolver` terminology instead of `detector`
- Simpler, more linear mermaid diagrams
- Clear emphasis on "pluggable components"

**Unique Features:**
- **Helper functions** for matchers: `or_matcher()`, `and_matcher()`
- Directory walking strategy functions: `walk_up_strategy()`, `walk_down_strategy()`
- Built-in `get_json()` / `set_json()` API with dot notation
- "Recipes" section with common patterns

**Configuration Structure:**
```lua
{
  project_resolver = { walk_strategy, markers, fallback_to_cwd },
  config_dir = function(ctx) return ... end,
  finder = composite_finder({ finders, filename_matcher }),
  executor = composite_executor({ executors, router })
}
```

**Discussion Depth:**
- 293 lines with 53 numbered questions
- Very thorough exploration of edge cases and "what if" scenarios
- Strong focus on testing philosophy, performance, and ecosystem integration
- Philosophical UX questions about target audience and complexity surface area

### 3. K25 (README-k25.md & DISCUSS.k25.md)

**Architecture Highlights:**
- **"pipeline pattern"** terminology instead of "composite"
- Four mermaid diagrams showing data flow clearly
- Most comprehensive API reference section

**Unique Features:**
- **Strategy strings**: `'walk_up'`, `'composite'`, `'simple'` as presets
- **Negation syntax**: `'not:node_modules'` in matchers
- **Extension router with default handler**: `default = { 'lua', 'vim' }`
- Detailed `discoverer/`, `finder/`, `executor/` directory structure

**Configuration Structure:**
```lua
{
  project_finder = { strategy, matchers, extract_name, fallback_name },
  config_dir = function() return ... end,
  config_finder = { strategy, finders },
  executor = { strategy, by_extension, executors },
  context = { /* custom data */ }
}
```

**Discussion Depth:**
- 819 lines with 95+ questions
- Most exhaustive exploration of design decisions
- Covers architecture, configuration, integration, README UX, implementation
- Prioritizes questions into P0/P1/P2/P3 categories

### 4. K2T (README.k2t.md & DISCUSS.k2t.md)

**Architecture Highlights:**
- Three-stage pipeline: **Discovery → Finding → Execution**
- Three mermaid diagrams focused on stage transitions
- Strong focus on performance and extensibility

**Unique Features:**
- **Cache validation function**: `validate_cache = function(file_path, cached_data) ... end`
- Custom test runner executor example in usage
- Clear separation between `strategies/` subdirectories
- Most detailed "Extending" section with metatable patterns

**Configuration Structure:**
```lua
{
  project_discovery = { strategy, matchers },
  config_dir = function() return ... end,
  finder = { strategy, simple = { matchers, directories } },
  executor = { strategy, routes, executors }
}
```

**Discussion Depth:**
- 545 lines covering 20 technical questions + comprehensive README analysis
- Strong focus on error handling strategies, cache invalidation
- Excellent README UX assessment with specific improvement proposals
- Discussion of auto-loading vs manual trigger with hybrid approach

### 5. Opus2 (README-opus2.md)

**Architecture Highlights:**
- Streamlined, production-ready version
- ASCII art architecture diagram alongside mermaid
- Most pragmatic, implementation-focused

**Unique Features:**
- **Function-based project_name_finder** as primary customization point
- `executor_map` with complex routing (matchers + executors)
- Modular exports: `require("nvim-project-config.finders").simple`
- Explicit `setup()` → `load()` API separation

**Configuration Structure:**
```lua
{
  config_dir = string|function,
  project_name_finder = function() -> string,
  finder = function(ctx) -> files[],
  file_matcher = string|function|table,
  executor_map = table
}
```

**Discussion:**
- No separate DISCUSS file; focus on clean, implementable API

## Key Technical Comparisons

### Terminology Differences

| Concept | Opus | GLM | K25 | K2T | Opus2 |
|---------|-------|-----|------|-----|-------|
| Stage 1 | detector | project_resolver | project_finder | project_discovery | project_name_finder |
| Stage 2 | finder | finder | config_finder | finder | finder |
| Stage 3 | executor | executor | executor | executor | executor_map |
| Pattern | composite | composite | composite/pipeline | composite | function-based |
| Matcher | matchers | filename_matcher | matchers | matchers | file_matcher |

### Matcher System Flexibility

All models support flexible matching with:
- **String**: Simple pattern matching
- **Function**: Custom predicate logic
- **List**: Multiple matchers (OR logic)

**Unique extensions:**
- **GLM**: Helper functions `or_matcher()`, `and_matcher()`
- **K25**: Negation prefix `'not:pattern'`
- **K2T**: Table matcher with `find` + `extract_name` functions
- **Opus**: Pattern strings + functions mixed in lists

### Directory Traversal Strategy

| Model | Default Strategy | Customization |
|-------|-----------------|---------------|
| Opus | Walk up looking for `.git` | Configurable matchers, fallback function |
| GLM | `walk_up_strategy({ markers, fallback })` | Strategy functions |
| K25 | `strategy = 'walk_up'` or `'cwd'` | Preset names or custom functions |
| K2T | Walk up with plenary.path | Custom strategy function |
| Opus2 | Custom `project_name_finder` function | Full function replacement |

### Config Directory Resolution

All models support:
- String path
- Function returning path

**Variations:**
- **Opus**: Function receives context object
- **GLM**: Function receives context object
- **K25**: Function receives context (used as `subdir` parameter)
- **K2T**: Function receives context
- **Opus2**: Function takes no arguments

### Finder Composition

| Model | Composition Approach |
|-------|-------------------|
| Opus | Composite finder calling simple finder twice (base + project subdir) |
| GLM | Composite finder with simple finder sub-components |
| K25 | Strategy string 'composite' with finders array |
| K2T | Strategy string 'composite' with `simple` sub-configuration |
| Opus2 | Function that calls `simple(ctx, ".")` and `simple(ctx, project_name)` |

**Consensus:** Default should search:
1. `<config_dir>/<project_name>.{lua,vim,json}`
2. `<config_dir>/<project_name>/` directory

### Executor Routing

| Model | Routing Mechanism |
|-------|-----------------|
| Opus | `handlers` map: extension → executor name |
| GLM | `router` map: extension → executor instance |
| K25 | `by_extension` map with special `default` key |
| K2T | `routes` map with regex patterns |
| Opus2 | `executor_map` with complex matchers |

**Built-in executors:**
- `lua`: Lua script execution
- `vim`: Vimscript execution
- `json`: JSON loading with mtime caching

### JSON Caching Strategy

All models agree on:
- In-memory cache
- mtime checking before reads/writes
- Fallback to dirty cache on mtime failure

**Unique aspects:**
- **K25**: Configurable `check_mtime`, `assume_dirty` flags
- **K2T**: Custom `validate_cache` function
- **GLM**: Explicit `cache_enabled` boolean
- **Opus**: Implicit always-on with error handling

### Context Object Lifecycle

| Model | Mutability | Contents |
|-------|------------|-----------|
| Opus | Mutable, enriched by stages | project_name, config_dir (core) + custom |
| GLM | Mutable | project_name, config_dir, cwd |
| K25 | Mutable | project_name, config_dir, cwd + user-defined |
| K2T | Mutable | project_name, config_dir, cwd |
| Opus2 | Minimal | project_name, config_dir |

**Consensus:** Context should carry project metadata through pipeline.

## Notable Features by Proposal

### Opus Standout Features

1. **Most comprehensive discussion document** - 499 lines exploring 10 major areas
2. **Multiple mermaid diagrams** at different abstraction levels (overview + detailed per-stage)
3. **Explicit configuration caching** with `cache_detection` toggle
4. **Error handling framework** - 4 strategies considered (fail-fast, collect, isolate, graceful)
5. **Clean separation of concerns** - detector/finder/executor terminology

### GLM Standout Features

1. **Helper functions for matchers** - `or_matcher()`, `and_matcher()` for composition
2. **Strategy functions** - `walk_up_strategy()`, `walk_down_strategy()` as building blocks
3. **API for JSON access** - `get_json()`, `set_json()` with dot notation
4. **"Recipes" section** - Common configuration patterns
5. **Thorough edge case exploration** - 53 questions covering filesystem, performance, ecosystem

### K25 Standout Features

1. **Strategy string presets** - `'walk_up'`, `'composite'`, `'simple'` for easy configuration
2. **Negation in matchers** - `'not:node_modules'` syntax
3. **Extension router with default** - `default = { 'lua', 'vim' }` fallback
4. **Most detailed directory structure** - `discoverer/strategies/`, `finder/strategies/`, `executor/strategies/`
5. **Question prioritization** - P0/P1/P2/P3 categories for implementation planning

### K2T Standout Features

1. **Custom cache validation** - `validate_cache` function for advanced caching logic
2. **Test runner executor example** - Shows extensibility clearly
3. **Metatable-based extension** pattern in "Extending" section
4. **Performance section** - Discusses startup time, memory, async boundaries
5. **Excellent README UX analysis** - Identifies 10 specific areas for improvement

### Opus2 Standout Features

1. **Most pragmatic, implementation-ready** - Focused on code that works
2. **ASCII art diagram** alongside mermaid for quick visualization
3. **Modular exports** - `require("nvim-project-config.finders").simple pattern
4. **Clean API** - `setup()` → `load()` separation
5. **Simplified configuration** - Reduces complexity while maintaining flexibility

## Unique Technical Insights

### 1. Async Boundary Questioning (All Models)

**Insight:** All models questioned where async is actually beneficial:
- Directory walking (I/O intensive) → async
- File stat/reading (JSON) → async
- Script execution (Lua/Vim) → sync by nature
- Cache validation (stat syscall) → could be sync

**Consensus:** Async should be used for filesystem operations, but not forced everywhere.

### 2. Matcher Composition (Opus, GLM, K25)

**Insight:** Three different approaches to matcher composition:
- **Opus**: Implicit OR in lists, single string/function
- **GLM**: Explicit `or_matcher()` and `and_matcher()` helpers
- **K25**: Negation prefix `'not:pattern'` for exclusion

**Value:** Shows flexibility in API design - implicit composition vs explicit helpers vs syntax sugar.

### 3. File Deduplication (K25 Discussion)

**Insight:** When composite finder merges results, what about duplicate files?

**Considered strategies:**
- Keep first occurrence
- Keep last occurrence
- Error on duplicate
- Deduplicate by path

**Value:** Edge case that could cause duplicate execution if not handled.

### 4. Configuration Structure Progression (Opus → Opus2)

**Insight:** Evolution from nested composites to simpler functions:

**Opus (v1):**
```lua
{
  detector = { strategy = 'up', matchers = { ... } },
  finder = {
    config_dir = function() ... end,
    find = function(ctx) ... end,
    file_matchers = { ... }
  }
}
```

**Opus2 (v2):**
```lua
{
  project_name_finder = function() return ... end,
  finder = function(ctx) return ... end,
  executor_map = { ... }
}
```

**Value:** Simplicity often trumps theoretical flexibility.

### 5. README UX Prioritization (K2T, K25)

**Insight:** Both K25 and K2T identified README cognitive load as critical:

**Problems identified:**
- Full config shown first overwhelms users
- Architecture diagrams before quick start
- Too many concepts introduced at once
- Missing "before/after" transformation examples

**Proposed solution:** Progressive disclosure:
1. Quick start (3 lines to working)
2. Common use cases (3-5 examples)
3. Basic configuration
4. Advanced configuration (linked/separate)
5. Architecture deep dive (optional)

**Value:** User experience of documentation is as important as the code.

### 6. Error Handling Strategies (Opus Discussion)

**Insight:** Four different error handling philosophies:

1. **Fail-fast**: Stop on first error, report immediately
2. **Collect**: Run everything, collect all errors, report at end
3. **Isolate**: Each file runs in pcall, failures logged but don't stop others
4. **Graceful**: Syntax errors stop that file, runtime errors caught per-call

**Value:** Different strategies suit different user expectations.

### 7. Context Immutability (All Discussions)

**Insight:** Trade-off between mutable and immutable context:

**Immutable:**
- ✓ Easier to test
- ✓ No hidden state
- ✓ Parallelizable
- ✗ More ceremony
- ✗ Can't communicate between stages

**Mutable:**
- ✓ Less ceremony
- ✓ Executors can see what other executors loaded
- ✗ Harder to test
- ✗ Hidden state mutations

**Value:** Fundamental design decision affecting entire architecture.

### 8. Monorepo Support (GLM, K25, K2T)

**Insight:** Handling monorepos introduces complexity:

**Detection options:**
- Root project (`.git` detected)
- Package project (`package.json` detected)
- Combined (`monorepo-package` naming)
- Layered (root config + package override)

**Configuration cascading:**
- Like CSS inheritance?
- Explicit `extends` syntax?
- Merge strategies?

**Value:** Real-world usage pattern that influences discovery strategy.

### 9. JSON API Design (Opus, GLM, K25, Opus2)

**Insight:** Different approaches to programmatic JSON access:

**Opus:** Module with `get()`/`set()`
```lua
local settings = require("nvim-project-config").json("my-project")
settings:get("formatOnSave")
settings:set("formatOnSave", true)
```

**GLM:** Direct API on main module
```lua
project_config.get_json('lsp.format_on_save')
project_config.set_json('test.command', 'pytest')
```

**K25:** Global accessor
```lua
local json = require('nvim-project-config').json
json.get('editor.tabSize')
json.set('editor.tabSize', 4)
```

**Value:** API ergonomics matter for day-to-day usage.

### 10. Performance Concerns (K2T, GLM)

**Insight:** Performance bottlenecks identified:

1. **Filesystem walking**: O(n) directory traversal to find `.git`
2. **Multiple stat calls**: One per potential config file
3. **Cache validation**: Stat on every JSON access
4. **Synchronous execution**: Blocks editor on slow configs

**Mitigations discussed:**
- Async I/O for filesystem operations
- Cache directory listings
- Configurable cache validation
- Defer loading after startup

**Value:** Performance considerations should inform async strategy.

## Technical Strengths by Model

### Opus: Architectural Clarity

- **Strength:** Cleanest separation of concerns with detector/finder/executor terminology
- **Strength:** Most comprehensive discussion document exploring trade-offs
- **Strength:** Multiple diagrams at different abstraction levels
- **Strength:** Consistent use of composite pattern throughout

### GLM: Composability

- **Strength:** Helper functions for matcher composition (`or_matcher`, `and_matcher`)
- **Strength:** Strategy functions as reusable building blocks
- **Strength:** API-focused with clean `get_json()`/`set_json()` interface
- **Strength:** "Recipes" section showing common patterns

### K25: Ergonomics

- **Strength:** Strategy string presets reduce configuration boilerplate
- **Strength:** Negation syntax for exclusion patterns
- **Strength:** Default extension handler reduces routing complexity
- **Strength:** Comprehensive file structure showing module organization

### K2T: Extensibility

- **Strength:** Custom cache validation function for advanced use cases
- **Strength:** Metatable-based extension pattern
- **Strength:** Performance section addressing real concerns
- **Strength:** Excellent README UX analysis with actionable improvements

### Opus2: Pragmatism

- **Strength:** Most implementable, production-ready proposal
- **Strength:** Simplified API without sacrificing flexibility
- **Strength:** Modular exports for easy extension
- **Strength:** Clear setup() → load() API separation

## Convergent Design Decisions

### 1. Three-Stage Pipeline

All models independently converged on the same architecture:
- Stage 1: Find project root + name
- Stage 2: Find config files
- Stage 3: Execute config files

**Conclusion:** This is the right abstraction for the problem.

### 2. Plenary.nvim Dependency

All models specify `plenary.nvim` as dependency for async, path utilities, and file scanning.

**Conclusion:** Use plenary - it's the de facto standard in Neovim ecosystem.

### 3. Matcher Flexibility

All models support string/function/list polymorphism for matching.

**Conclusion:** This flexibility is essential for power users while keeping simple cases simple.

### 4. Context Object

All models use a context object flowing through all stages.

**Conclusion:** This pattern enables clean separation and extensibility.

### 5. JSON Caching with mtime

All models specify mtime-based caching for JSON with fallback to dirty cache on failure.

**Conclusion:** This is the right balance of performance and reliability.

### 6. Composite Finders

All models use composite finders to search both base config dir and project subdirectory.

**Conclusion:** This provides both convenience and flexibility.

### 7. Extension-Based Executor Routing

All models route files to executors based on file extension.

**Conclusion:** Simple, predictable, and extensible.

### 8. Configurable by Function

All models allow configuration values to be either static values or functions returning values.

**Conclusion:** This enables dynamic configuration without complex APIs.

## Divergent Design Decisions

### 1. Terminology

- **Opus:** detector/finder/executor
- **GLM:** project_resolver/finder/executor
- **K25:** project_finder/config_finder/executor
- **K2T:** project_discovery/finder/executor
- **Opus2:** project_name_finder/finder/executor_map

**Recommendation:** Use Opus's detector/finder/executor - clearest and most intuitive.

### 2. Strategy vs Function

- **K25:** String presets `'walk_up'`, `'composite'`
- **Opus, GLM, K2T:** Functions as primary customization
- **Opus2:** Full function replacement

**Recommendation:** Support both - presets for common cases, functions for advanced.

### 3. Matcher Composition

- **Opus:** Implicit OR in lists
- **GLM:** Explicit `or_matcher()`, `and_matcher()` helpers
- **K25:** Negation prefix `'not:pattern'`

**Recommendation:** Use Opus's implicit OR + GLM's helpers for clarity.

### 4. Configuration Directory Resolution

- **Opus, GLM, K25, K2T:** Function receives context
- **Opus2:** Function takes no arguments

**Recommendation:** Follow Opus/GLM - context provides project_name if needed.

### 5. JSON API Shape

- **Opus:** Module instance per project
- **GLM:** Direct methods on main module
- **K25:** Global `.json` accessor
- **Opus2:** Module-based (similar to Opus)

**Recommendation:** Use Opus/K25 pattern - clean module-based API.

## Technical Recommendations

### For Core Architecture

1. **Use Opus's detector/finder/executor terminology** - clearest separation of concerns
2. **Adopt K25's strategy string presets** - reduces boilerplate for common cases
3. **Support both presets and functions** - progressive complexity
4. **Follow Opus2's pragmatic simplification** - functions where they matter, presets where convenient
5. **Use GLM's helper functions** for matcher composition - makes composition explicit

### For Configuration API

1. **Support both static values and functions** universally
2. **Provide helper functions** for common patterns (or_matcher, and_matcher, walk_up_strategy)
3. **Use extension-based routing** with optional default handler
4. **Support negation patterns** for exclusion
5. **Make config_dir accept context** for dynamic resolution

### For Finder

1. **Default to composite finder** searching both base dir and project subdir
2. **Support both simple and composite strategies**
3. **Allow file_matcher reuse** via 'inherit' or explicit passing
4. **Deduplicate results** from composite finders
5. **Document search order** clearly (base files first, then subdir)

### For Executor

1. **Extension-based routing** with default fallback
2. **Built-in lua, vim, json executors**
3. **mtime-based caching for JSON** with dirty fallback
4. **Support custom executor registration**
5. **Per-file error isolation** - one failure doesn't stop others

### For Context Object

1. **Keep mutable** - allows stage communication and flexibility
2. **Core fields:** project_name, project_root, config_dir, cwd
3. **Allow user augmentation** via setup() config
4. **Document immutability expectations** (core should be treated as read-only)

### For Error Handling

1. **Isolated per-file execution** - failures logged but don't stop others
2. **Discovery failure:** warn and fallback to cwd name
3. **Finder failure:** silent (no config is valid)
4. **Executor failure:** error per file, continue with others
5. **Cache failure:** warn and reload on every access

### For Async Strategy

1. **Async for filesystem operations** (directory walking, file reading)
2. **Sync for script execution** (Lua/Vim inherently synchronous)
3. **Optional async for cache validation** (configurable)
4. **Don't force async everywhere** - adds complexity without benefit
5. **Use plenary.async** for async operations

### For Documentation

1. **Progressive disclosure** - Quick start first, architecture later
2. **Before/after examples** showing transformation
3. **Common use cases** (3-5 real examples)
4. **Minimal config first**, link to full reference
5. **Separate ARCHITECTURE.md** for deep dives

### For Testing

1. **Unit tests** for individual components
2. **Integration tests** for full pipeline
3. **Mock filesystem** for reliability
4. **Property-based tests** for matcher logic
5. **Performance benchmarks** for large projects

## File Structure Recommendation

Based on K25's detailed structure and others' insights:

```
nvim-project-config/
├── lua/
│   └── nvim-project-config/
│       ├── init.lua              # Main entry point, setup(), load()
│       ├── config.lua            # Configuration validation and defaults
│       ├── context.lua           # Context object factory
│       ├── cache.lua             # General caching utilities
│       └── matcher.lua           # Matcher normalization (string/function/list)
│
│       ├── detector/             # Stage 1: Project discovery
│       │   ├── init.lua         # Detector orchestration
│       │   ├── strategies/
│       │   │   ├── walk_up.lua  # Default: walk up looking for markers
│       │   │   ├── walk_down.lua
│       │   │   └── composite.lua
│       │   └── matchers.lua     # Built-in matchers
│       │
│       ├── finder/              # Stage 2: Config finding
│       │   ├── init.lua         # Finder orchestration
│       │   ├── strategies/
│       │   │   ├── simple.lua   # Single directory finder
│       │   │   └── composite.lua
│       │   └── matchers.lua     # File name matchers
│       │
│       └── executor/            # Stage 3: Execution
│           ├── init.lua         # Executor orchestration and registry
│           ├── strategies/
│           │   ├── script.lua   # Lua/Vim script execution
│           │   ├── composite.lua # Extension routing
│           │   └── json.lua    # JSON with mtime caching
│           └── cache.lua       # Cache management with validation
│
├── tests/
│   ├── detector_spec.lua
│   ├── finder_spec.lua
│   └── executor_spec.lua
│
├── doc/
│   ├── nvim-project-config.txt  # Vim help documentation
│   └── architecture.md        # Detailed architecture (separate from README)
│
└── README.md                   # User-facing documentation
```

## Next Steps

1. **Merge best features** from all proposals into unified specification
2. **Create prototype** of core three-stage pipeline
3. **Write tests** for critical paths (discovery, finding, execution)
4. **Iterate on API** based on real usage patterns
5. **Progressively implement** features based on P0/P1/P2 priorities
6. **Refine README** using progressive disclosure approach
7. **Document decisions** in ARCHITECTURE.md
