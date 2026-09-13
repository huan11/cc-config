# 可复用提示词库 —— 按阶段

> 配合 `SKILL.md` 陪跑使用:陪跑某阶段的某件工作时,取对应模板,**据此实际驱动分析/产出**(不是把模板丢给用户)。
> `[...]` 是占位符。标注了建议的 Claude 产品面:**Chat**(快速问答)/ **Cowork**(联网/文件/定时的知识工作)/ **Code**(写测试上线代码)。
> 结构化 devil's advocate 贯穿所有阶段。

---

## ① Idea —— 验证一个想法是否值得做

**1.1 把问题打磨成可验证假设 · Chat**
```
Here is my problem statement: "[your rough problem statement]".
Help me sharpen it into a specific, testable hypothesis. Force specificity on:
who exactly has this problem, how often they hit it, how severely it affects them,
and what they currently do about it. Tell me which parts are still too vague to test.
```

**1.2 让 Claude 反驳你的想法(找反证)· Chat / Cowork**
```
Argue against my idea. Actively look for disconfirming evidence that refutes this
hypothesis: "[your hypothesis]". Surface negative market signals, failed
competitors in this space, customer behavior patterns, and structural obstacles
that a supportive analysis would quietly deprioritize.
```

**1.3 对抗性竞品分析(破解 competitor neglect)· Chat**
```
Make the most compelling argument for why a competitor in this space would succeed
while I do not. Analyze why their approach may be better, why customers would
choose them, and why my differentiators ([list your differentiators]) may not be
as defensible as I think.
```

**1.4 分层绘制竞争格局 · Cowork**
```
Map my competitive landscape by tier: direct competitors, indirect competitors,
potential acquirers, and adjacent players who could move into my space. For each
tier, argue why it poses a genuine threat — not the easy-to-dismiss version. My
product: [describe].
```

**1.5 综合竞品评价,找未被解决的痛点 · Cowork**
```
Synthesize customer reviews of competitors across [key sources / review sites].
Identify the top recurring complaints that existing solutions have NOT resolved.
Then tell me whether my hypothesis ([hypothesis]) addresses any of them.
```

**1.6 市场规模测算(TAM/SAM/SOM)· Cowork**
```
Build TAM/SAM/SOM models for [my market] from publicly available data, and
pressure-test the assumptions behind each number. Tell me whether the market is
expanding, consolidating, or mature. Then map the buyer landscape: who holds
budget, who influences decisions, and whether those are the same person.
```

**1.7 趋势判断(顺风还是逆风)· Cowork**
```
Identify three external trends — regulatory, technological, or demographic — that
could significantly affect [my market] in the next two years. For each, assess
whether it is a tailwind or a headwind for my specific hypothesis: [hypothesis].
```

**1.8 设计/审核客户访谈问题 · Chat**
```
Here are my draft customer-discovery interview questions: [paste questions].
Audit them. Flag any question that is leading, future-facing ("would you use…"),
too broad, or likely to produce a socially desirable answer. Rewrite the weak ones
to surface what people actually DID, not what they think they would do. Then suggest
a follow-up probe for the 2–3 moments most likely to generate deflection.
```

**1.9 访谈后复盘(对称性检验)· Cowork**
```
Here are my notes from the last [N] user interviews: [paste / attach].
Produce two lists: (1) evidence that supports my hypothesis, and (2) evidence that
challenges it. If the supporting list is significantly longer, tell me honestly
whether that asymmetry reflects what's actually in the data — or what I was hoping
to find.
```

**1.10 外联与排期自动化 · Cowork**
```
Using this validated interview target profile — [job titles, company types,
seniority levels] — build a prospect list with verified contact info, draft a
personalized outreach sequence, and set up a tracking sheet with columns for
outreach status, follow-up cadence, and interview completion. Then run the
coordination (send, schedule via Gmail/Calendar, and day-7 follow-ups).
```

**1.11 压力测试最终方案 · Chat**
```
Here is my solution concept: [describe]. Identify the three assumptions this design
depends on most heavily. For each, tell me what would have to be true for it to hold,
and what the consequences are if it doesn't.
```

