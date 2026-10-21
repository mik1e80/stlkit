// 用实际 CLI 验证退出码、阈值参数、修复和性能报告。
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const assert = require("node:assert/strict");
const { spawnSync } = require("node:child_process");
const root = path.resolve(__dirname, "../..");
const dir = fs.mkdtempSync(path.join(os.tmpdir(), "stlkit-cli-"));
const cube = fs.readFileSync(path.join(root, "examples/cube.obj"), "utf8");
const inward = cube.split(/\r?\n/).map(line => line.startsWith("f ")
  ? "f " + line.slice(2).trim().split(/\s+/).reverse().join(" ") : line).join("\n");
const thin = cube.split(/\r?\n/).map(line => {
  if (!line.startsWith("v ")) return line;
  const [tag, x, y, z] = line.split(/\s+/);
  return `${tag} ${x} ${y} ${Number(z) * 0.1}`;
}).join("\n");
const inwardPath = path.join(dir, "inward.obj");
const thinPath = path.join(dir, "thin.obj");
fs.writeFileSync(inwardPath, inward);
fs.writeFileSync(thinPath, thin);
function run(args, status, text) {
  const result = spawnSync("moon", ["run", "cmd/main", ...args], {
    cwd: root, encoding: "utf8", timeout: 60000,
  });
  if (result.error) throw result.error;
  const output = result.stdout + result.stderr;
  assert.equal(result.status, status, `${args.join(" ")}\n${output}`);
  if (text) assert.match(output, text);
  return output;
}
run(["examples/cube.obj", "--strict"], 0, /未发现已覆盖的问题/);
run([inwardPath, "--strict"], 1, /有符号体积为负/);
run([thinPath, "--strict"], 1, /低于参考阈值/);
run([thinPath, "--min-thickness", "0.05", "--strict"], 0);
run([thinPath, "--min-thickness", "0", "--strict"], 0);
run([thinPath, "--min-thickness", "NaN"], 1, /非负有限数字/);
run([thinPath, "--min-thickness", "-1"], 1);
const fixedPath = path.join(dir, "fixed.stl");
run([inwardPath, "--fix", fixedPath, "--strict"], 0);
assert(fs.statSync(fixedPath).size > 84);
run([fixedPath, "--strict"], 0);
run(["examples/cube.obj", "--bench"], 1, /只支持 STL/);
const benchmark = run(["examples/cube.stl", "--bench"], 0, /数据量估算/);
assert(!/省内存|\d+(?:\.\d+)?%/.test(benchmark));
run(["examples/nonfinite-rejected.obj", "--strict"], 1, /有限数字/);
console.log("CLI 回归通过：朝内、薄壁、阈值、严格退出码、修复和性能报告。");
run(["examples/cube.obj", "--samples", "12", "--nozzle", "0.4", "--supports", "on"], 0, /工艺未评估/);
run(["examples/cube.obj", "--samples", "0"], 1, /1\.\.100000/);
run(["examples/cube.obj", "--nozzle", "NaN"], 1, /正的有限/);
run(["examples/cube.obj", "--supports", "auto"], 1, /on\/off\/unknown/);
run([fixedPath, "--stream-only"], 0, /并非固定总内存/);
run(["examples/cube.stl", "--stream-only"], 1, /只支持二进制/);
run(["examples/cube.stl", "--stream-only", "--strict"], 1, /只接受文件路径/);
const bigCube = cube.split(/\r?\n/).map(line => line.startsWith('v ')
  ? 'v ' + line.slice(2).trim().split(/\s+/).map(Number).map(n=>2*n).join(' ') : line).join('\n');
const smallInward = inward.split(/\r?\n/).map(line => {
  if(line.startsWith('v ')) { const v=line.slice(2).trim().split(/\s+/).map(Number); v[0]+=5; return 'v '+v.join(' '); }
  if(line.startsWith('f ')) return 'f '+line.slice(2).trim().split(/\s+/).map(Number).map(n=>n+8).join(' ');
  return line;
}).join('\n');
const mixedPath = path.join(dir,'mixed-parts.obj');
fs.writeFileSync(mixedPath,bigCube+'\n'+smallInward);
const mixedReport = run([mixedPath,'--strict'],1,/分量 1.*有符号体积 -1/);
assert.match(mixedReport,/分量 0.*有符号体积 8/);
const mixedFixed = path.join(dir,'mixed-fixed.stl');
run([mixedPath,'--fix',mixedFixed,'--strict'],0,/翻转 1 个负体积分量/);
run([mixedFixed,'--strict'],0,/未发现已覆盖的问题/);

