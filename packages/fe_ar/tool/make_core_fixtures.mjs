// Generates the binary fixtures for src/test/fe_ar_core_test.c with the REAL
// meshoptimizer encoder driven through gltf-transform: the same toolchain the
// server's geometry build (CONTRACT C7) uses to write tiles. The C decoder is
// a port of meshoptimizer's reference decoder; these fixtures are what proves
// the port against the encoder rather than against itself.
//
// Usage (no install: it borrows the server's node_modules):
//   node tool/make_core_fixtures.mjs \
//     --node-modules ../../../fusion-eco-server/node_modules \
//     --out src/test/fixtures
//
// Outputs:
//   vertex_*.bin, index_*.bin, sequence_*.bin
//       u32 count, u32 stride, u32 rawLen, u32 encLen, raw bytes, encoded bytes
//   tile_quantize.glb  EXT_meshopt_compression (QUANTIZE) + KHR_mesh_quantization
//   tile_filter.glb    EXT_meshopt_compression (FILTER: octahedral normals)
// The expected values are hard-coded in the C test; keep both in step.
import { mkdirSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const args = Object.fromEntries(
  process.argv.slice(2).reduce((acc, a, i, all) => (a.startsWith('--') ? [...acc, [a.slice(2), all[i + 1]]] : acc), []),
);
const nm = resolve(args['node-modules'] ?? '../../../fusion-eco-server/node_modules');
const out = resolve(args.out ?? 'src/test/fixtures');
mkdirSync(out, { recursive: true });

const load = (p) => import(pathToFileURL(join(nm, p)).href);
const core = await load('@gltf-transform/core/dist/index.js');
const ext = await load('@gltf-transform/extensions/dist/index.js');
const { MeshoptEncoder } = await load('meshoptimizer/index.js');
await MeshoptEncoder.ready;

function writeCase(name, count, stride, raw, enc) {
  const head = new Uint32Array([count, stride, raw.byteLength, enc.byteLength]);
  const buf = Buffer.concat([Buffer.from(head.buffer), Buffer.from(raw.buffer, raw.byteOffset, raw.byteLength), Buffer.from(enc)]);
  writeFileSync(join(out, name), buf);
  console.log(`${name}: count=${count} stride=${stride} raw=${raw.byteLength} enc=${enc.byteLength} header=0x${enc[0].toString(16)}`);
}

// Deterministic pseudo-random data with realistic structure (smooth runs,
// repeated values, sign changes) so every group mode of the codec shows up.
let seed = 12345;
const rnd = () => ((seed = (seed * 1103515245 + 12345) >>> 0) / 4294967296);

function vertexData(count, stride) {
  const raw = new Uint8Array(count * stride);
  const f = new Float32Array(raw.buffer);
  const u16 = new Uint16Array(raw.buffer);
  for (let i = 0; i < count; i++) {
    for (let k = 0; k < stride / 4; k++) {
      const idx = i * (stride / 4) + k;
      if (k === 0) f[idx] = Math.sin(i * 0.01) * 10 + rnd() * 0.001;
      else if (k === 1) f[idx] = i % 7 === 0 ? 0 : Math.cos(i * 0.03) * 3;
      else if (k === 2) f[idx] = -i * 0.05;
      else {
        u16[idx * 2] = i % 300;
        u16[idx * 2 + 1] = 0;
      }
    }
  }
  return raw;
}

for (const [count, stride, version] of [
  [1000, 12, 0],
  [300, 16, 0],
  [17, 8, 0],
  [600, 16, 0],
  [1000, 16, 1],
  [777, 12, 1],
]) {
  const raw = vertexData(count, stride);
  const enc = MeshoptEncoder.encodeVertexBufferLevel(raw, count, stride, 2, version);
  writeCase(`vertex_${count}_${stride}_v${version}.bin`, count, stride, raw, enc);
}

// Triangle indices: a grid mesh, the common case, plus some shuffled
// triangles so the free-index (LEB128) paths run.
function gridIndices(w, h) {
  const idx = [];
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const a = y * (w + 1) + x, b = a + 1, c = a + (w + 1), d = c + 1;
      idx.push(a, b, c, b, d, c);
    }
  }
  for (let i = 0; i < 60; i++) idx.push(Math.floor(rnd() * 5000), Math.floor(rnd() * 5000), Math.floor(rnd() * 5000));
  return idx;
}
for (const size of [2, 4]) {
  const list = gridIndices(30, 20);
  const raw = size === 2 ? new Uint16Array(list) : new Uint32Array(list);
  const enc = MeshoptEncoder.encodeIndexBuffer(new Uint8Array(raw.buffer), list.length, size);
  writeCase(`index_${size}.bin`, list.length, size, new Uint8Array(raw.buffer), enc);
}
{
  const list = [];
  for (let i = 0; i < 400; i++) list.push(i % 2 ? i * 3 : 1000 - i);
  const raw = new Uint32Array(list);
  const enc = MeshoptEncoder.encodeIndexSequence(new Uint8Array(raw.buffer), list.length, 4);
  writeCase('sequence_4.bin', list.length, 4, new Uint8Array(raw.buffer), enc);
}

