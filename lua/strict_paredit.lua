-- =============================================================================
-- Scheme Strict Paredit Implementation Engine
-- Exact implementation according to docs/strict_paredit_algorithm_spec.md
-- =============================================================================

local M = {}

-- -----------------------------------------------------------------------------
-- 一、 语法模型与 AST 数据结构 (Syntax Model & AST Parser)
-- -----------------------------------------------------------------------------

local function is_space(b)
  return b == 32 or b == 9 or b == 10 or b == 13 or b == 12
end

local function is_delimiter(b)
  if is_space(b) then return true end
  return b == 40 or b == 41 or b == 91 or b == 93 or b == 123 or b == 125 or b == 34 or b == 59
end

--- 容错 AST 解析器：单遍有限状态机
---@param text string
---@return table SexpNode[]
function M.parseSexpressions(text)
  local stack = {}
  local roots = {}
  local i = 1
  local len = #text

  while i <= len do
    local b = text:byte(i)

    if is_space(b) then
      i = i + 1
    -- 单行注释：;.*$
    elseif b == 59 then
      local start_idx = i - 1
      while i <= len and text:byte(i) ~= 10 do
        i = i + 1
      end
      local node = { start = start_idx, ["end"] = i - 1, type = "comment" }
      if #stack > 0 then
        table.insert(stack[#stack].children, node)
      else
        table.insert(roots, node)
      end
    -- 字符字面量：#\space, #\a, #\( 等
    elseif b == 35 and i + 1 <= len and text:byte(i + 1) == 92 then
      local start_idx = i - 1
      i = i + 2
      while i <= len and not is_delimiter(text:byte(i)) do
        i = i + 1
      end
      local node = { start = start_idx, ["end"] = i - 1, type = "atom" }
      if #stack > 0 then
        table.insert(stack[#stack].children, node)
      else
        table.insert(roots, node)
      end
    -- 字符串字面量："([^"\\]|\\.)*"
    elseif b == 34 then
      local start_idx = i - 1
      i = i + 1
      while i <= len do
        local sb = text:byte(i)
        if sb == 92 and i + 1 <= len then
          i = i + 2
        elseif sb == 34 then
          i = i + 1
          break
        else
          i = i + 1
        end
      end
      local node = { start = start_idx, ["end"] = i - 1, type = "string" }
      if #stack > 0 then
        table.insert(stack[#stack].children, node)
      else
        table.insert(roots, node)
      end
    -- 开括号：(, [, {
    elseif b == 40 or b == 91 or b == 123 then
      local open_char = string.char(b)
      local close_char = open_char == "(" and ")" or (open_char == "[" and "]" or "}")
      local node = {
        start = i - 1,
        ["end"] = i,
        type = "list",
        openChar = open_char,
        closeChar = close_char,
        children = {},
      }
      table.insert(stack, { node = node, children = {} })
      i = i + 1
    -- 闭括号：), ], }
    elseif b == 41 or b == 93 or b == 125 then
      if #stack > 0 then
        local top = table.remove(stack)
        top.node["end"] = i
        top.node.children = top.children
        if #stack > 0 then
          table.insert(stack[#stack].children, top.node)
        else
          table.insert(roots, top.node)
        end
      end
      i = i + 1
    -- 原子标识符/数字 (atom)
    else
      local start_idx = i - 1
      while i <= len and not is_delimiter(text:byte(i)) do
        i = i + 1
      end
      local node = { start = start_idx, ["end"] = i - 1, type = "atom" }
      if #stack > 0 then
        table.insert(stack[#stack].children, node)
      else
        table.insert(roots, node)
      end
    end
  end

  -- 容错闭合：未闭合的开括号延展至文本末尾
  while #stack > 0 do
    local top = table.remove(stack)
    top.node["end"] = len
    top.node.children = top.children
    if #stack > 0 then
      table.insert(stack[#stack].children, top.node)
    else
      table.insert(roots, top.node)
    end
  end

  return roots
end

-- -----------------------------------------------------------------------------
-- 坐标与偏移量换算辅助函数 (Coordinate Converters)
-- -----------------------------------------------------------------------------

--- 将 0-indexed 字符偏移量转换为 (1-indexed row, 0-indexed col)
function M.offset_to_pos(text, offset)
  local row = 1
  local last_nl = 0
  local len = #text
  local target = math.min(math.max(offset, 0), len)
  for i = 1, target do
    if text:byte(i) == 10 then
      row = row + 1
      last_nl = i
    end
  end
  local col = target - last_nl
  return row, col
end

--- 将 (1-indexed row, 0-indexed col) 转换为 0-indexed 字符偏移量
function M.pos_to_offset(text, row, col)
  if row <= 1 then
    return math.min(math.max(col, 0), #text)
  end
  local cur_row = 1
  local len = #text
  for i = 1, len do
    if text:byte(i) == 10 then
      cur_row = cur_row + 1
      if cur_row == row then
        return math.min(i + col, len)
      end
    end
  end
  return len
end

--- 获取当前缓冲区的全量文本及当前光标偏移量
function M.get_buffer_context(bufnr)
  bufnr = bufnr or 0
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local text = table.concat(lines, "\n")
  local cursor = vim.api.nvim_win_get_cursor(0)
  local pos = M.pos_to_offset(text, cursor[1], cursor[2])
  return text, pos, cursor[1], cursor[2]
end

-- -----------------------------------------------------------------------------
-- 核心树检索辅助函数 (Core Tree Search Helpers)
-- -----------------------------------------------------------------------------

--- 检索严格包围当前偏移量 pos 的最内层 list 节点及其直接父列表
function M.findEnclosingWithParent(roots, pos)
  local enclosing = nil
  local parent = nil

  local function search(nodes, cur_parent)
    for _, node in ipairs(nodes) do
      if node.type == "list" and pos > node.start and pos < node["end"] then
        parent = enclosing or cur_parent
        enclosing = node
        if node.children and #node.children > 0 then
          search(node.children, node)
        end
      end
    end
  end

  search(roots, nil)
  return enclosing, parent
end

--- 检索覆盖 pos 的最小叶子节点
function M.findInnermostNodeAt(roots, pos)
  local result = nil
  local function search(nodes)
    for _, node in ipairs(nodes) do
      if pos >= node.start and pos <= node["end"] then
        result = node
        if node.children and #node.children > 0 then
          search(node.children)
        end
      end
    end
  end
  search(roots)
  return result
end

--- 检索位于 roots 顶层且覆盖 pos 的最外层 S 表达式
function M.findTopLevelNode(roots, pos)
  for _, node in ipairs(roots) do
    if pos >= node.start and pos <= node["end"] then
      return node
    end
  end
  return nil
end

-- -----------------------------------------------------------------------------
-- 二、 17 个 Strict Paredit 快捷键算法规范实现
-- -----------------------------------------------------------------------------

-- 全局选区历史栈（供 Alt+K 扩选 与 Alt+Shift+K 收缩）
local selection_history_stack = {}

--- 设置视觉选区
local function set_visual_selection(text, start_offset, end_offset)
  local r1, c1 = M.offset_to_pos(text, start_offset)
  local r2, c2 = M.offset_to_pos(text, end_offset)
  local mode = vim.fn.mode()
  if mode == "v" or mode == "V" or mode == "\22" then
    vim.cmd([[execute "normal! \<ESC>"]])
  end
  vim.api.nvim_win_set_cursor(0, { r1, c1 })
  vim.cmd("normal! v")
  local target_col = math.max(0, c2 - 1)
  vim.api.nvim_win_set_cursor(0, { r2, target_col })
end

--- 获取当前活动选区（若无选区返回 nil）
local function get_visual_selection(text)
  local mode = vim.fn.mode()
  if mode ~= "v" and mode ~= "V" and mode ~= "\22" then
    return nil
  end
  local s_start = vim.fn.getpos("v")
  local s_end = vim.api.nvim_win_get_cursor(0)
  local off1 = M.pos_to_offset(text, s_start[2], s_start[3] - 1)
  local off2 = M.pos_to_offset(text, s_end[1], s_end[2])
  local from_off = math.min(off1, off2)
  local to_off = math.max(off1, off2) + 1
  return from_off, to_off
end

--- 1. 向外扩选 Expand (Alt + K)
function M.expand()
  local text, pos = M.get_buffer_context()
  local from_off, to_off = get_visual_selection(text)
  if not from_off then
    from_off = pos
    to_off = pos
  end

  -- 保存当前选区到历史栈
  table.insert(selection_history_stack, { from = from_off, to = to_off })

  local roots = M.parseSexpressions(text)
  local candidate = nil
  local min_len = math.huge

  local function search(nodes)
    for _, node in ipairs(nodes) do
      if node.start <= from_off and node["end"] >= to_off and (node.start < from_off or node["end"] > to_off) then
        local l = node["end"] - node.start
        if l < min_len then
          min_len = l
          candidate = node
        end
      end
      if node.children and #node.children > 0 then
        search(node.children)
      end
    end
  end

  search(roots)

  if candidate then
    set_visual_selection(text, candidate.start, candidate["end"])
  end
end

--- 7. 向内收缩 Contract (Alt + Shift + K / Alt + I)
function M.contract()
  local text, pos = M.get_buffer_context()
  local from_off, to_off = get_visual_selection(text)
  if not from_off then
    return
  end

  -- 优先检查选区历史栈
  while #selection_history_stack > 0 do
    local prev = table.remove(selection_history_stack)
    if (prev.from > from_off or prev.to < to_off) and (prev.from ~= from_off or prev.to ~= to_off) then
      if prev.from == prev.to then
        vim.cmd([[execute "normal! \<ESC>"]])
        local r, c = M.offset_to_pos(text, prev.from)
        vim.api.nvim_win_set_cursor(0, { r, c })
      else
        set_visual_selection(text, prev.from, prev.to)
      end
      return
    end
  end

  -- AST 回退收缩
  local roots = M.parseSexpressions(text)
  local best_child = nil
  local max_len = -1

  local function search(nodes)
    for _, node in ipairs(nodes) do
      if node.start >= from_off and node["end"] <= to_off and (node.start > from_off or node["end"] < to_off) then
        local l = node["end"] - node.start
        if l > max_len then
          max_len = l
          best_child = node
        end
      end
      if node.children and #node.children > 0 then
        search(node.children)
      end
    end
  end

  search(roots)

  if best_child then
    set_visual_selection(text, best_child.start, best_child["end"])
  else
    -- 塌缩为单点光标
    vim.cmd([[execute "normal! \<ESC>"]])
    local r, c = M.offset_to_pos(text, from_off)
    vim.api.nvim_win_set_cursor(0, { r, c })
  end
end

--- 2. 发射求值 Eval REPL (Alt + Enter / Ctrl + Enter / Alt + E)
function M.eval_repl()
  local text, pos = M.get_buffer_context()
  local from_off, to_off = get_visual_selection(text)
  local code = nil
  local flash_start, flash_end = nil, nil

  if from_off and to_off and to_off > from_off then
    code = text:sub(from_off + 1, to_off)
    flash_start, flash_end = from_off, to_off
    vim.cmd([[execute "normal! \<ESC>"]])
  else
    local roots = M.parseSexpressions(text)
    local enclosing = M.findEnclosingWithParent(roots, pos)
    local target = enclosing or M.findInnermostNodeAt(roots, pos) or M.findTopLevelNode(roots, pos)
    if target then
      code = text:sub(target.start + 1, target["end"])
      flash_start, flash_end = target.start, target["end"]
    else
      code = vim.api.nvim_get_current_line()
      local cur_row = vim.api.nvim_win_get_cursor(0)[1]
      flash_start = M.pos_to_offset(text, cur_row, 0)
      flash_end = flash_start + #code
    end
  end

  if not code or vim.trim(code) == "" then
    return
  end

  -- 视觉闪烁反馈 (Visual Flash - 350ms)
  if flash_start and flash_end and flash_end > flash_start then
    local r1, c1 = M.offset_to_pos(text, flash_start)
    local r2, c2 = M.offset_to_pos(text, flash_end)
    local ns = vim.api.nvim_create_namespace("steel_eval_flash")
    pcall(function()
      if vim.highlight and vim.highlight.range then
        vim.highlight.range(0, ns, "IncSearch", { r1 - 1, c1 }, { r2 - 1, c2 }, { timeout = 350 })
      elseif vim.hl and vim.hl.range then
        vim.hl.range(0, ns, "IncSearch", { r1 - 1, c1 }, { r2 - 1, c2 }, { timeout = 350 })
      end
    end)
  end

  -- 送入 Steel REPL
  local repl = require("steel_repl")
  repl.send_text(code)
end

--- Calva 智能吸附计算函数 (Calva Smart Affinity)
function M.computeSmartWrap(text, pos, openChar, closeChar)
  openChar = openChar or "("
  closeChar = closeChar or ")"
  local roots = M.parseSexpressions(text)
  local enclosing = M.findEnclosingWithParent(roots, pos)
  local all_siblings = enclosing and (enclosing.children or {}) or roots
  local siblings = {}
  for _, s in ipairs(all_siblings) do
    if s.type ~= "comment" then
      table.insert(siblings, s)
    end
  end

  local target = nil
  local cursorType = "start"

  -- 1. 贴尾吸附 (Left Affinity / define| x)
  for _, s in ipairs(siblings) do
    if s["end"] == pos and pos > 0 and not is_space(text:byte(pos)) then
      target = s
      cursorType = "end"
      break
    end
  end

  -- 2. 内部吸附 (Inside token / def|ine)
  if not target then
    for _, s in ipairs(siblings) do
      if s.start < pos and pos < s["end"] then
        target = s
        cursorType = "inside"
        break
      end
    end
  end

  -- 3. 头部吸附 (Touching start / |define 或 define |x)
  if not target then
    for _, s in ipairs(siblings) do
      if s.start == pos then
        target = s
        cursorType = "start"
        break
      end
    end
  end

  -- 4. 空白处前向吸附 (Forward sibling in whitespace / define  |  x)
  if not target then
    for _, s in ipairs(siblings) do
      if s.start > pos then
        target = s
        cursorType = "forward"
        break
      end
    end
  end

  -- 计算替换内容与新光标位置
  if target then
    local targetText = text:sub(target.start + 1, target["end"])
    local newOffset
    if cursorType == "end" then
      newOffset = target["end"] + #openChar
    elseif cursorType == "inside" then
      newOffset = pos + #openChar
    else
      newOffset = target.start + #openChar
    end
    return {
      rangeStart = target.start,
      rangeEnd = target["end"],
      replacementText = openChar .. targetText .. closeChar,
      newOffset = newOffset,
    }
  else
    -- 5. 空白行或无目标：就地插入空对
    return {
      rangeStart = pos,
      rangeEnd = pos,
      replacementText = openChar .. closeChar,
      newOffset = pos + #openChar,
    }
  end
end

--- 执行文本替换并重置光标（单事务保证原子回滚）
local function apply_text_replacement(text, rangeStart, rangeEnd, replacementText, newOffset)
  local r1, c1 = M.offset_to_pos(text, rangeStart)
  local r2, c2 = M.offset_to_pos(text, rangeEnd)
  local lines = vim.split(replacementText, "\n", { plain = true })
  vim.api.nvim_buf_set_text(0, r1 - 1, c1, r2 - 1, c2, lines)

  if newOffset then
    local new_text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
    local nr, nc = M.offset_to_pos(new_text, newOffset)
    vim.api.nvim_win_set_cursor(0, { nr, nc })
  end
end

--- 3. 圆括号包裹 Wrap Parens - Calva 智能吸附 (Alt + H)
function M.wrap_parens()
  local text, pos = M.get_buffer_context()
  local from_off, to_off = get_visual_selection(text)
  if from_off and to_off and to_off > from_off then
    vim.cmd([[execute "normal! \<ESC>"]])
    local sel_text = text:sub(from_off + 1, to_off)
    apply_text_replacement(text, from_off, to_off, "(" .. sel_text .. ")", from_off + 1)
    return
  end

  local wrap = M.computeSmartWrap(text, pos, "(", ")")
  apply_text_replacement(text, wrap.rangeStart, wrap.rangeEnd, wrap.replacementText, wrap.newOffset)
end

--- 4. 方括号包裹 Wrap Square - Calva 智能吸附 (Alt + Shift + H)
function M.wrap_square()
  local text, pos = M.get_buffer_context()
  local from_off, to_off = get_visual_selection(text)
  if from_off and to_off and to_off > from_off then
    vim.cmd([[execute "normal! \<ESC>"]])
    local sel_text = text:sub(from_off + 1, to_off)
    apply_text_replacement(text, from_off, to_off, "[" .. sel_text .. "]", from_off + 1)
    return
  end

  local wrap = M.computeSmartWrap(text, pos, "[", "]")
  apply_text_replacement(text, wrap.rangeStart, wrap.rangeEnd, wrap.replacementText, wrap.newOffset)
end

--- 5. 向右吞噬 Slurp Forward (Alt + L)
function M.slurp_forward()
  local text, pos = M.get_buffer_context()
  local roots = M.parseSexpressions(text)
  local enc, par = M.findEnclosingWithParent(roots, pos)
  if not enc then return end

  local siblings = par and (par.children or {}) or roots
  local idx = nil
  for i, s in ipairs(siblings) do
    if s.start == enc.start and s["end"] == enc["end"] then
      idx = i
      break
    end
  end

  if not idx or idx >= #siblings then return end
  local next_sib = siblings[idx + 1]

  local close_char = enc.closeChar
  local before = text:sub(1, enc["end"] - 1)
  local mid = text:sub(enc["end"] + 1, next_sib["end"])
  local after = text:sub(next_sib["end"] + 1)
  mid = mid:gsub("^%s+", "")

  local new_text = before .. " " .. mid .. close_char .. after
  local new_lines = vim.split(new_text, "\n", { plain = true })
  vim.api.nvim_buf_set_lines(0, 0, -1, false, new_lines)

  -- 光标保持在原相对位置
  local nr, nc = M.offset_to_pos(new_text, pos)
  vim.api.nvim_win_set_cursor(0, { nr, nc })
end

--- 6. 向左吐出 Barf Forward (Alt + J)
function M.barf_forward()
  local text, pos = M.get_buffer_context()
  local roots = M.parseSexpressions(text)
  local enc, _ = M.findEnclosingWithParent(roots, pos)
  if not enc or not enc.children or #enc.children <= 1 then return end

  local children = {}
  for _, c in ipairs(enc.children) do
    if c.type ~= "comment" then
      table.insert(children, c)
    end
  end
  if #children <= 1 then return end

  local last_child = children[#children]
  local prev_child = children[#children - 1]
  local close_char = enc.closeChar

  local before = text:sub(1, prev_child["end"])
  local expelled = text:sub(last_child.start + 1, last_child["end"])
  local after = text:sub(enc["end"] + 1)

  local new_text = before .. close_char .. " " .. expelled .. after
  local new_lines = vim.split(new_text, "\n", { plain = true })
  vim.api.nvim_buf_set_lines(0, 0, -1, false, new_lines)

  -- 调整光标（若原光标在 expelled 项上，则跟随留在括号内侧闭括号前）
  local new_pos = math.min(pos, prev_child["end"])
  local nr, nc = M.offset_to_pos(new_text, new_pos)
  vim.api.nvim_win_set_cursor(0, { nr, nc })
end

--- 8. 选中顶级函数 Select Defun (Alt + 3)
function M.select_defun()
  local text, pos = M.get_buffer_context()
  local roots = M.parseSexpressions(text)
  local top = M.findTopLevelNode(roots, pos)
  if top then
    set_visual_selection(text, top.start, top["end"])
  end
end

--- 9. 脱壳解包 Splice (Alt + O)
function M.splice()
  local text, pos = M.get_buffer_context()
  local roots = M.parseSexpressions(text)
  local enc, _ = M.findEnclosingWithParent(roots, pos)
  if not enc then return end

  local inner_text = text:sub(enc.start + 2, enc["end"] - 1)
  apply_text_replacement(text, enc.start, enc["end"], inner_text, enc.start)
end

--- 10. 大步前进 Forward Sexp - Head-to-Head (Alt + 2)
function M.forward_sexp()
  local text, pos = M.get_buffer_context()
  local roots = M.parseSexpressions(text)
  local enc, _ = M.findEnclosingWithParent(roots, pos)
  local siblings = enc and (enc.children or {}) or roots

  local next_node = nil
  for _, s in ipairs(siblings) do
    if s.type ~= "comment" and s.start > pos then
      next_node = s
      break
    end
  end

  if next_node then
    local nr, nc = M.offset_to_pos(text, next_node.start)
    vim.api.nvim_win_set_cursor(0, { nr, nc })
  elseif enc then
    -- 右侧无兄弟，步出至外层闭括号右侧
    local nr, nc = M.offset_to_pos(text, enc["end"])
    vim.api.nvim_win_set_cursor(0, { nr, nc })
  end
end

--- 11. 大步后退 Backward Sexp - Head-to-Head (Alt + 1)
function M.backward_sexp()
  local text, pos = M.get_buffer_context()
  local roots = M.parseSexpressions(text)
  local enc, _ = M.findEnclosingWithParent(roots, pos)
  local siblings = enc and (enc.children or {}) or roots

  local prev_node = nil
  for _, s in ipairs(siblings) do
    if s.type ~= "comment" and s.start < pos then
      prev_node = s
    end
  end

  if prev_node then
    local nr, nc = M.offset_to_pos(text, prev_node.start)
    vim.api.nvim_win_set_cursor(0, { nr, nc })
  elseif enc then
    -- 左侧无兄弟，步出至外层开括号左侧
    local nr, nc = M.offset_to_pos(text, enc.start)
    vim.api.nvim_win_set_cursor(0, { nr, nc })
  end
end

--- 12. 步进深入 Step Into / Down (Alt + W)
function M.step_into()
  local text, pos = M.get_buffer_context()
  local roots = M.parseSexpressions(text)
  local enc, _ = M.findEnclosingWithParent(roots, pos)
  local siblings = enc and (enc.children or {}) or roots

  local child_list = nil
  for _, s in ipairs(siblings) do
    if s.type == "list" and s.start >= pos then
      child_list = s
      break
    end
  end

  if child_list then
    local nr, nc = M.offset_to_pos(text, child_list.start + 1)
    vim.api.nvim_win_set_cursor(0, { nr, nc })
  end
end

--- 13. 步退跳出 Step Out / Up (Alt + S)
function M.step_out()
  local text, pos = M.get_buffer_context()
  local roots = M.parseSexpressions(text)
  local enc, par = M.findEnclosingWithParent(roots, pos)
  if enc then
    local target_pos = enc.start
    if pos == enc.start and par then
      target_pos = par.start
    end
    local nr, nc = M.offset_to_pos(text, target_pos)
    vim.api.nvim_win_set_cursor(0, { nr, nc })
  end
end

--- 14. 向后整块删除 Kill Sexp (Alt + X)
function M.kill_sexp()
  local text, pos = M.get_buffer_context()
  local roots = M.parseSexpressions(text)
  local enc, _ = M.findEnclosingWithParent(roots, pos)
  local siblings = enc and (enc.children or {}) or roots

  local target = nil
  for _, s in ipairs(siblings) do
    if s.start >= pos then
      target = s
      break
    end
  end

  if target then
    -- 智能清除后续紧随的空白
    local end_del = target["end"]
    while end_del < #text and (text:byte(end_del + 1) == 32 or text:byte(end_del + 1) == 9) do
      end_del = end_del + 1
    end
    apply_text_replacement(text, pos, end_del, "", pos)
  end
end

--- 15. 智能格式排版 Indent (Alt + \)
function M.indent()
  local text, pos = M.get_buffer_context()
  local roots = M.parseSexpressions(text)
  local top = M.findTopLevelNode(roots, pos)
  local enc = M.findEnclosingWithParent(roots, pos)
  local target = top or enc

  if target then
    local r1, _ = M.offset_to_pos(text, target.start)
    local r2, _ = M.offset_to_pos(text, target["end"])
    vim.cmd(string.format("silent! %d,%dequal", r1, r2))
  else
    vim.cmd("silent! normal! ==")
  end
end

--- 16. 相邻参数对调 Transpose (Alt + Shift + L)
function M.transpose()
  local text, pos = M.get_buffer_context()
  local roots = M.parseSexpressions(text)
  local enc, _ = M.findEnclosingWithParent(roots, pos)
  local all_siblings = enc and (enc.children or {}) or roots
  local siblings = {}
  for _, s in ipairs(all_siblings) do
    if s.type ~= "comment" then
      table.insert(siblings, s)
    end
  end
  if #siblings < 2 then return end

  local prev_s, next_s = nil, nil
  for i, s in ipairs(siblings) do
    if pos >= s.start and pos <= s["end"] then
      if i < #siblings then
        prev_s = s
        next_s = siblings[i + 1]
      elseif i > 1 then
        prev_s = siblings[i - 1]
        next_s = s
      end
      break
    end
  end

  if not prev_s then
    for i = 1, #siblings - 1 do
      local s1, s2 = siblings[i], siblings[i + 1]
      if s1["end"] <= pos and s2.start >= pos then
        prev_s, next_s = s1, s2
        break
      end
    end
  end

  if prev_s and next_s then
    local prev_text = text:sub(prev_s.start + 1, prev_s["end"])
    local next_text = text:sub(next_s.start + 1, next_s["end"])
    local between = text:sub(prev_s["end"] + 1, next_s.start)
    local repl = next_text .. between .. prev_text
    apply_text_replacement(text, prev_s.start, next_s["end"], repl, prev_s.start + #next_text)
  end
end

--- 17. 列表切分 Split (Alt + Shift + J)
function M.split()
  local text, pos = M.get_buffer_context()
  local roots = M.parseSexpressions(text)
  local enc, _ = M.findEnclosingWithParent(roots, pos)
  if not enc then return end

  -- 裁剪光标左右的多余空格
  local split_start = pos
  while split_start > enc.start + 1 and is_space(text:byte(split_start)) do
    split_start = split_start - 1
  end

  local split_end = pos
  while split_end < enc["end"] - 1 and is_space(text:byte(split_end + 1)) do
    split_end = split_end + 1
  end

  local insert_text = enc.closeChar .. " " .. enc.openChar
  apply_text_replacement(text, split_start, split_end, insert_text, split_start + #enc.closeChar + 1)
end

-- -----------------------------------------------------------------------------
-- 三、 Pure Strict Paredit 物理按键守卫算法 (Physical Key Guards)
-- -----------------------------------------------------------------------------

--- 退格键拦截状态机 (Backspace Guard)
function M.handle_backspace()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local ch_before = col > 0 and line:sub(col, col) or ""
  local ch_at = line:sub(col + 1, col + 1)

  -- 1. 空括号对协同删除：(|) -> 清空
  if (ch_before == "(" and ch_at == ")") or (ch_before == "[" and ch_at == "]") or (ch_before == "{" and ch_at == "}") then
    return vim.api.nvim_replace_termcodes("<BS><Del>", true, true, true)
  end

  -- 2. 非空列表开括号右侧：(|foo) -> 硬拦截
  if ch_before == "(" or ch_before == "[" or ch_before == "{" then
    vim.notify("Strict Paredit: Cannot delete open delimiter of non-empty form", vim.log.levels.WARN)
    return ""
  end

  -- 3. 闭括号右侧：(foo)| -> 步进跳入内侧 (foo|)
  if ch_before == ")" or ch_before == "]" or ch_before == "}" then
    return vim.api.nvim_replace_termcodes("<Left>", true, true, true)
  end

  -- 默认放行
  return vim.api.nvim_replace_termcodes("<BS>", true, true, true)
end

--- 删除键拦截状态机 (Delete Guard)
function M.handle_delete()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local ch_at = line:sub(col + 1, col + 1)
  local ch_next = line:sub(col + 2, col + 2)
  local ch_before = col > 0 and line:sub(col, col) or ""

  -- 1. 空括号对协同删除：|() -> 清空
  if (ch_at == "(" and ch_next == ")") or (ch_at == "[" and ch_next == "]") or (ch_at == "{" and ch_next == "}") then
    return vim.api.nvim_replace_termcodes("<Del><Del>", true, true, true)
  end

  -- 2. 非空闭括号左侧：(foo|) -> 硬拦截
  if ch_at == ")" or ch_at == "]" or ch_at == "}" then
    if not ((ch_before == "(" and ch_at == ")") or (ch_before == "[" and ch_at == "]") or (ch_before == "{" and ch_at == "}")) then
      vim.notify("Strict Paredit: Cannot delete close delimiter of non-empty form", vim.log.levels.WARN)
      return ""
    end
  end

  return vim.api.nvim_replace_termcodes("<Del>", true, true, true)
end

--- 闭括号穿透跳跃 (Close Delimiter Step-over)
function M.handle_close_char(char)
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local ch_at = line:sub(col + 1, col + 1)

  if ch_at == char then
    return vim.api.nvim_replace_termcodes("<Right>", true, true, true)
  end
  return char
end

--- 开括号自动配对并居中光标
function M.handle_open_char(open_char, close_char)
  return open_char .. close_char .. vim.api.nvim_replace_termcodes("<Left>", true, true, true)
end

--- 普通模式 x 键守卫（删除空对，阻止破坏平衡）
function M.handle_normal_x()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local ch = line:sub(col + 1, col + 1)
  local ch_next = line:sub(col + 2, col + 2)
  local ch_prev = col > 0 and line:sub(col, col) or ""

  if (ch == "(" and ch_next == ")") or (ch == "[" and ch_next == "]") or (ch == "{" and ch_next == "}") then
    return "xx"
  end

  if ch == "(" or ch == "[" or ch == "{" or ch == ")" or ch == "]" or ch == "}" then
    vim.notify("Strict Paredit: Direct deletion of structural delimiter blocked! Use Alt+O (Splice) or Alt+X (Kill)", vim.log.levels.WARN)
    return ""
  end

  return "x"
end

-- -----------------------------------------------------------------------------
-- 四、 全局窗口漫游与 Tab 轮转算法 (Window Roaming & Tab Cycling)
-- -----------------------------------------------------------------------------

--- 聚焦编辑器 (Alt + Shift + Up)
function M.focus_editor()
  local cur_win = vim.api.nvim_get_current_win()
  local cur_buf = vim.api.nvim_win_get_buf(cur_win)
  if vim.bo[cur_buf].buftype == "terminal" then
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local b = vim.api.nvim_win_get_buf(win)
      if vim.bo[b].buftype == "" then
        vim.api.nvim_set_current_win(win)
        return
      end
    end
  end

  if vim.fn.bufname("%") == "" and vim.bo.buftype == "" and vim.bo.filetype == "" then
    vim.bo.filetype = "scheme"
  end
end

--- 聚焦终端 (Alt + Shift + Down)
function M.focus_terminal()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local b = vim.api.nvim_win_get_buf(win)
    if vim.bo[b].buftype == "terminal" then
      vim.api.nvim_set_current_win(win)
      vim.cmd("startinsert")
      return
    end
  end

  -- 若未打开，则拉起 REPL 并聚焦
  require("steel_repl").ensure_repl()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local b = vim.api.nvim_win_get_buf(win)
    if vim.bo[b].buftype == "terminal" then
      vim.api.nvim_set_current_win(win)
      vim.cmd("startinsert")
      return
    end
  end
end

--- 双向无缝回环切 Tab (cycleTab with wrap-around)
function M.cycle_tab(direction)
  local bufs = vim.fn.getbufinfo({ buflisted = 1 })
  if #bufs <= 1 then return end

  local cur_buf = vim.api.nvim_get_current_buf()
  local cur_idx = -1
  for i, b in ipairs(bufs) do
    if b.bufnr == cur_buf then
      cur_idx = i
      break
    end
  end

  if cur_idx == -1 then return end
  local next_idx = ((cur_idx - 1 + direction) % #bufs) + 1
  vim.api.nvim_set_current_buf(bufs[next_idx].bufnr)
end

-- -----------------------------------------------------------------------------
-- 五、 快捷键与物理守卫绑定主注册函数 (Setup & Bindings)
-- -----------------------------------------------------------------------------

function M.setup()
  local function bind_all(bufnr)
    local opts = bufnr and { buffer = bufnr, silent = true } or { silent = true }
    local expr_opts = bufnr and { buffer = bufnr, silent = true, expr = true } or { silent = true, expr = true }

    -- 1. 向外扩选 Expand (Alt + K)
    vim.keymap.set({ "n", "v" }, "<M-k>", M.expand, vim.tbl_extend("force", opts, { desc = "Expand Selection (Alt+K)" }))
    vim.keymap.set({ "n", "v" }, "\x1bk", M.expand, vim.tbl_extend("force", opts, { desc = "Expand Selection (Esc+K)" }))

    -- 7. 向内收缩 Contract (Alt + Shift + K / Alt + I)
    vim.keymap.set({ "n", "v" }, "<M-K>", M.contract, vim.tbl_extend("force", opts, { desc = "Contract Selection (Alt+Shift+K)" }))
    vim.keymap.set({ "n", "v" }, "<M-i>", M.contract, vim.tbl_extend("force", opts, { desc = "Contract Selection (Alt+I)" }))
    vim.keymap.set({ "n", "v" }, "\x1bK", M.contract, vim.tbl_extend("force", opts, { desc = "Contract Selection" }))
    vim.keymap.set({ "n", "v" }, "\x1bi", M.contract, vim.tbl_extend("force", opts, { desc = "Contract Selection" }))

    -- 2. 发射求值 Eval REPL (Alt + Enter / Ctrl + Enter / Alt + E)
    vim.keymap.set({ "n", "v" }, "<M-CR>", M.eval_repl, vim.tbl_extend("force", opts, { desc = "Eval in Steel REPL (Alt+Enter)" }))
    vim.keymap.set({ "n", "v" }, "<C-CR>", M.eval_repl, vim.tbl_extend("force", opts, { desc = "Eval in Steel REPL (Ctrl+Enter)" }))
    vim.keymap.set({ "n", "v" }, "<M-e>", M.eval_repl, vim.tbl_extend("force", opts, { desc = "Eval in Steel REPL (Alt+E)" }))
    vim.keymap.set({ "n", "v" }, "<leader><CR>", M.eval_repl, vim.tbl_extend("force", opts, { desc = "Eval in Steel REPL" }))
    vim.keymap.set({ "n", "v" }, "<leader>se", M.eval_repl, vim.tbl_extend("force", opts, { desc = "Eval in Steel REPL" }))

    -- 3. 圆括号包裹 Wrap Parens (Alt + H) - Calva Smart Affinity
    vim.keymap.set({ "n", "v" }, "<M-h>", M.wrap_parens, vim.tbl_extend("force", opts, { desc = "Smart Wrap ( ) (Alt+H)" }))
    vim.keymap.set({ "n", "v" }, "\x1bh", M.wrap_parens, vim.tbl_extend("force", opts, { desc = "Smart Wrap ( ) (Esc+H)" }))
    vim.keymap.set("n", "<leader>w(", M.wrap_parens, vim.tbl_extend("force", opts, { desc = "Smart Wrap ( )" }))

    -- 4. 方括号包裹 Wrap Square (Alt + Shift + H) - Calva Smart Affinity
    vim.keymap.set({ "n", "v" }, "<M-H>", M.wrap_square, vim.tbl_extend("force", opts, { desc = "Smart Wrap [ ] (Alt+Shift+H)" }))
    vim.keymap.set("n", "<leader>w[", M.wrap_square, vim.tbl_extend("force", opts, { desc = "Smart Wrap [ ]" }))

    -- 5. 向右吞噬 Slurp Forward (Alt + L)
    vim.keymap.set("n", "<M-l>", M.slurp_forward, vim.tbl_extend("force", opts, { desc = "Slurp Forward (Alt+L)" }))
    vim.keymap.set("n", "\x1bl", M.slurp_forward, vim.tbl_extend("force", opts, { desc = "Slurp Forward (Esc+L)" }))
    vim.keymap.set("n", ">)", M.slurp_forward, vim.tbl_extend("force", opts, { desc = "Slurp Forward" }))
    vim.keymap.set("n", "<leader>sl", M.slurp_forward, vim.tbl_extend("force", opts, { desc = "Slurp Forward" }))

    -- 6. 向左吐出 Barf Forward (Alt + J)
    vim.keymap.set("n", "<M-j>", M.barf_forward, vim.tbl_extend("force", opts, { desc = "Barf Forward (Alt+J)" }))
    vim.keymap.set("n", "\x1bj", M.barf_forward, vim.tbl_extend("force", opts, { desc = "Barf Forward (Esc+J)" }))
    vim.keymap.set("n", "<)", M.barf_forward, vim.tbl_extend("force", opts, { desc = "Barf Forward" }))
    vim.keymap.set("n", "<leader>ba", M.barf_forward, vim.tbl_extend("force", opts, { desc = "Barf Forward" }))

    -- 8. 选中顶级函数 Select Defun (Alt + 3)
    vim.keymap.set({ "n", "v" }, "<M-3>", M.select_defun, vim.tbl_extend("force", opts, { desc = "Select Defun (Alt+3)" }))
    vim.keymap.set({ "n", "v" }, "\x1b3", M.select_defun, vim.tbl_extend("force", opts, { desc = "Select Defun (Esc+3)" }))
    vim.keymap.set({ "n", "v" }, "<M-k3>", M.select_defun, vim.tbl_extend("force", opts, { desc = "Select Defun (Alt+Numpad3)" }))
    vim.keymap.set({ "n", "v" }, "<leader>3", M.select_defun, vim.tbl_extend("force", opts, { desc = "Select Defun" }))

    -- 9. 脱壳解包 Splice (Alt + O)
    vim.keymap.set("n", "<M-o>", M.splice, vim.tbl_extend("force", opts, { desc = "Splice / Unwrap (Alt+O)" }))
    vim.keymap.set("n", "\x1bo", M.splice, vim.tbl_extend("force", opts, { desc = "Splice / Unwrap (Esc+O)" }))
    vim.keymap.set("n", "<leader>sp", M.splice, vim.tbl_extend("force", opts, { desc = "Splice / Unwrap" }))

    -- 10. 大步前进 Forward Sexp (Alt + 2)
    vim.keymap.set("n", "<M-2>", M.forward_sexp, vim.tbl_extend("force", opts, { desc = "Forward Sexp (Alt+2)" }))
    vim.keymap.set("n", "\x1b2", M.forward_sexp, vim.tbl_extend("force", opts, { desc = "Forward Sexp (Esc+2)" }))
    vim.keymap.set("n", "<M-k2>", M.forward_sexp, vim.tbl_extend("force", opts, { desc = "Forward Sexp (Alt+Numpad2)" }))
    vim.keymap.set("n", "<leader>2", M.forward_sexp, vim.tbl_extend("force", opts, { desc = "Forward Sexp" }))
    vim.keymap.set("n", "]e", M.forward_sexp, vim.tbl_extend("force", opts, { desc = "Forward Sexp" }))

    -- 11. 大步后退 Backward Sexp (Alt + 1)
    vim.keymap.set("n", "<M-1>", M.backward_sexp, vim.tbl_extend("force", opts, { desc = "Backward Sexp (Alt+1)" }))
    vim.keymap.set("n", "\x1b1", M.backward_sexp, vim.tbl_extend("force", opts, { desc = "Backward Sexp (Esc+1)" }))
    vim.keymap.set("n", "<M-k1>", M.backward_sexp, vim.tbl_extend("force", opts, { desc = "Backward Sexp (Alt+Numpad1)" }))
    vim.keymap.set("n", "<leader>1", M.backward_sexp, vim.tbl_extend("force", opts, { desc = "Backward Sexp" }))
    vim.keymap.set("n", "[e", M.backward_sexp, vim.tbl_extend("force", opts, { desc = "Backward Sexp" }))

    -- 12. 步进深入 Step Into (Alt + W)
    vim.keymap.set("n", "<M-w>", M.step_into, vim.tbl_extend("force", opts, { desc = "Step Into (Alt+W)" }))
    vim.keymap.set("n", "\x1bw", M.step_into, vim.tbl_extend("force", opts, { desc = "Step Into (Esc+W)" }))
    vim.keymap.set("n", "]f", M.step_into, vim.tbl_extend("force", opts, { desc = "Step Into" }))

    -- 13. 步退跳出 Step Out (Alt + S)
    vim.keymap.set("n", "<M-s>", M.step_out, vim.tbl_extend("force", opts, { desc = "Step Out (Alt+S)" }))
    vim.keymap.set("n", "\x1bs", M.step_out, vim.tbl_extend("force", opts, { desc = "Step Out (Esc+S)" }))
    vim.keymap.set("n", "[f", M.step_out, vim.tbl_extend("force", opts, { desc = "Step Out" }))

    -- 14. 向后整块删除 Kill Sexp (Alt + X)
    vim.keymap.set("n", "<M-x>", M.kill_sexp, vim.tbl_extend("force", opts, { desc = "Kill Sexp (Alt+X)" }))
    vim.keymap.set("n", "\x1bx", M.kill_sexp, vim.tbl_extend("force", opts, { desc = "Kill Sexp (Esc+X)" }))
    vim.keymap.set("n", "<leader>k", M.kill_sexp, vim.tbl_extend("force", opts, { desc = "Kill Sexp" }))

    -- 15. 智能格式排版 Indent (Alt + \)
    vim.keymap.set({ "n", "v" }, "<M-\\>", M.indent, vim.tbl_extend("force", opts, { desc = "Indent Form / Selection (Alt+\\)" }))
    vim.keymap.set({ "n", "v" }, "\x1b\\", M.indent, vim.tbl_extend("force", opts, { desc = "Indent Form / Selection" }))
    vim.keymap.set({ "n", "v" }, "<leader>=", M.indent, vim.tbl_extend("force", opts, { desc = "Indent Form / Selection" }))

    -- 16. 相邻参数对调 Transpose (Alt + Shift + L)
    vim.keymap.set("n", "<M-L>", M.transpose, vim.tbl_extend("force", opts, { desc = "Transpose (Alt+Shift+L)" }))
    vim.keymap.set("n", "<leader>tr", M.transpose, vim.tbl_extend("force", opts, { desc = "Transpose" }))

    -- 17. 列表切分 Split (Alt + Shift + J)
    vim.keymap.set("n", "<M-J>", M.split, vim.tbl_extend("force", opts, { desc = "Split Form (Alt+Shift+J)" }))
    vim.keymap.set("n", "<leader>sj", M.split, vim.tbl_extend("force", opts, { desc = "Split Form" }))

    -- 物理按键守卫 (Key Guards)
    vim.keymap.set("i", "<BS>", M.handle_backspace, expr_opts)
    vim.keymap.set("i", "<Del>", M.handle_delete, expr_opts)
    vim.keymap.set("i", ")", function() return M.handle_close_char(")") end, expr_opts)
    vim.keymap.set("i", "]", function() return M.handle_close_char("]") end, expr_opts)
    vim.keymap.set("i", "}", function() return M.handle_close_char("}") end, expr_opts)
    vim.keymap.set("i", "(", function() return M.handle_open_char("(", ")") end, expr_opts)
    vim.keymap.set("i", "[", function() return M.handle_open_char("[", "]") end, expr_opts)
    vim.keymap.set("i", "{", function() return M.handle_open_char("{", "}") end, expr_opts)
    vim.keymap.set("n", "x", M.handle_normal_x, expr_opts)

    -- 全局漫游与 Tab 轮转 (Window Roaming & Tab Cycling)
    vim.keymap.set({ "n", "t" }, "<M-S-Up>", M.focus_editor, vim.tbl_extend("force", opts, { desc = "Focus Editor (Alt+Shift+Up)" }))
    vim.keymap.set({ "n", "t" }, "<M-S-Down>", M.focus_terminal, vim.tbl_extend("force", opts, { desc = "Focus Terminal (Alt+Shift+Down)" }))
    vim.keymap.set({ "n", "t" }, "<M-S-Left>", function() M.cycle_tab(-1) end, vim.tbl_extend("force", opts, { desc = "Prev Tab Cycle (Alt+Shift+Left)" }))
    vim.keymap.set({ "n", "t" }, "<M-S-Right>", function() M.cycle_tab(1) end, vim.tbl_extend("force", opts, { desc = "Next Tab Cycle (Alt+Shift+Right)" }))
  end

  -- 全局注册（草稿/无名缓冲区即刻可用）
  bind_all(nil)

  -- Scheme 缓冲区高优先级绑定
  vim.api.nvim_create_autocmd("FileType", {
    pattern = { "scheme" },
    callback = function(ev)
      bind_all(ev.buf)
    end,
  })
end

return M
