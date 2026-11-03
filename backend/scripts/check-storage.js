import config from '../src/config.js';
import { saveImage, imageUrl, readLocalFile } from '../src/lib/storage.js';

const PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  'base64',
);
let failed = false;

function check(label, value, ok) {
  console.log(`${ok ? 'OK  ' : 'FAIL'}  ${label.padEnd(28)} ${value}`);
  if (!ok) failed = true;
}

try {
  const where = config.cloudinary ? `Cloudinary (${config.cloudinary.cloudName})` : 'this computer (uploads folder)';
  check('storage', where, true);
  const key = await saveImage({ buffer: PNG, type: 'image/png' }, 'wasla/checks');
  check('upload', key, true);

  let saved;
  if (config.cloudinary) {
    const res = await fetch(imageUrl(key));
    saved = Buffer.from(await res.arrayBuffer());
    check('private link works', res.status, res.status === 200);

    const file = key.slice('cloudinary:'.length);
    const open = await fetch(`https://res.cloudinary.com/${config.cloudinary.cloudName}/image/private/${file}`);
    check('public link is blocked', open.status, open.status !== 200);
  } else {
    const url = new URL(imageUrl(key, 'http://localhost'));
    saved = await readLocalFile(url.pathname.split('/').pop(), url.searchParams.get('expires'),
      url.searchParams.get('signature'));
    check('saved file can be read', `${saved.length} bytes`, true);
  }
  check('same photo came back', `${saved.length} bytes`, saved.equals(PNG));
} catch (err) {
  check('error', err.message, false);
}

console.log(failed ? '\nSome checks failed' : '\nAll checks passed');
process.exit(failed ? 1 : 0);
