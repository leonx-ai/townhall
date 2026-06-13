# townhall

一个用来**学多 agent 编排**的玩具。纯 Ruby、DeepSeek 驱动。

> 一句话 → 并行起 N 个 agent 各出一版 → 挑一个最好的 → 出一个能点开的链接。

不是为了做产品,是为了**亲手写出一个 orchestrator 的内核**,把"协调 / 并行 / 收敛"这几块从"听说过"变成"摸过"。

📖 **这趟怎么做的、踩了哪些坑、每个结论怎么验 → 完整 devlog:<https://leonx.ai/posts/townhall.html>**

## 跑起来

```bash
cp .env.example .env      # 填上你的 DEEPSEEK_API_KEY
bundle install
bin/townhall "帮我做一个班级抽奖器,能输入名单,点开始随机抽,动画好看一点"
# 跑完会打印一个 file:// 链接,open 一下就能看
```

## 自己跑(Don't trust, verify)

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/leonx-ai/townhall)

- **本地**:`cp .env.example .env` 填 DeepSeek key → `bundle install` → 跑下面任意脚本。
- **云端一键**:点上面的 Codespaces 徽章(先在 GitHub 仓库设一个名为 `DEEPSEEK_API_KEY` 的 secret),进去在真终端里直接跑,本地什么都不用装。

每个脚本对应 [devlog](./devlog.md) 里的一个结论。挑你想验的跑:

| 想验证的结论 | 跑这个 | 你会看到 |
|---|---|---|
| 工具调用让模型从"会说"变"能做" | `ruby bin/try-tools` | 不给工具算错,给个 calc 工具就算对 |
| Critic 会幻觉、还漏掉真 bug | `ruby bin/eval-critic` | 误报/真召回的真实分布(默认 chat 很难看;`JUDGE_MODEL=deepseek-reasoner ruby bin/eval-critic` 看误报怎么掉到 0) |
| "停下来"靠外部闸,不靠模型自觉 | `bin/try-recursion "做一个在线测验平台" 3 12` | 多数叶子是被深度/预算【逼停】的 |
| 规则路由脆、LLM 路由灵活 | `ruby bin/try-route` | 规则 3/5 vs LLM 5/5 |
| 换任务只换 Domain、不动编排核 | `bin/run-task email` | 同一套核跑正则,不是网页 |
| 手撕字符串 vs 结构化输出 | `ruby bin/try-structured` | 正则抠错数字 vs 拿到干净对象 |
| 写入闸挡住错经验(heresy) | `bin/learn "井字棋" "井字棋是 4x4 共 16 格"` | 评审小组 0/3 拦下、不写入 |
| prompt injection 与三层防御 | `ruby bin/try-injection` | 劫持 + 输出侧确定性兜底 |

(沙箱相关的 `bin/check-sandbox`、`bin/eval-system` 需要 Chromium;Codespaces 已自动装,本地需自备 Chrome。)

## 代码地图(按主题分组,组内大致按该先读哪个排)

**主管线(先读这条,看一句话怎么变成一个链接)**

| 文件 | 角色 | 学什么 |
|------|------|--------|
| `lib/coordinator.rb` | **编排核心** | 怎么指挥 agent 协作 —— 最该读懂的 |
| `lib/parallel.rb` | 并行 | fan-out:别排队等 |
| `lib/worker.rb` | 工人 | 一版 HTML;自检自改 loop(agent in a loop) |
| `lib/judge.rb` | 评委 | 发散之后怎么收敛(已改用结构化输出) |

**验证:从"崩没崩"到"对不对"**

| 文件 | 角色 | 学什么 |
|------|------|--------|
| `lib/validator.rb` | 静态自检 | 把 HTML 当字符串读,抓结构残废 |
| `lib/sandbox.rb` | 真沙箱 | 把 HTML 当程序跑,抓运行时 bug;契约同 validator |
| `lib/critic.rb` | 评审员 | agent 验 agent:验"功能对不对";软指标用两两比较收敛 |

**记忆 / 真相源**

