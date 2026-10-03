// license:BSD-3-Clause
//============================================================
//
//  font_myosd.cpp - font module of this myosd port; the actual
//  glyph provider is platform code (droid/droid_font.cpp)
//
//  MAME4DROID by David Valdeita (Seleuco)
//
//============================================================

#include "modules/font/font_module.h"
#include "modules/osdmodule.h"

#include "myosd.h"
#include "myosd_platform.h"

namespace {

class font_myosd : public osd_module, public font_module
{
public:
	font_myosd() : osd_module(OSD_FONT_PROVIDER, MYOSD_PROVIDER_NAME) { }

	virtual int init(osd_interface &osd, const osd_options &options) override { return 0; }

	virtual osd_font::ptr font_alloc() override { return myosd_platform_font_alloc(); }
	virtual bool get_font_families(std::string const &font_path, std::vector<std::pair<std::string, std::string> > &result) override { return false; }
};

} // anonymous namespace


MODULE_DEFINITION(FONT_MYOSD, font_myosd)
