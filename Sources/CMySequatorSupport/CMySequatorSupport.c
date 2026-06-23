#include "CMySequatorSupport.h"

#include <Accelerate/Accelerate.h>
#include "libraw/libraw.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include "tiffio.h"

static char *msq_copy_error(const char *message) {
    if (message == NULL) {
        message = "Unknown error";
    }
    size_t length = strlen(message);
    char *copy = (char *)malloc(length + 1);
    if (copy == NULL) {
        return NULL;
    }
    memcpy(copy, message, length + 1);
    return copy;
}

static int msq_fail_image(MSQFloatRGBImage *out_image, const char *message) {
    if (out_image != NULL) {
        out_image->width = 0;
        out_image->height = 0;
        out_image->data = NULL;
        out_image->error_message = msq_copy_error(message);
    }
    return 1;
}

static int msq_fail_message(char **error_message, const char *message) {
    if (error_message != NULL) {
        *error_message = msq_copy_error(message);
    }
    return 1;
}

static float msq_clamp_float(float value, float lo, float hi) {
    if (value < lo) {
        return lo;
    }
    if (value > hi) {
        return hi;
    }
    return value;
}

int msq_load_raw_linear_rgb(const char *path, MSQFloatRGBImage *out_image) {
    MSQRawDecodeOptions options;
    options.white_balance_mode = 0;
    options.no_auto_bright = 1;
    options.highlight_mode = 0;
    options.use_user_black = 0;
    options.user_black = 0;
    return msq_load_raw_linear_rgb_with_options(path, &options, out_image);
}

int msq_load_raw_linear_rgb_with_options(const char *path, const MSQRawDecodeOptions *options, MSQFloatRGBImage *out_image) {
    if (out_image == NULL) {
        return 1;
    }
    out_image->width = 0;
    out_image->height = 0;
    out_image->data = NULL;
    out_image->error_message = NULL;

    libraw_data_t *raw = libraw_init(0);
    if (raw == NULL) {
        return msq_fail_image(out_image, "LibRaw initialization failed.");
    }

    int white_balance_mode = options == NULL ? 0 : options->white_balance_mode;
    if (white_balance_mode < 0 || white_balance_mode > 2) {
        white_balance_mode = 0;
    }
    int highlight_mode = options == NULL ? 0 : options->highlight_mode;
    if (highlight_mode < 0 || highlight_mode > 3) {
        highlight_mode = 0;
    }
    raw->params.use_camera_wb = white_balance_mode == 0 ? 1 : 0;
    raw->params.use_auto_wb = white_balance_mode == 1 ? 1 : 0;
    raw->params.no_auto_bright = options == NULL ? 1 : options->no_auto_bright;
    raw->params.highlight = highlight_mode;
    if (options != NULL && options->use_user_black) {
        raw->params.user_black = options->user_black;
    }
    raw->params.output_bps = 16;
    raw->params.output_color = 1;
    raw->params.gamm[0] = 1.0;
    raw->params.gamm[1] = 1.0;
    raw->params.user_flip = 0;

    int err = libraw_open_file(raw, path);
    if (err != LIBRAW_SUCCESS) {
        const char *message = libraw_strerror(err);
        libraw_close(raw);
        return msq_fail_image(out_image, message);
    }

    err = libraw_unpack(raw);
    if (err != LIBRAW_SUCCESS) {
        const char *message = libraw_strerror(err);
        libraw_close(raw);
        return msq_fail_image(out_image, message);
    }

    err = libraw_dcraw_process(raw);
    if (err != LIBRAW_SUCCESS) {
        const char *message = libraw_strerror(err);
        libraw_close(raw);
        return msq_fail_image(out_image, message);
    }

    libraw_processed_image_t *processed = libraw_dcraw_make_mem_image(raw, &err);
    if (processed == NULL || err != LIBRAW_SUCCESS) {
        const char *message = libraw_strerror(err);
        libraw_close(raw);
        return msq_fail_image(out_image, message);
    }

    if (processed->type != LIBRAW_IMAGE_BITMAP || processed->colors < 3) {
        libraw_dcraw_clear_mem(processed);
        libraw_close(raw);
        return msq_fail_image(out_image, "LibRaw did not return an RGB bitmap.");
    }

    int32_t width = (int32_t)processed->width;
    int32_t height = (int32_t)processed->height;
    int channels = processed->colors;
    size_t count = (size_t)width * (size_t)height * 3u;
    float *data = (float *)malloc(count * sizeof(float));
    if (data == NULL) {
        libraw_dcraw_clear_mem(processed);
        libraw_close(raw);
        return msq_fail_image(out_image, "Out of memory while decoding RAW.");
    }

    if (processed->bits == 16) {
        const uint16_t *source = (const uint16_t *)processed->data;
        for (int32_t y = 0; y < height; y++) {
            for (int32_t x = 0; x < width; x++) {
                size_t src = ((size_t)y * (size_t)width + (size_t)x) * (size_t)channels;
                size_t dst = ((size_t)y * (size_t)width + (size_t)x) * 3u;
                data[dst + 0] = (float)source[src + 0] / 65535.0f;
                data[dst + 1] = (float)source[src + 1] / 65535.0f;
                data[dst + 2] = (float)source[src + 2] / 65535.0f;
            }
        }
    } else {
        const uint8_t *source = (const uint8_t *)processed->data;
        for (int32_t y = 0; y < height; y++) {
            for (int32_t x = 0; x < width; x++) {
                size_t src = ((size_t)y * (size_t)width + (size_t)x) * (size_t)channels;
                size_t dst = ((size_t)y * (size_t)width + (size_t)x) * 3u;
                data[dst + 0] = (float)source[src + 0] / 255.0f;
                data[dst + 1] = (float)source[src + 1] / 255.0f;
                data[dst + 2] = (float)source[src + 2] / 255.0f;
            }
        }
    }

    out_image->width = width;
    out_image->height = height;
    out_image->data = data;
    out_image->error_message = NULL;

    libraw_dcraw_clear_mem(processed);
    libraw_close(raw);
    return 0;
}

