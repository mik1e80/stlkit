// SPDX-License-Identifier: Apache-2.0
// All fixtures are self-authored and have analytic answers.

///|
test "invalid tolerances cannot erase a mesh through the compatibility API" {
  let mesh = cube_mesh()
  for tolerance in [-1.0, 0.0 / 0.0, 1.0 / 0.0, -1.0 / 0.0] {
    assert_true(validate_checked(mesh, tolerance) is Err(_))
    let options = { ..RepairOptions::default(), tolerance, }
    assert_true(repair_checked(mesh, options) is Err(_))
    let result = repair(mesh, options)
    assert_false(result.changed())
    assert_eq(result.mesh.triangle_count(), 12)
    assert_true(close(result.mesh.volume(), 1.0))
    assert_eq(validate(mesh, tolerance).unique_vertex_count, 8)
  }
  assert_eq(validate_checked(mesh, 0.0).unwrap().unique_vertex_count, 8)
  assert_true(
    repair_checked(mesh, { ..RepairOptions::default(), tolerance: 0.0, })
    is Ok(_),
  )
}

///|
fn u_prism_open() -> Mesh {
  let points = [(0, 0), (4, 0), (4, 4), (3, 4), (3, 1), (1, 1), (1, 4), (0, 4)]
  let lines : Array[String] = []
  for z in [0, 1] {
    for (x, y) in points {
      lines.push("v \{x} \{y} \{z}\n")
    }
  }
  lines.push("f 8 7 6 5 4 3 2 1\n")
  for i in 0..<8 {
    let a = i + 1
    let b = (i + 1) % 8 + 1
    lines.push("f \{a} \{b} \{b + 8} \{a + 8}\n")
  }
  parse_obj(lines.join("")).unwrap()
}

///|
test "concave planar hole uses non-overlapping triangulation with analytic area" {
  let open = u_prism_open()
  let result = repair_checked(open, RepairOptions::default()).unwrap()
  assert_eq(result.filled_holes, 1)
  assert_eq(result.added_triangles, 6)
  assert_true(close(result.mesh.surface_area(), 42.0))
  assert_true(close(result.mesh.volume(), 10.0))
  assert_eq(validate_default(result.mesh).boundary_edge_count, 0)
  assert_eq(open.triangle_count(), 22)
}

///|
test "branching and self-intersecting boundaries are refused without mutation" {
  let branching = Mesh::new([
    Triangle::from_vertices(
      Vec3::zero(),
      Vec3::new(1, 0, 0),
      Vec3::new(0, 1, 0),
    ),
    Triangle::from_vertices(
      Vec3::zero(),
      Vec3::new(-1, 0, 0),
      Vec3::new(0, -1, 0),
    ),
  ])
  assert_true(repair_checked(branching, RepairOptions::default()) is Err(_))
  assert_eq(
    repair(branching, RepairOptions::default()).mesh.triangle_count(),
    2,
  )
  let bowtie = [
    Vec3::new(0, 0, 0),
    Vec3::new(2, 2, 0),
    Vec3::new(0, 2, 0),
    Vec3::new(2, 0, 0),
  ]
  let faces = []
  for i in 0..<4 {
    faces.push(
      Triangle::from_vertices(
        Vec3::new(1, 1, 1),
        bowtie[i],
        bowtie[(i + 1) % 4],
      ),
    )
  }
  assert_true(
    repair_checked(Mesh::new(faces), RepairOptions::default()) is Err(_),
  )
}

///|
test "non-planar rings and exceeded repair budgets return explicit errors" {
  let open = u_prism_open()
  let warp = fn(v : Vec3) {
    if v.x == 4.0 && v.y == 4.0 && v.z == 1.0 {
      Vec3::new(v.x, v.y, 1.2)
    } else {
      v
    }
  }
  let nonplanar = Mesh::new(
    open.triangles.map(t => {
      Triangle::from_vertices(warp(t.a), warp(t.b), warp(t.c))
    }),
  )
  assert_true(repair_checked(nonplanar, RepairOptions::default()) is Err(_))
  for
    limits in [
      { ..RepairLimits::default(), max_faces: 1, },
      { ..RepairLimits::default(), max_faces: 22, },
      { ..RepairLimits::default(), max_boundary_edges: 3, },
      { ..RepairLimits::default(), max_hole_vertices: 3, },
      { ..RepairLimits::default(), max_holes: 0, },
    ] {
    assert_true(
      repair_checked(open, RepairOptions::default(), limits~) is Err(_),
    )
  }
}

