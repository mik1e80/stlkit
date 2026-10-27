// SPDX-License-Identifier: Apache-2.0
// Independently authored in-memory seeds; no external model redistribution.

///|
fn obj_seed() -> String {
  "v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n"
}

///|
fn ply_seed() -> String {
  "ply\nformat ascii 1.0\nelement vertex 3\nproperty float x\nproperty float y\nproperty float z\nelement face 1\nproperty list uchar int vertex_indices\nend_header\n0 0 0 1 0 0 0 1 0 3 0 1 2\n"
}

///|
fn model_seed(extra~ : String = "") -> String {
  "<model xmlns=\"http://schemas.microsoft.com/3dmanufacturing/core/2015/02\"><resources><object id=\"1\"><mesh><vertices><vertex x=\"0\" y=\"0\" z=\"0\"/><vertex x=\"1\" y=\"0\" z=\"0\"/><vertex x=\"0\" y=\"1\" z=\"0\"/></vertices><triangles><triangle v1=\"0\" v2=\"1\" v3=\"2\"/></triangles></mesh></object>" +
  extra +
  "</resources><build><item objectid=\"1\"/></build></model>"
}

///|
fn zip_seed(model : String) -> Bytes {
  let entries = [
    ("3D/3dmodel.model", @utf8.encode(model).to_fixedarray()),
    (
      "_rels/.rels",
      @utf8.encode(
        "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"r\" Target=\"/3D/3dmodel.model\" Type=\"http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel\"/></Relationships>",
      ).to_fixedarray(),
    ),
    (
      "[Content_Types].xml",
      @utf8.encode(
        "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"model\" ContentType=\"application/vnd.ms-package.3dmanufacturing-3dmodel+xml\"/><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/></Types>",
      ).to_fixedarray(),
    ),
  ]
  Bytes::from_array(
    @fzip.zip_sync(entries, opts={
      ..@fzip.ZipEntryOptions::default(),
      level: 0,
    }),
  )
}

///|
fn seeds() -> Array[Bytes] {
  let mesh = @stlkit.parse_obj(obj_seed()).unwrap()
  [
    @stlkit.write_stl_binary(mesh),
    @utf8.encode(@stlkit.write_stl_ascii(mesh, "fuzz")),
    @utf8.encode(obj_seed()),
    @utf8.encode(ply_seed()),
    zip_seed(model_seed()),
  ]
}

///|
fn targeted_seed(kind : Int32, iteration : Int32) -> Bytes {
  match kind {
    0 => {
      let bytes = @stlkit.write_stl_binary(
        @stlkit.parse_obj(obj_seed()).unwrap(),
      ).to_fixedarray()
      let prefix = if iteration / 50 % 2 == 0 {
        b"PK\x03\x04"
      } else {
        b"ply\n"
      }
      for i in 0..<prefix.length() {
        bytes[i] = prefix[i]
      }
      Bytes::from_array(bytes)
    }
    1 =>
      @utf8.encode(
        "solid\nfacet normal 0 0 1\nouter loop\nvertex 1e309 0 0\nendloop\nendfacet\nendsolid\n",
      )
    2 =>
      @utf8.encode(
        obj_seed() +
        (if iteration % 2 == 0 {
          "f 2147483647 0 -2147483648\n"
        } else {
          "v 1e308 1e308 1e308\nf 1 2 4\n"
        }),
      )
    3 =>
      @utf8.encode(
        ply_seed().replace_all(
          old="element face 1",
          new="element empty 2147483647\nelement face 1",
        ),
      )
    _ => zip_seed(model_seed(extra="<object id=\"1\"/>"))
  }
}
