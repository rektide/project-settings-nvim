describe("detect stage", function()
  local detect = require("nvim-project-config.stages.detect")
  local pipeline = require("nvim-project-config.pipeline")
  local async = require("plenary.async")

  describe("string matcher", function()
    it("matches when file exists in directory", function(done)
      local channel = require("plenary.async.control").channel
      local input_tx, input_rx = channel.mpsc()
      local output_tx, output_rx = channel.mpsc()

      input_tx.send("/")
      input_tx.send(pipeline.DONE)

      local ctx = { _pipeline_stopped = false }
      local matched = false
      local stage = detect({
        matcher = ".git",
        on_match = function()
          matched = true
        end,
      })

      async.run(function()
        stage(ctx, input_rx, output_tx)
      end)

      async.run(function()
        local path = output_rx.recv()
        assert.equals("/", path)

        local done_sent = output_rx.recv()
        assert.equals(pipeline.DONE, done_sent)

        done()
      end)
    end)

    it("does not match when file does not exist", function(done)
      local channel = require("plenary.async.control").channel
      local input_tx, input_rx = channel.mpsc()
      local output_tx, output_rx = channel.mpsc()

      input_tx.send("/does/not/exist")
      input_tx.send(pipeline.DONE)

      local ctx = { _pipeline_stopped = false }
      local matched = false
      local stage = detect({
        matcher = ".git",
        on_match = function()
          matched = true
        end,
      })

      async.run(function()
        stage(ctx, input_rx, output_tx)
      end)

      async.run(function()
        local path = output_rx.recv()
        assert.equals("/does/not/exist", path)

        assert.is_false(matched)
        done()
      end)
    end)
  end)

  describe("table matcher", function()
    it("matches if any file exists (OR logic)", function(done)
      local channel = require("plenary.async.control").channel
      local input_tx, input_rx = channel.mpsc()
      local output_tx, output_rx = channel.mpsc()

      input_tx.send("/")
      input_tx.send(pipeline.DONE)

      local ctx = { _pipeline_stopped = false }
      local matched = false
      local stage = detect({
        matcher = { ".git", ".hg", "Makefile" },
        on_match = function()
          matched = true
        end,
      })

      async.run(function()
        stage(ctx, input_rx, output_tx)
      end)

      async.run(function()
        local path = output_rx.recv()
        assert.equals("/", path)

        local done_sent = output_rx.recv()
        assert.equals(pipeline.DONE, done_sent)

        done()
      end)
    end)

    it("matches with mixed string and function matchers", function(done)
      local channel = require("plenary.async.control").channel
      local input_tx, input_rx = channel.mpsc()
      local output_tx, output_rx = channel.mpsc()

      input_tx.send("/")
      input_tx.send(pipeline.DONE)

      local ctx = { _pipeline_stopped = false }
      local matched = false
      local stage = detect({
        matcher = {
          ".nonexistent",
          function(p)
            return p == "/"
          end,
        },
        on_match = function()
          matched = true
        end,
      })

      async.run(function()
        stage(ctx, input_rx, output_tx)
      end)

      async.run(function()
        local path = output_rx.recv()
        assert.equals("/", path)

        local done_sent = output_rx.recv()
        assert.equals(pipeline.DONE, done_sent)

        done()
      end)
    end)
  end)

  describe("function matcher", function()
    it("calls function matcher with path", function(done)
      local channel = require("plenary.async.control").channel
      local input_tx, input_rx = channel.mpsc()
      local output_tx, output_rx = channel.mpsc()

      input_tx.send("/test/path")
      input_tx.send(pipeline.DONE)

      local ctx = { _pipeline_stopped = false }
      local matched_paths = {}
      local stage = detect({
        matcher = function(p)
          table.insert(matched_paths, p)
          return p:match("^/test") ~= nil
        end,
        on_match = function()
        end,
      })

      async.run(function()
        stage(ctx, input_rx, output_tx)
      end)

      async.run(function()
        local path = output_rx.recv()
        assert.equals("/test/path", path)

        assert.is_true(#matched_paths > 0)
        assert.is_true(vim.tbl_contains(matched_paths, "/test/path"))
        done()
      end)
    end)
  end)

  describe("nil matcher", function()
    it("always matches", function(done)
      local channel = require("plenary.async.control").channel
      local input_tx, input_rx = channel.mpsc()
      local output_tx, output_rx = channel.mpsc()

      input_tx.send("/any/path")
      input_tx.send(pipeline.DONE)

      local ctx = { _pipeline_stopped = false }
      local matched = false
      local stage = detect({
        matcher = nil,
        on_match = function()
          matched = true
        end,
      })

      async.run(function()
        stage(ctx, input_rx, output_tx)
      end)

      async.run(function()
        local path = output_rx.recv()
        assert.equals("/any/path", path)

        assert.is_true(matched)
        done()
      end)
    end)
  end)

  describe("on_match callback", function()
    it("is called with ctx and path when matched", function(done)
      local channel = require("plenary.async.control").channel
      local input_tx, input_rx = channel.mpsc()
      local output_tx, output_rx = channel.mpsc()

      input_tx.send("/")
      input_tx.send(pipeline.DONE)

      local ctx = { _pipeline_stopped = false, test_value = "ctx" }
      local received_ctx, received_path
      local stage = detect({
        matcher = nil,
        on_match = function(c, p)
          received_ctx = c
          received_path = p
        end,
      })

      async.run(function()
        stage(ctx, input_rx, output_tx)
      end)

      async.run(function()
        local path = output_rx.recv()
        assert.equals("/", path)

        assert.equals(ctx, received_ctx)
        assert.equals("/", received_path)
        assert.equals("ctx", received_ctx.test_value)
        done()
      end)
    end)
  end)

  describe("pipeline flow", function()
    it("forwards path to output even when not matched", function(done)
      local channel = require("plenary.async.control").channel
      local input_tx, input_rx = channel.mpsc()
      local output_tx, output_rx = channel.mpsc()

      input_tx.send("/some/path")
      input_tx.send(pipeline.DONE)

      local ctx = { _pipeline_stopped = false }
      local stage = detect({
        matcher = ".nonexistent",
        on_match = function()
        end,
      })

      async.run(function()
        stage(ctx, input_rx, output_tx)
      end)

      async.run(function()
        local path = output_rx.recv()
        assert.equals("/some/path", path)
        done()
      end)
    end)

    it("sends DONE signal to output", function(done)
      local channel = require("plenary.async.control").channel
      local input_tx, input_rx = channel.mpsc()
      local output_tx, output_rx = channel.mpsc()

      input_tx.send("/test")
      input_tx.send(pipeline.DONE)

      local ctx = { _pipeline_stopped = false }
      local stage = detect({
        matcher = nil,
        on_match = function()
        end,
      })

      async.run(function()
        stage(ctx, input_rx, output_tx)
      end)

      async.run(function()
        local path = output_rx.recv()
        assert.equals("/test", path)

        local done_sent = output_rx.recv()
        assert.equals(pipeline.DONE, done_sent)
        done()
      end)
    end)
  end)

  describe("pipeline stopped", function()
    it("exits immediately when _pipeline_stopped is true", function(done)
      local channel = require("plenary.async.control").channel
      local input_tx, input_rx = channel.mpsc()
      local output_tx, output_rx = channel.mpsc()

      input_tx.send("/test")

      local ctx = { _pipeline_stopped = true }
      local stage = detect({
        matcher = nil,
        on_match = function()
        end,
      })

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
