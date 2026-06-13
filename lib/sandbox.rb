require "ferrum"
require "tempfile"

# 真沙箱:把 HTML 真正放进 headless Chrome 跑一遍,观察它"活着没有"。
#
# 和 Validator 的根本区别:
#   - Validator 把 HTML 当【字符串】读(静态)—— 只能看出结构残废。
#   - Sandbox  把 HTML 当【程序】跑(动态)—— 能抓到 JS 一加载就炸、
#     页面渲染成空白、按钮全死这类静态检查永远看不见的功能 bug。
#
# 关键设计:契约和 Validator 完全一样 —— check(html) → [错误字符串]。
# 所以它能原样插进 worker 已有的自检自改 loop,loop 一行都不用改。
#
# 依赖:gem "ferrum" + 本机装了 Chrome / Chromium。
# 如果浏览器起不来(比如没装 Chrome),返回空数组【跳过】检查 ——
# 那是环境问题,不是 HTML 的错,绝不能拿它去惩罚产物、让 worker 白白自改。
module Sandbox
  LOAD_WAIT = 0.8   # 加载后等一下,让首屏 JS 跑起来

  def self.check(html)
    errors  = []
    runtime = []     # 收集页面自己抛的 JS 错误
    file = nil
    browser = nil

    # 浏览器能不能启动,和 HTML 好不好是两回事。起不来就跳过,别误判。
    begin
      browser = Ferrum::Browser.new(headless: true, process_timeout: 20)
    rescue => e
      warn "[sandbox] 跳过沙箱检查(浏览器无法启动:#{e.message})"
      return []
    end

    begin
      file = Tempfile.new(["townhall-sandbox", ".html"])
      file.write(html)
      file.close

      page = browser.create_page
      page.command("Runtime.enable")

      # 订阅 CDP 事件:未捕获异常 + console.error
      page.on("Runtime.exceptionThrown") do |params, _|
        d = params.dig("exceptionDetails", "exception", "description") ||
            params.dig("exceptionDetails", "text") || "未知异常"
        runtime << d.to_s.lines.first.to_s.strip
      end
      page.on("Runtime.consoleAPICalled") do |params, _|
        next unless params["type"] == "error"
        txt = Array(params["args"]).map { |a| a["value"] || a["description"] }.compact.join(" ")
        runtime << "console.error: #{txt}"
      end

      page.go_to("file://#{file.path}")
      sleep LOAD_WAIT

      # 页面是不是"活的":body 里有没有真的渲染出内容。
      body_len = (page.evaluate("document.body ? document.body.innerText.trim().length : 0") rescue 0)
      errors << "页面加载后 body 是空的,可能渲染失败或 JS 崩了" if body_len.to_i.zero?

      runtime.uniq.each { |e| errors << "页面运行时报错:#{e}" }
    rescue => e
      # 加载/执行阶段的异常,这次算 HTML 的问题,喂回去让它改。
      errors << "沙箱运行页面时出错:#{e.message}"
    ensure
      browser&.quit
      file&.unlink if file
    end

    errors
  end
end
