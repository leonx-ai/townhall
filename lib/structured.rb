require "json"
require "ruby_llm"

# 结构化输出:不再手撕字符串,让模型直接吐【可解析的 JSON 对象】。
#
# townhall 现在到处在手撕:judge 抠 \d+、critic 认 "OK"、gatekeeper 认 "PASS"、
# 按行切 steps……模型换个说法、加句开场白,解析就崩或者悄悄错。结构化输出根治这个。
#
# 强约束有三档(从弱到强):
#   1. 光在 prompt 里说"给我 JSON" —— 模型可能加开场白/markdown,解析照样崩。
#   2. JSON 模式(response_format=json_object)—— provider 保证【是合法 JSON】(parse 不崩),
#      但不保证字段对,得自己校验。← 实测【DeepSeek 支持的就是这档】。
#   3. 严格 schema(response_format=json_schema)—— 保证【完全符合你的 schema】,字段都不用校验。
#      OpenAI / Anthropic 支持。DeepSeek【全系都拒】(chat 和 v4-pro 实测都报
#      "This response_format type is unavailable now")—— 注意 ruby_llm 的能力表【声称】
#      V4 支持 structured_output,但真实 API 拒;只有打到真接口才发现。又一次:别信能力表,信探针。
#
# 所以在 DeepSeek 上只能用第 2 档 + 自己校验必填键。换成 OpenAI/Anthropic 这类支持第 3 档的,
# 把 with_params 换成 chat.with_schema(schema) 就升级了 —— 一行的事,连校验都省了。
module Structured
  module_function

  # 返回一个已校验必填键的 Hash;出问题时带 "_error"(绝不静默错)。
  def ask(prompt, require_keys:, model: WORKER_MODEL)
    chat = RubyLLM.chat(model: model, provider: :deepseek, assume_model_exists: true)
    chat.with_params(response_format: { type: "json_object" })   # JSON 模式:保证吐合法 JSON
    raw = chat.ask("#{prompt}\n\n只返回 JSON,不要任何其他文字。").content.to_s

    data =
      begin
        JSON.parse(raw)
      rescue JSON::ParserError
        return { "_error" => "返回的不是合法 JSON", "_raw" => raw }
      end

    missing = require_keys.map(&:to_s) - data.keys
    return data.merge("_error" => "缺字段:#{missing.join(', ')}") unless missing.empty?
    data
  end
end
