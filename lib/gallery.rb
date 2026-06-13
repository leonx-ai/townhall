require "json"
require "time"
require "fileutils"

# 发现 / 画廊层:把每次跑出来的产物【攒起来】,组织成一个能浏览、能搜的画廊。
#
# 为什么要单独一层:coordinator 每跑一次只吐一个孤立链接,跑完就散落了,
# 第十次之后你根本找不到第三次做的那个东西。画廊层做两件事 ——
#   record: 把这次的产物 + 元信息追加进一个 manifest(output/gallery.json)
#   render: 读 manifest,生成一个 output/index.html 把它们全列出来、可搜
#
# 这一层的价值不在代码(代码很简单,谁都能抄),在那个【随时间增长的
# manifest】—— 它有状态、会积累,这正是之前聊的"护城河"在这个玩具里的
# 具体形态:抄走代码只得到一个空货架,抄不走你攒了多久的东西。
module Gallery
  OUTPUT_DIR = File.expand_path("../output", __dir__)
  MANIFEST   = File.join(OUTPUT_DIR, "gallery.json")
  INDEX      = File.join(OUTPUT_DIR, "index.html")

  module_function

  # 追加一条记录。entry 至少要有 :brief :angle :rel_path。
  def record(entry)
    FileUtils.mkdir_p(OUTPUT_DIR)
    items = load
    items << entry.merge(created_at: Time.now.iso8601)
    File.write(MANIFEST, JSON.pretty_generate(items))
    items
  end

  def load
    return [] unless File.exist?(MANIFEST)
    JSON.parse(File.read(MANIFEST), symbolize_names: true)
  rescue JSON::ParserError
    []   # manifest 坏了也别让整条流水线挂掉,大不了这次画廊少几条
  end

  # 读 manifest,生成画廊首页:一个自带客户端搜索框的单文件 HTML。
  # (连画廊自己也是一个自包含 HTML —— 跟这个项目造的东西保持同一种形态。)
  def render
    items = load.sort_by { |i| i[:created_at].to_s }.reverse  # 新的排前面
    File.write(INDEX, page(items))
    INDEX
  end

  def page(items)
    cards   = items.map { |i| card(i) }.join("\n")
    haystack = JSON.generate(items.map { |i| i[:brief].to_s.downcase })
    <<~HTML
      <!DOCTYPE html>
      <html lang="zh">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>townhall 画廊</title>
        <style>
          body{font-family:-apple-system,system-ui,sans-serif;max-width:880px;margin:40px auto;padding:0 16px;color:#222}
          h1{margin-bottom:4px}.sub{color:#888;margin-top:0}
          #q{width:100%;padding:10px 12px;font-size:16px;border:1px solid #ccc;border-radius:8px;margin:16px 0;box-sizing:border-box}
          .card{display:block;border:1px solid #eee;border-radius:10px;padding:14px 16px;margin:10px 0;text-decoration:none;color:inherit;transition:.15s}
          .card:hover{border-color:#888;box-shadow:0 2px 8px rgba(0,0,0,.06)}
          .brief{font-size:16px;font-weight:600;margin:0 0 6px}
          .meta{font-size:13px;color:#999;margin:0}
          .tag{display:inline-block;background:#f2f2f2;border-radius:6px;padding:1px 8px;margin-right:6px}
          .empty{color:#aaa;text-align:center;padding:60px 0}
        </style>
      </head>
      <body>
        <h1>🏛 townhall 画廊</h1>
        <p class="sub">共 #{items.size} 个作品 · 越新越靠前</p>
        <input id="q" placeholder="搜索需求关键词……">
        <div id="list">
          #{items.empty? ? %(<p class="empty">还没有作品。跑一次 bin/townhall 就会出现在这里。</p>) : cards}
        </div>
        <script>
          const briefs = #{haystack};
          const q = document.getElementById('q');
          const cards = [...document.querySelectorAll('.card')];
          q.addEventListener('input', () => {
            const k = q.value.trim().toLowerCase();
            cards.forEach((c, i) => { c.style.display = (!k || briefs[i].includes(k)) ? '' : 'none'; });
          });
        </script>
      </body>
      </html>
    HTML
  end

  def card(i)
    day = i[:created_at].to_s.split("T").first
    <<~HTML
      <a class="card" href="#{i[:rel_path]}">
        <p class="brief">#{escape(i[:brief])}</p>
        <p class="meta"><span class="tag">#{escape(i[:angle])}</span>#{day}</p>
      </a>
    HTML
  end

  def escape(s)
    s.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
  end
end
