require_relative "agent"

# 评审员:让一个 agent 来验 agent。
#
# 和 Validator/Sandbox 只问"崩了没"不同,Critic 问的是更难的那个问题 ——
# "它【做到需求要求的事】了吗"。它读「需求 + 产物源码」,挑出功能上没满足
# 需求的地方。这是把自检从"抓崩溃"升级到"验行为",也是 loop 第一次能在
# 正常需求下真正触发的原因。
#
# 两个能力:
#   review(brief, html)   → [问题字符串]   找茬:列出没做到需求的点(空 = 满意)
#   better?(brief, a, b)  → true/false     两两比较:a 是否真的比 b 更满足需求
#
# 为什么要 better?,而不是直接数 review 出来的问题个数:
#   Critic 是非确定的 —— 同一份产物,这次说 2 个问题、下次说 3 个。拿这种
#   抖动的绝对数量去当"改好了没"的判据,爬山会乱跳。经验是:LLM 不擅长打
#   绝对分,却很擅长"A 和 B 哪个好"。所以"这次修改要不要采纳"交给两两比较,
#   稳得多。这就是软指标下做收敛的正确姿势。
module Critic
  REVIEW_SYSTEM = <<~PROMPT
    你是一个严格的 QA。我给你一段【需求】和一份【单文件 HTML 实现】。
    只盯着"功能有没有满足需求"挑问题 —— 不要评价代码风格、美观、命名。

    检查方法(请照做):
    1. 先把需求拆成几个具体功能点。
    2. 逐个功能点对照代码,确认它真的实现了。
    3. 特别检查【边界情况】—— 正常流程之外会发生什么:
       比如操作到极限(填满、清空)、没有赢家/没有结果、重复或非法操作、结束后还能不能再来。
       这些"角落"最容易漏,而漏了往往就是真 bug。

    输出规则:
    - 只挑【会让用户用不了、或明显不符合需求】的真问题;没把握就不要编。
    - 如果实现满足了需求,只回复一个词:OK
    - 否则每行写一个具体问题,一句话,不要编号、不要解释、不要客套。
  PROMPT

  PREFER_SYSTEM = <<~PROMPT
    你是一个严格的 QA。我给你一段【需求】和【两份】实现:A 和 B。
    只从"哪个更满足需求、功能更完整可用"判断,忽略风格和美观。
    只回复一个字母:A 或 B。不要任何其他文字。
  PROMPT

  module_function

  def review(brief, html)
    answer = agent(REVIEW_SYSTEM).call(<<~MSG)
      【需求】#{brief}

      【实现】
      #{html}
    MSG
    parse_problems(answer)
  end

  # a 是否【真的】比 b 更满足需求。
  #
  # LLM 有位置偏好(容易无脑偏向 A 或 B),所以问两遍、把顺序对调:
  # 只有"a 放第一个时选它、a 放第二个时也选它"才算 a 真赢。平局/不一致 → false,
  # 不轻易替换,守住已有的(和之前 loop 的"改糟了不倒退"一脉相承)。
  def better?(brief, a_html, b_html)
    prefer(brief, a_html, b_html) == "A" && prefer(brief, b_html, a_html) == "B"
  end

  # 返回 "A" 或 "B":在「需求】下,first 和 second 哪个更好。
  def prefer(brief, first, second)
    answer = agent(PREFER_SYSTEM).call(<<~MSG)
      【需求】#{brief}

      【实现 A】
      #{first}

      【实现 B】
      #{second}
    MSG
    answer.to_s.strip.upcase.start_with?("B") ? "B" : "A"
  end

  def agent(system)
    Agent.new(model: JUDGE_MODEL, system: system)
  end

  def parse_problems(answer)
    text = answer.to_s.strip
    return [] if text.empty?
    return [] if text =~ /\A(ok|通过|没有问题|无问题|满足)/i
    text.lines
        .map { |l| l.strip.sub(/\A[-*•\d.、)]+\s*/, "") }
        .reject(&:empty?)
        .reject { |l| l =~ /\Aok\z/i }
  end
end
