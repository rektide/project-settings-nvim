local M = {}

local function cancel_debounce(ctx)
  if ctx._watchers and ctx._watchers.debounce_timer then
    vim.fn.timer_stop(ctx._watchers.debounce_timer)
    ctx._watchers.debounce_timer = nil
  end
end

local function debounced_reload(ctx, new_start_dir)
  cancel_debounce(ctx)

  local debounce_ms = 100
  if ctx.loading and ctx.loading.watch and ctx.loading.watch.debounce_ms then
    debounce_ms = ctx.loading.watch.debounce_ms
  end

  ctx._watchers.debounce_timer = vim.fn.timer_start(debounce_ms, function()
    ctx._watchers.debounce_timer = nil
    vim.schedule(function()
      local main = require("nvim-project-config")
      main.clear(ctx)
      if new_start_dir then
        main.load(vim.tbl_extend("force", ctx, { start_dir = new_start_dir }))
      else
        main.load(ctx)
      end
    end)
  end)
end

local function setup_config_dir_watcher(ctx)
  if not ctx.config_dir then
    return
  end

  local handle = vim.loop.new_fs_event()
  if not handle then
    return
  end

  local ok, err = handle:start(ctx.config_dir, {}, function(err, filename, events)
    if err then
      return
    end
    vim.schedule(function()
      debounced_reload(ctx)
    end)
  end)

  if ok then
    ctx._watchers.config_dir = handle
  else
    handle:close()
  end
end

local function setup_buffer_watcher(ctx)
  local augroup = vim.api.nvim_create_augroup("nvim_project_config_buffer_" .. tostring(ctx), { clear = true })

  local autocmd_id = vim.api.nvim_create_autocmd("BufEnter", {
    group = augroup,
    callback = function()
      local bufname = vim.api.nvim_buf_get_name(0)
      if bufname == "" then
        return
      end

      local buf_dir = vim.fn.fnamemodify(bufname, ":p:h")
      if buf_dir ~= ctx.project_root then
        debounced_reload(ctx, buf_dir)
      end
    end,
  })

  ctx._watchers.buffer_autocmd = autocmd_id
  ctx._watchers.buffer_augroup = augroup
end

local function setup_cwd_watcher(ctx)
  local augroup = vim.api.nvim_create_augroup("nvim_project_config_cwd_" .. tostring(ctx), { clear = true })

  local autocmd_id = vim.api.nvim_create_autocmd("DirChanged", {
    group = augroup,
    callback = function()
      vim.schedule(function()
        debounced_reload(ctx)
      end)
    end,
  })

  ctx._watchers.cwd_autocmd = autocmd_id
  ctx._watchers.cwd_augroup = augroup
end

function M.setup_watchers(ctx)
  ctx._watchers = ctx._watchers or {}

  local watch = ctx.loading and ctx.loading.watch
  if not watch then
    return
  end

  if watch.config_dir then
    setup_config_dir_watcher(ctx)
  end

  if watch.buffer then
    setup_buffer_watcher(ctx)
  end

  if watch.cwd then
    setup_cwd_watcher(ctx)
  end
end

function M.teardown_watchers(ctx)
  if not ctx._watchers then
    return
  end

  cancel_debounce(ctx)

  if ctx._watchers.config_dir then
    ctx._watchers.config_dir:stop()
    ctx._watchers.config_dir:close()
    ctx._watchers.config_dir = nil
  end

  if ctx._watchers.buffer_augroup then
    vim.api.nvim_del_augroup_by_id(ctx._watchers.buffer_augroup)
    ctx._watchers.buffer_autocmd = nil
    ctx._watchers.buffer_augroup = nil
  end

  if ctx._watchers.cwd_augroup then
    vim.api.nvim_del_augroup_by_id(ctx._watchers.cwd_augroup)
    ctx._watchers.cwd_autocmd = nil
    ctx._watchers.cwd_augroup = nil
  end

  ctx._watchers = nil
end

return M
