-- nvim-project-config plugin setup for lazy.nvim

local npc = require("nvim-project-config")

npc.setup()

-- Expose globally for easy access
_G.npc = npc
