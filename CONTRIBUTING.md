# 参与开发

先阅读 [格式支持范围](docs/format-compatibility.md)、[资源预算](docs/resource-limits.md) 和 [路线图](docs/roadmap.md)。缺陷报告请给出版本、后端、复现命令、实际/预期结果及最小输入；分享第三方模型前确认许可，并附作者、固定来源、完整许可、修改说明和哈希。

修改解析器时，先加入可重现的正常/异常输入测试。可自行生成的小模型优先使用自建数据，采用 Apache-2.0；不要把没有许可的下载文件加入仓库。新能力同时完成代码、测试和范围文档，不扩大兼容性声明。

```sh
moon update
moon fmt --check
moon fmt scripts/fuzz.mbtx scripts/consumer-smoke.mbtx scripts/limits-smoke.mbtx --check
moon check --target all --deny-warn
moon test --target wasm
moon test --target wasm-gc
moon test --target js
moon test --target native
moon run scripts/limits-smoke.mbtx
moon run scripts/fuzz.mbtx all 1000
```

完整模型、真实 CLI、100k 和网页回归命令见 CI。发布前在干净目录验证真实 Mooncakes 包：`moon run scripts/consumer-smoke.mbtx 0.1.5`；工作区测试通过不代表发布包安装成功。自动化新增脚本使用 `.mbtx`，既有外部工具脚本可继续维护；生成网页后检查页面功能及许可证随附情况。
