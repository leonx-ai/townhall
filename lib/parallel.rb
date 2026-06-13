# 并行小工具。MRI 有 GIL,但等 LLM 的 HTTP 响应时会释放 GIL,
# 所以多线程对"等 API"是真并行 —— 3 个工人几乎同时跑完,而不是排队。
#
# 这是你学编排要建立的第一个直觉:fan-out 的本质就是"别排队等"。
module Parallel
  def self.map(items, &block)
    items.map { |it| Thread.new { block.call(it) } }.map(&:value)
  end
end
