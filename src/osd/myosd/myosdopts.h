// license:BSD-3-Clause
//============================================================
//
//  myosdopts.h - MYOSD options, SDL/Windows sdlopts style
//
//  MAME4DROID by David Valdeita (Seleuco)
//
//============================================================

#ifndef MAME_OSD_MYOSD_MYOSDOPTS_H
#define MAME_OSD_MYOSD_MYOSDOPTS_H

#pragma once

#include "modules/lib/osdobj_common.h"

//============================================================
//  Option identifiers
//============================================================

#define OPTION_HISCORE  "hiscore"
#define OPTION_BEAM     "beam"

//============================================================
//  TYPE DEFINITIONS
//============================================================

class myosd_options : public osd_options
{
public:
	// construction/destruction
	myosd_options();

	// custom options
	bool hiscore() const { return bool_value(OPTION_HISCORE); }
	float beam() const { return float_value(OPTION_BEAM); }
};

#endif // MAME_OSD_MYOSD_MYOSDOPTS_H
