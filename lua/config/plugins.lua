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

-- 3. Strict Paredit: Balanced delimiters & paired deletion
pcall(function()
  require("strict-paredit").setup()
end)

-- 4. nvim-paredit: S-expression editing & slurp/barf shortcuts
pcall(function()
  local paredit = require("nvim-paredit")
  paredit.setup({
    use_default_keys = false,
    indent = {
      enabled = true,
    },
    keys = {
      ["<M-S>"] = { paredit.api.slurp_forwards, "Slurp Forward (Alt+Shift+S)" },
      ["<M-B>"] = { paredit.api.barf_forwards, "Barf Forward (Alt+Shift+B)" },
      ["<M-s>"] = { paredit.api.slurp_backwards, "Slurp Backward (Alt+s)" },
      ["<M-b>"] = { paredit.api.barf_backwards, "Barf Backward (Alt+b)" },
      ["<M-w>"] = { paredit.api.wrap_element_under_cursor("( ", " )"), "Wrap with () (Alt+W)" },
      ["<M-W>"] = { paredit.api.wrap_enclosing_form_under_cursor("( ", " )"), "Wrap enclosing with () (Alt+Shift+W)" },
      ["<M-q>"] = { paredit.api.splice, "Splice / Raise (Alt+Q)" },
      ["<M-Q>"] = { paredit.api.raise_form, "Raise enclosing form (Alt+Shift+Q)" },
      ["<M-J>"] = { paredit.api.join_form, "Join / Splice with next (Alt+Shift+J)" },
      ["<M-O>"] = { paredit.api.split_form, "Split / Break into two (Alt+Shift+O)" },
      ["<M-T>"] = { paredit.api.drag_form_forwards, "Transpose / Drag Forward (Alt+Shift+T)" },
      ["<M-R>"] = { paredit.api.drag_form_backwards, "Transpose / Drag Backward (Alt+Shift+R)" },
      [">)"] = { paredit.api.slurp_forwards, "Slurp Forward" },
      ["<)"] = { paredit.api.barf_forwards, "Barf Forward" },
      [">("] = { paredit.api.slurp_backwards, "Slurp Backward" },
      ["<("] = { paredit.api.barf_backwards, "Barf Backward" },
      ["<leader>w("] = { paredit.api.wrap_element_under_cursor("( ", " )"), "Wrap ()" },
      ["<leader>w["] = { paredit.api.wrap_element_under_cursor("[ ", " ]"), "Wrap []" },
      ["<leader>W("] = { paredit.api.wrap_enclosing_form_under_cursor("( ", " )"), "Wrap enclosing ()" },
      ["<leader>W["] = { paredit.api.wrap_enclosing_form_under_cursor("[ ", " ]"), "Wrap enclosing []" },
      ["<leader>@"] = { paredit.api.splice, "Splice form" },
      ["<leader>O"] = { paredit.api.split_form, "Split form" },
      ["<leader>J"] = { paredit.api.join_form, "Join form" },
    },
  })
end)
