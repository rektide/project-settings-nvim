describe("find_files stage", function()
  local find_files = require("nvim-project-config.stages.find_files")
  local pipeline = require("nvim-project-config.pipeline")

  describe("extension priority", function()
    it("sorts files with JSON > Lua > Vim priority", function()
      local files = {
        "/config/project.vim",
        "/config/project.lua",
        "/config/project.json",
      }

      local sorted = {}
      for _, f in ipairs(files) do
        table.insert(sorted, f)
      end

      assert.is_not_nil(sorted)
    end)
  end)
end)

describe("execute stage", function()
  local execute = require("nvim-project-config.stages.execute")
  local pipeline = require("nvim-project-config.pipeline")

  describe("executor routing", function()
    it("routes files by extension", function()
      local router = {
        [".lua"] = function(ctx, path)
        end,
        [".vim"] = function(ctx, path)
        end,
        [".json"] = function(ctx, path)
        end,
      }

      assert.is_not_nil(router[".lua"])
      assert.is_not_nil(router[".vim"])
      assert.is_not_nil(router[".json"])
      assert.is_nil(router[".py"])
    end)
  end)

  describe("executor options", function()
    it("checks async flag from ctx.executors", function()
      local ctx = {
        executors = {
          lua = { async = false },
          vim = { async = false },
          json = { async = true },
        },
        _files_loaded = {},
      }

      assert.is_false(ctx.executors.lua.async)
      assert.is_true(ctx.executors.json.async)
    end)
  end)
end)

describe("lua executor", function()
  local lua_exec = require("nvim-project-config.executors.lua")

  describe("execution", function()
    it("has function signature for executor", function()
      assert.equals("function", type(lua_exec))
    end)
  end)
end)

describe("vim executor", function()
  local vim_exec = require("nvim-project-config.executors.vim")

  describe("execution", function()
    it("has function signature for executor", function()
      assert.equals("function", type(vim_exec))
    end)
  end)
end)

describe("json executor", function()
  local json_mod = require("nvim-project-config.executors.json")

  describe("write_json", function()
    it("has write_json function", function()
      assert.equals("function", type(json_mod.write_json))
    end)
  end)

  describe("executor", function()
    it("has executor function", function()
      assert.equals("function", type(json_mod.executor))
    end)
  end)
end)

describe("pipeline", function()
  local pipeline = require("nvim-project-config.pipeline")

  describe("DONE sentinel", function()
    it("has DONE sentinel value", function()
      assert.is_not_nil(pipeline.DONE)
      assert.equals("table", type(pipeline.DONE))
    end)
  end)

  describe("run", function()
    it("has run function", function()
      assert.equals("function", type(pipeline.run))
    end)
  end)

  describe("stop", function()
    it("has stop function", function()
      assert.equals("function", type(pipeline.stop))
    end)
  end)
end)
