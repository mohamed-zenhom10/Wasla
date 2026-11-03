import { Router } from 'express';
import { readLocalFile } from '../lib/storage.js';

const router = Router();
const TYPES = { jpg: 'image/jpeg', png: 'image/png', webp: 'image/webp' };

router.get('/:name', async (req, res) => {
  const file = await readLocalFile(req.params.name, req.query.expires, req.query.signature);
  res.set('Content-Type', TYPES[req.params.name.split('.').pop()]);
  res.set('Cache-Control', 'private, max-age=600');
  res.send(file);
});

export default router;
