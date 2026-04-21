import { getEncoder } from './hwaccel.js';

// Legacy preset name aliases for backward compatibility
const PRESET_ALIASES = {
  max: 'maximum',
  small: 'compact',
  streaming: 'balanced',
};

// Normalize preset name: map legacy names to 6-tier names
function normalizePreset(preset) {
  return PRESET_ALIASES[preset] || preset;
}

const QUALITY_PRESETS = {
  h264_videotoolbox: {
    lossless: ['-b:v', '40000k', '-profile:v', 'high'],
    maximum: ['-b:v', '20000k', '-profile:v', 'high'],
    high: ['-b:v', '12000k', '-profile:v', 'high'],
    balanced: ['-b:v', '8000k', '-profile:v', 'high'],
    compact: ['-b:v', '4000k', '-profile:v', 'main'],
    tiny: ['-b:v', '1500k', '-profile:v', 'main'],
  },
  libx264: {
    lossless: ['-crf', '0', '-preset', 'slow'],
    maximum: ['-crf', '15', '-preset', 'medium'],
    high: ['-crf', '20', '-preset', 'fast'],
    balanced: ['-crf', '23', '-preset', 'fast'],
    compact: ['-crf', '30', '-preset', 'fast'],
    tiny: ['-crf', '38', '-preset', 'veryfast'],
  },
  hevc_videotoolbox: {
    lossless: ['-b:v', '30000k', '-tag:v', 'hvc1'],
    maximum: ['-b:v', '15000k', '-tag:v', 'hvc1'],
    high: ['-b:v', '8000k', '-tag:v', 'hvc1'],
    balanced: ['-b:v', '5000k', '-tag:v', 'hvc1'],
    compact: ['-b:v', '2500k', '-tag:v', 'hvc1'],
    tiny: ['-b:v', '1000k', '-tag:v', 'hvc1'],
  },
  libx265: {
    lossless: ['-crf', '0', '-preset', 'slow', '-tag:v', 'hvc1'],
    maximum: ['-crf', '18', '-preset', 'medium', '-tag:v', 'hvc1'],
    high: ['-crf', '23', '-preset', 'fast', '-tag:v', 'hvc1'],
    balanced: ['-crf', '28', '-preset', 'fast', '-tag:v', 'hvc1'],
    compact: ['-crf', '34', '-preset', 'fast', '-tag:v', 'hvc1'],
    tiny: ['-crf', '42', '-preset', 'veryfast', '-tag:v', 'hvc1'],
  },
  libsvtav1: {
    lossless: ['-crf', '0', '-preset', '4'],
    maximum: ['-crf', '20', '-preset', '6'],
    high: ['-crf', '27', '-preset', '6'],
    balanced: ['-crf', '32', '-preset', '6'],
    compact: ['-crf', '40', '-preset', '8'],
    tiny: ['-crf', '50', '-preset', '12'],
  },
  prores_videotoolbox: {
    lossless: ['-profile:v', '3'],
    maximum: ['-profile:v', '3'],
    high: ['-profile:v', '3'],
    balanced: ['-profile:v', '2'],
    compact: ['-profile:v', '1'],
    tiny: ['-profile:v', '1'],
  },
  prores_ks: {
    lossless: ['-profile:v', '3'],
    maximum: ['-profile:v', '3'],
    high: ['-profile:v', '3'],
    balanced: ['-profile:v', '2'],
    compact: ['-profile:v', '1'],
    tiny: ['-profile:v', '1'],
  },
};

// Capping ratios per 6-tier preset. lossless = no cap (null).
const BITRATE_CAP_RATIOS = {
  lossless: null,
  maximum: 0.9,
  high: 0.7,
  balanced: 0.5,
  compact: 0.3,
  tiny: 0.15,
};

