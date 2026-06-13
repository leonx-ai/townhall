require "ruby_llm"

# 一场【多轮对话】(Yegge minimax-context 里的 max 那派 / crew)。
#
# 注意:这【不是记忆】。它的"记得",只是因为前面的话还躺在这【一场对话】的
# 上下文窗口里。chat 对象一死,全没了。它就是一场更长的聊天而已 ——
# 不持久、不能跨对话取回。真·记忆是另一回事(持久存储 + 按需检索),见 TODO。
#
# 和 lib/agent.rb 的区别,只在【chat 活多久】:
#   Agent         每次 call 都开一个【新】chat,答完即扔 —— task, kill it。一次性。
#   Conversation  全程就【一个】chat,每次 say 接着往下说 —— 上下文越滚越肥。
#
# 各管各的:自包含小任务用 Agent(省 token、互不干扰);需要"读完资料再慢慢
# 聊、聊到收敛"的难设计任务用 Conversation。代价:历史一直累加,token 大致随
# 轮数二次增长,太长之后模型表现还会掉 —— 所以这是【刻意】为难任务选的,不是默认更好。
class Conversation
  def initialize(model:, system:)
    # 关键就这一行:chat 只建一次、之后一直复用 —— 历史就留在它身上。
    # (Agent 是每次 call 都新建,所以一场会就散、打完即忘。)
    @chat = RubyLLM.chat(model: model, provider: :deepseek, assume_model_exists: true)
    @chat.with_instructions(system)
  end

  # 说一句、拿回复。每次都接着前面的对话,模型记得【这场会】里说过什么。
  def say(message)
    @chat.ask(message).content
  end

  # 这场会攒了几轮(我说了几句)—— 用来直观感受"上下文在变肥"。
  def turns
    @chat.messages.count { |m| m.role == :user }
  end
end
