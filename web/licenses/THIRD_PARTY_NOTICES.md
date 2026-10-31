# 浏览器分发第三方声明

此目录说明网页实际分发的编译代码。模型在浏览器本地处理，不随网页分发测试模型。完整仓库中的模型和开发工具来源见 [仓库第三方声明](https://github.com/mik1e80/stlkit/blob/main/THIRD_PARTY_NOTICES.md)。

| 分发内容 | 来源 | 完整许可与声明 |
| --- | --- | --- |
| STLKit 自建代码 | [STLKit](https://github.com/mik1e80/stlkit) | [Apache-2.0](project.LICENSE) |
| MoonBit core 编译代码 | [moonbitlang/core](https://github.com/moonbitlang/core) | [Apache-2.0](moonbit-core.LICENSE)、[完整 NOTICE](moonbit-core.NOTICE) |
| hustcer/fzip 0.8.7 | [hustcer/fzip](https://github.com/hustcer/fzip) | [Apache-2.0](fzip.LICENSE) |
| Milky2018/xml 0.5.0 | [moonbit-community/xml-mbt](https://github.com/moonbit-community/xml-mbt) | [Apache-2.0](xml.LICENSE) |

构建脚本复制完整许可证和 MoonBit core 的 NOTICE，保留其中 fdlibm / musl 等上游来源、版权及免责声明。本页独立维护，不从仓库根声明直接复制，以上相对链接均指向本目录中实际随站点分发的文件。

测试模型（包括 CC0-1.0 和 BSD-2-Clause 文件）保存在 GitHub 源码仓库，来源、固定上游版本、哈希及完整条款分别见 [官方样例清单](https://github.com/mik1e80/stlkit/blob/main/examples/third-party-manifest.json)、[其他外部模型清单](https://github.com/mik1e80/stlkit/blob/main/examples/external/manifest.json) 和仓库声明；本页不将它们描述为浏览器代码依赖。
