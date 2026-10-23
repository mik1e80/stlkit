// SPDX-License-Identifier: Apache-2.0
// All fixtures below are independently constructed in memory.

///|
fn profile_obj_prefix() -> String {
  "v 0 0 0\nv 1 0 0\nv 0 1 0\nvt 0\nvt 1 0\nvt 0 1 0\nvn 0 0 1\n"
}

///|
test "OBJ four face reference forms validate all referenced tables" {
  for
    refs in [
      "1 2 3", "1/1 2/2 3/3", "1//1 2//1 3//1", "1/1/1 2/2/1 3/3/1", "-3/-3/-1 -2/-2/-1 -1/-1/-1",
    ] {
    let mesh = parse_obj(profile_obj_prefix() + "f " + refs + "\n").unwrap()
    assert_eq(mesh.triangle_count(), 1)
    assert_true((mesh.surface_area() - 0.5).abs() < 1.0e-9)
  }
}

///|
test "OBJ texture references reject missing zero and out of range declarations" {
  assert_true(parse_obj("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1/1 2/1 3/1\n") is Err(_))
  for
    face_ref in ["1/0", "1/4", "1/-4", "1/1.0", "1/no", "1/2147483648", "1/4/1"] {
    assert_true(
      parse_obj(profile_obj_prefix() + "f " + face_ref + " 2/2 3/3\n") is Err(_),
    )
  }
}

///|
test "OBJ incomplete and overlong face references are rejected" {
  for
    face_ref in [
      "1/", "1//", "1/1/", "1/1/1/2", "/1", "1///1", "0", "4", "1//2", "1//-2",
    ] {
    assert_true(
      parse_obj(profile_obj_prefix() + "f " + face_ref + " 2 3\n") is Err(_),
    )
  }
}

///|
test "OBJ malformed geometry and texture declarations are not ignored" {
  for
    line in [
      "v", "v 0 1", "vn 0 1", "vn 0 0 1 2", "vt", "vt 0 0 0 0", "vt nan", "vt 0 inf",
      "v 0 0 0 1 0 0",
    ] {
    assert_true(
      parse_obj(profile_obj_prefix() + line + "\nf 1 2 3\n") is Err(_),
    )
  }
}

///|
test "OBJ unit weight is supported and rational weights fail explicitly" {
  for weight in ["0", "2", "nan", "inf"] {
    assert_true(
      parse_obj(profile_obj_prefix() + "v 1 1 0 " + weight + "\nf 1 2 3\n")
      is Err(_),
    )
  }
  assert_true(parse_obj(profile_obj_prefix() + "v 1 1 0 1\nf 1 2 4\n") is Ok(_))
}

///|
test "OBJ whitespace inline comments and ignored material statements retain geometry" {
  let text = "v\t0  0\t0\r\nv 1 0 0\r\nv 0 1 0\r\nvt 0 0 # uv\r\nmtllib ignored.mtl\r\nusemtl ignored\r\nf\t1/1  2/1\t3/1 # face\r\n"
  assert_eq(parse_obj(text).unwrap().triangle_count(), 1)
}

///|
test "OBJ mixed face reference forms and non decimal indices fail" {
  for face in ["1/1 2 3", "1//1 2/2/1 3//1", "1_0 2 3", "0x1 2 3"] {
    assert_true(parse_obj(profile_obj_prefix() + "f " + face + "\n") is Err(_))
  }
}

///|
test "PLY binary uint indices cannot overflow internal Int" {
  let header = "ply\nformat binary_little_endian 1.0\nelement vertex 3\nproperty float x\nproperty float y\nproperty float z\nelement face 1\nproperty list uchar uint vertex_indices\nend_header\n"
  let vertices = b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x80\x3f\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x80\x3f\x00\x00\x00\x00"
  let data = @utf8.encode(header) +
    vertices +
    b"\x03\x00\x00\x00\x00\x01\x00\x00\x00\xff\xff\xff\xff"
  assert_true(parse_ply(data) is Err(_))
}

///|
test "3MF duplicate normalized package entries are rejected" {
  let model = cube_model_xml("millimeter", "<item objectid=\"1\"/>")
  let entries = [
    ("[Content_Types].xml", @utf8.encode(content_types_xml()).to_fixedarray()),
    ("_rels/.rels", @utf8.encode(rels_xml()).to_fixedarray()),
    ("3D/3dmodel.model", @utf8.encode(model).to_fixedarray()),
    ("3d/3DMODEL.model", @utf8.encode(model).to_fixedarray()),
  ]
  assert_true(parse_3mf(Bytes::from_array(@fzip.zip_sync(entries))) is Err(_))
}

///|
fn profile_ply(extra : String, values : String, faces : String) -> Bytes {
  @utf8.encode(
    "ply\nformat ascii 1.0\nelement vertex 3\nproperty float x\nproperty float y\nproperty float z\n" +
    extra +
    "element face 1\nproperty list uchar int vertex_indices\nend_header\n" +
    values +
    "\n" +
    faces +
    "\n",
  )
}

