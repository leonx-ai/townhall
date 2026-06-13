require_relative "structured"

# 评委:在 N 个版本里挑一个最好的,返回下标(从 0 开始)。
# 这是编排里的"收敛"步骤 —— 并行发散之后,得有人拍板。
#
# 这一版改用【结构化输出】拿结果,不再手撕 answer[/\d+/]。
# 旧写法是从一段话里抠第一个数字,模型一旦先蹦出别的数字(比如"在 3 个版本里…")
# 就会抠错。现在让它直接吐 {"winner": 数字, "reason": "…"},当对象用。
class Judge
  def self.pick(brief, candidates)
    list = candidates.each_with_index.map do |c, i|
      "## 版本 #{i}(风格:#{c[:angle]})\n#{c[:html][0, 2000]}"
    end.join("\n\n")

    data = Structured.ask(<<~MSG, require_keys: [:winner], model: JUDGE_MODEL)
      你是一个挑剔的产品评审。下面是同一个需求的多个 HTML 实现版本,
      挑出综合最好的一个(功能完整、可用、好看)。

      需求:#{brief}

      #{list}

      返回 JSON,形如 {"winner": <最好版本的编号,0 到 #{candidates.size - 1}>, "reason": "<一句话理由>"}
    MSG

    # 即便用了结构化,值仍可能越界(JSON 模式只保证"是合法 JSON",不保证值在范围内),
    # 所以还是夹一道兜底;解析失败时 data["winner"] 为 nil → to_i → 0,退回第 0 版。
    idx = data["winner"].to_i
    idx.between?(0, candidates.size - 1) ? idx : 0
  end
end
