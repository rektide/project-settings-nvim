describe("watchers", function()
  local watchers = require("nvim-project-config.watchers")

  describe("setup_watchers", function()
    it("has setup_watchers function", function()
      assert.equals("function", type(watchers.setup_watchers))
    end)
  end)

  describe("teardown_watchers", function()
    it("has teardown_watchers function", function()
      assert.equals("function", type(watchers.teardown_watchers))
    end)
  end)

  describe("watcher configuration", function()
    it("handles ctx with empty loading.watch", function()
      local ctx = {
        loading = {},
      }
      watchers.setup_watchers(ctx)
      assert.is_not_nil(ctx._watchers)
    end)
  end)

  describe("debounce", function()
    it("can start a watcher with config", function()
      local ctx = {
        loading = {
          watch = {
            config_dir = false,
            buffer = false,
            cwd = false,
            debounce_ms = 100,
          },
        },
      }
      watchers.setup_watchers(ctx)
      assert.is_not_nil(ctx._watchers)
      watchers.teardown_watchers(ctx)
    end)
  end)

  describe("config_dir watcher", function()
    it("skips setup when config_dir is nil", function()
      local ctx = {
        loading = {
          watch = {
            config_dir = false,
          },
        },
      }
      watchers.setup_watchers(ctx)
      assert.is_not_nil(ctx._watchers)
      watchers.teardown_watchers(ctx)
    end)
  end)

  describe("buffer watcher", function()
    it("skips setup when buffer watch is false", function()
      local ctx = {
        loading = {
          watch = {
            buffer = false,
          },
        },
      }
      watchers.setup_watchers(ctx)
      assert.is_not_nil(ctx._watchers)
      watchers.teardown_watchers(ctx)
    end)
  end)

  describe("cwd watcher", function()
    it("skips setup when cwd watch is false", function()
      local ctx = {
        loading = {
          watch = {
            cwd = false,
          },
        },
      }
      watchers.setup_watchers(ctx)
      assert.is_not_nil(ctx._watchers)
      watchers.teardown_watchers(ctx)
    end)
  end)

  describe("teardown", function()
    it("cleans up _watchers table", function()
      local ctx = {
        _watchers = {},
      }
      watchers.teardown_watchers(ctx)
      assert.is_nil(ctx._watchers)
    end)
  end)
end)
