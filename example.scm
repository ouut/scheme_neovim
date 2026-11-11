;;; =============================================================================
;;; Neovim + Steel Scheme (Rust Steel) 实战测试脚本
;;; 支持严格 Paredit 结构化编辑与交互式 REPL 工作流
;;; =============================================================================

;; -----------------------------------------------------------------------------
;; 1. 发射求值 (Alt + Enter 或 Ctrl + Enter)
;; 提示：光标放在任意括号内按 Alt+Enter，立即自动拉起 Steel REPL 并求值！
;; -----------------------------------------------------------------------------
(+ 10 20 30)

(define (factorial n)
  (if (<= n 1)
      1
      (* n (factorial (- n 1)))))

(factorial 10)

;; -----------------------------------------------------------------------------
;; 2. 结构化编辑试验田 (严格按照 docs/strict_paredit_guide.md 快捷键测试)
;; -----------------------------------------------------------------------------

;; [测试 Alt + H: 圆括号包裹]
;; 将光标移至 cards 上，按下 Alt+H -> 自动变成 (cards)
(define my-deck cards)

;; [测试 Alt + Shift + H: 方括号包裹]
;; 选中 x 10，按下 Alt+Shift+H -> 自动变成 [x 10]
(define (test-bindings)
  (let* (x 10
         y 20)
    (+ x y)))

;; [测试 Alt + L (吞噬 Slurp) 与 Alt + J (吐出 Barf)]
;; 光标在 (1 2) 内：
;;   按 Alt + L: 右括号吞入 3  -> 变成 (1 2 3) 4
;;   按 Alt + J: 右括号吐出 3  -> 还原为 (1 2) 3 4
(define numbers
  '( (1 2) 3 4 ))

;; [测试 Alt + Shift + L: 相邻参数对调 Transpose]
;; 光标在 a 上，按下 Alt + Shift + L -> 变成 (equal? b a)
(define (check-eq a b)
  (equal? a b))

;; [测试 Alt + Shift + J: 列表光标处切分 Split]
;; 光标置于 b 与 c 之间，按下 Alt + Shift + J -> 变成 (a b) (c d)
'(a b c d)

;; [测试 Alt + O: 脱壳解包 Splice]
;; 光标在 (inner-function x) 内，按 Alt + O -> 剥离外壳直接提取 inner-function x
(define (wrapper x)
  (outer-function (inner-function x)))

;; [测试 Alt + 3: 选中顶级函数 Defun]
;; 无论光标藏在此函数内部多深，按下 Alt+3 瞬间整块选中当前顶级 define！
(define (deeply-nested-algorithm lst)
  (let ((filtered (filter (lambda (x) (> x 0)) lst)))
    (map (lambda (x) (* x 2))
         filtered)))

;; [测试 Alt + K (扩选 Expand) 与 Alt + Shift + K (收缩 Contract)]
;; 在 filtered 内按 Alt + K 逐层扩张选择范围，按 Alt + Shift + K 逐层收缩！
