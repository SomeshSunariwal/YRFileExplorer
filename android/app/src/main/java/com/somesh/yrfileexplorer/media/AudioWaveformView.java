package com.somesh.yrfileexplorer.media;

import android.animation.ValueAnimator;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.LinearGradient;
import android.graphics.Paint;
import android.graphics.Shader;
import android.media.AudioFormat;
import android.media.MediaCodec;
import android.media.MediaExtractor;
import android.media.MediaFormat;
import android.net.Uri;
import android.os.SystemClock;
import android.view.View;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.Objects;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

/** Shows fixed frequency bands from the local track's decoded PCM. */
final class AudioWaveformView extends View {
    private static final int FRAME_MS = 50;
    private static final int STEP_MS = 8_000;
    private static final int WINDOW_MS = 11_000;
    private static final int BANDS = AudioSpectrum.BANDS;
    private static final int[] COLORS = {
            0xffc2a821, 0xffed883c, 0xffe64b79, 0xffa75ec5, 0xff588cd3, 0xff159db6
    };
    private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final float density;
    private Future<?> pending;
    private SpectrumWindow spectrum;
    private String source;
    private int requestedStart = -1, generation, position, duration;
    private long updatedAt;
    private boolean active, playing;

    private record SpectrumWindow(int start, float[] levels) {
    }

