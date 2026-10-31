# STLKit 验收交付说明

## 0.2.3 交付状态

2026-10-31 第二轮整改已发布。源码、GitHub Release、Mooncakes 和发布后安装分别核验；不代表组委会已作出最终验收结论。

| 项目 | 证据 |
| --- | --- |
| 固定源码 | `df3f5b573f0f0c72f37746f39ba5175e74e26299` / [v0.2.3](https://github.com/mik1e80/stlkit/tree/v0.2.3)，旧标签保留 |
| 语言 / 工具链 | MoonBit；本机 moonc 0.10.17+d971670cd，CI 0.10.18+6c83a7f62；验收最低 0.10.16，不声称实测该最低版本 |
| check / build / test | [固定源码两平台 CI](https://github.com/mik1e80/stlkit/actions/runs/41197025986) 成功；Linux 四后端各 427 / 427、全目标零警告、构建与格式检查；Windows 真实入口和许可 / 包检查通过 |
| Web | [公开部署](https://github.com/mik1e80/stlkit/actions/runs/41197025794) 成功，已检查 HTTPS 页面与新限额提示；编译产物 UI 回归覆盖逆序读取、失败、同文件重选和单次工作量 |
| 变异 | [四后端确定性变异](https://github.com/mik1e80/stlkit/actions/runs/41196900041) 各 1000 次，接受 252 / 拒绝 748 / 摘要 541334653 一致；其后仅文档 / Actions cache 改动 |
| 模型与压力 | 67 次读取、5 次修复重读、10 次厚度对照；Linux 10 万面全量 / 分块一致性通过。本机缺少 Python，没有本机压力新测值，50 万 / 100 万面历史计时不冒充本次结果 |
| 发布包 | [Mooncakes 0.2.3](https://mooncakes.io/docs/mik1e80/stlkit@0.2.3/) 发布返回 200 OK；[正式 Release](https://github.com/mik1e80/stlkit/releases/tag/v0.2.3) |
| 独立安装 | 本机干净项目及 [Linux / Windows 发布包矩阵](https://github.com/mik1e80/stlkit/actions/runs/41197315441) 各四后端通过，确认实际安装 0.2.3，并调用新增面积 / 最近点受检 API |
| 来源与许可 | 项目 Apache-2.0；17 个官方与 15 个外部条目 SHA-256，官方 Git Blob SHA-1，完整 CC0 / BSD 与浏览器许可检查通过；实际包内容和负向回归通过 |
| 维护状态 | Dependabot #5/#6/#7 已更新重测后合并；私密漏洞报告已启用。签名标签、不可变发布与分支 / 标签保护仍待长期维护，不标记为已完成 |

[第二轮逐项整改](round2-remediation.md) · [迁移和受检接口](checked-apis.md) · [0.2.3 发布说明](releases/0.2.3.md)。固定源码标签早于本次补证据文档提交，不移动标签。BVH、完整自交、非流形顶点、Worker / 取消仍未实现。

## 0.2.2 历史交付状态

2026-10-31 按参赛者提供的九项要求完成 0.2.2 工程交付；无需再次提交表格。本页记录实际源码、检查、发布与独立安装证据，不代表主办方已作出验收结论。

| 项目 | 状态 |
| --- | --- |
| GitHub | https://github.com/mik1e80/stlkit |
| 开发语言 / 许可 | MoonBit / Apache-2.0；第三方独立许可保留 |
| 工具链 | 验收最低 moonc 0.10.16；实际基线 0.10.17+d971670cd，本次 CI 验证 0.10.18+6c83a7f62 |
| 发布版本 / tag | [0.2.2 正式 Release](https://github.com/mik1e80/stlkit/releases/tag/v0.2.2) / v0.2.2，旧标签均保留 |
| 完整源码 SHA | `3a85bb4464d18dbc64a1cddd314724d5551fc206`，为固定的发布源码，不是后续证据文档提交 |
| check / build / 四后端 | [固定源码 CI](https://github.com/mik1e80/stlkit/actions/runs/41174322069) 成功；本机及 Linux Wasm / Wasm-GC / JS / Native 各 417 / 417，全目标零警告检查、构建与格式检查通过 |
| Windows / Pages | 同一源码 CI 的 Windows 检查、CLI、Quick Start、导出、路径和许可回归成功；[网页部署](https://github.com/mik1e80/stlkit/actions/runs/41174322050) 成功 |
| 独立变异 | [固定源码变异 CI](https://github.com/mik1e80/stlkit/actions/runs/41174322077) 成功，四后端各 1000 次摘要一致 |
| Mooncakes 0.2.2 | [公开包](https://mooncakes.io/docs/mik1e80/stlkit@0.2.2/)，发布返回 200 OK；干净项目实际下载并核对安装版本 |
| 独立 consumer | 本机干净目录四后端通过；[Linux / Windows 发布包矩阵](https://github.com/mik1e80/stlkit/actions/runs/41174578790) 两项任务均成功，每种系统四后端安装并调用受检校验 / 修复 / STL / SVG、面积加权采样及已有 API |
| 示例 | cube 12 面 / 体积 1 / 面积 6、缺面修复重读、JSON；quickstart-smoke 真实入口验证 |
| 模型 / 包内容 / 许可 | 67 次模型读取、5 组修复重读、10 组厚度对照通过；17 个官方及 15 个外部条目哈希、完整 BSD / CC0、浏览器许可链接校验通过；包清单保留必要许可与来源元数据，排除模型大文件与缓存 |

最终证据提交可以晚于源码 tag；此时明确区分固定的发布源码 SHA 和后续仅补证据的文档提交，不移动标签。发布后的工作流在 Linux / Windows 干净目录安装公开包；发布前 CI 不尝试安装尚不存在的新包。

[九项要求对照](acceptance-checklist.md) · [0.2.2 发布说明](releases/0.2.2.md) · [受检 API](checked-apis.md)。

## 历史证据说明

以下 395 项测试、版本表和计时保留第一批修订的原始状态，不是本次 0.2.2 的最终验收结果。后续边界修订见 [顾问建议整改记录](advisor-remediation.md)。

## 历史获批基线与首次修订

| 项目 | 当前状态 |
| --- | --- |
| 已获批申报基线 | `mik1e80/stlkit@0.1.4` / `v0.1.4`；保留原核心承诺 |
| 基线源码 SHA | `f62486ecfed4a6222373edfb4dd00b86454f1377` |
| 历史已发布参考 | `mik1e80/stlkit@0.2.0` / `v0.2.0` |
| 0.2.0 源码 SHA | `3a98e234c5507bb2a4273917d12a4aafdaf22a2e` |

旧申报核心承诺保留为核对基线；当前交付版本、完整 SHA 和 CI 见本页顶部。本文件不证明主办方已完成验收；旧标签不移动。

## 对照已获批承诺的修订

| 申报中的核心能力 | 已有基础及本批补正 | 可复核证据 |
| --- | --- | --- |
| 限定范围读取与格式拒绝 | 保留 0.1.4 的 OBJ / PLY / 3MF 严格读取；0.1.5 起增加资源限额 | 格式兼容性说明、格式负向回归、四后端测试 |
| 几何统计及质量属性 | 本批使用局部参考点、补偿求和及重心附近的二阶矩积分，修正平移后体积 / 惯量错误；增加必要数值复核 | `acceptance_regression_wbtest.mbt`、`scripts/acceptance-smoke.mbtx` |
| 修复后导出及重读复核 | 本批拒绝 Float32 溢出和新增退化 / 反向面；CLI 写盘前解析、写盘后重读，最终严格结果及 SVG 基于实际文件；网页修复报告和下载基于重读 STL | 真实 CLI 及网页回归 |
| 可直接使用的 CLI / 网页 | 本批保护输入路径，保留输出之间的冲突检查；增加厚度计算预算与明确提示 | 同路径 / 规范化别名 / 输出保留 / 预算超限回归 |
| 第三方来源与许可 | 保留固定来源、作者、哈希、修改说明及 CC0 / BSD-2-Clause 完整文本 | 模型语料许可及哈希检查 |

0.1.4 之后的资源限额、确定性变异测试、独立 consumer 验证，以及 0.2.0 的 JSON / 结构化错误 / IndexedMesh 均为后续实质工作。可在最终冻结后执行以下命令审查实际改动；不把提交数量当成工作质量的替代：

```sh
git log --oneline --since=2026-10-01
git diff --stat v0.1.4..HEAD
git status --short
git rev-parse HEAD
```

注意：`git diff v0.1.4..HEAD` 不包含未提交修改，本批仍需同时查看 `git diff` 和未跟踪的新文件。发布后应以最终固定 SHA 重跑检查，不能直接复用未发布工作区的结论。

## 复核命令与证据

本批新增模型均为项目自建 Apache-2.0 解析值模型，无新增网络下载。真实 CLI 回归生成的模型、JSON 及导出文件写在已忽略的 `_build/acceptance-smoke/`。

```sh
moon check --target all --deny-warn
moon fmt --check
moon build
moon test --target wasm --deny-warn
moon test --target wasm-gc --deny-warn
moon test --target js --deny-warn
moon test --target native --deny-warn
moon run scripts/acceptance-smoke.mbtx
moon run scripts/json-smoke.mbtx
node cmd/main/smoke.cjs
moon run scripts/build-web.mbtx
node web/smoke.cjs
python scripts/prepare-scan.py
node scripts/corpus-cases.cjs --check
```

获批基线为每后端 352 项，已发布 0.2.0 为每后端 385 项；本批工作区四后端各 **395 / 395** 通过。`moon check --target all --deny-warn`、构建、格式检查、脚本格式检查及公开接口生成通过；生成接口仅新增受检 STL 导出及质量属性数值检查两项 API。原有 CLI / 网页回归、20 组 JSON 真实进程案例、新增验收回归均通过；现有模型语料为 67 次读取、5 组修复后重读、10 组厚度对照通过，来源、完整许可证和哈希检查通过。已有审查案例亦已重跑，新增实际文件重读提示已更新到对应报告。

10 万面连通 STL 的本机 Native release 单次观察：默认 1000 样本因预算超限退出 1，约 64 ms 并提示 `--samples 200`；采用建议的 200 样本约 4.95 秒完成，1 样本约 1.66 秒。测试时有其他回归运行，不作为统计基准、吞吐承诺或算法加速倍率。预算拒绝与完成分析是不同结果；历史 30 秒观察窗口超时记录不改写。详见 [本批验证摘要](benchmarks/acceptance-maintenance.json)。

## 明确边界

- 质量属性数值检查只验证必要条件，不提供任意尺度 / 病态几何的误差界，也不证明没有自交。
- 原低层 `write_stl_binary` / `write_ply_binary` 继续是不做精度检查的编码器；推荐上层 `write_mesh` 或 `write_stl_binary_checked`。检查不保证 Float32 坐标完全相同或全部拓扑保真。
- 最新路径保护增加真实目标解析，识别符号链接和目录 junction；仍不识别硬链接别名，不防检查后的路径替换竞态，文件写入不承诺原子性。
- CLI 的 `面数 × 样本数` 上限为 20000000，超限拒绝并建议较小的 `--samples`；JSON 返回 `resource_limit`、退出 3，中文入口退出 1。网页自动降低预算并显示；这不保证总耗时，BVH / Worker / 取消功能仍在后续路线中。
- 最新补洞改为简单平面环耳切三角化，支持简单凹环；分支、自交、非平面或超预算洞拒绝。不将修订宣传为解决全部几何修复问题。

## 0.2.1 过渡发布记录

源码 d935f18c6f9dd3b1031d9928e4ba36f6b564ae28 / v0.2.1，[源码 CI](https://github.com/mik1e80/stlkit/actions/runs/41173680315) 通过，Mooncakes 发布返回 200 OK。随后的独立脚本启动因新注册表 async 0.22.7 引用旧 SDK 缺少的 core/async 而失败；未将它记为 consumer 通过，也未创建 0.2.1 GitHub Release。保留该包和标签，0.2.2 固定依赖后重新验证。
