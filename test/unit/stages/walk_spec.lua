describe("walk stage", function()
  local walk = require("nvim-project-config.stages.walk")
  local pipeline = require("nvim-project-config.pipeline")
  local coop = require("coop")
  local MpscQueue = require("coop.mpsc-queue").MpscQueue

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

  describe("upward traversal", function()
    it("walks from start directory to filesystem root", function(done)
      local input_tx, input_rx = create_channel()
      local output_tx, output_rx = create_channel()

      input_tx.send("/home/user/project")
      input_tx.send(pipeline.DONE)

      local ctx = { _pipeline_stopped = false }
      local stage = walk({ direction = "up" })

      coop.spawn(function()
        stage(ctx, input_rx, output_tx)
      end)

      coop.spawn(function()
        local paths = {}
        while true do
          local path = output_rx.recv()
          if path == nil or path == pipeline.DONE then
            break
          end
          table.insert(paths, path)
        end

        assert.is_true(#paths >= 1)
        assert.is_true(vim.tbl_contains(paths, "/home/user/project"))
        done()
      end)
    end)

    it("stops at filesystem root", function(done)
      local input_tx, input_rx = create_channel()
      local output_tx, output_rx = create_channel()

      input_tx.send("/")
      input_tx.send(pipeline.DONE)

      local ctx = { _pipeline_stopped = false }
      local stage = walk({ direction = "up" })

      coop.spawn(function()
        stage(ctx, input_rx, output_tx)
      end)

      coop.spawn(function()
        local paths = {}
        while true do
          local path = output_rx.recv()
          if path == nil or path == pipeline.DONE then
            break
          end
          table.insert(paths, path)
        end

        assert.is_true(vim.tbl_contains(paths, "/"))
        done()
      end)
    end)
  end)

  describe("matcher filtering", function()
    it("filters directories using string matcher", function(done)
      local matchers = require("nvim-project-config.matchers")
      local input_tx, input_rx = create_channel()
      local output_tx, output_rx = create_channel()

      input_tx.send("/home/user/project-with-marker/.git")
      input_tx.send(pipeline.DONE)

      local ctx = { _pipeline_stopped = false }
      local stage = walk({ direction = "up", matcher = ".git" })

      coop.spawn(function()
        stage(ctx, input_rx, output_tx)
      end)

      coop.spawn(function()
        local paths = {}
        while true do
          local path = output_rx.recv()
          if path == nil or path == pipeline.DONE then
            break
          end
          table.insert(paths, path)
        end

        assert.is_true(#paths == 0)
        done()
      end)
    end)

    it("filters directories using function matcher", function(done)
      local input_tx, input_rx = create_channel()
      local output_tx, output_rx = create_channel()

      input_tx.send("/home/user")
      input_tx.send("/home")
      input_tx.send(pipeline.DONE)

      local ctx = { _pipeline_stopped = false }
      local stage = walk({
        direction = "up",
        matcher = function(p)
          return p == "/home"
        end,
      })

      coop.spawn(function()
        stage(ctx, input_rx, output_tx)
      end)

      coop.spawn(function()
        local paths = {}
        while true do
          local path = output_rx.recv()
          if path == nil or path == pipeline.DONE then
            break
          end
          table.insert(paths, path)
        end

        assert.is_true(vim.tbl_contains(paths, "/home"))
        done()
      end)
    end)
  end)

  describe("non-directory input", function()
    it("starts from parent directory if input is a file", function(done)
      local input_tx, input_rx = create_channel()
      local output_tx, output_rx = create_channel()

      input_tx.send("/home/user/project/file.lua")
      input_tx.send(pipeline.DONE)

      local ctx = { _pipeline_stopped = false }
      local stage = walk({ direction = "up" })

      coop.spawn(function()
        stage(ctx, input_rx, output_tx)
      end)

      coop.spawn(function()
        local paths = {}
        while true do
          local path = output_rx.recv()
          if path == nil or path == pipeline.DONE then
            break
          end
          table.insert(paths, path)
        end

        assert.is_true(#paths >= 1)
        assert.is_true(vim.tbl_contains(paths, "/home/user/project"))
        done()
      end)
    end)
  end)

  describe("pipeline stopped", function()
    it("exits immediately when _pipeline_stopped is true", function(done)
      local input_tx, input_rx = create_channel()
      local output_tx, output_rx = create_channel()

      input_tx.send("/home/user/project")

      local ctx = { _pipeline_stopped = true }
      local stage = walk({ direction = "up" })

      coop.spawn(function()
        stage(ctx, input_rx, output_tx)
      end)

      coop.spawn(function()
        local path = output_rx.recv()
        assert.is_nil(path)
        done()
      end)
    end)
  end)
end)
