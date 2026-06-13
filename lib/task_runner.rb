require_relative "agent"
require_relative "parallel"

# 通用编排核:不认识 HTML、正则、SQL —— 只认识一个 Domain(怎么生成 + 怎么验)。
#
# 把 townhall 里【任务无关】的那部分单独拎出来就是这个:
#   fan-out N 个 → 各自"生成 → 验 → 错了带反馈自改(爬山,错误更少才换)" → 挑错误最少的。
# 换任务时,这段一行都不动,只把 new 进来的 Domain 换掉。
#
# 和 HTML 那条 coordinator 的区别,值得对照:
#   - 这里验证器是【硬】的(正则跑测试用例),错误可数,所以直接挑"错误最少"就行,
#     不需要 Critic/Judge —— count 就是可信指标。
#   - HTML 那边产物质量是【软】的、不可数,才必须上 Critic 两两比较 + Judge。
#   验证器硬不硬,决定了你要不要那套软收敛机制。
class TaskRunner
  FANOUT      = 3
  MAX_REPAIRS = 3

  def initialize(domain)
    @domain = domain
  end

  def run(brief, log: ->(m) { puts m })
    log.call("领域:#{@domain.name} · fan-out #{FANOUT} 个,各自自检自改")
    candidates = Parallel.map(1..FANOUT) { |seed| build_one(brief, seed) }

    candidates.each_with_index do |c, i|
      status = c[:errors].empty? ? "通过" : "剩 #{c[:errors].size} 处"
      log.call("  ##{i}:#{status}(自改 #{c[:repairs]} 轮)→ #{c[:artifact]}")
    end

    best = candidates.min_by { |c| c[:errors].size }   # 硬指标可数,直接挑错误最少的
    log.call("挑错误最少的 → #{best[:errors].empty? ? '完美通过' : "还剩 #{best[:errors].size} 处"}")
    best
  end

  private

  def build_one(brief, seed)
    agent = Agent.new(model: WORKER_MODEL, system: @domain.system)
    artifact = clean(agent.call("需求:#{brief}\n(第 #{seed} 版,可以和别的版本不一样)"))
    errors = @domain.check(brief, artifact)
    repairs = 0

    MAX_REPAIRS.times do
      break if errors.empty?
      repairs += 1
      cand = clean(agent.call(<<~MSG))
        需求:#{brief}

        你上一版有这些问题,请修复后重新输出【完整结果】(只输出结果本身):
        #{errors.map { |e| "- #{e}" }.join("\n")}

        上一版:
        #{artifact}
      MSG
      cand_errors = @domain.check(brief, cand)
      artifact, errors = cand, cand_errors if cand_errors.size < errors.size  # 爬山:更少才换
    end

    { artifact: artifact, errors: errors, repairs: repairs }
  end

  # 通用兜底:模型有时会包代码块,剥掉。
  def clean(text)
    text.to_s.strip
        .sub(/\A```[a-z]*\s*\n?/i, "")
        .sub(/\n?```\s*\z/, "")
        .strip
  end
end
