# 九项验收要求与证据

依据参赛者提供的本期验收指南：已审核通过者无需再交表格，开发内容上传 GitHub。这里是工程自查，不代表组委会已作出验收结论；不将八月技能附带的不同期次规则替换本次九条要求。

2026-10-31 已完成 0.2.3 第二轮整改、正式发布与独立安装，固定源码 `df3f5b573f0f0c72f37746f39ba5175e74e26299`。四后端各 427 项，Linux / Windows 源码 CI 和发布包四后端矩阵通过；现有模型语料、Linux 10 万面压力一致性、来源许可与实际包清单通过。完整链接见交付说明。此前 0.2.2 证据保留为历史，不替代新版本结果。

| 要求 | 对应实现与复核方法 |
| --- | --- |
| 1. MoonBit 为主，moonc ≥ 0.10.16 | 根目录、CLI 与网页的 .mbt 核心；check-toolchain 精确核对已验证的 0.10.17 / 0.10.18，不声称实测 0.10.16 |
| 2. 公开 GitHub、提交清晰 | [仓库](https://github.com/mik1e80/stlkit)、[提交记录](https://github.com/mik1e80/stlkit/commits/main)；固定 tag / 完整 SHA 见交付说明，不移动旧标签 |
| 3. 结构与声明的核心功能 | [接口文档](../README.mbt.md)、[格式子集](format-compatibility.md)、[受检 API](checked-apis.md)；未完成功能留在 roadmap |
| 4. README 可复现 | 版本化安装命令、工具链、CLI 示例、库示例与预期几何结果；Quick Start 真实进程复核 |
| 5. check / build / test CI | [工作流](../.github/workflows/ci.yml)：全目标检查、构建、四后端、Linux / Windows 入口与模型语料；实际结果以对应 SHA 为准 |
| 6. 可运行示例 | cube.obj、broken.stl、JSON 命令；README.mbt.md 的无文件依赖库示例参与测试 |
| 7. 核心路径测试 | 格式正反例、解析值、修复、JSON、SVG、CLI / Web、67 次模型读取、5 组修复重读、10 组厚度对照与独立变异测试；历史数量不冒充新版本结果 |
| 8. Mooncakes 发布 | [0.2.3 包](https://mooncakes.io/docs/mik1e80/stlkit@0.2.3/)；发布后干净目录安装并调用新增 API，Release consumer 覆盖 Linux / Windows 四后端 |
| 9. OSI 许可证及第三方要求 | 项目 Apache-2.0；完整 [LICENSE](../LICENSE)、[第三方声明](../THIRD_PARTY_NOTICES.md)、固定模型清单与 SHA-256；check-third-party 校验实际附件 |

每一项的最终状态、源码 SHA、CI 链接、包与独立安装结果统一见 [验收交付说明](acceptance-delivery.md)。版本号已修改、页面链接已写入或 tag 存在，本身都不证明包已发布和安装通过。

BVH、通用自相交、完整非流形顶点、MeshDocument、3MF 全部材料与 Web Worker / 取消是后续能力，不是本次声明的交付项。硬链接与文件写入竞态、采样漏检及病态数值限制继续公开。
