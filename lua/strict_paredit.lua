-- =============================================================================
-- Scheme Strict Paredit 核心算法引擎 (Strict Paredit Core Engine)
-- 严格基于 docs/strict_paredit_algorithm_spec.md 与 docs/strict_paredit_guide.md 规范实现
-- 包含：17 个单发结构化操作、纯严格物理按键守卫、全局窗口漫游与标签页轮转
-- 彻底废除 Vim 模态依赖：Normal / Insert / Visual / Terminal 全时直通单发生效
-- =============================================================================

local M = {}

-- -----------------------------------------------------------------------------
-- 一、 语法模型与容错 AST 数据结构 (Parser & AST)
-- -----------------------------------------------------------------------------

local function is_space(b)
  return b == 32 or b == 9 or b == 10 or b == 13
end

local function is_delimiter(b)
  return is_space(b) or b == 40 or b == 41 or b == 91 or b == 93 or b == 123 or b == 125 or b == 34 or b == 59
end

--- 容错 AST 解析器算法 (parseSexpressions)
function M.parseSexpressions(text)
  local stack = {}
  local roots = {}
  local i = 1
  local len = #text

  while i <= len do
    local b = text:byte(i)

    -- 1. 跳过空白字符
    if is_space(b) then
      i = i + 1

    -- 2. 单行注释：;.*$
    elseif b == 59 then -- ';'
      local s_start = i - 1
      while i <= len and text:byte(i) ~= 10 do
        i = i + 1
      end
      local node = { start = s_start, ["end"] = i - 1, type = "comment" }
      if #stack > 0 then
        table.insert(stack[#stack].children, node)
      else
        table.insert(roots, node)
      end

    -- 3. 字符字面量：#\space, #\a, #\( 等
    elseif b == 35 and i + 1 <= len and text:byte(i + 1) == 92 then -- '#\'
      local s_start = i - 1
      i = i + 2
      while i <= len and not is_delimiter(text:byte(i)) do
        i = i + 1
      end
      local node = { start = s_start, ["end"] = i - 1, type = "atom" }
      if #stack > 0 then
        table.insert(stack[#stack].children, node)
      else
        table.insert(roots, node)
      end

    -- 4. 字符串字面量："([^"\\]|\\.)*"
    elseif b == 34 then -- '"'
      local s_start = i - 1
      i = i + 1
      while i <= len do
        local sb = text:byte(i)
        if sb == 92 and i + 1 <= len then -- '\\'
          i = i + 2
        elseif sb == 34 then -- '"'
          i = i + 1
          break
        else
          i = i + 1
        end
      end
      local node = { start = s_start, ["end"] = i - 1, type = "string" }
      if #stack > 0 then
        table.insert(stack[#stack].children, node)
      else
        table.insert(roots, node)
      end

    -- 5. 开括号：(, [, {
    elseif b == 40 or b == 91 or b == 123 then
      local open_char = string.char(b)
      local close_char = b == 40 and ")" or (b == 91 and "]" or "}")
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

    -- 6. 闭括号：), ], }
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

    -- 7. 原子标识符/数字 (atom)
    else
      local s_start = i - 1
      while i <= len and not is_delimiter(text:byte(i)) do
        i = i + 1
      end
      local node = { start = s_start, ["end"] = i - 1, type = "atom" }
      if #stack > 0 then
        table.insert(stack[#stack].children, node)
      else
        table.insert(roots, node)
      end
    end
  end

  -- 8. 容错闭合：未配对的开括号自动隐式延展至文本末尾
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

--- 将 0-indexed 字符偏移量转换为 (1-indexed row, 0-indexed col)
function M.offset_to_pos(text, offset)
  local target = math.max(0, math.min(offset, #text))
  local row = 1
  local last_nl = 0
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

--- 检索覆盖 pos 的最小叶子节点 (pos >= node.start && pos <= node.end)
function M.findInnermostNodeAt(roots, pos)
  local result = nil
  local min_len = math.huge

  local function search(nodes)
    for _, node in ipairs(nodes) do
      if pos >= node.start and pos <= node["end"] then
        local l = node["end"] - node.start
        if l < min_len then
          min_len = l
          result = node
        end
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

--- 检索在 pos 处闭合的节点（支持光标紧贴在闭括号外侧）
function M.searchNodeEndingAt(roots, text, pos)
  local p = pos
  while p > 0 and (text:byte(p) == 32 or text:byte(p) == 9) do
    p = p - 1
  end
  local found = nil
  local function search(nodes)
    for _, node in ipairs(nodes) do
      if node["end"] == p then
        found = node
      end
      if node.children and #node.children > 0 then
        search(node.children)
      end
    end
  end
  search(roots)
  return found
end

-- -----------------------------------------------------------------------------
-- 二、 17 个 Strict Paredit 快捷键算法规范实现
-- -----------------------------------------------------------------------------

-- 全局选区历史栈（供 Alt+K 扩选 与 Alt+Shift+K 收缩）
local selection_history_stack = {}

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

--- 执行局部单事务替换并定位光标
local function apply_text_replacement(text, rangeStart, rangeEnd, replacementText, newOffset)
  local r1, c1 = M.offset_to_pos(text, rangeStart)
  local r2, c2 = M.offset_to_pos(text, rangeEnd)
  local lines = vim.split(replacementText, "\n", { plain = true })
  vim.api.nvim_buf_set_text(0, r1 - 1, c1, r2 - 1, c2, lines)

  if newOffset then
    local new_text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
    local nr, nc = M.offset_to_pos(new_text, newOffset)
    pcall(vim.api.nvim_win_set_cursor, 0, { nr, nc })
  end
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
    vim.cmd([[execute "normal! \<ESC>"]])
    local r, c = M.offset_to_pos(text, from_off)
    vim.api.nvim_win_set_cursor(0, { r, c })
  end
end

--- 2. 发射求值 Eval REPL (Alt + Enter / Ctrl + Enter / Alt + E)
function M.eval_repl()
  local in_insert = vim.fn.mode():sub(1, 1) == "i"
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
    local target = M.searchNodeEndingAt(roots, text, pos)
      or M.findEnclosingWithParent(roots, pos)
      or M.findInnermostNodeAt(roots, pos)
      or M.findTopLevelNode(roots, pos)

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

  -- 多顶层表达式自动包裹 (begin ...) 确保原子执行
  local sub_roots = M.parseSexpressions(code)
  local code_count = 0
  for _, r in ipairs(sub_roots) do
    if r.type ~= "comment" then
      code_count = code_count + 1
    end
  end
  if code_count > 1 then
    code = "(begin\n" .. code .. "\n)"
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

--- 5. 向右吞噬 Slurp Forward (Alt + L) - 原子非破坏性局部范围替换
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

  -- 替换区间：从原闭括号 [enc.end - 1, next_sib.end)
  local range_start = enc["end"] - 1
  local range_end = next_sib["end"]
  local between = text:sub(enc["end"] + 1, next_sib.start)
  local next_text = text:sub(next_sib.start + 1, next_sib["end"])
  local needs_space = (between == "")
  local repl = (needs_space and " " or "") .. between .. next_text .. enc.closeChar

  -- 光标跟随置于新吞入的兄弟之后
  local new_pos = range_start + #repl - 1
  apply_text_replacement(text, range_start, range_end, repl, new_pos)
end

--- 6. 向左吐出 Barf Forward (Alt + J) - 原子非破坏性局部范围替换
function M.barf_forward()
  local text, pos = M.get_buffer_context()
  local roots = M.parseSexpressions(text)
  local enc, _ = M.findEnclosingWithParent(roots, pos)
  if not enc or not enc.children or #enc.children == 0 then return end

  local children = {}
  for _, c in ipairs(enc.children) do
    if c.type ~= "comment" then
      table.insert(children, c)
    end
  end
  if #children <= 1 then return end

  local last_child = children[#children]
  local prev_child = children[#children - 1]

  -- 替换区间：从前一个子节点尾部 [prev_child.end, enc.end)
  local range_start = prev_child["end"]
  local range_end = enc["end"]
  local between = text:sub(prev_child["end"] + 1, last_child.start)
  local last_text = text:sub(last_child.start + 1, last_child["end"])
  local repl = enc.closeChar .. between .. last_text

  -- 光标留在闭合列表内侧
  local new_pos = math.min(pos, range_start)
  apply_text_replacement(text, range_start, range_end, repl, new_pos)
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
  local node_at = M.findInnermostNodeAt(roots, pos)
  local enc, _ = M.findEnclosingWithParent(roots, pos)

  local target = nil
  if node_at and node_at.type == "list" and (pos == node_at.start or pos == node_at["end"] - 1) then
    target = node_at
  else
    target = enc
  end
  if not target or target.type ~= "list" then return end

  local inner_text = text:sub(target.start + 2, target["end"] - 1)
  apply_text_replacement(text, target.start, target["end"], inner_text, target.start)
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
    if s["end"] > pos then
      target = s
      break
    end
  end

  if target then
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
  local from_off, to_off = get_visual_selection(text)
  local r1, r2

  if from_off and to_off and to_off > from_off then
    r1, _ = M.offset_to_pos(text, from_off)
    r2, _ = M.offset_to_pos(text, to_off)
    vim.cmd([[execute "normal! \<ESC>"]])
  else
    local roots = M.parseSexpressions(text)
    local top = M.findTopLevelNode(roots, pos)
    local enc = M.findEnclosingWithParent(roots, pos)
    local target = top or enc
    if target then
      r1, _ = M.offset_to_pos(text, target.start)
      r2, _ = M.offset_to_pos(text, target["end"])
    else
      local cur_row = vim.api.nvim_win_get_cursor(0)[1]
      r1, r2 = cur_row, cur_row
    end
  end

  local cur = vim.api.nvim_win_get_cursor(0)
  vim.cmd(string.format("silent! %d,%dequal", r1, r2))
  pcall(vim.api.nvim_win_set_cursor, 0, cur)
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

--- 校验选区是否会破坏括号树平衡 (Unbalanced Selection Guard)
function M.is_selection_balanced(text, from_off, to_off)
  local roots = M.parseSexpressions(text)
  local unbalanced = false

  local function check(nodes)
    for _, node in ipairs(nodes) do
      if node.type == "list" then
        if (node.start >= from_off and node.start < to_off and node["end"] > to_off) or
           (node.start < from_off and node["end"] > from_off and node["end"] <= to_off) then
          unbalanced = true
          return
        end
        if node.children and #node.children > 0 then
          check(node.children)
          if unbalanced then return end
        end
      end
    end
  end

  check(roots)
  return not unbalanced
end

--- 可视模式删除拦截守卫
function M.handle_visual_delete(key)
  local text, _ = M.get_buffer_context()
  local from_off, to_off = get_visual_selection(text)
  if from_off and to_off and to_off > from_off then
    if not M.is_selection_balanced(text, from_off, to_off) then
      vim.notify("Strict Paredit: Selection cuts across unbalanced parens! Deletion blocked to protect AST.", vim.log.levels.WARN)
      return ""
    end
  end
  return key
end

--- 退格键拦截状态机 (Backspace Guard)
function M.handle_backspace()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local ch_before = col > 0 and line:sub(col, col) or ""
  local ch_at = line:sub(col + 1, col + 1)

  -- 1. 空括号对/引号对协同删除：(|) -> 清空
  if (ch_before == "(" and ch_at == ")") or (ch_before == "[" and ch_at == "]") or (ch_before == "{" and ch_at == "}") or (ch_before == '"' and ch_at == '"') then
    return "<BS><Del>"
  end

  -- 2. 非空列表开括号右侧：(|foo) -> 硬拦截
  if ch_before == "(" or ch_before == "[" or ch_before == "{" then
    vim.notify("Strict Paredit: Cannot delete open delimiter of non-empty form", vim.log.levels.WARN)
    return ""
  end

  -- 3. 闭括号右侧：(foo)| -> 步进跳入内侧 (foo|)
  if ch_before == ")" or ch_before == "]" or ch_before == "}" or ch_before == '"' then
    return "<Left>"
  end

  -- 默认放行
  return "<BS>"
end

--- 删除键拦截状态机 (Delete Guard)
function M.handle_delete()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local ch_at = line:sub(col + 1, col + 1)
  local ch_next = line:sub(col + 2, col + 2)
  local ch_before = col > 0 and line:sub(col, col) or ""

  -- 1. 空括号对协同删除：|() -> 清空
  if (ch_at == "(" and ch_next == ")") or (ch_at == "[" and ch_next == "]") or (ch_at == "{" and ch_next == "}") or (ch_at == '"' and ch_next == '"') then
    return "<Del><Del>"
  end

  -- 2. 非空闭括号左侧：(foo|) -> 硬拦截
  if ch_at == ")" or ch_at == "]" or ch_at == "}" then
    if not ((ch_before == "(" and ch_at == ")") or (ch_before == "[" and ch_at == "]") or (ch_before == "{" and ch_at == "}")) then
      vim.notify("Strict Paredit: Cannot delete close delimiter of non-empty form", vim.log.levels.WARN)
      return ""
    end
  end

  return "<Del>"
end

--- 闭括号穿透跳跃 (Close Delimiter Step-over)
function M.handle_close_char(char)
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local ch_at = line:sub(col + 1, col + 1)

  if ch_at == char then
    return "<Right>"
  end
  return char
end

--- 开括号自动配对并居中光标
function M.handle_open_char(open_char, close_char)
  return open_char .. close_char .. "<Left>"
end

--- 双引号智能配对与穿透
function M.handle_quote()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local ch_before = col > 0 and line:sub(col, col) or ""
  local ch_at = line:sub(col + 1, col + 1)
  local ch_prev2 = col > 1 and line:sub(col - 1, col - 1) or ""

  -- 字符字面量 #\" 放行
  if ch_before == "\\" and ch_prev2 == "#" then
    return '"'
  end

  -- 紧贴闭合双引号：穿透跳过
  if ch_at == '"' then
    return "<Right>"
  end

  -- 自动配对
  return '""<Left>'
end

--- 普通模式 x 键守卫（删除空对，阻止破坏平衡）
function M.handle_normal_x()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local ch = line:sub(col + 1, col + 1)
  local ch_next = line:sub(col + 2, col + 2)

  if (ch == "(" and ch_next == ")") or (ch == "[" and ch_next == "]") or (ch == "{" and ch_next == "}") or (ch == '"' and ch_next == '"') then
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

--- 聚焦编辑器 (Alt + Shift + Up / Alt + Up)
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

--- 聚焦终端 (Alt + Shift + Down / Alt + Down)
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
-- 彻底废除 Vim 模态：全套按键在 Normal (n)、Visual (v)、Insert (i) 统一单发生效
-- -----------------------------------------------------------------------------

function M.setup()
  local function bind_all(bufnr)
    local opts = bufnr and { buffer = bufnr, silent = true } or { silent = true }
    local expr_opts = bufnr and { buffer = bufnr, silent = true, expr = true } or { silent = true, expr = true }
    local alt_modes = { "n", "v", "i" }
    local leader_modes = { "n", "v" }
    local all_modes = { "n", "v", "i", "t" }

    local function map_alt(keys, fn, desc)
      for _, k in ipairs(keys) do
        for _, m in ipairs(alt_modes) do
          vim.keymap.set(m, k, fn, vim.tbl_extend("force", opts, { desc = desc }))
        end
      end
    end

    local function map_leader(keys, fn, desc)
      for _, k in ipairs(keys) do
        for _, m in ipairs(leader_modes) do
          vim.keymap.set(m, k, fn, vim.tbl_extend("force", opts, { desc = desc }))
        end
      end
    end

    local function map_global(keys, fn, desc)
      for _, k in ipairs(keys) do
        for _, m in ipairs(all_modes) do
          if m == "t" then
            vim.keymap.set("t", k, function()
              vim.cmd([[call feedkeys("\<C-\>\<C-n>", "n")]])
              vim.schedule(fn)
            end, vim.tbl_extend("force", opts, { desc = desc }))
          else
            vim.keymap.set(m, k, fn, vim.tbl_extend("force", opts, { desc = desc }))
          end
        end
      end
    end

    -- 1. 向外扩选 Expand (Alt + K)
    map_alt({ "<M-k>", "\x1bk" }, M.expand, "Expand Selection (Alt+K)")

    -- 7. 向内收缩 Contract (Alt + Shift + K / Alt + I)
    map_alt({ "<M-K>", "<M-i>", "\x1bK", "\x1bi" }, M.contract, "Contract Selection (Alt+Shift+K)")

    -- 2. 发射求值 Eval REPL (Alt + Enter / Ctrl + Enter / Alt + E)
    map_alt({ "<M-CR>", "<C-CR>", "<M-e>", "\x1be", "\x1b\r" }, M.eval_repl, "Eval in Steel REPL (Alt+Enter / Alt+E)")
    map_leader({ "<leader><CR>", "<leader>se" }, M.eval_repl, "Eval in Steel REPL")

    -- 3. 圆括号包裹 Wrap Parens (Alt + H) - Calva Smart Affinity
    map_alt({ "<M-h>", "\x1bh" }, M.wrap_parens, "Smart Wrap ( ) (Alt+H)")
    map_leader({ "<leader>w(", "<leader>wh" }, M.wrap_parens, "Smart Wrap ( )")

    -- 4. 方括号包裹 Wrap Square (Alt + Shift + H) - Calva Smart Affinity
    map_alt({ "<M-H>", "\x1bH" }, M.wrap_square, "Smart Wrap [ ] (Alt+Shift+H)")
    map_leader({ "<leader>w[", "<leader>wH" }, M.wrap_square, "Smart Wrap [ ]")

    -- 5. 向右吞噬 Slurp Forward (Alt + L)
    map_alt({ "<M-l>", "\x1bl" }, M.slurp_forward, "Slurp Forward (Alt+L)")
    map_leader({ ">)", "<leader>sl" }, M.slurp_forward, "Slurp Forward")

    -- 6. 向左吐出 Barf Forward (Alt + J)
    map_alt({ "<M-j>", "\x1bj" }, M.barf_forward, "Barf Forward (Alt+J)")
    map_leader({ "<)", "<leader>ba" }, M.barf_forward, "Barf Forward")

    -- 8. 选中顶级函数 Select Defun (Alt + 3)
    map_alt({ "<M-3>", "\x1b3", "<M-k3>" }, M.select_defun, "Select Defun (Alt+3)")
    map_leader({ "<leader>3" }, M.select_defun, "Select Defun")

    -- 9. 脱壳解包 Splice (Alt + O)
    map_alt({ "<M-o>", "\x1bo" }, M.splice, "Splice / Unwrap (Alt+O)")
    map_leader({ "<leader>sp" }, M.splice, "Splice / Unwrap")

    -- 10. 大步前进 Forward Sexp (Alt + 2)
    map_alt({ "<M-2>", "\x1b2", "<M-k2>" }, M.forward_sexp, "Forward Sexp (Alt+2)")
    map_leader({ "]e", "<leader>2" }, M.forward_sexp, "Forward Sexp")

    -- 11. 大步后退 Backward Sexp (Alt + 1)
    map_alt({ "<M-1>", "\x1b1", "<M-k1>" }, M.backward_sexp, "Backward Sexp (Alt+1)")
    map_leader({ "[e", "<leader>1" }, M.backward_sexp, "Backward Sexp")

    -- 12. 步进深入 Step Into (Alt + W)
    map_alt({ "<M-w>", "\x1bw" }, M.step_into, "Step Into (Alt+W)")
    map_leader({ "]f" }, M.step_into, "Step Into")

    -- 13. 步退跳出 Step Out (Alt + S)
    map_alt({ "<M-s>", "\x1bs" }, M.step_out, "Step Out (Alt+S)")
    map_leader({ "[f" }, M.step_out, "Step Out")

    -- 14. 向后整块删除 Kill Sexp (Alt + X)
    map_alt({ "<M-x>", "\x1bx" }, M.kill_sexp, "Kill Sexp (Alt+X)")
    map_leader({ "<leader>k" }, M.kill_sexp, "Kill Sexp")

    -- 15. 智能格式排版 Indent (Alt + \)
    map_alt({ "<M-\\>", "\x1b\\" }, M.indent, "Indent Form / Selection (Alt+\\)")
    map_leader({ "<leader>=" }, M.indent, "Indent Form / Selection")

    -- 16. 相邻参数对调 Transpose (Alt + Shift + L)
    map_alt({ "<M-L>", "\x1bL" }, M.transpose, "Transpose (Alt+Shift+L)")
    map_leader({ "<leader>tr" }, M.transpose, "Transpose")

    -- 17. 列表切分 Split (Alt + Shift + J)
    map_alt({ "<M-J>", "\x1bJ" }, M.split, "Split Form (Alt+Shift+J)")
    map_leader({ "<leader>sj" }, M.split, "Split Form")

    -- 物理按键守卫 (Key Guards)
    vim.keymap.set("i", "<BS>", M.handle_backspace, expr_opts)
    vim.keymap.set("i", "<Del>", M.handle_delete, expr_opts)
    vim.keymap.set("i", ")", function() return M.handle_close_char(")") end, expr_opts)
    vim.keymap.set("i", "]", function() return M.handle_close_char("]") end, expr_opts)
    vim.keymap.set("i", "}", function() return M.handle_close_char("}") end, expr_opts)
    vim.keymap.set("i", "(", function() return M.handle_open_char("(", ")") end, expr_opts)
    vim.keymap.set("i", "[", function() return M.handle_open_char("[", "]") end, expr_opts)
    vim.keymap.set("i", "{", function() return M.handle_open_char("{", "}") end, expr_opts)
    vim.keymap.set("i", '"', M.handle_quote, expr_opts)
    vim.keymap.set("n", "x", M.handle_normal_x, expr_opts)

    -- 可视选区删除平衡守卫 (Unbalanced Selection Guard)
    vim.keymap.set("v", "<BS>", function() return M.handle_visual_delete("<BS>") end, expr_opts)
    vim.keymap.set("v", "<Del>", function() return M.handle_visual_delete("<Del>") end, expr_opts)
    vim.keymap.set("v", "x", function() return M.handle_visual_delete("x") end, expr_opts)
    vim.keymap.set("v", "d", function() return M.handle_visual_delete("d") end, expr_opts)
    vim.keymap.set("v", "c", function() return M.handle_visual_delete("c") end, expr_opts)

    -- 全局漫游与 Tab 轮转 (Window Roaming & Tab Cycling)
    map_global({ "<M-S-Up>", "<M-Up>" }, M.focus_editor, "Focus Editor (Alt+Shift+Up / Alt+Up)")
    map_global({ "<M-S-Down>", "<M-Down>" }, M.focus_terminal, "Focus Terminal (Alt+Shift+Down / Alt+Down)")
    map_global({ "<M-S-Left>", "<M-Left>" }, function() M.cycle_tab(-1) end, "Prev Tab Cycle (Alt+Shift+Left / Alt+Left)")
    map_global({ "<M-S-Right>", "<M-Right>" }, function() M.cycle_tab(1) end, "Next Tab Cycle (Alt+Shift+Right / Alt+Right)")
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
