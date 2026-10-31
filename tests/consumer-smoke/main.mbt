// SPDX-License-Identifier: Apache-2.0
// No fixtures, filesystem imports, workspace paths or private API access.
///|
fn main raise {
  let mesh = @stlkit.parse_obj("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n").unwrap()
  assert_eq(mesh.triangle_count(), 1)
  assert_true((mesh.surface_area() - 0.5).abs() < 1.0e-12)
  assert_eq(@stlkit.validate_default(mesh).boundary_edge_count, 3)
  let binary = @stlkit.write_stl_binary(mesh)
  let reread = @stlkit.parse_mesh(binary).unwrap()
  assert_eq(reread.triangle_count(), 1)
  assert_true(@stlkit.parse_mesh(b"not a model") is Err(_))
  let repaired = @stlkit.repair(mesh, @stlkit.RepairOptions::normals_only())
  assert_eq(repaired.mesh.triangle_count(), 1)
  let indexed = mesh.to_indexed().unwrap()
  assert_eq(indexed.vertex_count(), 3)
  assert_eq(indexed.to_mesh().surface_area(), 0.5)
  let document = @stlkit.inspection_json(mesh, format=@stlkit.Obj, samples=1).unwrap()
  assert_true(document.stringify().contains("\"schema_version\":1"))
  guard @stlkit.parse_mesh_checked(b"invalid") is Err(error) else { fail("expected structured error") }
  assert_eq(error.code(), "unknown_format")
  // These APIs distinguish the new package from the old 0.2.0 release.
  assert_eq(@stlkit.validate_checked(mesh, 0.0).unwrap().boundary_edge_count, 3)
  assert_true(@stlkit.validate_checked(mesh, -1.0) is Err(_))
  let checked = @stlkit.repair_checked(mesh, @stlkit.RepairOptions::normals_only(), limits=@stlkit.RepairLimits::default()).unwrap()
  assert_eq(checked.mesh.triangle_count(), 1)
  let protected_bytes = @stlkit.write_stl_binary_checked(checked.mesh).unwrap()
  assert_eq(@stlkit.parse_mesh(protected_bytes).unwrap().triangle_count(), 1)
  assert_true(@stlkit.render_svg_checked(mesh, @stlkit.PreviewOptions::default()).unwrap().contains("<svg"))
  let weighted = @stlkit.check_thickness_area_weighted(mesh, 4, seed=7)
  assert_eq(weighted.samples, 4)
  assert_eq(weighted.hits, 0)
  assert_eq(mesh.triangles[0].area_checked().unwrap(), 0.5)
  let nearest = mesh.nearest_point_checked(@stlkit.Vec3::new(0.25, 0.25, 1.0)).unwrap().unwrap()
  assert_eq(nearest.0, 1.0)
  assert_eq(nearest.1.z, 0.0)
  assert_true(@stlkit.Mesh::empty().nearest_point_checked(@stlkit.Vec3::zero()).unwrap() is None)
  println("CONSUMER_OK triangles=1 area=0.5 boundary=3 roundtrip=1 indexed_vertices=3 schema=1 checked_error=unknown_format")
}
