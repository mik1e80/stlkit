# STLKit 验收交付说明

后续边界、许可与 CI 修订见 [顾问建议整改记录](advisor-remediation.md)。本页下文的 395 项测试和计时是第一批修订的历史证据；不能代替最新修订的复核结果。

## 版本与获批范围

| 项目 | 当前状态 |
| --- | --- |
| 已获批申报基线 | `mik1e80/stlkit@0.1.4` / `v0.1.4`；保留原核心承诺 |
| 基线源码 SHA | `f62486ecfed4a6222373edfb4dd00b86454f1377` |
| 最近已发布参考 | `mik1e80/stlkit@0.2.0` / `v0.2.0` |
| 0.2.0 源码 SHA | `3a98e234c5507bb2a4273917d12a4aafdaf22a2e` |
| 本批验收修订 | 未发布的工作区修改；不属于上述包或标签 |
| 本批最终 tag / SHA / 包 | 尚未冻结和发布，不能用旧 SHA 代替 |

本文件补充交付证据，不自动替代已获批的线上申报，也不证明组委会已接受版本变更。最终交付前须将真实的新版本、完整 SHA、包版本及对应 CI 链接补入本表；旧标签不移动。

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
