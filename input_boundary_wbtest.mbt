///|
test "audit: reject nonfinite 3MF transform" {
  let xml = cube_model_xml(
    "millimeter", "<item objectid=\"1\" transform=\"1 0 0 0 1 0 0 0 1 nan 0 0\"/>",
  )
  assert_true(parse_3mf(mf_bytes(xml)) is Err(_))
}

///|
test "audit: reject unsupported required extension" {
  let xml = cube_model_xml("millimeter", "<item objectid=\"1\"/>").replace_all(
    old="<model unit=",
    new="<model xmlns:p=\"http://example.invalid/unsupported\" requiredextensions=\"p\" unit=",
  )
  assert_true(parse_3mf(mf_bytes(xml)) is Err(_))
}

///|
test "audit: reject overflowed 3MF geometry" {
  let xml = cube_model_xml(
    "millimeter", "<item objectid=\"1\" transform=\"1 0 0 0 1 0 0 0 1 1e309 0 0\"/>",
  )
  assert_true(parse_3mf(mf_bytes(xml)) is Err(_))
}

///|
test "audit: reject nonfinite ASCII STL coordinate" {
  let text = "solid a\nfacet normal 0 0 1\nouter loop\nvertex nan 0 0\nvertex 1 0 0\nvertex 0 1 0\nendloop\nendfacet\nendsolid a\n"
  assert_true(parse_stl_ascii(text) is Err(_))
}

///|
test "audit: reject nonfinite OBJ coordinate" {
  assert_true(parse_obj("v nan 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n") is Err(_))
}

///|
test "binary full and streaming readers reject nonfinite vertices" {
  // Inject IEEE-754 float32 +infinity, independently of the mesh writer.
  let original = single_triangle_binary()
  let bytes = Array::makei(original.length(), i => original[i])
  bytes[96] = b'\x00'
  bytes[97] = b'\x00'
  bytes[98] = b'\x80'
  bytes[99] = b'\x7f'
  let input = Bytes::from_array(bytes)
  assert_true(parse_stl_binary(input) is Err(_))
  assert_true(stream_stl_binary(input) is Err(_))
  for chunk_size in [1, 7, 50, 134] {
    assert_true(scan_in_chunks(input, chunk_size) is Err(_))
  }
}

///|
test "3MF rejects finite arithmetic overflow and accepts whitespace transforms" {
  let tf = "1e308 0 0 0 1 0 0 0 1 1e308 0 0"
  assert_true(
    parse_3mf(
      mf_bytes(
        cube_model_xml(
          "millimeter",
          "<item objectid=\"1\" transform=\"\{tf}\"/>",
        ),
      ),
    )
    is Err(_),
  )
  let xml = cube_model_xml("meter", "<item objectid=\"1\"/>").replace_all(
    old="x=\"1\"",
    new="x=\"1e308\"",
  )
  assert_true(parse_3mf(mf_bytes(xml)) is Err(_))
  let xml = cube_model_xml(
    "millimeter", "<item objectid=\"1\" transform=\"1&#x9;0 0 0 1 0 0 0 1 0 0 0\"/>",
  )
  assert_true(parse_3mf(mf_bytes(xml)) is Ok(_))
}

///|
test "optional 3MF extension remains ignorable but required extension is rejected" {
  let xml = cube_model_xml("millimeter", "<item objectid=\"1\"/>").replace_all(
    old="<model unit=",
    new="<model xmlns:p=\"http://example.invalid/unsupported\" unit=",
  )
  assert_true(parse_3mf(mf_bytes(xml)) is Ok(_))
  let empty_required = xml.replace_all(
    old="<model ",
    new="<model requiredextensions=\" &#x9; \" ",
  )
  assert_true(parse_3mf(mf_bytes(empty_required)) is Ok(_))
}