// PLY 解析的默认严格行为与几何复核分开验证：开放方片可读，但仍须复核。
const packedPly = run(['examples/ascii-packed.ply'], 0);
assert.match(packedPly, /三角形\s+2 个/);
assert.match(packedPly, /表面积\s+1 mm²/);
run(['examples/ascii-packed.ply', '--strict'], 1, /边界边/);
run(['examples/ascii-extra-values.ply'], 1, /未声明的多余数据/);

// Content detection, including misleading extensions and long headers.
const longStl = fs.readFileSync(path.join(root, 'examples/long-header.stl'), 'utf8');
const keywordsObj = fs.readFileSync(path.join(root, 'examples/obj-stl-keywords.obj'), 'utf8');
const wrongObjPath = path.join(dir, 'really-stl.obj');
const wrongStlPath = path.join(dir, 'really-obj.stl');
fs.writeFileSync(wrongObjPath, longStl); fs.writeFileSync(wrongStlPath, keywordsObj);
for (const file of ['examples/long-header.stl', wrongObjPath]) {
  const output = run([file, '--strict'], 0, /格式\s+ASCII STL/);
  assert.match(output, /三角形\s+12 个/);
}
for (const file of ['examples/obj-stl-keywords.obj', wrongStlPath]) {
  const output = run([file, '--strict'], 0, /格式\s+OBJ/);
  assert.match(output, /三角形\s+12 个/);
}
const junkPath = path.join(dir, 'unknown.obj');
fs.writeFileSync(junkPath, 'arbitrary non-mesh content');
run([junkPath], 1, /无法识别网格格式/);
console.log('格式识别 CLI 回归通过：长头 STL、OBJ 注释、错误后缀、未知输入。');

// 质量属性门槛与是否薄壁分开；失败时不能悄悄省略，也不能输出数值。
function assessed(output) {
  assert.match(output, /重心\s+0\.5, 0\.5, 0\.5 mm/);
  assert.match(output, /主惯量\s+0\.167 \/ 0\.167 \/ 0\.167/);
  assert.doesNotMatch(output, /重心\s+未评估|主惯量\s+未评估/);
}
function unassessed(output) {
  assert.match(output, /重心\s+未评估/);
  assert.match(output, /主惯量\s+未评估/);
  assert.match(output, /质量属性前提.*无退化面.*绕向一致.*分量朝向可靠/);
  assert.doesNotMatch(output, /重心\s+-?\d|主惯量\s+-?\d/);
}
assessed(run(['examples/cube.obj', '--strict'], 0));
assessed(run([fixedPath, '--strict'], 0));
for (const output of [
  run(['examples/degenerate-closed.obj', '--strict'], 1),
  run([inwardPath, '--strict'], 1),
  mixedReport,
  packedPly,
]) unassessed(output);
const flippedPath = path.join(dir, 'flipped-face.obj');
fs.writeFileSync(flippedPath, cube.replace(/^f (.+)$/m, (_, indices) =>
  'f ' + indices.trim().split(/\s+/).reverse().join(' ')));
unassessed(run([flippedPath, '--strict'], 1));
const thinReport = run([thinPath, '--strict'], 1);
assert.match(thinReport, /重心\s+0\.5, 0\.5, 0\.05 mm/);
assert.match(thinReport, /主惯量\s+\d/);
assert.doesNotMatch(thinReport, /主惯量\s+未评估/);
console.log('质量属性 CLI 回归通过：合法数值、闭合退化面、开放、绕向、修复及薄壁。');

// 同一份坏 STL 经过普通报告、整块统计及真正分块 IO，均须失败。
const binaryCube = fs.readFileSync(path.join(root, 'examples/review/cubes-1.stl'));
assert.equal(binaryCube.length, 84 + binaryCube.readUInt32LE(80) * 50);
run(['examples/review/cubes-1.stl', '--stream-only'], 0);
const badBinary = [
  ...[1, 49, 50, 51].map(n => Buffer.concat([binaryCube, Buffer.alloc(n)])),
  binaryCube.subarray(0, binaryCube.length - 1),
  binaryCube.subarray(0, 83),
];
const nonfiniteNormal = Buffer.from(binaryCube);
nonfiniteNormal.writeFloatLE(Infinity, 84);
badBinary.push(nonfiniteNormal);
for (const [i, bytes] of badBinary.entries()) {
  const input = path.join(dir, `bad-binary-${i}.stl`);
  fs.writeFileSync(input, bytes);
  for (const options of [[], ['--stream-only'], ['--bench']]) run([input, ...options], 1);
}
const asciiCube = fs.readFileSync(path.join(root, 'examples/cube.stl'), 'utf8');
const badAscii = [
  asciiCube + '\nfacet normal 0 0 1\nouter loop\nvertex 0 0 0\nendloop\nendfacet\n',
  asciiCube + '\nfacet normal 0 0 NaN\n',
  asciiCube + '\nfacet normal 0 0 1\n',
  asciiCube + '\ntrailing garbage\n',
];
for (const [i, text] of badAscii.entries()) {
  const input = path.join(dir, `bad-ascii-${i}.stl`);
  fs.writeFileSync(input, text);
  for (const options of [[], ['--bench']]) run([input, ...options], 1);
}
console.log('STL 输入契约 CLI 回归通过：尾部、截断、非有限法线及坏 ASCII 面。');

