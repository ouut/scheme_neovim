-- Bundled Plugins Configuration (100% Offline & Pre-Packaged)

-- 1. Colorscheme: tokyonight
pcall(function()
  require("tokyonight").setup({
    style = "night",
    transparent = false,
    terminal_colors = true,
  })
  vim.cmd.colorscheme("tokyonight-night")
end)

-- 2. Treesitter: Initialize modules & configure Scheme AST Navigation
pcall(function()
  -- Explicitly initialize built-in modules (highlight, incremental_selection, etc.)
  require("nvim-treesitter").setup()

  require("nvim-treesitter.configs").setup({
    ensure_installed = {},
    sync_install = false,
    auto_install = false,
    highlight = {
      enable = true,
      additional_vim_regex_highlighting = true,
    },
    incremental_selection = {
      enable = true,
      keymaps = {
        init_selection = "<M-k>",
        node_incremental = "<M-k>",
        scope_incremental = false,
        node_decremental = "<M-K>",
      },
    },
  })
end)

-- 3. Strict Paredit Engine (docs/strict_paredit_algorithm_spec.md)
-- 包含全部 17 个单发结构化编辑快捷键、物理按键守卫、全局窗口漫游与 Tab 轮转
pcall(function()
  require("strict_paredit").setup()
end)
