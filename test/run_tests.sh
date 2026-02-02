#!/bin/bash
# Set LUA_PATH environment variable before running nvim
export LUA_PATH=".test-agent/coop.nvim/lua/?.lua;.test-agent/coop.nvim/lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;.test-agent/plenary.nvim/lua/?.lua;.test-agent/plenary.nvim/lua/?/init.lua;;"

# Run tests with clean Neovim instance
nvim --headless --clean -c 'lua require("plenary.test_harness").test_directory("'$1'")' -c 'qa!'
