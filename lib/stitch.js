import { spawn } from 'child_process';
import { writeFile, unlink } from 'fs/promises';
import { existsSync } from 'fs';
import { dirname, basename, extname, join } from 'path';
import { tmpdir } from 'os';
import { v4 as uuidv4 } from 'uuid';
import { probe } from './probe.js';
import { getEncoder, detectHWAccel } from './hwaccel.js';

const FFMPEG_PATH = '/opt/homebrew/bin/ffmpeg';

/**
 * Probe all clips and check compatibility for lossless concat.
 * Returns { compatible, clips, reasons[] }
 */
export async function probeClips(clips) {
  const probed = [];
  const reasons = [];

  for (const clip of clips) {
    try {
      const meta = await probe(clip.path);
      probed.push({ ...clip, meta });
    } catch (err) {
      reasons.push(`Failed to probe ${clip.name || clip.path}: ${err.message}`);
      probed.push({ ...clip, meta: null });
    }
  }

  const validClips = probed.filter((c) => c.meta !== null);
  if (validClips.length < 2) {
    return { compatible: false, clips: probed, reasons: ['Need at least 2 valid clips'] };
  }

  // Check codec/resolution/fps compatibility
  const ref = validClips[0].meta;
  let compatible = true;

  for (let i = 1; i < validClips.length; i++) {
    const m = validClips[i].meta;
    if (m.codec !== ref.codec) {
      reasons.push(`Codec mismatch: clip 1 is ${ref.codec}, clip ${i + 1} is ${m.codec}`);
      compatible = false;
    }
    if (m.width !== ref.width || m.height !== ref.height) {
      reasons.push(
        `Resolution mismatch: clip 1 is ${ref.width}x${ref.height}, clip ${i + 1} is ${m.width}x${m.height}`,
      );
      compatible = false;
    }
    if (Math.abs(m.fps - ref.fps) > 0.5) {
      reasons.push(`FPS mismatch: clip 1 is ${ref.fps}, clip ${i + 1} is ${m.fps}`);
      compatible = false;
    }
  }

  // If any clips have trims, can't do lossless
  const hasTrims = clips.some((c) => c.trimStart || c.trimEnd);
  if (hasTrims) {
    reasons.push('Clips have trim points — re-encode required');
    compatible = false;
  }

  return { compatible, clips: probed, reasons };
}

/**
 * Lossless concat using -c copy (Path A).
 * All clips must have same codec/resolution/fps.
 */
export async function stitchLossless(clips, outputPath) {
  // Write concat list file
  const listPath = join(tmpdir(), `stitch-${uuidv4()}.txt`);
  const listContent = clips.map((c) => `file '${c.path.replace(/'/g, "'\\''")}'`).join('\n');
  await writeFile(listPath, listContent);

  return new Promise((resolve, reject) => {
    const args = [
      '-y',
      '-f',
      'concat',
      '-safe',
      '0',
      '-i',
      listPath,
      '-c',
      'copy',
      '-map_metadata',
      '0',
      '-movflags',
      '+faststart+use_metadata_tags',
      outputPath,
    ];

    const proc = spawn(FFMPEG_PATH, args, { stdio: ['ignore', 'pipe', 'pipe'] });

    let stderr = '';
    proc.stderr.on('data', (chunk) => {
      stderr += chunk.toString();
    });

    proc.on('error', (err) => {
      unlink(listPath).catch(() => {});
      reject(new Error(`FFmpeg failed to start: ${err.message}`));
    });

    proc.on('close', (code) => {
      unlink(listPath).catch(() => {});
      if (code === 0) {
        resolve({ outputPath, method: 'lossless' });
      } else {
        reject(new Error(`FFmpeg concat exited with code ${code}: ${stderr.slice(-500)}`));
      }
    });
  });
}

/**
 * Re-encode concat using filter_complex (Path B).
 * Handles different codecs, resolutions, and per-clip trims.
 *
 * `options.codec` accepts friendly names (h264, h265, prores, av1) or FFmpeg
 * encoder names — getEncoder() maps them to the correct encoder after HW
 * detection, matching the same logic used by buildCommand() in ffmpeg.js.
 */
