require_relative "agent"
require_relative "parallel"

# 记忆的【写入闸】。
#
# 为什么需要它:记忆是个真相源 —— 一条经验一旦写进去,会被 recall 自动塞进【以后所有
# 相关任务】。所以如果让 agent 随手写,一条【错的】经验就成了带公章的 heresy,污染一大片。
# 真相源的铁律:人人可读,写入必须过闸(见 README 那条设计原则)。
#
# 闸门做法:提议的经验先不算数,交给一个【独立评审小组】投票 —— 真吗?通用吗(不是只对
# 某个具体案例过拟合)?可操作吗?多数通过才放行。
#
# 诚实说:这是个【过滤器】,不是真理保证 —— 验证天生不完美(你一路都见过)。它把明显
# 错的 / 过拟合的 / 没用的挡在门外,把 heresy 混进真相源的概率压低,但压不到零。
module Gatekeeper
  PANEL = 3   # 几个独立评审(多数通过即放行)

  SYSTEM = <<~PROMPT
    你在审一条准备写进项目"经验库"的笔记。它一旦通过,会被自动塞进【以后所有相关任务】,
    所以标准要严。三条【全部】满足才算通过:
    - 真:说法正确,不是想当然;
    - 通用:适用于这一【类】任务,而不是只对某一个具体例子成立;
    - 可操作:照着做能避开真问题,不是空话套话。
    第一行只回 PASS 或 REJECT,第二行用一句话说理由。
  PROMPT

  module_function

  def vet(scope, lesson, log: nil)
    votes = Parallel.map(1..PANEL) do |_i|
      ans = Agent.new(model: JUDGE_MODEL, system: SYSTEM).call(<<~MSG)
        适用场景关键词:#{Array(scope).join(', ')}
        经验:#{lesson}
      MSG
      lines  = ans.to_s.strip.lines.map(&:strip).reject(&:empty?)
      pass   = (lines.first.to_s =~ /\APASS/i) ? true : false
      reason = lines[1] || lines.first.to_s.sub(/\A(PASS|REJECT)\s*/i, "")
      { pass: pass, reason: reason }
    end

    votes.each_with_index { |v, i| log&.call("  评审#{i + 1}:#{v[:pass] ? 'PASS' : 'REJECT'} — #{v[:reason]}") }
    passed = votes.count { |v| v[:pass] }
    { trusted: passed > PANEL / 2, pass: passed, total: PANEL }
  end
end
