// SPDX-License-Identifier: Apache-2.0
// Independently constructed analytic fixtures; no downloaded geometry.
const fs = require("node:fs");
const path = require("node:path");
const sub = (a, b) => a.map((v, i) => v - b[i]);
const cross = (a, b) => [
  a[1] * b[2] - a[2] * b[1],
  a[2] * b[0] - a[0] * b[2],
  a[0] * b[1] - a[1] * b[0],
];
function normal(t) {
  const n = cross(sub(t[1], t[0]), sub(t[2], t[0]));
  const d = Math.hypot(...n);
  return d ? n.map((v) => v / d) : [0, 0, 0];
}
const map = (mesh, fn) => mesh.map((t) => t.map(fn));
const reverse = (mesh) => mesh.map(([a, b, c]) => [a, c, b]);
function box(x = 1, y = 1, z = 1) {
  const v = [
    [0, 0, 0],
    [x, 0, 0],
    [x, y, 0],
    [0, y, 0],
    [0, 0, z],
    [x, 0, z],
    [x, y, z],
    [0, y, z],
  ];
  return [
    [0, 2, 1],
    [0, 3, 2],
    [4, 5, 6],
    [4, 6, 7],
    [0, 1, 5],
    [0, 5, 4],
    [1, 2, 6],
    [1, 6, 5],
    [2, 3, 7],
    [2, 7, 6],
    [3, 0, 4],
    [3, 4, 7],
  ].map((t) => t.map((i) => v[i]));
}
function binaryStl(mesh) {
  const b = Buffer.alloc(84 + 50 * mesh.length);
  b.write("STLKIT self-authored analytic corpus; Apache-2.0");
  b.writeUInt32LE(mesh.length, 80);
  mesh.forEach((t, i) =>
    [normal(t), ...t].forEach((v, j) =>
      v.forEach((a, k) => b.writeFloatLE(a, 84 + 50 * i + 12 * j + 4 * k)),
    ),
  );
  return b;
}
function obj(mesh) {
  return (
    "# STLKIT self-authored analytic corpus; SPDX-License-Identifier: Apache-2.0\n" +
    mesh.flatMap((t) => t.map((v) => "v " + v.join(" "))).join("\n") +
    "\n" +
    mesh.map((_, i) => `f ${i * 3 + 1} ${i * 3 + 2} ${i * 3 + 3}`).join("\n") +
    "\n"
  );
}
function indexed(mesh) {
  const v = [],
    f = [],
    seen = new Map();
  for (const t of mesh)
    f.push(
      t.map((p) => {
        const k = p.join(",");
        if (!seen.has(k)) {
          seen.set(k, v.length);
          v.push(p);
        }
        return seen.get(k);
      }),
    );
  return { v, f };
}
function ply(mesh) {
  const { v, f } = indexed(mesh);
  return (
    `ply\nformat ascii 1.0\ncomment STLKIT self-authored; SPDX-License-Identifier: Apache-2.0\nelement vertex ${v.length}\nproperty float x\nproperty float y\nproperty float z\nelement face ${f.length}\nproperty list uchar int vertex_indices\nend_header\n` +
    v.map((p) => p.join(" ")).join("\n") +
    "\n" +
    f.map((t) => "3 " + t.join(" ")).join("\n") +
    "\n"
  );
}
// Minimal uncompressed ZIP writer, fixed timestamps and deterministic order.
function crc32(b) {
  let c = 0xffffffff;
  for (const x of b) {
    c ^= x;
    for (let k = 0; k < 8; k++) c = (c >>> 1) ^ (c & 1 ? 0xedb88320 : 0);
  }
  return (c ^ 0xffffffff) >>> 0;
}
function zip(entries) {
  let offset = 0;
  const local = [],
    central = [];
  for (const [name, text] of entries) {
    const n = Buffer.from(name),
      data = Buffer.from(text),
      crc = crc32(data),
      h = Buffer.alloc(30),
      c = Buffer.alloc(46);
    h.writeUInt32LE(0x04034b50);
    h.writeUInt16LE(20, 4);
    h.writeUInt32LE(crc, 14);
    h.writeUInt32LE(data.length, 18);
    h.writeUInt32LE(data.length, 22);
    h.writeUInt16LE(n.length, 26);
    c.writeUInt32LE(0x02014b50);
    c.writeUInt16LE(20, 4);
    c.writeUInt16LE(20, 6);
    c.writeUInt32LE(crc, 16);
    c.writeUInt32LE(data.length, 20);
    c.writeUInt32LE(data.length, 24);
    c.writeUInt16LE(n.length, 28);
    c.writeUInt32LE(offset, 42);
    local.push(h, n, data);
    central.push(c, n);
    offset += h.length + n.length + data.length;
  }
  const cd = Buffer.concat(central),
    end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50);
  end.writeUInt16LE(entries.length, 8);
  end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(cd.length, 12);
  end.writeUInt32LE(offset, 16);
  return Buffer.concat([...local, cd, end]);
}
function threeMf(mesh) {
  const { v, f } = indexed(mesh);
  return zip([
    [
      "[Content_Types].xml",
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/></Types>',
    ],
    [
      "_rels/.rels",
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rel0" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel" Target="/3D/3dmodel.model"/></Relationships>',
    ],
    [
      "3D/3dmodel.model",
      '<?xml version="1.0"?><model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02"><metadata name="Copyright">STLKIT contributors; Apache-2.0</metadata><resources><object id="1" type="model"><mesh><vertices>' +
        v.map(([x, y, z]) => `<vertex x="${x}" y="${y}" z="${z}"/>`).join("") +
        "</vertices><triangles>" +
        f
          .map(([a, b, c]) => `<triangle v1="${a}" v2="${b}" v3="${c}"/>`)
          .join("") +
        '</triangles></mesh></object></resources><build><item objectid="1"/></build></model>',
    ],
  ]);
}
function tube(n = 128, r = 5, wall = 0.4, h = 10) {
  const tri = [],
    p = (r, i, z) => [
      r * Math.cos((2 * Math.PI * (i % n)) / n),
      r * Math.sin((2 * Math.PI * (i % n)) / n),
      z,
    ];
  for (let i = 0; i < n; i++) {
    const a = p(r, i, 0),
      b = p(r, i + 1, 0),
      c = p(r, i, h),
      d = p(r, i + 1, h),
      e = p(r - wall, i, 0),
      f = p(r - wall, i + 1, 0),
      g = p(r - wall, i, h),
      j = p(r - wall, i + 1, h);
    tri.push(
      [a, b, d],
      [a, d, c],
      [e, j, f],
      [e, g, j],
      [c, d, j],
      [c, j, g],
      [a, f, b],
      [a, e, f],
    );
  }
  return tri;
}
function generateSmall(root) {
  const dir = path.join(root, "examples/corpus");
  fs.mkdirSync(dir, { recursive: true });
  const cube = box(),
    tet = [
      [
        [0, 0, 0],
        [0, 1, 0],
        [1, 0, 0],
      ],
      [
        [0, 0, 0],
        [1, 0, 0],
        [0, 0, 1],
      ],
      [
        [0, 0, 0],
        [0, 0, 1],
        [0, 1, 0],
      ],
      [
        [1, 0, 0],
        [0, 1, 0],
        [0, 0, 1],
      ],
    ];
  const oct = [];
  for (const x of [-1, 1])
    for (const y of [-1, 1])
      for (const z of [-1, 1]) {
        const t = [
          [x, 0, 0],
          [0, y, 0],
          [0, 0, z],
        ];
        oct.push(x * y * z > 0 ? t : [t[0], t[2], t[1]]);
      }
  const shift = (m) => map(m, ([x, y, z]) => [x + 1, y + 1, z + 1]);
  const angle = 0.61,
    rotate = ([x, y, z]) => [
      Math.cos(angle) * x - Math.sin(angle) * y,
      Math.sin(angle) * x + Math.cos(angle) * y,
      z,
    ];
  const cases = [
    ["cube-1mm.ply", cube],
    ["cube-1mm.3mf", cube],
    ["box-2x3x4.stl", box(2, 3, 4)],
    ["tetrahedron-unit.stl", tet],
    ["octahedron-unit.stl", oct],
    ["rotated-box-2x3x4.stl", map(box(2, 3, 4), rotate)],
    ["square-prism-2x2x4.stl", map(box(2, 2, 4), rotate)],
    [
      "hollow-box-10-8.obj",
      [
        ...box(10, 10, 10),
        ...map(reverse(box(8, 8, 8)), (p) => p.map((v) => v + 1)),
      ],
    ],
    ["inside-out-cube.obj", reverse(cube)],
    ["duplicate-face.stl", [...cube, cube[0]]],
    [
      "non-manifold-edge.stl",
      [
        [
          [0, 0, 0],
          [1, 0, 0],
          [0, 1, 0],
        ],
        [
          [1, 0, 0],
          [0, 0, 0],
          [0, -1, 0],
        ],
        [
          [0, 0, 0],
          [1, 0, 0],
          [0, 0, 1],
        ],
      ],
    ],
    ["non-manifold-vertex.obj", [...cube, ...shift(cube)]],
    ["two-independent-holes.stl", cube.filter((_, i) => ![0, 2].includes(i))],
    ["vertex-touching-cubes.obj", [...cube, ...shift(cube)]],
    [
      "self-intersection.obj",
      [...cube, ...map(cube, (p) => p.map((v) => v + 0.5))],
    ],
    ["slab-0.05mm.stl", box(10, 10, 0.05)],
    ["slab-0.40mm.stl", box(10, 10, 0.4)],
    ["slab-0.80mm.stl", box(10, 10, 0.8)],
    [
      "wedge-variable-thickness.stl",
      map(box(10, 10, 1), ([x, y, z]) => [x, y, z * (0.05 + 0.095 * x)]),
    ],
    ["hollow-tube-wall-0.40mm.stl", tube()],
  ];
  for (const [name, mesh] of cases)
    fs.writeFileSync(
      path.join(dir, name),
      name.endsWith(".obj")
        ? obj(mesh)
        : name.endsWith(".ply")
          ? ply(mesh)
          : name.endsWith(".3mf")
            ? threeMf(mesh)
            : binaryStl(mesh),
    );
  // A CAD-style concave L prism, deliberately untriangulated cap polygons.
  const polygon = [
      [0, 0],
      [3, 0],
      [3, 1],
      [1, 1],
      [1, 3],
      [0, 3],
    ],
    v = [...polygon.map((p) => [...p, 0]), ...polygon.map((p) => [...p, 2])];
  const faces = [
    [5, 4, 3, 2, 1, 0],
    [6, 7, 8, 9, 10, 11],
  ];
  for (let i = 0; i < 6; i++)
    faces.push([i, (i + 1) % 6, ((i + 1) % 6) + 6, i + 6]);
  fs.writeFileSync(
    path.join(dir, "concave-l-prism.obj"),
    "# Self-authored CAD-style polygon fixture; SPDX-License-Identifier: Apache-2.0\n" +
      v.map((p) => "v " + p.join(" ")).join("\n") +
      "\n" +
      faces.map((t) => "f " + t.map((i) => i + 1).join(" ")).join("\n") +
      "\n",
  );
  return cases.map(([n]) => n).concat("concave-l-prism.obj");
}
// Connected closed torus, not repeated duplicate faces. Exact F=2*n*m, V=n*m.
function torusPoint(i, j, n, m) {
  const u = (2 * Math.PI * (i % n)) / n,
    v = (2 * Math.PI * (j % m)) / m;
  return [
    (10 + 2 * Math.cos(v)) * Math.cos(u),
    (10 + 2 * Math.cos(v)) * Math.sin(u),
    2 * Math.sin(v),
  ];
}
function stress(file, n, m) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const fd = fs.openSync(file, "w");
  try {
    const h = Buffer.alloc(84);
    h.write("STLKIT deterministic torus; Apache-2.0");
    h.writeUInt32LE(2 * n * m, 80);
    fs.writeSync(fd, h);
    for (let i = 0; i < n; i++) {
      const mesh = [];
      for (let j = 0; j < m; j++) {
        const a = torusPoint(i, j, n, m),
          b = torusPoint(i + 1, j, n, m),
          c = torusPoint(i + 1, j + 1, n, m),
          d = torusPoint(i, j + 1, n, m);
        mesh.push([a, b, c], [a, c, d]);
      }
      fs.writeSync(fd, binaryStl(mesh).subarray(84));
    }
  } finally {
    fs.closeSync(fd);
  }
}
module.exports = {
  zip,
  box,
  map,
  reverse,
  binaryStl,
  obj,
  ply,
  threeMf,
  generateSmall,
  stress,
};
if (require.main === module) {
  const root = path.resolve(__dirname, "..");
  if (process.argv.includes("--stress")) {
    for (const [label, n, m] of [
      ["100k", 250, 200],
      ["500k", 500, 500],
      ["1m", 1000, 500],
    ]) {
      const file = path.join(root, "_build/corpus/stress-" + label + ".stl");
      stress(file, n, m);
      console.log(file);
    }
  } else
    console.log(
      "Generated " +
        generateSmall(root).length +
        " self-authored fixtures (Apache-2.0).",
    );
}
