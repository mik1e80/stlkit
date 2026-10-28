// SPDX-License-Identifier: Apache-2.0

///|
fn inspection_value(document : Json, keys : Array[String]) -> Json raise {
  let mut current = document
  for key in keys {
    guard current is Object(values) else { fail("expected object at " + key) }
    current = values.get(key).unwrap()
  }
  current
}

///|
fn inspection_number(document : Json, keys : Array[String]) -> Double raise {
  guard inspection_value(document, keys) is Number(value, ..) else {
    fail("expected number")
  }
  value
}

///|
test "JSON inspection matches cube analytic oracles without rounding away values" {
  let document = inspection_json(
    cube_mesh(),
    format=Obj,
    min_thickness=0.0,
    samples=16,
  ).unwrap()
  assert_eq(inspection_value(document, ["schema_version"]), Json(1))
  assert_true(
    (inspection_number(document, ["geometry", "volume_mm3"]) - 1.0).abs() <
    1.0e-12,
  )
  assert_true(
    (inspection_number(document, ["geometry", "surface_area_mm2"]) - 6.0).abs() <
    1.0e-12,
  )
  assert_eq(
    inspection_value(document, ["mass_properties", "status"]),
    Json("available"),
  )
  assert_eq(inspection_value(document, ["review", "needs_review"]), Json(false))
  assert_eq(
    inspection_value(document, ["review", "printability_certified"]),
    Json(false),
  )
  assert_eq(
    inspection_value(document, ["thickness", "global_minimum_certified"]),
    Json(false),
  )
  assert_eq(@json.parse(document.stringify()), document)
}

///|
test "JSON keeps unassessed open and inward meshes distinct from valid zero" {
  for mesh in [cube_mesh_without(1), cube_inside_out()] {
    let document = inspection_json(mesh, samples=8).unwrap()
    assert_eq(
      inspection_value(document, ["geometry", "volume_mm3"]),
      Json::null(),
    )
    assert_eq(
      inspection_value(document, ["mass_properties", "center_of_mass_mm"]),
      Json::null(),
    )
    assert_eq(
      inspection_value(document, ["mass_properties", "status"]),
      Json("not_evaluated"),
    )
    assert_eq(inspection_value(document, ["thickness", "min_mm"]), Json::null())
    assert_eq(
      inspection_value(document, ["review", "needs_review"]),
      Json(true),
    )
  }
}

///|
test "JSON computed overflow becomes null and requires review" {
  let mesh = Mesh::new([
    Triangle::from_vertices(
      Vec3::zero(),
      Vec3::new(1.0e200, 0, 0),
      Vec3::new(0, 1.0e200, 0),
    ),
  ])
  let document = inspection_json(mesh, samples=1).unwrap()
  assert_eq(
    inspection_value(document, ["geometry", "surface_area_mm2"]),
    Json::null(),
  )
  assert_eq(
    inspection_value(document, ["review", "numeric_failure"]),
    Json(true),
  )
  assert_eq(inspection_value(document, ["review", "needs_review"]), Json(true))
  assert_eq(@json.parse(document.stringify()), document)
}

///|
test "JSON rejects invalid options and non-finite manual mesh input" {
  assert_true(inspection_json(cube_mesh(), samples=0) is Err(_))
  assert_true(inspection_json(cube_mesh(), samples=100001) is Err(_))
  let infinity = @string.parse_double("inf")
  assert_true(inspection_json(cube_mesh(), min_thickness=infinity) is Err(_))
  let mesh = Mesh::new([
    Triangle::from_vertices(
      Vec3::new(infinity, 0, 0),
      Vec3::zero(),
      Vec3::zero(),
    ),
  ])
  assert_true(inspection_json(mesh) is Err(_))
  let empty = inspection_json(Mesh::empty(), samples=1).unwrap()
  assert_eq(inspection_value(empty, ["geometry", "aabb_mm"]), Json::null())
  assert_eq(inspection_value(empty, ["review", "needs_review"]), Json(true))
}

///|
test "checked parse classifies configuration and all reserved resource errors" {
  let cube = @utf8.encode(cube_obj())
  for
    (limits, expected) in [
      ({ ..ParseLimits::default(), max_input_bytes: -1, }, "invalid_limits"),
      ({ ..ParseLimits::default(), max_input_bytes: 1, }, "resource_limit"),
      ({ ..ParseLimits::default(), max_triangles: 1, }, "resource_limit"),
      ({ ..ParseLimits::default(), max_vertices: 1, }, "resource_limit"),
    ] {
    guard parse_mesh_checked(cube, limits~) is Err(error) else {
      fail("expected error")
    }
    assert_eq(error.code(), expected)
    assert_eq(inspection_value(error.to_json(), ["location"]), Json::null())
  }
  guard parse_mesh_checked(b"junk junk", limits={
      ..ParseLimits::default(),
      max_records: 1,
    })
    is Err(error) else {
    fail("expected budget failure")
  }
  assert_eq(error.code(), "resource_limit")
}

///|
test "checked parse does not infer localized syntax subtypes or user markers" {
  guard parse_mesh_checked(b"no known geometry") is Err(unknown) else {
    fail("expected unknown")
  }
  assert_eq(unknown.code(), "unknown_format")
  guard parse_mesh_checked(b"v 0 0 0\nf 1 2 99\n") is Err(invalid) else {
    fail("expected invalid data")
  }
  assert_eq(invalid.code(), "invalid_data")
  assert_eq(inspection_value(invalid.to_json(), ["format"]), Json("obj"))
  let spoof = b"v resource_limit: 0 0\nf 1 2 3\n"
  guard parse_mesh_checked(spoof) is Err(error) else {
    fail("expected bad numeric token")
  }
  assert_eq(error.code(), "invalid_data")
  assert_eq(@json.parse(error.to_json().stringify()), error.to_json())
}