int msq_read_tiff_rgb_float(const char *path, MSQFloatRGBImage *out_image) {
    if (out_image == NULL) {
        return 1;
    }
    out_image->width = 0;
    out_image->height = 0;
    out_image->data = NULL;
    out_image->error_message = NULL;

    TIFF *tiff = TIFFOpen(path, "r");
    if (tiff == NULL) {
        return msq_fail_image(out_image, "Unable to open TIFF.");
    }

    uint32_t width = 0;
    uint32_t height = 0;
    uint16_t samples = 0;
    uint16_t bits = 0;
    uint16_t sample_format = SAMPLEFORMAT_UINT;
    uint16_t planar = PLANARCONFIG_CONTIG;
    TIFFGetField(tiff, TIFFTAG_IMAGEWIDTH, &width);
    TIFFGetField(tiff, TIFFTAG_IMAGELENGTH, &height);
    TIFFGetField(tiff, TIFFTAG_SAMPLESPERPIXEL, &samples);
    TIFFGetField(tiff, TIFFTAG_BITSPERSAMPLE, &bits);
    TIFFGetFieldDefaulted(tiff, TIFFTAG_SAMPLEFORMAT, &sample_format);
    TIFFGetFieldDefaulted(tiff, TIFFTAG_PLANARCONFIG, &planar);

    if (width == 0 || height == 0 || samples == 0 || planar != PLANARCONFIG_CONTIG) {
        TIFFClose(tiff);
        return msq_fail_image(out_image, "Unsupported TIFF layout.");
    }
    if (!(samples == 1 || samples == 3 || samples == 4)) {
        TIFFClose(tiff);
        return msq_fail_image(out_image, "Unsupported TIFF channel count.");
    }
    if (!(bits == 8 || bits == 16 || bits == 32)) {
        TIFFClose(tiff);
        return msq_fail_image(out_image, "Unsupported TIFF bit depth.");
    }

    size_t count = (size_t)width * (size_t)height * 3u;
    float *data = (float *)malloc(count * sizeof(float));
    if (data == NULL) {
        TIFFClose(tiff);
        return msq_fail_image(out_image, "Out of memory while loading TIFF.");
    }

    tmsize_t scanline_size = TIFFScanlineSize(tiff);
    unsigned char *row = (unsigned char *)_TIFFmalloc(scanline_size);
    if (row == NULL) {
        free(data);
        TIFFClose(tiff);
        return msq_fail_image(out_image, "Out of memory while loading TIFF row.");
    }

    for (uint32_t y = 0; y < height; y++) {
        if (TIFFReadScanline(tiff, row, y, 0) < 0) {
            _TIFFfree(row);
            free(data);
            TIFFClose(tiff);
            return msq_fail_image(out_image, "Failed reading TIFF scanline.");
        }

        for (uint32_t x = 0; x < width; x++) {
            float rgb[3] = {0.0f, 0.0f, 0.0f};
            for (uint16_t c = 0; c < 3; c++) {
                uint16_t source_channel = samples == 1 ? 0 : c;
                size_t source_index = ((size_t)x * (size_t)samples + (size_t)source_channel);
                if (bits == 8) {
                    const uint8_t *typed = (const uint8_t *)row;
                    rgb[c] = (float)typed[source_index] / 255.0f;
                } else if (bits == 16) {
                    const uint16_t *typed = (const uint16_t *)row;
                    rgb[c] = (float)typed[source_index] / 65535.0f;
                } else if (sample_format == SAMPLEFORMAT_IEEEFP) {
                    const float *typed = (const float *)row;
                    rgb[c] = typed[source_index];
                } else {
                    const uint32_t *typed = (const uint32_t *)row;
                    rgb[c] = (float)typed[source_index] / 4294967295.0f;
                }
            }

            size_t dst = ((size_t)y * (size_t)width + (size_t)x) * 3u;
            data[dst + 0] = rgb[0];
            data[dst + 1] = rgb[1];
            data[dst + 2] = rgb[2];
        }
    }

    _TIFFfree(row);
    TIFFClose(tiff);

    out_image->width = (int32_t)width;
    out_image->height = (int32_t)height;
    out_image->data = data;
    out_image->error_message = NULL;
    return 0;
}