///|
test "SVG escapes injected attributes and validates numeric drawing options" {
  let mesh = cube_mesh()
  let svg = render_svg_checked(mesh, {
    ..PreviewOptions::default(),
    stroke: "\" onload=\"alert(1)",
  }).unwrap()
  assert_true(svg.contains("&quot;"))
  assert_false(svg.contains("onload=\""))
  for
    options in [
      { ..PreviewOptions::default(), width: -1, },
      { ..PreviewOptions::default(), height: 0, },
      { ..PreviewOptions::default(), yaw: 0.0 / 0.0, },
      { ..PreviewOptions::default(), pitch: 1.0 / 0.0, },
      { ..PreviewOptions::default(), stroke_width: 1.0 / 0.0, },
      { ..PreviewOptions::default(), stroke: "\u0000", },
    ] {
    assert_true(render_svg_checked(mesh, options) is Err(_))
  }
}

///|
test "SVG preview explicitly bounds selected faces and output bytes" {
  let mesh = Mesh::new(Array::make(30000, cube_mesh().triangles[0]))
  let svg = render_svg_checked(mesh, PreviewOptions::default(), max_faces=16).unwrap()
  assert_true(svg.contains("sampled 16 of 30000"))
  assert_true(svg.split("<polygon").collect().length() <= 17)
  assert_true(svg.length() < 20000)
  assert_true(
    render_svg_checked(
      cube_mesh(),
      PreviewOptions::default(),
      max_output_bytes=20,
    )
    is Err(_),
  )
}

///|
test "vector normalization and PCA remain finite at extreme finite scales" {
  for size in [1.0e-200, 1.0e200] {
    let vector = Vec3::new(size, 0.0, 0.0)
    assert_true((vector.length() / size - 1.0).abs() < 1.0e-12)
    assert_true(close(vector.normalize().x, 1.0))
    let box = box_mesh(size, 2.0 * size, 3.0 * size)
      .oriented_bounding_box()
      .unwrap()
    let dimensions = box.size()
    assert_true((dimensions.x / size - 3.0).abs() < 1.0e-10)
    assert_true((dimensions.y / size - 2.0).abs() < 1.0e-10)
    assert_true((dimensions.z / size - 1.0).abs() < 1.0e-10)
  }
}

///|
test "area volume and centroidal inertia follow scale laws" {
  for scale in [1.0e-9, 1.0, 1.0e9] {
    let mesh = box_mesh(scale, scale, scale)
    assert_true(
      (mesh.surface_area() / (6.0 * scale * scale) - 1.0).abs() < 1.0e-12,
    )
    assert_true((mesh.volume() / (scale * scale * scale) - 1.0).abs() < 1.0e-12)
    let expected = scale * scale * scale * scale * scale / 6.0
    for value in mesh.principal_moments() {
      assert_true((value / expected - 1.0).abs() < 1.0e-12)
    }
    assert_true(mesh.mass_properties_numeric_valid())
  }
}

///|
test "remote geometry cannot enlarge the thickness starting offset" {
  let thin = box_mesh(1.0, 1.0, 0.001)
  let faces = thin.triangles.copy()
  for
    triangle in shifted_box(100.0, 100.0, 100.0, Vec3::new(1000000, 0, 0)).triangles {
    faces.push(triangle)
  }
  let measured = check_thickness(Mesh::new(faces), 240)
  assert_true(measured.hits > 0)
  assert_true((measured.min_thickness - 0.001).abs() < 1.0e-9)
}

///|
test "weighted sampling is reproducible and insensitive to cube face refinement" {
  let cube = cube_mesh()
  let refined = []
  for triangle in cube.triangles {
    let ab = Vec3::new(
      (triangle.a.x + triangle.b.x) / 2.0,
      (triangle.a.y + triangle.b.y) / 2.0,
      (triangle.a.z + triangle.b.z) / 2.0,
    )
    refined.push(Triangle::from_vertices(triangle.a, ab, triangle.c))
    refined.push(Triangle::from_vertices(ab, triangle.b, triangle.c))
  }
  for mesh in [cube, Mesh::new(refined)] {
    let one = check_thickness_area_weighted(mesh, 128, seed=42)
    let two = check_thickness_area_weighted(mesh, 128, seed=42)
    assert_eq(one.hits, two.hits)
    assert_eq(one.mean_thickness, two.mean_thickness)
    assert_true(close(one.mean_thickness, 1.0))
    assert_true(close(one.min_thickness, 1.0))
  }
}
