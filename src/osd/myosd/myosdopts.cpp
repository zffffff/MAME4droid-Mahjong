// license:BSD-3-Clause
//============================================================
//
//  myosdopts.cpp - MYOSD options, SDL/Windows sdlopts style
//
//  MAME4DROID by David Valdeita (Seleuco)
//
//============================================================

#include "myosdopts.h"

#include "myosd_platform.h"

namespace {

// only entries osd_options does not already provide; gl_glsl must stay
// because USE_OPENGL=0 drops it from the base table and the host may
// still pass it on the command line or keep it in an old ini
const options_entry f_myosd_option_entries[] =
{
	{ nullptr,              nullptr,    core_options::option_type::HEADER,  "MYOSD OPTIONS" },
	{ OPTION_HISCORE,       "0",        core_options::option_type::BOOLEAN, "enable hiscore system" },
	{ OPTION_BEAM,          "1.0",      core_options::option_type::FLOAT,   "set vector beam width maximum" },
	{ OSDOPTION_GL_GLSL,    "0",        core_options::option_type::BOOLEAN, "Does nothing in " MYOSD_PROVIDER_DISPLAY_NAME },
	{ nullptr }
};

} // anonymous namespace

//============================================================
//  myosd_options
//============================================================

myosd_options::myosd_options()
	: osd_options()
{
	add_entries(f_myosd_option_entries);

	// this port's own render/sound modules are the defaults
	set_default_value(OSDOPTION_VIDEO, MYOSD_PROVIDER_NAME);
	set_default_value(OSDOPTION_SOUND, MYOSD_PROVIDER_NAME);
}

//============================================================
//  osd_setup_osd_specific_emu_options
//============================================================

void osd_setup_osd_specific_emu_options(emu_options &opts)
{
	opts.add_entries(osd_options::s_option_entries);
	opts.add_entries(f_myosd_option_entries);

	opts.set_default_value(OSDOPTION_VIDEO, MYOSD_PROVIDER_NAME);
	opts.set_default_value(OSDOPTION_SOUND, MYOSD_PROVIDER_NAME);
}