// 组合参数必须生成两个输出，而且 SVG 必须属于最终网格。
function fixWithSvg(input, status, name, svgFirst = false) {
  const meshPath = path.join(dir, `${name}.stl`);
  const svgPath = path.join(dir, `${name}.svg`);
  const options = svgFirst ? ['--svg', svgPath, '--fix', meshPath]
    : ['--fix', meshPath, '--svg', svgPath];
  const output = run([input, ...options, '--strict'], status);
  assert(fs.statSync(meshPath).size > 84, '指定的网格输出必须写出');
  const svg = fs.readFileSync(svgPath, 'utf8');
  assert.match(svg, /^<svg\b/);
  assert.match(svg, /<polygon\b/);
  assert(output.indexOf('已存到') < output.indexOf('预览图已导出到'));
  const expectedPath = path.join(dir, `${name}-from-saved.svg`);
  run([meshPath, '--svg', expectedPath], 0);
  const expected = fs.readFileSync(expectedPath, 'utf8');
  // 二进制 STL 会将坐标量化为 float32，重读后的投影允许微小数值误差。
  const points = text => [...text.matchAll(/points="([^"]+)"/g)]
    .flatMap(match => match[1].trim().split(/[ ,]+/).map(Number));
  assert.equal(svg.replace(/points="[^"]+"/g, 'points=""'),
    expected.replace(/points="[^"]+"/g, 'points=""'), '最终网格的可见面和样式应一致');
  const actualPoints = points(svg), expectedPoints = points(expected);
  assert.equal(actualPoints.length, expectedPoints.length);
  for (let i = 0; i < actualPoints.length; i++) {
    assert(Math.abs(actualPoints[i] - expectedPoints[i]) < 1e-5,
      '组合预览应与修复文件单独生成的预览坐标一致');
  }
  return svg;
}
const inwardSvg = path.join(dir, 'inward-original.svg');
run([inwardPath, '--svg', inwardSvg], 0);
const repairedSvg = fixWithSvg(inwardPath, 0, 'combo-inward');
assert.notEqual(repairedSvg, fs.readFileSync(inwardSvg, 'utf8'), '不得使用修复前网格生成 SVG');
fixWithSvg(inwardPath, 0, 'combo-reversed-options', true);
fixWithSvg('examples/cube.obj', 0, 'combo-no-change');
fixWithSvg(thinPath, 1, 'combo-thin-no-change');
const thinInwardPath = path.join(dir, 'thin-inward.obj');
fs.writeFileSync(thinInwardPath, thin.split(/\r?\n/).map(line => line.startsWith('f ')
  ? 'f ' + line.slice(2).trim().split(/\s+/).reverse().join(' ') : line).join('\n'));
fixWithSvg(thinInwardPath, 1, 'combo-repaired-still-thin');
const missingFix = path.join(dir, 'missing-mesh-dir', 'fixed.stl');
const skippedSvg = path.join(dir, 'must-not-be-written.svg');
run([inwardPath, '--fix', missingFix, '--svg', skippedSvg], 1, /写不了文件/);
assert(!fs.existsSync(skippedSvg));
const savedBeforeSvgError = path.join(dir, 'saved-before-svg-error.stl');
const missingSvg = path.join(dir, 'missing-svg-dir', 'preview.svg');
const svgError = run([inwardPath, '--fix', savedBeforeSvgError, '--svg', missingSvg], 1, /写不了预览图/);
assert(fs.statSync(savedBeforeSvgError).size > 84);
assert.doesNotMatch(svgError, /预览图已导出到/);
const collisionPath = path.join(dir, 'collision.stl');
fs.writeFileSync(collisionPath, 'keep existing file');
run([inwardPath, '--fix', collisionPath, '--svg', collisionPath], 1, /不同的输出路径/);
assert.equal(fs.readFileSync(collisionPath, 'utf8'), 'keep existing file');
console.log('CLI 修复与 SVG 组合回归通过：最终网格、参数顺序、无需改动、严格模式和写入失败。');