function getAudioArgs(options) {
  const { audioCodec = 'aac', audioBitrate = 192, codec, preset } = options;

  if (audioCodec === 'copy') return ['-c:a', 'copy'];
  if (audioCodec === 'opus') return ['-c:a', 'libopus', '-b:a', `${audioBitrate}k`];

  // ProRes always uses PCM regardless of audioCodec setting
  if (codec === 'prores') return ['-c:a', 'pcm_s16le'];

  // AV1 defaults to opus unless user explicitly chose aac
  if (codec === 'av1' && audioCodec !== 'aac')
    return ['-c:a', 'libopus', '-b:a', `${audioBitrate}k`];

  // Default: AAC
  // Legacy: max preset used 256k; honour that if caller doesn't specify
  const defaultBitrate =
    audioBitrate === 192 && (preset === 'max' || preset === 'maximum') ? 256 : audioBitrate;
  return ['-c:a', 'aac', '-b:a', `${defaultBitrate}k`];
}

/**
 * Adjust HW-encoder bitrate target so we never exceed the input bitrate.
 * Ratios are driven by the 6-tier preset caps in BITRATE_CAP_RATIOS.
 */
function adjustBitrate(targetKbps, inputBitrateKbps, preset) {
  if (!inputBitrateKbps || inputBitrateKbps <= 0) return targetKbps;
  const normalised = normalizePreset(preset);
  const ratio = BITRATE_CAP_RATIOS[normalised];
  if (ratio === null || ratio === undefined) return targetKbps; // lossless — no cap
  const maxTarget = Math.floor(inputBitrateKbps * ratio);
  return Math.min(targetKbps, maxTarget);
}

const SCALE_HEIGHTS = {
  '4k': 2160,
  '2160p': 2160,
  '2k': 1440,
  '1440p': 1440,
  '1080p': 1080,
  '720p': 720,
  '480p': 480,
  '360p': 360,
};

/**
 * Build the base FFmpeg args for a single pass (or a specific pass number).
 * pass: null = single-pass, 1 = first pass, 2 = second pass
 */
