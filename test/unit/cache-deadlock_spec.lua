local async = require("plenary.async")

-- Tests demonstrating the cache refactor issue and fix
--
-- WHY THESE TESTS ARE LIMITED:
--
-- These tests CANNOT reliably reproduce the exact deadlock that occurred in production.
-- The deadlock was timing-dependent and happened when:
-- - The pipeline ran in async.run() coroutine A
-- - JSON executor called ctx.file_cache:get() which spawned coroutine B via async.run()
-- - get() created oneshot in A and yielded rx() in A
-- - Callback in B called tx() - deadlock due to coroutine boundary
--
-- In these tests, oneshot channels often work because the timing is different.
-- The key issue isn't that oneshot NEVER works across coroutines - it's that:
-- 1. The pattern is fragile and timing-dependent
-- 2. It creates unnecessary complexity
-- 3. The solution is simple: just don't bridge coroutines
--
-- THE FIX:
-- - OLD: get() spawns coroutine, creates oneshot, yields rx() -> callback -> deadlock (timing)
-- - NEW: get_async() is pure coroutine, called from pipeline coroutine -> no bridging needed

describe("cache deadlock demonstration", function()

  describe("pattern difference", function()
    it("shows the OLD pattern: spawn-coroutine + oneshot = fragile", function()
      async.run(function()
        -- OLD PATTERN: A function that spawns a coroutine and uses oneshot to return
        local function old_pattern_get()
          local tx, rx = async.control.channel.oneshot()

          -- Spawn a NEW coroutine
          async.run(function()
            -- This is in a DIFFERENT coroutine context
            -- The oneshot bridging can cause issues depending on timing
            tx("result from inner coroutine")
          end)

          -- Try to receive in the OUTER coroutine
          return rx()
        end

        -- This CAN work depending on timing, but it's fragile and unpredictable
        -- The fix is: don't spawn coroutines unnecessarily
        local ok, result = pcall(old_pattern_get)

        print("OLD pattern - success:", ok, "result:", result)
      end)
    end)

    it("shows the NEW pattern: pure coroutine function = reliable", function()
      async.run(function()
        -- NEW PATTERN: A pure coroutine function (no spawning)
        local function new_pattern_get()
          -- No coroutine spawning, no oneshot bridging
          -- Just return the value directly
          return "result directly"
        end

        -- This is reliable and predictable
        local result = new_pattern_get()
        assert.equals("result directly", result)
      end)
    end)
  end)

  describe("demonstration with async-like operations", function()
    it("OLD pattern with callback shows fragility", function()
      async.run(function()
        local function mock_async_file_read(path, callback)
          -- Simulates async file read with callback
          callback("file content")
        end

        local function old_get(path)
          local tx, rx = async.control.channel.oneshot()

          async.run(function()
            mock_async_file_read(path, function(content)
              -- Callback executes in inner coroutine
              tx(content)
            end)
          end)

          return rx()
        end

        -- This can work, but demonstrates the fragility
        local completed = false
        async.run(function()
          local ok, result = pcall(old_get, "dummy.json")
          completed = true
          print("OLD async pattern - ok:", ok, "result:", result)
        end)

        async.util.sleep(50)
        assert.is_true(completed)
      end)
    end)

    it("NEW pattern with coroutines works reliably", function()
      async.run(function()
        local function read_file_coro(path)
          -- Pure coroutine function
          -- In real code, this would use async.uv.fs_*() which yields correctly
          return "file content"
        end

        local function new_get(path)
          -- Pure coroutine function, no spawning
          return read_file_coro(path)
        end

        local result = new_get("dummy.json")
        assert.equals("file content", result)
      end)
    end)
  end)

  describe("pipeline context demonstration", function()
    it("OLD pattern in pipeline context - fragile", function()
      async.run(function()
        -- Simulate a pipeline stage using OLD pattern
        local function pipeline_stage_old()
          local tx, rx = async.control.channel.oneshot()

          async.run(function()
            -- Simulate cache.get() spawning a coroutine
            tx("data from cache")
          end)

          return rx()
        end

        local completed = false
        async.run(function()
          local result = pipeline_stage_old()
          completed = true
          print("OLD pipeline result:", result)
        end)

        async.util.sleep(50)
        assert.is_true(completed)
      end)
    end)

    it("NEW pattern in pipeline context - reliable", function()
      async.run(function()
        -- Simulate a pipeline stage using NEW pattern
        local function pipeline_stage_new()
          -- Pure coroutine function, just return data
          return "data from cache"
        end

        local result = pipeline_stage_new()
        assert.equals("data from cache", result)
      end)
    end)
  end)

  describe("key lessons", function()
    it("lesson 1: send-then-receive is always safe", function()
      async.run(function()
        local tx, rx = async.control.channel.oneshot()

        -- Pattern that always works: send first, then receive
        tx("value 1")
        local result1 = rx()
        assert.equals("value 1", result1)
      end)
    end)

    it("lesson 2: receive-then-send across coroutines is fragile", function()
      async.run(function()
        -- Pattern that CAN work but is fragile
        local tx, rx = async.control.channel.oneshot()

        local completed = false
        async.run(function()
          -- Send from inner coroutine
          tx("value 2")
          completed = true
        end)

        -- Receive from outer coroutine
        -- This can work, but it's fragile because it depends on coroutine scheduling
        local result2 = rx()

        -- Eventually completes but demonstrates the fragility
        assert.is_true(completed)
        assert.equals("value 2", result2)
      end)
    end)

    it("lesson 3: pure coroutines are simpler and more reliable", function()
      async.run(function()
        -- The best pattern: no bridging, no oneshot, just pure coroutines
        local function pure_coroutine_function()
          return "simple and reliable"
        end

        local result = pure_coroutine_function()
        assert.equals("simple and reliable", result)
      end)
    end)
  end)
end)
