# Neovim + Steel Scheme 快捷键终极速查手册 (Cheat Sheet)

本手册汇总了 `steel-ide` 中预置的全部快捷键，涵盖 **严格 Paredit 结构化几何编辑**、**Steel REPL 交互流**、**底部 Shell 终端** 及 **多文件与窗口导航**。

> **设计哲学**：
> 1. **彻底废除 Leader 两阶段**：核心高频操作纯单发（One-Shot），按一下立刻生效！
> 2. **左手大拇指锚定 Alt（Mac: Option / ⌥）**：零浏览器与系统冲突，右手依托 `H-J-K-L` 四轴主矩阵。
> 3. **严格结构守护（Strict Delimiter Balance）**：代码即数据，永远无法产生失衡的孤儿括号。

---

## 目录
1. [严格 Paredit 结构化编辑 (17 个核心单发键)](#1-严格-paredit-结构化编辑-17-个核心单发键)
2. [严格模式括号守护键 (Strict Balance Rules)](#2-严格模式括号守护键-strict-balance-rules)
3. [Steel REPL 交互与求值 (右侧分屏)](#3-steel-repl-交互与求值-右侧分屏)
4. [系统 Shell 终端管理 (底部底栏)](#4-系统-shell-终端管理-底部底栏)
5. [多文件与多窗口导航](#5-多文件与多窗口导航)

---

## 1. 严格 Paredit 结构化编辑 (17 个核心单发键)

遵循 [`docs/strict_paredit_guide.md`](docs/strict_paredit_guide.md) 设计，在 `.scm`、`.ss`、`.steel` 文件中具备最高优先级。

| 频级 / 占比 | Linux / Win | macOS (⌥) | 模式 | 命令动作 | 心智助记符 | 核心功能与变换效果 |
|:---:|:---:|:---:|:---:|:---|:---|:---|
| ⭐⭐⭐⭐⭐<br>(45%) | **`Alt + K`** | **`⌥ K`** | N / V | **向外扩选 (Expand)** | 右手纵向扩张 | 自动严丝合缝选中当前 `(...)`，连按逐层外扩括号 |
| ⭐⭐⭐⭐⭐<br>(45%) | **`Alt + Enter`<br>`Ctrl + Enter`** | **`⌥ ↵`<br>`⌘ ↵`** | N / V | **发射求值 (Eval REPL)** | 拇指锚定，一拍回车 | 将当前 S 表达式或选区代码送入右侧 Steel REPL |
| ⭐⭐⭐⭐<br>(25%) | **`Alt + H`** | **`⌥ H`** | N / V | **圆括号包裹 (Wrap Parens)** | Hold/Hug 左侧包裹 | `cards` $\rightarrow$ `(cards)`（支持普通模式与可视选区） |
| ⭐⭐⭐⭐<br>(25%) | **`Alt + Shift + H`** | **`⌥ ⇧ H`** | N / V | **方括号包裹 (Wrap Square)** | Hold square 方括号 | `x 10` $\rightarrow$ `[x 10]`（写 `let*` 局部变量与 `cond` 必备） |
| ⭐⭐⭐⭐<br>(20%) | **`Alt + L`** | **`⌥ L`** | N | **向右吞噬 (Slurp)** | 右手 L（偏右吸入扩张） | `(a b) c` $\rightarrow$ `(a b c)`（右括号向右跨越吞入一元素） |
| ⭐⭐⭐⭐<br>(20%) | **`Alt + J`** | **`⌥ J`** | N | **向左吐出 (Barf)** | 右手 J（偏左吐出收缩） | `(a b c)` $\rightarrow$ `(a b) c`（右括号向左收缩吐出末项） |
| ⭐⭐⭐<br>(15%) | **`Alt + Shift + K`** | **`⌥ ⇧ K`** | V | **向内收缩 (Contract)** | 右手纵向收缩 | 与 `Alt+K` 镜像呼应，扩选过头随时往回收缩一级 |
| ⭐⭐⭐<br>(10%) | **`Alt + 3`** | **`⌥ 3`** | N / V | **选中顶级函数 (Defun)** | 数字区 3（定点直达） | 无论光标藏在函数内部多深，一键直达最外层 `(define ...)` |
| ⭐⭐⭐<br>(10%) | **`Alt + O`** | **`⌥ O`** | N | **脱壳解包 (Splice)** | Open 剥离外壳 | `(let () (expr))` $\rightarrow$ `(expr)`，打碎外层提取内部代码 |
| ⭐⭐⭐<br>(10%) | **`Alt + 2`** | **`⌥ 2`** | N | **大步前进 (Forward)** | 数字区 2（向右前进） | 光标直接跨过右侧整组完整 S 表达式或参数 |
| ⭐⭐⭐<br>(10%) | **`Alt + 1`** | **`⌥ 1`** | N | **大步后退 (Backward)** | 数字区 1（向左后退） | 光标直接跨过左侧整组完整 S 表达式或参数 |
| ⭐⭐<br>(5%) | **`Alt + W`** | **`⌥ W`** | N | **步进深入 (Step Into)** | W 前进深入钻入 | 光标直接步进跳入当前括号内部最左侧第一个参数前 |
| ⭐⭐<br>(5%) | **`Alt + S`** | **`⌥ S`** | N | **步退跳出 (Step Out)** | S 后退撤出外层 | 光标跳回当前外层括号左侧前置起始位 |
| ⭐⭐<br>(5%) | **`Alt + X`** | **`⌥ X`** | N | **整块删除 (Kill Sexp)** | eXterminate 删块 | 删掉光标右侧的一整组完整子表达式，绝不破坏括号平衡 |
| ⭐⭐<br>(5%) | **`Alt + \`** | **`⌥ \`** | N / V | **智能格式排版 (Indent)** | 排版与对齐 | 一键重新按 Lisp 缩进规范对齐当前 S 表达式代码块 |
| ⭐<br>(2%) | **`Alt + Shift + L`** | **`⌥ ⇧ L`** | N | **相邻参数对调 (Transpose)** | Leap swap 横向对调 | `(equal? a b)` $\rightarrow$ `(equal? b a)`，两项位置瞬间互换 |
| ⭐<br>(2%) | **`Alt + Shift + J`** | **`⌥ ⇧ J`** | N | **列表切分 (Split)** | Joint cut 光标处切分 | `(a b \| c d)` $\rightarrow$ `(a b) (c d)`，从光标处平分列表 |

*注：模式列中 `N` = Normal 普通模式，`V` = Visual 可视选择模式。*

---

## 2. 严格模式括号守护键 (Strict Balance Rules)

由 `strict-paredit.nvim` 实时守门，防止编写 Lisp 代码时产生语法失衡：

| 按键 | 触发模式 | 行为描述 |
|:---|:---:|:---|
| **`(` / `[` / `{`** | Insert (插入) | 自动插入成对括号 `()`，光标停留在括号中间 |
| **`)` / `]` / `}`** | Insert (插入) | **智能跳过（Move-over）**：若光标正位于对应闭括号前，直接右移跨过，绝不产生多余孤儿括号 |
| **`<BS>`** (退格) | Insert (插入) | 若位于空括号对中间 `( | )`，**同时删除双侧括号**；若会导致括号失衡，拦截并警告 |
| **`<Del>`** (删除) | Insert (插入) | 若位于开括号前，**成对删除匹配的双侧括号** |
| **`x`** | Normal (普通) | 若光标停在括号上，**强制成对删除匹配的双侧括号**；阻止单边破坏平衡 |

---

## 3. Steel REPL 交互与求值 (右侧分屏)

| 快捷键 | 所在模式 | 功能说明 | 助记说明 |
|:---|:---:|:---|:---|
| **`Alt + R`** (或 `⌥ R`) | Normal / Terminal | **一键秒开 / 秒关 Steel REPL** | **R**EPL 开关，终端内按自动收起返回代码 |
| **`Alt + Enter`**<br>`Ctrl + Enter` | Normal / Visual | **发送当前表达式或选区求值** | 未打开时**自动在右侧拉起 REPL 并平滑滚屏** |
| **`Space + s + o`** | Normal | 展开 / 隐藏右侧 REPL 窗口 | **s**teel **o**pen |
| **`Space + s + c`** | Normal | 单向关闭 (隐藏) 右侧 REPL 窗口 | **s**teel **c**lose |
| **`Space + s + q`** | Normal | 彻底杀死并重启 Steel REPL 进程 | **s**teel **q**uit |
| **`Space + s + b`** | Normal | 将当前文件的全部代码全量送入 REPL 执行 | **s**end **b**uffer |
| **`:SteelRepl`** | Command | 命令行指令：切换开关 REPL | — |

---

## 4. 系统 Shell 终端管理 (底部底栏)

独立的系统 Shell（Bash/Zsh/PowerShell），会话在后台保持，命令历史不丢失：

| 快捷键 | 所在模式 | 功能说明 | 助记说明 |
|:---|:---:|:---|:---|
| **`Alt + T`** (或 `⌥ T`) | Normal / Terminal | **一键秒开 / 秒关底部系统 Shell** | **T**erminal 开关，终端内按自动收起返回代码 |
| **`Ctrl + \``** (反引号) | Normal / Terminal | **秒开 / 秒关底部系统 Shell** | VS Code 经典肌肉记忆终端键 |
| **`Space + t + t`** | Normal | 展开 / 隐藏底部 Shell 窗口 | **t**erminal **t**oggle |
| **`<Esc><Esc>`** | Terminal | **退出输入模式，进入终端查看模式** | 方便向上翻页、查看日志或复制输出 |
| **`:Terminal`** | Command | 命令行指令：切换开关底部终端 | — |

---

## 5. 多文件与多窗口导航

所有打开的文件**全局共享右侧同一个 Steel REPL 实例**，跨文件函数与变量无缝打通。

### 5.1 文件切换与管理
| 快捷键 / 命令 | 所在模式 | 功能说明 |
|:---|:---:|:---|
| **`Space + b + n`** | Normal | 切换到**下一个**已打开的文件 (Buffer Next) |
| **`Space + b + p`** | Normal | 切换到**上一个**已打开的文件 (Buffer Previous) |
| **`Space + b + d`** | Normal | 关闭当前文件 Buffer (Buffer Delete，不退出编辑器) |
| **`:e <路径>`** | Command | 打开或新建文件 |
| **`:vsp <路径>`** | Command | 左右垂直分屏打开文件 |
| **`:sp <路径>`** | Command | 上下水平分屏打开文件 |
| **`:Ex`** 或 **`:Explore`** | Command | 打开内置目录树浏览器浏览文件 |

### 5.2 窗口焦点跳转
| 快捷键 | 功能说明 |
|:---|:---|
| **`Ctrl + h`** | 将光标焦点移至 **左侧** 窗口 |
| **`Ctrl + l`** | 将光标焦点移至 **右侧** 窗口 (进入 REPL) |
| **`Ctrl + j`** | 将光标焦点移至 **下方** 窗口 (进入 Shell) |
| **`Ctrl + k`** | 将光标焦点移至 **上方** 窗口 |
| **`<Esc>`** | 在普通模式下一键清除搜索高亮标记 |
