require_relative "agent"

# 递归编排 +「停下来」问题。
#
# 一个任务,问模型:"够小能直接做?还是得拆?" 要拆,就对每个子任务【再问一遍】——
# 这就是递归(agent 派 agent)。Yegge 说 orchestrator 真正的难点就是这个:它停不下来。
#
# 为什么停不下来:"够小了吗"是模型的【主观】判断,而几乎任何任务都还能再拆。
# 所以光靠模型自己,几乎【永远不会主动收手】。让递归收敛的,是外面的硬约束:
#   - 深度上限 max_depth:到底了就强制变叶子,不准再拆
#   - 预算 Budget:调用次数花完就停,不管拆没拆完
# 这两道闸,才是真正让递归 orchestrator 停下来的东西 —— 不是模型的自觉。
module Recursive
  # 预算:把"调用次数"当成一等约束来数。townhall 之前任何地方都没数过这个。
  class Budget
    attr_reader :cap, :spent
    def initialize(cap)
      @cap = cap
      @spent = 0
    end

    def charge
      @spent += 1
    end

    def left
      @cap - @spent
    end
  end

  SPLIT_SYSTEM = <<~PROMPT
    你在做任务分解。我给你一个任务,你判断:
    - 如果它已经足够小、能一步直接完成,只回复一个词:ATOMIC
    - 否则把它拆成 2~4 个更小的子任务,每行一个,一句话,不要编号、不要解释。
  PROMPT

  module_function

  # 把 task 递归拆成一棵任务树。
  # 返回 { task:, children: [...], reason: } —— children 为空即叶子,reason 记它为啥停。
  def tree(task, budget, depth: 0, max_depth: 2, log: nil)
    pad = "  " * depth

    # —— 两道"停下来"的闸,在问模型之前先挡 ——
    if depth >= max_depth
      log&.call("#{pad}• [#{depth}] 到深度上限,强制收手 → #{task}")
      return { task: task, children: [], reason: :depth }
    end
    if budget.left <= 0
      log&.call("#{pad}• [#{depth}] 预算花完,强制收手 → #{task}")
      return { task: task, children: [], reason: :budget }
    end

    subs = ask_split(task, budget)   # 烧 1 次预算
    if subs.empty?
      log&.call("#{pad}• [#{depth}] 模型说够小,直接做 → #{task}")
      { task: task, children: [], reason: :atomic }
    else
      log&.call("#{pad}▸ [#{depth}] 拆成 #{subs.size} 块:#{task}")
      kids = subs.map { |s| tree(s, budget, depth: depth + 1, max_depth: max_depth, log: log) }
      { task: task, children: kids, reason: :split }
    end
  end

  # 问模型:够小→返回 [];要拆→返回子任务数组。每问一次烧 1 次预算。
  def ask_split(task, budget)
    budget.charge
    answer = Agent.new(model: WORKER_MODEL, system: SPLIT_SYSTEM).call("任务:#{task}")
    return [] if answer.to_s.strip =~ /\A(ATOMIC|够小|不用拆|atomic)/i
    answer.to_s.lines
          .map { |l| l.strip.sub(/\A[-*•\d.、)]+\s*/, "") }
          .reject(&:empty?)
          .reject { |l| l =~ /\Aatomic\z/i }
  end
end
