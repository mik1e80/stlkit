// SPDX-License-Identifier: Apache-2.0
// Offline integration tests against the real CLI, analytic oracles and recorded boundaries.
const fs = require("node:fs"),
  path = require("node:path"),
  cp = require("node:child_process"),
  crypto = require("node:crypto"),
  assert = require("node:assert/strict");
const root = path.resolve(__dirname, ".."),
  output = path.join(root, "examples/corpus/reports"),
  tmp = path.join(root, "_build/corpus");
const hash = (b) => crypto.createHash("sha256").update(b).digest("hex");
function build() {
  const r = cp.spawnSync(
    "moon",
    ["build", "--target", "native", "--release", "cmd/main"],
    { cwd: root, encoding: "utf8", timeout: 180000, maxBuffer: 3e6 },
  );
  if (r.error) throw r.error;
  assert.equal(r.status, 0, r.stdout + r.stderr);
  return (
    ["main.exe", "main"]
      .map((n) => path.join(root, "_build/native/release/build/cmd/main", n))
      .find(fs.existsSync) || assert.fail("Native CLI not found")
  );
}
function metrics(text) {
  const get = (re) => text.match(re)?.[1];
  return {
    triangles: Number(get(/三角形\s+(\d+) 个/)),
    vertices: Number(get(/去重后 (\d+) 个/)),
    volume: Number(get(/(?:体积|有符号贡献绝对值)\s+([\d.e+-]+)/)),
    area: Number(get(/表面积\s+([\d.e+-]+)/)),
    parts: Number(get(/零件\s+(\d+) 个/)),
    boundary: Number(get(/有 (\d+) 条边界边/) || 0),
    nonmanifold: Number(get(/有 (\d+) 条非流形边/) || 0),
    degenerate: Number(get(/有 (\d+) 个退化面/) || 0),
    mass: !/重心\s+未评估/.test(text),
    obb: get(/定向包围盒 ([^\r\n]+) mm/),
    sample_min_mm: get(/采样最小厚度 ([\d.e+-]+) mm/)
      ? Number(get(/采样最小厚度 ([\d.e+-]+) mm/))
      : null,
  };
}
function near(actual, expected, tolerance = 0.0015) {
  assert(Number.isFinite(actual));
  assert(
    Math.abs(actual - expected) <= tolerance,
    `${actual} != ${expected} (+/-${tolerance})`,
  );
}
function main() {
  const update = process.argv.includes("--update");
  fs.mkdirSync(output, { recursive: true });
  fs.mkdirSync(tmp, { recursive: true });
  require("./model-builders.cjs").generateSmall(root);
  const manifest = JSON.parse(
    fs.readFileSync(path.join(root, "examples/external/manifest.json")),
  );
  for (const f of manifest.files) {
    assert(f.license && f.author && f.source && f.changes);
    assert.equal(
      hash(fs.readFileSync(path.join(root, f.file))),
      f.sha256,
      f.file + " source integrity",
    );
  }
  const exe = build(),
    results = [],
    reports = new Map();
  function run(file, extra = [], status = 0, suffix = "") {
    assert(fs.existsSync(path.join(root, file)), file);
    const args = [
      file,
      ...(extra.includes("--samples") ? [] : ["--samples", "1"]),
      ...(extra.includes("--min-thickness") ? [] : ["--min-thickness", "0"]),
      ...extra,
    ];
    const r = cp.spawnSync(exe, args, {
      cwd: root,
      encoding: "utf8",
      timeout: 180000,
      maxBuffer: 4e6,
    });
    if (r.error) throw r.error;
    assert.equal(r.status, status, file + "\n" + r.stdout + r.stderr);
    const text = (r.stdout + r.stderr).replace(/\r\n/g, "\n");
    const report =
      file.replace(/^examples\//, "").replaceAll("/", "_") + suffix + ".txt";
    reports.set(report, text);
    return {
      file,
      report,
      exit: r.status,
      command: "moon run --target native cmd/main " + args.join(" "),
      ...(status === 0
        ? metrics(text)
        : {
            error:
              text.split("\n").find((l) => l.startsWith("错误：")) ||
              text.trim(),
          }),
      text,
    };
  }
  function check(file, e, note, license = "Apache-2.0", group = "analytic") {
    const r = run(file, [], e.reject ? 1 : 0);
    if (e.reject) {
      assert.match(r.error, new RegExp(e.reject));
    } else {
      for (const key of [
        "triangles",
        "vertices",
        "parts",
        "boundary",
        "nonmanifold",
        "degenerate",
        "mass",
      ])
        if (e[key] !== undefined)
          assert.equal(r[key], e[key], file + " " + key);
      for (const key of ["volume", "area"])
        if (e[key] !== undefined) near(r[key], e[key]);
      if (e.obb) {
        const size = r.obb.split(" × ").map(Number);
        e.obb.forEach((v, i) => near(size[i], v, 0.003));
      }
    }
    results.push({ ...r, text: undefined, license, group, feedback: note });
    return r;
  }
  const c = "examples/corpus/";
  for (const file of [
    "examples/cube.stl",
    "examples/cube.obj",
    c + "cube-1mm.ply",
    c + "cube-1mm.3mf",
  ])
    check(
      file,
      { triangles: 12, volume: 1, area: 6, parts: 1, mass: true },
      "12 面，体积 1、面积 6；四格式数值一致",
    );
  check(
    c + "box-2x3x4.stl",
    { triangles: 12, volume: 24, area: 52, mass: true },
    "解析值 24 / 52 符合",
  );
  check(
    c + "tetrahedron-unit.stl",
    { triangles: 4, volume: 1 / 6, area: 1.5 + Math.sqrt(3) / 2, mass: true },
    "解析体积 1/6、面积 (3+√3)/2 符合",
  );
  check(
    c + "octahedron-unit.stl",
    { triangles: 8, volume: 4 / 3, area: 4 * Math.sqrt(3), mass: true },
    "解析体积 4/3、面积 4√3 符合",
  );
  check(
    c + "rotated-box-2x3x4.stl",
    { volume: 24, area: 52, obb: [4, 3, 2] },
    "旋转后 AABB 改变，PCA OBB 约 4×3×2",
  );
  const square = check(
    c + "square-prism-2x2x4.stl",
    { volume: 16, area: 40 },
    "重复特征值：OBB 有效且无零轴；不要求恢复唯一旋转方向",
  );
  assert(
    square.obb
      .split(" × ")
      .map(Number)
      .every((n) => n >= 1.99),
  );
  check(
    c + "hollow-box-10-8.obj",
    { triangles: 24, parts: 2, volume: 488, area: 984, mass: false },
    "两壳层、内壳负体积；潜在嵌套，质量属性暂停",
  );
  const inside = check(
    c + "inside-out-cube.obj",
    { triangles: 12, mass: false },
    "检测到一个负体积分量，暂停质量属性",
  );
  assert.match(inside.text, /体积为负/);
  check(
    c + "duplicate-face.stl",
    { triangles: 13, nonmanifold: 3 },
    "重复面导致 3 条多重边；修复删除 1 面",
  );
  check(
    c + "non-manifold-edge.stl",
    { triangles: 3, nonmanifold: 1, boundary: 6, mass: false },
    "三面共边，识别 1 条非流形边",
  );
  for (const f of ["non-manifold-vertex.obj", "vertex-touching-cubes.obj"])
    check(
      c + f,
      { parts: 2, vertices: 15, nonmanifold: 0, boundary: 0, mass: false },
      "共享顶点仍为两个共享边分量；包围盒提示，未实现顶点流形判定",
    );
  check(
    c + "two-independent-holes.stl",
    { triangles: 10, boundary: 6, mass: false },
    "两处独立三角洞；修复新增 2 面，边界 6→0",
  );
  check(
    c + "self-intersection.obj",
    { parts: 2, nonmanifold: 0, boundary: 0, mass: false },
    "仅包围盒重叠提示，不能据此声称精确检测自交",
  );
  check(
    c + "concave-l-prism.obj",
    { triangles: 20, volume: 10, area: 34, mass: true },
    "自建 L 形凹多边形面，耳切三角化符合解析值",
  );
  for (const [name, t] of [
    ["0.05", 0.05],
    ["0.40", 0.4],
    ["0.80", 0.8],
  ])
    check(
      c + "slab-" + name + "mm.stl",
      { volume: 100 * t, area: 200 + 40 * t, mass: true },
      "均匀薄板；固定预算采样结果见壁厚表",
    );
  check(
    c + "wedge-variable-thickness.stl",
    { volume: 52.5 },
    "竖向高度 0.05→1；射线首命中距离随端面/侧面采样改变，不能等同竖向高度",
  );
  check(
    c + "hollow-tube-wall-0.40mm.stl",
    { triangles: 1024, boundary: 0, nonmanifold: 0, mass: true },
    "128 段闭合空心管；离散曲面采样约 0.40 mm",
  );
  // Existing corpus: count snapshots preserve regression behavior, not independent geometric proof.
  const old = [
    ["ascii-packed.ply", 2, "完整解析跨记录空白；开放方形，质量属性暂停"],
    ["box.3mf", 12, "官方长方体，10×20×30，体积 6000"],
    ["broken.stl", 11, "开放三角洞，3 条边界边"],
    ["flipped.stl", 12, "局部绕向冲突，暂停质量属性"],
    ["degenerate-closed.obj", 12, "边计数闭合仍有退化面，暂停质量属性"],
    ["long-header.stl", 12, "长 ASCII 头仍识别为 STL"],
    ["obj-stl-keywords.obj", 12, "关键词不误识别为 STL"],
    ["torus.obj", 2304, "曲面离散模型；与 STL 对照"],
    ["torus.stl", 2304, "曲面离散模型；与 OBJ 对照"],
    ["torus.3mf", 2200, "官方圆环几何读取"],
    ["multiple_cylinders.3mf", 528, "六个 build 实例，按变换读取"],
    ["cube_gears.3mf", 25692, "报告退化/拓扑风险；不据此断言上游模型有错"],
    ["review/cubes-1.stl", 12, "分块表项增长基线"],
    ["review/cubes-16.stl", 192, "16 个分离立方体"],
    ["review/cubes-64.stl", 768, "64 个分离立方体"],
    ["review/opposite-parts.obj", 24, "总体积 +7 掩盖 +8 / −1 两分量"],
    ["review/opposite-parts-fixed.stl", 24, "修复后独立分量均朝外，总体积 9"],
    [
      "review/sampling-blindspot.obj",
      3084,
      "确定性面顺序反例；1000 / 全面预算另行复核",
    ],
  ];
  for (const [file, triangles, note] of old) {
    const license = file.endsWith(".3mf") ? "BSD-2-Clause" : "Apache-2.0";
    const e = { triangles };
    if (file === "box.3mf")
      Object.assign(e, { volume: 6000, area: 2200, mass: true });
    if (file === "broken.stl") Object.assign(e, { boundary: 3, mass: false });
    if (file === "flipped.stl" || file === "degenerate-closed.obj")
      e.mass = false;
    if (file === "multiple_cylinders.3mf") e.parts = 6;
    check("examples/" + file, e, note, license, "existing");
  }
  for (const [file, pattern] of [
    ["missing-format.ply", "缺少 format"],
    ["missing-z.ply", "缺少.*z"],
    ["nonfinite-rejected.obj", "有限|NaN|nan|数值"],
    ["ascii-extra-values.ply", "多余|尾部"],
  ])
    check(
      "examples/" + file,
      { reject: pattern },
      "坏输入按预期拒绝；属于成功的负向回归",
      "Apache-2.0",
      "existing",
    );
  for (const name of fs
    .readdirSync(path.join(root, "examples/conformance"))
    .filter((n) => n.endsWith(".3mf"))
    .sort()) {
    const triangles =
      name.includes("MultipleItemsTransform") || name.includes("Components")
        ? 60
        : name.includes("ExplicitSupport")
          ? 484
          : name.includes("MultiObjects_")
            ? 24
            : 12;
    check(
      "examples/conformance/" + name,
      { triangles },
      "声明范围内几何读取成功；未验证材质/支撑/完整 3MF 一致性",
      "BSD-2-Clause",
      "existing",
    );
  }
  const external = [
    [
      "bracket.stl",
      8060,
      "CC0-1.0",
      "支架实测报告 18 个退化面、2 个零件；质量属性暂停",
    ],
    ["gear.stl", 284, "CC0-1.0", "复杂轮廓齿轮读取成功"],
    [
      "concave-cad.obj",
      28,
      "CC0-1.0",
      "U 形 CAD 凹八边形面，体积 2750、面积 2250",
    ],
    ["heart.stl", 33576, "CC0-1.0", "有机曲面读取成功；未检验精确自遮挡/自交"],
    [
      "rotated-group.3mf",
      40,
      "CC0-1.0",
      "4 个共享边零件；报告 3 条非流形边及 6 个退化面",
    ],
    [
      "cura-4.2-project.3mf",
      null,
      "CC0-1.0",
      "Cura 4.2 工程几何读取；不验证切片配置",
    ],
    [
      "kinect-scan.3mf",
      282544,
      "BSD-2-Clause",
      "141249 顶点扫描模型读取成功；材料不进入 Mesh",
    ],
  ];
  for (const [name, n, license, note] of external)
    check(
      "examples/external/" + name,
      n ? { triangles: n } : {},
      note,
      license,
      "external",
    );
  check(
    "examples/external/cura-4.5-project.3mf",
    { reject: "build.*没有列任何对象" },
    "标准 build 为空，当前拒绝；不支持完整 Cura 工程恢复",
    "CC0-1.0",
    "external",
  );
  const scan = check(
    "_build/corpus/kinect-scan.ply",
    { triangles: 282544, vertices: 141249 },
    "同一 3MF 的独立几何转换；非独立扫描源；材料未转换",
    "BSD-2-Clause",
    "external",
  );
  const original = results.find(
    (r) => r.file === "examples/external/kinect-scan.3mf",
  );
  near(scan.volume, original.volume, 0.002);
  near(scan.area, original.area, 0.002);
  const torusObj = results.find((r) => r.file === "examples/torus.obj"),
    torusStl = results.find((r) => r.file === "examples/torus.stl");
  near(torusObj.volume, torusStl.volume);
  near(torusObj.area, torusStl.area);
  const repaired = [];
  for (const [file, added, removed] of [
    [c + "two-independent-holes.stl", 2, 0],
    [c + "duplicate-face.stl", 0, 1],
    ["examples/broken.stl", 1, 0],
    ["examples/flipped.stl", 0, 0],
    [c + "inside-out-cube.obj", 0, 0],
  ]) {
    const target = "_build/corpus/" + path.basename(file) + ".fixed.stl";
    const fix = run(file, ["--fix", target], 0, ".repair");
    if (added)
      assert.match(fix.text, new RegExp("补洞：新增 " + added + " 个"));
    if (removed)
      assert.match(fix.text, new RegExp("删掉 " + removed + " 个重复"));
    const after = run(target, ["--strict"], 0, ".recheck");
    assert.equal(after.triangles, 12);
    assert.equal(after.boundary, 0);
    assert.equal(after.nonmanifold, 0);
    assert(after.mass);
    repaired.push({
      file,
      after_triangles: after.triangles,
      after_boundary: after.boundary,
      added,
      removed,
      report: fix.report,
    });
  }
  const thickness = [];
  for (const name of [
    "slab-0.05mm.stl",
    "slab-0.40mm.stl",
    "slab-0.80mm.stl",
    "wedge-variable-thickness.stl",
    "hollow-tube-wall-0.40mm.stl",
  ])
    for (const budget of [1000, 4096]) {
      const r = run(
        c + name,
        ["--samples", String(budget)],
        0,
        ".samples-" + budget,
      );
      assert(r.sample_min_mm > 0);
      if (name.startsWith("slab-"))
        near(r.sample_min_mm, Number(name.match(/slab-([\d.]+)mm/)[1]), 0.002);
      if (name.startsWith("hollow-tube")) near(r.sample_min_mm, 0.4, 0.003);
      thickness.push({
        file: c + name,
        budget,
        threshold_mm: 0,
        unit: "mm",
        weld_tolerance: 1e-6,
        inset_policy: "library scale-dependent probe_inset; see thickness.mbt",
        sample_min_mm: r.sample_min_mm,
        hits: Number(r.text.match(/命中 (\d+)\//)?.[1]),
        report: r.report,
      });
    }
  const all = new Set();
  function walk(dir) {
    for (const e of fs.readdirSync(path.join(root, dir), {
      withFileTypes: true,
    })) {
      const f = dir + "/" + e.name;
      if (e.isDirectory()) {
        if (
          e.name !== "source" &&
          e.name !== "licenses" &&
          e.name !== "reports"
        )
          walk(f);
      } else if (/\.(stl|obj|ply|3mf)$/.test(e.name)) all.add(f);
    }
  }
  walk("examples");
  for (const f of all)
    assert(
      results.some((r) => r.file === f),
      "Model not tested: " + f,
    );
  assert.equal(
    all.size,
    results.filter((r) => !r.file.startsWith("_build/")).length,
  );
  for (const r of results) {
    const b = fs.readFileSync(path.join(root, r.file));
    const textFile =
      r.file.endsWith(".obj") ||
      (r.file.endsWith(".stl") && b.subarray(0, 5).toString() === "solid") ||
      (r.file.endsWith(".ply") &&
        b.subarray(0, 100).toString().includes("format ascii"));
    r.sha256 = hash(
      textFile ? Buffer.from(b.toString("utf8").replace(/\r\n/g, "\n")) : b,
    );
    r.hash_scope = textFile ? "LF-normalized text" : "file bytes";
  }
  const summary = {
    scope:
      "Analytic formulas + finite CLI regression snapshots; no complete format, self-intersection or printability certification.",
    settings: {
      target: "native release CLI",
      samples: 1,
      min_thickness_mm: 0,
      weld_tolerance: 1e-6,
    },
    models: results,
    repairs: repaired,
    thickness,
  };
  // Compare structured numeric fields with display-rounding tolerance across toolchains.
  const summaryFile = path.join(output, "summary.json");
  if (update)
    fs.writeFileSync(summaryFile, JSON.stringify(summary, null, 2) + "\n");
  else {
    const oldSummary = JSON.parse(fs.readFileSync(summaryFile));
    assert.equal(oldSummary.models.length, results.length);
    for (let i = 0; i < results.length; i++) {
      const a = results[i],
        b = oldSummary.models[i];
      for (const k of [
        "file",
        "exit",
        "triangles",
        "vertices",
        "parts",
        "boundary",
        "nonmanifold",
        "degenerate",
        "mass",
        "sha256",
      ])
        assert.equal(a[k], b[k], a.file + " snapshot " + k);
      for (const k of ["volume", "area"])
        if (a[k] !== undefined) near(a[k], b[k], 0.003);
    }
    for (let i = 0; i < thickness.length; i++) {
      near(
        thickness[i].sample_min_mm,
        oldSummary.thickness[i].sample_min_mm,
        0.003,
      );
      assert.equal(thickness[i].hits, oldSummary.thickness[i].hits);
    }
  }
  for (const [name, text] of reports)
    if (update) fs.writeFileSync(path.join(output, name), text);
  const table = (headers, rows) =>
    "| " +
    headers.join(" | ") +
    " |\n| " +
    headers.map(() => "---").join(" | ") +
    " |\n" +
    rows.map((row) => "| " + row.join(" | ") + " |").join("\n");
  const row = (r) => {
    const file = r.file.startsWith("_build/")
      ? "`" + r.file + "`"
      : `[${r.file}](${r.file})`;
    return [
      file,
      r.license,
      r.exit === 0 ? r.triangles : "—",
      r.exit === 0 ? `${r.volume} / ${r.area}` : "拒绝",
      r.exit === 0 ? `${r.boundary} / ${r.nonmanifold} / ${r.degenerate}` : "—",
      r.feedback + `；[原始输出](examples/corpus/reports/${r.report})`,
    ];
  };
  const section =
    "<!-- corpus-results:start -->\n## 模型实测与反馈（2026-10-21）\n\n以下语料与报告为 GitHub 主分支补充，核心库及 CLI 与已发布 0.1.3 一致；没有把旧 Mooncakes 包或版本标签改写成包含这些新附件。数据由 `node scripts/corpus-cases.cjs --update` 调用实际 Native CLI 生成。默认门槛为 0 mm、样本预算 1，只用于快速几何回归；壁厚另按下表固定预算测试。STL / OBJ / PLY 的坐标由调用方按毫米解释；3MF 按声明单位换算。顶点焊接默认容差为 `1e-6`。报告三位小数按绝对误差约 0.0015 核对；跨工具链快照容许 0.003。完整数值、退出码、命令和输入哈希见 [summary.json](examples/corpus/reports/summary.json)。\n\n解析退出 0 不等于检查通过。下表体积列在朝向不可靠时仅为有符号贡献绝对值，不可作为可靠实体体积；以原始报告中的质量属性前提为准。外部样例的计数快照用于发现行为变化，不能替代独立正确性证明。\n\n### 自建解析值与边界模型\n\n模型和生成脚本采用 [Apache-2.0](LICENSE)，全部为独立构造。`non-manifold-vertex` 与 `vertex-touching-cubes` 故意使用同一几何验证两个语义，不算两个独立几何来源。\n\n" +
    table(
      [
        "模型",
        "许可",
        "面数",
        "体积 / 面积",
        "边界 / 非流形边 / 退化面",
        "反馈",
      ],
      results.filter((r) => r.group === "analytic").map(row),
    ) +
    "\n\n### 外部模型、许可与实测\n\nCC0 模型来自 [Ghostkeeper / SlicerTestModels contributors](https://github.com/Ghostkeeper/SlicerTestModels/tree/e1bbc8eec047c2fb604b71f7e4793c3e0189fd6d)；BSD 扫描源来自 [3MF Consortium](https://github.com/3MFConsortium/3mf-samples/tree/665e20dc4d7777fd4c9702bca86a2d4028440337)，Copyright (c) 2018, 3MF Consortium。每个文件的作者、固定来源 URL、SHA-256、改动和转换命令见 [manifest.json](examples/external/manifest.json)。[CC0-1.0 完整文本](examples/external/licenses/SlicerTestModels.CC0-1.0.txt) 与 [BSD-2-Clause 完整文本](examples/external/licenses/3MFConsortium.BSD-2-Clause.txt) 随样例保留，不以项目的 Apache-2.0 覆盖它们。外部文件的报告仅描述当前工具和容差下的观察，不据此直接断言上游文件有缺陷。\n\n" +
    table(
      [
        "模型",
        "许可",
        "面数",
        "体积 / 面积",
        "边界 / 非流形边 / 退化面",
        "反馈",
      ],
      results.filter((r) => r.group === "external").map(row),
    ) +
    "\n\nR01 支架、R02 齿轮、R03 CAD 凹面、R04 扫描 PLY、R05 有机曲面、R06 组件 3MF、R07 Cura 工程、R08 10–30 万面均有对应案例。R04 与 R08 使用同一个 BSD 扫描源，PLY 是几何转换，不能当作第二个独立来源。R04 没有验证颜色/法线保真，3MF 材质、Cura 配置和精确自遮挡均未评估；不声称完整切片工程兼容。\n\n### 现有模型全部复测\n\n旧版 COMPARISON.md 未逐个列模型，本次扩大至仓库全部现有 `examples/` 网格（含 13 个官方几何读取案例和坏输入），没有只挑成功文件。\n\n" +
    table(
      [
        "模型",
        "许可",
        "面数",
        "体积 / 面积",
        "边界 / 非流形边 / 退化面",
        "反馈",
      ],
      results.filter((r) => r.group === "existing").map(row),
    ) +
    "\n\n### 修复后重新读取\n\n" +
    table(
      ["输入", "新增面", "删除重复面", "修复后面数", "修复后边界", "证据"],
      repaired.map((r) => [
        "`" + r.file + "`",
        r.added,
        r.removed,
        r.after_triangles,
        r.after_boundary,
        `[修复及复核](examples/corpus/reports/${r.report})`,
      ]),
    ) +
    "\n\n两个三角洞彼此独立，各新增一个三角形；重读导出文件后确认为 12 面且无边界。该结果不扩展到任意复杂洞。\n\n### 固定条件的壁厚采样\n\n所有模型均按 mm，使用默认焊接容差 `1e-6`，几何法线反向射线，参考阈值 0（不按工艺判定）。射线偏移由 `probe_inset()` 按包围盒尺度选取；脚本不覆盖库默认偏移。确定性采样不是面积加权随机采样，命中数和面顺序会影响结果。\n\n" +
    table(
      ["模型", "预算", "命中", "采样最小值 mm", "证据"],
      thickness.map((r) => [
        "`" + path.basename(r.file) + "`",
        r.budget,
        r.hits,
        r.sample_min_mm,
        `[输出](examples/corpus/reports/${r.report})`,
      ]),
    ) +
    "\n\n薄板和空心管结果与解析厚度约符。楔形的竖向高度为 0.05–1 mm，但 1000 / 4096 预算实测射线首命中最小距离为 0.043 / 0.003 mm：采样包含端面和侧面，沿各自内法线命中邻面，测量量并不是竖向高度，0.05 不能作为所有射线距离的下界。不能将这些值写成全局最小壁厚，增加预算也不能保证物理壁厚精度。旧采样漏检反例仍由 `node scripts/review-cases.cjs` 验证。\n\n### 复现\n\n```sh\npython scripts/prepare-scan.py\nnode scripts/corpus-cases.cjs --check\nnode scripts/review-cases.cjs\nnode scripts/stress-cases.cjs\n```\n\n常规 CI 离线使用随仓库的已许可文件，不临时下载模型。大模型和修复输出写入已忽略的 `_build/corpus/`；性能结果见下节，不把 50 MB 模型推入 Git 历史。OpenSCAD 2021.01（GPL-2.0 工具，仅本地执行、不随仓库分发）用于可复现 CAD 导出；重建命令见 `scripts/prepare-external.cjs`。CAD 源码重建可能改变三角化与面顺序；来源清单 SHA 固定的是本次实测附件，重建后必须重新审查与测试，不能承诺字节一致。网上获取的新文件必须先补齐作者、固定来源、许可证、完整条款和 SHA-256。\n<!-- corpus-results:end -->";
  const docFile = path.join(root, "COMPARISON.md"),
    doc = fs.readFileSync(docFile, "utf8"),
    re = /<!-- corpus-results:start -->[\s\S]*?<!-- corpus-results:end -->/;
  if (update)
    fs.writeFileSync(
      docFile,
      re.test(doc)
        ? doc.replace(re, () => section)
        : doc.trimEnd() + "\n\n" + section + "\n",
    );
  else assert(re.test(doc), "Missing model results in COMPARISON.md");
  console.log(
    `Verified ${results.length} model reads (${all.size} checked-in + 1 prepared scan), ${repaired.length} repair/reload cases, ${thickness.length} thickness cases; all source licenses and hashes present.`,
  );
}
module.exports = { build, metrics };
if (require.main === module) main();
