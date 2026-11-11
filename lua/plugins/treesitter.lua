-- Treesitter Configuration for Scheme & AST Navigation
return {
  "nvim-treesitter/nvim-treesitter",
  branch = "master",
  build = ":TSUpdate",
  lazy = false,
  config = function()
    require("nvim-treesitter.configs").setup({
      ensure_installed = { "scheme", "query" },
      sync_install = false,
      auto_install = false,
      highlight = {
        enable = true,
        additional_vim_regex_highlighting = false,
      },
      incremental_selection = {
        enable = true,
        keymaps = {
          -- Shortcut 1: Alt + K (向外扩选 / Expand AST selection)
          init_selection = "<M-k>",
          node_incremental = "<M-k>",
          scope_incremental = false,
          -- Shortcut 7: Alt + Shift + K (向内收缩 / Contract AST selection)
          node_decremental = "<M-K>",
        },
      },
    })
  end,
}
