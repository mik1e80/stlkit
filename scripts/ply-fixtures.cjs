// Self-authored PLY input boundaries shared by the actual CLI/web smoke tests.
function invalidHeaderCases(text) {
  const format = 'format ascii 1.0\n';
  return [
    [text.replace(format, ''), /缺少 format/],
    [text.replace(format, format + format), /重复声明 format/],
    [text.replace(format, 'format ascii\n'), /完整声明/],
    [text.replace(format, 'format ascii 9.9\n'), /只支持 PLY 1\.0/],
    [text.replace(format, 'format ascii 1.0 extra\n'), /完整声明/],
    [text.replace(format, '').replace('end_header\n', format + 'end_header\n'), /位于 element 之前/],
    [text.replace('ply\n', 'ply\ncomment before format\n'), /必须紧跟 ply/],
  ];
}
function binaryTrianglePly(big) {
  const kind = big ? 'binary_big_endian' : 'binary_little_endian';
  const header = Buffer.from(`ply\nformat ${kind} 1.0\nelement vertex 3\nproperty float x\nproperty float y\nproperty float z\nelement face 1\nproperty list uchar int vertex_indices\nend_header\n`);
  const body = Buffer.alloc(49);
  [0,0,0, 1,0,0, 0,1,0].forEach((n,i) => big ? body.writeFloatBE(n,4*i) : body.writeFloatLE(n,4*i));
  body[36] = 3;
  [0,1,2].forEach((n,i) => big ? body.writeInt32BE(n,37+4*i) : body.writeInt32LE(n,37+4*i));
  return Buffer.concat([header, body]);
}
module.exports = { invalidHeaderCases, binaryTrianglePly };
