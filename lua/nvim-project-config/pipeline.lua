local coop = require("coop")
local MpscQueue = require("coop.mpsc-queue").MpscQueue

local M = {}

M.DONE = {}

local function noop_sender()
  return {
    send = function() end,
  }
end

local function create_channel()
  local queue = MpscQueue.new()
  local sender = {
    send = function(value)
      queue:push(value)
    end,
  }
  local receiver = {
    recv = function()
      return queue:pop()
    end,
  }
  return sender, receiver
end

function M.run(ctx, stages, initial_input)
  ctx.channels = {}
  ctx._pipeline_stopped = false
  local pending = #stages

  for i = 1, #stages + 1 do
    local tx, rx = create_channel()
    ctx.channels[i] = { tx = tx, rx = rx }
  end

  coop.spawn(function()
    ctx.channels[1].tx.send(initial_input)
    ctx.channels[1].tx.send(M.DONE)
  end)

  for i, stage in ipairs(stages) do
    local input_rx = ctx.channels[i].rx
    local output_tx = (i < #stages) and ctx.channels[i + 1].tx or noop_sender()

    coop.spawn(function()
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
