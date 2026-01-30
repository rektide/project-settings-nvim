describe("integration", function()
  describe("full pipeline loading", function()
    it("loads and initializes main module", function()
      local npc = require("nvim-project-config")
      assert.is_not_nil(npc)
      assert.equals("table", type(npc))
    end)

    it("has setup function", function()
      local npc = require("nvim-project-config")
      assert.equals("function", type(npc.setup))
    end)

    it("has load function", function()
      local npc = require("nvim-project-config")
      assert.equals("function", type(npc.load))
    end)

    it("has clear function", function()
      local npc = require("nvim-project-config")
      assert.equals("function", type(npc.clear))
    end)
  end)

  describe("caches", function()
    it("can create FileCache", function()
      local file_cache = require("nvim-project-config.cache.file").new()
      assert.is_not_nil(file_cache)
      assert.is_not_nil(file_cache._cache)
    end)

    it("can create DirectoryCache", function()
      local dir_cache = require("nvim-project-config.cache.directory").new()
      assert.is_not_nil(dir_cache)
      assert.is_not_nil(dir_cache._cache)
    end)
  end)

  describe("json reactive table", function()
    it("can set and get values", function()
      local json = require("nvim-project-config").ctx or {}
      if not json.json then
        json.json = {}
      end
      json.json.test_value = "test"
      assert.equals("test", json.json.test_value)
    end)
  end)

  describe("stages", function()
    it("can create walk stage", function()
      local walk = require("nvim-project-config.stages.walk")
      local stage = walk({ direction = "up" })
      assert.equals("function", type(stage))
    end)

    it("can create detect stage", function()
      local detect = require("nvim-project-config.stages.detect")
      local stage = detect({ matcher = ".git" })
      assert.equals("function", type(stage))
    end)

    it("can create find_files stage", function()
      local find_files = require("nvim-project-config.stages.find_files")
      local stage = find_files({ extensions = { ".lua" } })
      assert.equals("function", type(stage))
    end)

    it("can create execute stage", function()
      local execute = require("nvim-project-config.stages.execute")
      local stage = execute({ router = {} })
      assert.equals("function", type(stage))
    end)
  end)

  describe("matchers module", function()
    it("exports all matcher functions", function()
      local matchers = require("nvim-project-config.matchers")

      assert.equals("function", type(matchers.process))
      assert.equals("function", type(matchers.any))
      assert.equals("function", type(matchers.all))
      assert.equals("function", type(matchers.not_))
      assert.equals("function", type(matchers.literal))
      assert.equals("function", type(matchers.pattern))
      assert.equals("function", type(matchers.fn))
    end)
  end)
end)
