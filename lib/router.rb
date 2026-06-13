require_relative "structured"

# 路由:看一眼输入,决定走【哪条路】—— 而不是所有任务都用同一套(townhall 现在不管什么
# 需求都 fan-out 3+1)。这是 orchestrator-worker 模式的"前门":先分诊,再分派。
#
# 两种路由器,各有取舍:
#   by_rules —— 关键词规则:便宜、确定、零延迟、零成本,但【脆】(换个说法就漏)、覆盖窄。
#   by_llm   —— LLM 分类器:灵活、能处理模糊说法,但【多一次调用】、非确定、也会误判。
#   实务上常【先规则、命中不了再 LLM 兜底】,兼顾便宜和覆盖。
#
# 两个要记住的点:
#   1. 路由器是个【分类器】,所以能像任何分类器一样被 eval(已知输入→期望路由→准确率)。
#   2. 它是新的【单点故障】:误路由会让任务走错管线、质量【静默】下降 —— 所以值得被量、被兜底。
module Router
  ROUTES = %i[html_app regex question].freeze

  module_function

  # 规则路由:看关键词。便宜,但只认你写进去的那些词。
  def by_rules(text)
    t = text.to_s
    return :regex    if t =~ /正则|regex|匹配.*(格式|字符串)/
    return :html_app if t =~ /做(一)?个|网页|页面|app|应用|游戏|计算器|时钟|清单/
    :question
  end

  # LLM 路由:让模型分类。灵活,但要一次调用,也可能判错。
  def by_llm(text)
    data = Structured.ask(<<~MSG, require_keys: [:route], model: WORKER_MODEL)
      把下面这条用户请求分到【一类】:
      - html_app:要做一个能在浏览器打开看的网页 / 小应用 / 游戏
      - regex:要一个正则表达式
      - question:只是问一个问题,要文字回答

      请求:#{text}

      返回 JSON,形如 {"route": "html_app 或 regex 或 question", "reason": "一句话"}
    MSG
    route = data["route"].to_s.to_sym
    ROUTES.include?(route) ? route : :question   # 兜底:不认识就当成问题
  end
end
