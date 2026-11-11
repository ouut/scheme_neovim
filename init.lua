-- Neovim Scheme / Steel Development Environment Configuration
-- Main Entry Point (100% Self-Contained, Zero-Download, Offline-First)

local current_file = debug.getinfo(1, "S").source:sub(2)
local config_dir = vim.fn.fnamemodify(current_file, ":p:h")
local root_dir = vim.fn.fnamemodify(config_dir, ":h")

-- 1. Ensure config directory is in runtimepath
if not vim.tbl_contains(vim.opt.rtp:get(), config_dir) then
  vim.opt.rtp:prepend(config_dir)
end

-- 2. Add bundled and pre-installed plugins to runtimepath
local candidate_dirs = {
  root_dir .. "/plugins",
  vim.env.LAZY_PLUGINS_PATH,
  vim.fn.expand("~/.local/share/nvim/lazy"),
  vim.fn.stdpath("data") .. "/lazy",
}

for _, pdir in ipairs(candidate_dirs) do
  if vim.fn.isdirectory(pdir) == 1 then
    for _, name in ipairs(vim.fn.readdir(pdir)) do
      local p = pdir .. "/" .. name
      if vim.fn.isdirectory(p) == 1 and not vim.tbl_contains(vim.opt.rtp:get(), p) then
        vim.opt.rtp:append(p)
        local plugin_sub = p .. "/plugin"
        if vim.fn.isdirectory(plugin_sub) == 1 then
          for _, f in ipairs(vim.fn.readdir(plugin_sub)) do
            if f:match("%.lua$") or f:match("%.vim$") then
              vim.cmd("source " .. vim.fn.fnameescape(plugin_sub .. "/" .. f))
            end
          end
        end
      end
    end
  end
end

-- 3. Set leader keys
vim.g.mapleader = " "
vim.g.maplocalleader = ","

-- 4. Load core options, autocmds, and keymaps
require("config.options")
require("config.autocmds")
require("config.keymaps")

-- 5. Load and setup bundled plugins natively (offline, zero-download)
require("config.plugins")

-- 6. Load REPL and Shell Terminal
require("config.repl")
require("config.terminal")
