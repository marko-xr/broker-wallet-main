// Broker Wallet — small synthetic files for the Plan attachment staging acceptance.
//
// Built in memory, so nothing binary is committed: a minimal PDF, a minimal Word DOCX
// (a WordprocessingML package Word can open), a structurally Word-shaped DOC (an OLE2
// compound file holding Word's own `WordDocument` stream, not saved by Word), and the
// masquerades the Worker must refuse: an XLSX or PPTX that would be renamed `.docx`, and an
// XLS or PPT that would be renamed `.doc`. They are Excel-/PowerPoint-shaped in exactly the
// way the Worker tells apart (the package's main part type, the compound file's streams).
//
// Node built-ins only.

import { randomUUID } from 'node:crypto';

const CRC_TABLE = Array.from({ length: 256 }, (_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});
function crc32(bytes) {
  let c = 0xffffffff;
  for (const b of bytes) c = CRC_TABLE[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

/** A ZIP archive of stored (uncompressed) entries, in the order given. */
export function zipStored(entries) {
  const chunks = [];
  const central = [];
  let offset = 0;
  for (const entry of entries) {
    const name = Buffer.from(entry.name, 'utf8');
    const data = Buffer.from(entry.data);
    const crc = crc32(data);
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4);
    local.writeUInt16LE(0x21, 12);
    local.writeUInt32LE(crc, 14);
    local.writeUInt32LE(data.length, 18);
    local.writeUInt32LE(data.length, 22);
    local.writeUInt16LE(name.length, 26);
    chunks.push(local, name, data);
    const header = Buffer.alloc(46);
    header.writeUInt32LE(0x02014b50, 0);
    header.writeUInt16LE(20, 4);
    header.writeUInt16LE(20, 6);
    header.writeUInt16LE(0x21, 14);
    header.writeUInt32LE(crc, 16);
    header.writeUInt32LE(data.length, 20);
    header.writeUInt32LE(data.length, 24);
    header.writeUInt16LE(name.length, 28);
    header.writeUInt32LE(offset, 42);
    central.push(header, name);
    offset += 30 + name.length + data.length;
  }
  const directory = Buffer.concat(central);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(entries.length, 8);
  end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(directory.length, 12);
  end.writeUInt32LE(offset, 16);
  return Buffer.concat([...chunks, directory, end]);
}

const XML = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';
const MAIN_TYPES = Object.freeze({
  word: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml',
  excel: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml',
  powerpoint: 'application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml',
});
const OFFICE_DOCUMENT = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument';

/** An Open XML package whose one main part is [part], typed [contentType]; content types first. */
function ooxml(part, contentType, body) {
  return zipStored([
    {
      name: '[Content_Types].xml',
      data: `${XML}<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">` +
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' +
        '<Default Extension="xml" ContentType="application/xml"/>' +
        `<Override PartName="/${part}" ContentType="${contentType}"/></Types>`,
    },
    {
      name: '_rels/.rels',
      data: `${XML}<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">` +
        `<Relationship Id="rId1" Type="${OFFICE_DOCUMENT}" Target="${part}"/></Relationships>`,
    },
    { name: part, data: body },
  ]);
}

/** A minimal Word document: one paragraph. */
export const makeDocx = (label) => ooxml('word/document.xml', MAIN_TYPES.word,
  `${XML}<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>` +
  `<w:p><w:r><w:t>staging-e2e ${label} ${randomUUID()}</w:t></w:r></w:p></w:body></w:document>`);

/** Excel's package, the kind of file that would be renamed .docx. */
export const makeXlsx = () => ooxml('xl/workbook.xml', MAIN_TYPES.excel,
  `${XML}<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheets/></workbook>`);

/** PowerPoint's package, the other kind that would be renamed .docx. */
export const makePptx = () => ooxml('ppt/presentation.xml', MAIN_TYPES.powerpoint,
  `${XML}<p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"/>`);

const FREE = 0xffffffff;
const END = 0xfffffffe;
const FAT_SECTOR = 0xfffffffd;

/**
 * An OLE2 compound file (version 3, 512-byte sectors) whose root holds [streams] as its only
 * children: { name, size (a multiple of 512, at least 4096 so they are not mini streams), head }.
 * The directory is a proper binary search tree in compound-file name order, as real writers
 * produce, so a strict reader (such as Windows' own) opens it.
 */
function compoundFile(streams) {
  const sectorSize = 512;
  const perSector = sectorSize / 4;
  const entries = [{ name: 'Root Entry', type: 5 }, ...streams.map((s) => ({ ...s, type: 2 }))];
  entries.forEach((entry, id) => { entry.id = id; });

  const order = (a, b) => a.name.length - b.name.length ||
    (a.name.toUpperCase() < b.name.toUpperCase() ? -1 : a.name.toUpperCase() > b.name.toUpperCase() ? 1 : 0);
  const link = (nodes) => {
    if (nodes.length === 0) return FREE;
    const middle = nodes.length >> 1;
    const node = nodes[middle];
    node.left = link(nodes.slice(0, middle));
    node.right = link(nodes.slice(middle + 1));
    return node.id;
  };
  entries[0].child = link(entries.slice(1).sort(order));

  let next = 0;
  const data = [];
  for (const entry of entries.slice(1)) {
    entry.start = next;
    entry.sectors = Math.ceil(entry.size / sectorSize);
    next += entry.sectors;
    const bytes = Buffer.alloc(entry.sectors * sectorSize);
    if (entry.head) Buffer.from(entry.head).copy(bytes);
    data.push(bytes);
  }
  const directorySectors = Math.ceil(entries.length / (sectorSize / 128));
  const directoryStart = next;
  const fatStart = directoryStart + directorySectors;
  if (fatStart + 1 > perSector) throw new Error('fixture needs more than one FAT sector');

  const fat = new Uint32Array(perSector).fill(FREE);
  for (const entry of entries.slice(1)) {
    for (let i = 0; i < entry.sectors; i++) fat[entry.start + i] = i === entry.sectors - 1 ? END : entry.start + i + 1;
  }
  for (let i = 0; i < directorySectors; i++) fat[directoryStart + i] = i === directorySectors - 1 ? END : directoryStart + i + 1;
  fat[fatStart] = FAT_SECTOR;

  const directory = Buffer.alloc(directorySectors * sectorSize);
  for (let id = 0; id < directorySectors * (sectorSize / 128); id++) {
    const at = id * 128;
    const entry = entries[id];
    directory.writeUInt32LE(entry?.left ?? FREE, at + 68);
    directory.writeUInt32LE(entry?.right ?? FREE, at + 72);
    directory.writeUInt32LE(entry?.child ?? FREE, at + 76);
    if (!entry) continue;
    for (let c = 0; c < entry.name.length; c++) directory.writeUInt16LE(entry.name.charCodeAt(c), at + c * 2);
    directory.writeUInt16LE((entry.name.length + 1) * 2, at + 64);
    directory[at + 66] = entry.type;
    directory[at + 67] = 1;
    if (entry.type === 2) {
      directory.writeUInt32LE(entry.start, at + 116);
      directory.writeUInt32LE(entry.size, at + 120);
    }
  }

  const header = Buffer.alloc(sectorSize);
  Buffer.from([0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1]).copy(header);
  header.writeUInt16LE(0x3e, 24);
  header.writeUInt16LE(3, 26);
  header.writeUInt16LE(0xfffe, 28);
  header.writeUInt16LE(9, 30);
  header.writeUInt16LE(6, 32);
  header.writeUInt32LE(1, 44);
  header.writeUInt32LE(directoryStart, 48);
  header.writeUInt32LE(4096, 56);
  header.writeUInt32LE(END, 60);
  header.writeUInt32LE(END, 68);
  for (let i = 0; i < 109; i++) header.writeUInt32LE(i === 0 ? fatStart : FREE, 76 + i * 4);

  return Buffer.concat([header, ...data, directory, Buffer.from(fat.buffer)]);
}

const stream = (name, head) => ({ name, size: 4096, head });

/** Word 97-2003 shaped: Word's own streams, `WordDocument` first (its FIB signature starts 0xA5EC). */
export const makeDoc = () => compoundFile([
  stream('WordDocument', [0xec, 0xa5]), stream('1Table'), stream('\u0005SummaryInformation'),
]);
/** Excel 97-2003 shaped: a `Workbook` stream. */
export const makeXls = () => compoundFile([stream('Workbook'), stream('\u0005SummaryInformation')]);
/** PowerPoint 97-2003 shaped: a `PowerPoint Document` stream. */
export const makePpt = () => compoundFile([stream('PowerPoint Document'), stream('Current User'), stream('Pictures')]);

/** A minimal, structurally plain PDF whose bytes are unique per [label]. */
export function makePdf(label) {
  const text = '%PDF-1.4\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n' +
    '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n' +
    '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] >>\nendobj\n' +
    `% staging-e2e ${label} ${randomUUID()}\n` +
    'trailer\n<< /Root 1 0 R /Size 4 >>\n%%EOF\n';
  return Buffer.from(text, 'latin1');
}
