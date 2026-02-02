local coop = require("coop")

describe("cache deadlock demonstration", function()

  describe("pattern difference", function()
    it("shows OLD pattern: spawn-coroutine + future = fragile", function()
      coop.spawn(function()
        local function old_pattern_get()
          local future = coop.Future.new()

          coop.spawn(function()
            future:complete("result from inner coroutine")
          end)

          return future()
        end

        local ok, result = pcall(old_pattern_get)

        print("OLD pattern - success:", ok, "result:", result)
      end)
    end)

    it("shows the NEW pattern: pure coroutine function = reliable", function()
      coop.spawn(function()
        local function new_pattern_get()
          return "result directly"
        end

        local result = new_pattern_get()
        assert.equals("result directly", result)
      end)
    end)
  end)

  describe("demonstration with async-like operations", function()
    it("OLD pattern with callback shows fragility", function()
      coop.spawn(function()
        local function mock_async_file_read(path, callback)
          callback("file content")
        end

        local function old_get(path)
          local future = coop.Future.new()

          coop.spawn(function()
            mock_async_file_read(path, function(content)
              future:complete(content)
            end)
          end)

          return future()
        end

        local completed = false
        coop.spawn(function()
          local ok, result = pcall(old_get, "dummy.json")
          completed = true
          print("OLD async pattern - ok:", ok, "result:", result)
        end)

        require("coop.uv-utils").sleep(50)
        assert.is_true(completed)
      end)
    end)

    it("NEW pattern with coroutines works reliably", function()
      coop.spawn(function()
        local function read_file_coro(path)
          return "file content"
        end

        local function new_get(path)
          return read_file_coro(path)
        end

        local result = new_get("dummy.json")
        assert.equals("file content", result)
      end)
    end)
  end)

  describe("pipeline context demonstration", function()
    it("OLD pattern in pipeline context - fragile", function()
      coop.spawn(function()
        local function pipeline_stage_old()
          local future = coop.Future.new()

          coop.spawn(function()
            future:complete("data from cache")
          end)

          return future()
        end

        local completed = false
        coop.spawn(function()
          local result = pipeline_stage_old()
          completed = true
          print("OLD pipeline result:", result)
        end)

        require("coop.uv-utils").sleep(50)
        assert.is_true(completed)
      end)
    end)

    it("NEW pattern in pipeline context - reliable", function()
      coop.spawn(function()
        local function pipeline_stage_new()
          return "data from cache"
        end

        local result = pipeline_stage_new()
        assert.equals("data from cache", result)
      end)
    end)
  end)

  describe("key lessons", function()
    it("lesson 1: complete-then-await is always safe", function()
      coop.spawn(function()
        local future = coop.Future.new()

        future:complete("value 1")
        local result1 = future()
        assert.equals("value 1", result1)
      end)
    end)

    it("lesson 2: await-then-complete across coroutines is fragile", function()
      coop.spawn(function()
        local future = coop.Future.new()

        local completed = false
        coop.spawn(function()
          future:complete("value 2")
          completed = true
        end)

        local result2 = future()

        assert.is_true(completed)
        assert.equals("value 2", result2)
      end)
    end)

    it("lesson 3: pure coroutines are simpler and more reliable", function()
      coop.spawn(function()
        local function pure_coroutine_function()
          return "simple and reliable"
        end

        local result = pure_coroutine_function()
        assert.equals("simple and reliable", result)
      end)
    end)
  end)
end)
