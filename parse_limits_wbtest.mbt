// SPDX-License-Identifier: Apache-2.0

///|
test "binary STL opaque PK and PLY headers do not override exact length routing" {
  let original = write_stl_binary(parse_obj(limited_obj()).unwrap())
  for prefix in [b"PK\x03\x04", b"ply\n"] {
    let bytes = original.to_fixedarray()
    for i in 0..<prefix.length() {
      bytes[i] = prefix[i]
    }
    let data = Bytes::from_array(bytes)
    assert_true(detect_format(data) is Binary)
    assert_eq(parse_mesh(data).unwrap().triangle_count(), 1)
  }
}

///|
test "3MF ZIP checksum mismatch is rejected before XML processing" {
  let archive = @fzip.zip_sync(
    [
      (
        "3D/3dmodel.model",
        @utf8.encode(cube_model_xml("millimeter", "<item objectid=\"1\"/>")).to_fixedarray(),
      ),
    ],
    opts={ ..@fzip.ZipEntryOptions::default(), level: 0, },
  )
  let offset = 30 + "3D/3dmodel.model".length()
  assert_true(
    parse_3mf(Bytes::from_array(archive), compatibility=true) is Ok(_),
  )
  archive[offset + 2] = b' '
  assert_true(
    parse_3mf(Bytes::from_array(archive), compatibility=true) is Err(e) &&
    e.contains("ZIP 解不开"),
  )
}

///|
fn[T] expect_limit(result : Result[T, String], field : String) -> Unit raise {
  match result {
    Err(error) =>
      assert_true(error.contains("resource_limit: " + field), msg=error)
    Ok(_) => fail("expected limit " + field)
  }
}

///|
fn limited_obj() -> String {
  "v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n"
}

///|
test "limits validate negative budgets and unsafe recursion settings" {
  for
    limits in [
      { ..ParseLimits::default(), max_vertices: -1, },
      { ..ParseLimits::default(), max_xml_depth: 129, },
      { ..ParseLimits::default(), max_component_depth: 129, },
      { ..ParseLimits::default(), max_triangles: 715827883, },
    ] {
    assert_true(
      parse_mesh(b"", limits~) is Err(e) && e.has_prefix("invalid_limits:"),
    )
    assert_true(StlScanner::new(limits~).finish() is Err(_))
  }
}

///|
test "limits exact byte boundary and UTF8 text accounting" {
  let text = "# 模型\n" + limited_obj()
  let data = @utf8.encode(text)
  let exact = { ..ParseLimits::default(), max_input_bytes: data.length(), }
  assert_true(parse_mesh(data, limits=exact) is Ok(_))
  assert_true(parse_obj(text, limits=exact) is Ok(_))
  let below = { ..exact, max_input_bytes: data.length() - 1, }
  expect_limit(parse_mesh(data, limits=below), "max_input_bytes")
  expect_limit(parse_obj(text, limits=below), "max_input_bytes")
}

///|
test "limits STL full scan and chunked header agree on triangle and corner budgets" {
  let data = write_stl_binary(parse_obj(limited_obj()).unwrap())
  for
    limits in [
      { ..ParseLimits::default(), max_triangles: 0, },
      { ..ParseLimits::default(), max_vertices: 2, },
    ] {
    let field = if limits.max_triangles == 0 {
      "max_triangles"
    } else {
      "max_vertices"
    }
    expect_limit(parse_stl_binary(data, limits~), field)
    expect_limit(stream_stl_binary(data, limits~), field)
    let scanner = StlScanner::new(limits~)
    scanner.feed(data[:84].to_owned())
    assert_true(scanner.error() is Some(_))
    expect_limit(scanner.finish(), field)
    assert_eq(scanner.storage().edge_records, 0)
    scanner.feed(data)
    assert_eq(scanner.storage().pending_bytes, 0)
  }
}

///|
test "limits scanner checks consumed bytes before buffering and errors stay sticky" {
  let scanner = StlScanner::new(limits={
    ..ParseLimits::default(),
    max_input_bytes: 3,
  })
  scanner.feed(b"1234")
  expect_limit(scanner.finish(), "max_input_bytes")
  assert_eq(scanner.storage().peak_buffered_bytes, 0)
  scanner.feed(b"0")
  expect_limit(scanner.finish(), "max_input_bytes")
}

///|
test "limits ASCII STL scan and full parser enforce identical budgets" {
  let text = write_stl_ascii(parse_obj(limited_obj()).unwrap(), "seed")
  let limits = { ..ParseLimits::default(), max_triangles: 0, }
  expect_limit(parse_stl_ascii(text, limits~), "max_triangles")
  expect_limit(stream_stl_ascii(text, limits~), "max_triangles")
}

///|
test "limits OBJ attributes polygons and cumulative face references" {
  expect_limit(
    parse_obj(limited_obj(), limits={
      ..ParseLimits::default(),
      max_vertices: 2,
    }),
    "max_vertices",
  )
  expect_limit(
    parse_obj(limited_obj() + "vn 0 0 1\n", limits={
      ..ParseLimits::default(),
      max_vertices: 3,
    }),
    "max_vertices",
  )
  expect_limit(
    parse_obj(limited_obj(), limits={
      ..ParseLimits::default(),
      max_polygon_vertices: 2,
    }),
    "max_polygon_vertices",
  )
  expect_limit(
    parse_obj(limited_obj() + "f 1 2 3\n", limits={
      ..ParseLimits::default(),
      max_list_items: 5,
    }),
    "max_list_items",
  )
  expect_limit(
    parse_obj(limited_obj(), limits={
      ..ParseLimits::default(),
      max_triangles: 0,
    }),
    "max_triangles",
  )
}

