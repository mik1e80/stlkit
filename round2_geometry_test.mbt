// SPDX-License-Identifier: Apache-2.0

///|
test "checked geometry public contracts" {
  let triangle = @stlkit.Triangle::from_vertices(
    @stlkit.Vec3::zero(),
    @stlkit.Vec3::new(1.0, 0.0, 0.0),
    @stlkit.Vec3::new(0.0, 1.0, 0.0),
  )
  assert_eq(triangle.area_checked().unwrap(), 0.5)
  assert_true(
    @stlkit.Mesh::empty().nearest_point_checked(@stlkit.Vec3::zero()).unwrap()
    is None,
  )
  let nearest = @stlkit.Mesh::new([triangle])
    .nearest_point_checked(@stlkit.Vec3::new(0.25, 0.25, 1.0))
    .unwrap()
    .unwrap()
  assert_eq(nearest.0, 1.0)
  assert_eq(nearest.1.z, 0.0)
}