function buildArgs(options, pass, passlogFile) {
  const {
    inputPath,
    outputPath,
    preset: rawPreset,
    codec,
    format,
    hwAccel,
    trim = null,
    crop = null,
    scale = 'original',
    sourceBitrate = 0,
    sourceHeight = null,
    crf = null,
    speed = null,
    audioBitrate = 192,
    audioCodec = 'aac',
    fps = 'original',
    preserveMetadata = true,
    fastStart = true,
  } = options;

  const preset = normalizePreset(rawPreset);
  const hwAvailable = isHWAvailable(codec, hwAccel);
  const encoder = getEncoder(codec, hwAvailable);
  const isVT = encoder.includes('videotoolbox');
  const args = [];

  // Determine if we'll need video filters (scale, crop, fps)
  const targetHeight = SCALE_HEIGHTS[scale];
  const needsScale =
    scale !== 'original' && targetHeight && !(sourceHeight && sourceHeight === targetHeight);
  const needsCrop = !!crop;
  const needsFpsFilter = fps && fps !== 'original';
  const needsFilters = needsScale || needsCrop || needsFpsFilter;

  // Hardware decode acceleration
  if (isVT && !needsFilters) {
    // Zero-copy: VT decode → VT encode (no CPU frame transfer)
    args.push('-hwaccel', 'videotoolbox', '-hwaccel_output_format', 'videotoolbox_vld');
  } else {
    // HW decode to CPU memory (still faster than pure SW decode)
    args.push('-hwaccel', 'videotoolbox');
  }

  // -threads 0 only helps software encoders; VT manages its own threading
  if (!isVT) {
    args.push('-threads', '0');
  }

  args.push('-y');
  args.push('-i', inputPath);

  // Metadata
  if (preserveMetadata) {
    args.push('-map_metadata', '0');
  } else {
    args.push('-map_metadata', '-1');
  }

  // Stream mapping
  if (pass === 1) {
    // Pass 1: video only — no audio needed
    args.push('-map', '0:v:0');
  } else if (format === 'mkv') {
    // MKV: keep all video + audio tracks (users may want multi-track)
    args.push('-map', '0:v', '-map', '0:a?');
  } else {
    // MP4/MOV: first video + first audio only — skip extra tracks, subtitles, data streams
    args.push('-map', '0:v:0', '-map', '0:a:0?');
  }

  if (trim) {
    if (trim.start) args.push('-ss', trim.start);
    if (trim.end) args.push('-to', trim.end);
  }

  args.push('-c:v', encoder);

  if (rawPreset === 'custom' && crf !== null) {
    // Custom preset: use raw CRF/bitrate + speed values
    if (encoder.includes('videotoolbox')) {
      const bitrateKbps = Math.max(500, Math.round(30000 * Math.pow(0.94, crf)));
      const adjusted =
        sourceBitrate > 0
          ? Math.min(bitrateKbps, Math.floor((sourceBitrate / 1000) * 0.9))
          : bitrateKbps;
      args.push('-b:v', `${adjusted}k`);
      if (encoder === 'hevc_videotoolbox') args.push('-tag:v', 'hvc1');
      if (encoder === 'h264_videotoolbox') args.push('-profile:v', 'high');
    } else if (encoder === 'libsvtav1') {
      args.push('-crf', String(crf));
      if (speed) {
        const svtMap = { veryslow: '2', slow: '4', medium: '6', fast: '8', ultrafast: '12' };
        args.push('-preset', svtMap[speed] || '6');
      }
    } else if (encoder === 'prores_videotoolbox' || encoder === 'prores_ks') {
      const profile = crf <= 15 ? '3' : crf <= 28 ? '2' : crf <= 40 ? '1' : '0';
      args.push('-profile:v', profile);
    } else {
      args.push('-crf', String(crf));
      if (speed) args.push('-preset', speed);
      if (encoder === 'libx265') args.push('-tag:v', 'hvc1');
    }
  } else {
    const qualityFlags = QUALITY_PRESETS[encoder]?.[preset];
    if (qualityFlags) {
      const flags = [...qualityFlags];
      const bvIndex = flags.indexOf('-b:v');
      if (bvIndex !== -1 && sourceBitrate > 0) {
        const targetKbps = parseInt(flags[bvIndex + 1], 10);
        flags[bvIndex + 1] = `${adjustBitrate(targetKbps, sourceBitrate / 1000, preset)}k`;
      }
      args.push(...flags);
    }
  }

  // Explicit pixel format for VT encoders (only when not in zero-copy mode)
  if (isVT && needsFilters) {
    args.push('-pix_fmt', 'yuv420p');
  }

  // FPS filter
  const filters = [];
  if (crop) filters.push(`crop=${crop.width}:${crop.height}:${crop.x}:${crop.y}`);

  // Skip scale filter if source already matches the target resolution
  if (needsScale) {
    filters.push(`scale=-2:${targetHeight}`);
  }
  if (fps && fps !== 'original') {
    args.push('-r', String(fps));
  }
  if (filters.length > 0) args.push('-vf', filters.join(','));

  // Two-pass flags
  if (pass !== null) {
    args.push('-pass', String(pass), '-passlogfile', passlogFile);
  }

  if (pass === 1) {
    // Pass 1: discard output
    args.push('-an', '-f', 'null', '/dev/null');
  } else {
    // Audio (skip on pass 1)
    args.push(...getAudioArgs({ audioCodec, audioBitrate, codec, preset: rawPreset }));

    if (format === 'mp4' || format === 'mov') {
      const movFlags = fastStart ? '+faststart+use_metadata_tags' : '+use_metadata_tags';
      args.push('-movflags', movFlags);
    }

    args.push(outputPath);
  }

  return args;
}

export function buildCommand(options) {
  return buildArgs(options, null, null);
}

/**
 * Build args for two-pass encoding.
 * Returns { pass1Args, pass2Args, passlogFile }.
 */
export function buildTwoPassCommands(options, passlogFile) {
  return {
    pass1Args: buildArgs(options, 1, passlogFile),
    pass2Args: buildArgs(options, 2, passlogFile),
  };
}

function isHWAvailable(codec, hwAccel) {
  if (!hwAccel) return false;
  switch (codec) {
    case 'h264':
      return !!hwAccel.h264_videotoolbox;
    case 'h265':
      return !!hwAccel.hevc_videotoolbox;
    case 'prores':
      return !!hwAccel.prores_videotoolbox;
    case 'av1':
      return false;
    default:
      return false;
  }
}
