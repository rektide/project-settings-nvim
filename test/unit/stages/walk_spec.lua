describe("walk stage", function()
  local walk = require("nvim-project-config.stages.walk")
  local pipeline = require("nvim-project-config.pipeline")
  local async = require("plenary.async")
  local uv = async.uv

  describe("upward traversal", function()
    it("walks from start directory to filesystem root", function(done)
      local channel = require("plenary.async.control").channel
      local input_tx, input_rx = channel.mpsc()
      local output_tx, output_rx = channel.mpsc()

      input_tx.send("/home/user/project")
      input_tx.send(pipeline.DONE)

      local ctx = { _pipeline_stopped = false }
      local stage = walk({ direction = "up" })

      async.run(function()
        stage(ctx, input_rx, output_tx)
      end)

      async.run(function()
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
      local channel = require("plenary.async.control").channel
      local input_tx, input_rx = channel.mpsc()
      local output_tx, output_rx = channel.mpsc()

      input_tx.send("/")
      input_tx.send(pipeline.DONE)

      local ctx = { _pipeline_stopped = false }
      local stage = walk({ direction = "up" })

      async.run(function()
        stage(ctx, input_rx, output_tx)
      end)

      async.run(function()
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
      local channel = require("plenary.async.control").channel
      local input_tx, input_rx = channel.mpsc()
      local output_tx, output_rx = channel.mpsc()

      input_tx.send("/home/user/project-with-marker/.git")
      input_tx.send(pipeline.DONE)

      local ctx = { _pipeline_stopped = false }
      local stage = walk({ direction = "up", matcher = ".git" })

      async.run(function()
        stage(ctx, input_rx, output_tx)
      end)

      async.run(function()
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
      local channel = require("plenary.async.control").channel
      local input_tx, input_rx = channel.mpsc()
      local output_tx, output_rx = channel.mpsc()

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

      async.run(function()
        stage(ctx, input_rx, output_tx)
      end)

      async.run(function()
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
      local channel = require("plenary.async.control").channel
      local input_tx, input_rx = channel.mpsc()
      local output_tx, output_rx = channel.mpsc()

      input_tx.send("/home/user/project/file.lua")
      input_tx.send(pipeline.DONE)

      local ctx = { _pipeline_stopped = false }
      local stage = walk({ direction = "up" })

      async.run(function()
        stage(ctx, input_rx, output_tx)
      end)

      async.run(function()
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
      local channel = require("plenary.async.control").channel
      local input_tx, input_rx = channel.mpsc()
      local output_tx, output_rx = channel.mpsc()

      input_tx.send("/home/user/project")

      local ctx = { _pipeline_stopped = true }
      local stage = walk({ direction = "up" })

      async.run(function()
        stage(ctx, input_rx, output_tx)
      end)

      async.run(function()
        local path = output_rx.recv()
        assert.is_nil(path)
        done()
      end)
    end)
  end)
end)
