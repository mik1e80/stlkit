// SPDX-License-Identifier: Apache-2.0
// Reproduce selected CC0 CAD exports using a locally provided OpenSCAD 2021.01.
const fs = require("node:fs"),
  path = require("node:path"),
  cp = require("node:child_process"),
  assert = require("node:assert/strict");
const { binaryStl } = require("./model-builders.cjs");
const root = path.resolve(__dirname, ".."),
  dir = path.join(root, "examples/external"),
  out = path.join(root, "_build/corpus/openscad");
function packAscii(text) {
  const p = [...text.matchAll(/^\s*vertex\s+(\S+)\s+(\S+)\s+(\S+)\s*$/gm)].map(
    (m) => m.slice(1).map(Number),
  );
  assert.equal(p.length % 3, 0);
  assert(p.length > 0 && p.flat().every(Number.isFinite));
  const data = binaryStl(
    Array.from({ length: p.length / 3 }, (_, i) => p.slice(i * 3, i * 3 + 3)),
  );
  data.fill(0, 0, 80);
  data.write("CC0-1.0; Ghostkeeper/SlicerTestModels; see manifest.json", 0);
  return data;
}
function offToObj(text) {
  const tok = text.trim().split(/\s+/);
  assert.equal(tok.shift(), "OFF");
  const nv = Number(tok.shift()),
    nf = Number(tok.shift());
  tok.shift();
  const v = Array.from({ length: nv }, () => [
    Number(tok.shift()),
    Number(tok.shift()),
    Number(tok.shift()),
  ]);
  const f = Array.from({ length: nf }, () =>
    Array.from({ length: Number(tok.shift()) }, () => Number(tok.shift())),
  );
  const remaining = [];
  // Recover each planar U cap's single boundary from CAD's triangulated OFF.
  for (const z of [0, 5]) {
    const edges = new Map();
    for (const face of f.filter((face) => face.every((i) => v[i][2] === z)))
      for (let j = 0; j < face.length; j++) {
        const a = face[j],
          b = face[(j + 1) % face.length],
          key = [Math.min(a, b), Math.max(a, b)].join(",");
        if (edges.has(key)) edges.delete(key);
        else edges.set(key, [a, b]);
      }
    const next = new Map([...edges.values()]);
    assert.equal(next.size, 8);
    const loop = [],
      start = next.keys().next().value;
    let at = start;
    do {
      loop.push(at);
      at = next.get(at);
      assert(at !== undefined && loop.length <= 8);
    } while (at !== start);
    assert.equal(loop.length, 8);
    remaining.push(loop);
  }
  for (const face of f)
    if (!face.every((i) => v[i][2] === 0) && !face.every((i) => v[i][2] === 5))
      remaining.push(face);
  return (
    "# CC0-1.0; Ghostkeeper/SlicerTestModels; see manifest.json.\n# Derived from OpenSCAD OFF: rejoined planar U caps; no coordinate changes.\n" +
    v.map((p) => "v " + p.join(" ")).join("\n") +
    "\n" +
    remaining.map((t) => "f " + t.map((i) => i + 1).join(" ")).join("\n") +
    "\n"
  );
}
function main() {
  const exe = process.env.OPENSCAD || "openscad";
  fs.mkdirSync(out, { recursive: true });
  const version = cp.spawnSync(exe, ["--version"], { encoding: "utf8" });
  if (version.error) throw version.error;
  assert.match(
    version.stdout + version.stderr,
    /2021\.01/,
    "Use documented OpenSCAD version for these snapshots.",
  );
  for (const [source, name, extra] of [
    ["spice_bracket.scad", "bracket", []],
    ["gear.scad", "gear", []],
    ["heart.scad", "heart", ["-D", 'front_text=""', "-D", 'back_text=""']],
    ["u.scad", "concave-cad", []],
  ]) {
    const file = path.join(
      out,
      name + (name === "concave-cad" ? ".off" : ".stl"),
    );
    const run = cp.spawnSync(
      exe,
      [...extra, "-o", file, path.join(dir, "source", source)],
      { encoding: "utf8", timeout: 180000, maxBuffer: 2e6 },
    );
    if (run.error) throw run.error;
    assert.equal(run.status, 0, run.stderr);
    const text = fs.readFileSync(file, "utf8");
    fs.writeFileSync(
      path.join(dir, name + (name === "concave-cad" ? ".obj" : ".stl")),
      name === "concave-cad" ? offToObj(text) : packAscii(text),
    );
    console.log("Prepared CC0-1.0 " + name);
  }
}
module.exports = { packAscii, offToObj };
if (require.main === module) main();
