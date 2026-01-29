local async = require("plenary.async")
local channel = require("plenary.async.control").channel

local M = {}

M.DONE = {} -- Sentinel value to signal end of stream

local function noop_sender()
  return {
    send = function() end,
  }
end

function M.run(ctx, stages, initial_input)
  ctx.channels = {}
  ctx._pipeline_stopped = false
  local pending = #stages

  for i = 1, #stages + 1 do
    local tx, rx = channel.mpsc()
    ctx.channels[i] = { tx = tx, rx = rx }
  end

  async.run(function()
    ctx.channels[1].tx.send(initial_input)
    ctx.channels[1].tx.send(M.DONE)
  end)

  for i, stage in ipairs(stages) do
    local input_rx = ctx.channels[i].rx
    local output_tx = (i < #stages) and ctx.channels[i + 1].tx or noop_sender()

    async.run(function()
      local ok, err = pcall(function()
        stage(ctx, input_rx, output_tx)
      end)

      if not ok then
        vim.schedule(function()
          vim.notify("pipeline stage " .. i .. " error: " .. tostring(err), vim.log.levels.ERROR)
        end)
      end

      if i < #stages then
        ctx.channels[i + 1].tx.send(M.DONE)
      end

      pending = pending - 1
      if pending == 0 and ctx.on_load and not ctx._pipeline_stopped then
        vim.schedule(function()
          ctx.on_load(ctx)
        end)
      end
    end)
  end
end

function M.stop(ctx)
  ctx._pipeline_stopped = true
  ctx.channels = nil
end

return M
