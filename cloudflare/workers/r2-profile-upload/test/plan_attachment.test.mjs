// Land / plot plan attachments (Offer and Owner): the Worker's eight plan
// routes against an in-memory Supabase and R2. The fake database's two plan
// functions model the SQL in supabase/migrations/20261012233000_*.sql, which is
// exercised against a real PostgreSQL engine by the validation script beside it;
// what is proven HERE is the Worker's own behavior: authorization, the Single
// Active Device gate, validation of the real bytes and sizes, the order of the
// replacement (the old plan survives until the new one is confirmed), removal,
// parent isolation, cleanup and what the routes never reveal or persist.
//
// Nothing here touches Supabase, R2 or Cloudflare.
import { test, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import zlib from 'node:zlib';
import worker, { proveWordDocument, runOfferPlanSweeps, runOwnerPlanSweeps } from '../worker.js';
import { removeAccountMedia } from '../account_deletion.js';

const ALICE = '11111111-1111-4111-8111-111111111111';
const BOB = '22222222-2222-4222-8222-222222222222';
const OFFER_A = 'a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a1a1';
const OFFER_A2 = 'a2a2a2a2-a2a2-42a2-82a2-a2a2a2a2a2a2';
const OFFER_A_DELETED = 'a3a3a3a3-a3a3-43a3-83a3-a3a3a3a3a3a3';
const OFFER_B = 'b1b1b1b1-b1b1-41b1-81b1-b1b1b1b1b1b1';
const OWNER_A = 'c1c1c1c1-c1c1-41c1-81c1-c1c1c1c1c1c1';
const OWNER_A2 = 'c2c2c2c2-c2c2-42c2-82c2-c2c2c2c2c2c2';
const OWNER_A_DELETED = 'c3c3c3c3-c3c3-43c3-83c3-c3c3c3c3c3c3';
const OWNER_B = 'd1d1d1d1-d1d1-41d1-81d1-d1d1d1d1d1d1';
const BUCKET = 'broker-wallet-media-staging';
const OTHER_BUCKET = 'broker-wallet-media';
const SUPABASE_URL = 'https://project.supabase.test';
const SECRET = 'test-service-key';
const MIB = 1024 * 1024;
const DAY = 24 * 60 * 60 * 1000;
const DOCX = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

// --- file bytes ------------------------------------------------------------

const pad = (head, length = 64) => {
  const out = new Uint8Array(Math.max(length, head.length));
  out.set(head);
  return out;
};
const zipEntry = (name, flags = 0) => {
  const encoded = new TextEncoder().encode(name);
  const out = new Uint8Array(30 + encoded.length + 16);
  out.set([0x50, 0x4b, 0x03, 0x04]);
  out[6] = flags;
  out[26] = encoded.length & 0xff;
  out[27] = encoded.length >> 8;
  out.set(encoded, 30);
  return out;
};
const JPEG = pad([0xff, 0xd8, 0xff]);
const PNG = pad([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const WEBP = pad([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50]);
const PDF = new TextEncoder().encode('%PDF-1.7\n1 0 obj\n%%EOF');
// --- Office files, built in memory (never stored) ---------------------------
// Office files built in memory, never stored: Open XML packages (ZIP) and compound
// files (OLE2). They have the shape Office writes, so what the Worker must tell
// apart (Word from Excel from PowerPoint) is exactly what differs between them.
const utf8 = (text) => new TextEncoder().encode(text);
const bytesOf = (data) => (typeof data === 'string' ? utf8(data) : data);
const u16 = (n) => [n & 0xff, (n >>> 8) & 0xff];
const u32 = (n) => [n & 0xff, (n >>> 8) & 0xff, (n >>> 16) & 0xff, (n >>> 24) & 0xff];
const concat = (chunks) => {
  const out = new Uint8Array(chunks.reduce((sum, c) => sum + c.length, 0));
  let at = 0;
  for (const chunk of chunks) {
    out.set(chunk, at);
    at += chunk.length;
  }
  return out;
};

const CRC_TABLE = Array.from({ length: 256 }, (_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});
const crc32 = (bytes) => {
  let c = 0xffffffff;
  for (const b of bytes) c = CRC_TABLE[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
};

/**
 * A ZIP archive. Each entry: { name, data, method: 'deflate' | 'store', flags,
 * descriptor } (descriptor: the sizes follow the data, as streaming writers do).
 * To build the hostile archives an entry may also carry rawMethod (the method
 * number written), packed (the bytes stored in place of data's own) and claim
 * ({ size, packed }: what the directory says about its sizes); [eocd] overrides
 * the end record's fields and [comment] is its trailing comment.
 */
function zipArchive(entries, { comment = '', eocd = {} } = {}) {
  const chunks = [];
  const records = [];
  let offset = 0;
  for (const entry of entries) {
    const name = utf8(entry.name);
    const data = bytesOf(entry.data);
    const stored = entry.method === 'store';
    const packed = entry.packed ?? (stored ? data : zlib.deflateRawSync(data));
    const crc = crc32(data);
    const flags = (entry.flags ?? 0) | (entry.descriptor ? 0x8 : 0);
    const method = entry.rawMethod ?? (stored ? 0 : 8);
    const local = Uint8Array.from([
      0x50, 0x4b, 0x03, 0x04, ...u16(20), ...u16(flags), ...u16(method), ...u16(0), ...u16(0x21),
      ...u32(entry.descriptor ? 0 : crc), ...u32(entry.descriptor ? 0 : packed.length),
      ...u32(entry.descriptor ? 0 : data.length), ...u16(name.length), ...u16(0), ...name,
    ]);
    chunks.push(local, packed);
    let length = local.length + packed.length;
    if (entry.descriptor) {
      chunks.push(Uint8Array.from([0x50, 0x4b, 0x07, 0x08, ...u32(crc), ...u32(packed.length), ...u32(data.length)]));
      length += 16;
    }
    records.push({ name, flags, method, crc, packed: entry.claim?.packed ?? packed.length, size: entry.claim?.size ?? data.length, offset });
    offset += length;
  }
  const directory = concat(records.map((r) => Uint8Array.from([
    0x50, 0x4b, 0x01, 0x02, ...u16(20), ...u16(20), ...u16(r.flags), ...u16(r.method), ...u16(0), ...u16(0x21),
    ...u32(r.crc), ...u32(r.packed), ...u32(r.size), ...u16(r.name.length), ...u16(0), ...u16(0), ...u16(0),
    ...u16(0), ...u32(0), ...u32(r.offset), ...r.name,
  ])));
  const count = eocd.count ?? records.length;
  const end = Uint8Array.from([
    0x50, 0x4b, 0x05, 0x06, ...u16(eocd.disk ?? 0), ...u16(eocd.directoryDisk ?? 0), ...u16(eocd.countOnDisk ?? count),
    ...u16(count), ...u32(eocd.directorySize ?? directory.length), ...u32(eocd.directoryOffset ?? offset),
    ...u16(utf8(comment).length), ...utf8(comment),
  ]);
  return concat([...chunks, directory, end]);
}

const WORD_MAIN = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml';
const XLSX_MAIN = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml';
const PPTX_MAIN = 'application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml';
const OFFICE_DOCUMENT = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument';
const XML = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';

const contentTypesXml = (part, contentType) =>
  `${XML}<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">` +
  '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' +
  '<Default Extension="xml" ContentType="application/xml"/>' +
  `<Override PartName="/${part}" ContentType="${contentType}"/></Types>`;

const relationshipsXml = (target, type = OFFICE_DOCUMENT) =>
  `${XML}<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">` +
  `<Relationship Id="rId1" Type="${type}" Target="${target}"/></Relationships>`;

/**
 * An Open XML package as Office writes it: the content-types part first, the
 * root relationship naming the main part, then the main part. Options replace
 * any piece ([types], [rels], [entries] for the whole list) or add parts.
 */
function ooxmlPackage({ part, contentType, body = '<root/>', types, rels, extra = [], entries, archive }) {
  return zipArchive(entries ?? [
    { name: '[Content_Types].xml', data: types ?? contentTypesXml(part, contentType) },
    { name: '_rels/.rels', data: rels ?? relationshipsXml(part) },
    { name: part, data: body },
    ...extra,
  ], archive);
}

const WORD_BODY =
  '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:r><w:t>Plot 14</w:t></w:r></w:p></w:body></w:document>';
const docxFile = (options = {}) =>
  ooxmlPackage({
    part: 'word/document.xml',
    contentType: WORD_MAIN,
    body: WORD_BODY,
    extra: [{ name: 'docProps/core.xml', data: '<cp/>' }],
    ...options,
  });
const xlsxFile = (options = {}) =>
  ooxmlPackage({ part: 'xl/workbook.xml', contentType: XLSX_MAIN, ...options });
const pptxFile = (options = {}) =>
  ooxmlPackage({ part: 'ppt/presentation.xml', contentType: PPTX_MAIN, ...options });

/**
 * A package as Microsoft's packaging library writes it, and so the generators built
 * on it: the first XML part it writes types every `.xml` part by the Default for
 * `xml` (there is no Override for it), the relationship target is absolute, and the
 * content-types part comes last.
 */
const netPackagedFile = (part, mainType) => zipArchive([
  { name: part, data: WORD_BODY },
  { name: 'docProps/core.xml', data: '<cp/>', method: 'store' },
  {
    name: '_rels/.rels',
    method: 'store',
    data: '<?xml version="1.0" encoding="utf-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
      `<Relationship Type="${OFFICE_DOCUMENT}" Target="/${part}" Id="R3b4c10ddb5a3493d" /></Relationships>`,
  },
  {
    name: '[Content_Types].xml',
    method: 'store',
    data: '<?xml version="1.0" encoding="utf-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' +
      `<Default Extension="xml" ContentType="${mainType}" />` +
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml" />' +
      '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml" /></Types>',
  },
]);

const FREE = 0xffffffff;
const END = 0xfffffffe;
const FAT_SECTOR = 0xfffffffd;
const DIFAT_SECTOR = 0xfffffffc;
const CFB_MAGIC = [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1];

/**
 * A compound file (OLE2) as Word, Excel and PowerPoint write one: the streams in
 * sectors, then the directory, then the FAT (and DIFAT sectors beyond 109 FAT
 * sectors). [tree] lists the root's children: { name, size } for a stream,
 * { name, children } for a storage. [version] 3 has 512-byte sectors, 4 has 4096.
 */
function compoundFile({ tree, version = 3 }) {
  const sectorSize = version === 4 ? 4096 : 512;
  const perSector = sectorSize / 4;

  // Entries in directory order: the root, then each child list depth-first.
  const entries = [{ name: 'Root Entry', type: 5, children: tree }];
  const place = (list) => {
    const ids = list.map((node) => {
      entries.push(node);
      node.type = node.children ? 1 : 2;
      node.id = entries.length - 1;
      return node;
    });
    for (const node of ids) if (node.children) node.childIds = place(node.children);
    return ids;
  };
  entries[0].childIds = place(tree);
  entries[0].id = 0;

  // Each storage's children form a binary search tree in CFB order (a shorter
  // name first, then by upper-case), as the writers produce and strict readers need.
  const order = (a, b) => a.name.length - b.name.length || (a.name.toUpperCase() < b.name.toUpperCase() ? -1 : a.name.toUpperCase() > b.name.toUpperCase() ? 1 : 0);
  const link = (nodes) => {
    if (nodes.length === 0) return FREE;
    const middle = nodes.length >> 1;
    const node = nodes[middle];
    node.left = link(nodes.slice(0, middle));
    node.right = link(nodes.slice(middle + 1));
    return node.id;
  };
  for (const entry of entries) if (entry.childIds) entry.treeRoot = link([...entry.childIds].sort(order));

  // Data sectors for every stream, in entry order.
  let next = 0;
  const data = [];
  for (const entry of entries) {
    if (entry.type !== 2) continue;
    entry.start = next;
    entry.sectors = Math.max(1, Math.ceil(entry.size / sectorSize));
    next += entry.sectors;
    const bytes = new Uint8Array(entry.sectors * sectorSize);
    if (entry.head) bytes.set(entry.head);
    data.push(bytes);
  }
  const dataSectors = next;
  const dirSectors = Math.ceil(entries.length / (sectorSize / 128));

  // FAT and DIFAT sizes depend on each other: grow until they are stable.
  let fatSectors = 1;
  let difatSectors = 0;
  for (;;) {
    const total = dataSectors + dirSectors + fatSectors + difatSectors;
    const needFat = Math.ceil(total / perSector);
    const needDifat = needFat > 109 ? Math.ceil((needFat - 109) / (perSector - 1)) : 0;
    if (needFat === fatSectors && needDifat === difatSectors) break;
    fatSectors = needFat;
    difatSectors = needDifat;
  }
  const dirStart = dataSectors;
  const fatStart = dirStart + dirSectors;
  const difatStart = fatStart + fatSectors;
  const total = difatStart + difatSectors;

  const fat = new Uint32Array(fatSectors * perSector).fill(FREE);
  const chain = (start, count) => {
    for (let i = 0; i < count; i++) fat[start + i] = i === count - 1 ? END : start + i + 1;
  };
  for (const entry of entries) if (entry.type === 2) chain(entry.start, entry.sectors);
  chain(dirStart, dirSectors);
  for (let i = 0; i < fatSectors; i++) fat[fatStart + i] = FAT_SECTOR;
  for (let i = 0; i < difatSectors; i++) fat[difatStart + i] = DIFAT_SECTOR;

  // The directory. A storage's children are linked as one chain of right siblings.
  const directory = new Uint8Array(dirSectors * sectorSize);
  const view = new DataView(directory.buffer);
  const set = (id, entry) => {
    const at = id * 128;
    const name = entry?.name ?? '';
    for (let c = 0; c < name.length; c++) view.setUint16(at + c * 2, name.charCodeAt(c), true);
    view.setUint16(at + 64, entry ? (name.length + 1) * 2 : 0, true);
    directory[at + 66] = entry?.type ?? 0;
    directory[at + 67] = 1;
    view.setUint32(at + 68, entry?.left ?? FREE, true);
    view.setUint32(at + 72, entry?.right ?? FREE, true);
    view.setUint32(at + 76, entry?.treeRoot ?? FREE, true);
    view.setUint32(at + 116, entry?.type === 2 ? entry.start : 0, true);
    view.setUint32(at + 120, entry?.type === 2 ? entry.size : 0, true);
  };
  for (let id = 0; id < dirSectors * (sectorSize / 128); id++) {
    set(id, entries[id]);
    if (!entries[id]) {
      view.setUint32(id * 128 + 68, FREE, true);
      view.setUint32(id * 128 + 72, FREE, true);
      view.setUint32(id * 128 + 76, FREE, true);
    }
  }

  // The header, padded to a whole sector.
  const header = new Uint8Array(sectorSize);
  const h = new DataView(header.buffer);
  header.set(CFB_MAGIC);
  h.setUint16(24, 0x3e, true);
  h.setUint16(26, version, true);
  h.setUint16(28, 0xfffe, true);
  h.setUint16(30, version === 4 ? 12 : 9, true);
  h.setUint16(32, 6, true);
  h.setUint32(40, version === 4 ? dirSectors : 0, true);
  h.setUint32(44, fatSectors, true);
  h.setUint32(48, dirStart, true);
  h.setUint32(56, 4096, true);
  h.setUint32(60, END, true);
  h.setUint32(68, difatSectors > 0 ? difatStart : END, true);
  h.setUint32(72, difatSectors, true);
  for (let i = 0; i < 109; i++) h.setUint32(76 + i * 4, i < fatSectors ? fatStart + i : FREE, true);

  const fatBytes = new Uint8Array(fat.buffer);
  const difat = new Uint8Array(difatSectors * sectorSize);
  const d = new DataView(difat.buffer);
  for (let s = 0; s < difatSectors; s++) {
    for (let i = 0; i < perSector - 1; i++) {
      const index = 109 + s * (perSector - 1) + i;
      d.setUint32(s * sectorSize + i * 4, index < fatSectors ? fatStart + index : FREE, true);
    }
    d.setUint32(s * sectorSize + sectorSize - 4, s + 1 < difatSectors ? difatStart + s + 1 : END, true);
  }
  const file = concat([header, ...data, directory, fatBytes, difat]);
  file.layout = { sectorSize, dirStart, fatStart, difatStart, total };
  return file;
}

const wordStream = (size = 4096) => ({ name: 'WordDocument', size, head: [0xec, 0xa5] });

/** A Word 97-2003 document: Word's streams, as Word lays them out. */
const docFile = (options = {}) =>
  compoundFile({
    tree: [wordStream(), { name: '1Table', size: 4096 }, { name: '\u0005SummaryInformation', size: 4096 }],
    ...options,
  });
const xlsFile = (options = {}) =>
  compoundFile({ tree: [{ name: 'Workbook', size: 4096 }, { name: '\u0005SummaryInformation', size: 4096 }], ...options });
const oldXlsFile = (options = {}) =>
  compoundFile({ tree: [{ name: 'Book', size: 4096 }], ...options });
const pptFile = (options = {}) =>
  compoundFile({
    tree: [{ name: 'PowerPoint Document', size: 4096 }, { name: 'Current User', size: 4096 }, { name: 'Pictures', size: 4096 }],
    ...options,
  });

// Genuine Word documents: what a plan of each document type must be.
const DOC = docFile();
const DOCX_BYTES = docxFile();

/** Every accepted plan type, with the bytes that prove it. */
const TYPES = [
  { name: 'JPEG image', contentType: 'image/jpeg', ext: 'jpg', kind: 'image', mediaType: 'image', bytes: JPEG },
  { name: 'PNG image', contentType: 'image/png', ext: 'png', kind: 'image', mediaType: 'image', bytes: PNG },
  { name: 'WebP image', contentType: 'image/webp', ext: 'webp', kind: 'image', mediaType: 'image', bytes: WEBP },
  { name: 'PDF', contentType: 'application/pdf', ext: 'pdf', kind: 'document', mediaType: 'pdf', bytes: PDF },
  { name: 'DOC', contentType: 'application/msword', ext: 'doc', kind: 'document', mediaType: 'unknown', bytes: DOC },
  { name: 'DOCX', contentType: DOCX, ext: 'docx', kind: 'document', mediaType: 'unknown', bytes: DOCX_BYTES },
];
const RULES = Object.fromEntries(TYPES.map((t) => [t.contentType, {
  ext: t.ext, kind: t.mediaType, max: t.kind === 'image' ? 10 * MIB : 25 * MIB,
}]));

const PARENTS = {
  offer: {
    prefix: '/offer-plan', idField: 'offerId', segment: 'offer-plans', live: OFFER_A, other: OFFER_A2,
    deleted: OFFER_A_DELETED, foreign: OFFER_B, notFound: 'offer_not_found', table: 'offers',
    sweepVar: 'OFFER_MEDIA_SWEEP_MODE', sweep: runOfferPlanSweeps, deletedKey: 'deletedOfferPlans',
  },
  owner: {
    prefix: '/owner-plan', idField: 'ownerRecordId', segment: 'owner-plans', live: OWNER_A, other: OWNER_A2,
    deleted: OWNER_A_DELETED, foreign: OWNER_B, notFound: 'owner_not_found', table: 'owners',
    sweepVar: 'OWNER_MEDIA_SWEEP_MODE', sweep: runOwnerPlanSweeps, deletedKey: 'deletedOwnerPlans',
  },
};

/** The eight routes, as [method, path-builder]. */
const ROUTES = Object.values(PARENTS).flatMap((p) => [
  ['POST', `${p.prefix}/authorize`, p],
  ['POST', `${p.prefix}/confirm`, p],
  ['GET', `${p.prefix}?${p.idField}=${p.live}`, p],
  ['POST', `${p.prefix}/remove`, p],
]);

// --- fakes -----------------------------------------------------------------

function json(value, status = 200) {
  return new Response(JSON.stringify(value), { status, headers: { 'Content-Type': 'application/json' } });
}

function matches(value, filter) {
  if (filter.startsWith('not.')) return !matches(value, filter.slice(4));
  if (filter === 'is.null') return value == null;
  if (filter.startsWith('eq.')) return String(value) === filter.slice(3);
  if (filter.startsWith('like.')) {
    const regex = `^${filter.slice(5).split('*').map((s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('.*')}$`;
    return new RegExp(regex).test(String(value ?? ''));
  }
  if (filter.startsWith('lt.')) return value != null && Date.parse(value) < Date.parse(filter.slice(3));
  throw new Error(`Unsupported fake filter ${filter}`);
}

function filtered(rows, search) {
  return rows.filter((row) => [...search.entries()].every(([key, value]) =>
    ['select', 'order', 'limit', 'offset'].includes(key) || key.includes('.') || matches(row[key], value)));
}

class FakeBucket {
  objects = new Map();
  failDeleteKey = null;
  deleted = [];
  put(key, bytes, contentType) { this.objects.set(key, { bytes, contentType }); }
  async head(key) {
    const value = this.objects.get(key);
    return value ? { size: value.bytes.length, httpMetadata: { contentType: value.contentType } } : null;
  }
  async get(key, { range } = {}) {
    const value = this.objects.get(key);
    if (!value) return null;
    const bytes = range ? value.bytes.slice(range.offset, range.offset + range.length) : value.bytes;
    return { arrayBuffer: async () => bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) };
  }
  async delete(keys) {
    for (const key of Array.isArray(keys) ? keys : [keys]) {
      if (key === this.failDeleteKey) throw new Error('simulated R2 delete failure');
      this.deleted.push(key);
      this.objects.delete(key);
    }
  }
  async list({ prefix = '' } = {}) {
    return { objects: [...this.objects.keys()].filter((k) => k.startsWith(prefix)).map((key) => ({ key })), truncated: false };
  }
}

class FakeSupabase {
  constructor() {
    const parent = (id, owner, deletedAt = null) => ({ id, owner_id: owner, deleted_at: deletedAt, plan_media_id: null });
    this.offers = [
      parent(OFFER_A, ALICE), parent(OFFER_A2, ALICE), parent(OFFER_A_DELETED, ALICE, null), parent(OFFER_B, BOB),
    ];
    this.owners = [
      parent(OWNER_A, ALICE), parent(OWNER_A2, ALICE), parent(OWNER_A_DELETED, ALICE, null), parent(OWNER_B, BOB),
    ];
    this.media = [];
    this.calls = [];
    this.rpcCalls = [];
    this.activeSessionAllowed = true;
    this.sessionCheckStatus = 200;
    this.deletionJob = false;
    this.deletionJobsStatus = 200;
  }

  fetch = async (url, init = {}) => {
    const parsed = new URL(url);
    const method = init.method ?? 'GET';
    this.calls.push(parsed.pathname);
    if (parsed.pathname === '/auth/v1/user') {
      const token = init.headers?.Authorization;
      return token === 'Bearer token-a' ? json({ id: ALICE })
        : token === 'Bearer token-b' ? json({ id: BOB }) : json({}, 401);
    }
    if (parsed.pathname === '/rest/v1/rpc/is_current_app_session') {
      return this.sessionCheckStatus === 200 ? json(this.activeSessionAllowed) : json({}, this.sessionCheckStatus);
    }
    assert.equal(init.headers?.apikey, SECRET);
    const { pathname, searchParams: search } = parsed;
    const body = init.body ? JSON.parse(init.body) : null;
    const returning = String(init.headers?.Prefer).includes('return=representation');
    if (pathname === '/rest/v1/account_deletion_jobs') {
      if (this.deletionJobsStatus !== 200) return json({ message: 'unavailable' }, this.deletionJobsStatus);
      return json(this.deletionJob ? [{ user_id: ALICE, bucket: BUCKET, status: 'pending' }] : []);
    }
    for (const [table, rows] of [['offers', this.offers], ['owners', this.owners]]) {
      if (pathname === `/rest/v1/${table}`) {
        const matched = filtered(rows, search);
        if (method === 'GET') return json(matched);
        if (method === 'PATCH') {
          for (const row of matched) Object.assign(row, body);
          return json(returning ? matched : []);
        }
      }
    }
    if (pathname === '/rest/v1/media_objects') {
      if (method === 'POST') {
        if (this.media.some((m) => m.id === body.id)) return json({ code: '23505' }, 409);
        const at = new Date().toISOString();
        this.media.push({ ...body, created_at: at, updated_at: at });
        return json([], 201);
      }
      const matched = filtered(this.media, search);
      if (method === 'GET') return json(matched);
      if (method === 'PATCH') {
        if (this.beforeMediaPatch) {
          const hook = this.beforeMediaPatch;
          this.beforeMediaPatch = null;
          hook();
        }
        const again = filtered(this.media, search);
        for (const row of again) Object.assign(row, body, { updated_at: new Date().toISOString() });
        return json(returning ? again : []);
      }
      if (method === 'DELETE') {
        for (const row of matched) this.media.splice(this.media.indexOf(row), 1);
        return json(returning ? matched : []);
      }
    }
    const rpc = /^\/rest\/v1\/rpc\/(confirm|remove)_(offer|owner)_plan(?:_upload)?$/.exec(pathname);
    if (rpc) {
      this.rpcCalls.push({ fn: rpc[1], kind: rpc[2], ...body });
      try {
        return json([this.planRpc(rpc[2], rpc[1], body)]);
      } catch (_) {
        return json({ code: 'P0001', message: 'raised' }, 400);
      }
    }
    throw new Error(`Unexpected fake API call ${method} ${pathname}`);
  };

  /** The SQL functions of the migration, as a model. */
  planRpc(kind, fn, p) {
    const parents = kind === 'offer' ? this.offers : this.owners;
    const parentId = kind === 'offer' ? p.p_offer_id : p.p_owner_record_id;
    const segment = kind === 'offer' ? 'offer-plans' : 'owner-plans';
    const parent = parents.find((x) => x.id === parentId && x.owner_id === p.p_user_id);
    if (!parent || parent.deleted_at) return { outcome: `${kind}_not_found` };
    const current = parent.plan_media_id ?? null;
    const expected = p.p_expected_media_id ?? null;
    const prefix = `profiles/${p.p_user_id}/${segment}/${parent.id}/`;
    if (fn === 'remove') {
      if (!current) return { outcome: 'already_removed' };
      if (current !== expected) return { outcome: 'stale_replacement' };
      const old = this.media.find((m) => m.id === current);
      if (!old || old.status !== 'ready' || old.bucket !== p.p_bucket || !old.object_key.startsWith(prefix)) {
        return { outcome: 'invalid_state' };
      }
      parent.plan_media_id = null;
      old.status = 'pending_delete';
      return { outcome: 'removed', previous_media_id: current };
    }
    const rules = RULES[p.p_observed_content_type];
    if (!rules || !Number.isInteger(p.p_observed_size) || p.p_observed_size < 1 || p.p_observed_size > rules.max) {
      throw new Error('raised');
    }
    const media = this.media.find((m) => m.id === p.p_media_id && m.owner_id === p.p_user_id && m.bucket === p.p_bucket);
    if (!media || media.object_key !== `${prefix}${media.id}.${rules.ext}` ||
        media.content_type !== p.p_observed_content_type || media.media_type !== rules.kind) {
      return { outcome: 'media_not_found' };
    }
    if (current === media.id && media.status === 'ready') return { outcome: 'already_attached' };
    if (current !== expected) return { outcome: 'stale_replacement' };
    if (media.status !== 'pending_upload') return { outcome: 'invalid_status' };
    if (current) {
      const old = this.media.find((m) => m.id === current);
      if (!old || old.status !== 'ready' || old.bucket !== p.p_bucket || !old.object_key.startsWith(prefix)) {
        return { outcome: 'invalid_state' };
      }
    }
    Object.assign(media, { status: 'ready', size_bytes: p.p_observed_size, content_type: p.p_observed_content_type });
    parent.plan_media_id = media.id;
    if (current) this.media.find((m) => m.id === current).status = 'pending_delete';
    return { outcome: 'attached', previous_media_id: current };
  }
}

let state;
let originalFetch;
beforeEach(() => {
  const supabase = new FakeSupabase();
  const bucket = new FakeBucket();
  state = {
    supabase,
    bucket,
    env: {
      SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_test', SUPABASE_SECRET_KEY: SECRET,
      R2_BUCKET_NAME: BUCKET, R2_S3_ENDPOINT: 'https://r2.test.example.com',
      R2_ACCESS_KEY_ID: 'test-access', R2_SECRET_ACCESS_KEY: 'test-secret', MEDIA_BUCKET: bucket,
    },
  };
  originalFetch = globalThis.fetch;
  globalThis.fetch = supabase.fetch;
});
afterEach(() => { globalThis.fetch = originalFetch; });

async function call(path, user = ALICE, body, { token } = {}) {
  const method = body === undefined ? 'GET' : 'POST';
  const headers = { 'Content-Type': 'application/json' };
  const bearer = token === undefined ? (user === ALICE ? 'token-a' : user === BOB ? 'token-b' : null) : token;
  if (bearer) headers.Authorization = `Bearer ${bearer}`;
  const response = await worker.fetch(new Request(`https://worker.test${path}`, {
    method, headers, ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  }), state.env, {});
  return { status: response.status, body: await response.json(), headers: response.headers };
}

const media = (id) => state.supabase.media.find((m) => m.id === id);
const parentRow = (kind, id) => (kind === 'offer' ? state.supabase.offers : state.supabase.owners).find((p) => p.id === id);

async function authorize(kind, {
  parentId = PARENTS[kind].live, expected = null, type = TYPES[3], length, mediaObjectId = crypto.randomUUID(),
  user = ALICE, fileName, contentType,
} = {}) {
  const p = PARENTS[kind];
  const result = await call(`${p.prefix}/authorize`, user, {
    [p.idField]: parentId, expectedMediaId: expected, mediaObjectId,
    contentType: contentType === undefined ? type.contentType : contentType,
    contentLength: length === undefined ? type.bytes.length : length,
    ...(fileName ? { originalFileName: fileName } : {}),
  });
  return { ...result, mediaObjectId, key: media(mediaObjectId)?.object_key };
}

function confirmRequest(kind, mediaObjectId, { parentId = PARENTS[kind].live, expected = null, user = ALICE } = {}) {
  const p = PARENTS[kind];
  return call(`${p.prefix}/confirm`, user, { [p.idField]: parentId, mediaObjectId, expectedMediaId: expected });
}

/** authorize → private PUT → confirm, as the app does. */
async function uploadPlan(kind, {
  parentId = PARENTS[kind].live, expected = null, type = TYPES[3], bytes = type.bytes, user = ALICE, fileName,
} = {}) {
  const auth = await authorize(kind, { parentId, expected, type, length: bytes.length, user, fileName });
  assert.equal(auth.status, 200, JSON.stringify(auth.body));
  state.bucket.put(auth.key, bytes, type.contentType);
  const confirmed = await confirmRequest(kind, auth.mediaObjectId, { parentId, expected, user });
  return { ...auth, confirmed };
}

function removeRequest(kind, { parentId = PARENTS[kind].live, expected = null, mediaObjectId, user = ALICE } = {}) {
  const p = PARENTS[kind];
  return call(`${p.prefix}/remove`, user, {
    [p.idField]: parentId, expectedMediaId: expected, ...(mediaObjectId ? { mediaObjectId } : {}),
  });
}

const getPlan = (kind, parentId = PARENTS[kind].live, user = ALICE) =>
  call(`${PARENTS[kind].prefix}?${PARENTS[kind].idField}=${parentId}`, user);

for (const kind of ['offer', 'owner']) {
  const p = PARENTS[kind];
  const title = kind === 'offer' ? 'Offer' : 'Owner';

  test(`${kind}: authorize reserves a private plan key for every accepted type and never returns the key`, async () => {
    for (const type of TYPES) {
      const result = await authorize(kind, { type, fileName: `plan.${type.ext}` });
      assert.equal(result.status, 200, `${type.name}: ${JSON.stringify(result.body)}`);
      assert.equal(result.body.status, 'pending');
      assert.equal(result.body.mediaObjectId, result.mediaObjectId);
      assert.equal(result.body.mediaType, type.mediaType);
      assert.match(result.body.presignedUrl, /^https:\/\/r2\.test\.example\.com\//);
      assert.equal(result.body.objectKey, undefined, 'the storage key is never part of a plan answer');
      // The signed URL is the transport and necessarily names the object; nothing else may.
      assert.ok(!JSON.stringify({ ...result.body, presignedUrl: null }).includes('profiles/'));
      const row = media(result.mediaObjectId);
      assert.equal(row.object_key, `profiles/${ALICE}/${p.segment}/${p.live}/${result.mediaObjectId}.${type.ext}`);
      assert.equal(row.bucket, BUCKET);
      assert.equal(row.media_type, type.mediaType);
      assert.equal(row.content_type, type.contentType);
      assert.equal(row.status, 'pending_upload');
      assert.equal(row.original_file_name, `plan.${type.ext}`);
      assert.equal(parentRow(kind, p.live).plan_media_id, null, 'nothing is attached before confirm');
      // Withdraw it, so the next type is not a fourth waiting upload.
      assert.equal((await removeRequest(kind, { mediaObjectId: result.mediaObjectId })).status, 200);
    }
  });

  test(`${kind}: authorize refuses unsupported types and sizes, and malformed requests`, async () => {
    const refusedTypes = ['image/gif', 'image/svg+xml', 'image/heic', 'application/zip', 'application/x-rar-compressed',
      'application/x-msdownload', 'application/vnd.android.package-archive', 'application/octet-stream',
      'application/vnd.ms-excel', 'application/acad', 'image/vnd.dwg', 'video/mp4', 'text/html', '', null];
    for (const contentType of refusedTypes) {
      const result = await authorize(kind, { contentType, length: 100 });
      assert.equal(result.status, 400, String(contentType));
      assert.equal(result.body.code, 'unsupported_media_type', String(contentType));
    }
    const big = await authorize(kind, { type: TYPES[3], length: 25 * MIB + 1 });
    assert.deepEqual([big.status, big.body.code], [400, 'document_too_large']);
    const bigDoc = await authorize(kind, { type: TYPES[5], length: 25 * MIB + 1 });
    assert.deepEqual([bigDoc.status, bigDoc.body.code], [400, 'document_too_large']);
    const bigImage = await authorize(kind, { type: TYPES[0], length: 10 * MIB + 1 });
    assert.deepEqual([bigImage.status, bigImage.body.code], [400, 'image_too_large']);
    for (const length of [0, -1, 1.5, '100', null]) {
      const result = await authorize(kind, { type: TYPES[3], length });
      assert.equal(result.status, 400, String(length));
    }
    // The limits are inclusive.
    for (const [type, length] of [[TYPES[3], 25 * MIB], [TYPES[4], 25 * MIB], [TYPES[5], 25 * MIB], [TYPES[0], 10 * MIB]]) {
      const result = await authorize(kind, { type, length });
      assert.equal(result.status, 200, `${type.name} at its limit`);
      assert.equal((await removeRequest(kind, { mediaObjectId: result.mediaObjectId })).status, 200);
    }
    const missing = await call(`${p.prefix}/authorize`, ALICE, {
      [p.idField]: p.live, contentType: 'application/pdf', contentLength: 10,
    });
    assert.deepEqual([missing.status, missing.body.code], [400, 'invalid_request']);
    const malformed = await call(`${p.prefix}/authorize`, ALICE, {
      [p.idField]: 'not-a-uuid', expectedMediaId: null, contentType: 'application/pdf', contentLength: 10,
    });
    assert.equal(malformed.status, 400);
    const badExpected = await call(`${p.prefix}/authorize`, ALICE, {
      [p.idField]: p.live, expectedMediaId: 'nope', contentType: 'application/pdf', contentLength: 10,
    });
    assert.equal(badExpected.status, 400);
  });

  test(`${kind}: every type is uploaded, confirmed, listed and read through a short-lived signed link`, async () => {
    for (const type of TYPES) {
      const parentId = p.live;
      const current = parentRow(kind, parentId).plan_media_id;
      const up = await uploadPlan(kind, { type, expected: current, fileName: `site plan.${type.ext}` });
      assert.equal(up.confirmed.status, 200, `${type.name}: ${JSON.stringify(up.confirmed.body)}`);
      assert.equal(up.confirmed.body[p.idField], parentId);
      assert.equal(up.confirmed.body.mediaObjectId, up.mediaObjectId);
      assert.equal(parentRow(kind, parentId).plan_media_id, up.mediaObjectId);
      assert.equal(media(up.mediaObjectId).status, 'ready');
      assert.equal(media(up.mediaObjectId).size_bytes, type.bytes.length);

      const listed = await getPlan(kind);
      assert.equal(listed.status, 200);
      assert.equal(listed.headers.get('cache-control'), 'no-store');
      assert.equal(listed.body[p.idField], parentId);
      assert.equal(listed.body.plan.mediaObjectId, up.mediaObjectId);
      assert.equal(listed.body.plan.contentType, type.contentType);
      assert.equal(listed.body.plan.kind, type.kind);
      assert.equal(listed.body.plan.fileName, `site plan.${type.ext}`);
      assert.equal(listed.body.plan.sizeBytes, type.bytes.length);
      assert.match(listed.body.plan.url, /^https:\/\/r2\.test\.example\.com\//);
      assert.equal(listed.body.expiresInSeconds, 900);
      assert.ok(
        !JSON.stringify({ ...listed.body, plan: { ...listed.body.plan, url: null } }).includes('profiles/'),
        'the key is revealed only inside the signed URL',
      );
    }
    assert.ok(!JSON.stringify(state.supabase.media).includes('X-Amz'), 'no signed URL is ever stored');
    assert.ok(!JSON.stringify(state.supabase.offers).includes('https://'));
  });

  test(`${kind}: confirm proves the real bytes, never the authorized type alone`, async () => {
    // An ISO-BMFF "heic" brand: the shared image detector knows it, plans refuse it.
    const heicAsJpeg = pad([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63]);
    const cases = [
      ['PDF bytes under a JPEG authorization', TYPES[0], PDF],
      ['JPEG bytes under a PDF authorization', TYPES[3], JPEG],
      ['a Windows executable under a DOCX authorization', TYPES[5], pad([0x4d, 0x5a])],
      ['an Android package (ZIP) under a DOCX authorization', TYPES[5], zipEntry('AndroidManifest.xml')],
      ['an archive whose first entry is no Office part', TYPES[5], zipEntry('notes.txt')],
      ['an encrypted ZIP entry under a DOCX authorization', TYPES[5], zipEntry('[Content_Types].xml', 1)],
      ['DOC bytes under a DOCX authorization', TYPES[5], DOC],
      ['DOCX bytes under a DOC authorization', TYPES[4], DOCX_BYTES],
      ['SVG text under a PNG authorization', TYPES[1], new TextEncoder().encode('<svg xmlns="http://www.w3.org/2000/svg"/>')],
      ['HEIC bytes under a JPEG authorization', TYPES[0], heicAsJpeg],
      ['plain text under a PDF authorization', TYPES[3], new TextEncoder().encode('just some text, not a PDF at all')],
    ];
    for (const [label, type, bytes] of cases) {
      const auth = await authorize(kind, { type, length: bytes.length });
      assert.equal(auth.status, 200, label);
      state.bucket.put(auth.key, bytes, type.contentType);
      const result = await confirmRequest(kind, auth.mediaObjectId);
      assert.deepEqual([result.status, result.body.code], [422, 'media_type_mismatch'], label);
      assert.equal(media(auth.mediaObjectId).status, 'failed', label);
      assert.equal(state.bucket.objects.has(auth.key), false, `${label}: the rejected bytes are dropped`);
      assert.equal(parentRow(kind, p.live).plan_media_id, null, label);
    }
    // R2's own recorded content type must agree with what was authorized.
    const auth = await authorize(kind, { type: TYPES[3] });
    state.bucket.put(auth.key, PDF, 'application/octet-stream');
    const mislabeled = await confirmRequest(kind, auth.mediaObjectId);
    assert.deepEqual([mislabeled.status, mislabeled.body.code], [422, 'media_type_mismatch']);
    assert.equal(state.supabase.rpcCalls.length, 0, 'a refused upload never reaches the database function');
  });

  // --- DOC / DOCX are proven to be Word's own, not just an Office container ---

  const MAIN = 'word/document.xml';
  const withAReadLog = () => {
    const reads = [];
    const original = state.bucket.get.bind(state.bucket);
    state.bucket.get = async (key, options) => {
      reads.push(options?.range);
      return original(key, options);
    };
    return { reads, restore: () => { state.bucket.get = original; } };
  };

  test(`${kind}: confirm proves a DOC or DOCX is Word's own, never another Office file in the same container`, async () => {
    // What an owner could upload by renaming an Excel or PowerPoint file, and the
    // packages and compound files built to look like Word's.
    const workbookWithWordPart = ooxmlPackage({
      part: 'xl/workbook.xml',
      contentType: XLSX_MAIN,
      types: `<Types><Override PartName="/xl/workbook.xml" ContentType="${XLSX_MAIN}"/><Override PartName="/${MAIN}" ContentType="${WORD_MAIN}"/></Types>`,
      extra: [{ name: MAIN, data: WORD_BODY }],
    });
    const wordOnlyInAComment = docxFile({ types: `<Types><!-- <Override PartName="/${MAIN}" ContentType="${WORD_MAIN}"/> --></Types>` });
    const cases = [
      ['an XLSX renamed .docx', TYPES[5], xlsxFile()],
      ['a PPTX renamed .docx', TYPES[5], pptxFile()],
      ['a macro-enabled document (docm) renamed .docx', TYPES[5],
        docxFile({ types: contentTypesXml(MAIN, 'application/vnd.ms-word.document.macroEnabled.main+xml') })],
      ['a Word template (dotx) renamed .docx', TYPES[5],
        docxFile({ types: contentTypesXml(MAIN, 'application/vnd.openxmlformats-officedocument.wordprocessingml.template.main+xml') })],
      ['a workbook that carries a Word part', TYPES[5], workbookWithWordPart],
      ['a Word content type only an XML comment holds', TYPES[5], wordOnlyInAComment],
      ['a workbook as Microsoft\'s packaging library writes one', TYPES[5], netPackagedFile('xl/workbook.xml', XLSX_MAIN)],
      ['a presentation as Microsoft\'s packaging library writes one', TYPES[5], netPackagedFile('ppt/presentation.xml', PPTX_MAIN)],
      ['an XLS renamed .doc', TYPES[4], xlsFile()],
      ['an Excel 5/95 workbook renamed .doc', TYPES[4], oldXlsFile()],
      ['a PPT renamed .doc', TYPES[4], pptFile()],
      ['a compound file with Word and Excel streams side by side', TYPES[4],
        compoundFile({ tree: [wordStream(), { name: 'Workbook', size: 4096 }] })],
      ['a compound file with no Word stream at all', TYPES[4], compoundFile({ tree: [{ name: 'Contents', size: 4096 }] })],
    ];
    for (const [label, type, bytes] of cases) {
      const auth = await authorize(kind, { type, length: bytes.length });
      assert.equal(auth.status, 200, label);
      state.bucket.put(auth.key, bytes, type.contentType);
      const result = await confirmRequest(kind, auth.mediaObjectId);
      assert.deepEqual([result.status, result.body.code], [422, 'media_type_mismatch'], label);
      assert.equal(media(auth.mediaObjectId).status, 'failed', label);
      assert.equal(state.bucket.objects.has(auth.key), false, `${label}: the rejected bytes are dropped`);
      assert.equal(parentRow(kind, p.live).plan_media_id, null, label);
    }
    assert.equal(state.supabase.rpcCalls.length, 0, 'a refused upload never reaches the database function');
  });

  test(`${kind}: a masquerading replacement is refused and the plan the record has survives`, async () => {
    const original = await uploadPlan(kind, { type: TYPES[3] });
    assert.equal(original.confirmed.status, 200);
    for (const [type, bytes] of [[TYPES[5], xlsxFile()], [TYPES[4], pptFile()]]) {
      const bad = await uploadPlan(kind, { type, bytes, expected: original.mediaObjectId });
      assert.deepEqual([bad.confirmed.status, bad.confirmed.body.code], [422, 'media_type_mismatch']);
      assert.equal(parentRow(kind, p.live).plan_media_id, original.mediaObjectId);
      assert.equal(media(original.mediaObjectId).status, 'ready');
      assert.equal(state.bucket.objects.has(original.key), true);
    }
  });

  test(`${kind}: genuine Word documents are accepted in the layouts Word and its converters write`, async () => {
    const stored = { method: 'store' };
    const genuine = [
      ['a DOCX', TYPES[5], DOCX_BYTES],
      ['a DOCX whose entries state their sizes after the data', TYPES[5], docxFile({ entries: [
        { name: '[Content_Types].xml', data: contentTypesXml(MAIN, WORD_MAIN), descriptor: true },
        { name: '_rels/.rels', data: relationshipsXml(MAIN), descriptor: true },
        { name: MAIN, data: WORD_BODY, descriptor: true },
      ] })],
      ['a DOCX with stored (uncompressed) parts', TYPES[5], docxFile({ entries: [
        { name: '[Content_Types].xml', data: contentTypesXml(MAIN, WORD_MAIN), ...stored },
        { name: '_rels/.rels', data: relationshipsXml(MAIN), ...stored },
        { name: MAIN, data: WORD_BODY, ...stored },
      ] })],
      ['a DOCX with an archive comment', TYPES[5], docxFile({ archive: { comment: 'x'.repeat(4000) } })],
      ['a DOCX under the strict Open XML namespaces', TYPES[5],
        docxFile({ rels: relationshipsXml(MAIN, 'http://purl.oclc.org/ooxml/officeDocument/relationships/officeDocument') })],
      ['a DOCX as Microsoft\'s packaging library writes it (typed by the default for xml)', TYPES[5], netPackagedFile(MAIN, WORD_MAIN)],
      ['a DOC', TYPES[4], DOC],
      ['a DOC in 4096-byte sectors', TYPES[4], docFile({ version: 4 })],
      ['a DOC with an Excel object embedded in it', TYPES[4], compoundFile({ tree: [
        wordStream(),
        { name: 'ObjectPool', children: [{ name: '_1234567890', children: [{ name: 'Workbook', size: 4096 }] }] },
      ] })],
    ];
    let current = null;
    for (const [label, type, bytes] of genuine) {
      const up = await uploadPlan(kind, { type, bytes, expected: current });
      assert.equal(up.confirmed.status, 200, `${label}: ${JSON.stringify(up.confirmed.body)}`);
      assert.equal(parentRow(kind, p.live).plan_media_id, up.mediaObjectId, label);
      current = up.mediaObjectId;
    }
  });

  test(`${kind}: proving Word reads a few ranges of a large file, never the whole of it`, async () => {
    const largeDocx = docxFile({ extra: [{ name: 'word/media/photo.jpg', data: new Uint8Array(6 * MIB).fill(7), method: 'store' }] });
    // A directory placed after 8 MiB of data needs DIFAT sectors to be found.
    const largeDoc = docFile({ tree: [wordStream(), { name: '1Table', size: 4096 }, { name: 'Data', size: 8 * MIB }] });
    let current = null;
    for (const [label, type, bytes] of [['DOCX', TYPES[5], largeDocx], ['DOC', TYPES[4], largeDoc]]) {
      assert.ok(bytes.length > 5 * MIB, label);
      const log = withAReadLog();
      const up = await uploadPlan(kind, { type, bytes, expected: current });
      log.restore();
      assert.equal(up.confirmed.status, 200, `${label}: ${JSON.stringify(up.confirmed.body)}`);
      current = up.mediaObjectId;
      const proof = log.reads.filter((range) => !(range.offset === 0 && range.length === 64));
      const bytesRead = proof.reduce((sum, range) => sum + range.length, 0);
      assert.ok(proof.length >= 2 && proof.length <= 12, `${label}: ${proof.length} reads`);
      assert.ok(bytesRead < 200 * 1024, `${label}: ${bytesRead} bytes read of ${bytes.length}`);
    }
  });

  test(`${kind}: an image or a PDF is read exactly as before: its signature and nothing else`, async () => {
    let current = null;
    for (const type of [TYPES[0], TYPES[1], TYPES[2], TYPES[3]]) {
      const log = withAReadLog();
      const up = await uploadPlan(kind, { type, expected: current });
      log.restore();
      assert.equal(up.confirmed.status, 200, type.name);
      assert.deepEqual(log.reads, [{ offset: 0, length: 64 }], type.name);
      current = up.mediaObjectId;
    }
  });

  test(`${kind}: a storage error while proving Word is retried, never taken for a bad file`, async () => {
    const auth = await authorize(kind, { type: TYPES[5], length: DOCX_BYTES.length });
    state.bucket.put(auth.key, DOCX_BYTES, DOCX);
    const original = state.bucket.get.bind(state.bucket);
    let reads = 0;
    // The signature is the first read; the proof's own reads follow it.
    state.bucket.get = async (key, options) => {
      reads += 1;
      if (reads === 3) throw new Error('simulated storage outage');
      return original(key, options);
    };
    const failed = await confirmRequest(kind, auth.mediaObjectId);
    assert.equal(failed.status, 500);
    assert.notEqual(failed.body.code, 'media_type_mismatch');
    assert.equal(media(auth.mediaObjectId).status, 'pending_upload', 'the upload is neither rejected nor attached');
    assert.equal(state.bucket.objects.has(auth.key), true, 'the bytes are kept for the retry');
    assert.equal(parentRow(kind, p.live).plan_media_id, null);

    state.bucket.get = original;
    const retried = await confirmRequest(kind, auth.mediaObjectId);
    assert.equal(retried.status, 200, JSON.stringify(retried.body));
    assert.equal(parentRow(kind, p.live).plan_media_id, auth.mediaObjectId);
  });

  test(`${kind}: confirm enforces the real object size, the limits are inclusive`, async () => {
    const oversized = new Uint8Array(25 * MIB + 1);
    oversized.set(PDF);
    const auth = await authorize(kind, { type: TYPES[3], length: 100 });
    state.bucket.put(auth.key, oversized, 'application/pdf');
    const tooBig = await confirmRequest(kind, auth.mediaObjectId);
    assert.deepEqual([tooBig.status, tooBig.body.code], [422, 'document_too_large']);
    assert.equal(media(auth.mediaObjectId).status, 'failed');
    assert.equal(state.bucket.objects.has(auth.key), false);

    const bigImage = new Uint8Array(10 * MIB + 1);
    bigImage.set(JPEG);
    const imageAuth = await authorize(kind, { type: TYPES[0], length: 100 });
    state.bucket.put(imageAuth.key, bigImage, 'image/jpeg');
    const imageTooBig = await confirmRequest(kind, imageAuth.mediaObjectId);
    assert.deepEqual([imageTooBig.status, imageTooBig.body.code], [422, 'image_too_large']);

    const emptyAuth = await authorize(kind, { type: TYPES[3], length: 100 });
    state.bucket.put(emptyAuth.key, new Uint8Array(0), 'application/pdf');
    const empty = await confirmRequest(kind, emptyAuth.mediaObjectId);
    assert.deepEqual([empty.status, empty.body.code], [422, 'unsupported_media_type']);
    assert.equal(media(emptyAuth.mediaObjectId).status, 'failed');

    const exact = new Uint8Array(25 * MIB);
    exact.set(PDF);
    const exactAuth = await authorize(kind, { type: TYPES[3], length: 25 * MIB });
    state.bucket.put(exactAuth.key, exact, 'application/pdf');
    const accepted = await confirmRequest(kind, exactAuth.mediaObjectId);
    assert.equal(accepted.status, 200, JSON.stringify(accepted.body));
    assert.equal(media(exactAuth.mediaObjectId).size_bytes, 25 * MIB);
  });

  test(`${kind}: a confirm before the bytes arrive is retryable and marks nothing`, async () => {
    const auth = await authorize(kind);
    const early = await confirmRequest(kind, auth.mediaObjectId);
    assert.deepEqual([early.status, early.body.code], [409, 'upload_incomplete']);
    assert.equal(media(auth.mediaObjectId).status, 'pending_upload');
    state.bucket.put(auth.key, PDF, 'application/pdf');
    assert.equal((await confirmRequest(kind, auth.mediaObjectId)).status, 200);
  });

  test(`${kind}: confirm and authorize are idempotent`, async () => {
    const first = await uploadPlan(kind);
    assert.equal(first.confirmed.status, 200);
    const calls = state.supabase.rpcCalls.length;
    const again = await confirmRequest(kind, first.mediaObjectId);
    assert.equal(again.status, 200);
    assert.equal(again.body.alreadyConfirmed, true);
    assert.equal(state.supabase.rpcCalls.length, calls, 'a repeated confirm does not repeat the database work');
    assert.equal(state.supabase.media.length, 1);

    // The response to the first confirm was lost: the app authorizes the same
    // upload again, still believing the slot is empty. It is answered as done.
    const retry = await call(`${p.prefix}/authorize`, ALICE, {
      [p.idField]: p.live, expectedMediaId: null, mediaObjectId: first.mediaObjectId,
      contentType: 'application/pdf', contentLength: PDF.length,
    });
    assert.equal(retry.status, 200);
    assert.equal(retry.body.status, 'ready');
    assert.equal(retry.body.presignedUrl, undefined);
    assert.equal(state.supabase.media.length, 1);

    // The same id resumes the same row with a fresh link while pending.
    const pending = await authorize(kind, { expected: first.mediaObjectId });
    const resumed = await call(`${p.prefix}/authorize`, ALICE, {
      [p.idField]: p.live, expectedMediaId: first.mediaObjectId, mediaObjectId: pending.mediaObjectId,
      contentType: 'application/pdf', contentLength: PDF.length,
    });
    assert.equal(resumed.status, 200);
    assert.equal(resumed.body.status, 'pending');
    assert.equal(state.supabase.media.filter((m) => m.id === pending.mediaObjectId).length, 1);
    const differentSize = await call(`${p.prefix}/authorize`, ALICE, {
      [p.idField]: p.live, expectedMediaId: first.mediaObjectId, mediaObjectId: pending.mediaObjectId,
      contentType: 'application/pdf', contentLength: PDF.length + 1,
    });
    assert.deepEqual([differentSize.status, differentSize.body.code], [409, 'idempotency_mismatch']);
    const differentType = await call(`${p.prefix}/authorize`, ALICE, {
      [p.idField]: p.live, expectedMediaId: first.mediaObjectId, mediaObjectId: pending.mediaObjectId,
      contentType: 'image/png', contentLength: PDF.length,
    });
    assert.deepEqual([differentType.status, differentType.body.code], [409, 'idempotency_mismatch']);
  });

  test(`${kind}: an id belonging to another account is never resumed`, async () => {
    const mine = await authorize(kind);
    const theirs = await call(`${p.prefix}/authorize`, BOB, {
      [p.idField]: p.foreign, expectedMediaId: null, mediaObjectId: mine.mediaObjectId,
      contentType: 'application/pdf', contentLength: PDF.length,
    });
    assert.deepEqual([theirs.status, theirs.body.code], [409, 'media_id_conflict']);
    assert.equal(media(mine.mediaObjectId).owner_id, ALICE);
  });

  test(`${kind}: replacement keeps the old plan until the new one is confirmed`, async () => {
    const original = await uploadPlan(kind, { type: TYPES[3] });
    assert.equal(original.confirmed.status, 200);

    // Authorize and upload a candidate, but do not confirm: nothing changed.
    const candidate = await authorize(kind, { expected: original.mediaObjectId, type: TYPES[5], length: DOCX_BYTES.length });
    assert.equal(candidate.status, 200);
    state.bucket.put(candidate.key, DOCX_BYTES, DOCX);
    assert.equal(parentRow(kind, p.live).plan_media_id, original.mediaObjectId);
    assert.equal(media(original.mediaObjectId).status, 'ready');
    assert.equal(state.bucket.objects.has(original.key), true);
    assert.equal((await getPlan(kind)).body.plan.mediaObjectId, original.mediaObjectId);

    // A candidate that fails verification costs nothing.
    const bad = await authorize(kind, { expected: original.mediaObjectId, type: TYPES[0], length: 64 });
    state.bucket.put(bad.key, PDF, 'image/jpeg');
    const refused = await confirmRequest(kind, bad.mediaObjectId, { expected: original.mediaObjectId });
    assert.equal(refused.status, 422);
    assert.equal(parentRow(kind, p.live).plan_media_id, original.mediaObjectId);
    assert.equal(media(original.mediaObjectId).status, 'ready');
    assert.equal(state.bucket.objects.has(original.key), true);

    // An upload that never arrived costs nothing either.
    const missing = await authorize(kind, { expected: original.mediaObjectId, type: TYPES[4], length: 64 });
    const never = await confirmRequest(kind, missing.mediaObjectId, { expected: original.mediaObjectId });
    assert.equal(never.status, 409);
    assert.equal(parentRow(kind, p.live).plan_media_id, original.mediaObjectId);

    // The good candidate switches the plan and retires the old one.
    const switched = await confirmRequest(kind, candidate.mediaObjectId, { expected: original.mediaObjectId });
    assert.equal(switched.status, 200, JSON.stringify(switched.body));
    assert.equal(switched.body.previousMediaId, original.mediaObjectId);
    assert.equal(switched.body.cleanupPending, undefined);
    assert.equal(parentRow(kind, p.live).plan_media_id, candidate.mediaObjectId);
    assert.equal(media(candidate.mediaObjectId).status, 'ready');
    assert.equal(media(original.mediaObjectId).status, 'deleted');
    assert.equal(state.bucket.objects.has(original.key), false);
    assert.equal(state.bucket.objects.has(candidate.key), true);
    assert.equal((await getPlan(kind)).body.plan.contentType, DOCX);
  });

  test(`${kind}: a stale replacement can never overwrite a newer plan`, async () => {
    const original = await uploadPlan(kind, { type: TYPES[3] });
    const a = await authorize(kind, { expected: original.mediaObjectId, type: TYPES[0], length: JPEG.length });
    const b = await authorize(kind, { expected: original.mediaObjectId, type: TYPES[1], length: PNG.length });
    state.bucket.put(a.key, JPEG, 'image/jpeg');
    state.bucket.put(b.key, PNG, 'image/png');
    assert.equal((await confirmRequest(kind, a.mediaObjectId, { expected: original.mediaObjectId })).status, 200);
    const rpcBefore = state.supabase.rpcCalls.length;
    const stale = await confirmRequest(kind, b.mediaObjectId, { expected: original.mediaObjectId });
    assert.deepEqual([stale.status, stale.body.code], [409, 'stale_replacement']);
    assert.equal(state.supabase.rpcCalls.length, rpcBefore, 'a stale confirm is refused before the database function');
    assert.equal(parentRow(kind, p.live).plan_media_id, a.mediaObjectId);
    assert.equal(media(b.mediaObjectId).status, 'pending_upload');
    // A caller that thinks there is no plan cannot start a replacement either.
    const blind = await authorize(kind, { expected: null });
    assert.deepEqual([blind.status, blind.body.code], [409, 'stale_replacement']);
    // And the retired plan can never come back.
    const old = await confirmRequest(kind, original.mediaObjectId, { expected: a.mediaObjectId });
    assert.equal(old.status, 410);
    assert.equal(old.body.code, 'media_removed');
  });

  test(`${kind}: a failed cleanup of the old object is retryable and never undoes the switch`, async () => {
    const original = await uploadPlan(kind, { type: TYPES[0] });
    const next = await authorize(kind, { expected: original.mediaObjectId, type: TYPES[3] });
    state.bucket.put(next.key, PDF, 'application/pdf');
    state.bucket.failDeleteKey = original.key;
    const confirmed = await confirmRequest(kind, next.mediaObjectId, { expected: original.mediaObjectId });
    assert.equal(confirmed.status, 200);
    assert.equal(confirmed.body.cleanupPending, true);
    assert.equal(parentRow(kind, p.live).plan_media_id, next.mediaObjectId);
    assert.equal(media(original.mediaObjectId).status, 'pending_delete');
    assert.equal(media(next.mediaObjectId).status, 'ready');
    state.bucket.failDeleteKey = null;
    state.env[p.sweepVar] = 'on';
    const report = await p.sweep(state.env);
    assert.equal(report.pendingDeletes, 1);
    assert.equal(report.errors, 0);
    assert.equal(media(original.mediaObjectId).status, 'deleted');
    assert.equal(state.bucket.objects.has(original.key), false);
    assert.equal(state.bucket.objects.has(next.key), true);
  });

  test(`${kind}: removal retires the current plan, is idempotent and guarded`, async () => {
    const up = await uploadPlan(kind, { type: TYPES[5] });
    assert.equal(up.confirmed.status, 200);

    const stale = await removeRequest(kind, { expected: crypto.randomUUID() });
    assert.deepEqual([stale.status, stale.body.code], [409, 'stale_replacement']);
    assert.equal(parentRow(kind, p.live).plan_media_id, up.mediaObjectId);
    const stranger = await removeRequest(kind, { expected: up.mediaObjectId, user: BOB });
    assert.deepEqual([stranger.status, stranger.body.code], [404, p.notFound]);

    const removed = await removeRequest(kind, { expected: up.mediaObjectId });
    assert.equal(removed.status, 200);
    assert.equal(removed.body.removed, true);
    assert.equal(removed.body.previousMediaId, up.mediaObjectId);
    assert.equal(removed.headers.get('cache-control'), 'no-store');
    assert.equal(parentRow(kind, p.live).plan_media_id, null);
    assert.equal(media(up.mediaObjectId).status, 'deleted');
    assert.equal(state.bucket.objects.has(up.key), false);
    const after = await getPlan(kind);
    assert.deepEqual([after.status, after.body.plan], [200, null]);

    const again = await removeRequest(kind, { expected: up.mediaObjectId });
    assert.equal(again.status, 200);
    assert.equal(again.body.previousMediaId, null);
  });

  test(`${kind}: cancelling a candidate withdraws it and leaves the current plan`, async () => {
    const original = await uploadPlan(kind, { type: TYPES[3] });
    const candidate = await authorize(kind, { expected: original.mediaObjectId, type: TYPES[0], length: JPEG.length });
    state.bucket.put(candidate.key, JPEG, 'image/jpeg');
    const cancelled = await removeRequest(kind, { expected: original.mediaObjectId, mediaObjectId: candidate.mediaObjectId });
    assert.equal(cancelled.status, 200);
    assert.equal(media(candidate.mediaObjectId).status, 'deleted');
    assert.equal(state.bucket.objects.has(candidate.key), false);
    assert.equal(parentRow(kind, p.live).plan_media_id, original.mediaObjectId);
    assert.equal(media(original.mediaObjectId).status, 'ready');
    const repeat = await removeRequest(kind, { expected: original.mediaObjectId, mediaObjectId: candidate.mediaObjectId });
    assert.equal(repeat.status, 200);
    assert.equal(repeat.body.alreadyRemoved, true);
    // A candidate that was never created is also a quiet success.
    const unknown = await removeRequest(kind, { expected: original.mediaObjectId, mediaObjectId: crypto.randomUUID() });
    assert.equal(unknown.status, 200);
  });

  test(`${kind}: another account and another record are refused everywhere`, async () => {
    const mine = await authorize(kind);
    state.bucket.put(mine.key, PDF, 'application/pdf');
    const cases = [
      ['authorize on a stranger\'s record', () => authorize(kind, { parentId: p.foreign })],
      ['authorize by a stranger on my record', () => authorize(kind, { user: BOB })],
      ['confirm by a stranger', () => confirmRequest(kind, mine.mediaObjectId, { user: BOB })],
      ['remove by a stranger', () => removeRequest(kind, { user: BOB })],
      ['read by a stranger', () => getPlan(kind, p.live, BOB)],
      ['read of a stranger\'s record', () => getPlan(kind, p.foreign)],
      ['an unknown record id', () => getPlan(kind, crypto.randomUUID())],
    ];
    for (const [label, run] of cases) {
      const result = await run();
      assert.deepEqual([result.status, result.body.code], [404, p.notFound], label);
    }
    // My candidate cannot be confirmed against my OTHER record, nor by a
    // stranger who knows its id (their own record is not the key's record).
    const otherRecord = await confirmRequest(kind, mine.mediaObjectId, { parentId: p.other });
    assert.deepEqual([otherRecord.status, otherRecord.body.code], [409, 'media_mismatch']);
    const bobsRecord = await confirmRequest(kind, mine.mediaObjectId, { parentId: p.foreign, user: BOB });
    assert.deepEqual([bobsRecord.status, bobsRecord.body.code], [404, 'media_not_found']);
    const cancelOther = await removeRequest(kind, { parentId: p.other, mediaObjectId: mine.mediaObjectId });
    assert.deepEqual([cancelOther.status, cancelOther.body.code], [409, 'media_mismatch']);
    assert.equal(media(mine.mediaObjectId).status, 'pending_upload');
    assert.equal(state.bucket.objects.has(mine.key), true);
    assert.equal(state.supabase.rpcCalls.length, 0);
  });

  test(`${kind}: a soft-deleted record can neither read nor change its plan`, async () => {
    const up = await uploadPlan(kind, { type: TYPES[3] });
    assert.equal(up.confirmed.status, 200);
    parentRow(kind, p.live).deleted_at = new Date().toISOString();
    const attempts = [
      await authorize(kind, { expected: up.mediaObjectId }),
      await confirmRequest(kind, up.mediaObjectId, { expected: up.mediaObjectId }),
      await getPlan(kind),
      await removeRequest(kind, { expected: up.mediaObjectId }),
    ];
    for (const result of attempts) assert.deepEqual([result.status, result.body.code], [404, p.notFound]);
    assert.equal(media(up.mediaObjectId).status, 'ready', 'the plan is left for the retention sweep');
  });

  test(`${kind}: the gallery cannot supply a plan and the plan never touches gallery data`, async () => {
    // A gallery-keyed row (the Offer / Owner media key segment) and a profile image.
    const segment = kind === 'offer' ? 'offers' : 'owners';
    const galleryId = crypto.randomUUID();
    state.supabase.media.push({
      id: galleryId, owner_id: ALICE, bucket: BUCKET, media_type: 'image', content_type: 'image/jpeg',
      object_key: `profiles/${ALICE}/${segment}/${p.live}/${galleryId}.jpg`, size_bytes: 64, status: 'ready',
      created_at: new Date().toISOString(), updated_at: new Date().toISOString(),
    });
    const profileId = crypto.randomUUID();
    state.supabase.media.push({
      id: profileId, owner_id: ALICE, bucket: BUCKET, media_type: 'image', content_type: 'image/jpeg',
      object_key: `profiles/${ALICE}/${profileId}.jpg`, size_bytes: 64, status: 'pending_upload',
      created_at: new Date().toISOString(), updated_at: new Date().toISOString(),
    });
    for (const id of [galleryId, profileId]) {
      const confirm = await confirmRequest(kind, id);
      assert.deepEqual([confirm.status, confirm.body.code], [409, 'media_mismatch']);
      const cancel = await removeRequest(kind, { mediaObjectId: id });
      assert.deepEqual([cancel.status, cancel.body.code], [409, 'media_mismatch']);
    }
    assert.equal(media(galleryId).status, 'ready');
    // A complete plan lifecycle never touched offer_media / owner_media (the fake
    // throws on any request outside the plan tables).
    const up = await uploadPlan(kind, { type: TYPES[0] });
    assert.equal(up.confirmed.status, 200);
    assert.equal((await removeRequest(kind, { expected: up.mediaObjectId })).status, 200);
    assert.ok(!state.supabase.calls.some((path) => /offer_media|owner_media|quotation_media|profile_media/.test(path)));
  });

  test(`${kind}: no more than three plan uploads may wait for one record`, async () => {
    const ids = [];
    for (let i = 0; i < 3; i += 1) {
      const result = await authorize(kind);
      assert.equal(result.status, 200);
      ids.push(result.mediaObjectId);
    }
    const fourth = await authorize(kind);
    assert.deepEqual([fourth.status, fourth.body.code], [409, 'plan_upload_limit']);
    assert.equal(state.supabase.media.length, 3);
    // Resuming one of the three is not a fourth reservation.
    const resumed = await call(`${p.prefix}/authorize`, ALICE, {
      [p.idField]: p.live, expectedMediaId: null, mediaObjectId: ids[0],
      contentType: 'application/pdf', contentLength: PDF.length,
    });
    assert.equal(resumed.status, 200);
    // Another record has its own allowance.
    assert.equal((await authorize(kind, { parentId: p.other })).status, 200);
    // An abandoned reservation older than a day stops counting and is retired.
    media(ids[1]).created_at = new Date(Date.now() - 2 * DAY).toISOString();
    const afterAbandon = await authorize(kind);
    assert.equal(afterAbandon.status, 200);
    assert.equal(media(ids[1]).status, 'deleted');
  });

  test(`${kind}: sweeps retire the plan of a long-deleted record, only under the record's own switch`, async () => {
    const live = await uploadPlan(kind, { type: TYPES[3], parentId: p.live });
    const doomed = await uploadPlan(kind, { type: TYPES[5], parentId: p.deleted });
    const recent = await uploadPlan(kind, { type: TYPES[0], parentId: p.other });
    assert.equal(live.confirmed.status + doomed.confirmed.status + recent.confirmed.status, 600);
    const row = parentRow(kind, p.deleted);
    row.deleted_at = new Date(Date.now() - 8 * DAY).toISOString();
    parentRow(kind, p.other).deleted_at = new Date(Date.now() - 2 * DAY).toISOString();
    const otherKind = kind === 'offer' ? 'owner' : 'offer';
    const bystander = await uploadPlan(otherKind, { type: TYPES[3] });

    const before = state.supabase.calls.length;
    const off = await p.sweep(state.env);
    assert.equal(off.mode, 'off');
    assert.equal(media(doomed.mediaObjectId).status, 'ready');
    assert.equal(state.supabase.calls.length, before, 'off does no work at all');

    state.env[p.sweepVar] = 'dry_run';
    const dry = await p.sweep(state.env);
    assert.equal(dry.mode, 'dry_run');
    assert.equal(dry[p.deletedKey], 1);
    assert.equal(media(doomed.mediaObjectId).status, 'ready');
    assert.equal(row.plan_media_id, doomed.mediaObjectId);

    state.env[p.sweepVar] = 'on';
    const report = await p.sweep(state.env);
    assert.equal(report[p.deletedKey], 1);
    assert.equal(report.pendingDeletes, 1);
    assert.equal(report.errors, 0);
    assert.equal(row.plan_media_id, null, 'the deleted record\'s pointer is cleared');
    assert.notEqual(row.deleted_at, null, 'and the record stays deleted');
    assert.equal(media(doomed.mediaObjectId).status, 'deleted');
    assert.equal(state.bucket.objects.has(doomed.key), false);
    // Untouched: a live record's plan, a record deleted only 2 days ago, the other kind's plan.
    assert.equal(media(live.mediaObjectId).status, 'ready');
    assert.equal(parentRow(kind, p.live).plan_media_id, live.mediaObjectId);
    assert.equal(media(recent.mediaObjectId).status, 'ready');
    assert.equal(media(bystander.mediaObjectId).status, 'ready');
    assert.equal(state.bucket.objects.has(bystander.key), true);

    // The other kind's switch is separate: this one being on does nothing to it.
    const otherSweep = otherKind === 'offer' ? runOfferPlanSweeps : runOwnerPlanSweeps;
    assert.equal((await otherSweep(state.env)).mode, 'off');
  });

  test(`${kind}: sweeps retire abandoned and failed uploads and never touch other buckets or kinds`, async () => {
    const old = await authorize(kind);
    const young = await authorize(kind);
    const failed = await authorize(kind);
    const day = (n) => new Date(Date.now() - n * DAY).toISOString();
    media(failed.mediaObjectId).status = 'failed';
    const foreignBucket = await authorize(kind);
    // Aged only now, so authorize's own cleanup has not already retired them.
    media(old.mediaObjectId).created_at = day(2);
    media(failed.mediaObjectId).updated_at = day(8);
    media(foreignBucket.mediaObjectId).bucket = OTHER_BUCKET;
    media(foreignBucket.mediaObjectId).created_at = day(5);
    // A gallery row of the same record and a profile image, both old: not plans.
    const galleryId = crypto.randomUUID();
    state.supabase.media.push({
      id: galleryId, owner_id: ALICE, bucket: BUCKET, media_type: 'image', content_type: 'image/jpeg',
      object_key: `profiles/${ALICE}/${kind === 'offer' ? 'offers' : 'owners'}/${p.live}/${galleryId}.jpg`,
      size_bytes: 64, status: 'pending_upload', created_at: day(5), updated_at: day(5),
    });
    state.env[p.sweepVar] = 'on';
    const report = await p.sweep(state.env);
    assert.equal(report.abandonedUploads, 1);
    assert.equal(report.failedUploads, 1);
    assert.equal(report.errors, 0);
    assert.equal(media(old.mediaObjectId).status, 'deleted');
    assert.equal(media(failed.mediaObjectId).status, 'deleted');
    assert.equal(media(young.mediaObjectId).status, 'pending_upload');
    assert.equal(media(foreignBucket.mediaObjectId).status, 'pending_upload');
    assert.equal(media(galleryId).status, 'pending_upload');
  });
}

test('a plan the record still points at is never deleted by a sweep, whatever its status says', async () => {
  const up = await uploadPlan('offer', { type: TYPES[3] });
  media(up.mediaObjectId).status = 'pending_delete'; // an anomaly: the Offer still points at it
  state.env.OFFER_MEDIA_SWEEP_MODE = 'on';
  const report = await runOfferPlanSweeps(state.env);
  assert.equal(report.pendingDeletes, 0);
  assert.equal(report.errors, 1, 'the anomaly is reported, not acted on');
  assert.equal(parentRow('offer', OFFER_A).plan_media_id, up.mediaObjectId);
  assert.equal(state.bucket.objects.has(up.key), true);
  assert.equal(media(up.mediaObjectId).status, 'pending_delete');
});

// --- cross-kind isolation --------------------------------------------------

test('an Offer plan can never bind to an Owner, nor an Owner plan to an Offer', async () => {
  const offerCandidate = await authorize('offer');
  const ownerCandidate = await authorize('owner');
  state.bucket.put(offerCandidate.key, PDF, 'application/pdf');
  state.bucket.put(ownerCandidate.key, PDF, 'application/pdf');
  // Each is confirmed against the OTHER kind's route with that kind's own record.
  const toOwner = await confirmRequest('owner', offerCandidate.mediaObjectId);
  assert.deepEqual([toOwner.status, toOwner.body.code], [409, 'media_mismatch']);
  const toOffer = await confirmRequest('offer', ownerCandidate.mediaObjectId);
  assert.deepEqual([toOffer.status, toOffer.body.code], [409, 'media_mismatch']);
  const cancelAcross = await removeRequest('owner', { mediaObjectId: offerCandidate.mediaObjectId });
  assert.deepEqual([cancelAcross.status, cancelAcross.body.code], [409, 'media_mismatch']);
  // An id of one kind on the other kind's route is simply not found.
  const offerIdOnOwnerRoute = await authorize('owner', { parentId: OFFER_A });
  assert.deepEqual([offerIdOnOwnerRoute.status, offerIdOnOwnerRoute.body.code], [404, 'owner_not_found']);
  const ownerIdOnOfferRoute = await authorize('offer', { parentId: OWNER_A });
  assert.deepEqual([ownerIdOnOfferRoute.status, ownerIdOnOfferRoute.body.code], [404, 'offer_not_found']);
  assert.equal(media(offerCandidate.mediaObjectId).status, 'pending_upload');
  assert.equal(media(ownerCandidate.mediaObjectId).status, 'pending_upload');
  assert.equal(state.supabase.rpcCalls.length, 0);
  assert.equal(parentRow('offer', OFFER_A).plan_media_id, null);
  assert.equal(parentRow('owner', OWNER_A).plan_media_id, null);
});

test('an object key outside the plan\'s own prefix or bucket never confirms', async () => {
  const auth = await authorize('offer');
  state.bucket.put(auth.key, PDF, 'application/pdf');
  const tampered = [
    ['another account\'s prefix', `profiles/${BOB}/offer-plans/${OFFER_A}/${auth.mediaObjectId}.pdf`],
    ['another record\'s prefix', `profiles/${ALICE}/offer-plans/${OFFER_A2}/${auth.mediaObjectId}.pdf`],
    ['the Owner plan segment', `profiles/${ALICE}/owner-plans/${OFFER_A}/${auth.mediaObjectId}.pdf`],
    ['the gallery segment', `profiles/${ALICE}/offers/${OFFER_A}/${auth.mediaObjectId}.pdf`],
    ['a different file name', `profiles/${ALICE}/offer-plans/${OFFER_A}/${crypto.randomUUID()}.pdf`],
    ['a different extension', `profiles/${ALICE}/offer-plans/${OFFER_A}/${auth.mediaObjectId}.docx`],
  ];
  for (const [label, key] of tampered) {
    media(auth.mediaObjectId).object_key = key;
    const result = await confirmRequest('offer', auth.mediaObjectId);
    assert.deepEqual([result.status, result.body.code], [409, 'media_mismatch'], label);
  }
  media(auth.mediaObjectId).object_key = auth.key;
  media(auth.mediaObjectId).bucket = OTHER_BUCKET;
  const wrongBucket = await confirmRequest('offer', auth.mediaObjectId);
  assert.deepEqual([wrongBucket.status, wrongBucket.body.code], [409, 'media_mismatch']);
  assert.equal(state.supabase.rpcCalls.length, 0);
});

// --- authentication and the active-session gate ----------------------------

test('every plan route refuses a missing or invalid bearer before any work', async () => {
  for (const [method, path, p] of ROUTES) {
    const body = method === 'GET' ? undefined : { [p.idField]: p.live, expectedMediaId: null };
    const missing = await call(path, ALICE, body, { token: null });
    assert.equal(missing.status, 401, `${method} ${path} without a token`);
    const invalid = await call(path, ALICE, body, { token: 'not-a-session' });
    assert.equal(invalid.status, 401, `${method} ${path} with an invalid token`);
  }
  assert.equal(state.supabase.media.length, 0);
  assert.equal(state.supabase.rpcCalls.length, 0);
});

test('Single Active Device: a displaced session is refused on every plan route before any database or R2 work', async () => {
  state.supabase.activeSessionAllowed = false;
  for (const [method, path, p] of ROUTES) {
    state.supabase.calls.length = 0;
    const body = method === 'GET' ? undefined
      : { [p.idField]: p.live, expectedMediaId: null, mediaObjectId: crypto.randomUUID(), contentType: 'application/pdf', contentLength: 10 };
    const result = await call(path, ALICE, body);
    assert.equal(result.status, 403, `${method} ${path}`);
    assert.equal(result.body.code, 'session_superseded', `${method} ${path}`);
    assert.deepEqual(state.supabase.calls, ['/auth/v1/user', '/rest/v1/rpc/is_current_app_session'], `${method} ${path}`);
  }
  assert.equal(state.supabase.media.length, 0);
  assert.equal(state.bucket.objects.size, 0);
  assert.equal(state.supabase.rpcCalls.length, 0);
});

test('Single Active Device: an unavailable session check fails closed on every plan route', async () => {
  state.supabase.sessionCheckStatus = 503;
  for (const [method, path, p] of ROUTES) {
    const body = method === 'GET' ? undefined : { [p.idField]: p.live, expectedMediaId: null };
    const result = await call(path, ALICE, body);
    assert.equal(result.status, 503, `${method} ${path}`);
    assert.equal(result.body.code, 'session_check_unavailable', `${method} ${path}`);
  }
  assert.equal(state.supabase.media.length, 0);
});

test('Single Active Device: the router and the gate coverage of the plan routes cannot drift apart', () => {
  const source = fs.readFileSync(new URL('../worker.js', import.meta.url), 'utf8');
  const routed = [...source.matchAll(/request\.method === '(GET|POST)' && path === '(\/(?:offer|owner)-plan[^']*)'/g)]
    .map((m) => `${m[1]} ${m[2]}`).sort();
  const covered = ROUTES.map(([method, path]) => `${method} ${path.split('?')[0]}`).sort();
  assert.deepEqual(routed, covered, 'a plan route was added or removed without updating this test');

  for (const handler of ['handlePlanAuthorize', 'handlePlanConfirm', 'handlePlanGet', 'handlePlanRemove']) {
    const start = source.indexOf(`async function ${handler}(`);
    assert.ok(start > 0, handler);
    const end = source.indexOf('\n}\n', start);
    const body = source.slice(start, end);
    const gate = body.indexOf('verifySupabaseTokenAndGetUserId(request, env)');
    assert.ok(gate > 0, `${handler} must start with the session gate`);
    for (const later of ['supabaseServiceFetch(', 'env.MEDIA_BUCKET', 'readJson(request)', 'loadOwnedPlanParent(']) {
      const at = body.indexOf(later);
      assert.ok(at === -1 || at > gate, `${handler}: ${later} runs before the gate`);
    }
  }
  // The route table above is the gate table the staging runner sweeps.
  const runner = fs.readFileSync(new URL('../staging-acceptance/quotation_media_staging_acceptance.mjs', import.meta.url), 'utf8');
  for (const route of covered) {
    const [method, path] = route.split(' ');
    const present = method === 'GET' ? runner.includes(`${path}?`) : runner.includes(`'${path}'`);
    assert.ok(present, `the acceptance runner's gate table lacks ${route}`);
  }
});

// --- account deletion ------------------------------------------------------

for (const kind of ['offer', 'owner']) {
  test(`${kind}: no signed PUT is issued while the account is being deleted, and nothing is left behind`, async () => {
    state.supabase.deletionJob = true;
    const result = await authorize(kind);
    assert.equal(result.status, 409);
    assert.equal(result.body.code, 'deletion_in_progress');
    assert.equal(result.body.presignedUrl, undefined);
    assert.equal(parentRow(kind, PARENTS[kind].live).plan_media_id, null);
    assert.ok(
      state.supabase.media.every((m) => m.status !== 'pending_upload'),
      'a refused upload leaves no waiting row',
    );
    assert.equal(state.bucket.objects.size, 0);
  });

  test(`${kind}: an unreadable deletion-job table fails closed: no signed PUT`, async () => {
    state.supabase.deletionJobsStatus = 503;
    const result = await authorize(kind);
    assert.equal(result.status, 503);
    assert.equal(result.body.presignedUrl, undefined);
    assert.ok(state.supabase.media.every((m) => m.status !== 'pending_upload'));
  });
}


test('account deletion inventories and removes plan objects with the account prefix', async () => {
  const offerPlan = await uploadPlan('offer', { type: TYPES[3] });
  const ownerPlan = await uploadPlan('owner', { type: TYPES[5] });
  const retired = await uploadPlan('offer', { parentId: OFFER_A2, type: TYPES[0] });
  await removeRequest('offer', { parentId: OFFER_A2, expected: retired.mediaObjectId });
  // An orphan plan object with no media row: found through the prefix alone.
  const orphan = `profiles/${ALICE}/offer-plans/${OFFER_A}/${crypto.randomUUID()}.pdf`;
  state.bucket.put(orphan, PDF, 'application/pdf');
  const bobPlan = await uploadPlan('offer', { parentId: OFFER_B, type: TYPES[3], user: BOB });
  assert.equal(bobPlan.confirmed.status, 200);

  const removed = await removeAccountMedia(
    ALICE,
    { ...state.env },
    state.supabase.fetch,
    () => new Date(),
  );
  assert.ok(removed >= 3);
  for (const key of [offerPlan.key, ownerPlan.key, orphan]) {
    assert.equal(state.bucket.objects.has(key), false, 'a plan object survived account deletion');
  }
  assert.equal(state.bucket.objects.has(bobPlan.key), true, 'another account\'s plan is untouched');
  assert.ok(state.supabase.media.filter((m) => m.owner_id === ALICE).every((m) => m.status === 'deleted'));
});

// --- Word proof, unit level: the shapes of package and compound file -----------
//
// The route tests above prove what the Worker does with a verdict; these prove
// the verdict itself over every shape of Open XML package and compound file the
// proof must accept or refuse, including hostile ones.

const WORD_PART = 'word/document.xml';

/** A bucket over [bytes] that answers ranged reads and logs them. */
function rangeBucket(bytes) {
  const reads = [];
  return {
    reads,
    async get(_key, { range }) {
      reads.push(range);
      const slice = bytes.slice(range.offset, range.offset + range.length);
      return { arrayBuffer: async () => slice.buffer.slice(slice.byteOffset, slice.byteOffset + slice.byteLength) };
    },
  };
}

async function prove(bytes, contentType) {
  const bucket = rangeBucket(bytes);
  const result = await proveWordDocument(bucket, 'plan.bin', bytes.length, contentType);
  return { result, reads: bucket.reads.length };
}

async function assertVerdicts(cases, contentType, expected) {
  for (const [label, bytes] of cases) {
    const { result, reads } = await prove(bytes, contentType);
    assert.equal(result, expected, label);
    assert.ok(reads <= 48, `${label}: ${reads} reads`);
  }
}

test('proveWordDocument: a DOCX is Word only when its root relationship names a main part of the WordprocessingML type', async () => {
  const typesFor = (type) => contentTypesXml(WORD_PART, type);
  const good = typesFor(WORD_MAIN);
  const withTypes = (types) => docxFile({ types });
  const withRels = (rels) => docxFile({ rels });
  const withContentTypesEntry = (entry) => docxFile({ entries: [
    { name: '[Content_Types].xml', ...entry },
    { name: '_rels/.rels', data: relationshipsXml(WORD_PART) },
    { name: WORD_PART, data: WORD_BODY },
  ] });
  const deflated = zlib.deflateRawSync(Buffer.from(good));
  const comment = (xml) => xml.replace('?>\n', '?>\n<!-- <Override PartName="/xl/workbook.xml" ContentType="x"/> -->');

  await assertVerdicts([
    ['a DOCX as Word writes it', docxFile()],
    ['a package as Microsoft\'s packaging library writes it, the Word type given by the default for xml', netPackagedFile(WORD_PART, WORD_MAIN)],
    ['the default for the extension, written in upper case', withTypes(`<Types><Default Extension="XML" ContentType="${WORD_MAIN}"/></Types>`)],
    ['the Word type, in upper case, given by the default', withTypes(`<Types><Default Extension="xml" ContentType="${WORD_MAIN.toUpperCase()}"/></Types>`)],
    ['a Word override over a default of another type', withTypes(`<Types><Default Extension="xml" ContentType="${XLSX_MAIN}"/><Override PartName="/${WORD_PART}" ContentType="${WORD_MAIN}"/></Types>`)],
    ['a main part with another name', ooxmlPackage({ part: 'word/document2.xml', contentType: WORD_MAIN })],
    ['an absolute relationship target', withRels(relationshipsXml(`/${WORD_PART}`))],
    ['the strict Open XML relationship type', withRels(relationshipsXml(WORD_PART, 'http://purl.oclc.org/ooxml/officeDocument/relationships/officeDocument'))],
    ['single-quoted attributes in any order', docxFile({
      types: `<?xml version='1.0'?><Types xmlns='x'><Override ContentType='${WORD_MAIN}' PartName='/${WORD_PART}'/></Types>`,
      rels: `<Relationships xmlns='r'><Relationship Target='${WORD_PART}' Id='rId9' Type='${OFFICE_DOCUMENT}'/></Relationships>`,
    })],
    ['a byte-order mark and an unrelated comment after the declaration', withTypes(`﻿${comment(good)}`)],
    ['the content type in upper case', withTypes(typesFor(WORD_MAIN.toUpperCase()))],
    ['an archive comment', docxFile({ archive: { comment: 'x'.repeat(5000) } })],
    ['an archive comment that itself holds an end-record signature', docxFile({ archive: { comment: `PK\u0005\u0006${'x'.repeat(30)}` } })],
    ['3000 parts', docxFile({ extra: Array.from({ length: 3000 }, (_, i) => ({ name: `word/media/image${i}.png`, data: 'x', method: 'store' })) })],
  ], DOCX, true);

  await assertVerdicts([
    ['an XLSX', xlsxFile()],
    ['a PPTX', pptxFile()],
    ['a macro-enabled document', withTypes(typesFor('application/vnd.ms-word.document.macroEnabled.main+xml'))],
    ['a template', withTypes(typesFor('application/vnd.openxmlformats-officedocument.wordprocessingml.template.main+xml'))],
    ['a macro-enabled template', withTypes(typesFor('application/vnd.ms-word.template.macroEnabledTemplate.main+xml'))],
    ['the Word type only inside a comment', withTypes(`<Types><!-- ${good} --></Types>`)],
    ['a comment before the XML declaration', withTypes(`<!-- c -->${good}`)],
    ['a workbook that is the real main part, with a Word part and type beside it', ooxmlPackage({
      part: 'xl/workbook.xml',
      contentType: XLSX_MAIN,
      types: `<Types><Override PartName="/xl/workbook.xml" ContentType="${XLSX_MAIN}"/><Override PartName="/${WORD_PART}" ContentType="${WORD_MAIN}"/></Types>`,
      extra: [{ name: WORD_PART, data: WORD_BODY }],
    })],
    ['a relationship to a part that is not in the archive', withRels(relationshipsXml('word/missing.xml'))],
    ['a Word type given to a main part the archive does not contain', docxFile({
      types: contentTypesXml('word/missing.xml', WORD_MAIN),
      rels: relationshipsXml('word/missing.xml'),
    })],
    ['two main-document relationships', withRels(`<Relationships><Relationship Id="a" Type="${OFFICE_DOCUMENT}" Target="${WORD_PART}"/><Relationship Id="b" Type="${OFFICE_DOCUMENT}" Target="xl/workbook.xml"/></Relationships>`)],
    ['an external main-document relationship', withRels(`<Relationships><Relationship Id="a" TargetMode="External" Type="${OFFICE_DOCUMENT}" Target="${WORD_PART}"/></Relationships>`)],
    ['no main-document relationship', withRels(relationshipsXml(WORD_PART, 'http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties'))],
    ['two overrides for the main part, one of them Excel', withTypes(`<Types><Override PartName="/${WORD_PART}" ContentType="${WORD_MAIN}"/><Override PartName="/WORD/document.xml" ContentType="${XLSX_MAIN}"/></Types>`)],
    // The type is the part's Override, else the Default for its extension: a default
    // that names another application's type, an override that contradicts a Word
    // default, two answers or none each leave a package that is not Word's.
    ['a workbook written the way Microsoft\'s packaging library writes one', netPackagedFile('xl/workbook.xml', XLSX_MAIN)],
    ['a presentation written the way Microsoft\'s packaging library writes one', netPackagedFile('ppt/presentation.xml', PPTX_MAIN)],
    ['the default for the main part\'s extension names Excel', withTypes(`<Types><Default Extension="xml" ContentType="${XLSX_MAIN}"/></Types>`)],
    ['a Word default for the extension, overridden by Excel for the main part', withTypes(`<Types><Default Extension="xml" ContentType="${WORD_MAIN}"/><Override PartName="/${WORD_PART}" ContentType="${XLSX_MAIN}"/></Types>`)],
    ['a Word default for the extension, overridden by a type that is none for the main part', withTypes(`<Types><Default Extension="xml" ContentType="${WORD_MAIN}"/><Override PartName="/${WORD_PART}"/></Types>`)],
    ['two defaults for the main part\'s extension, both Word', withTypes(`<Types><Default Extension="xml" ContentType="${WORD_MAIN}"/><Default Extension="XML" ContentType="${WORD_MAIN}"/></Types>`)],
    ['Word defaults for other extensions only', withTypes(`<Types><Default Extension="rels" ContentType="${WORD_MAIN}"/><Default Extension="bin" ContentType="${WORD_MAIN}"/></Types>`)],
    ['content types that give the main part none', withTypes('<Types/>')],
    ['a main part with no extension, under a Word default named for its whole name', ooxmlPackage({
      part: 'word/document', contentType: WORD_MAIN, body: WORD_BODY,
      types: `<Types><Default Extension="document" ContentType="${WORD_MAIN}"/></Types>`,
    })],
    ['a main part whose name ends in a dot, under a Word default for no extension', ooxmlPackage({
      part: 'word/document.', contentType: WORD_MAIN, body: WORD_BODY,
      types: `<Types><Default Extension="" ContentType="${WORD_MAIN}"/></Types>`,
    })],
    ['a main part whose only dot is in a folder name, under a Word default for what follows it', ooxmlPackage({
      part: 'word.d/document', contentType: WORD_MAIN, body: WORD_BODY,
      types: `<Types><Default Extension="d/document" ContentType="${WORD_MAIN}"/></Types>`,
    })],
    ['a relationship target with a dot segment', withRels(relationshipsXml(`../${WORD_PART}`))],
    ['a relationship target that is percent-encoded', withRels(relationshipsXml('word/doc%75ment.xml'))],
    ['no root relationships part', docxFile({ entries: [{ name: '[Content_Types].xml', data: good }, { name: WORD_PART, data: WORD_BODY }] })],
    ['no content-types part', docxFile({ entries: [{ name: '_rels/.rels', data: relationshipsXml(WORD_PART) }, { name: WORD_PART, data: WORD_BODY }] })],
    // Readers disagree on which of two same-named parts is the real one: whichever
    // the proof would take, the package is refused.
    ['one part name twice, the Word types first', docxFile({ entries: [
      { name: '[Content_Types].xml', data: good }, { name: '_rels/.rels', data: relationshipsXml(WORD_PART) },
      { name: WORD_PART, data: WORD_BODY }, { name: '[Content_Types].xml', data: contentTypesXml('xl/workbook.xml', XLSX_MAIN) },
    ] })],
    ['one part name twice, the Word types last', docxFile({ entries: [
      { name: '[Content_Types].xml', data: contentTypesXml('xl/workbook.xml', XLSX_MAIN) }, { name: '_rels/.rels', data: relationshipsXml(WORD_PART) },
      { name: WORD_PART, data: WORD_BODY }, { name: '[Content_Types].xml', data: good },
    ] })],
    ['one part name twice, differing in case, the Word types last', docxFile({ entries: [
      { name: '[CONTENT_TYPES].xml', data: contentTypesXml('xl/workbook.xml', XLSX_MAIN) }, { name: '_rels/.rels', data: relationshipsXml(WORD_PART) },
      { name: WORD_PART, data: WORD_BODY }, { name: '[Content_Types].xml', data: good },
    ] })],
    ['an encrypted content-types part', withContentTypesEntry({ data: good, flags: 1 })],
    ['an unsupported compression method', withContentTypesEntry({ data: good, rawMethod: 9 })],
    ['content types that inflate to 40 MiB under a 700-byte claim', withContentTypesEntry({ data: Buffer.alloc(700, 0x20), packed: zlib.deflateRawSync(Buffer.alloc(40 * MIB, 0x20)) })],
    ['a deflate stream that is corrupt', withContentTypesEntry({ data: good, packed: Buffer.from([0xff, 0xff, 0xff, 0xff, 0xff, 0xff]) })],
    ['a deflate stream cut short', withContentTypesEntry({ data: good, packed: deflated.subarray(0, deflated.length - 6) })],
    ['bytes after the end of the deflate stream', withContentTypesEntry({ data: good, packed: Buffer.concat([deflated, Buffer.from([1, 2, 3, 4, 5])]) })],
    ['a part the directory claims is 5 MiB', withContentTypesEntry({ data: good, claim: { size: 5 * MIB } })],
    ['a part the directory claims is smaller than it is', withContentTypesEntry({ data: good, claim: { size: 10 } })],
    ['a part the directory claims is larger than it is', withContentTypesEntry({ data: good, claim: { size: 5000 } })],
    ['a packed size claimed beyond the file', withContentTypesEntry({ data: good, claim: { packed: 0x7fffffff } })],
    ['a local header that names another part than the directory does', (() => {
      const file = new Uint8Array(docxFile());
      file[30] = 0x5d; // the first local header's name begins at byte 30
      return file;
    })()],
    ['ZIP64 markers in the end record', docxFile({ archive: { eocd: { count: 0xffff } } })],
    ['an end record for another disk', docxFile({ archive: { eocd: { disk: 1 } } })],
    ['a directory offset past the end', docxFile({ archive: { eocd: { directoryOffset: 5_000_000 } } })],
    ['a directory size past the file', docxFile({ archive: { eocd: { directorySize: 900_000 } } })],
    ['an entry count that is not the directory\'s', docxFile({ archive: { eocd: { count: 9, countOnDisk: 9 } } })],
    ['an archive cut short (no end record)', docxFile().slice(0, 400)],
    ['too few bytes for an end record', new Uint8Array([0x50, 0x4b, 3, 4, 0, 0])],
    ['bytes that are not a ZIP at all', new Uint8Array(2000).fill(0x41)],
    ['a DTD that defines an entity, after the declaration', withTypes(good.replace('?>\n', '?>\n<!DOCTYPE Types [<!ENTITY e "x">]>'))],
    ['CDATA in the relationships, after the declaration', withRels(relationshipsXml(WORD_PART).replace('?>\n', '?>\n<![CDATA[ x ]]>'))],
    ['a processing instruction after the declaration', withTypes(`<?xml version="1.0"?><?pi x?>${good}`)],
    ['an unknown entity in an element beside the Word override', withTypes(good.replace('</Types>', '<Override PartName="/other.xml" ContentType="&bogus;"/></Types>'))],
    ['a repeated attribute whose last value names the Word part', withTypes(`<Types><Override PartName="/xl/workbook.xml" PartName="/${WORD_PART}" ContentType="${WORD_MAIN}"/></Types>`)],
    ['content types in UTF-16', withTypes(Buffer.from(`﻿${good}`, 'utf16le'))],
    ['bytes that are not UTF-8', withTypes(new Uint8Array([0xc3, 0x28, 0xff]))],
  ], DOCX, false);
});

test('proveWordDocument: a DOC is Word only when the root directory holds Word\'s own stream and no other application\'s', async () => {
  const base = docFile();
  const { sectorSize, dirStart, fatStart } = base.layout;
  const entryAt = (index) => (dirStart + 1) * sectorSize + index * 128;
  const mutated = (change) => {
    const file = new Uint8Array(base);
    change(new DataView(file.buffer), file);
    return file;
  };
  const loop = mutated((view) => view.setUint32((fatStart + 1) * sectorSize + dirStart * 4, dirStart, true));
  const cycle = mutated((view) => {
    const first = view.getUint32(entryAt(0) + 76, true);
    view.setUint32(entryAt(first) + 68, first, true);
  });
  const largeDoc = docFile({ tree: [wordStream(), { name: '1Table', size: 4096 }, { name: 'Data', size: 20 * MIB }] });
  const endless = new Uint8Array(largeDoc);
  {
    // A DIFAT chain that points at itself, under a header claiming billions of sectors.
    const view = new DataView(endless.buffer);
    view.setUint32((largeDoc.layout.difatStart + 1) * largeDoc.layout.sectorSize + largeDoc.layout.sectorSize - 4, largeDoc.layout.difatStart, true);
    view.setUint32(72, 0xffffffff, true);
  }
  // A directory chained through 60 sectors spread 9 apart: a real Word file's is
  // contiguous, and this one would take more reads of storage than the proof allows.
  const scattered = new Uint8Array(largeDoc);
  {
    const view = new DataView(scattered.buffer);
    const { sectorSize: size, dirStart: first, fatStart } = largeDoc.layout;
    const fatEntry = (id) => (fatStart + Math.floor(id / (size / 4)) + 1) * size + (id % (size / 4)) * 4;
    let previous = first;
    for (let i = 0; i < 60; i++) {
      const sector = 30 + i * 9; // inside the Data stream
      view.setUint32(fatEntry(previous), sector, true);
      previous = sector;
    }
    view.setUint32(fatEntry(previous), 0xfffffffe, true);
  }

  await assertVerdicts([
    ['a DOC', base],
    ['a DOC in 4096-byte sectors', docFile({ version: 4 })],
    ['an Excel object embedded in the document', compoundFile({ tree: [
      wordStream(), { name: 'ObjectPool', children: [{ name: '_1234567890', children: [{ name: 'Workbook', size: 4096 }] }] },
    ] })],
    ['the stream name in another case', compoundFile({ tree: [{ name: 'worddocument', size: 4096 }] })],
    ['forty other streams (a directory of several sectors)', compoundFile({ tree: [
      wordStream(), ...Array.from({ length: 40 }, (_, i) => ({ name: `Stream${i}`, size: 4096 })),
    ] })],
    [`a ${(largeDoc.length / MIB).toFixed(0)} MiB DOC whose directory is found through DIFAT sectors`, largeDoc],
  ], 'application/msword', true);

  await assertVerdicts([
    ['an Excel workbook', xlsFile()],
    ['an Excel 5/95 workbook', oldXlsFile()],
    ['a PowerPoint presentation', pptFile()],
    ['a compound file with no Word stream', compoundFile({ tree: [{ name: 'CompObj', size: 4096 }] })],
    ['Word and Excel streams side by side', compoundFile({ tree: [wordStream(), { name: 'Workbook', size: 4096 }] })],
    ['Word and Excel 5/95 streams side by side', compoundFile({ tree: [wordStream(), { name: 'Book', size: 4096 }] })],
    ['Word and PowerPoint streams side by side', compoundFile({ tree: [wordStream(), { name: 'PowerPoint Document', size: 4096 }] })],
    ['a storage named WordDocument, not a stream', compoundFile({ tree: [{ name: 'WordDocument', children: [] }] })],
    ['a WordDocument stream only inside another storage', compoundFile({ tree: [{ name: 'Embedded', children: [wordStream()] }] })],
    ['two root streams of one name', compoundFile({ tree: [wordStream(), wordStream()] })],
    ['a signature that is not a compound file\'s', mutated((view, file) => { file[0] = 0; })],
    ['a byte-order mark that is not little endian', mutated((view) => view.setUint16(28, 0xfeff, true))],
    ['a version that is neither 3 nor 4', mutated((view) => view.setUint16(26, 5, true))],
    ['version 3 with 4096-byte sectors', mutated((view) => view.setUint16(30, 12, true))],
    ['a mini sector size that is not 64', mutated((view) => view.setUint16(32, 7, true))],
    ['a file too short to hold a directory', base.slice(0, 900)],
    ['a header and nothing else', base.slice(0, 512)],
    ['a directory that starts outside the file', mutated((view) => view.setUint32(48, 99999, true))],
    ['a directory that starts at a reserved value', mutated((view) => view.setUint32(48, 0xfffffffd, true))],
    ['a header that declares no FAT sector', mutated((view) => view.setUint32(44, 0, true))],
    ['a header whose FAT sector entry is free', mutated((view) => view.setUint32(76, 0xffffffff, true))],
    ['a directory chain that loops onto itself', loop],
    ['a directory of more than 256 sectors', compoundFile({ tree: Array.from({ length: 1100 }, (_, i) => ({ name: `S${i}`, size: 4096 })) })],
    ['a first entry that is not the root storage', mutated((view, file) => { file[entryAt(0) + 66] = 2; })],
    ['a root child outside the directory', mutated((view) => view.setUint32(entryAt(0) + 76, 500, true))],
    ['a sibling tree that loops', cycle],
    ['a DIFAT chain that never ends', endless],
    ['a directory scattered over more reads than the proof allows', scattered],
  ], 'application/msword', false);
});

test('proveWordDocument: a package part built to make a search start over is refused at once, and a large genuine one is not slowed', async () => {
  const head = '<?xml version="1.0"?>\n';
  const slow = [
    ['"<Override " over and over with no ">"', docxFile({ types: head + '<Override '.repeat(30_000) })],
    ['"<!--" over and over with no "-->"', docxFile({ types: head + '<!--'.repeat(75_000) })],
    ['one tag whose attributes are 300,000 letters', docxFile({ types: `${head}<Override ${'a'.repeat(300_000)}>` })],
    ['one tag with 300,000 spaces and no "="', docxFile({ types: `${head}<Override a${' '.repeat(300_000)}>` })],
    ['"<Relationship " over and over in the relationships', docxFile({ rels: head + '<Relationship '.repeat(20_000) })],
  ];
  for (const [label, bytes] of slow) {
    const started = performance.now();
    const { result } = await prove(bytes, DOCX);
    const elapsed = performance.now() - started;
    assert.equal(result, false, label);
    assert.ok(elapsed < 3000, `${label}: took ${Math.round(elapsed)} ms`);
  }

  // A genuine part of the largest size the proof reads, with thousands of overrides.
  const overrides = Array.from({ length: 6000 }, (_, i) =>
    `<Override PartName="/word/charts/chart${i}.xml" ContentType="application/vnd.openxmlformats-officedocument.drawingml.chart+xml"/>`).join('');
  const big = docxFile({ types: contentTypesXml(WORD_PART, WORD_MAIN).replace('</Types>', `${overrides}</Types>`) });
  const started = performance.now();
  assert.equal((await prove(big, DOCX)).result, true);
  assert.ok(performance.now() - started < 3000);
});

test('proveWordDocument: nothing is read for any other type, and a missing object is a storage matter, not a verdict', async () => {
  const untouched = { get: async () => { throw new Error('storage must not be read'); } };
  for (const type of ['image/jpeg', 'image/png', 'image/webp', 'application/pdf']) {
    assert.equal(await proveWordDocument(untouched, 'k', 1000, type), true, type);
  }
  const vanished = { get: async () => null };
  for (const [type, size] of [[DOCX, DOCX_BYTES.length], ['application/msword', DOC.length]]) {
    await assert.rejects(
      proveWordDocument(vanished, 'k', size, type),
      (error) => error.code === 'upload_incomplete' && error.status === 409,
      type,
    );
  }
  const failing = { get: async () => { throw new Error('storage outage'); } };
  await assert.rejects(proveWordDocument(failing, 'k', DOCX_BYTES.length, DOCX), /storage outage/);
});
