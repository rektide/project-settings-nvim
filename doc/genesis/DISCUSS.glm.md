# Architecture & Design Discussion

This document collects open questions and discussion points for nvim-project-config. We're using this to explore design decisions before committing to implementation.

## Architecture Questions

### Project Name Resolution

1. **Git root vs .git location**: When we find a `.git` directory at `/home/user/src/my-project/app/.git`, should the project name be:
   - `my-project` (the git repository root)?
   - `app` (the immediate parent of `.git`)?
   - Configurable?

2. **Nested repositories**: If there's a git repo inside another git repo (e.g., monorepo with submodule), how do we decide which one represents "the project"?

3. **Workspace managers**: Should we detect and integrate with workspace managers like:
   - `projections.nvim` / `vim.projectionist`
   - Neovim's built-in workspace (`vim.lsp.buf.list_workspace_folders`)
   - tmuxinator / direnv / nix-shell integration?

4. **Caching project names**: Should we cache the resolved project name in a buffer variable or vim global? What happens when you do `:cd` to another directory?

5. **No git found**: In a non-git project (or in the git root itself), what's the most useful fallback behavior?
   - Use directory basename always?
   - Have a marker system (`.project`, `package.json`, `Cargo.toml`)?
   - Allow user-specified strategies per directory?

### Configuration Discovery & Execution

6. **Multiple config files**: If both `projects/my-project.lua` and `projects/my-project/my-project.lua` exist, what happens?
   - Load both in order?
   - Warn on duplicates?
   - Prefer one over the other?
   - What's the execution order (dot directory first or last)?

7. **Extension ambiguity**: How do we handle files that could be processed by multiple executors (e.g., `config.json` that could also be lua-processed as data)?
   - First match wins?
   - All matching executors run?
   - Explicit type metadata?

8. **Execution failures**: What happens when:
   - A Lua file has a syntax error?
   - A Vim script fails?
   - JSON is malformed?
   - Continue to load other files? Abort entirely?

9. **Environment context**: Should executors receive any metadata about:
   - File path they're executing?
   - Project root directory?
   - Environment variables (NODE_ENV, RAILS_ENV)?

10. **File watcher integration**: Should we integrate with existing file watchers:
    - `nvim-autocommands` DirChanged events?
    - `plenary.job` for reload on file change?
    - Provide hooks for manual reload?

### JSON Layer

11. **JSON API design**: Is the proposed API shape good?
    ```lua
    get_json('lsp.format_on_save')      -- dot notation
    get_json()['lsp']['format_on_save']  -- nested access
    ```
    Or should we prefer:
    ```lua
    local json = project_config.get_json()
    json.lsp.format_on_save
    ```

12. **Multi-project JSON access**: Can/should users access JSON configs for *other* projects?
    - `project_config.get_json('other-project', 'path')`
    - Or keep the API scoped to current project only?

13. **JSON file location**: Is `projects/my-project/my-project.json` the right default?
    - Or `projects/my-project/config.json`?
    - Or both supported?

14. **Dirty cache behavior**: When `os.time()` precision is too coarse (or mtime fails entirely):
    - Always reload on read?
    - Always reload on write?
    - Both?
    - Expose a `force_reload` flag?

15. **JSON mutation API**: Should we support:
    - Field deletion (`delete_json('lsp')`)?
    - Merging (`merge_json({ new: settings })`)?
    - Or just get/set primitives?

### Matcher & Routing System

16. **Matcher power vs complexity**: Are matchers *too* powerful? Should we:
    - Keep them simple (strings, glob patterns)?
    - Or support full functions (current design)?

17. **Router fallback**: When a file extension doesn't match any router entry:
    - Skip the file silently?
    - Log a warning?
    - Error out?

18. **Router composition**: Can routers be nested or composed?
    - A default router with user overrides?
    - Router priority system?

### Async vs Sync

19. **File watching**: Plenary async is great, but Neovim's event model is largely synchronous. Where does async actually help?
    - Initial project detection (might search up many directories)?
    - JSON file watching?
    - Or is the complexity not worth it?

20. **Initial load timing**: When should configs load:
    - At `VimEnter` (after all plugins loaded)?
    - At startup, but async?
    - Manually triggered?

## User Experience & Ergonomics (The README)

### Onboarding Flow

21. **The "aha" moment**: Does the architecture diagram or quick start hit first? What's the clearest way to communicate the core concept to someone scanning the docs?

22. **Prerequisite assumptions**: What should we assume users know?
    - Lua basics?
    - Neovim config structure (init.lua)?
    - Or start from absolute zero?

23. **Motivation clarity**: Do we clearly answer "why would I want this?" vs "what is this?" Are the use cases compelling and concrete?

### Configuration Complexity

24. **Configuration overload**: Does the full default configuration overwhelm or illuminate? Do we need:
    - A layered config section (basic → intermediate → advanced)?
    - Interactive examples vs complete config dumps?

25. **Finder/Executor mental model**: Are the concepts of "finder → context → executor" intuitive? Or is there a simpler metaphor that lands better?

26. **Matcher system complexity**: The matcher documentation is fairly involved. Is this power worth the conceptual load? Or would most users be happier with a simpler convention-over-configuration approach?

### Documentation Structure

27. **Learning path**: Is there a clear progression:
    - Quick start → basic customization → advanced → API reference?
    - Do people know where to look if they have a specific problem?

