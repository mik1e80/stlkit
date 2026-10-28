// SPDX-License-Identifier: Apache-2.0

///|
test "public indexed construction roundtrip and validation" {
  let indexed = @stlkit.IndexedMesh::new(
    [
      @stlkit.Vec3::zero(),
      @stlkit.Vec3::new(1, 0, 0),
      @stlkit.Vec3::new(0, 1, 0),
    ],
    [{ a: 0, b: 1, c: 2, }],
  ).unwrap()
  assert_eq(indexed.vertex_count(), 3)
  assert_eq(indexed.triangle_count(), 1)
  assert_eq(indexed.validate().boundary_edge_count, 3)
  assert_eq(indexed.to_mesh().to_indexed().unwrap().vertex_count(), 3)
}
