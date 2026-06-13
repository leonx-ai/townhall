require "ruby_llm"

# 最小的 agent 原语:一次性"系统提示 + 用户输入 → 文本输出"。
# 编排层(worker / judge / coordinator)全都建立在它之上。
#
# 注意:每次 call 都是独立的一轮、没有记忆 —— 这就是 Yegge 说的
# "task, kill it, task, kill it" 那一派(min 上下文)。等以后做需要
# 多轮对话的难任务时,再加一个"带记忆"的版本(max 上下文)。
class Agent
  def initialize(model:, system:)
    @model = model
    @system = system
  end

  def call(prompt)
    chat = RubyLLM.chat(model: @model, provider: :deepseek, assume_model_exists: true)
    chat.with_instructions(@system).ask(prompt).content
  end
end