| 文件 | 角色 | 学什么 |
|------|------|--------|
| `lib/memory.rb` | 真·记忆 | 持久(存磁盘)+ 检索(取回相关几条),跨运行 |
| `lib/gatekeeper.rb` | 写入闸 | agent 提议的经验要过评审小组才算数,挡"带公章的 heresy" |
| `lib/gallery.rb` | 发现 / 画廊层 | 把散落的产物攒成有状态、可搜的库 |

**编排的几种形状**

| 文件 | 角色 | 学什么 |
|------|------|--------|
| `lib/assembly.rb` | 分解(垂直) | 拆成有序步骤、流水线一段段建;对照 worker 的水平 fan-out |
| `lib/recursive.rb` | 递归 +「停下来」 | agent 派 agent;模型停不下来,靠深度/预算两道闸收敛 |
| `lib/router.rb` | 路由 | 看一眼输入选走哪条路;规则 vs LLM;路由器是个可被 eval 的分类器 |

**底层原语 / 通用化 / 护栏**

| 文件 | 角色 | 学什么 |
|------|------|--------|
| `lib/agent.rb` | agent 原语(min) | 一次"系统提示+输入→文本",一次性、无记忆 |
| `lib/conversation.rb` | 多轮对话(max) | 一个 chat 滚到底;是"上下文长",【不是】记忆 |
| `lib/tools.rb` | 工具调用 | 模型请求→你执行→喂回→续答;从"会说"到"能做"的原子 |
| `lib/structured.rb` | 结构化输出 | 让模型吐可解析 JSON,别再手撕字符串;三档强约束的取舍 |
| `lib/domain.rb` | 领域包(可插拔) | 一个领域 = 怎么生成 + 怎么验;换任务就换它 |
| `lib/task_runner.rb` | 通用编排核 | 只认 Domain、不认 HTML;同一套核跑任意任务 |
| `lib/guard.rb` | 护栏 | 防 prompt injection:输入框起来 / 输出确定性校验 / 工具加闸 |

跑完除了单个作品链接,还会刷新一个画廊首页 `output/index.html`,把历次产物列出来、可按需求关键词搜。

记忆存在 `output/memory.json`,跑新任务前 coordinator 会检索相关经验、塞给工人避坑。

## 验证 / 试玩脚本

**验证(先验后信,别盲信)**
- `ruby bin/check-sandbox` —— 用已知好/坏的 HTML 逼沙箱表态,确认它不漏报也不误报(不烧 token)。
- `ruby bin/check-critic` —— 用已知好/坏的实现验 Critic 不装睡、能选对(烧几个 token)。
- `ruby bin/eval-critic [n]` —— 钉死输入跑 N 次,量化 Critic 的误报 / 真召回(组件 eval)。
- `ruby bin/eval-system` —— 跑整条管线评最终产物质量(系统 eval,最贵);改动前后对比看好坏。

**试玩(每个对应一个概念)**
- `ruby bin/try-memory` —— min(一次性 Agent)vs max(一场多轮 Conversation)。
- `bin/try-decompose "需求"` —— 垂直分解:Planner 拆步骤 → 流水线一段段建。
- `bin/try-recursion "任务" [深度] [预算]` —— 递归 +「停下来」:模型总想再拆,靠深度/预算逼停。
- `bin/run-task [email|phone|date]` —— 通用编排核跑【非 HTML】任务;换任务只换 Domain。
- `ruby bin/try-tools` —— 工具调用:不给工具算错,给个 calc 工具它自己借来算对。
- `ruby bin/try-structured` —— 手撕字符串 vs 结构化输出(JSON 模式 + 校验)。
- `ruby bin/try-route` —— 规则路由 vs LLM 路由,各自准不准(路由器的 mini eval)。
- `ruby bin/try-injection` —— prompt injection 怎么劫持 agent,以及三层防御。

**记忆写入(对照看"写者唯一" vs "过闸")**
- `bin/remember "场景" "经验"` —— 人手直接写(信任写者,不烧 token)。
- `bin/learn "场景" "经验"` —— agent 提议 → 评审小组把关 → 过了才写(挡 heresy)。

## 已经做了

