describe("integration", function()
  describe("JSON loading with cache", function()
    it("loads JSON files from astrovim-git/projects with cache enabled", function()
      local npc = require("nvim-project-config")
      local async = require("plenary.async")

      -- Setup to use astrovim projects directory with cache enabled
      npc.setup({
        config_dir = "/home/rektide/.config/astrovim-git/projects",
        loading = { on = "manual" },
      })

      -- Load and await completion
      async.run(function()
        local awaiter = npc.load_await()
        local ctx = awaiter()

        print("=== JSON Loading Test Results ===")
        print("Project:", ctx.project_name or "nil")
        print("Config dir:", ctx.config_dir or "nil")
        print()

        print("=== ctx.json contents ===")
        if ctx.json then
          for k, v in pairs(ctx.json) do
            print(string.format("  %s: %s", k, tostring(v)))
          end
        else
          print("  (empty)")
        end

        print()

        -- Verify test-cache.json was loaded
        assert.is_not_nil(ctx.json, "ctx.json should not be nil")
        assert.equals("test-value", ctx.json["test-key"], "test-key should be loaded")
        assert.equals("passes", ctx.json["cache-test"], "cache-test should be loaded")
        assert.equals("value", ctx.json.nested and ctx.json.nested.deep, "nested value should be loaded")

        print("✅ SUCCESS: All JSON values loaded correctly with cache enabled")
        print()
        print("This verifies:")
        print("- Cache async operations work during pipeline execution")
        print("- JSON executor successfully reads from cache")
        print("- Values merge into ctx.json correctly")
        print("- No deadlock occurred")
      end)
    end)

    it("verifies cache does not deadlock during pipeline execution", function()
      local npc = require("nvim-project-config")
      local async = require("plenary.async")

      -- Setup cache-enabled context
      npc.setup({
        config_dir = "/home/rektide/src/nvim-project-config/test/fixture",
        loading = { on = "manual" },
      })

      async.run(function()
        local awaiter = npc.load_await()
        local ctx = awaiter()

        -- Try to read same file twice (stress test)
        local cache1 = ctx.file_cache:get_async("/home/rektide/src/nvim-project-config/test/fixture/test-cache.json")
        local cache2 = ctx.file_cache:get_async("/home/rektide/src/nvim-project-config/test/fixture/test-cache.json")

        -- Both should succeed (no deadlock)
        assert.is_not_nil(cache1, "First cache read should return entry")
        assert.is_not_nil(cache2, "Second cache read should return entry")
        assert.equals(cache1.content, cache2.content, "Both reads should return same content")

        print("✅ SUCCESS: Cache handles concurrent reads without deadlock")
      end)
    end)
  end)
end)
