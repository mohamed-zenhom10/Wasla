import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import config from '../config.js';
import { AppError } from '../errors.js';

const UPLOADS = fileURLToPath(new URL('../../uploads/', import.meta.url));
const LINK_SECONDS = 3600;
const LOCAL_NAME = /^[a-z0-9_-]+\.(jpg|png|webp)$/;

export const IMAGE_TYPES = ['image/jpeg', 'image/png', 'image/webp'];
export const MAX_IMAGE_MB = 5;

const EXTENSIONS = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp' };
const PNG_START = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

function imageKind(buffer) {
  if (buffer.length > 3 && buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) {
    return 'image/jpeg';
  }
  if (buffer.length > 8 && buffer.subarray(0, 8).equals(PNG_START)) {
    return 'image/png';
  }
  if (buffer.length > 12 && buffer.toString('ascii', 0, 4) === 'RIFF' && buffer.toString('ascii', 8, 12) === 'WEBP') {
    return 'image/webp';
  }
  return null;
}

export function readImage(req) {
  if (!Buffer.isBuffer(req.body) || req.body.length === 0) {
    throw new AppError(415, 'UNSUPPORTED_IMAGE', 'Send the photo itself as the body (image/jpeg, png or webp)');
  }
  const kind = imageKind(req.body);
  if (!kind) {
    throw new AppError(400, 'INVALID_IMAGE', 'The file is not a JPEG, PNG or WEBP photo');
  }
  return { buffer: req.body, type: kind };
}

function sign(params) {
  const text = Object.keys(params).sort().map((key) => `${key}=${params[key]}`).join('&');
  return crypto.createHash('sha1').update(text + config.cloudinary.apiSecret).digest('hex');
}

async function saveToCloudinary(image, folder) {
  const { cloudName, apiKey } = config.cloudinary;
  const params = {
    asset_folder: folder,
    public_id: `${folder}/${crypto.randomUUID()}`,
    timestamp: Math.floor(Date.now() / 1000),
    type: 'private',
  };
  const form = new FormData();
  form.append('file', new Blob([image.buffer], { type: image.type }));
  for (const [key, value] of Object.entries(params)) {
    form.append(key, String(value));
  }
  form.append('api_key', apiKey);
  form.append('signature', sign(params));

  let res;
  try {
    res = await fetch(`https://api.cloudinary.com/v1_1/${cloudName}/image/upload`, {
      method: 'POST',
      body: form,
      signal: AbortSignal.timeout(30000),
    });
  } catch (err) {
    console.error('Photo upload failed:', err.message);
    throw new AppError(503, 'STORAGE_FAILED', 'Could not save the photo, try again');
  }
  const result = await res.json().catch(() => ({}));
  if (!res.ok || !result.public_id) {
    console.error('Photo upload failed:', res.status, result.error && result.error.message);
    throw new AppError(503, 'STORAGE_FAILED', 'Could not save the photo, try again');
  }
  return `cloudinary:${result.public_id}.${result.format}`;
}

async function saveLocally(image) {
  const name = `${crypto.randomUUID()}.${EXTENSIONS[image.type]}`;
  await fs.mkdir(UPLOADS, { recursive: true });
  await fs.writeFile(UPLOADS + name, image.buffer);
  return `local:${name}`;
}

export function saveImage(image, folder) {
  return config.cloudinary ? saveToCloudinary(image, folder) : saveLocally(image);
}

function localSignature(name, expires) {
  return crypto.createHmac('sha256', config.jwtSecret).update(`${name}:${expires}`).digest('base64url');
}

export function imageUrl(key, baseUrl) {
  const expires = Math.floor(Date.now() / 1000) + LINK_SECONDS;
  if (key.startsWith('cloudinary:') && config.cloudinary) {
    const file = key.slice('cloudinary:'.length);
    const dot = file.lastIndexOf('.');
    const params = {
      expires_at: expires,
      format: file.slice(dot + 1),
      public_id: file.slice(0, dot),
      timestamp: Math.floor(Date.now() / 1000),
      type: 'private',
    };
    const query = new URLSearchParams({
      ...params, api_key: config.cloudinary.apiKey, signature: sign(params),
    });
    return `https://api.cloudinary.com/v1_1/${config.cloudinary.cloudName}/image/download?${query}`;
  }
  if (key.startsWith('local:')) {
    const name = key.slice('local:'.length);
    return `${baseUrl}/api/files/${name}?expires=${expires}&signature=${localSignature(name, expires)}`;
  }
  return null;
}

export async function readLocalFile(name, expires, signature) {
  if (!LOCAL_NAME.test(name) || !/^[0-9]+$/.test(String(expires)) || typeof signature !== 'string') {
    throw new AppError(404, 'NOT_FOUND', 'File not found');
  }
  const expected = Buffer.from(localSignature(name, expires));
  const given = Buffer.from(signature);
  if (given.length !== expected.length || !crypto.timingSafeEqual(given, expected)) {
    throw new AppError(403, 'LINK_NOT_VALID', 'This link is not valid');
  }
  if (Number(expires) < Date.now() / 1000) {
    throw new AppError(403, 'LINK_EXPIRED', 'This link expired, load the page again');
  }
  try {
    return await fs.readFile(UPLOADS + name);
  } catch {
    throw new AppError(404, 'NOT_FOUND', 'File not found');
  }
}
