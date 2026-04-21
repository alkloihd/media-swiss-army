import { execFile, spawn } from 'child_process';
import { promisify } from 'util';
import { existsSync } from 'fs';
import { basename, dirname, extname, join } from 'path';

const execFileAsync = promisify(execFile);

// Common ExifTool paths on macOS
const EXIFTOOL_PATHS = [
  '/opt/homebrew/bin/exiftool',
  '/usr/local/bin/exiftool',
  '/usr/bin/exiftool',
];

let cachedDetection = null;

/**
 * Detect ExifTool installation. Cached after first call.
 */
export async function detectExifTool() {
  if (cachedDetection !== null) return cachedDetection;

  for (const toolPath of EXIFTOOL_PATHS) {
    if (!existsSync(toolPath)) continue;
    try {
      const { stdout } = await execFileAsync(toolPath, ['-ver'], { timeout: 5000 });
      cachedDetection = Object.freeze({
        installed: true,
        version: stdout.trim(),
        path: toolPath,
      });
      return cachedDetection;
    } catch {
      continue;
    }
  }

  // Try 'exiftool' from PATH
  try {
    const { stdout } = await execFileAsync('exiftool', ['-ver'], { timeout: 5000 });
    cachedDetection = Object.freeze({
      installed: true,
      version: stdout.trim(),
      path: 'exiftool',
    });
    return cachedDetection;
  } catch {
    // not found
  }

  cachedDetection = Object.freeze({ installed: false, version: null, path: null });
  return cachedDetection;
}

/**
 * Read all metadata from a file as structured JSON.
 * Uses -G1 for group names, -a for duplicates, -s for tag names.
 */
export async function readMetadataJson(filePath) {
  const tool = await detectExifTool();
  if (!tool.installed) throw new Error('ExifTool is not installed');

  const { stdout } = await execFileAsync(tool.path, ['-json', '-G1', '-a', '-s', filePath], {
    timeout: 30000,
  });

  let parsed;
  try {
    parsed = JSON.parse(stdout);
  } catch {
    throw new Error(`ExifTool returned invalid JSON for "${basename(filePath)}"`);
  }
  return Array.isArray(parsed) ? parsed[0] : parsed;
}

/**
 * Compute which tags to remove based on mode.
 *
 * Modes:
 *   'attribution' — Remove Meta/Ray-Ban branding tags only
 *   'privacy'     — Attribution + UUIDs, serial numbers, descriptions
 *
 * Returns { tags: [{group, tag, oldValue}], count }
 */
export function computeRemovals(metadata, mode = 'attribution') {
  const META_PATTERN = /(meta|ray-?ban|meta ai|meta view)/i;
  const removals = [];

  // Attribution tags: Make, Model, Comment, Copyright where value matches Meta pattern
  const attributionTags = [
    'Make',
    'Model',
    'Comment',
    'Copyright',
    'Software',
    'CameraModelName',
    'LensMake',
    'LensModel',
  ];

  // Pre-scan: check if this file has ANY Meta attribution (to handle binary data)
  const hasMetaAttribution = Object.values(metadata).some((v) => META_PATTERN.test(String(v)));

  for (const [fullKey, value] of Object.entries(metadata)) {
    if (fullKey === 'SourceFile') continue;
    const strValue = String(value);

    // Extract group and tag from "Group:Tag" format
    const colonIdx = fullKey.indexOf(':');
    const group = colonIdx > -1 ? fullKey.slice(0, colonIdx) : '';
    const tag = colonIdx > -1 ? fullKey.slice(colonIdx + 1) : fullKey;

    // Check attribution tags — match on Meta pattern OR binary data in confirmed Meta files
    // Binary data in QuickTime/MOV Comments hides device fingerprints (app ID, device UUID)
    const isAttributionTag = attributionTags.some((t) => tag.toLowerCase() === t.toLowerCase());
    const isBinaryInMetaFile = hasMetaAttribution && strValue.startsWith('(Binary data');
    if (isAttributionTag && (META_PATTERN.test(strValue) || isBinaryInMetaFile)) {
      removals.push({ group, tag, fullKey, oldValue: strValue });
      continue;
    }

    // In confirmed Meta files: strip Description (device firmware codes like "2Q")
    // and CreationDate (redundant with CreateDate, but unique QuickTime Keys format)
    if (
      hasMetaAttribution &&
      (tag === 'Description' || tag === 'CreationDate') &&
      group === 'Keys'
    ) {
      removals.push({ group, tag, fullKey, oldValue: strValue });
      continue;
    }

    // Privacy mode: additional tags
    if (mode === 'privacy') {
      // UserComment often contains UUIDs
      if (tag === 'UserComment' || tag === 'ImageUniqueID') {
        removals.push({ group, tag, fullKey, oldValue: strValue });
        continue;
      }
      // Serial numbers
      if (tag === 'SerialNumber' || tag === 'InternalSerialNumber') {
        removals.push({ group, tag, fullKey, oldValue: strValue });
        continue;
      }
      // SubSec timestamps (can fingerprint)
      if (tag.startsWith('SubSec')) {
        removals.push({ group, tag, fullKey, oldValue: strValue });
        continue;
      }
      // Description/Caption that matches Meta pattern
      if (
        (tag === 'Description' || tag === 'Caption-Abstract' || tag === 'ImageDescription') &&
        META_PATTERN.test(strValue)
      ) {
        removals.push({ group, tag, fullKey, oldValue: strValue });
        continue;
      }
      // Android version info
      if (tag === 'AndroidVersion' || tag === 'AndroidModel') {
        removals.push({ group, tag, fullKey, oldValue: strValue });
        continue;
      }
      // GPS / location data (any tag starting with GPS)
      if (tag.startsWith('GPS')) {
        removals.push({ group, tag, fullKey, oldValue: strValue });
        continue;
      }
    }
  }

  return { tags: removals, count: removals.length };
}

