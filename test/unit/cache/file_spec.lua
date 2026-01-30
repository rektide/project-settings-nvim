describe("FileCache", function()
  local uv = require("plenary.async").uv
  local tmp_dir
  local file_cache

  local function cleanup()
    if tmp_dir and uv.fs_stat(tmp_dir) then
      local function rm_recursive(path)
        local stat = uv.fs_stat(path)
        if stat and stat.type == "directory" then
          local fd = uv.fs_opendir(path)
          if fd then
            while true do
              local entries = uv.fs_readdir(fd)
              if not entries then
                break
              end
              for _, entry in ipairs(entries) do
                rm_recursive(path .. "/" .. entry.name)
              end
            end
            uv.fs_closedir(fd)
            uv.fs_rmdir(path)
          end
        else
          uv.fs_unlink(path)
        end
      end
      rm_recursive(tmp_dir)
    end
  end

  before_each(function()
    tmp_dir = "/tmp/npc-test-" .. vim.loop.os_getpid()
    uv.fs_mkdir(tmp_dir, 493)
    file_cache = require("nvim-project-config.cache.file").new({
      trust_mtime = true,
    })
  end)

  after_each(function()
    cleanup()
    file_cache:clear_all()
  end)

  describe("cache structure", function()
    it("has _cache table", function()
      assert.is_not_nil(file_cache._cache)
      assert.equals("table", type(file_cache._cache))
    end)

    it("has trust_mtime option", function()
      assert.is_true(file_cache.trust_mtime)
    end)
  end)

  describe("clear_all", function()
    it("removes all cached entries", function()
      file_cache._cache["/test1"] = { path = "/test1", content = "content1" }
      file_cache._cache["/test2"] = { path = "/test2", content = "content2" }

      file_cache:clear_all()

      assert.is_nil(next(file_cache._cache))
    end)
  end)

  describe("invalidate", function()
    it("removes specific entry from cache", function()
      file_cache._cache["/test"] = { path = "/test", content = "content" }

      file_cache:invalidate("/test")

      local cache = file_cache._cache["/test"]
      assert.is_nil(cache)
    end)
  end)

  describe("trust_mtime option", function()
    it("can be set to false", function()
      local no_cache = require("nvim-project-config.cache.file").new({
        trust_mtime = false,
      })
      assert.is_false(no_cache.trust_mtime)
    end)

    it("defaults to true", function()
      local default_cache = require("nvim-project-config.cache.file").new()
      assert.is_true(default_cache.trust_mtime)
    end)
  end)

  describe("cache entry structure", function()
    it("stores complete entry structure", function()
      file_cache._cache["/test.lua"] = {
        path = "/test.lua",
        content = "vim.opt.test = true",
        mtime = 1234567890,
        json = { key = "value" },
      }

      local entry = file_cache._cache["/test.lua"]
      assert.equals("/test.lua", entry.path)
      assert.equals("vim.opt.test = true", entry.content)
      assert.equals(1234567890, entry.mtime)
      assert.equals("value", entry.json.key)
    end)

    it("handles entry without json field", function()
      file_cache._cache["/test.lua"] = {
        path = "/test.lua",
        content = "vim.opt.test = true",
        mtime = 1234567890,
      }

      local entry = file_cache._cache["/test.lua"]
      assert.equals("/test.lua", entry.path)
      assert.equals("vim.opt.test = true", entry.content)
      assert.is_nil(entry.json)
    end)
  end)
end)
