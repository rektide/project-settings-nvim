# Architectural Discussion Questions

This document captures open questions, trade-offs, and design decisions that need resolution before finalizing the architecture of `nvim-project-config`.

## Context

`nvim-project-config` is a library for Neovim that loads configuration based on the current project. It follows a three-stage pipeline:

1. **Project Discovery**: Find the project root and extract a name
2. **Configuration Discovery**: Locate configuration files
3. **Execution**: Run discovered files through appropriate executors

The following questions explore the boundaries, edge cases, and user experience of this system.

---

## Stage 1: Project Discovery

### Matcher Pattern Design

**Question 1.1**: The matcher pattern (string/function/list) is used throughout the system. Is this the right level of flexibility?

- Should we support additional pattern types (regex, glob patterns)?
- Should we allow explicit AND/OR composition rather than implicit OR in lists?
- Is the `not:` prefix sufficient for negation, or do we need a full boolean expression system?

**Question 1.2**: How should string matchers behave?

- Check for exact file name match?
- Check for directory existence (for `.git`)?
- Support wildcards (`.git*`, `package*.json`)?
- Case sensitivity (filesystem-dependent vs explicit)?

**Question 1.3**: What happens when multiple matchers match?

- Use the first match (closest to cwd)?
- Use the last match (highest in tree)?
- Allow explicit priority/ordering?
- Error on ambiguity?

**Question 1.4**: Name extraction strategies

- Is `dirname` sufficient, or do we need:
  - Reading from `package.json` "name" field?
  - Reading from `.git/config` remote URL?
  - Custom function receiving the matched path?
  - Pattern extraction (e.g., `^(.*)-project$`)?

**Question 1.5**: Fallback behavior

If no matcher finds a project:

- Use cwd name (current plan)?
- Use a default project name (`"default"`)?
- Error and require explicit configuration?
- Skip loading entirely?

**Question 1.6**: Walking strategy edge cases