static int msq_prepare_tiff(TIFF **out_tiff, const char *path, int32_t width, int32_t height, uint16_t bits, uint16_t sample_format, char **error_message) {
    if (width <= 0 || height <= 0) {
        return msq_fail_message(error_message, "Invalid TIFF dimensions.");
    }
    TIFF *tiff = TIFFOpen(path, "w");
    if (tiff == NULL) {
        return msq_fail_message(error_message, "Unable to open output TIFF.");
    }

    TIFFSetField(tiff, TIFFTAG_IMAGEWIDTH, (uint32_t)width);
    TIFFSetField(tiff, TIFFTAG_IMAGELENGTH, (uint32_t)height);
    TIFFSetField(tiff, TIFFTAG_SAMPLESPERPIXEL, 3);
    TIFFSetField(tiff, TIFFTAG_BITSPERSAMPLE, bits);
    TIFFSetField(tiff, TIFFTAG_SAMPLEFORMAT, sample_format);
    TIFFSetField(tiff, TIFFTAG_ORIENTATION, ORIENTATION_TOPLEFT);
    TIFFSetField(tiff, TIFFTAG_PLANARCONFIG, PLANARCONFIG_CONTIG);
    TIFFSetField(tiff, TIFFTAG_PHOTOMETRIC, PHOTOMETRIC_RGB);
    TIFFSetField(tiff, TIFFTAG_ROWSPERSTRIP, TIFFDefaultStripSize(tiff, 0));
    *out_tiff = tiff;
    return 0;
}

