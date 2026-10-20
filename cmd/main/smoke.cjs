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
