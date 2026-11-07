package com.somesh.yrfileexplorer.media;

import android.animation.ValueAnimator;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
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

/** Draws a small rolling envelope from the local track, without recording audio. */
final class AudioWaveformView extends View {
    private static final int BUCKET_MS = 32;
    private static final int STEP_MS = 8_000;
    private static final int WINDOW_MS = 11_000;
    private static final int BARS = 49;
    private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final int accent, muted;
    private Future<?> pending;
    private Envelope envelope;
    private String source;
    private int requestedStart = -1, generation, position, duration;
    private long updatedAt;
    private boolean active, playing;

    private record Envelope(int start, float[] peaks) {
        float at(float time) {
            float bucket = (time - start) / BUCKET_MS;
            if (bucket < 0 || bucket >= peaks.length - 1) return 0;
            int index = (int) bucket;
            return peaks[index] + (peaks[index + 1] - peaks[index]) * (bucket - index);
        }
    }

    AudioWaveformView(Context context, int accent, int muted) {
        super(context);
        this.accent = accent;
        this.muted = muted;
        paint.setStrokeCap(Paint.Cap.ROUND);
        setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_NO);
    }

    void setActive(boolean value) {
        if (active == value) return;
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
            cancelPending();
            envelope = null;
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
        if (pending != null) pending.cancel(true);
        pending = null;
        requestedStart = envelope == null ? -1 : envelope.start();
    }

    private void requestWindow() {
        if (duration <= 0 || source == null || source.isEmpty()) return;
        int start = Math.max(0, (position / STEP_MS) * STEP_MS - 1_000);
        if (start == requestedStart) return;
        cancelPending();
        requestedStart = start;
        String track = source;
        int request = generation;
        Context context = getContext().getApplicationContext();
        pending = worker.submit(() -> {
            Envelope decoded = decode(context, track, start);
            if (!Thread.currentThread().isInterrupted()) post(() -> {
                if (generation != request || !active) return;
                envelope = decoded;
                pending = null;
                invalidate();
            });
        });
    }

    @Override protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        int width = getWidth() - getPaddingLeft() - getPaddingRight();
        if (width <= 0) return;
        float stride = (float) width / BARS;
        float baseline = getHeight() - 2 * getResources().getDisplayMetrics().density;
        paint.setStrokeWidth(Math.max(1, stride * .42f));
        long elapsed = playing && active ? SystemClock.elapsedRealtime() - updatedAt : 0;
        float playhead = Math.min(duration, position + Math.min(elapsed, 550));
        for (int i = 0; i < BARS; i++) {
            int offset = i - BARS / 2;
            float peak = envelope == null ? 0 : envelope.at(playhead + offset * BUCKET_MS);
            float height = 1.5f + (baseline - 2) * (float) Math.sqrt(peak);
            float x = getPaddingLeft() + (i + .5f) * stride;
            paint.setColor(offset <= 0 && peak > 0 ? accent : muted);
            canvas.drawLine(x, baseline - height, x, baseline, paint);
        }
        if (active && playing && envelope != null) {
            postInvalidateDelayed(ValueAnimator.areAnimatorsEnabled() ? 32 : 180);
        }
    }

    private static Envelope decode(Context context, String source, int start) {
        MediaExtractor extractor = new MediaExtractor();
        MediaCodec codec = null;
        try {
            if (source.startsWith("content:")) extractor.setDataSource(context, Uri.parse(source), null);
            else extractor.setDataSource(source);
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
            if (format == null) return null;
            extractor.seekTo(start * 1_000L, MediaExtractor.SEEK_TO_PREVIOUS_SYNC);
            codec = MediaCodec.createDecoderByType(mime);
            codec.configure(format, null, null, 0);
            codec.start();
            return readPeaks(extractor, codec, format, start);
        } catch (IOException | RuntimeException error) {
            // Some containers play through Android but expose no decodable PCM track.
            return null;
        } finally {
            if (codec != null) codec.release();
            extractor.release();
        }
    }

    private static Envelope readPeaks(MediaExtractor extractor, MediaCodec codec, MediaFormat format, int start) {
        float[] peaks = new float[WINDOW_MS / BUCKET_MS + 2];
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
                    if (!inputDone) extractor.advance();
                }
            }
            int output = codec.dequeueOutputBuffer(info, 5_000);
            if (output == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                format = codec.getOutputFormat();
            } else if (output >= 0) {
                ByteBuffer pcm = codec.getOutputBuffer(output);
                if (pcm != null && info.size > 0) {
                    collect(pcm, info, format, start, peaks);
                }
                codec.releaseOutputBuffer(output, false);
                if ((info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) break;
            }
        }
        return new Envelope(start, peaks);
    }

    private static void collect(ByteBuffer buffer, MediaCodec.BufferInfo info, MediaFormat format,
                                int start, float[] peaks) {
        int rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE, 44_100);
        int channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT, 1);
        if (rate <= 0 || channels <= 0) return;
        int encoding = format.getInteger(MediaFormat.KEY_PCM_ENCODING, AudioFormat.ENCODING_PCM_16BIT);
        if (encoding != AudioFormat.ENCODING_PCM_16BIT && encoding != AudioFormat.ENCODING_PCM_FLOAT) return;
        boolean floats = encoding == AudioFormat.ENCODING_PCM_FLOAT;
        int sampleBytes = floats ? 4 : 2;
        int frameBytes = channels * sampleBytes;
        buffer.order(ByteOrder.nativeOrder());
        int frames = info.size / frameBytes;
        for (int frame = 0; frame < frames; frame += 3) {
            long time = info.presentationTimeUs + frame * 1_000_000L / rate - start * 1_000L;
            if (time < 0) continue;
            int index = (int) (time / (BUCKET_MS * 1_000L));
            if (index >= peaks.length) break;
            int offset = info.offset + frame * frameBytes;
            float peak = peaks[index];
            for (int channel = 0; channel < channels; channel++) {
                int sample = offset + channel * sampleBytes;
                float amplitude = floats ? Math.abs(buffer.getFloat(sample)) : Math.abs(buffer.getShort(sample)) / 32768f;
                if (Float.isFinite(amplitude)) peak = Math.max(peak, Math.min(1, amplitude));
            }
            peaks[index] = peak;
        }
    }
}