///|
test "PLY ASCII integer scalar values obey every declared integer width" {
  for
    (ty, lo, hi, bad_lo, bad_hi) in [
      ("char", "-128", "127", "-129", "128"),
      ("uchar", "0", "255", "-1", "256"),
      ("short", "-32768", "32767", "-32769", "32768"),
      ("ushort", "0", "65535", "-1", "65536"),
      ("int", "-2147483648", "2147483647", "-2147483649", "2147483648"),
      ("uint", "0", "4294967295", "-1", "4294967296"),
    ] {
    for token in [lo, hi] {
      assert_true(
        parse_ply(
          profile_ply(
            "property " + ty + " sample\n",
            "0 0 0 " + token + " 1 0 0 " + token + " 0 1 0 " + token,
            "3 0 1 2",
          ),
        )
        is Ok(_),
      )
    }
    for token in [bad_lo, bad_hi, "1.0", "1e0", "nan", "inf", "1_0"] {
      assert_true(
        parse_ply(
          profile_ply(
            "property " + ty + " sample\n",
            "0 0 0 " + token + " 1 0 0 0 0 1 0 0",
            "3 0 1 2",
          ),
        )
        is Err(_),
      )
    }
  }
}

///|
test "PLY header counts are bounded decimal integers" {
  let good = profile_ply("", "0 0 0 1 0 0 0 1 0", "3 0 1 2")
  for count in ["3.0", "3e0", "-1", "2147483648", "nan", "3_0"] {
    let text = @utf8.decode_lossy(good[:]).replace_all(
      old="element vertex 3",
      new="element vertex " + count,
    )
    assert_true(parse_ply(@utf8.encode(text)) is Err(_))
  }
}

///|
test "PLY rejects unknown malformed and unfinished header records" {
  let good = @utf8.decode_lossy(
    profile_ply("", "0 0 0 1 0 0 0 1 0", "3 0 1 2")[:],
  )
  for
    record in [
      "property", "element vertex", "property float x extra", "ply", "nonsense",
      "end_header extra",
    ] {
    let bad = good.replace_all(
      old="element face 1",
      new=record + "\nelement face 1",
    )
    assert_true(parse_ply(@utf8.encode(bad)) is Err(_))
  }
  assert_true(
    parse_ply(@utf8.encode(good.replace_all(old="end_header\n", new="")))
    is Err(_),
  )
}

///|
test "PLY list count and face index declarations must be integral" {
  let good = @utf8.decode_lossy(
    profile_ply("", "0 0 0 1 0 0 0 1 0", "3 0 1 2")[:],
  )
  for
    declaration in [
      "property list float int vertex_indices", "property list uchar float vertex_indices",
    ] {
    assert_true(
      parse_ply(
        @utf8.encode(
          good.replace_all(
            old="property list uchar int vertex_indices",
            new=declaration,
          ),
        ),
      )
      is Err(_),
    )
  }
  for values in ["-1", "256", "3.0", "3e0", "4 0 1 2", "3 0 1 2147483648"] {
    assert_true(
      parse_ply(profile_ply("", "0 0 0 1 0 0 0 1 0", values)) is Err(_),
    )
  }
}

///|
test "PLY subtriangle faces fail even when another face is valid" {
  for face in ["0", "1 0", "2 0 1"] {
    let text = @utf8.decode_lossy(
      profile_ply("", "0 0 0 1 0 0 0 1 0", "3 0 1 2")[:],
    ).replace_all(old="element face 1", new="element face 2")
    assert_true(parse_ply(@utf8.encode(text + face + "\n")) is Err(_))
  }
}

///|
fn profile_mf(model : String, rels : String?, types : String?) -> Bytes {
  let entries = [("3D/3dmodel.model", @utf8.encode(model).to_fixedarray())]
  if rels is Some(t) {
    entries.push(("_rels/.rels", @utf8.encode(t).to_fixedarray()))
  }
  if types is Some(t) {
    entries.push(("[Content_Types].xml", @utf8.encode(t).to_fixedarray()))
  }
  Bytes::from_array(@fzip.zip_sync(entries))
}

///|
test "3MF strict package discovery and explicit compatibility are separate" {
  let model = cube_model_xml("millimeter", "<item objectid=\"1\"/>")
  for
    (rels, types) in [
      (None, None),
      (Some(rels_xml()), None),
      (Some("<broken>"), Some(content_types_xml())),
    ] {
    let data = profile_mf(model, rels, types)
    assert_true(parse_3mf(data) is Err(_))
    assert_eq(parse_3mf(data, compatibility=true).unwrap().triangle_count(), 12)
    assert_true(parse_mesh(data) is Err(_))
  }
}

