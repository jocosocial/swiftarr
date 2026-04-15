// ABOUTME: C shim functions that wrap variadic libvips calls for Swift interop.
// ABOUTME: Swift cannot call C variadic functions directly, so each shim provides a typed interface.

#ifndef SWIFTARR_VIPS_SHIM_H
#define SWIFTARR_VIPS_SHIM_H

#include <vips/vips.h>

// Initialize libvips. Must be called once before any other vips operations.
// Returns 0 on success, non-zero on failure.
int swiftarr_vips_init(void);

// Load an image from a memory buffer. Auto-detects format via magic bytes.
// Caller owns the returned VipsImage (must g_object_unref when done).
// Returns NULL on failure.
VipsImage *swiftarr_vips_load_buffer(const void *buf, size_t len);

// Auto-rotate image based on EXIF orientation tag, then strip the tag.
// Returns a new VipsImage (caller owns it). Returns NULL on failure.
VipsImage *swiftarr_vips_autorot(VipsImage *in);

// Flatten alpha channel onto a solid background color (r, g, b in 0-255 range).
// Returns a new VipsImage without alpha. Returns NULL on failure.
VipsImage *swiftarr_vips_flatten(VipsImage *in, double r, double g, double b);

// Resize image to fit within width x height, preserving aspect ratio.
// Pass 0 for either dimension to only constrain by the other.
// Returns a new VipsImage. Returns NULL on failure.
VipsImage *swiftarr_vips_thumbnail(VipsImage *in, int width, int height);

// Extract a rectangular region from the image.
// Returns a new VipsImage. Returns NULL on failure.
VipsImage *swiftarr_vips_crop(VipsImage *in, int left, int top, int width, int height);

// Export image to JPEG in a memory buffer.
// Sets *out_len to the size of the returned buffer.
// Caller must g_free() the returned buffer. Returns NULL on failure.
void *swiftarr_vips_jpegsave_buffer(VipsImage *in, int quality, size_t *out_len);

// Export image to PNG in a memory buffer.
// Sets *out_len to the size of the returned buffer.
// Caller must g_free() the returned buffer. Returns NULL on failure.
void *swiftarr_vips_pngsave_buffer(VipsImage *in, size_t *out_len);

// Create an image from raw pixel data in memory.
// Data must be width * height * bands bytes of unsigned char.
// The returned image does NOT own the data — caller must keep it alive.
// Returns NULL on failure.
VipsImage *swiftarr_vips_image_new_from_memory(const void *data, size_t size,
                                                int width, int height, int bands);

#endif /* SWIFTARR_VIPS_SHIM_H */
