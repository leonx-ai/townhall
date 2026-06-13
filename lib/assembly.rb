require_relative "agent"

# 任务分解(垂直)。和 worker 的水平 fan-out 正好是两种并行形状:
#   worker   = 同一个需求,N 个风格【各做一份完整的】,最后挑一份。
#   Assembly = 一份东西,拆成有序步骤,【一段段累加】建起来。
#
# 三个新概念都在这:
#   分解   Planner 把需求拆成有序子任务。
#   依赖   后一步看得见前一步的产物(流水线,不是各做各的)。
#   集成   每一步把自己那部分【接进】同一份产物 —— 集成是持续发生的,不是最后才拼。
#
# 为什么用"流水线累加",而不是"并行各做一块,最后合并":
#   并行做出 HTML 片段 / JS 片段 / CSS 片段,最后得有个 agent 把它们【合并】成一个
#   自洽的单文件 —— 合并极容易缝出一个四不像。集成才是分解真正难的地方。
#   流水线让集成在【每一步】自然发生,全程只有一份在长大的产物,绕开了合并地狱。
#   (代价:必须串行,后一步要等前一步;而且每步都重发/重出整份 HTML,token 偏贵。)
module Assembly
  PLANNER_SYSTEM = <<~PROMPT
    你是一个前端架构师。把用户需求拆成 2~4 个【有序】的构建步骤,后一步在前一步基础上做。
    典型顺序:先搭 HTML 结构和占位元素,再实现交互逻辑(JS),最后加样式美化。
    只输出步骤,每行一个,一句话,不要编号、不要解释、不要客套。
  PROMPT

  BUILDER_SYSTEM = <<~PROMPT
    你是一个前端工程师。我会给你:整体需求、当前这一版 HTML、以及这一步要做的事。
    请在【当前 HTML 的基础上】完成这一步,并保持已有的部分继续可用。
    只输出完整的单文件 HTML 源码本身,第一行必须是 <!DOCTYPE html>,不要 markdown、不要解释。
  PROMPT

  module_function

  # 分解:需求 → 有序子任务列表。
  def plan(brief)
    Agent.new(model: WORKER_MODEL, system: PLANNER_SYSTEM)
         .call("需求:#{brief}")
         .lines.map { |l| l.strip.sub(/\A[-*•\d.、)]+\s*/, "") }
         .reject(&:empty?)
  end

  # 流水线:按子任务顺序,把产物一段段建起来。每步都把上一步的成果带进去。
  # lessons:从 Memory 检索来的避坑经验,和 worker 一样带上,PK 才公平。
  def build(brief, steps, lessons: [], log: nil)
    builder = Agent.new(model: WORKER_MODEL, system: BUILDER_SYSTEM)
    avoid = lessons.empty? ? "" : "\n注意避开这些坑:\n#{lessons.map { |l| "- #{l}" }.join("\n")}\n"
    html = "(还没有,请从头开始)"
    steps.each_with_index do |step, i|
      log&.call("第 #{i + 1}/#{steps.size} 步:#{step}")
      raw = builder.call(<<~MSG)
        整体需求:#{brief}
        #{avoid}
        当前这一版 HTML:
        #{html}

        这一步要做的:#{step}
      MSG
      html = strip_fences(raw)   # 上一步的产物,成了下一步的输入 —— 这就是"依赖"
    end
    html
  end

  def strip_fences(text)
    text.to_s.strip
        .sub(/\A```(?:html)?\s*\n?/, "")
        .sub(/\n?```\s*\z/, "")
        .strip
  end
end
