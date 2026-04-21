import express from 'express';
import { createServer } from 'http';
import { WebSocketServer } from 'ws';
import { fileURLToPath } from 'url';
import { dirname, join, basename, extname, resolve } from 'path';
import { existsSync, createReadStream, statSync, renameSync } from 'fs';
import { mkdir, stat, unlink, readdir } from 'fs/promises';
import { tmpdir, homedir } from 'os';
import multer from 'multer';
import { v4 as uuidv4 } from 'uuid';
import { detectHWAccel } from './lib/hwaccel.js';
import { probe } from './lib/probe.js';
import { buildCommand, buildTwoPassCommands } from './lib/ffmpeg.js';
import { JobQueue } from './lib/jobQueue.js';
import { spawn } from 'child_process';
import {
  detectExifTool,
  readMetadataJson,
  computeRemovals,
  writeCleanCopy,
  generateReport,
} from './lib/exiftool.js';
import { probeClips, stitch } from './lib/stitch.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const app = express();
const server = createServer(app);
const wss = new WebSocketServer({ server });

const PORT = process.env.PORT || 3000;
const UPLOAD_DIR = join(tmpdir(), 'video-compressor-uploads');
const FFMPEG_PATH = '/opt/homebrew/bin/ffmpeg';

await mkdir(UPLOAD_DIR, { recursive: true });

// Clean stale uploads from previous sessions on startup
async function cleanUploadDir() {
  try {
    const files = await readdir(UPLOAD_DIR);
    let cleaned = 0;
    for (const f of files) {
      try {
        await unlink(join(UPLOAD_DIR, f));
        cleaned++;
      } catch {
        /* skip locked files */
      }
    }
    if (cleaned > 0) console.log(`  Cleaned ${cleaned} stale temp file(s) from previous session`);
  } catch {
    /* dir may not exist yet */
  }
}
await cleanUploadDir();

// Clean up a specific temp upload after compression completes
async function cleanTempUpload(inputPath) {
  const resolved = resolve(inputPath);
  if (!resolved.startsWith(resolve(UPLOAD_DIR))) return; // only clean uploads, not local paths
  try {
    await unlink(resolved);
  } catch {
    /* already gone */
  }
}

// Output directory for uploaded files (instead of temp dir)
const OUTPUT_DIR = join(homedir(), 'Movies', 'Video Compressor Output');
await mkdir(OUTPUT_DIR, { recursive: true });

// Path safety: allow user home, /Volumes, upload dir, and temp
function isSafePath(filePath) {
  const resolved = resolve(filePath);
  const blocked = ['/System', '/Library', '/usr', '/bin', '/sbin', '/private/etc'];
  if (blocked.some((b) => resolved.startsWith(b))) return false;
  const home = resolve(homedir());
  const allowedRoots = [home, '/Volumes', resolve(UPLOAD_DIR), resolve(tmpdir())];
  return allowedRoots.some((root) => resolved.startsWith(root + '/') || resolved === root);
}

// Multer for file uploads
const upload = multer({
  dest: UPLOAD_DIR,
  limits: { fileSize: 50 * 1024 * 1024 * 1024 }, // 50GB
});

// Detect hardware acceleration on startup
let hwaccelCapabilities = null;
try {
  hwaccelCapabilities = await detectHWAccel();
  console.log('Hardware acceleration:', hwaccelCapabilities);
} catch (err) {
  console.warn('HW accel detection failed:', err.message);
  hwaccelCapabilities = Object.freeze({
    h264_videotoolbox: false,
    hevc_videotoolbox: false,
    prores_videotoolbox: false,
  });
}

const jobQueue = new JobQueue();
const wsClients = new Set();

wss.on('connection', (ws) => {
  wsClients.add(ws);
  ws.on('close', () => wsClients.delete(ws));
  ws.on('error', () => wsClients.delete(ws));
});

function broadcast(data) {
  const msg = JSON.stringify(data);
  for (const client of wsClients) {
    if (client.readyState === 1) {
      try {
        client.send(msg);
      } catch (_) {
        /* client disconnected */
      }
    }
  }
}

