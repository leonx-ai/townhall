require "ruby_llm"

# 一个"工具"= 一个模型【可以请求你去执行】的能力。
#
# 子类化 RubyLLM::Tool,声明三件事 —— 它叫啥、干嘛的、要哪些参数 —— 再实现 execute。
# 模型看到这份"说明书"后,在需要时不会直接作答,而是吐出一个【调用请求】(工具名 + 参数);
# 由你的代码真去跑 execute,把结果喂回去,模型再继续。这就是 tool use 的全部。
#
# 注意 execute 里那行算式:那是【你的确定性代码】在干活,不是模型在猜。
# 模型负责"决定要不要用、用什么参数",真正的计算交给可靠的代码 —— 各司其职。
class Calculator < RubyLLM::Tool
  description "做精确的乘法。需要把两个数相乘时调用我 —— 不要自己心算,你(模型)算大数会出错。"
  param :a, type: "number", desc: "第一个乘数"
  param :b, type: "number", desc: "第二个乘数"

  def execute(a:, b:)
    a * b
  end
end
