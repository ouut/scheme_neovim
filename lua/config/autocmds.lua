-- Autocommands & Filetype associations

-- Filetype detection for Scheme & Rust Steel files
vim.filetype.add({
  extension = {
    scm = "scheme",
    ss = "scheme",
    steel = "scheme",
    sld = "scheme",
    rkt = "scheme",
  },
  filename = {
    [".steelrc"] = "scheme",
  },
})

local scheme_group = vim.api.nvim_create_augroup("SchemeCustomSettings", { clear = true })

-- Scheme specific buffer options
vim.api.nvim_create_autocmd("FileType", {
  group = scheme_group,
  pattern = { "scheme" },
  callback = function(ev)
    vim.bo[ev.buf].tabstop = 2
    vim.bo[ev.buf].shiftwidth = 2
    vim.bo[ev.buf].softtabstop = 2
    vim.bo[ev.buf].expandtab = true
    vim.bo[ev.buf].lisp = true
    vim.bo[ev.buf].commentstring = ";; %s"

    -- Ensure Tree-sitter parsing & highlighting explicitly starts on Scheme buffers
    pcall(vim.treesitter.start, ev.buf, "scheme")

    -- Steel / Scheme standard lisp keywords for indentation
    vim.opt_local.lispwords:append({
      "define", "define-syntax", "syntax-rules", "lambda", "let", "let*", "letrec", "letrec*",
      "if", "cond", "case", "when", "unless", "begin", "do", "match",
      "defn", "struct", "contract/",
    })
  end,
})

-- Default empty unnamed buffer to Scheme mode so steel-ide starts ready
vim.api.nvim_create_autocmd({ "VimEnter", "BufEnter" }, {
  group = scheme_group,
  callback = function(ev)
    local buf = ev.buf or vim.api.nvim_get_current_buf()
    if vim.fn.bufname(buf) == "" and vim.bo[buf].buftype == "" and vim.bo[buf].filetype == "" then
      vim.bo[buf].filetype = "scheme"
      pcall(vim.treesitter.start, buf, "scheme")
    end
  end,
})

-- Highlight on yank
local yank_group = vim.api.nvim_create_augroup("HighlightYank", { clear = true })
vim.api.nvim_create_autocmd("TextYankPost", {
  group = yank_group,
  callback = function()
    vim.highlight.on_yank({ higroup = "IncSearch", timeout = 150 })
  end,
})
