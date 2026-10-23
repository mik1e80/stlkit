// SPDX-License-Identifier: Apache-2.0
// Independent malformed fixtures shared by real CLI and browser regression.
const { zip } = require('./model-builders.cjs');
const vertices = 'v 0 0 0\nv 1 0 0\nv 0 1 0\n';
const ply = 'ply\nformat ascii 1.0\nelement vertex 3\nproperty float x\nproperty float y\nproperty float z\nelement face 1\nproperty list uchar int vertex_indices\nend_header\n0 0 0 1 0 0 0 1 0\n3 0 1 2\n';
const model = '<model xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02"><resources><object id="1" type="model"><mesh><vertices><vertex x="0" y="0" z="0"/><vertex x="1" y="0" z="0"/><vertex x="0" y="1" z="0"/></vertices><triangles><triangle v1="0" v2="1" v3="2"/></triangles></mesh></object></resources><build><item objectid="1"/></build></model>';
const rels = '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rel0" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel" Target="/3D/3dmodel.model"/></Relationships>';
const types = '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/></Types>';
function mf({geometry=model, relationships=rels, contentTypes=types}={}) {
  const entries = [['3D/3dmodel.model',geometry]];
  if(relationships!==null) entries.push(['_rels/.rels',relationships]);
  if(contentTypes!==null) entries.push(['[Content_Types].xml',contentTypes]);
  return zip(entries);
}
const cases = [
  ['missing-vt.obj',vertices+'f 1/1 2/1 3/1\n',/纹理/],
  ['bad-vt-index.obj',vertices+'vt 0 0\nf 1/2 2/1 3/1\n',/纹理/],
  ['bad-face-form.obj',vertices+'f 1///1 2 3\n',/引用/],
  ['uchar-overflow.ply',ply.replace('element face 1','property uchar flag\nelement face 1').replace('0 0 0 1 0 0 0 1 0','0 0 0 256 1 0 0 0 0 1 0 0'),/声明类型|数值范围/],
  ['unknown-header.ply',ply.replace('element face 1','invalid_header\nelement face 1'),/header/],
  ['short-face.ply',ply.replace('element face 1','element face 2')+'2 0 1\n',/三个顶点/],
  ['missing-types.3mf',mf({contentTypes:null}),/Content_Types/],
  ['missing-rels.3mf',mf({relationships:null}),/_rels/],
  ['wrong-mime.3mf',mf({contentTypes:types.replace('3dmanufacturing-3dmodel+xml','wrong+xml')}),/ContentType/],
  ['duplicate-object.3mf',mf({geometry:model.replace('</resources>','<object id="1"/></resources>')}),/id 重复/],
  ['wrong-core-uri.3mf',mf({geometry:model.replace('core/2015/02','core/2099/01')}),/Core/],
].map(([name,data,error])=>({name,bytes:Buffer.isBuffer(data)?data:Buffer.from(data),error}));
module.exports={cases};
