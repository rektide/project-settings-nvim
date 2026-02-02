-- Preload coop module before tests run
local coop_path = ".test-agent/coop.nvim/lua/?.lua;.test-agent/coop.nvim/lua/?/init.lua"
local project_path = "./lua/?.lua;./lua/?/init.lua"
local plenary_path = ".test-agent/plenary.nvim/lua/?.lua;.test-agent/plenary.nvim/lua/?/init.lua"

package.path = coop_path .. ";" .. project_path .. ";" .. plenary_path .. ";" .. package.path

-- Preload coop to make it available
package.preload["coop"] = loadfile(".test-agent/coop.nvim/lua/coop.lua")

-- Also preload coop.uv submodules
package.preload["coop.uv"] = loadfile(".test-agent/coop.nvim/lua/coop/uv.lua")
package.preload["coop.mpsc-queue"] = loadfile(".test-agent/coop.nvim/lua/coop/mpsc-queue.lua")
package.preload["coop.uv-utils"] = loadfile(".test-agent/coop.nvim/lua/coop/uv-utils.lua")
