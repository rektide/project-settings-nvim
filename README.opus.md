# nvim-project-config

> Per-project configuration for Neovim, loaded automatically based on your working directory.

## Install

```lua
-- lazy.nvim
{ "rektide/nvim-project-config" }
```

## Quick Start

```lua
require("nvim-project-config").setup()
```

With default settings, opening a file in `~/src/rad-project/test/foo.lua` will:
1. Walk up to find `rad-project` as your project root
2. Look for config files in `~/.config/nvim/projects/`
3. Execute `rad-project.lua`, `rad-project.vim`, or load `rad-project.json`

## Configuration Files

Place project configs in your config directory (default: `~/.config/nvim/projects/`):

```
~/.config/nvim/projects/
├── rad-project.lua      # Lua config for rad-project
├── rad-project.vim      # Vimscript config
├── rad-project.json     # Persistent JSON settings
└── rad-project/         # Subdirectory for additional configs
    ├── init.lua
    └── keymaps.lua
```

### Lua/Vim Configs

Executed when entering the project:

```lua
-- ~/.config/nvim/projects/rad-project.lua
vim.opt_local.tabstop = 4
vim.opt_local.shiftwidth = 4
vim.keymap.set("n", "<leader>t", ":!npm test<CR>", { buffer = true })
```

### JSON Settings

Persistent key-value storage per project:

```lua
local npc = require("nvim-project-config")

-- Read a setting
local last_file = npc.get("last_opened_file")

-- Write a setting (persists to disk)
npc.set("last_opened_file", vim.fn.expand("%"))

-- Bulk read
local settings = npc.json()
```

JSON files are cached in memory and automatically reloaded when the file changes on disk.

## Setup Options

```lua
require("nvim-project-config").setup({
  -- Where to find project configs
  -- String or function(context) -> string
  config_dir = vim.fn.stdpath("config") .. "/projects",

  -- How to determine project name from cwd
  -- Function receives cwd, returns project name
  project_resolver = function(cwd)
    -- Default: walks up looking for .git, package.json, etc.
    -- Falls back to directory name
  end,

  -- What files to look for
  -- Single or list of: string patterns or matcher functions
  file_patterns = { "%.lua$", "%.vim$", "%.json$" },

  -- Custom finder: receives context, returns list of files
  finder = function(ctx)
    -- ctx.project_name - detected project name
    -- ctx.config_dir   - resolved config directory
  end,

  -- Custom executor: receives context and file list
  executor = function(ctx, files)
    -- Process found config files
  end,
})
```

## Matching Patterns

All matching options accept flexible input:

```lua
-- Single string
file_patterns = "%.lua$"

-- List of strings
file_patterns = { "%.lua$", "%.vim$" }

-- Matcher function
file_patterns = function(filename) return filename:match("%.lua$") end

-- Mixed list
file_patterns = { "%.lua$", function(f) return f == "init.vim" end }
```

## Context Object

All configurable functions receive a context object:

```lua
{
  project_name = "rad-project",  -- Detected project name
  config_dir = "/home/user/.config/nvim/projects",  -- Resolved config dir
  cwd = "/home/user/src/rad-project/test",  -- Original working directory
  project_root = "/home/user/src/rad-project",  -- Detected project root
}
```

## API

```lua
local npc = require("nvim-project-config")

npc.setup(opts)           -- Initialize with options
npc.project_name()        -- Get current project name
npc.reload()              -- Re-run config detection and loading
npc.get(key)              -- Read from project JSON
npc.set(key, value)       -- Write to project JSON
npc.json()                -- Get full JSON table
```

## License

MIT
