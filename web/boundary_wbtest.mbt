// SPDX-License-Identifier: Apache-2.0

///|
test "web rejects mixed unsupported OBJ geometry" {
  let bytes = @base64.encode(
    @stlkit.write_mesh(
      @stlkit.parse_obj("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n").unwrap(),
      "one.obj",
    ).unwrap(),
  )
  assert_true(analyze_error(bytes).length() == 0)
  let mixed = @base64.encode(b"v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\nl 1 2\n")
  assert_true(analyze_error(mixed).contains("不支持"))
}

///|
test "web rejects duplicate PLY face index schemas" {
  let bytes = b"ply\nformat ascii 1.0\nelement vertex 3\nproperty float x\nproperty float y\nproperty float z\nelement face 1\nproperty list uchar int vertex_indices\nproperty list uchar int vertex_index\nend_header\n"
  assert_true(analyze_error(@base64.encode(bytes)).contains("恰好"))
}

///|
test "web repair refuses branched boundaries consistently" {
  let bytes = @base64.encode(
    b"v 0 0 0\nv 1 0 0\nv 0 1 0\nv -1 0 0\nv 0 -1 0\nf 1 2 3\nf 1 4 5\n",
  )
  assert_eq(fixed_stl(bytes), "")
  assert_eq(fixed_preview(bytes), "")
  assert_true(fix_error(bytes).contains("branching boundary"))
}

///|
test "web preview declares bounded downsampling" {
  let parts = ["v 0 0 0\nv 1 0 0\nv 0 1 0\n"]
  for _ in 0..<20001 {
    parts.push("f 1 2 3\n")
  }
  let bytes = @base64.encode(
    @stlkit.write_mesh(
      @stlkit.parse_obj(parts.join("")).unwrap(),
      "preview.obj",
    ).unwrap(),
  )
  assert_true(preview(bytes).contains("sampled 20000 of 20001"))
}