jobQueue.on('progress', (data) => broadcast({ ...data, type: 'progress', jobId: data.id }));
jobQueue.on('complete', (data) => {
  broadcast({ ...data, type: 'complete', jobId: data.id, outputSize: data.compressedSize });
  // Clean up temp upload after successful compression
  if (data.inputPath) cleanTempUpload(data.inputPath);
});
jobQueue.on('error', (data) =>
  broadcast({ ...data, type: 'error', jobId: data.id, error: data.message }),
);

app.use(express.json({ limit: '1mb' }));
app.use(express.static(join(__dirname, 'public')));

// Upload files
app.post('/api/upload', upload.array('file', 20), (req, res) => {
  if (!req.files || req.files.length === 0) {
    return res.status(400).json({ error: 'No files uploaded' });
  }
  const results = req.files.map((f) => {
    // Rename to include original extension
    const ext = extname(f.originalname) || '.mp4';
    const newPath = f.path + ext;
    try {
      renameSync(f.path, newPath);
    } catch {}
    return { path: newPath, name: f.originalname, size: f.size };
  });
  res.json({ files: results });
});

// Probe
app.get('/api/probe', async (req, res) => {
  const filePath = req.query.path;
  if (!filePath) return res.status(400).json({ error: "Query parameter 'path' is required" });
  if (!isSafePath(filePath)) return res.status(403).json({ error: 'Access denied' });
  if (!existsSync(filePath)) return res.status(404).json({ error: `File not found: ${filePath}` });
  try {
    const metadata = await probe(filePath);
    res.json(metadata);
  } catch (err) {
    res.status(500).json({ error: `Failed to probe: ${err.message}` });
  }
});

// Stream video
app.get('/api/stream', (req, res) => {
  const filePath = req.query.path;
  if (!filePath) return res.status(400).json({ error: 'Missing path' });
  if (!isSafePath(filePath)) return res.status(403).json({ error: 'Access denied' });
  if (!existsSync(filePath)) return res.status(404).json({ error: 'File not found' });

  const fileStat = statSync(filePath);
  const fileSize = fileStat.size;
  const range = req.headers.range;
  const ext = extname(filePath).toLowerCase();
  const mimeTypes = {
    '.mp4': 'video/mp4',
    '.mov': 'video/quicktime',
    '.mkv': 'video/x-matroska',
    '.webm': 'video/webm',
    '.avi': 'video/x-msvideo',
    '.wmv': 'video/x-ms-wmv',
    '.flv': 'video/x-flv',
    '.ts': 'video/mp2t',
    '.m4v': 'video/mp4',
    '.mts': 'video/mp2t',
  };
  const contentType = mimeTypes[ext] || 'video/mp4';

  if (range) {
    const parts = range.replace(/bytes=/, '').split('-');
    const start = parseInt(parts[0], 10);
    const end = parts[1] ? parseInt(parts[1], 10) : fileSize - 1;
    res.writeHead(206, {
      'Content-Range': `bytes ${start}-${end}/${fileSize}`,
      'Accept-Ranges': 'bytes',
      'Content-Length': end - start + 1,
      'Content-Type': contentType,
    });
    createReadStream(filePath, { start, end }).pipe(res);
  } else {
    res.writeHead(200, { 'Content-Length': fileSize, 'Content-Type': contentType });
    createReadStream(filePath).pipe(res);
  }
});

// Thumbnail
app.get('/api/thumbnail', (req, res) => {
  const filePath = req.query.path;
  const time = req.query.time || '00:00:02';
  const width = parseInt(req.query.width) || 320;
  if (!filePath) return res.status(400).json({ error: "Query parameter 'path' is required" });
  if (!isSafePath(filePath)) return res.status(403).json({ error: 'Access denied' });
  if (!existsSync(filePath)) return res.status(404).json({ error: 'File not found' });

  const proc = spawn(
    FFMPEG_PATH,
    [
      '-ss',
      String(time),
      '-i',
      filePath,
      '-vframes',
      '1',
      '-vf',
      `scale=${width}:-1`,
      '-f',
      'image2',
      '-c:v',
      'mjpeg',
      '-q:v',
      '5',
      'pipe:1',
    ],
    { stdio: ['ignore', 'pipe', 'ignore'] },
  );

  const chunks = [];
  proc.stdout.on('data', (chunk) => chunks.push(chunk));
  proc.on('close', (code) => {
    if (code !== 0 || chunks.length === 0)
      return res.status(500).json({ error: 'Thumbnail generation failed' });
    const buffer = Buffer.concat(chunks);
    res.writeHead(200, {
      'Content-Type': 'image/jpeg',
      'Content-Length': buffer.length,
      'Cache-Control': 'public, max-age=3600',
    });
    res.end(buffer);
  });
});

