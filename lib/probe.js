import { execFile } from 'child_process';
import { stat } from 'fs/promises';
import { promisify } from 'util';

const execFileAsync = promisify(execFile);
const FFPROBE_PATH = '/opt/homebrew/bin/ffprobe';

const _cache = new Map();

export async function probe(filePath) {
  let mtimeMs = 0;
  try {
    const s = await stat(filePath);
    mtimeMs = s.mtimeMs;
    const hit = _cache.get(filePath);
    if (hit && hit.mtimeMs === mtimeMs) return hit.data;
  } catch {
    // if stat fails, fall through to ffprobe which will surface a better error
  }

  let stdout;
  try {
    const result = await execFileAsync(
      FFPROBE_PATH,
      ['-v', 'quiet', '-print_format', 'json', '-show_streams', '-show_format', filePath],
      { timeout: 30_000 },
    );
    stdout = result.stdout;
  } catch (err) {
    throw new Error(`ffprobe failed for "${filePath}": ${err.stderr || err.message}`);
  }

  let data;
  try {
    data = JSON.parse(stdout);
  } catch {
    throw new Error(`ffprobe returned invalid JSON for "${filePath}"`);
  }

  if (!data.streams || !Array.isArray(data.streams))
    throw new Error(`No streams found in "${filePath}"`);

  const videoStream = data.streams.find((s) => s.codec_type === 'video');
  if (!videoStream) throw new Error(`"${filePath}" does not contain a video stream.`);

  const audioStream = data.streams.find((s) => s.codec_type === 'audio');
  const fps = parseFps(videoStream.r_frame_rate);
  const format = data.format || {};

  const duration = parseFloat(format.duration) || 0;
  const fileSize = parseInt(format.size, 10) || 0;
  let bitrate = parseInt(format.bit_rate, 10) || 0;
  if (bitrate === 0 && duration > 0 && fileSize > 0) {
    bitrate = Math.round((fileSize * 8) / duration);
  }

  const data2 = {
    duration,
    width: parseInt(videoStream.width, 10) || 0,
    height: parseInt(videoStream.height, 10) || 0,
    fps,
    codec: videoStream.codec_name || 'unknown',
    bitrate,
    size: fileSize,
    format: format.format_name || 'unknown',
    audioCodec: audioStream ? audioStream.codec_name : null,
  };

  if (mtimeMs) _cache.set(filePath, { mtimeMs, data: data2 });
  return data2;
}

function parseFps(rateStr) {
  if (!rateStr) return 0;
  const parts = rateStr.split('/');
  if (parts.length === 2) {
    const num = parseFloat(parts[0]);
    const den = parseFloat(parts[1]);
    if (den !== 0) return Math.round((num / den) * 1000) / 1000;
  }
  const parsed = parseFloat(rateStr);
  return Number.isFinite(parsed) ? parsed : 0;
}
