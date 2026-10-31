// SPDX-License-Identifier: Apache-2.0

///|
test "unsupported OBJ geometry and external statements cannot silently disappear" {
  for
    record in [
      "l 1 2", "p 1", "curv 0 1 1 2", "curv2 1 2", "surf 0 1 0 1 1 2 3", "vp 1 2 3",
      "call other.obj", "csh arbitrary",
    ] {
    assert_true(parse_obj(cube_obj() + "\n" + record + "\n") is Err(_))
  }
  assert_eq(
    parse_obj("o cube\ng group\ns off\n" + cube_obj()).unwrap().triangle_count(),
    12,
  )
}

///|
test "PLY duplicate face lists aliases and non-coordinate properties fail before body reading" {
  for encoding in ["ascii", "binary_little_endian", "binary_big_endian"] {
    for
      property in [
        "property list uchar int vertex_indices\n", "property list uchar int vertex_index\n",
        "property int vertex_indices\n",
      ] {
      let text = "ply\nformat \{encoding} 1.0\nelement vertex 3\nproperty float x\nproperty float y\nproperty float z\nelement face 1\nproperty list uchar int vertex_indices\n" +
        property +
        "end_header\n"
      assert_true(parse_ply(@utf8.encode(text)) is Err(_))
    }
  }
  let duplicate = "ply\nformat ascii 1.0\nelement vertex 3\nproperty float x\nproperty float y\nproperty float z\nproperty uchar red\nproperty uchar red\nelement face 1\nproperty list uchar int vertex_indices\nend_header\n"
  assert_true(parse_ply(@utf8.encode(duplicate)) is Err(_))
}

///|
test "PLY fixed header budget has an explicit resource error" {
  let parts = ["ply\nformat ascii 1.0\n"]
  for _ in 0..<7000 {
    parts.push("comment generated header\n")
  }
  parts.push(
    "element vertex 3\nproperty float x\nproperty float y\nproperty float z\nelement face 1\nproperty list uchar int vertex_indices\nend_header\n0 0 0\n1 0 0\n0 1 0\n3 0 1 2\n",
  )
  guard parse_ply(@utf8.encode(parts.join(""))) is Err(message) else {
    fail("header budget must fail")
  }
  assert_true(message.contains("65536"))
}

///|
test "3MF mesh containers are required unique and ordered" {
  let xml = cube_model_xml("millimeter", "<item objectid=\"1\"/>")
  for
    malformed in [
      xml.replace(old="</vertices>", new="</vertices><vertices/>"),
      xml.replace(old="</triangles>", new="</triangles><triangles/>"),
      xml.replace(old="<vertices>", new="<triangles/><vertices>"),
      xml
      .replace(old="<triangles>", new="<ignored>")
      .replace(old="</triangles>", new="</ignored>"),
    ] {
    assert_true(parse_3mf(mf_bytes(malformed)) is Err(_))
  }
  assert_eq(parse_3mf(mf_bytes(xml)).unwrap().triangle_count(), 12)
}

///|
test "3MF preserves reflected volume sign rejects singular matrices and accepts scale and shear" {
  for transform in ["1 0 0 0 1 0 0 0 0 0 0 0"] {
    let xml = cube_model_xml(
      "millimeter",
      "<item objectid=\"1\" transform=\"\{transform}\"/>",
    )
    assert_true(parse_3mf(mf_bytes(xml)) is Err(_))
  }
  let reflected = parse_3mf(
    mf_bytes(
      cube_model_xml(
        "millimeter", "<item objectid=\"1\" transform=\"-1 0 0 0 1 0 0 0 1 0 0 0\"/>",
      ),
    ),
  ).unwrap()
  let original = parse_3mf(
    mf_bytes(cube_model_xml("millimeter", "<item objectid=\"1\"/>")),
  ).unwrap()
  let before = check_winding_default(original).components[0].signed_volume
  let after = check_winding_default(reflected).components[0].signed_volume
  assert_true(before * after > 0.0)
  assert_true(close(before, after))
  for
    (transform, volume) in [
      ("2 0 0 0 3 0 0 0 4 0 0 0", 24.0),
      ("1 0 0 0.5 1 0 0 0 1 0 0 0", 1.0),
    ] {
    let xml = cube_model_xml(
      "millimeter",
      "<item objectid=\"1\" transform=\"\{transform}\"/>",
    )
    assert_true(close(parse_3mf(mf_bytes(xml)).unwrap().volume(), volume))
  }
}

///|
test "binary STL length wins over header ZIP and PLY magic ambiguity" {
  for magic in [b"PK\x03\x04", b"ply\n"] {
    let raw = write_stl_binary(cube_mesh()).to_fixedarray()
    for i in 0..<magic.length() {
      raw[i] = magic[i]
    }
    let bytes = Bytes::from_array(raw.iter().collect())
    assert_true(detect_format(bytes) is Binary)
    assert_eq(parse_mesh(bytes).unwrap().triangle_count(), 12)
  }
}
