# 第二轮整改与验证

对应 2026-10-31 提供的第二轮意见。候选版本 0.2.3，旧 0.2.2 包、标签和验收证据保留；本批正式发布和固定 SHA 待最终 CI / 独立安装后填写，未完成事项不标记为已交付。

| 审查项 | 本批实现 / 边界 |
| --- | --- |
| Web 重复解析与修复 | 新增 analyze_bundle / fix_bundle JSON 接口；分析一次解析，修复一次源解析、一次修复、一次受检导出、一次必要导出重读。报告、预览、下载共享同一结果；私有实际调用计数的每次差值可供回归核验 |
| 读取竞态与同文件重选 | 每个新请求增加代次，过时成功及失败不更新 UI；取得 File 对象后重置选择框。读取前和实际 ArrayBuffer 返回后都检查大小 |
| 浏览器内存预算 | 默认 16 MiB，硬上限 32 MiB / 50 万面；较大文件提示 CLI。双端强制限额，未宣称测得所有设备上的安全内存上限；仍在主线程，没有 Worker/取消 |
| 极端法线与面积 | 两条边分别缩放，面积按二进制指数恢复；正面积不可表示或检测到缩放信息丢失时 area_checked 返回 Err。普通 area 仍受 Double 范围约束。没有任意病态几何误差界 |
| 最近点 | nearest_point_checked 空网格为 Ok(None)，非有限查询/顶点、不可表示结果或检测到归一化损失为 Err；旧接口用 Infinity 哨兵，保留原签名 |
| 三角化成本 | 每个多边形固定 2000000 次边对 / 候选 / 阻挡检查预算，超限 resource_limit；阻挡成立即停止候选检查。最坏复杂度未被宣传为已变成 O(n²) |
| 补丁相交 | 明确只验证环本身，不验证补丁与其余非邻接面的几何相交；完整自交诊断仍待后续实现 |
| 3MF ZIP | 依赖已有硬条目预算和解压防护；项目的更严格条目数检查仍在 unzip_list 返回之后，未虚构为底层首个分配前检查 |
| SVG 失败及 paint | CLI 使用受检接口，失败保留既有目标文件且不报导出成功；Web 提供可见错误原因。stroke 为十六进制颜色及有限安全名称允许列表，url()/变量/其他表达式拒绝 |
| 来源和完整许可 | 真正计算 SHA1("blob " + 字节数 + NUL + 原字节)，与 17 个上游 blob 比较；并校验 SHA-256、40 位小写十六进制格式。外部许可只允许既已审查的 CC0-1.0 / BSD-2-Clause，完整法律文本以已批准 SHA-256 固定 |
| 实际包内容 | package-smoke 调用 moon package --list，在 Linux / Windows 路径格式下核对完整许可/来源清单，拒绝模型与缓存；负向回归覆盖缺许可、混入模型、错误 blob 和未审查许可 |
| 文档 / Actions / 供应链 | 同步 CONTRIBUTING、roadmap、历史测试数和 Mooncakes 未附带模型的 GitHub 链接。Dependabot 分支需基于本批 main 更新并重跑后处理；签名、不可变发布、分支/标签保护与私密报告的实际核查另记，未操作不得写已启用 |

## 已建立的回归

- MoonBit 测试：1e-200 / 1e-100 / 1e100 / 1e200、不同边尺度、跨度溢出、缩放信息丢失、空/非法最近点、退化线段、三角化预算与不安全 paint。
- Web 包测试：实际工作量差值、导出 STL 重读及报告一致、预览单独不可用、硬限额。
- 既有网页 UI 回归扩展：A/B 逆序完成、过时读取失败、拒绝超大文件前不读文件、实际 buffer 大小、同文件重选，以及强制旧拆分接口不可调用时仍完成分析/修复/阈值更新。
- scripts/round2-smoke.mbtx：实际 Native CLI 的 SVG 失败退出、已有输出字节保留，以及来源/打包检查的真实负向进程。

## 验证命令

```sh
moon fmt --check
moon info
moon check --target all --deny-warn
moon test --target wasm --deny-warn
moon test --target wasm-gc --deny-warn
moon test --target js --deny-warn
moon test --target native --deny-warn
moon run scripts/check-third-party.mbtx
moon run scripts/package-smoke.mbtx
moon run scripts/round2-smoke.mbtx
moon run scripts/build-web.mbtx
node web/smoke.cjs
node scripts/corpus-cases.cjs --check
```

本机 moonc 0.10.17+d971670cd：全目标零警告检查、构建、格式检查、四后端各 427 / 427，全部入口回归与现有语料 67 次读取 / 5 次修复 / 10 次厚度对照通过。确定性变异每后端 1000 次，接受 252、拒绝 748、摘要 541334653 一致。

本机没有 Python，压力脚本未运行成功，由 Linux CI 补验；不以历史压力数据替代本批结果。浏览器工具不允许本地 file://，未绕过访问限制；实际编译产物及 app 的交互由 Node UI 回归验证，公开 HTTPS 部署后的页面另行复核，未测浏览器峰值内存。
