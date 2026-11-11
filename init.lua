-- Neovim Scheme / Steel Development Environment Configuration
-- Main Entry Point

-- Ensure config directory is in runtimepath (essential for portable all-in-one packaging)
local current_file = debug.getinfo(1, "S").source:sub(2)
local config_dir = vim.fn.fnamemodify(current_file, ":p:h")
if not vim.tbl_contains(vim.opt.rtp:get(), config_dir) then
  vim.opt.rtp:prepend(config_dir)
end

-- Set leader key before plugins are loaded
vim.g.mapleader = " "
vim.g.maplocalleader = ","

-- Load core configurations
require("config.options")
require("config.autocmds")
require("config.keymaps")
require("config.repl")
require("config.terminal")

-- Bootstrap & load lazy.nvim plugin manager
require("config.lazy")
