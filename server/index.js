const express = require('express');
const multer  = require('multer');
const path    = require('path');
const fs      = require('fs');

const app  = express();
const PORT = 3000;

// Preserve original filenames so they match items_json entries
const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, path.join(__dirname, 'uploads')),
  filename:    (req, file, cb) => cb(null, file.originalname),
});
const upload = multer({ storage });

app.post('/api/v1/images/batch', upload.array('files'), (req, res) => {
  let items;
  try {
    items = JSON.parse(req.body.items_json);
  } catch {
    return res.status(400).json({ error: 'Invalid items_json' });
  }

  const files = req.files ?? [];

  console.log(`--- Batch received: ${items.length} image(s) ---`);

  for (const item of items) {
    const file = files.find(f => f.originalname === item.filename);
    console.log(`  File     : ${item.filename} (${file ? file.size + ' bytes' : 'NOT FOUND'})`);
    console.log(`  GPS      : ${item.latitude}, ${item.longitude}`);
    if (item.altitude   != null) console.log(`  Altitude : ${item.altitude}m`);
    if (item.gps_accuracy != null) console.log(`  Accuracy : ±${item.gps_accuracy}m`);
    if (item.heading    != null) console.log(`  Heading  : ${item.heading}°`);
    console.log(`  Captured : ${new Date(item.captured_at).toISOString()}`);
    console.log('');
  }

  res.json({ ok: true, count: items.length });
});

app.get('/health', (req, res) => res.json({ ok: true }));

app.listen(PORT, '0.0.0.0', () => {
  console.log(`PatchGuard server running on http://0.0.0.0:${PORT}`);
  console.log(`Ingest : POST http://<mac-ip>:${PORT}/api/v1/images/batch`);
  console.log(`Saved  : ${path.join(__dirname, 'uploads')}`);
  console.log('');
});