export async function stitchReencode(clips, outputPath, options = {}) {
  // Resolve friendly codec name → FFmpeg encoder name via HW detection
  const friendlyCodec = options.codec || 'h264';
  const hwAccel = await detectHWAccel();
  const hwAvailable =
    (friendlyCodec === 'h264' && !!hwAccel.h264_videotoolbox) ||
    (friendlyCodec === 'h265' && !!hwAccel.hevc_videotoolbox) ||
    (friendlyCodec === 'prores' && !!hwAccel.prores_videotoolbox);
  const encoder = getEncoder(friendlyCodec, hwAvailable);

  const { preset = 'medium', crf = '23', width = null, height = null } = options;

  return new Promise((resolve, reject) => {
    const args = ['-y'];

    // Input files with optional trim
    for (const clip of clips) {
      if (clip.trimStart) args.push('-ss', String(clip.trimStart));
      if (clip.trimEnd) args.push('-to', String(clip.trimEnd));
      args.push('-i', clip.path);
    }

    // Build filter_complex for normalization + concat
    const n = clips.length;
    const filterParts = [];
    let concatInputs = '';

    for (let i = 0; i < n; i++) {
      if (width && height) {
        filterParts.push(
          `[${i}:v]scale=${width}:${height}:force_original_aspect_ratio=decrease,pad=${width}:${height}:(ow-iw)/2:(oh-ih)/2,setsar=1[v${i}]`,
        );
      } else {
        filterParts.push(`[${i}:v]setsar=1[v${i}]`);
      }
      filterParts.push(`[${i}:a]aformat=sample_rates=48000:channel_layouts=stereo[a${i}]`);
      concatInputs += `[v${i}][a${i}]`;
    }

    filterParts.push(`${concatInputs}concat=n=${n}:v=1:a=1[outv][outa]`);
    const filterComplex = filterParts.join(';');

    args.push('-filter_complex', filterComplex);
    args.push('-map', '[outv]', '-map', '[outa]');
    args.push('-c:v', encoder);

    // Quality settings — matched to the same encoder names used by ffmpeg.js
    if (encoder === 'libx264') {
      args.push('-crf', String(crf), '-preset', preset);
    } else if (encoder === 'libx265') {
      args.push('-crf', String(crf), '-preset', preset, '-tag:v', 'hvc1');
    } else if (encoder === 'h264_videotoolbox') {
      args.push('-b:v', '8000k', '-profile:v', 'high');
    } else if (encoder === 'hevc_videotoolbox') {
      args.push('-b:v', '6000k', '-tag:v', 'hvc1');
    } else if (encoder === 'prores_videotoolbox' || encoder === 'prores_ks') {
      args.push('-profile:v', '2');
    } else if (encoder === 'libsvtav1') {
      args.push('-crf', String(crf), '-preset', '6');
    }

    // Audio codec — mirrors getAudioFlags() in ffmpeg.js (keyed on friendly name)
    if (friendlyCodec === 'prores') {
      args.push('-c:a', 'pcm_s16le');
    } else if (friendlyCodec === 'av1') {
      args.push('-c:a', 'libopus', '-b:a', '128k');
    } else {
      args.push('-c:a', 'aac', '-b:a', '192k');
    }

    args.push('-movflags', '+faststart+use_metadata_tags');
    args.push(outputPath);

    const proc = spawn(FFMPEG_PATH, args, { stdio: ['ignore', 'pipe', 'pipe'] });

    let stderr = '';
    proc.stderr.on('data', (chunk) => {
      stderr += chunk.toString();
    });

    proc.on('error', (err) => {
      reject(new Error(`FFmpeg failed to start: ${err.message}`));
    });

    proc.on('close', (code) => {
      if (code === 0) {
        resolve({ outputPath, method: 'reencode' });
      } else {
        reject(new Error(`FFmpeg stitch exited with code ${code}: ${stderr.slice(-500)}`));
      }
    });
  });
}

/**
 * Auto-select lossless or re-encode path.
 */
export async function stitch(clips, options = {}) {
  const probeResult = await probeClips(clips);

  // Determine output path
  const firstClip = clips[0];
  const dir = dirname(firstClip.path);
  const ext = options.format === 'mov' ? '.mov' : options.format === 'mkv' ? '.mkv' : '.mp4';
  const firstName = basename(firstClip.path, extname(firstClip.path));
  const clipNums = clips.map((_, i) => i + 1).join('-');
  const suffix = options.compress ? '_STITCH_' + clipNums + '_COMP' : '_STITCH_' + clipNums;
  let outputPath = join(dir, `${firstName}${suffix}${ext}`);

  let counter = 2;
  while (existsSync(outputPath)) {
    outputPath = join(dir, `${firstName}${suffix}_${counter}${ext}`);
    counter++;
  }

  if (probeResult.compatible && !options.compress) {
    // Path A: lossless concat
    return stitchLossless(clips, outputPath);
  } else {
    // Path B: re-encode
    const ref = probeResult.clips.find((c) => c.meta)?.meta;
    return stitchReencode(clips, outputPath, {
      codec: options.codec || 'h264',
      preset: options.preset || 'medium',
      crf: options.crf || '23',
      width: ref?.width || null,
      height: ref?.height || null,
    });
  }
}