// Compress
app.post('/api/compress', async (req, res) => {
  const {
    files,
    preset,
    codec,
    format,
    trim,
    crop,
    scale,
    crf,
    speed,
    audioBitrate = 192,
    audioCodec = 'aac',
    fps = 'original',
    twoPass = false,
    preserveMetadata = true,
    fastStart = true,
  } = req.body;
  if (!files || !Array.isArray(files) || files.length === 0)
    return res.status(400).json({ error: 'Missing required field: files' });
  if (!preset) return res.status(400).json({ error: 'Missing required field: preset' });
  if (!codec) return res.status(400).json({ error: 'Missing required field: codec' });
  if (!format) return res.status(400).json({ error: 'Missing required field: format' });

  // Validate all paths before processing
  for (const file of files) {
    if (!isSafePath(file.path)) {
      return res.status(403).json({ error: 'Access denied' });
    }
  }

  const jobs = [];
  for (const file of files) {
    const inputPath = file.path;
    if (!existsSync(inputPath))
      return res.status(404).json({ error: `File not found: ${inputPath}` });

    const inputDir = dirname(inputPath);
    const isUploadedFile = resolve(inputDir).startsWith(resolve(UPLOAD_DIR));
    const outputDir = isUploadedFile ? OUTPUT_DIR : inputDir;
    const inputName = isUploadedFile
      ? basename(file.name || inputPath, extname(file.name || inputPath))
      : basename(inputPath, extname(inputPath));
    const outputExt = format === 'mkv' ? '.mkv' : format === 'mov' ? '.mov' : '.mp4';
    let outputName = `${inputName}_COMP${outputExt}`;
    let outputPath = join(outputDir, outputName);
    let counter = 2;
    while (existsSync(outputPath)) {
      outputName = `${inputName}_COMP_${counter}${outputExt}`;
      outputPath = join(outputDir, outputName);
      counter++;
    }

    let metadata;
    try {
      metadata = await probe(inputPath);
    } catch (err) {
      return res.status(500).json({ error: `Failed to probe: ${inputPath}: ${err.message}` });
    }

    const buildOptions = {
      inputPath,
      outputPath,
      preset,
      codec,
      format,
      hwAccel: hwaccelCapabilities,
      trim: trim || null,
      crop: crop || null,
      scale: scale || 'original',
      sourceBitrate: metadata.bitrate || 0,
      sourceHeight: metadata.height || null,
      sourceWidth: metadata.width || null,
      crf: crf !== undefined ? crf : null,
      speed: speed || null,
      audioBitrate: Number(audioBitrate) || 192,
      audioCodec: audioCodec || 'aac',
      fps: fps || 'original',
      twoPass: !!twoPass,
      preserveMetadata: preserveMetadata !== false,
      fastStart: fastStart !== false,
    };

    // Determine if two-pass is viable (software encoders only)
    const hwAvailable =
      (codec === 'h264' && hwaccelCapabilities?.h264_videotoolbox) ||
      (codec === 'h265' && hwaccelCapabilities?.hevc_videotoolbox) ||
      (codec === 'prores' && hwaccelCapabilities?.prores_videotoolbox);
    const useTwoPass = twoPass && !hwAvailable && codec !== 'prores';

    let ffmpegArgs;
    let pass1Args = null;
    let passlogFile = null;

    if (useTwoPass) {
      passlogFile = join(tmpdir(), `ffmpeg2pass-${uuidv4()}`);
      const twoPassCmds = buildTwoPassCommands(buildOptions, passlogFile);
      pass1Args = twoPassCmds.pass1Args;
      ffmpegArgs = twoPassCmds.pass2Args;
    } else {
      ffmpegArgs = buildCommand(buildOptions);
    }

    const fileStat = await stat(inputPath);

    const job = jobQueue.addJob({
      inputPath,
      outputPath,
      preset,
      codec,
      format,
      ffmpegArgs,
      pass1Args,
      passlogFile,
      duration: metadata.duration,
      originalSize: fileStat.size,
    });

    // Clean up passlog files when the job completes or errors
    if (passlogFile) {
      const cleanupPasslog = async () => {
        for (const suffix of ['', '-0.log', '-0.log.mbtree']) {
          try {
            await unlink(`${passlogFile}${suffix}`);
          } catch (_) {
            /* file may not exist */
          }
        }
      };
      jobQueue.once(`complete:${job.id}`, cleanupPasslog);
      jobQueue.once(`error:${job.id}`, cleanupPasslog);
    }

    jobs.push({
      id: job.id,
      status: job.status,
      inputPath,
      outputPath,
      fileName: file.name || basename(inputPath),
    });
  }
  res.json({ jobs });
});