**1.12 构建最小可感原型 · Code**
```
The single core interaction my solution depends on is: [describe the one interaction].
Build only that — the minimum surface area needed to put it in front of a real person
and get a genuine reaction. Don't build anything else yet.
```

---

## ② MVP —— 把验证过的问题变成真实产品

**2.1 先定架构,再写代码(生成 CLAUDE.md)· Chat → Code**
```
I'm building [product]: the core problem it solves is [problem], the users are [users],
and I realistically expect [scale] in the next six months. Help me define:
(1) the architectural principles that should govern this MVP build,
(2) the dependencies to avoid given my constraints, and
(3) the tradeoffs I'm consciously accepting at this stage.
Output it as a CLAUDE.md I can drop into the repo as persistent project memory.
```

**2.2 定义并守住 MVP 范围 · Chat**
```
Help me write a scope document for my MVP. It must state: what the product DOES,
what it deliberately DOES NOT do, and the feature-amendment criteria — i.e., what
specific evidence from real users would justify adding something new. Product: [describe].
```

**2.3 新功能请求把关(信号 or 冲动)· Chat**
```
A new feature idea just came up: "[feature]". Pressure-test it against my MVP scope doc
[paste scope]. Is this genuine signal from users, or founder enthusiasm dressed up as
product thinking? What user evidence would justify building it now vs. later?
```

**2.4 Claude Code 会话模板 · Code**
```
Session context:
- Architecture context (CLAUDE.md): [paste or reference]
- Task for this session: [specific task]
- Constraints / patterns to observe: [list]
Execute only this task as a decision already made — do not introduce new product
decisions. At the end, output a short log entry: what was built, what decisions were
made, and what assumptions this session introduced.
```

**2.5 上线前安全评审 · Chat / Code**
```
Review my core application code before any real user touches it. Specifically check:
authentication and session handling, data exposure in API responses, input validation
and injection risks, and dependencies with known vulnerabilities. For each finding,
tell me whether it needs a fix now, and flag anything touching authentication, secrets,
or data handling for human review.
```

**2.6 上线前建立度量框架 · Chat**
```
For [product], help me define a measurement framework BEFORE launch: which metrics
actually matter, my activation criteria, and my retention benchmarks with Day-7 and
Day-30 targets. Then define what a FALSE POSITIVE looks like for my product (e.g.
signups without activation, revenue without retention). Finally, make the adversarial
case against my traction: what would a skeptic say about these numbers?
```

**2.7 用户反馈闭环自动化 · Cowork**
```
Run my MVP-stage feedback loop: draft outreach to my early user list, schedule feedback
sessions, design a structured intake process for bug reports and feature requests, and
write a weekly synthesis of what's come in. I'll review the synthesis first; then flag
any significant points I may have overlooked.
```

**2.8 是否该 pivot 的诊断 · Chat / Cowork**
```
I've completed [N ≥ 3] iteration cycles without meaningful movement toward my PMF
benchmarks. Here is my retention data, user feedback, and original problem hypothesis:
[attach]. Answer three questions:
1. Is there a segment in this data responding differently than the rest?
2. Is the gap between designed value and experienced value a positioning problem or a
   product problem?
3. What would have to be true for the current product to find genuine PMF — and is that
   scenario realistic given what I'm seeing?
```

---

## ③ Launch —— 把早期牵引力变成可复制的增长引擎

**3.1 技术债审计与排期 · Code → Chat**
```
Audit my MVP codebase and produce a prioritized list of structural weaknesses,
test-coverage gaps, and refactoring candidates. [Then:] Given this list [paste], sequence
the remediation work across my next sprints: what must be fixed before the next release,
what can be handled in parallel with feature work, and what is acceptable ongoing debt.
```

**3.2 审计并替代创始人注意力 · Cowork**
```
Run a structured audit of my current operational load: document every recurring task,
every decision that lands on my desk, and every workflow that only happens because I
personally remember to do it. Categorize each into: (a) can be fully automated, (b) needs
a human but not necessarily me, (c) genuinely requires founder judgment. For the automation
candidates, design the workflow logic: trigger, decision rules, output, and where it goes.
```