28. **Code examples**: Do the examples feel:
    - Realistic to actual workflows?
    - Complete enough to copy-paste?
    - Sufficiently commented to understand *why* you'd do this?

29. **Architecture diagrams**: The mermaid diagrams help, but:
    - Are they at the right level of abstraction?
    - Do they need more context labels (e.g., what data flows between components)?
    - One overview, or multiple diagrams for each subsystem?

### Troubleshooting & Debugging

30. **Debug story**: When something doesn't work, where do people start?
    - Should we expose a `:NvimProjectConfig debug` command?
    - What gets logged and where?
    - How to trace the discovery process ("why didn't my config load?")?

31. **Common failure modes**: What will trip people up most often?
    - Wrong file naming conventions?
    - Project name mis-detection?
    - JSON file permissions?

### The "First 5 Minutes" Experience

32. **Copy-paste success rate**: Can someone copy the Quick Start and have it work _immediately_?
    - Does it require creating dummy files?
    - Does it require understanding the full system first?

33. **Mental model mismatch**: When someone's mental model of "project config" doesn't match our architecture (e.g., they expect a simple `config.json` file), do we help them bridge the gap or do we just show the "right way"?

34. **Delight factor**: What could make the first experience actually delightful?
    - A demo mode that shows what would be loaded?
    - Tab completion for config keys?
    - Example configs that feel like real projects?

### Philosophical User Experience Questions

35. **Target audience**:
   - Plugin ecosystem developers who want to consume project config?
   - End users who just want per-project settings?
   - Both, and if so, which path does the README prioritize?

36. **Complexity surface area**: Is this library trying to:
   - Be a simple "just works" project config loader?
   - A framework for building project config systems?
   - Something in between, and is that a coherent vision or a compromise?

37. **Convention vs Configuration**:
   - How much should be reasonable defaults vs explicit control?
   - Are we erring toward "make common cases simple" or "make everything possible"?

38. **The progressive disclosure problem**:
   - You don't want to hide advanced features from advanced users
   - You don't want to overwhelm beginners with options they don't need
   - Is the current structure achieving this balance?

39. **Conceptual vocabulary**: Do we introduce too many new concepts at once?
   - Finder, executor, matcher, router, context object
   - Is the terminology clear, or could we rename things to be more instantly understandable?

40. **The "what if I don't want any of this"** story:
   - What's the migration path from existing ad-hoc project config solutions?
   - What's the uninstall story if someone adopts it and regrets it?

## System Design (Broader)

### Library Philosophy

41. **Opinions about project structure**: Our default strategies assume a certain worldview (git repositories, certain directory structures). How opinionated should we be, and how easy should it be to adopt alternative worldviews?

42. **The boundary problem**: What belongs in `nvim-project-config` vs what should be plugins consuming it?
   - File format loaders (JSON, YAML, TOML)?
   - LSP integration?
   - Where's the line?

43. **Testing philosophy**: How do we test something so deeply integrated with the filesystem and user's Neovim config?
   - Unit tests for individual components?
   - Integration tests with fake file trees?
   - How much behavior is untestable?

### Performance & Footprint

44. **Startup cost**: What's the acceptable cost for project detection + config loading?
   - Is 10ms too much? 50ms? 100ms?
    - How do we measure this in practice?

45. **Memory footprint**: JSON configs get cached. What's the expected size?
   - Do we need bounds or eviction?
   - What if someone configures 50 projects with large JSON files?

46. **File system thrashing**: Walking up directories to find `.git` could be expensive in deep directory trees. Do we:
   - Cache results per session?
   - Add depth limits?
   - Optimize the default strategy?

### Ecosystem Integration

47. **Neovim version support**: What minimum version do we target?
   - LuaJIT 2.1 (built into Neovim)?
   - Which Neovim API features can we rely on?

48. **Plugin ecosystem goals**: Should this be a standalone library, or part of a larger ecosystem?
   - Should we provide hooks that other plugins can tap into?
   - Event system for when config loads/reloads?

49. **Cross-platform considerations**: Windows vs macOS vs Linux differences:
   - Path separators
   - File system behaviors
   - Git detection quirks

### Future Extensions

50. **Remote projects**: How would this work with remote development (sshfs, tramp, neovim-remote)?
    - Does project detection work over remote fs?
    - Should we limit loading or add delays?

51. **Project templates**: Should we support:
    - Built-in config templates for common project types (React, Rails, Rust)?
    - A schema or conventions for community templates?

52. **Validation**: Should we support:
    - JSON schema validation for configs?
    - Type checking for Lua configs?
    - Or is that outside our scope?

53. **Editor integration**: Should we provide:
    - LSP completions for `get_json()` calls?
    - Hover docs for config keys?
    - Or is that consumer library work?

---

## Questions for You (The Human)

What resonates with you from here? What feels like the right next step?

Some possible directions:

1. **Pick 3-5 highest-priority questions** and we can work through them first — maybe pick a mix of architecture and UX?

2. **Start with the README/UX section** — if we don't nail the developer experience, the architecture details matter less

3. **Prototype the simplest thing** — get a MVP running with minimal features, see how the design feels in practice

4. **Refining the architecture diagram** — maybe we need more diagrams, or different diagrams, to clarify the system

5. **Alternative approaches** — before committing, should we explore other strategies for project discovery or config loading?

What feels most valuable to you right now?