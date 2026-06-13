require "json"
require "fileutils"

# 真·记忆:持久(存在对话之外的磁盘上)+ 检索(按当前任务取回相关的几条)。
#
# 和 Conversation 的根本区别 ——
#   Conversation 的"记得"活不过一场对话,chat 一死就没。
#   Memory 存在文件里,跨任意多少次运行都还在;而且【不是把全部历史倒回去】
#   (那只是 max 上下文),是只挑【和当前需求相关】的那几条塞进去。
#
# 一条记忆 = { scope: [关键词...], lesson: "一句话经验" }。
# scope 是判断"这条经验适用于当前需求吗"的依据;命中越多越相关。
module Memory
  STORE = File.expand_path("../output/memory.json", __dir__)
  TOP_K = 3   # 最多取回几条 —— 检索的关键就是"只给相关的几条",而不是全倒回去

  module_function

  # 检索:返回和 brief 相关的经验(按命中关键词数排序,最多 TOP_K 条)。
  def recall(brief)
    text = brief.to_s
    load.map { |note| [Array(note[:scope]).count { |kw| text.include?(kw.to_s) }, note] }
        .select { |hits, _| hits.positive? }
        .sort_by { |hits, _| -hits }
        .first(TOP_K)
        .map { |_, note| note[:lesson].to_s }
  end

  # 写入:把一条新经验追加进磁盘(跨运行持久)。
  # 这一版先由人(bin/remember)手动写;以后可以让 agent 跑完自己回看、自己写。
  def remember(scope:, lesson:)
    FileUtils.mkdir_p(File.dirname(STORE))
    notes = load
    notes << { scope: Array(scope), lesson: lesson }
    File.write(STORE, JSON.pretty_generate(notes))
    notes
  end

  def load
    return [] unless File.exist?(STORE)
    JSON.parse(File.read(STORE), symbolize_names: true)
  rescue JSON::ParserError
    []   # 文件坏了也别拖垮主流程,大不了这次没记忆
  end
end