- What if we hit filesystem boundaries (mount points)?
- What about permission errors (can't read parent)?
- Symlinks: follow or treat as barriers?
- Maximum walk depth to prevent infinite loops in pathological cases?

---

## Stage 2: Configuration Discovery

### Finder Composition

**Question 2.1**: Composite finder semantics

- Should child finders run in parallel (async) or sequence?
- If parallel, how do we handle race conditions in file discovery?
- Should we support conditional finders (skip if file exists, etc.)?

**Question 2.2**: Simple finder file scanning

- Do we scan recursively or just immediate directory?
- How do we handle nested project structures?
- Should we support exclusion patterns (`.gitignore`-style)?

**Question 2.3**: Matcher reuse in composite finders

The current design suggests reusing matchers by specifying `'inherit'`. Is this:

- Intuitive?
- Too implicit? Should we require explicit passing?
- Should we support "inherit with modifications"?

**Question 2.4**: File deduplication

When the composite finder merges results from multiple finders:

- How do we handle duplicate files found by different finders?
- Keep first occurrence? Last? Error?
- Should order matter for execution?

**Question 2.5**: Dynamic subdir resolution

The `subdir` parameter can be a function. What are the failure modes?

- Function returns `nil` → skip this finder?
- Function errors → fail entire discovery?
- Function returns absolute path → use as-is or resolve relative to config_dir?
- Function returns path outside config_dir → security concern?

### Configuration Loading Order

**Question 2.6**: Execution precedence

With the default finder looking in two places:

1. `config_dir/{project_name}.{lua,vim,json}`
2. `config_dir/{project_name}/`

What's the loading order?

- Root files first, then subdirectory files?
- Subdirectory files first, then root files (overrides)?
- Alphabetical within each location?
- Explicit dependency ordering (e.g., `init.lua` always first)?

**Question 2.7**: Extension priority

If we find both `rad.lua` and `rad.vim`:

- Load both?
- Prefer Lua over Vimscript?
- Configuration-controlled priority?
- Error on conflict?

---

## Stage 3: Execution

### Executor Architecture

**Question 3.1**: Extension routing complexity

The `by_extension` map can route to single or multiple executors. Is this necessary?

- When would you want multiple executors for one file?
- Should we support file-type detection (not just extension)?
- What about files without extensions?

**Question 3.2**: Executor failure handling

If an executor fails:

- Log and continue?
- Fail entire loading process?
- Mark file as failed and skip?
- Retry mechanism?

**Question 3.3**: Lua/Vim executor environment

What should be available to configuration files?

- Context object bound to `_G`?
- Custom sandboxed environment?
- Access to full Neovim API?
- Access to `nvim-project-config` internals?

**Question 3.4**: Lua loading mechanism

For `.lua` files, which loading strategy?

- `dofile()` - fresh load, no caching
- `loadfile()` with custom environment
- `require()` - uses package.loaded cache
- Custom implementation?

Trade-offs:
- `dofile`: No conflicts, but slower on reload
- `require`: Fast, but potential conflicts with user modules
- Custom: Most control, but more code

### JSON Executor Specifics

**Question 3.5**: JSON conflict resolution

When multiple files write to the same JSON key:

- Last-write-wins?
- Deep merge (objects only)?
- Error on conflict?
- Namespacing by source file (auto or manual)?

**Question 3.6**: mtime checking reliability

The plan is to check mtime before read/write operations. Edge cases:

- Filesystem doesn't support mtime (rare, but possible)?
- Clock skew between systems (shared filesystems)?
- Sub-second resolution needed?
- Race conditions between check and read?

**Question 3.7**: mtime failure strategy

If mtime checking fails:

- Treat cache as always dirty (reload every time)?
- Disable caching entirely?
- Warn user and continue with potentially stale data?
- Error and require manual intervention?

**Question 3.8**: JSON API design

For the programmatic interface:

```lua
json.get('editor.tabSize')  -- dot notation
json.set('editor.tabSize', 4)
```

Questions:

- Support array indexing (`'plugins[0].name'`)?
- Support creation of nested paths (`set('a.b.c', 1)` creates intermediate tables)?
- Type coercion (string "4" vs number 4)?
- Default values (`get(path, default)`)?
- Validation hooks (callback on set)?
- Batch operations (transaction-like)?

**Question 3.9**: JSON persistence

When does writing actually persist to disk?

- Immediately on every `set()`?
- Deferred/batched (flush on idle)?
- Explicit `flush()` required?
- Auto-flush on VimLeave?

**Question 3.10**: Multiple JSON files

If multiple JSON files are found (e.g., `rad.json` and `rad/settings.json`):

- Merge them?
- Treat as separate namespaces?
- Error?
- Configuration-controlled?

---

## Cross-Cutting Concerns

### Context Object

**Question 4.1**: Context mutability

The context object flows through all stages:

- Should it be immutable (safer, but less flexible)?
- Mutable (allows stages to communicate)?
- Hybrid: immutable core + mutable `meta` table?

**Question 4.2**: Context lifecycle

When is context created and destroyed?

- Created at setup, persists for session?
- Recreated on `reload()`?
- Different context per buffer (for buffer-local configs)?
- Global singleton vs instance-based?

**Question 4.3**: Context content

What belongs in context?

- Core: project_name, project_root, config_dir, cwd
- Runtime: loaded_files, execution_errors, timestamps
- User-defined: arbitrary data from setup()
- Computed: git_branch, file_count, etc.?

### Error Handling

**Question 4.4**: Failure granularity

How granular should error handling be?

- One error fails everything?
- Per-stage errors (discovery can fail but execution continues)?
- Per-file errors (one bad config doesn't break others)?
- Per-operation errors (individual `set()` calls can fail)?

**Question 4.5**: Error reporting

How do users learn about errors?

- `vim.notify()` messages?
- Silent logging (require user to check)?
- Return error object from `setup()`?
- Exception throwing (Lua error)?
- Error callback in config?

**Question 4.6**: Debugging support

What debugging facilities should we provide?

- Verbose mode (log all decisions)?
- Dry-run mode (find files but don't execute)?
- Interactive inspection of context?
- Tracing (which file loaded when)?

### Async Strategy

**Question 4.7**: Async boundaries

What operations must be async vs. can be sync?

| Operation | Sync | Async | Notes |
|-----------|------|-------|-------|
| Directory walking | | ✓ | Already planned |
| File stat (mtime) | ? | ? | Performance vs complexity |
| File reading | ? | ? | For JSON executor |
| Config file execution | ✓ | | Vimscript/Lua is sync |
| JSON writing | ? | ? | Auto-flush vs explicit |

**Question 4.8**: Async error handling

With `plenary.async`, errors in async operations:

- Propagate as Lua errors?
- Return success/failure tuple?
- Callback-based error handling?

**Question 4.9**: Startup impact

Neovim startup time is critical:

- Should `setup()` block or defer loading?
- Lazy loading options?
- Configurable delay/scheduler integration?

### Extensibility

**Question 4.10**: Plugin architecture

Should we support third-party extensions?

- Global registry for executors/matchers/finders?
- Hook system (pre/post discovery, pre/post execution)?
- Event system (`User` autocommands)?
- Just functions users can compose?

**Question 4.11**: Executor registration API

```lua
executor.register('toml', my_toml_executor)
```

Questions:

- Should this be global (affects all projects) or scoped?
- How to handle name conflicts?
- Can users override built-in executors?
- Type checking on registration?

### Security

**Question 4.12**: Arbitrary code execution

Configuration files execute Lua/Vimscript. Risks:

- Untrusted projects (cloned repos with malicious `.nvim.lua`)?
- Should we have a trust system (like nvim's built-in one)?
- Sandboxing options?
- User confirmation for first run?

**Question 4.13**: Path traversal

With user-defined functions for paths:

- Can `config_dir` function escape intended directories?
- Can `subdir` function navigate outside `config_dir`?
- Should we validate and sandbox paths?

---

## Configuration Design

### Configuration Structure

**Question 5.1**: Flat vs nested config

Current design is nested:

```lua
{
  project_finder = { strategy = 'walk_up', matchers = ... },
  config_finder = { strategy = 'composite', finders = ... },
  executor = { strategy = 'composite', by_extension = ... },
}
```

Alternative: flatter structure with prefixed keys:

```lua
{
  finder_strategy = 'walk_up',
  finder_matchers = { '.git' },
  loader_strategy = 'composite',
  -- etc.
}
```

Which is more ergonomic?

**Question 5.2**: Preset system

The design mentions "preset names" like `'walk_up'`, `'composite'`. Questions:

- How many built-in presets?
- Can users define custom presets?
- Preset composition/inheritance?
- Preset documentation discoverability?

**Question 5.3**: Validation

Should we validate configuration at `setup()`?

- Strict validation (error on unknown keys)?
- Lenient (ignore unknown, warn)?
- Runtime validation (fail when used)?
- Schema-based validation?

**Question 5.4**: Defaults and overrides

What's the merging strategy for configuration?

- Deep merge (current + user = merged)?
- Shallow merge (user replaces entire sections)?
- Explicit override markers?
- Function-based customization (receive defaults, return modified)?

### User Customization Patterns

**Question 5.5**: Common customization scenarios

What are the 80% use cases we should optimize for?

1. Just use defaults (change nothing)
2. Add additional matchers (`.git` + `package.json`)
3. Change config directory location
4. Add custom file types (`.toml`, `.yaml`)
5. Per-project override logic

Are we optimizing for these?

**Question 5.6**: Function vs configuration

For customization, when should users provide:

- Configuration data (tables)?
- Functions?
- Both (configuration with function overrides)?

Example: `matchers = { '.git' }` vs `matchers = my_custom_function`

---

## Integration

### Neovim Ecosystem

**Question 6.1**: Autocommand integration

When should project config load?

- On `VimEnter`?
- On `DirChanged`?
- On buffer enter (for buffer-local config)?
- Manual only?

**Question 6.2**: LSP integration

Should we integrate with LSP?

- Automatically detect project root from LSP?
- Provide project config to LSP settings?
- Keep separate concerns?

**Question 6.3**: Plugin manager integration

Common plugin managers (lazy.nvim, packer, etc.):

- Special integration needed?
- Lazy-loading considerations?
- Dependency declaration (plenary)?

**Question 6.4**: Telescope/fzf-lua integration

Should we provide pickers?

- Select project from list?
- Browse available project configs?
- Preview what will be loaded?

### File Watching

**Question 6.5**: Auto-reload on file changes

Should we watch config files and auto-reload?

- Use `libuv` fs watchers?
- Performance impact?
- Debouncing/throttling?
- Opt-in or default?

**Question 6.6**: Watch scope

What should we watch?

- Just the loaded config files?
- Entire config directory?
- Project root (in case matchers change)?
- User's choice?

---

## README User Experience: First Contact

The README is the **first and often only** touchpoint for developers evaluating `nvim-project-config`. Its clarity, structure, and tone determine whether a developer invests time in trying the library or moves on.

### First Impressions

**Question R.1**: Opening hook

The README starts with:

```markdown
# nvim-project-config

> Per-project Neovim configuration with a pluggable, async-first architecture.
```

Is this compelling? Does it answer "why should I care?" within 3 seconds?

- Should we lead with a problem statement instead?
- Is "async-first architecture" meaningful to the target audience?
- Should we show a concrete example immediately?

**Question R.2**: The "Longer Introduction" balance

The current longer introduction:

> Every project is different. Your Neovim configuration should adapt to where you're working...

Is this:
- Too abstract? Needs concrete pain points?
- Too long? Should be one sentence?
- Missing the "aha moment" that makes it click?

**Question R.3**: Quick start prominence

Quick start appears after architecture. Should it be:
- First thing after intro (get users running immediately)?
- Where it is (understand before using)?
- Collapsible or linked from intro?

### Architecture Explanation

**Question R.4**: Mermaid diagram complexity

The architecture diagram shows three stages with subgraphs. Is this:
- Too detailed for first contact?
- Helpful mental model or overwhelming?
- Missing key information (data flow arrows, error paths)?

**Question R.5**: Stage explanations

Each stage has a paragraph. Are these:
- Too abstract? Need concrete examples?
- Too technical? Missing the "why"?
- Properly sequenced (build understanding incrementally)?

### Configuration Documentation

**Question R.6**: Full configuration overwhelm

The "Full Configuration" section is extensive (~150 lines). Does this:
- Provide clarity through completeness?
- Scare users away with complexity?
- Need progressive disclosure (basic → advanced)?

**Question R.7**: Configuration examples

Configuration examples use the internal API:

```lua
project_finder = find_project_default,
config_finder = find_config_composite,
```

Should we:
- Use string presets instead (`'walk_up'`, `'composite'`)?
- Show both simple and advanced forms?
- Explain what these functions do?

**Question R.8**: The "Matcher Flexibility" section

Matchers are documented separately with type flexibility. Is this:
- Essential core knowledge?
- Implementation detail that could be footnoted?
- Needs earlier placement (fundamental concept)?

### Navigation and Discovery

**Question R.9**: Table of contents

The README lacks a TOC. Is this:
- Acceptable for this length?
- Missing navigation aid?
- Better as a collapsible TOC?

**Question R.10**: Section ordering

Current order:
1. Intro (short + long)
2. Architecture
3. Quick Start
4. Configuration
5. File Structure
6. Detailed Architecture
7. Usage Examples
8. API Reference

Is this logical? Alternative:
1. Intro
2. Quick Start (get running)
3. Usage Examples (see value)
4. Configuration (customize)
5. Architecture (understand internals)
6. API Reference

**Question R.11**: Deep dive sections

"Detailed Architecture" has more diagrams. For a README, should we:
- Move this to a separate ARCHITECTURE.md?
- Keep inline but collapsible?
- Current placement is fine?

### Tone and Accessibility

**Question R.12**: Technical vocabulary

Terms used:
- "pluggable"
- "async-first"
- "composite pattern"
- "mtime caching"
- "Context object"

Is the vocabulary:
- Appropriate for Neovim users?
- Accessible to Lua beginners?
- Need a glossary?

**Question R.13**: Assumed knowledge

The README assumes familiarity with:
- Neovim Lua configuration
- `vim.fn.stdpath()`
- `require()`
- Neovim's module system

Should we:
- Add links to Neovim/Lua resources?
- Include a "Prerequisites" section?
- Current level is appropriate?

### Actionability

**Question R.14**: Call to action

The README ends with "License". Does it need:
- Installation instructions (currently missing)?
- Link to examples repo?
- "Getting Help" section?
- Contributing guidelines summary?

**Question R.15**: Copy-paste readiness

Are the code examples:
- Immediately runnable?
- Self-contained?
- Marked as "example" vs "production-ready"?

### Visual Design

**Question R.16**: Markdown formatting

- Too many headings? Too few?
- Code blocks properly language-tagged?
- Consistent use of bold, italics, code?
- Emoji usage appropriate for the project?

**Question R.17**: Mermaid diagrams

- Will they render correctly on GitHub?
- Are there too many (4 total)?
- Should they be SVGs instead?
- Color scheme accessible?

---

## Implementation Considerations

### Dependencies

**Question I.1**: Required dependencies

- `plenary.nvim` (for async) - mandatory or optional?
- Any other dependencies?
- How to handle missing dependencies gracefully?

**Question I.2**: Neovim version support

- Minimum version (0.7? 0.8? 0.9? nightly)?
- Feature detection vs version checks?
- Deprecation policy?

### Testing Strategy

**Question I.3**: Test scope

What needs testing?

- Unit tests for individual components?
- Integration tests (full pipeline)?
- Property-based testing (matcher logic)?
- Performance benchmarks?

**Question I.4**: Test environment

- Use `busted` (Lua standard)?
- Use `plenary.test_harness` (Neovim standard)?
- CI on multiple Neovim versions?
- Mock filesystem or temp directories?

**Question I.5**: Testing async code

- How to test async operations deterministically?
- Mock `plenary.async` or use real async?
- Timeout handling in tests?

### Performance

**Question I.6**: Startup time budget

- What's acceptable latency for `setup()`?
- Should we defer loading if cwd is large?
- Profiling hooks?

**Question I.7**: Memory usage

- Context object lifetime?
- JSON cache eviction?
- Handling large configuration directories?

### Documentation Maintenance

**Question I.8**: Code-doc synchronization

- How to keep README and code in sync?
- Generate docs from code annotations?
- Single source of truth for configuration schema?

**Question I.9**: Versioning

- Semver?
- Breaking change policy?
- Migration guides?

---

## Open Questions Summary

### Must Decide Before Implementation

1. **Matcher pattern**: Finalize the string/function/list system
2. **Lua loading**: `dofile` vs `require` vs custom
3. **JSON conflict resolution**: Last-write, merge, or namespacing
4. **Context mutability**: Immutable vs mutable
5. **Async boundaries**: Which operations must be async

### Can Iterate On

1. Additional matcher types (regex, glob)
2. File watching for auto-reload
3. Telescope integration
4. Preset system expansion
5. Performance optimizations

### README Critical

1. Opening hook and first impression
2. Configuration section complexity
3. Section ordering
4. Vocabulary accessibility
5. Copy-paste ready examples

---

## Next Steps

To finalize the architecture:

1. **Prioritize questions**: Which are blockers vs nice-to-have?
2. **Prototype critical paths**: Implement discovery and execution with test cases
3. **Validate ergonomics**: Have potential users review the README
4. **Document decisions**: For each question answered, update design doc
5. **Iterate**: Implement → test → document → refine

---

*This document is a living artifact. Add new questions as they arise, and mark resolved questions with their decisions and rationale.*
