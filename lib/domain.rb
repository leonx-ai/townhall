# 一个"领域"(Domain)= 把任务里【和领域相关】的两样东西打包:
#   system           —— 怎么生成(给生成 agent 的系统提示)
#   check(brief, art) —— 怎么验(产物 → 错误列表,空 = 通过)
#
# 这就是"通用核 + 可插拔的边":编排核(TaskRunner)只跟 Domain 打交道,
# 不知道产物是 HTML 还是正则。换任务 = 换一个 Domain,编排逻辑一行不动。
Domain = Struct.new(:name, :system, :checker) do
  def check(brief, artifact)
    checker.call(brief, artifact)
  end
end

# 几个现成的领域。注意它们的 check 各不相同 —— 验证器才是每个领域真正要啃的硬骨头。
module Domains
  module_function

  # 正则:验证器【特别硬】—— 拿已知"该匹配 / 不该匹配"的例子去真跑生成的正则。
  # 对错是确定的、可数的,所以根本不需要 Critic/Judge 那套软判断。
  def regex(should_match:, should_not_match:)
    Domain.new(
      "正则表达式",
      <<~SYS,
        你是正则专家。根据需求,写一个【Ruby 正则表达式】。
        只输出正则本身:不要用 / / 包裹、不要解释、不要代码块。
        例如要匹配三位区号加四位号码,就只输出:  \\A\\d{3}-\\d{4}\\z
      SYS
      lambda do |_brief, pattern|
        re =
          begin
            Regexp.new(pattern)
          rescue RegexpError => e
            return ["正则语法错误:#{e.message}"]
          end
        errors = []
        should_match.each     { |s| errors << "本该匹配却没匹配:#{s.inspect}" unless re.match?(s) }
        should_not_match.each { |s| errors << "本不该匹配却匹配了:#{s.inspect}" if re.match?(s) }
        errors
      end
    )
  end
end
