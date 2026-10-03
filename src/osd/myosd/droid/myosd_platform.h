// license:BSD-3-Clause
//============================================================
//
//  myosd_platform.h - identity of THIS concrete myosd port.
//  Another port (e.g. iOS) ships its own myosd_platform.h and
//  points the build includedirs at its folder instead of droid/.
//
//  MAME4DROID by David Valdeita (Seleuco)
//
//============================================================

#ifndef MAME_OSD_MYOSD_DROID_MYOSD_PLATFORM_H
#define MAME_OSD_MYOSD_DROID_MYOSD_PLATFORM_H

#pragma once

#include <android/log.h>

// provider name as seen inside MAME (module lists, -video/-sound defaults)
#define MYOSD_PROVIDER_NAME         "mame4droid"

// display name (monitor device, audio node, option descriptions)
#define MYOSD_PROVIDER_DISPLAY_NAME "MAME4droid"

// platform debug log; generic myosd code must not touch <android/log.h>
#define MYOSD_PLATFORM_LOG(tag, ...) __android_log_print(ANDROID_LOG_DEBUG, tag, __VA_ARGS__)

#endif // MAME_OSD_MYOSD_DROID_MYOSD_PLATFORM_H
