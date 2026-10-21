// SPDX-License-Identifier: Apache-2.0
// Generates connected tori under ignored _build; invokes real native CLI paths.
const fs = require("node:fs"),
  path = require("node:path"),
  cp = require("node:child_process"),
  os = require("node:os"),
  crypto = require("node:crypto"),
  assert = require("node:assert/strict");
const root = path.resolve(__dirname, ".."),
  dir = path.join(root, "_build/corpus"),
  reportDir = path.join(
    root,
    process.argv.includes("--ci")
      ? "_build/corpus/performance"
      : "examples/corpus/performance",
  );
const { stress } = require("./model-builders.cjs"),
  { build } = require("./corpus-cases.cjs");
const exe = build(),
  python = process.env.PYTHON || "python";
fs.mkdirSync(reportDir, { recursive: true });
const results = [];
const small = process.argv.includes("--ci");
const cases = small
  ? [["100k", 250, 200]]
  : [
      ["100k", 250, 200],
      ["500k", 500, 500],
      ["1m", 1000, 500],
    ];
for (const [name, n, m] of cases) {
  const relative = "_build/corpus/stress-" + name + ".stl",
    file = path.join(root, relative),
    faces = 2 * n * m;
  stress(file, n, m);
  assert.equal(fs.statSync(file).size, 84 + 50 * faces);
  const row = {
    file: relative,
    triangles: faces,
    expected_unique_vertices: n * m,
    expected_edge_records: 3 * faces,
    bytes: fs.statSync(file).size,
    sha256: crypto
      .createHash("sha256")
      .update(fs.readFileSync(file))
      .digest("hex"),
    runs: [],
  };
  for (const mode of ["stream-only", "bench"]) {
    const report = path.join(reportDir, name + "-" + mode + ".txt");
    const run = cp.spawnSync(
      python,
      [
        path.join(root, "scripts/measure-process.py"),
        report,
        "--",
        exe,
        relative,
        "--" + mode,
      ],
      { cwd: root, encoding: "utf8", timeout: 300000, maxBuffer: 3e6 },
    );
    if (run.error) throw run.error;
    assert.equal(run.status, 0, run.stdout + run.stderr);
    const measurement = JSON.parse(run.stdout.trim());
    const text = fs.readFileSync(report, "utf8");
    if (mode === "stream-only") {
      assert.match(
        text,
        new RegExp(
          `三角形 ${faces}；顶点表 ${n * m} 项；边记录 ${faces * 3} 项`,
        ),
      );
      assert.match(text, /残留 0 字节/);
    } else {
      assert.match(text, /计数一致（通过）/);
      assert.match(text, new RegExp(`三角形\\s+${faces}`));
    }
    row.runs.push({
      mode,
      command: "moon run --target native cmd/main " + relative + " --" + mode,
      ...measurement,
    });
    console.log(
      name +
        " " +
        mode +
        ": " +
        measurement.elapsed_ms +
        " ms, observed peak " +
        measurement.observed_peak_rss_bytes +
        " bytes",
    );
  }
  results.push(row);
}
if (small) {
  console.log(
    "CI 100k stress passed; recorded workstation results left unchanged.",
  );
  process.exit(0);
}
const summary = {
  platform: process.platform,
  architecture: process.arch,
  cpu: os.cpus()[0].model.trim(),
  logical_cpus: os.cpus().length,
  total_memory_bytes: os.totalmem(),
  moon: cp
    .execFileSync("moon", ["version", "--all"], { cwd: root, encoding: "utf8" })
    .trim(),
  node: process.version,
  measurement:
    "One cold child process per run; 10 ms OS peak-memory polling; elapsed includes process startup, excludes generation/build. Local observation only, not a performance guarantee. bench runs chunked, full and whole-buffer paths sequentially, so its process peak is not full-parser-only memory.",
  models: results,
};
fs.writeFileSync(
  path.join(reportDir, "summary.json"),
  JSON.stringify(summary, null, 2) + "\n",
);
const rows = results.map((r) => {
  const a = r.runs[0],
    b = r.runs[1],
    mem = (x) =>
      x.observed_peak_rss_bytes
        ? (x.observed_peak_rss_bytes / 1048576).toFixed(1)
        : "未测";
  return `| ${r.triangles.toLocaleString("en-US")} | ${r.expected_unique_vertices} / ${r.expected_edge_records} | ${a.elapsed_ms} / ${b.elapsed_ms} | ${mem(a)} / ${mem(b)} | [分块](examples/corpus/performance/${path.basename(r.file, ".stl").replace("stress-", "")}-stream-only.txt)、[交叉验证](examples/corpus/performance/${path.basename(r.file, ".stl").replace("stress-", "")}-bench.txt) |`;
});
const section =
  "<!-- stress-results:start -->\n## 大文件实测\n\n由独立参数化闭合圆环生成，半径 R=10、r=2 mm；面数精确为 `2×n×m`。这些是有共享顶点的连通网格，不是简单重复同一面。模型写到忽略目录，100k / 500k / 1m 文件分别约 5 / 25 / 50 MB。\n\n| 面数 | 顶点表 / 边记录 | 分块 / bench 整进程耗时 ms | 分块 / bench 观察峰值 MiB | 输出 |\n| --- | --- | --- | --- | --- |\n" +
  rows.join("\n") +
  "\n\n环境：" +
  summary.platform +
  " " +
  summary.architecture +
  "，" +
  summary.cpu +
  "，Native release；工具版本、输入 SHA-256 和完整命令见 [性能记录](examples/corpus/performance/summary.json)。时间包括进程启动，不含模型生成和编译。每项仅单次本机观察，没有预热、重复统计或跨项目排名。内存为每 10 ms 读取一次 OS 报告的进程历史峰值，退出间隙可能漏掉峰值，属于观察下界；不是 CLI 的字段估算。\n\n`--bench` 会顺序执行分块、全量与整块流式，并核对三角形、顶点、边界和非流形边计数；各路径工作量不同。bench 进程峰值不能当成纯全量路径的独立内存。`--stream-only` 的顶点表与边记录随规模增长，不能承诺固定总内存。CI 每次生成并验证 100k 的两个入口，不比较计时；500k/1m 用上述脚本手动复测。\n<!-- stress-results:end -->";
const docFile = path.join(root, "COMPARISON.md"),
  doc = fs.readFileSync(docFile, "utf8"),
  re = /<!-- stress-results:start -->[\s\S]*?<!-- stress-results:end -->/;
fs.writeFileSync(
  docFile,
  re.test(doc)
    ? doc.replace(re, () => section)
    : doc.trimEnd() + "\n\n" + section + "\n",
);