/**
 * Write a clean copy of the file with specified tags removed.
 * NEVER uses -all= (surgical removal only).
 *
 * Output: {inputName}_CLEAN.{ext} in same directory
 */
export async function writeCleanCopy(inputPath, removals) {
  const tool = await detectExifTool();
  if (!tool.installed) throw new Error('ExifTool is not installed');

  const dir = dirname(inputPath);
  const ext = extname(inputPath);
  const name = basename(inputPath, ext);
  let outputPath = join(dir, `${name}_CLEAN${ext}`);

  // Handle existing files
  let counter = 2;
  while (existsSync(outputPath)) {
    outputPath = join(dir, `${name}_CLEAN_${counter}${ext}`);
    counter++;
  }

  // Build removal args: -TAG= for each tag to remove
  const args = ['-overwrite_original'];
  for (const removal of removals) {
    // Use full key (Group:Tag) when group is available for precision
    const key = removal.group ? `${removal.group}:${removal.tag}` : removal.tag;
    args.push(`-${key}=`);
  }

  // Copy source to output first, then strip from the copy
  const { copyFile } = await import('fs/promises');
  await copyFile(inputPath, outputPath);

  // Apply removals to the copy
  args.push(outputPath);

  await execFileAsync(tool.path, args, { timeout: 30000 });
  return outputPath;
}

/**
 * Generate a before/after report.
 */
export async function generateReport(inputPath, outputPath, removals) {
  const outputMeta = await readMetadataJson(outputPath);

  const removed = removals.map((r) => ({
    group: r.group,
    tag: r.tag,
    oldValue: r.oldValue,
  }));

  // Collect preserved tags (excluding SourceFile and ExifTool metadata)
  const preserved = Object.entries(outputMeta)
    .filter(([k]) => k !== 'SourceFile' && !k.startsWith('ExifTool:'))
    .map(([key, value]) => {
      const parts = key.split(':');
      const group = parts.length > 1 ? parts[0] : 'Other';
      const tag = parts.length > 1 ? parts.slice(1).join(':') : key;
      return { group, tag, value: String(value).substring(0, 120) };
    });

  return {
    removed,
    removedCount: removed.length,
    preserved,
    preservedCount: preserved.length,
    inputPath,
    outputPath,
  };
}

/**
 * Deep clean: re-encode video through FFmpeg to strip resolution fingerprint
 * and rebuild the container from scratch. This removes ALL hidden atoms,
 * vendor-specific data, and changes the resolution to a standard size.
 *
 * Used for Meta glasses videos where Instagram identifies the device from
 * the unique 1600x2128 resolution even after metadata stripping.
 */
export function deepCleanVideo(inputPath) {
  const FFMPEG = '/opt/homebrew/bin/ffmpeg';
  const dir = dirname(inputPath);
  const ext = extname(inputPath);
  const name = basename(inputPath, ext);

  // Output as MP4 (standard container, no QuickTime vendor atoms)
  let outputPath = join(dir, `${name}_DEEPCLEAN.mp4`);
  let counter = 2;
  while (existsSync(outputPath)) {
    outputPath = join(dir, `${name}_DEEPCLEAN_${counter}.mp4`);
    counter++;
  }

  return new Promise((resolve, reject) => {
    // Re-encode to standard 1080 portrait (1080x1440) or landscape depending on aspect
    // -map_metadata -1 strips ALL metadata from the container
    // -fflags +bitexact prevents writing encoder-specific atoms
    // scale to nearest standard resolution, keep aspect ratio
    const args = [
      '-i',
      inputPath,
      '-map_metadata',
      '-1', // Strip ALL metadata from output
      '-fflags',
      '+bitexact', // Don't write encoder strings
      '-vf',
      'scale=-2:1080', // Standard 1080p height
      '-c:v',
      'libx264', // Generic encoder (no VideoToolbox fingerprint)
      '-preset',
      'fast',
      '-crf',
      '18', // High quality
      '-c:a',
      'aac',
      '-b:a',
      '192k',
      '-movflags',
      '+faststart',
      '-y',
      outputPath,
    ];

    const proc = spawn(FFMPEG, args, { stdio: ['ignore', 'pipe', 'pipe'] });
    let stderr = '';

    proc.stderr.on('data', (chunk) => {
      stderr += chunk.toString();
    });

    proc.on('error', (err) => reject(new Error(`FFmpeg failed to start: ${err.message}`)));

    proc.on('close', (code) => {
      if (code === 0) {
        resolve(outputPath);
      } else {
        reject(new Error(`FFmpeg deep clean failed (code ${code}): ${stderr.slice(-500)}`));
      }
    });
  });
}
