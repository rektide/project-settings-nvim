describe("reactive metatable", function()
  local old_ctx

  before_each(function()
    old_ctx = require("nvim-project-config").ctx
  end)

  after_each(function()
    require("nvim-project-config").ctx = old_ctx
  end)

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

  describe("flat operations", function()
    it("triggers on_change when setting value", function()
      local called = false
      local table = make_reactive_table(function()
        called = true
      end)
      table.key = "value"
      assert.is_true(called)
    end)

    it("allows getting set values", function()
      local table = make_reactive_table(function() end)
      table.test_key = "test_value"
      assert.equals("test_value", table.test_key)
    end)

    it("allows reading multiple values", function()
      local table = make_reactive_table(function() end)
      table.a = 1
      table.b = 2
      table.c = 3
      assert.equals(1, table.a)
      assert.equals(2, table.b)
      assert.equals(3, table.c)
    end)

    it("overwrites existing values", function()
      local table = make_reactive_table(function() end)
      table.key = "first"
      assert.equals("first", table.key)
      table.key = "second"
      assert.equals("second", table.key)
    end)

    it("allows nil values", function()
      local called = false
      local table = make_reactive_table(function()
        called = true
      end)
      table.key = nil
      assert.is_true(called)
      assert.is_nil(table.key)
    end)

    it("handles boolean values", function()
      local table = make_reactive_table(function() end)
      table.enabled = true
      table.disabled = false
      assert.is_true(table.enabled)
      assert.is_false(table.disabled)
    end)

    it("handles numeric values", function()
      local table = make_reactive_table(function() end)
      table.int = 42
      table.float = 3.14
      table.negative = -10
      assert.equals(42, table.int)
      assert.equals(3.14, table.float)
      assert.equals(-10, table.negative)
    end)
  end)

  describe("nested table operations", function()
    it("creates reactive nested tables", function()
      local called_count = 0
      local table = make_reactive_table(function()
        called_count = called_count + 1
      end)
      table.nested = {}
      assert.equals("table", type(table.nested))
      assert.is_not_nil(getmetatable(table.nested))
    end)

    it("does not wrap tables with existing metatables", function()
      local called_count = 0
      local table = make_reactive_table(function()
        called_count = called_count + 1
      end)
      local mt = { __index = function() return "custom" end }
      local custom = setmetatable({}, mt)
      table.custom = custom
      assert.equals(mt, getmetatable(table.custom))
    end)

    it("triggers on_change when writing to nested table", function()
      local called_count = 0
      local table = make_reactive_table(function()
        called_count = called_count + 1
      end)
      table.nested = {}
      local initial_count = called_count
      table.nested.key = "value"
      assert.equals(initial_count + 1, called_count)
      assert.equals("value", table.nested.key)
    end)

    it("allows reading nested values", function()
      local table = make_reactive_table(function() end)
      table.config = {}
      table.config.formatter = "biome"
      table.config.lsp = {}
      table.config.lsp.enabled = true
      assert.equals("biome", table.config.formatter)
      assert.is_true(table.config.lsp.enabled)
    end)

    it("allows updating existing nested table values", function()
      local called_count = 0
      local table = make_reactive_table(function()
        called_count = called_count + 1
      end)
      table.settings = {}
      table.settings.timeout = 1000
      local initial_count = called_count
      table.settings.timeout = 2000
      assert.equals(initial_count + 1, called_count)
      assert.equals(2000, table.settings.timeout)
    end)

    it("supports multiple independent nested tables", function()
      local called_count = 0
      local table = make_reactive_table(function()
        called_count = called_count + 1
      end)
      table.lsp = {}
      table.formatter = {}
      table.lsp.enabled = true
      table.formatter.name = "prettier"
      assert.is_true(table.lsp.enabled)
      assert.equals("prettier", table.formatter.name)
      assert.equals(4, called_count)
    end)

    it("handles nested nil assignments", function()
      local called_count = 0
      local table = make_reactive_table(function()
        called_count = called_count + 1
      end)
      table.config = {}
      table.config.value = "test"
      table.config.value = nil
      assert.is_nil(table.config.value)
    end)
  end)

  describe("deep nesting (3+ levels)", function()
    it("supports three levels of nesting", function()
      local called_count = 0
      local table = make_reactive_table(function()
        called_count = called_count + 1
      end)
      table.level1 = {}
      table.level1.level2 = {}
      table.level1.level2.level3 = "deep"
      assert.equals("deep", table.level1.level2.level3)
      assert.equals(3, called_count)
    end)

    it("triggers on_change at any depth", function()
      local called_count = 0
      local table = make_reactive_table(function()
        called_count = called_count + 1
      end)
      table.a = {}
      table.a.b = {}
      table.a.b.c = {}
      local initial_count = called_count
      table.a.b.c.value = "test"
      assert.equals(initial_count + 1, called_count)
      assert.equals("test", table.a.b.c.value)
    end)

    it("allows reading deep nested values", function()
      local table = make_reactive_table(function() end)
      table.project = {}
      table.project.settings = {}
      table.project.settings.lsp = {}
      table.project.settings.lsp.enabled = true
      assert.is_true(table.project.settings.lsp.enabled)
    end)

    it("allows updating deep nested values", function()
      local called_count = 0
      local table = make_reactive_table(function()
        called_count = called_count + 1
      end)
      table.app = {}
      table.app.config = {}
      table.app.config.timeout = 1000
      local initial_count = called_count
      table.app.config.timeout = 5000
      assert.equals(5000, table.app.config.timeout)
      assert.equals(initial_count + 1, called_count)
    end)

    it("supports very deep structures (5+ levels)", function()
      local called_count = 0
      local table = make_reactive_table(function()
        called_count = called_count + 1
      end)
      table.l1 = {}
      table.l1.l2 = {}
      table.l1.l2.l3 = {}
      table.l1.l2.l3.l4 = {}
      table.l1.l2.l3.l4.l5 = "very deep"
      assert.equals("very deep", table.l1.l2.l3.l4.l5)
      assert.equals(5, called_count)
    end)

    it("allows adding siblings at deep levels", function()
      local called_count = 0
      local table = make_reactive_table(function()
        called_count = called_count + 1
      end)
      table.root = {}
      table.root.child = {}
      table.root.child.grandchild = {}
      local initial_count = called_count
      table.root.child.sibling = "brother"
      assert.equals("brother", table.root.child.sibling)
      assert.equals(initial_count + 1, called_count)
    end)
  end)

  describe("complex scenarios", function()
    it("handles mixed types in nested structures", function()
      local table = make_reactive_table(function() end)
      table.config = {}
      table.config.enabled = true
      table.config.count = 42
      table.config.name = "test"
      table.config.nested = {}
      table.config.nested.value = "deep"
      assert.is_true(table.config.enabled)
      assert.equals(42, table.config.count)
      assert.equals("test", table.config.name)
      assert.equals("deep", table.config.nested.value)
    end)

    it("allows replacing nested table with different value", function()
      local called_count = 0
      local table = make_reactive_table(function()
        called_count = called_count + 1
      end)
      table.config = {}
      table.config.settings = {}
      table.config.settings.timeout = 1000
      local initial_count = called_count
      table.config.settings = "replaced"
      assert.equals("replaced", table.config.settings)
      assert.equals(initial_count + 1, called_count)
    end)

    it("supports array-like nested structures", function()
      local called_count = 0
      local table = make_reactive_table(function()
        called_count = called_count + 1
      end)
      table.array = {}
      table.array[1] = "first"
      table.array[2] = "second"
      table.array[3] = "third"
      assert.equals("first", table.array[1])
      assert.equals("second", table.array[2])
      assert.equals("third", table.array[3])
    end)

    it("allows reading multiple nested values", function()
      local table = make_reactive_table(function() end)
      table.config = {}
      table.config.a = 1
      table.config.b = 2
      table.config.c = 3

      assert.equals(1, table.config.a)
      assert.equals(2, table.config.b)
      assert.equals(3, table.config.c)
    end)

    it("handles sparse nested tables", function()
      local table = make_reactive_table(function() end)
      table.sparse = {}
      table.sparse[1] = "one"
      table.sparse[5] = "five"
      table.sparse[10] = "ten"
      assert.equals("one", table.sparse[1])
      assert.equals("five", table.sparse[5])
      assert.equals("ten", table.sparse[10])
    end)

    it("clears nested table values correctly", function()
      local called_count = 0
      local table = make_reactive_table(function()
        called_count = called_count + 1
      end)
      table.config = {}
      table.config.keep = "this"
      table.config.remove = "that"
      local initial_count = called_count
      table.config.remove = nil
      assert.is_nil(table.config.remove)
      assert.equals("this", table.config.keep)
      assert.equals(initial_count + 1, called_count)
    end)
  end)

  describe("integration with ctx.json", function()
    it("creates ctx.json as reactive table in setup", function()
      local npc = require("nvim-project-config")
      npc.setup()
      assert.is_not_nil(npc.ctx.json)
      assert.is_not_nil(getmetatable(npc.ctx.json))
      npc.ctx = old_ctx
    end)

    it("allows writing to ctx.json", function()
      local npc = require("nvim-project-config")
      npc.setup()
      npc.ctx.json.test_key = "test_value"
      assert.equals("test_value", npc.ctx.json.test_key)
      npc.ctx = old_ctx
    end)

    it("creates nested reactive tables in ctx.json", function()
      local npc = require("nvim-project-config")
      npc.setup()
      npc.ctx.json.config = {}
      assert.is_not_nil(getmetatable(npc.ctx.json.config))
      npc.ctx.json.config.value = "nested"
      assert.equals("nested", npc.ctx.json.config.value)
      npc.ctx = old_ctx
    end)

    it("allows deep nesting in ctx.json", function()
      local npc = require("nvim-project-config")
      npc.setup()
      npc.ctx.json.level1 = {}
      npc.ctx.json.level1.level2 = {}
      npc.ctx.json.level1.level2.level3 = "deep"
      assert.equals("deep", npc.ctx.json.level1.level2.level3)
      npc.ctx = old_ctx
    end)

    it("clear recreates reactive ctx.json", function()
      local npc = require("nvim-project-config")
      npc.setup()
      npc.ctx.json.test = "before"
      npc.clear()
      assert.is_not_nil(npc.ctx.json)
      assert.is_not_nil(getmetatable(npc.ctx.json))
      assert.is_nil(npc.ctx.json.test)
      npc.ctx = old_ctx
    end)
  end)

  describe("parent_path tracking", function()
    it("tracks parent_path for nested tables", function()
      local captured_paths = {}
      local function make_tracked_reactive(on_change, parent_path)
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
              table.insert(captured_paths, vim.list_extend({}, path))
              value = make_tracked_reactive(on_change, path)
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

      local table = make_tracked_reactive(function() end)
      table.a = {}
      table.a.b = {}
      table.a.b.c = {}

      assert.equals(3, #captured_paths)
      assert.equals("a", captured_paths[1][1])
      assert.equals("b", captured_paths[2][2])
      assert.equals("c", captured_paths[3][3])
    end)
  end)
end)
