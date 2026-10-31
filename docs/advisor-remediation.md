# 顾问建议整改记录

本页保留 2026-10-31 边界与许可整改的实现记录；这些代码现归入 0.2.2，实际冻结、发布与独立安装状态统一见 [验收交付说明](acceptance-delivery.md)。旧标签保持不动，获批范围基线仍为 0.1.4；依据本次提供的验收指南，无需重交报名表。

| 建议 | 本批实现 | 保留边界 |
| --- | --- | --- |
| 输出覆盖输入 | 词法路径与 realpath 双重比较，解析新输出的最近已存在父目录 | 硬链接、检查后路径替换竞态、原子写入未解决 |
| 非法焊接容差 | validate_checked / repair_checked 拒绝非有限、负值；零表示精确坐标 | 旧 repair 失败返回原网格和零修改计数，需区分原因用受检接口 |
| 大小尺度数值 | hypot 稳定范数、缩放归一化、局部缩放 PCA；前批已修正局部质量积分 | 不承诺任意病态尺度误差界或无自交 |
| 厚度查询 | 从表面查询且排除来源面；新增固定 seed 面积加权采样 | 原接口保持面索引采样；有限采样和射线阈值仍可能漏薄处 |
| 安全补洞 | 建立邻接、限制预算、检查简单平面闭环并耳切三角化 | 不执行复杂拓扑修复或消除自交；拒绝时不生成伪修复结果 |
| SVG | 属性转义、有限参数、最多 20000 面预览并标示抽样、输出大小检查 | 不是分析面数限制；大小检查不等于进程内存硬上限 |
| 格式边界 | 拒绝 OBJ 不支持几何；PLY 重复属性/别名、64 KiB header；3MF 唯一有序容器与变换回归 | 固定 header 限额尚非可配置；不宣称完整格式认证 |
| 第三方许可 | 17 个官方模型固定内容锚点、原路径与 SHA-256；15 个既有外部清单保留；完整 BSD / CC0 与浏览器许可证链接校验 | 未知许可网络模型不收录；没有臆造最初获取时间 |
| CI / 安全说明 | 固定 Actions SHA、contents:read、Dependabot、Windows 验证、编译器版本检查、安全维护版本表 | 远程私密报告、tag 保护及不可变 Release 设置未核验或修改 |

3MF 镜像按 Core 1.3 §3.3 消费者规则调整三角形绕向，保持输入有符号体积。真实 Cura rotated-group 样例因此更新原始体积贡献快照：57262.581 → 72720.115，文件 SHA 不变。它原本就含退化、非流形及方向问题，前后均不作为可信实体体积；解析值镜像模型另有独立回归，不能把此快照当数学真值。

17 个官方文件与上游提交 `665e20dc4d7777fd4c9702bca86a2d4028440337` 内容相同；本次通过 Git blob 和 SHA-256 核验，未记录原始获取日期。见 [官方模型清单](../examples/third-party-manifest.json)、[外部清单](../examples/external/manifest.json) 和 [完整许可声明](../THIRD_PARTY_NOTICES.md)。规范仅作链接及自行描述，不重分发未知许可 PDF。

## 复核

这是发布前记录：本机四后端各 416 / 416；0.2.2 最终各 417 / 417。第二轮结果见 [第二轮整改](round2-remediation.md)。格式及独立脚本格式、全目标零警告检查、构建与公开接口生成通过。CLI 参数、资源限额、JSON 协议、实际文件重读、路径别名与修复拒绝回归通过；网页重建及回归通过。现有模型语料 **67 次读取、5 组修复后重读、10 组厚度对照** 通过，17 个官方及 15 个外部来源条目的 SHA-256 / 完整许可检查通过。

本机额外变异命令未获执行许可，未把它记为本机通过。随后 GitHub 上 [c278311 的独立变异 CI](https://github.com/mik1e80/stlkit/actions/runs/41168848521) 在编译器 0.10.18 上通过四后端各 1000 次：accepted=252、rejected=748、digest=541334653，一致。已有历史报告保留原版本和日期。`moon package --list` 已执行，核对公开接口后新增受检修复、验证、SVG、面积加权采样及 RepairLimits，旧签名保留。

Windows 干净环境还暴露了旧 CLI 测试的跨盘符问题：系统临时目录在 C:，checkout 在 D:，path.relative 返回绝对路径，原测试再加 ./ 得到非法路径。该相对别名案例迁到 MoonBit boundary-smoke 的同卷夹具中，继续验证写入前拒绝及原字节保留；没有放宽产品路径保护。

```sh
moon fmt --check
moon check --target all --deny-warn
moon test --target wasm --deny-warn
moon test --target wasm-gc --deny-warn
moon test --target js --deny-warn
moon test --target native --deny-warn
moon run scripts/acceptance-smoke.mbtx
moon run scripts/boundary-smoke.mbtx
moon run scripts/check-third-party.mbtx
moon run scripts/check-toolchain.mbtx
moon run scripts/json-smoke.mbtx
moon run scripts/build-web.mbtx
node web/smoke.cjs
node scripts/corpus-cases.cjs --check
moon package --list
```

本机目录链接别名已覆盖，Windows 文件符号链接因权限不足明确跳过，交由具备权限的 Linux CI 验证；不能把跳过记为通过。工具链仍通过官方 latest 安装器下载，再核对精确编译器白名单：本机 `v0.10.17+d971670cd`，远程安装器当前返回 `v0.10.18+6c83a7f62`。后者必须通过完整 CI 后才能记作已验证；不接受开放的最低版本判断。未取得经验证可下载的固定历史 archive，因此尚非完整可复现安装，其他版本漂移会使 CI 失败而非悄悄通过。

BVH、通用自相交、非流形顶点、完整模型属性层、Web Worker 与取消任务仍在后续路线，不标记为已完成。
