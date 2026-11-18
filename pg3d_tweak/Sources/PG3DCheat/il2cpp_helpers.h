#pragma once
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Resolves the static List<Player_move_c>* pointer
// Returns pointer to the pointer (double indirect) or NULL.
void** resolvePlayerList(void);

// Resolves Camera.Render function pointer for frame hook;
// also sets up WorldToScreen as a side effect.
void* resolveCameraRenderFn(uintptr_t base);

// Update active camera (called from frame hook)
void pg3d_setActiveCamera(void* cam);

#ifdef __cplusplus
}
#endif
