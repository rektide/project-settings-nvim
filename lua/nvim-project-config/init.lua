--- Main entry point for nvim-project-config
--- @module nvim-project-config

local pipeline = require("nvim-project-config.pipeline")
local watchers = require("nvim-project-config.watchers")
local dir_cache = require("nvim-project-config.cache.directory")
local file_cache = require("nvim-project-config.cache.file")

local walk = require("nvim-project-config.stages.walk")
local detect = require("nvim-project-config.stages.detect")
local find_files = require("nvim-project-config.stages.find_files")
local execute = require("nvim-project-config.stages.execute")

local lua_exec = require("nvim-project-config.executors.lua")
local vim_exec = require("nvim-project-config.executors.vim")
local json_mod = require("nvim-project-config.executors.json")

local M = {}

M.ctx = nil

local function make_reactive_table(on_change, parent_path)
  parent_path = parent_path or {}
  local data = {}
  local mt = {
    __index = function(_, key)
      return data[key]
    end,
    __newindex = function(_, key, value)
      vim.notify("Reactive table __newindex: key=" .. tostring(key) .. " value=" .. tostring(value), vim.log.levels.INFO)
      if type(value) == "table" and getmetatable(value) == nil then
        local path = vim.list_extend({}, parent_path)
        table.insert(path, key)
        value = make_reactive_table(on_change, path)
      end
      data[key] = value
      vim.notify("Calling on_change()", vim.log.levels.INFO)
      on_change()
    end,
  }
  return setmetatable({}, mt)
end

local function default_on_match(ctx, path)
  if ctx.project_root then
    return
  end
  ctx.project_root = path
  local name = vim.fn.fnamemodify(path, ":t")
  if name == "" then
    name = vim.fn.fnamemodify(path, ":h:t")
  end
  ctx.project_name = name
end

local function create_default_pipeline()
  return {
    walk({ direction = "up" }),
    detect({
      matcher = { ".git", ".hg", "Makefile", "package.json" },
      on_match = default_on_match,
    }),
    find_files({ extensions = { ".lua", ".vim", ".json" } }),
    execute({
      router = {
        lua = lua_exec,
        vim = vim_exec,
        json = json_mod.executor,
      },
    }),
  }
end

local defaults = {
  config_dir = function()
    return vim.fn.stdpath("config") .. "/projects"
  end,
  pipeline = nil,
  executors = { lua = { async = false }, vim = { async = false }, json = { async = true } },
  loading = {
    on = "startup",
    start_dir = nil,
    watch = { config_dir = false, buffer = false, cwd = false, debounce_ms = 100 },
  },
  cache = { trust_mtime = true },
  on_load = nil,
  on_error = nil,
  on_clear = nil,
}

local function deep_merge(base, override)
  if type(base) ~= "table" or type(override) ~= "table" then
    if override ~= nil then
      return override
    end
    return base
  end
  local result = {}
  for k, v in pairs(base) do
    result[k] = v
  end
  for k, v in pairs(override) do
    result[k] = deep_merge(result[k], v)
  end
  return result
end

function M.setup(opts)
  opts = opts or {}
  local config = deep_merge(defaults, opts)

  local config_dir = config.config_dir
  if type(config_dir) == "function" then
    config_dir = config_dir()
  end

  local ctx = {
    config_dir = config_dir,
    pipeline = config.pipeline or create_default_pipeline(),
    executors = config.executors,
    loading = config.loading,
    cache = config.cache,
    on_load = config.on_load,
    on_error = config.on_error,
    on_clear = config.on_clear,

    dir_cache = dir_cache.new({ trust_mtime = config.cache.trust_mtime }),
    file_cache = file_cache.new({ trust_mtime = config.cache.trust_mtime }),

    project_root = nil,
    project_name = nil,
    _files_loaded = {},
    _last_project_json = nil,
  }

  ctx.json = make_reactive_table(function()
    json_mod.write_json(ctx)
  end)

  M.ctx = ctx

  watchers.setup_watchers(ctx)

  local loading_on = config.loading.on
  if loading_on == "startup" then
    vim.schedule(function()
      M.load_await()
    end)
  elseif loading_on == "lazy" then
    local augroup = vim.api.nvim_create_augroup("nvim_project_config_lazy", { clear = true })
    vim.api.nvim_create_autocmd("BufEnter", {
      group = augroup,
      once = true,
      callback = function()
        M.load_await()
      end,
    })
  else
    watchers.setup_watchers(ctx)
  end
end

function M.load(override_ctx)
  local ctx = override_ctx or M.ctx
  if not ctx then
    return
  end

  local start_dir = ctx.loading and ctx.loading.start_dir or vim.fn.getcwd()
  pipeline.run(ctx, ctx.pipeline, start_dir)
end

function M.load_await(override_ctx)
  local async = require("plenary.async")
  local channel = require("plenary.async.control").channel

  local ctx = override_ctx or M.ctx
  if not ctx then
    return nil
  end

  local tx, rx = channel.oneshot()

  local old_on_load = ctx.on_load
  ctx.on_load = function(loaded_ctx)
    if old_on_load then
      old_on_load(loaded_ctx)
    end
    tx(loaded_ctx)
  end

  local start_dir = ctx.loading and ctx.loading.start_dir or vim.fn.getcwd()
  pipeline.run(ctx, ctx.pipeline, start_dir)

  return function()
    return rx()
  end
end

function M.clear(override_ctx)
  local ctx = override_ctx or M.ctx
  if not ctx then
    return
  end

  pipeline.stop(ctx)

  ctx.project_root = nil
  ctx.project_name = nil
  ctx._files_loaded = {}
  ctx._last_project_json = nil

  local old_json = ctx.json
  ctx.json = make_reactive_table(function()
    json_mod.write_json(ctx)
  end)

  if ctx.on_clear then
    ctx.on_clear(ctx)
  end
end

return M