int msq_write_float_tiff(const char *path, int32_t width, int32_t height, const float *data, char **error_message) {
    if (error_message != NULL) {
        *error_message = NULL;
    }
    TIFF *tiff = NULL;
    int err = msq_prepare_tiff(&tiff, path, width, height, 32, SAMPLEFORMAT_IEEEFP, error_message);
    if (err != 0) {
        return err;
    }

    for (int32_t y = 0; y < height; y++) {
        const float *row = data + ((size_t)y * (size_t)width * 3u);
        if (TIFFWriteScanline(tiff, (void *)row, (uint32_t)y, 0) < 0) {
            TIFFClose(tiff);
            return msq_fail_message(error_message, "Failed writing float TIFF scanline.");
        }
    }
    TIFFClose(tiff);
    return 0;
}

int msq_write_uint16_tiff(const char *path, int32_t width, int32_t height, const float *data, char **error_message) {
    if (error_message != NULL) {
        *error_message = NULL;
    }
    TIFF *tiff = NULL;
    int err = msq_prepare_tiff(&tiff, path, width, height, 16, SAMPLEFORMAT_UINT, error_message);
    if (err != 0) {
        return err;
    }

    uint16_t *row = (uint16_t *)malloc((size_t)width * 3u * sizeof(uint16_t));
    if (row == NULL) {
        TIFFClose(tiff);
        return msq_fail_message(error_message, "Out of memory while writing TIFF.");
    }

    for (int32_t y = 0; y < height; y++) {
        const float *source = data + ((size_t)y * (size_t)width * 3u);
        for (int32_t x = 0; x < width * 3; x++) {
            float scaled = msq_clamp_float(source[x], 0.0f, 1.0f) * 65535.0f;
            row[x] = (uint16_t)lrintf(scaled);
        }
        if (TIFFWriteScanline(tiff, row, (uint32_t)y, 0) < 0) {
            free(row);
            TIFFClose(tiff);
            return msq_fail_message(error_message, "Failed writing uint16 TIFF scanline.");
        }
    }

    free(row);
    TIFFClose(tiff);
    return 0;
}

static int msq_is_power_of_two(int32_t value) {
    return value > 0 && (value & (value - 1)) == 0;
}

static vDSP_Length msq_log2_int(int32_t value) {
    vDSP_Length out = 0;
    while (value > 1) {
        value >>= 1;
        out++;
    }
    return out;
}