///|
test "limits text line token and empty record floods are bounded before splitting" {
  expect_limit(
    parse_obj("# " + "x".repeat(64) + "\n" + limited_obj(), limits={
      ..ParseLimits::default(),
      max_line_bytes: 32,
    }),
    "max_line_bytes",
  )
  expect_limit(
    parse_obj("\n".repeat(20) + limited_obj(), limits={
      ..ParseLimits::default(),
      max_records: 10,
    }),
    "max_records",
  )
  expect_limit(
    parse_obj(limited_obj(), limits={
      ..ParseLimits::default(),
      max_records: 5,
    }),
    "max_records",
  )
}

///|
test "limits PLY rejects huge zero property element counts before body iteration" {
  let data = @utf8.encode(
    "ply\nformat ascii 1.0\nelement padding 2147483647\nelement vertex 3\nproperty float x\nproperty float y\nproperty float z\nelement face 1\nproperty list uint int vertex_indices\nend_header\n0 0 0 1 0 0 0 1 0 3 0 1 2\n",
  )
  expect_limit(parse_ply(data), "max_records")
}

///|
test "limits PLY cumulative lists polygon and triangulated output budgets" {
  let data = profile_ply("", "0 0 0 1 0 0 0 1 0", "3 0 1 2")
  expect_limit(
    parse_ply(data, limits={ ..ParseLimits::default(), max_list_items: 2, }),
    "max_list_items",
  )
  expect_limit(
    parse_ply(data, limits={ ..ParseLimits::default(), max_vertices: 2, }),
    "max_vertices",
  )
  expect_limit(
    parse_ply(data, limits={
      ..ParseLimits::default(),
      max_polygon_vertices: 2,
    }),
    "max_polygon_vertices",
  )
  let quad = @utf8.encode(
    "ply\nformat ascii 1.0\nelement vertex 4\nproperty float x\nproperty float y\nproperty float z\nelement face 1\nproperty list uchar int vertex_indices\nend_header\n0 0 0 1 0 0 1 1 0 0 1 0 4 0 1 2 3\n",
  )
  expect_limit(
    parse_ply(quad, limits={ ..ParseLimits::default(), max_triangles: 1, }),
    "max_triangles",
  )
}

///|
test "limits 3MF total ZIP bytes and entries are checked before extraction" {
  let data = mf_bytes(cube_model_xml("millimeter", "<item objectid=\"1\"/>"))
  for compatibility in [false, true] {
    expect_limit(
      parse_3mf(data, compatibility~, limits={
        ..ParseLimits::default(),
        max_zip_entries: 2,
      }),
      "max_zip_entries",
    )
    expect_limit(
      parse_3mf(data, compatibility~, limits={
        ..ParseLimits::default(),
        max_uncompressed_bytes: 20,
      }),
      "max_uncompressed_bytes",
    )
  }
}

///|
test "limits 3MF shared build items have a global output budget" {
  let data = mf_bytes(
    cube_model_xml("millimeter", "<item objectid=\"1\"/><item objectid=\"1\"/>"),
  )
  expect_limit(
    parse_3mf(data, limits={ ..ParseLimits::default(), max_triangles: 20, }),
    "max_triangles",
  )
  expect_limit(
    parse_3mf(data, limits={
      ..ParseLimits::default(),
      max_component_instances: 1,
    }),
    "max_component_instances",
  )
  expect_limit(
    parse_3mf(data, limits={ ..ParseLimits::default(), max_vertices: 7, }),
    "max_vertices",
  )
}

///|
test "limits 3MF nested empty fanout is bounded independently of output" {
  let xml = "<model xmlns=\"" +
    MF_CORE_NS +
    "\"><resources><object id=\"1\"><components><component objectid=\"2\"/><component objectid=\"2\"/></components></object><object id=\"2\"><components><component objectid=\"3\"/><component objectid=\"3\"/></components></object><object id=\"3\"/></resources><build><item objectid=\"1\"/></build></model>"
  expect_limit(
    parse_3mf(mf_bytes(xml), limits={
      ..ParseLimits::default(),
      max_component_instances: 3,
    }),
    "max_component_instances",
  )
  expect_limit(
    parse_3mf(mf_bytes(xml), limits={
      ..ParseLimits::default(),
      max_component_depth: 0,
    }),
    "max_component_depth",
  )
}

///|
test "limits 3MF optional XML depth and event count are bounded" {
  let xml = "<model xmlns=\"" +
    MF_CORE_NS +
    "\"><extra><extra><extra/></extra></extra><resources/><build/></model>"
  expect_limit(
    parse_3mf(mf_bytes(xml), limits={
      ..ParseLimits::default(),
      max_xml_depth: 2,
    }),
    "max_xml_depth",
  )
  expect_limit(
    parse_3mf(mf_bytes(xml), limits={
      ..ParseLimits::default(),
      max_records: 1,
    }),
    "max_records",
  )
}

///|
test "limits raising a budget permits a valid input without relaxing syntax" {
  let data = write_stl_binary(parse_obj(limited_obj()).unwrap())
  let zero = { ..ParseLimits::default(), max_triangles: 0, }
  expect_limit(parse_mesh(data, limits=zero), "max_triangles")
  assert_eq(
    parse_mesh(data, limits={ ..zero, max_triangles: 1, })
    .unwrap()
    .triangle_count(),
    1,
  )
  assert_true(
    parse_mesh(b"not a model", limits={ ..zero, max_triangles: 1, }) is Err(_),
  )
}