app.get('/api/jobs', (req, res) => {
  res.json({ jobs: jobQueue.getJobs() });
});

app.delete('/api/jobs/:id', (req, res) => {
  const { id } = req.params;
  const job = jobQueue.getJob(id);
  if (!job) return res.status(404).json({ error: `Job not found: ${id}` });
  if (job.status === 'complete') return res.status(409).json({ error: 'Job already completed' });
  const cancelled = jobQueue.cancelJob(id);
  res.json({ cancelled, id });
});

app.get('/api/hwaccel', (req, res) => {
  res.json(hwaccelCapabilities);
});

// ExifTool status
app.get('/api/exiftool', async (req, res) => {
  try {
    const status = await detectExifTool();
    res.json(status);
  } catch (err) {
    res.status(500).json({ error: `ExifTool detection failed: ${err.message}` });
  }
});

// Read all metadata from a file
app.get('/api/metadata', async (req, res) => {
  const filePath = req.query.path;
  if (!filePath) return res.status(400).json({ error: "Query parameter 'path' is required" });
  if (!isSafePath(filePath)) return res.status(403).json({ error: 'Access denied' });
  if (!existsSync(filePath)) return res.status(404).json({ error: 'File not found' });
  try {
    const metadata = await readMetadataJson(filePath);
    res.json(metadata);
  } catch (err) {
    res.status(500).json({ error: `Failed to read metadata: ${err.message}` });
  }
});

// Surgical metadata cleaning
app.post('/api/metaclean', async (req, res) => {
  const { files, mode } = req.body;
  if (!files || !Array.isArray(files) || files.length === 0) {
    return res.status(400).json({ error: 'Missing required field: files' });
  }

  const validMode = mode === 'privacy' ? 'privacy' : 'attribution';
  const results = [];

  for (const file of files) {
    const filePath = file.path;
    if (!isSafePath(filePath)) {
      results.push({ path: filePath, error: 'Access denied', success: false });
      continue;
    }
    if (!existsSync(filePath)) {
      results.push({ path: filePath, error: 'File not found', success: false });
      continue;
    }

    try {
      // Read metadata
      const metadata = await readMetadataJson(filePath);

      // Compute removals
      const removals = computeRemovals(metadata, validMode);

      if (removals.count === 0) {
        results.push({
          path: filePath,
          name: file.name,
          status: 'clean',
          success: true,
          outputPath: null,
          removedCount: 0,
          removed: [],
          message: 'No matching tags found to remove',
        });
        broadcast({ type: 'metaclean-complete', filePath, removedCount: 0 });
        continue;
      }

      // Write clean copy
      const outputPath = await writeCleanCopy(filePath, removals.tags);

      // Generate report
      const report = await generateReport(filePath, outputPath, removals.tags);

      results.push({
        path: filePath,
        name: file.name,
        status: 'cleaned',
        success: true,
        outputPath,
        removedCount: report.removedCount,
        removed: report.removed,
        preserved: report.preserved,
        preservedCount: report.preservedCount,
      });

      broadcast({
        type: 'metaclean-complete',
        filePath,
        outputPath,
        name: file.name,
        removedCount: report.removedCount,
        removed: report.removed,
      });
    } catch (err) {
      results.push({
        path: filePath,
        name: file.name,
        success: false,
        error: err.message,
      });
      broadcast({ type: 'metaclean-error', filePath, error: err.message });
    }
  }

  res.json({ results, mode: validMode });
});

