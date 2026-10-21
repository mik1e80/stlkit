"""SPDX-License-Identifier: Apache-2.0
Convert the pinned BSD-2-Clause 3MF scan into geometry-only binary PLY.
This fixture converter accepts only this source's single identity build item.
It is independent of STLKIT's parsers; no repair, rescaling or triangulation.
"""
from pathlib import Path
import hashlib
import json
import struct
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]

def main():
    source = ROOT / "examples/external/kinect-scan.3mf"
    manifest = json.loads((ROOT / "examples/external/manifest.json").read_text("utf-8"))
    entry = next(e for e in manifest["files"] if e["file"] == "examples/external/kinect-scan.3mf")
    assert hashlib.sha256(source.read_bytes()).hexdigest() == entry["sha256"]
    with zipfile.ZipFile(source) as archive:
        root = ET.fromstring(archive.read("3D/3dmodel.model"))
    ns = {"c": "http://schemas.microsoft.com/3dmanufacturing/core/2015/02"}
    assert root.attrib["unit"] == "millimeter"
    items = root.findall("c:build/c:item", ns)
    objects = root.findall("c:resources/c:object", ns)
    assert len(items) == len(objects) == 1
    assert items[0].attrib == {"objectid": objects[0].attrib["id"]}
    vertices = objects[0].findall("c:mesh/c:vertices/c:vertex", ns)
    faces = objects[0].findall("c:mesh/c:triangles/c:triangle", ns)
    assert len(vertices) == 141249 and len(faces) == 282544
    target = ROOT / "_build/corpus/kinect-scan.ply"
    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open("wb") as output:
        output.write(("ply\nformat binary_little_endian 1.0\n"
                      "comment 3MF Consortium; BSD-2-Clause; geometry-only conversion\n"
                      f"element vertex {len(vertices)}\n"
                      "property float x\nproperty float y\nproperty float z\n"
                      f"element face {len(faces)}\n"
                      "property list uchar int vertex_indices\nend_header\n").encode())
        for vertex in vertices:
            output.write(struct.pack("<fff", *(float(vertex.attrib[k]) for k in ("x", "y", "z"))))
        for face in faces:
            output.write(struct.pack("<Biii", 3, *(int(face.attrib[k]) for k in ("v1", "v2", "v3"))))
    print(f"Prepared BSD-2-Clause scan: {len(vertices)} vertices, {len(faces)} triangles; {target}")

if __name__ == "__main__":
    main()
