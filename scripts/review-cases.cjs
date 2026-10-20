// Reproduce rejection-related boundaries with actual CLI reports.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const {spawnSync} = require('node:child_process');
const root = path.resolve(__dirname, '..');
const dir = path.join(root, 'examples', 'review');
const output = path.join(dir, 'reports');
fs.mkdirSync(output, {recursive:true});
const vertices = [], cube = [];
for (const line of fs.readFileSync(path.join(root,'examples/cube.obj'),'utf8').split(/\r?\n/)) {
  const [kind,...tokens] = line.trim().split(/\s+/);
  if (kind === 'v') vertices.push(tokens.map(Number));
  if (kind === 'f') {
    const face = tokens.map(n=>vertices[Number(n)-1]);
    for(let i=1;i+1<face.length;i++) cube.push([face[0],face[i],face[i+1]]);
  }
}
const mid=(a,b)=>a.map((x,i)=>(x+b[i])/2);
let dense = cube;
for(let depth=0;depth<4;depth++) dense=dense.flatMap(([a,b,c])=>{
  const ab=mid(a,b), bc=mid(b,c), ca=mid(c,a);
  return [[a,ab,ca],[ab,b,bc],[ca,bc,c],[ab,bc,ca]];
});
const count=dense.length+cube.length;
const selected=new Set(Array.from({length:1000},(_,i)=>(i*2654435761)%count));
assert.equal(new Set(Array.from({length:count},(_,i)=>(i*2654435761)%count)).size,count);
const missed=Array.from({length:count},(_,i)=>i).filter(i=>!selected.has(i)).slice(0,12);
const thin=cube.map(t=>t.map(([x,y,z])=>[x+3,y,z*0.05]));
const mesh=[]; let di=0, ti=0;
for(let i=0;i<count;i++) mesh.push(missed.includes(i)?thin[ti++]:dense[di++]);
let obj='# Self-authored sampling counterexample: unit cube and 1x1x0.05 plate.\n';
for(const tri of mesh) for(const v of tri) obj+=`v ${v.join(' ')}\n`;
for(let i=0;i<mesh.length;i++) obj+=`f ${3*i+1} ${3*i+2} ${3*i+3}\n`;
fs.writeFileSync(path.join(dir,'sampling-blindspot.obj'),obj);
function binary(k) {
  const b=Buffer.alloc(84+50*12*k); b.writeUInt32LE(12*k,80);
  let pos=84;
  for(let j=0;j<k;j++) for(const tri of cube) {
    tri.forEach((v,i)=>v.forEach((x,a)=>b.writeFloatLE(x+(a===0?j*3:0),pos+12+12*i+4*a)));
    pos+=50;
  }
  return b;
}
function run(name,args,expected) {
  const r=spawnSync('moon',['run','cmd/main',...args],{cwd:root,encoding:'utf8',timeout:120000});
  if(r.error) throw r.error;
  assert.equal(r.status,expected,`${name}\n${r.stdout}\n${r.stderr}`);
  fs.writeFileSync(path.join(output,`${name}.txt`),r.stdout);
  return r.stdout;
}
const cases=[];
for(const [name,nozzle,supports,threshold,status] of [
  ['cube-a','0.4','off','0.8',0], ['cube-b','0.8','on','1.2',1], ['cube-c','0.4','on','0.8',0]
]) {
  const args=['examples/cube.obj','--nozzle',nozzle,'--supports',supports,'--min-thickness',threshold,'--strict'];
  const text=run(name,args,status);
  assert.match(text,/不构成可打印结论/); assert.match(text,/工艺未评估/);
  cases.push({name,input:'examples/cube.obj',nozzle_mm:Number(nozzle),supports,reference_threshold_mm:Number(threshold),exit_code:status,command:`moon run cmd/main ${args.join(' ')}`});
}
const a=run('sampling-1000',['examples/review/sampling-blindspot.obj','--samples','1000','--min-thickness','0.1','--strict'],0);
const b=run('sampling-all',['examples/review/sampling-blindspot.obj','--samples',String(count),'--min-thickness','0.1','--strict'],1);
assert.match(a,/采样最小厚度 1/); assert.match(b,/采样最小厚度 0\.05/);
const storage=[];
for(const k of [1,16,64]) {
  const filename=`cubes-${k}.stl`;
  fs.writeFileSync(path.join(dir,filename),binary(k));
  const text=run(`stream-${k}`,[`examples/review/${filename}`,'--stream-only'],0);
  assert.match(text,new RegExp(`顶点表 ${8*k} 项；边记录 ${36*k} 项`));
  storage.push({cubes:k,triangles:12*k,unique_vertices:8*k,edge_records:36*k});
}
fs.writeFileSync(path.join(output,'summary.json'),JSON.stringify({
  model_lf_text_sha256:crypto.createHash('sha256').update(fs.readFileSync(path.join(root,'examples/cube.obj'),'utf8').replace(/\r\n/g,'\n')).digest('hex'),
  scenarios:cases,sampling:{triangles:count,budget_1000_reported_mm:Number(a.match(/采样最小厚度 ([\d.]+)/)[1]),budget_all_reported_mm:Number(b.match(/采样最小厚度 ([\d.]+)/)[1]),analytic_plate_thickness_mm:0.05,arranged_to_expose_deterministic_miss:true},
  storage,scope:'Nozzle/supports are recorded context only; sample minima are not global minima; storage counts are not process RSS.'
},null,2)+'\n');
console.log('Review cases verified: same-model settings, deterministic sampling miss, growing vertex/edge storage.');
