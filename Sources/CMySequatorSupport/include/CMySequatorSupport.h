#ifndef CMYSEQUATORSUPPORT_H
#define CMYSEQUATORSUPPORT_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int32_t width;
    int32_t height;
    float *data;
    char *error_message;
} MSQFloatRGBImage;

typedef struct {
    int32_t white_balance_mode;
    int32_t no_auto_bright;
    int32_t highlight_mode;
    int32_t use_user_black;
    int32_t user_black;
} MSQRawDecodeOptions;

int msq_load_raw_linear_rgb(const char *path, MSQFloatRGBImage *out_image);
int msq_load_raw_linear_rgb_with_options(const char *path, const MSQRawDecodeOptions *options, MSQFloatRGBImage *out_image);
int msq_read_tiff_rgb_float(const char *path, MSQFloatRGBImage *out_image);
int msq_write_float_tiff(const char *path, int32_t width, int32_t height, const float *data, char **error_message);
int msq_write_uint16_tiff(const char *path, int32_t width, int32_t height, const float *data, char **error_message);
int msq_phase_correlate_translation(const float *reference, const float *moving, int32_t width, int32_t height, int32_t *dy, int32_t *dx, float *peak);
void msq_accumulate_masked_rgb(const float *frame, const uint8_t *mask, int32_t pixel_count, float *accumulator, float *weights);
void msq_finish_masked_mean(int32_t pixel_count, const float *accumulator, const float *weights, float *out_image);
void msq_accumulate_max_rgb(const float *frame, int32_t value_count, float *out_image);
void msq_free_float_rgb_image(MSQFloatRGBImage *image);
void msq_free_error_message(char *message);

#ifdef __cplusplus
}
#endif

#endif
