-- Neovim General Options
local opt = vim.opt

-- Line numbers
opt.number = true
opt.relativenumber = true

-- Tabs and indentation (Lisp/Scheme 2-space standard)
opt.tabstop = 2
opt.shiftwidth = 2
opt.softtabstop = 2
opt.expandtab = true
opt.autoindent = true

-- UI settings
opt.termguicolors = true
opt.signcolumn = "yes"
opt.cursorline = true
opt.showmode = false -- We can show mode in statusline or keep clean
opt.scrolloff = 8
opt.sidescrolloff = 8

-- Enable baseline syntax highlighting
vim.cmd("syntax enable")

-- Search settings
opt.ignorecase = true
opt.smartcase = true
opt.hlsearch = true
opt.incsearch = true

-- Behavior
opt.hidden = true
opt.splitbelow = true
opt.splitright = true
opt.timeoutlen = 400
opt.ttimeoutlen = 20
opt.updatetime = 250
opt.undofile = true
opt.swapfile = false

-- Better display of invisible characters
opt.list = true
opt.listchars = { tab = "» ", trail = "·", nbsp = "␣" }