///|
test "3MF rejects wrong external duplicate or missing model relationships" {
  let model = cube_model_xml("millimeter", "<item objectid=\"1\"/>")
  for
    rels in [
      rels_xml().replace_all(old="2013/01/3dmodel", new="wrong/3dmodel"),
      rels_xml().replace_all(
        old="Id=\"rel0\"",
        new="Id=\"rel0\" TargetMode=\"External\"",
      ),
      rels_xml().replace_all(old="/3D/3dmodel.model", new="/3D/absent.model"),
      rels_xml().replace_all(
        old="</Relationships>",
        new="<Relationship Id=\"rel2\" Type=\"http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel\" Target=\"/3D/3dmodel.model\"/></Relationships>",
      ),
      rels_xml().replace_all(old="/3D/3dmodel.model", new="../3D/3dmodel.model"),
    ] {
    assert_true(
      parse_3mf(profile_mf(model, Some(rels), Some(content_types_xml())))
      is Err(_),
    )
  }
}

///|
test "3MF content types require correct unique model and relationship declarations" {
  let model = cube_model_xml("millimeter", "<item objectid=\"1\"/>")
  for
    types in [
      content_types_xml().replace_all(
        old="3dmanufacturing-3dmodel+xml",
        new="wrong+xml",
      ),
      content_types_xml().replace_all(
        old="Extension=\"model\"",
        new="Extension=\"other\"",
      ),
      content_types_xml().replace_all(
        old="</Types>",
        new="<Default Extension=\"model\" ContentType=\"wrong\"/></Types>",
      ),
      content_types_xml().replace_all(
        old="Extension=\"rels\"",
        new="Extension=\"bad\"",
      ),
      "<Types/>",
    ] {
    assert_true(
      parse_3mf(profile_mf(model, Some(rels_xml()), Some(types))) is Err(_),
    )
  }
  let override_types = content_types_xml().replace_all(
    old="<Default Extension=\"model\"",
    new="<Override PartName=\"/3D/3dmodel.model\"",
  )
  assert_true(
    parse_3mf(profile_mf(model, Some(rels_xml()), Some(override_types)))
    is Ok(_),
  )
}

///|
test "3MF Core namespace is exact and mandatory" {
  let good = cube_model_xml("millimeter", "<item objectid=\"1\"/>")
  for
    uri in [
      "http://evil.invalid/3dmanufacturing/core", "http://schemas.microsoft.com/3dmanufacturing/core/2099/01",
      "", "https://schemas.microsoft.com/3dmanufacturing/core/2015/02",
    ] {
    assert_true(
      parse_3mf(mf_bytes(good.replace_all(old=MF_CORE_NS, new=uri))) is Err(_),
    )
  }
}

///|
test "3MF same URI aliases and locally bound prefixes are accepted" {
  let mut text = cube_model_xml("millimeter", "<item objectid=\"1\"/>")
  text = text.replace_all(
    old="<model ",
    new="<a:model xmlns:a=\"" +
      MF_CORE_NS +
      "\" xmlns:b=\"" +
      MF_CORE_NS +
      "\" ",
  )
  text = text.replace_all(old="</model>", new="</a:model>")
  for
    name in [
      "resources", "object", "mesh", "vertices", "vertex", "triangles", "triangle",
      "build", "item",
    ] {
    text = text.replace_all(old="<" + name + ">", new="<b:" + name + ">")
    text = text.replace_all(old="<" + name + " ", new="<b:" + name + " ")
    text = text.replace_all(old="</" + name + ">", new="</b:" + name + ">")
  }
  assert_eq(parse_3mf(mf_bytes(text)).unwrap().triangle_count(), 12)
}

///|
test "3MF foreign extension subtrees cannot inject Core lookalikes" {
  let text = cube_model_xml("millimeter", "<item objectid=\"1\"/>").replace_all(
    old="<vertices>",
    new="<x:extra xmlns:x=\"urn:test\"><vertex x=\"nan\"/></x:extra><vertices>",
  )
  assert_eq(parse_3mf(mf_bytes(text)).unwrap().triangle_count(), 12)
}

///|
test "3MF object IDs and core geometry structure are validated" {
  let good = cube_model_xml("millimeter", "<item objectid=\"1\"/>")
  for
    text in [
      good.replace_all(old="</resources>", new="<object id=\"1\"/></resources>"),
      good.replace_all(old="<mesh>", new="<mesh/><mesh>"),
      good.replace_all(old="</mesh>", new="</mesh><components/>"),
      good.replace_all(old="<build>", new="<build/><build>"),
      good.replace_all(
        old="</resources>",
        new="</resources><vertex x=\"0\" y=\"0\" z=\"0\"/>",
      ),
      good.replace_all(old="id=\"1\"", new="id=\"0\""),
      good.replace_all(old="id=\"1\"", new="id=\"2147483648\""),
      good.replace_all(old="v1=\"0\"", new="v1=\"1e0\""),
    ] {
    assert_true(parse_3mf(mf_bytes(text)) is Err(_))
  }
}

///|
test "3MF non UTF8 model bytes are rejected before geometry extraction" {
  let entries = [
    ("[Content_Types].xml", @utf8.encode(content_types_xml()).to_fixedarray()),
    ("_rels/.rels", @utf8.encode(rels_xml()).to_fixedarray()),
    ("3D/3dmodel.model", b"\xff\xfe".to_fixedarray()),
  ]
  assert_true(parse_3mf(Bytes::from_array(@fzip.zip_sync(entries))) is Err(_))
}