    AudioWaveformView(Context context) {
        super(context);
        density = getResources().getDisplayMetrics().density;
        setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_NO);
    }

    void setActive(boolean value) {
        if (active == value)
            return;
        active = value;
        if (active) {
            requestWindow();
            invalidate();
        } else {
            cancelPending();
        }
    }

    void update(String track, int duration, int position, boolean playing) {
        if (!Objects.equals(source, track)) {
            spectrum = null;
            cancelPending();
            source = track;
        }
        this.duration = duration;
        this.position = position;
        this.playing = playing;
        updatedAt = SystemClock.elapsedRealtime();
        if (active) {
            requestWindow();
            invalidate();
        }
    }

    void dispose() {
        active = false;
        cancelPending();
        worker.shutdownNow();
    }

    private void cancelPending() {
        generation++;
        if (pending != null)
            pending.cancel(true);
        pending = null;
        requestedStart = spectrum == null ? -1 : spectrum.start();
    }

    private void requestWindow() {
        if (duration <= 0 || source == null || source.isEmpty())
            return;
        int start = Math.max(0, (position / STEP_MS) * STEP_MS - 1_000);
        if (start == requestedStart)
            return;
        cancelPending();
        requestedStart = start;
        String track = source;
        int request = generation;
        Context context = getContext().getApplicationContext();
        pending = worker.submit(() -> {
            SpectrumWindow decoded = decode(context, track, start);
            if (!Thread.currentThread().isInterrupted())
                post(() -> {
                    if (generation != request || !active)
                        return;
                    spectrum = decoded;
                    pending = null;
                    invalidate();
                });
        });
    }

    @Override
    protected void onSizeChanged(int width, int height, int oldWidth, int oldHeight) {
        super.onSizeChanged(width, height, oldWidth, oldHeight);
        float left = getPaddingLeft();
        float right = width - getPaddingRight();
        if (right > left) {
            paint.setShader(new LinearGradient(left, 0, right, 0, COLORS, null, Shader.TileMode.CLAMP));
        }
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        int width = getWidth() - getPaddingLeft() - getPaddingRight();
        if (width <= 0)
            return;
        float stride = (float) width / BANDS;
        float halfBar = Math.max(.5f, stride * .23f);
        float baseline = getHeight() - density;
        float minHeight = 1.5f * density;
        float heightRange = Math.max(0, baseline - density - minHeight);
        long elapsed = playing && active ? SystemClock.elapsedRealtime() - updatedAt : 0;
        float playhead = Math.min(duration, position + Math.min(elapsed, 550));
        float frame = spectrum == null ? -1 : (playhead - spectrum.start()) / FRAME_MS;
        int index = (int) frame * BANDS;
        float fraction = frame - (int) frame;
        float[] levels = spectrum == null ? null : spectrum.levels();
        boolean hasFrame = frame >= 0 && levels != null && index + 2 * BANDS <= levels.length;
        for (int band = 0; band < BANDS; band++) {
            float level = 0;
            if (hasFrame) {
                float current = levels[index + band];
                level = current + (levels[index + BANDS + band] - current) * fraction;
            }
            float height = minHeight + heightRange * level;
            float x = getPaddingLeft() + (band + .5f) * stride;
            float radius = Math.min(halfBar, density);
            canvas.drawRoundRect(x - halfBar, baseline - height, x + halfBar, baseline,
                    radius, radius, paint);
        }
        if (active && playing && spectrum != null) {
            postInvalidateDelayed(ValueAnimator.areAnimatorsEnabled() ? 32 : 180);
        }
    }

    private static SpectrumWindow decode(Context context, String source, int start) {
        MediaExtractor extractor = new MediaExtractor();
        MediaCodec codec = null;
        try {
            if (source.startsWith("content:"))
                extractor.setDataSource(context, Uri.parse(source), null);
            else
                extractor.setDataSource(source);
            MediaFormat format = null;
            String mime = null;
            for (int i = 0; i < extractor.getTrackCount(); i++) {
                MediaFormat candidate = extractor.getTrackFormat(i);
                String type = candidate.getString(MediaFormat.KEY_MIME);
                if (type != null && type.startsWith("audio/")) {
                    extractor.selectTrack(i);
                    format = candidate;
                    mime = type;
                    break;
                }
            }
            if (format == null)
                return null;
            extractor.seekTo(start * 1_000L, MediaExtractor.SEEK_TO_PREVIOUS_SYNC);
            codec = MediaCodec.createDecoderByType(mime);
            codec.configure(format, null, null, 0);
            codec.start();
            return readSpectrum(extractor, codec, format, start);
        } catch (IOException | RuntimeException error) {
            // Some containers play through Android but expose no decodable PCM track.
            return null;
        } finally {
            if (codec != null)
                codec.release();
            extractor.release();
        }
    }

    private static SpectrumWindow readSpectrum(MediaExtractor extractor, MediaCodec codec,
            MediaFormat format, int start) {
        SpectrumFrames frames = new SpectrumFrames(start);
        long endUs = (start + WINDOW_MS) * 1_000L;
        MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
        boolean inputDone = false;
        long deadline = SystemClock.elapsedRealtime() + 8_000;
        while (!Thread.currentThread().isInterrupted() && SystemClock.elapsedRealtime() < deadline) {
            if (!inputDone) {
                int index = codec.dequeueInputBuffer(5_000);
                if (index >= 0) {
                    ByteBuffer buffer = codec.getInputBuffer(index);
                    long time = extractor.getSampleTime();
                    int size = time < 0 || time >= endUs || buffer == null ? -1 : extractor.readSampleData(buffer, 0);
                    inputDone = size < 0;
                    codec.queueInputBuffer(index, 0, Math.max(0, size), Math.max(0, time),
                            inputDone ? MediaCodec.BUFFER_FLAG_END_OF_STREAM : 0);
                    if (!inputDone)
                        extractor.advance();
                }
            }
            int output = codec.dequeueOutputBuffer(info, 5_000);
            if (output == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                format = codec.getOutputFormat();
            } else if (output >= 0) {
                ByteBuffer pcm = codec.getOutputBuffer(output);
                if (pcm != null && info.size > 0) {
                    frames.collect(pcm, info, format);
                }
                codec.releaseOutputBuffer(output, false);
                if ((info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0)
                    break;
            }
        }
        frames.finishFrame();
        return new SpectrumWindow(start, frames.levels);
    }

    private static final class SpectrumFrames {
        private static final int FRAME_COUNT = WINDOW_MS / FRAME_MS + 2;
        private final float[] levels = new float[FRAME_COUNT * BANDS];
        private final long startUs;
        private int frameIndex = -1, sampleRate;
        private AudioSpectrum analyzer;

        SpectrumFrames(int start) {
            startUs = start * 1_000L;
        }

        void finishFrame() {
            if (frameIndex >= 0)
                analyzer.writeLevels(levels, frameIndex * BANDS);
        }

        void collect(ByteBuffer buffer, MediaCodec.BufferInfo info, MediaFormat format) {
            int rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE, 44_100);
            int channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT, 1);
            int encoding = format.getInteger(MediaFormat.KEY_PCM_ENCODING, AudioFormat.ENCODING_PCM_16BIT);
            if (rate < 4_000 || channels <= 0 || (encoding != AudioFormat.ENCODING_PCM_16BIT
                    && encoding != AudioFormat.ENCODING_PCM_FLOAT))
                return;
            int stride = (int) Math.ceil(rate / 48_000.0);
            if (rate != sampleRate) {
                finishFrame();
                frameIndex = -1;
                sampleRate = rate;
                analyzer = new AudioSpectrum((float) rate / stride, FRAME_MS);
            }
            boolean floats = encoding == AudioFormat.ENCODING_PCM_FLOAT;
            int sampleBytes = floats ? 4 : 2;
            int frameBytes = channels * sampleBytes;
            int frames = info.size / frameBytes;
            buffer.order(ByteOrder.nativeOrder());
            for (int frame = 0; frame < frames; frame += stride) {
                long time = info.presentationTimeUs + frame * 1_000_000L / rate - startUs;
                if (time < 0)
                    continue;
                int index = (int) (time / (FRAME_MS * 1_000L));
                if (index >= FRAME_COUNT)
                    break;
                if (index != frameIndex) {
                    finishFrame();
                    frameIndex = index;
                }
                if (!analyzer.hasRoom())
                    continue;
                // Analyze a single channel to preserve beats in out-of-phase stereo tracks.
                int offset = info.offset + frame * frameBytes;
                float sample = floats ? buffer.getFloat(offset) : buffer.getShort(offset) / 32768f;
                analyzer.add(Float.isFinite(sample) ? sample : 0);
            }
        }
    }
}
