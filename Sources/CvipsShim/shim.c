// ABOUTME: Implements typed C wrappers around variadic libvips functions.
// ABOUTME: Each function translates typed parameters into a variadic vips call.

#include "shim.h"

int swiftarr_vips_init(void) {
    return VIPS_INIT("swiftarr");
}

VipsImage *swiftarr_vips_load_buffer(const void *buf, size_t len) {
    return vips_image_new_from_buffer(buf, len, "", NULL);
}

VipsImage *swiftarr_vips_autorot(VipsImage *in) {
    VipsImage *out = NULL;
    if (vips_autorot(in, &out, NULL) != 0) {
        return NULL;
    }
    return out;
}

VipsImage *swiftarr_vips_flatten(VipsImage *in, double r, double g, double b) {
    VipsImage *out = NULL;
    VipsArrayDouble *bg = vips_array_double_newv(3, r, g, b);
    int result = vips_flatten(in, &out, "background", bg, NULL);
    vips_area_unref(VIPS_AREA(bg));
    if (result != 0) {
        return NULL;
    }
    return out;
}

VipsImage *swiftarr_vips_thumbnail(VipsImage *in, int width, int height) {
    VipsImage *out = NULL;
    int result;
    if (height > 0) {
        result = vips_thumbnail_image(in, &out, width, "height", height,
                                       "size", VIPS_SIZE_BOTH, NULL);
    } else {
        result = vips_thumbnail_image(in, &out, width,
                                       "size", VIPS_SIZE_BOTH, NULL);
    }
    if (result != 0) {
        return NULL;
    }
    return out;
}

VipsImage *swiftarr_vips_crop(VipsImage *in, int left, int top, int width, int height) {
    VipsImage *out = NULL;
    if (vips_crop(in, &out, left, top, width, height, NULL) != 0) {
        return NULL;
    }
    return out;
}

void *swiftarr_vips_jpegsave_buffer(VipsImage *in, int quality, size_t *out_len) {
    void *buf = NULL;
    size_t len = 0;
    if (vips_jpegsave_buffer(in, &buf, &len, "Q", quality, NULL) != 0) {
        return NULL;
    }
    *out_len = len;
    return buf;
}

void *swiftarr_vips_pngsave_buffer(VipsImage *in, size_t *out_len) {
    void *buf = NULL;
    size_t len = 0;
    if (vips_pngsave_buffer(in, &buf, &len, NULL) != 0) {
        return NULL;
    }
    *out_len = len;
    return buf;
}

void *swiftarr_vips_gifsave_buffer(VipsImage *in, size_t *out_len) {
    void *buf = NULL;
    size_t len = 0;
    if (vips_gifsave_buffer(in, &buf, &len, NULL) != 0) {
        return NULL;
    }
    *out_len = len;
    return buf;
}

void *swiftarr_vips_webpsave_buffer(VipsImage *in, int quality, size_t *out_len) {
    void *buf = NULL;
    size_t len = 0;
    if (vips_webpsave_buffer(in, &buf, &len, "Q", quality, NULL) != 0) {
        return NULL;
    }
    *out_len = len;
    return buf;
}

VipsImage *swiftarr_vips_image_new_from_memory(const void *data, size_t size,
                                                int width, int height, int bands) {
    return vips_image_new_from_memory(data, size, width, height, bands, VIPS_FORMAT_UCHAR);
}

void *swiftarr_vips_animated_thumbnail(const void *buf, size_t buf_len,
                                        int height, int is_gif,
                                        size_t *out_len) {
    VipsImage *thumb = NULL;
    // Load all animation frames and resize to target height.
    // Width 10000 is effectively unconstrained — height is the real constraint.
    if (vips_thumbnail_buffer((void *)buf, buf_len, &thumb, 10000,
                              "option-string", "[n=-1]",
                              "height", height,
                              "size", VIPS_SIZE_DOWN,
                              NULL) != 0) {
        return NULL;
    }

    void *out_buf = NULL;
    size_t out_size = 0;
    int result;
    if (is_gif) {
        result = vips_gifsave_buffer(thumb, &out_buf, &out_size, NULL);
    } else {
        result = vips_webpsave_buffer(thumb, &out_buf, &out_size, "Q", 90, NULL);
    }
    g_object_unref(thumb);

    if (result != 0) return NULL;
    *out_len = out_size;
    return out_buf;
}

int swiftarr_vips_copy(VipsImage *in, VipsImage **out) {
    return vips_copy(in, out, NULL);
}

VipsImage *swiftarr_vips_resize_nearest(VipsImage *in, int width, int height) {
    double hscale = (double)width / vips_image_get_width(in);
    double vscale = (double)height / vips_image_get_height(in);
    VipsImage *out = NULL;
    if (vips_resize(in, &out, hscale, "vscale", vscale,
                    "kernel", VIPS_KERNEL_NEAREST, NULL) != 0) {
        return NULL;
    }
    return out;
}
