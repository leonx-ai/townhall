# 最糙的"自检":不跑浏览器,只做结构层面的体检。
# 返回错误字符串数组 —— 空数组代表通过。
#
# 关键:返回的是"可操作的错误描述",不是 true/false。
# 因为这些字符串会被原样喂回给 worker,让它照着改 ——
# 所以每一条都得是它看得懂、改得动的话。
#
# 这是"自检自改 loop"的左半边(检)。右半边(改)在 worker.rb。
# 真正跑 headless 浏览器的"硬校验"是下一项("真沙箱"),先不碰。
module Validator
  # 这些标签都是成对出现的,开闭数量对不上,基本就是没闭合或被截断。
  PAIRED_TAGS = %w[html head body div script style button ul ol].freeze

  def self.check(html)
    text = html.to_s
    errors = []

    # 太短就别往下查了,直接判废 —— 多半是空的或输出被截断。
    if text.length < 80
      return ["产物太短(#{text.length} 字符),基本是空的或被截断了"]
    end

    unless text =~ /\A\s*<!DOCTYPE html>/i
      errors << "第一行必须是 <!DOCTYPE html>"
    end

    %w[<html <body].each do |tag|
      errors << "缺少 #{tag}> 标签" unless text.downcase.include?(tag)
    end

    unless text.downcase.include?("</html>")
      errors << "缺少结尾的 </html>,输出可能被截断了"
    end

    # 成对标签配平检查
    PAIRED_TAGS.each do |tag|
      open  = text.scan(/<#{tag}(?:\s|>|\/)/i).size
      close = text.scan(/<\/#{tag}>/i).size
      next if open.zero? && close.zero?  # 没用到这个标签,跳过
      if open != close
        errors << "<#{tag}> 标签没配平:#{open} 个开,#{close} 个闭"
      end
    end

    # 有 <script> 却看不到任何函数/事件 —— 交互大概率没真正实现。
    if text.downcase.include?("<script") &&
       text !~ /function|=>|addEventListener|onclick/i
      errors << "有 <script> 但看不到任何函数或事件处理,交互可能没实现"
    end

    errors
  end
end
