// license:BSD-3-Clause
//============================================================
//
//  drawmyosd.cpp - myosd render module; its renderer bridges
//  the MAME render target to the Java-side GL renderer
//
//  MAME4DROID by David Valdeita (Seleuco)
//
//============================================================

#include "modules/render/render_module.h"

#include "modules/lib/osdobj_common.h"
#include "modules/osdmodule.h"
#include "modules/osdwindow.h"

// MAME headers
#include "emu.h"
#include "render.h"

// MYOSD headers
#include "window.h"
#include "myosd_platform.h"

#include <memory>

namespace {

//============================================================
//  renderer_myosd
//============================================================

class renderer_myosd : public osd_renderer
{
public:
	renderer_myosd(osd_window &window) : osd_renderer(window) { }

	virtual int create() override { return 0; }

	virtual render_primitive_list *get_primitives() override
	{
		return &window().target()->get_primitives();
	}

	// draw() only hands the primitives to the GL thread under the
	// bridge mutex; the real GL draw happens asynchronously (video.cpp)
	virtual int draw(const int update) override
	{
		auto &win = static_cast<myosd_window_info &>(window());
		myosd_gl_sync(win.m_primlist, win.in_menu(), win.min_width(), win.min_height());
		return 0;
	}
};

//============================================================
//  video_myosd
//============================================================

class video_myosd : public osd_module, public render_module
{
public:
	video_myosd() : osd_module(OSD_RENDERER_PROVIDER, MYOSD_PROVIDER_NAME) { }

	virtual int init(osd_interface &osd, osd_options const &options) override { return 0; }

	virtual std::unique_ptr<osd_renderer> create(osd_window &window) override
	{
		return std::make_unique<renderer_myosd>(window);
	}

protected:
	virtual unsigned flags() const override { return 0; }
};

} // anonymous namespace


MODULE_DEFINITION(RENDERER_MYOSD, video_myosd)
