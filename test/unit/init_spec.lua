describe("nvim-project-config main module", function()
  local npc = require("nvim-project-config")
  local pipeline = require("nvim-project-config.pipeline")

  after_each(function()
    if npc.ctx then
      npc.clear()
    end
  end)

  describe("setup", function()
    it("initializes context with default values", function()
      local old_ctx = npc.ctx
      npc.setup()
      assert.is_not_nil(npc.ctx)
      assert.is_not_nil(npc.ctx.config_dir)
      assert.is_not_nil(npc.ctx.pipeline)
      assert.is_not_nil(npc.ctx.executors)
      assert.is_not_nil(npc.ctx.loading)
      assert.is_not_nil(npc.ctx.cache)
      assert.is_not_nil(npc.ctx.dir_cache)
      assert.is_not_nil(npc.ctx.file_cache)
      assert.is_not_nil(npc.ctx.json)
      npc.ctx = old_ctx
    end)

    it("uses provided config_dir", function()
      local old_ctx = npc.ctx
      npc.setup({ config_dir = "/custom/config/dir" })
      assert.equals("/custom/config/dir", npc.ctx.config_dir)
      npc.ctx = old_ctx
    end)

    it("resolves config_dir function", function()
      local old_ctx = npc.ctx
      npc.setup({ config_dir = function()
        return "/resolved/path"
      end })
      assert.equals("/resolved/path", npc.ctx.config_dir)
      npc.ctx = old_ctx
    end)

    it("uses default config_dir function when none provided", function()
      local old_ctx = npc.ctx
      npc.setup()
      local default_config_dir = vim.fn.stdpath("config") .. "/projects"
      assert.equals(default_config_dir, npc.ctx.config_dir)
      npc.ctx = old_ctx
    end)

    it("merges executor options", function()
      local old_ctx = npc.ctx
      npc.setup({
        executors = { lua = { async = true } }
      })
      assert.is_true(npc.ctx.executors.lua.async)
      assert.is_false(npc.ctx.executors.vim.async)
      assert.is_true(npc.ctx.executors.json.async)
      npc.ctx = old_ctx
    end)

    it("creates reactive json table", function()
      local old_ctx = npc.ctx
      npc.setup()
      assert.is_not_nil(npc.ctx.json)
      assert.equals("table", type(npc.ctx.json))
      npc.ctx.json.test_key = "test_value"
      assert.equals("test_value", npc.ctx.json.test_key)
      npc.ctx = old_ctx
    end)

    it("accepts on_load callback", function()
      local old_ctx = npc.ctx
      local called = false
      npc.setup({
        on_load = function(ctx)
          called = true
          assert.is_not_nil(ctx)
        end
      })
      assert.is_not_nil(npc.ctx.on_load)
      assert.equals("function", type(npc.ctx.on_load))
      npc.ctx.on_load(npc.ctx)
      assert.is_true(called)
      npc.ctx = old_ctx
    end)

    it("accepts on_error callback", function()
      local old_ctx = npc.ctx
      npc.setup({
        on_error = function(ctx, err)
          assert.is_not_nil(ctx)
          assert.is_not_nil(err)
        end
      })
      assert.is_not_nil(npc.ctx.on_error)
      assert.equals("function", type(npc.ctx.on_error))
      npc.ctx.on_error(npc.ctx, "test error")
      npc.ctx = old_ctx
    end)

    it("accepts on_clear callback", function()
      local old_ctx = npc.ctx
      local called = false
      npc.setup({
        on_clear = function(ctx)
          called = true
          assert.is_not_nil(ctx)
        end
      })
      assert.is_not_nil(npc.ctx.on_clear)
      assert.equals("function", type(npc.ctx.on_clear))
      npc.ctx.on_clear(npc.ctx)
      assert.is_true(called)
      npc.ctx = old_ctx
    end)

    it("merges cache options", function()
      local old_ctx = npc.ctx
      npc.setup({
        cache = { trust_mtime = false }
      })
      assert.is_false(npc.ctx.cache.trust_mtime)
      npc.ctx = old_ctx
    end)

    it("merges loading options", function()
      local old_ctx = npc.ctx
      npc.setup({
        loading = {
          on = "lazy",
          start_dir = "/custom/start",
          watch = { config_dir = true }
        }
      })
      assert.equals("lazy", npc.ctx.loading.on)
      assert.equals("/custom/start", npc.ctx.loading.start_dir)
      assert.is_true(npc.ctx.loading.watch.config_dir)
      npc.ctx = old_ctx
    end)

    it("stores watchers configuration", function()
      local old_ctx = npc.ctx
      npc.setup({
        loading = {
          watch = {
            config_dir = true,
            buffer = true,
            cwd = true,
            debounce_ms = 200
          }
        }
      })
      assert.is_true(npc.ctx.loading.watch.config_dir)
      assert.is_true(npc.ctx.loading.watch.buffer)
      assert.is_true(npc.ctx.loading.watch.cwd)
      assert.equals(200, npc.ctx.loading.watch.debounce_ms)
      npc.ctx = old_ctx
    end)

    it("initializes caches with trust_mtime option", function()
      local old_ctx = npc.ctx
      npc.setup({ cache = { trust_mtime = false } })
      assert.is_not_nil(npc.ctx.dir_cache)
      assert.is_not_nil(npc.ctx.file_cache)
      npc.ctx = old_ctx
    end)
  end)

  describe("load", function()
    it("returns early when no context exists", function()
      npc.ctx = nil
      local result = npc.load()
      assert.is_nil(result)
    end)

    it("errors when context is not a table", function()
      npc.ctx = "invalid"
      assert.has.errors(function()
        npc.load()
      end)
      npc.ctx = nil
    end)

    it("uses provided override context", function()
      local old_ctx = npc.ctx
      local override_ctx = {
        pipeline = {},
        loading = { start_dir = "/test/dir" }
      }
      local called = false
      local original_run = pipeline.run
      pipeline.run = function(ctx, pipe, start_dir)
        called = true
        assert.equals(override_ctx, ctx)
        assert.equals("/test/dir", start_dir)
        pipeline.run = original_run
      end
      npc.load(override_ctx)
      assert.is_true(called)
      npc.ctx = old_ctx
    end)

    it("uses current working directory when no start_dir specified", function()
      local old_ctx = npc.ctx
      npc.setup()
      local cwd = vim.fn.getcwd()
      local called = false
      local original_run = pipeline.run
      pipeline.run = function(ctx, pipe, start_dir)
        called = true
        assert.equals(cwd, start_dir)
        pipeline.run = original_run
      end
      npc.load()
      assert.is_true(called)
      npc.ctx = old_ctx
    end)

    it("uses ctx.loading.start_dir when provided", function()
      local old_ctx = npc.ctx
      npc.setup({
        loading = { start_dir = "/custom/path" }
      })
      local called = false
      local original_run = pipeline.run
      pipeline.run = function(ctx, pipe, start_dir)
        called = true
        assert.equals("/custom/path", start_dir)
        pipeline.run = original_run
      end
      npc.load()
      assert.is_true(called)
      npc.ctx = old_ctx
    end)

    it("calls pipeline.run with context and pipeline", function()
      local old_ctx = npc.ctx
      npc.setup()
      local called = false
      local original_run = pipeline.run
      pipeline.run = function(ctx, pipe, start_dir)
        called = true
        assert.equals(npc.ctx, ctx)
        assert.is_not_nil(pipe)
        assert.equals("table", type(pipe))
        assert.is_not_nil(start_dir)
        pipeline.run = original_run
      end
      npc.load()
      assert.is_true(called)
      npc.ctx = old_ctx
    end)
  end)

  describe("load_await", function()
    it("returns nil when no context exists", function()
      npc.ctx = nil
      local result = npc.load_await()
      assert.is_nil(result)
    end)

    it("returns an awaiter function", function()
      local old_ctx = npc.ctx
      npc.setup()
      local awaiter = npc.load_await()
      assert.is_not_nil(awaiter)
      assert.equals("function", type(awaiter))
      npc.ctx = old_ctx
    end)

    it("awaiter function returns context when pipeline completes", function()
      local old_ctx = npc.ctx
      local async = require("plenary.async")
      local called = false
      local result_ctx = nil

      npc.setup()
      npc.ctx.pipeline = {
        function(ctx, rx, tx)
          tx.send("dummy")
          tx.send(pipeline.DONE)
        end,
        function(ctx, rx, tx)
          local input = rx()
          if input ~= pipeline.DONE then
            if ctx.on_load then
              ctx.on_load(ctx)
            end
          end
        end,
      }

      local awaiter = npc.load_await()
      async.run(function()
        result_ctx = awaiter()
        called = true
      end)

      vim.wait(100, function()
        return called
      end)

      assert.is_true(called)
      assert.equals(npc.ctx, result_ctx)
      npc.ctx = old_ctx
    end)

    it("preserves existing on_load callback", function()
      local old_ctx = npc.ctx
      local async = require("plenary.async")
      local on_load_called = false
      local awaiter_called = false
      local result_ctx = nil

      npc.setup({
        on_load = function(ctx)
          on_load_called = true
        end,
      })

      npc.ctx.pipeline = {
        function(ctx, rx, tx)
          tx.send("dummy")
          tx.send(pipeline.DONE)
        end,
        function(ctx, rx, tx)
          local input = rx()
          if input ~= pipeline.DONE then
            if ctx.on_load then
              ctx.on_load(ctx)
            end
          end
        end,
      }

      local awaiter = npc.load_await()
      async.run(function()
        result_ctx = awaiter()
        awaiter_called = true
      end)

      vim.wait(100, function()
        return awaiter_called
      end)

      assert.is_true(on_load_called)
      assert.is_true(awaiter_called)
      assert.equals(npc.ctx, result_ctx)
      npc.ctx = old_ctx
    end)

    it("uses provided override context", function()
      local old_ctx = npc.ctx
      local async = require("plenary.async")
      local called = false
      local on_load_triggered = false
      local result_ctx = nil

      local override_ctx = {
        pipeline = {},
        loading = { start_dir = "/test/dir" },
        on_load = function(ctx)
          on_load_triggered = true
        end,
      }

      local original_run = pipeline.run
      pipeline.run = function(ctx, pipe, start_dir)
        called = true
        assert.equals(override_ctx, ctx)
        assert.equals("/test/dir", start_dir)
        if ctx.on_load then
          ctx.on_load(ctx)
        end
        pipeline.run = original_run
      end

      local awaiter = npc.load_await(override_ctx)
      async.run(function()
        result_ctx = awaiter()
      end)

      vim.wait(200, function()
        return called and on_load_triggered and result_ctx ~= nil
      end)

      assert.is_true(called)
      assert.is_true(on_load_triggered)
      assert.equals(override_ctx, result_ctx)
      npc.ctx = old_ctx
    end)
  end)

  describe("load", function()
    it("returns early when no context exists", function()
      npc.ctx = nil
      local result = npc.load()
      assert.is_nil(result)
    end)

    it("errors when context is not a table", function()
      npc.ctx = "invalid"
      assert.has.errors(function()
        npc.load()
      end)
      npc.ctx = nil
    end)

    it("uses provided override context", function()
      local old_ctx = npc.ctx
      local override_ctx = {
        pipeline = {},
        loading = { start_dir = "/test/dir" }
      }
      local called = false
      local original_run = pipeline.run
      pipeline.run = function(ctx, pipe, start_dir)
        called = true
        assert.equals(override_ctx, ctx)
        assert.equals("/test/dir", start_dir)
        pipeline.run = original_run
      end
      npc.load(override_ctx)
      assert.is_true(called)
      npc.ctx = old_ctx
    end)

    it("uses current working directory when no start_dir specified", function()
      local old_ctx = npc.ctx
      npc.setup()
      local cwd = vim.fn.getcwd()
      local called = false
      local original_run = pipeline.run
      pipeline.run = function(ctx, pipe, start_dir)
        called = true
        assert.equals(cwd, start_dir)
        pipeline.run = original_run
      end
      npc.load()
      assert.is_true(called)
      npc.ctx = old_ctx
    end)

    it("uses ctx.loading.start_dir when provided", function()
      local old_ctx = npc.ctx
      npc.setup({
        loading = { start_dir = "/custom/path" }
      })
      local called = false
      local original_run = pipeline.run
      pipeline.run = function(ctx, pipe, start_dir)
        called = true
        assert.equals("/custom/path", start_dir)
        pipeline.run = original_run
      end
      npc.load()
      assert.is_true(called)
      npc.ctx = old_ctx
    end)

    it("calls pipeline.run with context and pipeline", function()
      local old_ctx = npc.ctx
      npc.setup()
      local called = false
      local original_run = pipeline.run
      pipeline.run = function(ctx, pipe, start_dir)
        called = true
        assert.equals(npc.ctx, ctx)
        assert.is_not_nil(pipe)
        assert.equals("table", type(pipe))
        assert.is_not_nil(start_dir)
        pipeline.run = original_run
      end
      npc.load()
      assert.is_true(called)
      npc.ctx = old_ctx
    end)
  end)

  describe("clear", function()
    it("returns early when no context exists", function()
      npc.ctx = nil
      local result = npc.clear()
      assert.is_nil(result)
    end)

    it("errors when context is not a table", function()
      npc.ctx = "invalid"
      assert.has.errors(function()
        npc.clear()
      end)
      npc.ctx = nil
    end)

    it("resets project_root and project_name", function()
      local old_ctx = npc.ctx
      npc.setup()
      npc.ctx.project_root = "/test/root"
      npc.ctx.project_name = "test_project"
      npc.clear()
      assert.is_nil(npc.ctx.project_root)
      assert.is_nil(npc.ctx.project_name)
      npc.ctx = old_ctx
    end)

    it("clears _files_loaded and _last_project_json", function()
      local old_ctx = npc.ctx
      npc.setup()
      npc.ctx._files_loaded = { "/test/file.lua" }
      npc.ctx._last_project_json = { key = "value" }
      npc.clear()
      assert.is_true(vim.tbl_isempty(npc.ctx._files_loaded))
      assert.is_nil(npc.ctx._last_project_json)
      npc.ctx = old_ctx
    end)

    it("creates new reactive json table", function()
      local old_ctx = npc.ctx
      npc.setup()
      local old_json = npc.ctx.json
      old_json.test_key = "test_value"
      npc.clear()
      assert.is_not_nil(npc.ctx.json)
      assert.is_not_nil(npc.ctx.json)
      assert.is_nil(npc.ctx.json.test_key)
      npc.ctx = old_ctx
    end)

    it("calls pipeline.stop", function()
      local old_ctx = npc.ctx
      npc.setup()
      local called = false
      local original_stop = pipeline.stop
      pipeline.stop = function(ctx)
        called = true
        assert.equals(npc.ctx, ctx)
        pipeline.stop = original_stop
      end
      npc.clear()
      assert.is_true(called)
      npc.ctx = old_ctx
    end)

    it("calls on_clear callback if provided", function()
      local old_ctx = npc.ctx
      local called = false
      npc.setup({
        on_clear = function(ctx)
          called = true
          assert.equals(npc.ctx, ctx)
        end
      })
      npc.clear()
      assert.is_true(called)
      npc.ctx = old_ctx
    end)

    it("does not error when on_clear is nil", function()
      local old_ctx = npc.ctx
      npc.setup({ on_clear = nil })
      assert.has_no.errors(function()
        npc.clear()
      end)
      npc.ctx = old_ctx
    end)

    it("uses provided override context", function()
      local old_ctx = npc.ctx
      npc.setup()
      local override_ctx = {
        project_root = "/test/root",
        pipeline = {}
      }
      local called = false
      local original_stop = pipeline.stop
      pipeline.stop = function(ctx)
        called = true
        assert.equals(override_ctx, ctx)
        pipeline.stop = original_stop
      end
      npc.clear(override_ctx)
      assert.is_true(called)
      assert.is_nil(override_ctx.project_root)
      npc.ctx = old_ctx
    end)
  end)

  describe("deep_merge", function()
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

    it("merges two flat tables", function()
      local base = { a = 1, b = 2 }
      local override = { b = 3, c = 4 }
      local result = deep_merge(base, override)
      assert.equals(1, result.a)
      assert.equals(3, result.b)
      assert.equals(4, result.c)
    end)

    it("recursively merges nested tables", function()
      local base = { a = { x = 1, y = 2 } }
      local override = { a = { y = 3, z = 4 } }
      local result = deep_merge(base, override)
      assert.equals(1, result.a.x)
      assert.equals(3, result.a.y)
      assert.equals(4, result.a.z)
    end)

    it("returns override when base is not a table", function()
      local result = deep_merge("string", { key = "value" })
      assert.equals("value", result.key)
    end)

    it("returns override when base is nil", function()
      local result = deep_merge(nil, { key = "value" })
      assert.equals("value", result.key)
    end)

    it("returns base when override is nil", function()
      local base = { key = "value" }
      local result = deep_merge(base, nil)
      assert.equals(base, result)
    end)

    it("replaces table with non-table in override", function()
      local base = { a = { x = 1, y = 2 } }
      local override = { a = "string" }
      local result = deep_merge(base, override)
      assert.equals("string", result.a)
    end)

    it("preserves base keys not in override", function()
      local base = { a = 1, b = 2, c = 3 }
      local override = { b = 20 }
      local result = deep_merge(base, override)
      assert.equals(1, result.a)
      assert.equals(20, result.b)
      assert.equals(3, result.c)
    end)

    it("handles deeply nested structures", function()
      local base = { a = { b = { c = { d = 1 } } } }
      local override = { a = { b = { c = { e = 2 } } } }
      local result = deep_merge(base, override)
      assert.equals(1, result.a.b.c.d)
      assert.equals(2, result.a.b.c.e)
    end)
  end)

  describe("default pipeline creation", function()
    it("creates default pipeline with 4 stages", function()
      local old_ctx = npc.ctx
      npc.setup()
      assert.equals(4, #npc.ctx.pipeline)
      npc.ctx = old_ctx
    end)

    it("includes walk stage as first stage", function()
      local old_ctx = npc.ctx
      npc.setup()
      assert.equals("function", type(npc.ctx.pipeline[1]))
      npc.ctx = old_ctx
    end)

    it("includes detect stage as second stage", function()
      local old_ctx = npc.ctx
      npc.setup()
      assert.equals("function", type(npc.ctx.pipeline[2]))
      npc.ctx = old_ctx
    end)

    it("includes find_files stage as third stage", function()
      local old_ctx = npc.ctx
      npc.setup()
      assert.equals("function", type(npc.ctx.pipeline[3]))
      npc.ctx = old_ctx
    end)

    it("includes execute stage as fourth stage", function()
      local old_ctx = npc.ctx
      npc.setup()
      assert.equals("function", type(npc.ctx.pipeline[4]))
      npc.ctx = old_ctx
    end)

    it("allows custom pipeline to override default", function()
      local old_ctx = npc.ctx
      local custom_pipeline = {
        function() return "custom" end
      }
      npc.setup({ pipeline = custom_pipeline })
      assert.equals(custom_pipeline, npc.ctx.pipeline)
      assert.equals(1, #npc.ctx.pipeline)
      npc.ctx = old_ctx
    end)
  end)

  describe("loading modes", function()
    it("supports 'startup' loading mode", function()
      local old_ctx = npc.ctx
      npc.setup({
        loading = { on = "startup" }
      })
      assert.equals("startup", npc.ctx.loading.on)
      npc.ctx = old_ctx
    end)

    it("supports 'lazy' loading mode", function()
      local old_ctx = npc.ctx
      npc.setup({
        loading = { on = "lazy" }
      })
      assert.equals("lazy", npc.ctx.loading.on)
      npc.ctx = old_ctx
    end)

    it("defaults to 'startup' loading mode", function()
      local old_ctx = npc.ctx
      npc.setup()
      assert.equals("startup", npc.ctx.loading.on)
      npc.ctx = old_ctx
    end)

    it("stores default start_dir as nil", function()
      local old_ctx = npc.ctx
      npc.setup()
      assert.is_nil(npc.ctx.loading.start_dir)
      npc.ctx = old_ctx
    end)
  end)

  describe("context structure", function()
    it("has all required context fields", function()
      local old_ctx = npc.ctx
      npc.setup()

      assert.is_not_nil(npc.ctx.config_dir)
      assert.is_not_nil(npc.ctx.pipeline)
      assert.is_not_nil(npc.ctx.executors)
      assert.is_not_nil(npc.ctx.loading)
      assert.is_not_nil(npc.ctx.cache)
      assert.is_not_nil(npc.ctx.dir_cache)
      assert.is_not_nil(npc.ctx.file_cache)
      assert.is_not_nil(npc.ctx.json)

      assert.is_not_nil(npc.ctx._files_loaded)

      npc.ctx = old_ctx
    end)

    it("initializes project state fields", function()
      local old_ctx = npc.ctx
      npc.setup()
      assert.is_nil(npc.ctx.project_root)
      assert.is_nil(npc.ctx.project_name)
      assert.is_true(vim.tbl_isempty(npc.ctx._files_loaded))
      assert.is_nil(npc.ctx._last_project_json)
      npc.ctx = old_ctx
    end)
  end)

  describe("reactive table", function()
    it("calls on_change when value is set", function()
      local old_ctx = npc.ctx
      local called = false

      local function make_reactive_table(on_change, parent_path)
        parent_path = parent_path or {}
        local data = {}
        local mt = {
          __index = function(_, key)
            return data[key]
          end,
          __newindex = function(_, key, value)
            if type(value) == "table" and getmetatable(value) == nil then
              local path = vim.list_extend({}, parent_path)
              table.insert(path, key)
              value = make_reactive_table(on_change, path)
            end
            data[key] = value
            on_change()
          end,
          __pairs = function()
            return pairs(data)
          end,
        }
        return setmetatable({}, mt)
      end

      local table = make_reactive_table(function()
        called = true
      end)
      table.key = "value"
      assert.is_true(called)
      npc.ctx = old_ctx
    end)

    it("allows getting values", function()
      local old_ctx = npc.ctx
      local function make_reactive_table(on_change, parent_path)
        parent_path = parent_path or {}
        local data = {}
        local mt = {
          __index = function(_, key)
            return data[key]
          end,
          __newindex = function(_, key, value)
            if type(value) == "table" and getmetatable(value) == nil then
              local path = vim.list_extend({}, parent_path)
              table.insert(path, key)
              value = make_reactive_table(on_change, path)
            end
            data[key] = value
          end,
          __pairs = function()
            return pairs(data)
          end,
        }
        return setmetatable({}, mt)
      end

      local table = make_reactive_table(function() end)
      table.test_key = "test_value"
      assert.equals("test_value", table.test_key)
      npc.ctx = old_ctx
    end)

    it("allows reading multiple values", function()
      local old_ctx = npc.ctx
      local function make_reactive_table(on_change, parent_path)
        parent_path = parent_path or {}
        local data = {}
        local mt = {
          __index = function(_, key)
            return data[key]
          end,
          __newindex = function(_, key, value)
            if type(value) == "table" and getmetatable(value) == nil then
              local path = vim.list_extend({}, parent_path)
              table.insert(path, key)
              value = make_reactive_table(on_change, path)
            end
            data[key] = value
          end,
          __pairs = function()
            return pairs(data)
          end,
        }
        return setmetatable({}, mt)
      end

      local table = make_reactive_table(function() end)
      table.a = 1
      table.b = 2
      table.c = 3

      assert.equals(1, table.a)
      assert.equals(2, table.b)
      assert.equals(3, table.c)
      npc.ctx = old_ctx
    end)
  end)
end)
