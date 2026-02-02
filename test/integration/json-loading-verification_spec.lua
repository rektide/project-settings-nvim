local async = require("plenary.async")

-- Test that JSON files are actually loaded from ~/.config/astrovim-git/projects/

describe("JSON loading verification", function()
  it("loads JSON files from astrovim-git/projects directory", function()
    local npc = require("nvim-project-config")

    -- Setup with astrovim projects directory
    npc.setup({
      config_dir = "/home/rektide/.config/astrovim-git/projects",
      loading = { on = "manual" },
    })

    async.run(function()
      local awaiter = npc.load_await()
      local ctx = awaiter()

      print("\n=== JSON Loading Verification ===")
      print("Project:", ctx.project_name or "nil")
      print("Config dir:", ctx.config_dir or "nil")
      print()

      -- Check if JSON files were loaded
      print("=== ctx.json contents ===")
      if ctx.json then
        local count = 0
        for k, v in pairs(ctx.json) do
          count = count + 1
          print(string.format("  %s: %s", k, vim.inspect(v)))
        end
        print(string.format("Total entries: %d", count))

        -- Verify some expected files exist
        assert.is_not_nil(ctx.json["nvim-project-config"], "nvim-project-config.json should be loaded")
        assert.is_not_nil(ctx.json.repo, "repo.json should be loaded")
        assert.is_not_nil(ctx.json.plugin, "plugin.json should be loaded")

        print("\n✅ SUCCESS: JSON files loaded successfully")
      else
        print("  (empty - no JSON files loaded)")
        assert.fail("ctx.json should not be empty - JSON files should be loaded")
      end
    end)
  end)

  it("verifies nvim-project-config.json content is loaded", function()
    local npc = require("nvim-project-config")

    npc.setup({
      config_dir = "/home/rektide/.config/astrovim-git/projects",
      loading = { on = "manual" },
    })

    async.run(function()
      local awaiter = npc.load_await()
      local ctx = awaiter()

      print("\n=== nvim-project-config.json content ===")
      if ctx.json and ctx.json["nvim-project-config"] then
        print("Content:", vim.inspect(ctx.json["nvim-project-config"]))

        -- Verify the actual content
        local content = ctx.json["nvim-project-config"]
        assert.is_not_nil(content.color_persist, "color_persist field should exist")
        assert.equals("blink", content.color_persist, "color_persist should be 'blink'")

        print("\n✅ SUCCESS: nvim-project-config.json loaded correctly")
      else
        assert.fail("nvim-project-config.json should be loaded into ctx.json")
      end
    end)
  end)

  it("verifies repo.json content is loaded", function()
    local npc = require("nvim-project-config")

    npc.setup({
      config_dir = "/home/rektide/.config/astrovim-git/projects",
      loading = { on = "manual" },
    })

    async.run(function()
      local awaiter = npc.load_await()
      local ctx = awaiter()

      print("\n=== repo.json content ===")
      if ctx.json and ctx.json.repo then
        print("Content:", vim.inspect(ctx.json.repo))

        local content = ctx.json.repo
        assert.is_not_nil(content.test, "test field should exist")
        assert.equals("successful", content.test, "test should be 'successful'")

        print("\n✅ SUCCESS: repo.json loaded correctly")
      else
        assert.fail("repo.json should be loaded into ctx.json")
      end
    end)
  end)

  it("verifies multiple JSON files are loaded", function()
    local npc = require("nvim-project-config")

    npc.setup({
      config_dir = "/home/rektide/.config/astrovim-git/projects",
      loading = { on = "manual" },
    })

    async.run(function()
      local awaiter = npc.load_await()
      local ctx = awaiter()

      print("\n=== Verifying multiple JSON files loaded ===")

      -- List files that should exist
      local expected_files = {
        "nvim-project-config",
        "repo",
        "plugin",
        "src",
        "doc",
        "color_persist",
        "color_persist_nvim",
        "archive_list",
        "gunshi_mcp",
        "nvim_auto_listen",
        "req_gov",
      }

      local loaded_count = 0
      local missing_files = {}

      for _, file_key in ipairs(expected_files) do
        if ctx.json and ctx.json[file_key] then
          loaded_count = loaded_count + 1
          print(string.format("  ✓ %s.json", file_key))
        else
          table.insert(missing_files, file_key)
          print(string.format("  ✗ %s.json (MISSING)", file_key))
        end
      end

      print(string.format("\nLoaded %d/%d expected files", loaded_count, #expected_files))

      -- At least the key files should be loaded
      assert.is_true(
        ctx.json ~= nil and ctx.json.nvim_project_config ~= nil and ctx.json.repo ~= nil,
        "At least nvim-project-config.json and repo.json should be loaded"
      )

      if #missing_files == 0 then
        print("\n✅ SUCCESS: All expected JSON files loaded")
      else
        print(string.format("⚠ WARNING: %d files missing from ctx.json", #missing_files))
      end
    end)
  end)
end)
