#pragma once

#ifdef __cplusplus
extern "C" {
#endif

void SI_RunApp(void);
void SI_SetStatusIcon(const char *path);
void SI_RegisterHotKey(int actionId, int keyCode, unsigned int cocoaFlags);
void SI_PerformAction(int actionId);
void SI_SetSizeDeltaConfig(int type, double fixedW, double fixedH, double windowPct, double screenPct);
void SI_SetDebug(int enabled);
void SI_AddMenuItem(int actionId, const char *title);

#ifdef __cplusplus
}
#endif

// Implemented in Go.
void GoHandleAction(int actionId);