**3.3 安全与合规工作流 · Code → Chat**
```
Run a code-level review oriented to the frameworks my target market requires
([SOC 2 / GDPR / HIPAA / ...]). Surface both vulnerabilities and compliance gaps. [Then:]
From these findings [paste], produce two things: (1) a prioritized security remediation
sequence, and (2) a list of the documentation and controls I'll need to satisfy a
compliance review from a prospective enterprise buyer.
```

**3.4 搭建轻量产品管理系统 · Chat → Cowork**
```
Design a lightweight product-management operating system for my Launch-stage startup:
a defined sprint cadence, a minimum spec template (what a spec must include before Claude
Code touches a feature), a bug-triage decision tree, and a weekly metrics brief that pulls
from [my data sources]. Then set up the recurring operational elements — scheduling
ceremonies, routing bug reports, compiling the weekly metrics — to run on schedule without me.
```

---

## ④ Scale —— 建立系统性增长与可防御的护城河

**4.1 只有创始人该做的事 + 瓶颈地图 · Chat**
```
Build the list of things only I should be doing at the Scale stage (e.g. product narrative
decisions, board relationships, enterprise deals, founder-to-founder conversations). Then
produce a bottleneck map of my current operational layer: every workflow, decision, and
approval currently routed through me. Extrapolate what happens to each one if I'm unavailable
for a week — the ones that stall are where I'm still hands-on enough to derail progress.
```

**4.2 压力测试现有系统的可扩展性 · Chat / Cowork**
```
Map my current workflows [attach / describe], then tell me what happens to each one when
I'm unavailable for a week. For the workflows that stall, identify whether the handoff
criteria, escalation paths, or exception handling need tightening, and recommend fixes I
can push into my Claude Cowork automations.
```

**4.3 企业级基础设施差距分析 · Chat → Code + Cowork**
```
Here are three ideal enterprise accounts I'd love to sign: [list]. Produce a gap analysis:
what documentation, SLAs, and support infrastructure would each account's procurement team
expect to see before signing a multi-year contract, and where do I currently fall short?
Use the output to sequence the technical work (Claude Code) and documentation work (Claude Cowork).
```

**4.4 构建真正的 GTM 引擎 · Chat → Cowork**
```
Help me build foundational GTM resources from scratch for [product]: market segmentation,
messaging architecture, analyst-relations strategy, sales playbooks, and investor-facing
metrics narratives. For each audience (individual users, enterprise buyers, investors/analysts),
translate my product's value props into messaging that uses that audience's vocabulary and
evaluation standards.
```

**4.5 把领域知识变成护城河(边界用例测试)· Code**
```
Identify one edge case a generic competitor would definitely get wrong in [my vertical].
Build a dedicated test case for it, based on this real scenario I've seen: [scenario]. This
isn't a unit test — it encodes domain expertise. I'll add a new one each time a similar edge
case surfaces so the test suite becomes a map of my moat.
```

**4.6 把用户数据复利成优势(护城河叙事)· Chat**
```
Here is a summary of my product's interaction data: what I've collected, how long I've been
collecting it, and how users engage over time — [attach]. Identify the three highest-signal
behavioral patterns, and design a feedback loop that turns each into a systematic
model/product improvement. Then draft a one-page moat narrative: how my data flywheel works,
how long it's been spinning, and why a well-resourced competitor starting today couldn't
replicate it in under two years.
```

**4.7 创造工作流锁定(集成审计)· Chat → Code**
```
Build a workflow-integration audit for my top ten customers. For each: document the
automations they've built on my product, the integrations they depend on, the team workflows
that run through it, and my estimate of their switching cost. Then identify the patterns across
the group: which integration types create the deepest lock-in, and what I could build or enable
to deepen integration for customers currently at the surface.
```

---

## 贯穿全程的通用模式(任何阶段可复用)

- **结构化 devil's advocate**:`Now make the strongest case against this / try to refute it. Default to skepticism if uncertain.`
- **对称性检验**:每次给支持证据后,同时要求列反对证据,并追问哪边更符合数据。
- **"什么必须为真"**:对任何计划追问 `What would have to be true for this to work, and is that realistic?`
- **持久化上下文**:架构与决策落到 `CLAUDE.md` / scope doc / 会话日志,让每次新会话从共享认知开始。