int msq_phase_correlate_translation(const float *reference, const float *moving, int32_t width, int32_t height, int32_t *dy, int32_t *dx, float *peak) {
    if (reference == NULL || moving == NULL || dy == NULL || dx == NULL || peak == NULL) {
        return 1;
    }
    if (!msq_is_power_of_two(width) || !msq_is_power_of_two(height)) {
        return 2;
    }

    size_t count = (size_t)width * (size_t)height;
    float *ref_real = (float *)malloc(count * sizeof(float));
    float *ref_imag = (float *)calloc(count, sizeof(float));
    float *mov_real = (float *)malloc(count * sizeof(float));
    float *mov_imag = (float *)calloc(count, sizeof(float));
    if (ref_real == NULL || ref_imag == NULL || mov_real == NULL || mov_imag == NULL) {
        free(ref_real);
        free(ref_imag);
        free(mov_real);
        free(mov_imag);
        return 3;
    }

    memcpy(ref_real, reference, count * sizeof(float));
    memcpy(mov_real, moving, count * sizeof(float));

    DSPSplitComplex ref = { .realp = ref_real, .imagp = ref_imag };
    DSPSplitComplex mov = { .realp = mov_real, .imagp = mov_imag };
    vDSP_Length log2_width = msq_log2_int(width);
    vDSP_Length log2_height = msq_log2_int(height);
    vDSP_Length max_log2 = log2_width > log2_height ? log2_width : log2_height;
    FFTSetup setup = vDSP_create_fftsetup(max_log2, kFFTRadix2);
    if (setup == NULL) {
        free(ref_real);
        free(ref_imag);
        free(mov_real);
        free(mov_imag);
        return 4;
    }

    vDSP_fft2d_zip(setup, &ref, 1, width, log2_width, log2_height, FFT_FORWARD);
    vDSP_fft2d_zip(setup, &mov, 1, width, log2_width, log2_height, FFT_FORWARD);

    for (size_t i = 0; i < count; i++) {
        float rr = ref.realp[i];
        float ri = ref.imagp[i];
        float mr = mov.realp[i];
        float mi = mov.imagp[i];
        float real = rr * mr + ri * mi;
        float imag = ri * mr - rr * mi;
        float magnitude = sqrtf(real * real + imag * imag);
        if (magnitude > 1e-12f) {
            ref.realp[i] = real / magnitude;
            ref.imagp[i] = imag / magnitude;
        } else {
            ref.realp[i] = 0.0f;
            ref.imagp[i] = 0.0f;
        }
    }

    vDSP_fft2d_zip(setup, &ref, 1, width, log2_width, log2_height, FFT_INVERSE);

    size_t best_index = 0;
    float best_value = ref.realp[0];
    for (size_t i = 1; i < count; i++) {
        if (ref.realp[i] > best_value) {
            best_value = ref.realp[i];
            best_index = i;
        }
    }

    int32_t peak_y = (int32_t)(best_index / (size_t)width);
    int32_t peak_x = (int32_t)(best_index % (size_t)width);
    if (peak_y > height / 2) {
        peak_y -= height;
    }
    if (peak_x > width / 2) {
        peak_x -= width;
    }

    *dy = peak_y;
    *dx = peak_x;
    *peak = best_value;

    vDSP_destroy_fftsetup(setup);
    free(ref_real);
    free(ref_imag);
    free(mov_real);
    free(mov_imag);
    return 0;
}

void msq_accumulate_masked_rgb(const float *frame, const uint8_t *mask, int32_t pixel_count, float *accumulator, float *weights) {
    for (int32_t pixel = 0; pixel < pixel_count; pixel++) {
        if (mask[pixel] == 0) {
            continue;
        }
        int32_t base = pixel * 3;
        accumulator[base + 0] += frame[base + 0];
        accumulator[base + 1] += frame[base + 1];
        accumulator[base + 2] += frame[base + 2];
        weights[pixel] += 1.0f;
    }
}

void msq_finish_masked_mean(int32_t pixel_count, const float *accumulator, const float *weights, float *out_image) {
    for (int32_t pixel = 0; pixel < pixel_count; pixel++) {
        float weight = weights[pixel] > 1.0f ? weights[pixel] : 1.0f;
        int32_t base = pixel * 3;
        out_image[base + 0] = accumulator[base + 0] / weight;
        out_image[base + 1] = accumulator[base + 1] / weight;
        out_image[base + 2] = accumulator[base + 2] / weight;
    }
}

void msq_accumulate_max_rgb(const float *frame, int32_t value_count, float *out_image) {
    for (int32_t i = 0; i < value_count; i++) {
        if (frame[i] > out_image[i]) {
            out_image[i] = frame[i];
        }
    }
}

void msq_free_float_rgb_image(MSQFloatRGBImage *image) {
    if (image == NULL) {
        return;
    }
    if (image->data != NULL) {
        free(image->data);
    }
    if (image->error_message != NULL) {
        free(image->error_message);
    }
    image->width = 0;
    image->height = 0;
    image->data = NULL;
    image->error_message = NULL;
}

void msq_free_error_message(char *message) {
    if (message != NULL) {
        free(message);
    }
}
