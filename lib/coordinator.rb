require_relative "parallel"
require_relative "worker"
require_relative "judge"
require_relative "gallery"
require_relative "memory"
require_relative "assembly"
require_relative "validator"
require_relative "sandbox"
require "fileutils"

# 编排核心。这是整个项目你最该读懂的一个文件:
# 它自己不写任何 HTML,只负责"指挥 agent 们怎么协作"。
#
#   coordinator(一句话)
#     → 并行起 N 个工人,各出一版        (fan-out / 发散)
#     → 最糙的自检,淘汰废品              (validate)
#     → 评委挑一个赢家                   (收敛)
#     → 落盘,返回可点开的链接
#
# 还没做的(下一轮加):自检自改循环、沙箱真跑、发现/画廊层。
class Coordinator
  # 三个不同的风格角度 —— 故意制造差异,让"挑选"这一步有意义。
  ANGLES = [
    "简洁实用,交互清晰,优先把核心功能做对",
    "视觉华丽,动画和过渡效果丰富",
    "信息密度高,一屏展示尽量多的功能"
  ].freeze

  def run(brief)
    log "需求:#{brief}"
    log "并行起 #{ANGLES.size} 个工人,各出一版……"

    # 0) 检索记忆:从过去的经验里,取回和这个需求相关的几条(持久 + 检索)。
    lessons = Memory.recall(brief)
    unless lessons.empty?
      log "想起 #{lessons.size} 条相关经验,带给工人:"
      lessons.each { |l| log "  ↺ #{l}" }
    end

    # 1) 并行生成(fan-out)。两种编排形状一起 PK:
    #    - 3 个 worker:水平 —— 各做一份完整的(自带自检自改 loop)
    #    - 1 个 assembly:垂直 —— 分解成有序步骤、流水线一段段建
    #    都丢进同一批候选,最后让评委挑。
    producers = ANGLES.map do |angle|
      -> { Worker.new(brief, angle, lessons: lessons).build }
    end
    producers << -> { decomposed_candidate(brief, lessons) }
    candidates = Parallel.map(producers, &:call)

    candidates.each do |c|
      status = c[:errors].empty? ? "自检通过" : "仍有 #{c[:errors].size} 处问题"
      log "  · #{c[:angle][0, 12]}…:自改 #{c[:repairs]} 轮,#{status}"
      # 把 Critic 具体抱怨啥也打出来 —— 没有这个,你判断不了它是真发现还是瞎找茬。
      c[:errors].each { |e| log "      ↳ #{e}" }
    end

    # 2) 兜底:彻底废掉的(太短 / 不像 HTML)才淘汰;
    #    带小瑕疵但还能看的留下来,把选择权交给评委。
    candidates.select! { |c| c[:html].length > 50 && c[:html].include?("<") }
    raise "全部工人都没产出有效 HTML" if candidates.empty?
    log "拿到 #{candidates.size} 个有效版本。"

    # 3) 评委挑赢家(收敛)
    winner_idx = Judge.pick(brief, candidates)
    winner = candidates[winner_idx]
    log "评委选了版本 ##{winner_idx}(#{winner[:angle]})。"

    # 4) 落盘
    path = write_site(brief, winner[:html])
    log "完成 → file://#{path}"

    # 5) 记进画廊,刷新画廊首页(发现 / 画廊层)
    rel = path.sub("#{Gallery::OUTPUT_DIR}/", "")
    Gallery.record(brief: brief, angle: winner[:angle], rel_path: rel)
    index = Gallery.render
    log "画廊 → file://#{index}"

    path
  end

  private

  # 第 4 个选手:用分解(垂直)而不是一口气(水平)建一版。
  # 包成和 worker 一样的候选 shape,这样后面的淘汰 / 评委 / 画廊全都不用改。
  # 注意:它走的是裸流水线,没有 worker 那套自检自改 loop —— 所以这场 PK 还不算
  # 完全对等(assembly 少了一层自我修复)。先这样看效果,要对等是下一步。
  def decomposed_candidate(brief, lessons)
    steps = Assembly.plan(brief)
    html  = Assembly.build(brief, steps, lessons: lessons)
    { angle: "分步搭建(分解→流水线)",
      html: html,
      repairs: 0,
      errors: Validator.check(html) + Sandbox.check(html) }
  end

  def write_site(brief, html)
    slug = brief.gsub(/[^\p{Word}]+/, "-").gsub(/\A-+|-+\z/, "")[0, 30]
    slug = "app" if slug.nil? || slug.empty?
    dir = File.expand_path("../output/#{slug}-#{rand(36**4).to_s(36)}", __dir__)
    FileUtils.mkdir_p(dir)
    file = File.join(dir, "index.html")
    File.write(file, html)
    file
  end

  def log(msg)
    puts "[townhall] #{msg}"
  end
end
