describe("DirectoryCache", function()
  local uv = require("plenary.async").uv
  local tmp_dir
  local dir_cache

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
    tmp_dir = "/tmp/npc-test-dir-" .. vim.loop.os_getpid()
    uv.fs_mkdir(tmp_dir, 493)
    dir_cache = require("nvim-project-config.cache.directory").new({
      trust_mtime = true,
    })
  end)

  after_each(function()
    cleanup()
    dir_cache:clear_all()
  end)

  describe("cache structure", function()
    it("has _cache table", function()
      assert.is_not_nil(dir_cache._cache)
      assert.equals("table", type(dir_cache._cache))
    end)

    it("has _trust_mtime option", function()
      assert.is_true(dir_cache._trust_mtime)
    end)
  end)

  describe("clear_all", function()
    it("removes all cached entries", function()
      dir_cache._cache["/dir1"] = { path = "/dir1", entries = {} }
      dir_cache._cache["/dir2"] = { path = "/dir2", entries = {} }

      dir_cache:clear_all()

      assert.is_nil(next(dir_cache._cache))
    end)
  end)

  describe("invalidate", function()
    it("removes specific entry from cache", function()
      dir_cache._cache["/test"] = {
        path = "/test",
        entries = { { name = "file.lua" } },
        mtime = 1234567890,
      }

      dir_cache:invalidate("/test")

      local cache = dir_cache._cache["/test"]
      assert.is_nil(cache)
    end)
  end)

  describe("trust_mtime option", function()
    it("can be set to false", function()
      local no_cache = require("nvim-project-config.cache.directory").new({
        trust_mtime = false,
      })
      assert.is_false(no_cache._trust_mtime)
    end)

    it("defaults to true", function()
      local default_cache = require("nvim-project-config.cache.directory").new()
      assert.is_true(default_cache._trust_mtime)
    end)
  end)

  describe("cache entry structure", function()
    it("stores complete entry structure", function()
      dir_cache._cache["/test-dir"] = {
        path = "/test-dir",
        entries = {
          { name = "file1.lua", type = "file" },
          { name = "file2.lua", type = "file" },
          { name = "subdir", type = "directory" },
        },
        mtime = 1234567890,
      }

      local cached = dir_cache._cache["/test-dir"]
      assert.equals("/test-dir", cached.path)
      assert.is_not_nil(cached.entries)
      assert.equals(3, #cached.entries)
      assert.equals(1234567890, cached.mtime)
    end)
  end)
end)