- [x] **自检自改循环**:worker 产物跑校验,报错就带着错误反馈自己改,最多 N 轮;爬山保留最优版,改糟了不倒退
- [x] **真沙箱**:headless Chrome(ferrum)实跑,抓 JS 运行时异常 / 空白渲染;和静态校验共用 `check(html) → [错误]` 契约,直接插进同一个 loop
- [x] **评审员 Critic**:agent 验 agent,验"功能对不对";软指标用两两比较收敛 + 位置偏好对调。用 eval 实测后,Critic/Judge 默认走 `deepseek-reasoner`(零幻觉)
- [x] **发现 / 画廊层**:`output/gallery.json` 累积 manifest + 自动生成可搜的画廊首页
- [x] **min/max 上下文**:`Agent`(一次性)对 `Conversation`(一场多轮),把 Yegge 的 minimax-context 摆成两个对象
- [x] **真·记忆**:`Memory` 持久存经验 + 按需求关键词检索,跑新任务时取回相关几条注入工人(避坑)
- [x] **任务分解(垂直)**:`Assembly` 拆步骤 + 流水线建;作为第 4 个选手进 fan-out,和 3 个水平风格版同场 PK
- [x] **递归 +「停下来」**:`Recursive` agent 派 agent;实测模型几乎不主动收手(75% 的叶子靠深度/预算逼停),收敛全靠外部硬闸
- [x] **通用核 + 可插拔领域**:`TaskRunner` 只认 `Domain`(生成 + 验),不认 HTML;同一套核跑通了正则任务。硬验证器(可数)直接挑最优,不需要 Critic/Judge
- [x] **记忆写入闸**:`Gatekeeper` 让 agent 提议的经验过独立评审小组,多数通过才写入;挡"带公章的 heresy"(实测坏/错经验被 0/3 拦下)
- [x] **系统级 eval**:`bin/eval-system` 跑整条管线、给最终产物打分(客观沙箱 + 软评分)、汇总;改动前后对比的回归网
- [x] **工具调用**:`Tools` + `bin/try-tools`,模型请求→执行→喂回→续答的循环;"会说"到"能做"
- [x] **结构化输出**:`Structured` 用 JSON 模式拿可解析对象,替掉手撕字符串;`judge` 已切过去。实测 DeepSeek 全系只到 JSON 模式,严格 schema 被拒(库的能力表撒谎,探针才发现)
- [x] **路由**:`Router` 规则 vs LLM,看输入选路;路由器是可被 eval 的分类器
- [x] **护栏 / prompt injection**:`Guard` 三层(输入框起来 / 输出确定性校验 / 工具加闸)

## 一条贯穿全程的主线

**非确定的组件,最终都得靠外面的【确定性闸】兜底** —— 同一个道理换了一个又一个位置:
自检 loop 靠 `MAX_REPAIRS`、Critic/路由器靠 eval 量化、递归靠 depth/budget、记忆靠写入闸、安全靠输出校验。
模型的自我判断信不过,这不是 bug,是工程现实。一句话:**把"对/安全/该停"从【靠模型自觉】变成【被系统强制】。**

另一条副线:**Don't trust, verify** —— 文档/库的能力表说支持严格 schema,真打 API 才发现被拒;一次结果(eval、路由)说明不了什么,要量分布、要 A/B。

## 还没做(下一轮)

- [ ] 公平 PK:把所有候选都落盘(现在只存赢家,没法对比);给 assembly 选手也套上自检 loop
- [ ] 把 `Router` 接进主管线:简单需求走便宜路、难的走 fan-out(现在不管啥都重武器)
- [~] 检索升级到 RAG(embedding/向量):**刻意不在玩具里做** —— 这点量(几条一句话经验)关键词匹配就够,上 RAG 是"规模没到先建基建"。真到知识库规模(如 leonclass)才换。留作判断示例,非缺口。
- [ ] 系统 eval 加【行为断言】档:每个 fixture 模拟点按钮、断言交互真发生(对 leonclass 最关键)
- [ ] `Structured` 升级:换支持严格 schema 的模型时,把 `with_params` 换成 `with_schema`,连校验都省
