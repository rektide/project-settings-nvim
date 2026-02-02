--- Walk stage: walks directories upward from input path toward root
--- @module nvim-project-config.stages.walk

local matchers = require("nvim-project-config.matchers")

--- Create a walk stage that walks directories upward
--- @param opts table|nil options
--- @param opts.direction string "up" (default) - direction to walk
--- @param opts.matcher any optional matcher to filter directories
--- @return function async stage function(ctx, input_rx, output_tx)
local function walk(opts)
  opts = opts or {}
  opts.direction = opts.direction or "up"
  local matcher = matchers.process(opts.matcher)

  return function(ctx, input_rx, output_tx)
    local pipeline = require("nvim-project-config.pipeline")
    local path = input_rx.recv()
    if path == nil or path == pipeline.DONE or ctx._pipeline_stopped then
      return
    end

    local current = vim.fn.fnamemodify(path, ":p")
    if vim.fn.isdirectory(current) == 0 then
      current = vim.fn.fnamemodify(current, ":h")
    end

    while current and current ~= "" do
      if ctx._pipeline_stopped then
        return
      end

      if matcher(current) then
        output_tx.send(current)
      end

      local parent = vim.fn.fnamemodify(current, ":h")
      if parent == current then
        break
      end
      current = parent
    end
  end
end

return walk