// Probe clips for stitch compatibility
app.post('/api/stitch/probe', async (req, res) => {
  const { paths } = req.body;
  if (!paths || !Array.isArray(paths) || paths.length === 0) {
    return res.status(400).json({ error: "Body field 'paths' (array) is required" });
  }

  if (paths.length < 2) {
    return res.status(400).json({ error: 'At least 2 clip paths are required' });
  }

  for (const p of paths) {
    if (!isSafePath(p)) return res.status(403).json({ error: 'Access denied' });
  }

  const clips = paths.map((path) => ({ path, name: basename(path) }));

  try {
    const result = await probeClips(clips);
    res.json(result);
  } catch (err) {
    res.status(500).json({ error: `Probe failed: ${err.message}` });
  }
});

// Stitch (concatenate) clips
app.post('/api/stitch', async (req, res) => {
  const { clips, compress, preset, codec, format } = req.body;
  if (!clips || !Array.isArray(clips) || clips.length < 2) {
    return res.status(400).json({ error: 'At least 2 clips are required' });
  }

  // Validate all clip paths are safe and exist
  for (const clip of clips) {
    if (!clip.path || !isSafePath(clip.path)) {
      return res.status(403).json({ error: 'Access denied' });
    }
    if (!existsSync(clip.path)) {
      return res.status(404).json({ error: `Clip not found: ${clip.path}` });
    }
  }

  try {
    // Probe clips for compatibility info
    const probeResult = await probeClips(clips);

    // Perform stitch
    const result = await stitch(clips, {
      compress: !!compress,
      codec: codec || 'h265',
      format: format || 'mp4',
      preset: preset || 'medium',
    });

    // Get output file size
    const outputStat = await stat(result.outputPath);

    broadcast({
      type: 'stitch-complete',
      outputPath: result.outputPath,
      method: result.method,
      outputSize: outputStat.size,
    });

    res.json({
      success: true,
      outputPath: result.outputPath,
      method: result.method,
      outputSize: outputStat.size,
      compatible: probeResult.compatible,
      reasons: probeResult.reasons,
    });
  } catch (err) {
    broadcast({ type: 'stitch-error', error: err.message });
    res.status(500).json({ error: `Stitch failed: ${err.message}` });
  }
});

app.get('/api/download', (req, res) => {
  const filePath = req.query.path;
  if (!filePath) return res.status(400).json({ error: "Query parameter 'path' is required" });
  if (!isSafePath(filePath)) return res.status(403).json({ error: 'Access denied' });
  if (!existsSync(filePath)) return res.status(404).json({ error: 'File not found' });

  const fileStat = statSync(filePath);
  const fileName = basename(filePath);
  const ext = extname(filePath).toLowerCase();
  const mimeTypes = {
    '.mp4': 'video/mp4',
    '.mov': 'video/quicktime',
    '.mkv': 'video/x-matroska',
    '.webm': 'video/webm',
    '.avi': 'video/x-msvideo',
    '.heic': 'image/heic',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.png': 'image/png',
  };
  const contentType = mimeTypes[ext] || 'application/octet-stream';

  res.writeHead(200, {
    'Content-Type': contentType,
    'Content-Length': fileStat.size,
    'Content-Disposition': `attachment; filename="${encodeURIComponent(fileName)}"`,
  });
  createReadStream(filePath).pipe(res);
});

function shutdown() {
  console.log('\nShutting down...');
  for (const client of wsClients) client.close();
  server.close(() => {
    console.log('Server closed.');
    process.exit(0);
  });
  setTimeout(() => process.exit(1), 5000);
}
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);

server.listen(PORT, '127.0.0.1', () => {
  console.log(`\n  Video Compressor ready at http://localhost:${PORT}\n`);
  console.log(
    `  Hardware acceleration: ${hwaccelCapabilities.h264_videotoolbox ? 'VideoToolbox' : 'Software only'}`,
  );
  console.log(`  FFmpeg: ${FFMPEG_PATH}`);
  console.log(`  Upload dir: ${UPLOAD_DIR}\n`);
});
