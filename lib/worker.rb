require_relative "agent"
require_relative "validator"
require_relative "sandbox"
require_relative "critic"

# 工人:把"一句话需求 + 一个风格角度" → 一版自包含的 HTML。
# 多个工人用不同角度并行跑,就是文章里的 "slot machine / 做 N 版挑赢家"。
#
# 这一版的新东西:自检自改 loop。
#   生成一版 → 自检 → 没过就带着错误反馈再生成 → …… 最多 N 轮。
# 这就是 Yegge 说的 "agent 放进 loop" —— orchestrator 的核心原语。
# 而且 worker 跑在 Parallel 的线程里,所以 N 个修复循环是同时转的。
class Worker
  MAX_REPAIRS = 2  # 第一版之外,最多再自改几轮(防止改不动时死循环)

  SYSTEM = <<~PROMPT
    你是一个前端工程师。根据用户需求,生成一个【单文件、自包含】的 HTML 应用。
    要求:
    - 所有 CSS 写在 <style> 里,所有 JS 写在 <script> 里,不依赖任何外部文件。
    - 只输出 HTML 源码本身,不要 markdown 代码块,不要任何解释文字。
    - 第一行必须是 <!DOCTYPE html>。
  PROMPT

  def initialize(brief, angle, lessons: [])
    @brief = brief
    @angle = angle
    @lessons = lessons   # 从 Memory 检索来的、和这个需求相关的过往经验
    @agent = Agent.new(model: WORKER_MODEL, system: SYSTEM)
  end

  def build
    best = generate
    problems = check(best)   # 崩溃级(硬) + 功能级(Critic 软)
    repairs = 0

    MAX_REPAIRS.times do
      break if problems.empty?                       # 没毛病,收工
      repairs += 1
      candidate = regenerate(best, problems)

      # 采纳门槛两道:
      #  1) 候选不能是崩的 —— 崩溃级是确定性的,直接一票否决,连比都不用比;
      #  2) 软指标(功能好不好)不可数 → 交给两两比较:只有 Critic 判定
      #     candidate 真的比 best 更满足需求,才换。改糟了/打平 → 守住 best。
      next unless hard_errors(candidate).empty?
      next unless Critic.better?(@brief, candidate, best)
      best = candidate
      problems = check(best)                          # 换了人,重新体检
    end

    # 交出的是这几轮里【最好的一版】,不是最后一版。
    # repairs 记的是"尝试了几次修复"(某次可能没被采纳)。
    { angle: @angle, html: best, repairs: repairs, errors: problems }
  end

  private

  # 完整自检 = 硬检查(崩溃级)+ Critic(功能级)。三者契约一样:→ 问题字符串数组。
  # 新增一个检查维度,就是在这里多 + 一项 —— loop 主体一行都不用动。
  def check(html)
    hard_errors(html) + Critic.review(@brief, html)
  end

  # 崩溃级硬检查:静态结构 + 真沙箱跑。确定性、可数,用来一票否决崩掉的候选。
  def hard_errors(html)
    Validator.check(html) + Sandbox.check(html)
  end

  def generate
    raw = @agent.call(<<~MSG)
      需求:#{@brief}
      #{lessons_block}
      你这一版的风格侧重:#{@angle}
    MSG
    strip_fences(raw)
  end

  # 把检索来的过往经验拼成一段提醒,塞进生成 prompt。
  # 这就是"记忆被用上"的那一刻:不是把历史全倒回去,只把相关的几条变成避坑提示。
  def lessons_block
    return "" if @lessons.empty?
    "过去做类似东西踩过的坑,这次请提前避开:\n" +
      @lessons.map { |l| "- #{l}" }.join("\n") + "\n"
  end

  # 把"上一版坏 HTML + 自检错误"拼成一个新 prompt,要一版修好的。
  # 注意:Agent 没记忆(task/kill 那派),所以上下文必须自己塞进 prompt 里 ——
  # 这就是"无状态反馈"。等以后换成带记忆的 max-context agent,这里会简化成多轮对话。
  def regenerate(html, errors)
    raw = @agent.call(<<~MSG)
      你上一版 HTML 没通过自检,有这些问题:
      #{errors.map { |e| "- #{e}" }.join("\n")}

      请在保持原有功能和风格(#{@angle})的前提下,只修复上述问题,
      重新输出【完整的】单文件 HTML。仍然只输出 HTML 源码本身,
      第一行必须是 <!DOCTYPE html>,不要任何解释。

      这是上一版(需要修复):
      #{html}
    MSG
    strip_fences(raw)
  end

  # DeepSeek 有时还是会包一层 ```html,稳一手剥掉。
  # 这种"模型不老实、我兜底"的护栏,正是弱模型下要练的编排肌肉。
  def strip_fences(text)
    text.to_s.strip
        .sub(/\A```(?:html)?\s*\n?/, "")
        .sub(/\n?```\s*\z/, "")
        .strip
  end
end
