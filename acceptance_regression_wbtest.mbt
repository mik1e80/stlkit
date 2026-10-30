// SPDX-License-Identifier: Apache-2.0
// Self-authored analytic fixtures; no external model downloads.

///|
fn shifted_box(a : Double, b : Double, c : Double, offset : Vec3) -> Mesh {
  let shift = fn(v : Vec3) {
    Vec3::new(v.x + offset.x, v.y + offset.y, v.z + offset.z)
  }
  Mesh::new(
    box_mesh(a, b, c).triangles.map(t => {
      Triangle::from_vertices(shift(t.a), shift(t.b), shift(t.c))
    }),
  )
}

///|
test "mass properties remain invariant after large positive and negative translation" {
  for offset in [1.0e5, -1.0e5, 1.0e8, -1.0e8, 1.0e12] {
    let mesh = shifted_box(1.0, 1.0, 1.0, Vec3::new(offset, -offset, offset))
    assert_true(close(mesh.volume(), 1.0))
    let center = mesh.center_mass()
    assert_eq(center.x, offset + 0.5)
    assert_eq(center.y, -offset + 0.5)
    assert_eq(center.z, offset + 0.5)
    let inertia = mesh.moment_inertia()
    for i in [0, 4, 8] {
      assert_true(close(inertia[i], 1.0 / 6.0))
    }
    for i in [1, 2, 3, 5, 6, 7] {
      assert_true(inertia[i].abs() < 1.0e-12)
    }
    assert_true(mesh.mass_properties_numeric_valid())
  }
}

///|
test "translated rectangular box has analytic central inertia and survives reversed winding" {
  let mesh = shifted_box(2.0, 3.0, 4.0, Vec3::new(1.0e8, -1.0e8, 1.0e8))
  let expected = [50.0, 40.0, 26.0]
  for subject in [mesh, Mesh::new(mesh.triangles.map(flip_winding))] {
    assert_true(close(subject.volume(), 24.0))
    for i, value in subject.principal_moments() {
      assert_true(close(value, expected[i]))
    }
    assert_true(subject.mass_properties_numeric_valid())
  }
}

///|
test "numeric guard rejects finite but physically impossible inertia" {
  assert_false(
    inertia_numeric_valid([-1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]),
  )
  assert_false(
    inertia_numeric_valid([10.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]),
  )
  assert_false(Mesh::empty().mass_properties_numeric_valid())
}

///|
test "translated tetrahedron retains analytic non-diagonal central inertia" {
  let mesh = parse_obj(
    "v 0 0 0\nv 1 0 0\nv 0 1 0\nv 0 0 1\nf 1 3 2\nf 1 2 4\nf 1 4 3\nf 2 3 4\n",
  ).unwrap()
  let offset = 1.0e8
  let shift = fn(v : Vec3) {
    Vec3::new(v.x + offset, v.y - offset, v.z + offset)
  }
  let translated = Mesh::new(
    mesh.triangles.map(t => {
      Triangle::from_vertices(shift(t.a), shift(t.b), shift(t.c))
    }),
  )
  let inertia = translated.moment_inertia()
  assert_true(close(translated.volume(), 1.0 / 6.0))
  for i in [0, 4, 8] {
    assert_true(close(inertia[i], 1.0 / 80.0))
  }
  for i in [1, 2, 3, 5, 6, 7] {
    assert_true(close(inertia[i], 1.0 / 480.0))
  }
  assert_true(translated.mass_properties_numeric_valid())
}

///|
test "checked Float32 export rejects collapsed triangles and preserves safe exports" {
  let collapsed = shifted_box(1.0, 1.0, 1.0, Vec3::new(1.0e8, 1.0e8, 1.0e8))
  assert_true(write_stl_binary_checked(collapsed) is Err(_))
  for path in ["output.stl", "output.ply"] {
    assert_true(write_mesh(collapsed, path) is Err(_))
  }
  let obj = write_mesh(collapsed, "output.obj").unwrap()
  assert_true(close(parse_mesh(obj).unwrap().volume(), 1.0))
  let safe = shifted_box(1.0, 1.0, 1.0, Vec3::new(1.0e5, 1.0e5, 1.0e5))
  let restored = parse_stl_binary(write_stl_binary_checked(safe).unwrap()).unwrap()
  assert_true(close(restored.surface_area(), 6.0))
  assert_eq(validate_default(restored).degenerate_count, 0)
}

///|
test "checked export rejects Float32 overflow and nonfinite coordinates" {
  let overflow = shifted_box(
    1.0e35,
    1.0e35,
    1.0e35,
    Vec3::new(1.0e40, 0.0, 0.0),
  )
  assert_true(write_stl_binary_checked(overflow) is Err(_))
  let invalid = Mesh::new([
    Triangle::from_vertices(
      Vec3::new(1.0 / 0.0, 0.0, 0.0),
      Vec3::zero(),
      Vec3::new(1.0, 1.0, 0.0),
    ),
  ])
  assert_true(write_mesh(invalid, "output.obj") is Err(_))
  assert_true(write_stl_binary_checked(invalid) is Err(_))
}
