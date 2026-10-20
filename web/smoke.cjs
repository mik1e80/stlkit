// 执行实际编译产物和页面报告逻辑，覆盖判断与修复流程。
// 这里只模拟最小 DOM；页面布局仍由浏览器负责。
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const assert = require("node:assert/strict");
class Element {
  constructor(tag) {
    this.tagName = tag;
    this.children = [];
    this.textContent = "";
    this.className = "";
    this.value = "";
    this.events = new Map();
    this.classList = { add() {}, remove() {} };
  }
  append(...items) { this.children.push(...items); }
  replaceChildren(...items) { this.children = items; this.textContent = ""; }
  addEventListener(event, fn) { this.events.set(event, fn); }
  click() {}
}
const nodes = new Map();
const document = {
  getElementById(id) {
    if (!nodes.has(id)) nodes.set(id, new Element("div"));
    return nodes.get(id);
  },
  createElement(tag) { return new Element(tag); },
};
document.getElementById("min-thickness").value = "0.8";
const context = vm.createContext({
  console, document, Uint8Array, ArrayBuffer, DataView, TextEncoder, TextDecoder,
  atob: s => Buffer.from(s, "base64").toString("binary"),
  btoa: s => Buffer.from(s, "binary").toString("base64"),
});
const artifact = process.argv[2] || path.join(__dirname, "dist", "web.js");
vm.runInContext(fs.readFileSync(artifact, "utf8"), context);
vm.runInContext(fs.readFileSync(path.join(__dirname, "app.js"), "utf8"), context);
const cube = fs.readFileSync(path.join(__dirname, "..", "examples", "cube.obj"), "utf8");
const inward = cube.split(/\r?\n/).map(line => line.startsWith("f ")
  ? "f " + line.slice(2).trim().split(/\s+/).reverse().join(" ") : line).join("\n");
const thin = cube.split(/\r?\n/).map(line => {
  if (!line.startsWith("v ")) return line;
  const [tag, x, y, z] = line.split(/\s+/);
  return `${tag} ${x} ${y} ${Number(z) * 0.1}`;
}).join("\n");
const mixed = cube.split(/\r?\n/).map(line => line.startsWith('v ')?'v '+line.slice(2).trim().split(/\s+/).map(Number).map(n=>2*n).join(' '):line).join('\n')+'\n'+
  inward.split(/\r?\n/).map(line=>{
    if(line.startsWith('v ')) {const v=line.slice(2).trim().split(/\s+/).map(Number);v[0]+=5;return 'v '+v.join(' ');}
    if(line.startsWith('f ')) return 'f '+line.slice(2).trim().split(/\s+/).map(Number).map(n=>n+8).join(' ');
    return line;
  }).join('\n');
function report(text, threshold = 0.8) {
  return context.parseReport(context.analyze_with_threshold(Buffer.from(text).toString("base64"), threshold));
}
function descendants(el) { return [el, ...el.children.flatMap(descendants)]; }
async function load(text) {
  const bytes = Buffer.from(text);
  await context.handleFile({ name: "test.obj", arrayBuffer: async () =>
    bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) });
}
(async () => {
  const packedPly = fs.readFileSync(path.join(__dirname, '..', 'examples', 'ascii-packed.ply'), 'utf8');
  const extraPly = fs.readFileSync(path.join(__dirname, '..', 'examples', 'ascii-extra-values.ply'), 'utf8');
  assert.equal(report(packedPly)['三角形'], '2');
  assert.equal(report(packedPly)['表面积'], '1');
  assert.equal(report(packedPly)['需复核'], 'true');
  assert.equal(context.analyze(Buffer.from(extraPly).toString('base64')), '');
  assert.match(context.analyze_error(Buffer.from(extraPly).toString('base64')), /未声明的多余数据/);
  assert.equal(report(cube)["需复核"], "false");
  assert.match(report(cube)["结论"], /不构成可打印结论/);
  assert.match(report(cube)["工艺范围"], /喷嘴、支撑/);
  assert.equal(report(cube)["采样最小厚度"], "1");
  assert.equal(report(inward)["负体积分量"], "1");
  assert.equal(report(inward)["需复核"], "true");
  assert.equal(report(mixed)["负体积分量"], "1");
  assert.equal(report(mixed)["绕向分量数"], "2");
  assert.match(report(mixed)["分量1"], /有符号体积 -1/);
  assert.equal(report(mixed)["需复核"], "true");
  assert.equal(report(mixed)["体积朝向已复核"], "false");
  assert.equal(report(mixed)["主惯量"], undefined);
  await load(mixed);
  assert(descendants(document.getElementById("report")).some(e => e.textContent.includes("负体积方向")));
  context.runFix();
  assert(descendants(document.getElementById("report")).some(e => e.className === "verdict verdict-ok"));
  assert.equal(report(thin)["薄壁"], "1");
  assert.equal(report(thin, 0.05)["需复核"], "false");
  assert.equal(report(thin, 0)["薄壁"], "0");
  await load(thin);
  const beforeSettings = report(thin)["需复核"];
  document.getElementById("supports").value = "on";
  document.getElementById("supports").events.get("change")();
  assert.equal(report(thin)["需复核"], beforeSettings, "支撑只记录，不能使几何检查通过");
  let rendered = descendants(document.getElementById("report"));
  assert(rendered.some(e => e.className === "verdict verdict-bad"));
  assert(!rendered.some(e => e.id === "fix"), "薄壁不能通过补洞或法线修复");
  document.getElementById("min-thickness").value = "0.05";
  document.getElementById("min-thickness").events.get("change")();
  assert(descendants(document.getElementById("report")).some(e => e.className === "verdict verdict-ok"));
  document.getElementById("min-thickness").value = "0.8";
  await load(inward);
  context.runFix();
  rendered = descendants(document.getElementById("report"));
  assert(rendered.some(e => e.className === "verdict verdict-ok"));
  assert(!rendered.some(e => /可以.*打印/.test(e.textContent)), "修复后也不能承诺打印成功");
  document.getElementById("min-thickness").events.get("change")();
  assert(descendants(document.getElementById("report")).some(e => e.className === "verdict verdict-ok"), "阈值调整应继续检查修复后的模型");
  await load("invalid model");
  document.getElementById("min-thickness").events.get("change")();
  assert(!descendants(document.getElementById("report")).some(e => e.className.startsWith("verdict")), "无效文件不能恢复上一个模型的报告");
  document.getElementById("min-thickness").value = "";
  await load(cube);
  assert(descendants(document.getElementById("report")).some(e => e.textContent.includes("请填写参考壁厚")));
  await load("v nan 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n");
  assert(!descendants(document.getElementById("report")).some(e => e.className.startsWith("verdict")));
  assert.match(context.analyze_error(Buffer.from("v nan 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n").toString("base64")), /有限数字/);
  console.log("网页回归通过：朝内、薄壁、阈值调整、修复结论和非法输入。");
})().catch(error => { console.error(error); process.exitCode = 1; });