// ---------------------------------------------------------------------------
// Tiles
//
// Geometry, in the TILE frame after the node transforms:
//   box A (local 0, featureId 7):  x 10..11, y 0..1, z -6..-5   (MEP)
//   box B (local 1, featureId 42): x 12..13, y 0..1, z -6..-5
//   an edge line (local 2, featureId 99) from (10, 2, -5) to (13, 2, -5)
// The mesh is authored around a quantisation grid: positions are int16
// normalised in [-1, 1] with the dequantisation in the child node's
// scale/translation (the KHR_mesh_quantization pattern), under a parent node
// translated by (10, 0, -5).
// ---------------------------------------------------------------------------
function box(x0, y0, z0, x1, y1, z1) {
  const v = [
    [x0, y0, z0], [x1, y0, z0], [x1, y1, z0], [x0, y1, z0],
    [x0, y0, z1], [x1, y0, z1], [x1, y1, z1], [x0, y1, z1],
  ];
  const f = [
    [0, 1, 2], [0, 2, 3], [4, 6, 5], [4, 7, 6],
    [0, 4, 5], [0, 5, 1], [3, 2, 6], [3, 6, 7],
    [1, 5, 6], [1, 6, 2], [0, 3, 7], [0, 7, 4],
  ];
  return { v, f };
}

function makeTile(method, withNormals) {
  const doc = new core.Document();
  const buffer = doc.createBuffer();
  doc.createExtension(ext.KHRMeshQuantization).setRequired(true);
  doc
    .createExtension(ext.EXTMeshoptCompression)
    .setRequired(true)
    .setEncoderOptions({ method });

  // Local (pre-dequantisation) space: the child node maps q in [-1,1] to
  // [-1, 3] metres: p = q * 2 + 1 (scale 2, translation 1 on every axis),
  // which covers every local coordinate below (x 0..3, y 0..2, z -1..0).
  const S = 2, T = 1;
  const quant = (m) => {
    const q = Math.round(((m - T) / S) * 32767);
    if (q < -32767 || q > 32767) throw new Error(`coordinate ${m} outside the quantisation range`);
    return q;
  };

  const parts = [box(0, 0, -1, 1, 1, 0), box(2, 0, -1, 3, 1, 0)];
  const pos = [], fid = [], idx = [], nrm = [];
  parts.forEach((b, local) => {
    const base = pos.length / 3;
    b.v.forEach((p) => {
      pos.push(quant(p[0]), quant(p[1]), quant(p[2]));
      fid.push(local, 0);
      const n = [p[0] - (local * 2 + 0.5), p[1] - 0.5, p[2] + 0.5];
      const l = Math.hypot(...n);
      nrm.push(Math.round((n[0] / l) * 127), Math.round((n[1] / l) * 127), Math.round((n[2] / l) * 127));
    });
    b.f.forEach((t) => idx.push(base + t[0], base + t[1], base + t[2]));
  });

  const acc = (arr, type, normalized = false) =>
    doc.createAccessor().setArray(arr).setType(type).setNormalized(normalized).setBuffer(buffer);

  const tri = doc
    .createPrimitive()
    .setAttribute('POSITION', acc(new Int16Array(pos), 'VEC3', true))
    .setAttribute('TEXCOORD_1', acc(new Uint16Array(fid), 'VEC2'))
    .setIndices(acc(new Uint16Array(idx), 'SCALAR'));
  if (withNormals) tri.setAttribute('NORMAL', acc(new Int8Array(nrm), 'VEC3', true));

  const lpos = [quant(0), quant(2), quant(0), quant(3), quant(2), quant(0)];
  const line = doc
    .createPrimitive()
    .setMode(core.Primitive.Mode.LINES)
    .setAttribute('POSITION', acc(new Int16Array(lpos), 'VEC3', true))
    .setAttribute('TEXCOORD_1', acc(new Uint16Array([2, 0, 2, 0]), 'VEC2'))
    .setIndices(acc(new Uint32Array([0, 1]), 'SCALAR'));

  const mesh = doc.createMesh('tile').addPrimitive(tri).addPrimitive(line);
  const child = doc.createNode('dequant').setMesh(mesh).setScale([S, S, S]).setTranslation([T, T, T]);
  const parent = doc.createNode('cell').setTranslation([10, 0, -5]).addChild(child);
  const scene = doc.createScene('tile').addChild(parent);
  scene.setExtras({ fe: { featureIds: [7, 42, 99], layer: 'mep', buildId: 'build-fixture-1' } });
  doc.getRoot().setDefaultScene(scene);
  return doc;
}

const io = new core.NodeIO()
  .registerExtensions([ext.EXTMeshoptCompression, ext.KHRMeshQuantization])
  .registerDependencies({ 'meshopt.encoder': MeshoptEncoder });

for (const [name, method, normals] of [
  ['tile_quantize.glb', ext.EXTMeshoptCompression.EncoderMethod.QUANTIZE, false],
  ['tile_filter.glb', ext.EXTMeshoptCompression.EncoderMethod.FILTER, true],
]) {
  const glb = await io.writeBinary(makeTile(method, normals));
  writeFileSync(join(out, name), glb);
  const json = JSON.parse(Buffer.from(glb.slice(20, 20 + new DataView(glb.buffer, glb.byteOffset).getUint32(12, true))).toString());
  const modes = (json.bufferViews || [])
    .map((v) => v.extensions?.EXT_meshopt_compression)
    .filter(Boolean)
    .map((m) => `${m.mode}/${m.filter ?? 'NONE'}/stride${m.byteStride}`);
  console.log(`${name}: ${glb.byteLength} bytes, meshopt views: ${modes.join(', ')}`);
}
