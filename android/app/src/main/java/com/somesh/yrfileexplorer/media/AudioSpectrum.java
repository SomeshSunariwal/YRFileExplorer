package com.somesh.yrfileexplorer.media;

/** Reusable FFT workspace for one short frame of decoded PCM. */
final class AudioSpectrum {
    static final int BANDS = 28;
    private static final int FFT_BITS = 11;
    private static final int FFT_SIZE = 1 << FFT_BITS;
    private static final int[] REVERSED = new int[FFT_SIZE];
    private static final float[] COS = new float[FFT_SIZE / 2];
    private static final float[] SIN = new float[FFT_SIZE / 2];

    static {
        for (int i = 0; i < FFT_SIZE; i++) {
            REVERSED[i] = Integer.reverse(i) >>> (Integer.SIZE - FFT_BITS);
        }
        for (int i = 0; i < COS.length; i++) {
            double angle = -2 * Math.PI * i / FFT_SIZE;
            COS[i] = (float) Math.cos(angle);
            SIN[i] = (float) Math.sin(angle);
        }
    }

    private final float[] real = new float[FFT_SIZE];
    private final float[] imaginary = new float[FFT_SIZE];
    private final float[] window;
    private final int[] bandEdges = new int[BANDS + 1];
    private int samples;

    AudioSpectrum(float sampleRate, int frameMs) {
        int sampleLimit = Math.min(FFT_SIZE, Math.max(2, Math.round(sampleRate * frameMs / 1000)));
        window = new float[sampleLimit];
        for (int i = 0; i < window.length; i++) {
            window[i] = (float) (.5 - .5 * Math.cos(2 * Math.PI * i / (window.length - 1)));
        }

        int last = Math.min(FFT_SIZE / 2, Math.round(16_000 * FFT_SIZE / sampleRate));
        int first = Math.max(1, Math.round(35 * FFT_SIZE / sampleRate));
        bandEdges[0] = first;
        for (int band = 1; band <= BANDS; band++) {
            int logEdge = (int) Math.round(first * Math.pow((double) last / first, (double) band / BANDS));
            bandEdges[band] = Math.max(bandEdges[band - 1] + 1, logEdge);
        }
    }

    boolean hasRoom() {
        return samples < window.length;
    }

    void add(float sample) {
        real[REVERSED[samples]] = sample * window[samples];
        samples++;
    }

    void writeLevels(float[] levels, int offset) {
        for (int i = samples; i < FFT_SIZE; i++)
            real[REVERSED[i]] = 0;
        for (int i = 0; i < FFT_SIZE; i++)
            imaginary[i] = 0;
        for (int size = 2; size <= FFT_SIZE; size *= 2) {
            int half = size / 2;
            int step = FFT_SIZE / size;
            for (int start = 0; start < FFT_SIZE; start += size) {
                for (int i = 0; i < half; i++) {
                    int even = start + i;
                    int odd = even + half;
                    int phase = i * step;
                    float r = real[odd] * COS[phase] - imaginary[odd] * SIN[phase];
                    float im = real[odd] * SIN[phase] + imaginary[odd] * COS[phase];
                    real[odd] = real[even] - r;
                    imaginary[odd] = imaginary[even] - im;
                    real[even] += r;
                    imaginary[even] += im;
                }
            }
        }
        for (int band = 0; band < BANDS; band++) {
            float power = 0;
            for (int bin = bandEdges[band]; bin < bandEdges[band + 1]; bin++) {
                power = Math.max(power, real[bin] * real[bin] + imaginary[bin] * imaginary[bin]);
            }
            double amplitude = Math.min(1, 4 * Math.sqrt(power) / window.length);
            levels[offset + band] = (float) Math.sqrt(amplitude);
        }
        samples = 0;
    }
}
