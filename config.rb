require "ruby_llm"
require "dotenv/load"

RubyLLM.configure do |config|
  config.deepseek_api_key = ENV.fetch("DEEPSEEK_API_KEY")
  config.request_timeout  = ENV.fetch("RUBYLLM_REQUEST_TIMEOUT", "300").to_i
end

# DeepSeek 官方 API 的模型 id。
# worker 用 chat;judge 也先用 chat(快、稳)。
# 想试 reasoner 做评判,把 JUDGE_MODEL 改成 deepseek-reasoner 即可。
WORKER_MODEL = ENV.fetch("WORKER_MODEL", "deepseek-chat")
JUDGE_MODEL  = ENV.fetch("JUDGE_MODEL", "deepseek-chat")
