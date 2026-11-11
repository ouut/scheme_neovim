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
local candidate_dirs = {}
local function add_cand(dir)
  if dir and dir ~= "" then
    table.insert(candidate_dirs, dir)
    local norm = dir:gsub("\\", "/")
    if norm ~= dir then
      table.insert(candidate_dirs, norm)
    end
  end
end

add_cand(vim.env.STEEL_IDE_DIR and (vim.env.STEEL_IDE_DIR .. "/plugins"))
add_cand(root_dir .. "/plugins")
add_cand(config_dir .. "/plugins")
add_cand(vim.env.LAZY_PLUGINS_PATH)
add_cand(vim.fn.expand("~/.local/share/nvim/lazy"))
add_cand(vim.fn.stdpath("data") .. "/lazy")

local added = {}
for _, pdir in ipairs(candidate_dirs) do
  if vim.fn.isdirectory(pdir) == 1 then
    for _, name in ipairs(vim.fn.readdir(pdir)) do
      local p = pdir .. "/" .. name
      local norm_p = (vim.fs and vim.fs.normalize) and vim.fs.normalize(p) or p:gsub("\\", "/")
      if vim.fn.isdirectory(p) == 1 and not added[norm_p] then
        added[norm_p] = true
        if not vim.tbl_contains(vim.opt.rtp:get(), p) then
          vim.opt.rtp:append(p)
        end
        local plugin_sub = p .. "/plugin"
        if vim.fn.isdirectory(plugin_sub) == 1 then
          for _, f in ipairs(vim.fn.readdir(plugin_sub)) do
            if f:match("%.lua$") or f:match("%.vim$") then
              pcall(vim.cmd.source, plugin_sub .. "/" .. f)
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
