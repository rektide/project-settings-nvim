# nvim-project-config

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![NPM Version](https://img.shields.io/npm/v/nvim-project-config)](https://www.npmjs.com/package/nvim-project-config)

> Load Neovim configuration based on your current project directory

## Table of Contents

- [Background](#background)
- [Install](#install)
- [Usage](#usage)
  - [Basic Setup](#basic-setup)
  - [Configuration File Types](#configuration-file-types)
  - [JSON Configuration with Programmatic Access](#json-configuration-with-programmatic-access)
  - [Advanced Configuration](#advanced-configuration)
- [API](#api)
- [Contributing](#contributing)
- [License](#license)

## Background

Managing Neovim configuration across different projects can be challenging. You might want different LSP settings, buffer options, or keybindings depending on whether you're working on a web application, a backend service, or a documentation project.

`nvim-project-config` solves this by automatically detecting your project name and loading project-specific configuration files. It supports multiple configuration formats and provides a flexible, pluggable architecture for finding and executing configuration.

When you're in `~/src/rad-project/test`, `nvim-project-config` will:
1. Identify the project name (`rad`) using a configurable directory walking strategy
2. Locate configuration files in your config directory
3. Execute the appropriate configuration based on file type

## Install

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "rektide/nvim-project-config",
  config = function()
    require("nvim-project-config").setup()
  end
}
```

Using [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use {
  "rektide/nvim-project-config",
  config = function()
    require("nvim-project-config").setup()
  end
}
```

## Usage

### Basic Setup

The simplest configuration requires no setup at all:

```lua
require("nvim-project-config").setup()
```

This will:
- Look for configuration files in `~/.config/nvim/projects/`
- Detect project names by walking up the directory tree
- Load files matching `.{lua,vim,json}` with the project name

If you're in `~/src/my-cool-app/src/components`, the project name will be `my-cool`, and `nvim-project-config` will look for:
- `~/.config/nvim/projects/my-cool.lua`
- `~/.config/nvim/projects/my-cool.vim`
- `~/.config/nvim/projects/my-cool.json`

### Configuration File Types

#### Lua Configuration

Create `~/.config/nvim/projects/my-cool.lua`:

```lua
return {
  -- Configure LSP
  lsp = {
    servers = {
      tsserver = {},
      eslint = {},
    }
  },

  -- Set buffer options
  opts = {
    shiftwidth = 2,
    tabstop = 2,
    expandtab = true,
  },

  -- Define keybindings
  keys = {
    { "<leader>rf", function() require("telescope.builtin").find_files() end, desc = "Find files" },
  }
}
```

The configuration will be automatically applied when you enter files in that project.

#### Vimscript Configuration

Create `~/.config/nvim/projects/my-cool.vim`:

```vim
" Set local options
setlocal shiftwidth=2
setlocal tabstop=2
setlocal expandtab

" Define commands
command! -buffer RunTests :lua require("my-cool.tests").run()
```

#### JSON Configuration

Create `~/.config/nvim/projects/my-cool.json`:

```json
{
  "lsp": {
    "servers": ["tsserver", "eslint"]
  },
  "opts": {
    "shiftwidth": 2,
    "tabstop": 2,
    "expandtab": true
  }
}
```

### JSON Configuration with Programmatic Access

JSON configuration files support runtime reading and writing with automatic cache invalidation:

```lua
-- Get the project config object
local proj_config = require("nvim-project-config")

-- Read a value from the JSON config
local settings = proj_config.get_json_config("my-cool")
print(settings.lsp.servers)  -- => { "tsserver", "eslint" }

-- Write a value to the JSON config (automatically saves to file)
proj_config.set_json_config("my-cool", "lsp.servers", function(servers)
  table.insert(servers, "tailwindcss")
  return servers
end)

-- Or set a simple value
proj_config.set_json_config("my-cool", "debug.enabled", true)

-- The cache automatically reloads if the file is modified externally
```

The JSON executor monitors file modification times and reloads the configuration when needed. If file time tracking fails on your system, it falls back to reloading on every access.

### Advanced Configuration

#### Custom Config Directory

Change where project configurations are stored:

```lua
require("nvim-project-config").setup({
  config_dir = "~/.config/my-nvim-projects",
  -- or use a function
  config_dir = function(ctx)
    return vim.fn.expand("~/.config") .. "/nvim/projects/" .. ctx.project_name
  end
})
```

#### Custom Project Name Detection

Override the default directory walking strategy:

```lua
require("nvim-project-config").setup({
  project_name_finder = function()
    -- Use the parent directory name
    return vim.fn.fnamemodify(vim.fn.getcwd(), ":t")
  end
})
```

Or implement a custom walking strategy:

```lua
require("nvim-project-config").setup({
  project_name_finder = function()
    local cwd = vim.fn.getcwd()
    local path = cwd

    while path ~= "/" do
      -- Check for common project markers
      for _, marker in ipairs({ ".git", "package.json", "Cargo.toml", "go.mod" }) do
        if vim.fn.filereadable(path .. "/" .. marker) == 1 then
          return vim.fn.fnamemodify(path, ":t")
        end
      end
      path = vim.fn.fnamemodify(path, ":h")
    end

    return vim.fn.fnamemodify(cwd, ":t")  -- Fallback to current directory
  end
})
```

#### Custom File Finders

Configure which files are loaded and from where:

```lua
require("nvim-project-config").setup({
  finder = function(ctx)
    -- Custom finder that looks in multiple locations
    local config_dir = ctx.config_dir
    local project = ctx.project_name

    return {
      -- Check for project-specific overrides
      config_dir .. "/overrides/" .. project .. ".lua",
      config_dir .. "/overrides/" .. project .. ".vim",
      -- Fall back to base config
      config_dir .. "/base/" .. project .. ".lua",
    }
  end
})
```

Using the built-in finder with custom matchers:

```lua
require("nvim-project-config").setup({
  finder = function(ctx)
    local base_finder = require("nvim-project-config.finders").simple
    return {
      base_finder(ctx, "."),
      base_finder(ctx, "common"),
      base_finder(ctx, ctx.project_name),
    }
  end,

  -- Custom file matching
  file_matcher = function(project_name, filename)
    -- Match project-name.*, or any file starting with "config_"
    if filename:match("^" .. project_name .. "%.") then
      return true
    end
    if filename:match("^config_") then
      return true
    end
    return false
  end
})
```

#### Custom Executors

Define how configuration files are executed:

```lua
require("nvim-project-config").setup({
  executor_map = {
    -- Only execute .lua and .vim files, skip JSON
    ["lua"] = require("nvim-project-config.executors").lua_vim,
    ["vim"] = require("nvim-project-config.executors").lua_vim,
  }
})
```

Or use matchers for more complex routing:

```lua
require("nvim-project-config").setup({
  executor_map = {
    -- Use custom executor for files matching a pattern
    {
      match = function(filename)
        return filename:match("test_.*%.lua$")
      end,
      executor = require("nvim-project-config.executors").test_runner,
    },
    -- Default for everything else
    require("nvim-project-config.executors").lua_vim,
  }
})
```

#### Multiple Executors Per File

Run multiple executors for the same file type:

```lua
require("nvim-project-config").setup({
  executor_map = {
    ["lua"] = {
      require("nvim-project-config.executors").lua_vim,
      require("nvim-project-config.executors").validator,  -- Validate after loading
    },
    ["vim"] = {
      require("nvim-project-config.executors").lua_vim,
    },
  }
})
```

#### Complete Custom Configuration Example

```lua
require("nvim-project-config").setup({
  -- Where to find project configs
  config_dir = "~/.config/nvim/projects",

  -- How to detect the project name
  project_name_finder = function()
    local cwd = vim.fn.getcwd()
    local parts = vim.split(cwd, "/")
    return parts[#parts]
  end,

  -- How to find config files
  finder = function(ctx)
    local finder = require("nvim-project-config.finders").simple
    return {
      finder(ctx, "."),                    -- ~/.config/nvim/projects/.*
      finder(ctx, ctx.project_name),      -- ~/.config/nvim/projects/my-project/.*
    }
  end,

  -- How to match files
  file_matcher = function(project, file)
    return vim.startswith(file, project .. ".")
  end,

  -- How to execute found files
  executor_map = {
    ["lua"] = require("nvim-project-config.executors").lua_vim,
    ["vim"] = require("nvim-project-config.executors").lua_vim,
    ["json"] = {
      require("nvim-project-config.executors").json,
      require("nvim-project-config.executors").json_validator,
    },
  },
})
```

## API

### `setup(opts)`

Initialize `nvim-project-config` with custom options.

**Parameters:**
- `opts` (table): Configuration options
  - `config_dir` (string|function): Path to config directory or function returning path. Default: `vim.fn.stdpath("config") .. "/projects"`
  - `project_name_finder` (function): Function that returns the project name. Default: Walks up directory tree and uses first directory name
  - `finder` (function): Function that receives context object and returns list of files to load
  - `file_matcher` (function|table): Function or matcher that determines if a file should be loaded
  - `executor_map` (table): Map of file extensions to executors. Can be single executor, list, or matcher

**Context object:**
- `project_name` (string): The detected project name
- `config_dir` (string): The resolved config directory path

### `load()`

Manually trigger configuration loading for the current directory.

```lua
require("nvim-project-config").load()
```

### `get_context()`

Get the current context object (project name and config directory).

```lua
local ctx = require("nvim-project-config").get_context()
print(ctx.project_name)  -- => "my-project"
print(ctx.config_dir)    -- => "/home/user/.config/nvim/projects"
```

### `get_json_config(project_name)`

Get the parsed JSON configuration for a project.

**Returns:** The parsed JSON object or `nil` if not found.

```lua
local config = require("nvim-project-config").get_json_config("my-project")
if config then
  print(config.lsp.servers[1])
end
```

### `set_json_config(project_name, key_path, value)`

Set a value in the JSON configuration. Supports nested keys using dot notation or a function.

**Parameters:**
- `project_name` (string): Name of the project
- `key_path` (string): Dot-separated key path (e.g., `"lsp.servers"`)
- `value` (any|function): Value to set, or function that receives current value and returns new value

```lua
-- Set a simple value
require("nvim-project-config").set_json_config("my-project", "debug.enabled", true)

-- Modify an array
require("nvim-project-config").set_json_config("my-project", "lsp.servers", function(servers)
  table.insert(servers, "tailwindcss")
  return servers
end)

-- Set nested value
require("nvim-project-config").set_json_config("my-project", "formatter.options.tabWidth", 2)
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT © [rektide de la faye](https://github.com/rektide)
