--- Execute stage: routes config files to extension-specific executors
--- @module nvim-project-config.stages.execute

local async = require("plenary.async")

--- Create an execute stage that runs config files
--- @param opts table|nil options
--- @param opts.router table extension -> executor mapping
--- @return function stage function(ctx, input_rx, output_tx)
local function execute(opts)
  opts = opts or {}
  opts.router = opts.router or {}

  return function(ctx, input_rx, output_tx)
    local pipeline = require("nvim-project-config.pipeline")
    ctx._files_loaded = ctx._files_loaded or {}

    while true do
      if ctx._pipeline_stopped then
        return
      end
      
      local file_path = input_rx.recv()
      if file_path == nil or file_path == pipeline.DONE then
        break
      end

      local ext = vim.fn.fnamemodify(file_path, ":e")
      local executor = opts.router[ext]

      if executor then
        local executor_opts = ctx.executors and ctx.executors[ext] or {}
        local run_async = executor_opts.async or false

        local function run_executor()
          executor(ctx, file_path)
          ctx._files_loaded[file_path] = true
        end

        local ok, err
        if run_async then
          ok, err = pcall(function()
            async.run(run_executor)
          end)
        else
          ok, err = pcall(run_executor)
        end

        if not ok and ctx.on_error then
          vim.schedule(function()
            ctx.on_error(err, ctx, file_path)
          end)
        end
      end
    end
  end
end

return execute
