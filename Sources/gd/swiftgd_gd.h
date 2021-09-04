#include <gd.h>

extern gdImagePtr rcf_gdImageCreateFromJpegPtr (int size, void *data);
extern void * rcf_gdImageJpegPtr(gdImagePtr im, int *size, int quality);
