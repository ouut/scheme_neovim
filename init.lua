-- Neovim Scheme / Steel Development Environment Configuration
-- Main Entry Point

-- Set leader key before plugins are loaded
vim.g.mapleader = " "
vim.g.maplocalleader = ","

-- Load core configurations
require("config.options")
require("config.autocmds")
require("config.keymaps")

-- Bootstrap & load lazy.nvim plugin manager
require("config.lazy")
