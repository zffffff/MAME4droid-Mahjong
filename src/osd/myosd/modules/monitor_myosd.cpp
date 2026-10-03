// license:BSD-3-Clause
//============================================================
//
//  monitor_myosd.cpp - myosd monitor module: one virtual
//  monitor sized after the host display (myosd_set globals)
//
//  MAME4DROID by David Valdeita (Seleuco)
//
//============================================================

#include "modules/monitor/monitor_common.h"

#include "modules/lib/osdobj_common.h"
#include "modules/osdwindow.h"

// MYOSD headers
#include "myosd.h"
#include "myosd_platform.h"

namespace {

//============================================================
//  myosd_monitor_info
//============================================================

class myosd_monitor_info : public osd_monitor_info
{
public:
	myosd_monitor_info(monitor_module &module)
		: osd_monitor_info(module, 0, MYOSD_PROVIDER_DISPLAY_NAME, 1.0f)
	{
		m_is_primary = true;
		myosd_monitor_info::refresh();
	}

	// display size comes from the host app via myosd_set()
	virtual void refresh() override
	{
		int const w = myosd_display_width > 0 ? myosd_display_width : 640;
		int const h = myosd_display_height > 0 ? myosd_display_height : 480;
		m_pos_size = osd_rect(0, 0, w, h);
		m_usuable_pos_size = m_pos_size;
		set_aspect(float(w) / float(h)); // square pixels
	}
};

//============================================================
//  myosd_monitor_module
//============================================================

class myosd_monitor_module : public monitor_module_base
{
public:
	myosd_monitor_module() : monitor_module_base(OSD_MONITOR_PROVIDER, MYOSD_PROVIDER_NAME) { }

	std::shared_ptr<osd_monitor_info> monitor_from_rect(const osd_rect &rect) override
	{
		return list().front();
	}

	std::shared_ptr<osd_monitor_info> monitor_from_window(const osd_window &window) override
	{
		return list().front();
	}

protected:
	int init_internal(const osd_options &options) override
	{
		add_monitor(std::make_shared<myosd_monitor_info>(*this));
		return 0;
	}
};

} // anonymous namespace


MODULE_DEFINITION(MONITOR_MYOSD, myosd_monitor_module)
