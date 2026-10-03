// license:BSD-3-Clause
//============================================================
//
//  myosd_sound.cpp - myosd sound module: routes MAME audio
//  to the host app callbacks
//
//  MAME4DROID by David Valdeita (Seleuco)
//
//============================================================

// MAME headers
#include "emu.h"

// DROID headers
#include "myosd.h"
#include "myosd_platform.h"

#include "modules/osdmodule.h"
#include "modules/sound/sound_module.h"

static void myosd_sound_init(int rate, int stereo);
static void myosd_sound_play(void *buff, int len);
static void myosd_sound_exit(void);

namespace {

//============================================================
//  sound_myosd
//============================================================

class sound_myosd : public osd_module, public sound_module
{
public:
	sound_myosd()
		: osd_module(OSD_SOUND_PROVIDER, MYOSD_PROVIDER_NAME)
		, m_osd(nullptr)
		, m_current_stream_id(0)
		, m_next_stream_id(1)
	{
	}

	// runs once per machine session (the module manager re-inits
	// every module after each osd_exit)
	virtual int init(osd_interface &osd, const osd_options &options) override
	{
		osd_printf_verbose("sound_myosd::init\n");

		m_osd = dynamic_cast<my_osd_interface *>(&osd);
		if (m_osd == nullptr)
			return -1;

		myosd_callbacks &callbacks = m_osd->callbacks();

		// if the host does not want to handle audio, do a default
		if (callbacks.sound_play == NULL)
		{
			callbacks.sound_init = myosd_sound_init;
			callbacks.sound_play = myosd_sound_play;
			callbacks.sound_exit = myosd_sound_exit;
		}

		if (m_osd->sample_rate() != 0)
		{
			callbacks.sound_init(m_osd->sample_rate(), 1);
		}

		m_current_stream_id = 0;
		m_next_stream_id = 1;
		return 0;
	}

	// the host sound_exit callback fires from my_osd_interface::osd_exit
	// to keep the legacy video -> input -> sound teardown order
	virtual void exit() override
	{
		osd_printf_verbose("sound_myosd::exit\n");
		m_current_stream_id = 0;
	}

	virtual uint32_t get_generation() override { return 1; }

	virtual osd::audio_info get_information() override
	{
		osd::audio_info result;
		result.m_generation = 1;
		result.m_default_sink = 1;
		result.m_default_source = 0;
		result.m_nodes.resize(1);
		result.m_nodes[0].m_name = MYOSD_PROVIDER_NAME;
		result.m_nodes[0].m_display_name = MYOSD_PROVIDER_DISPLAY_NAME " sound";
		result.m_nodes[0].m_id = 1;
		result.m_nodes[0].m_rate.m_default_rate = 0; // Magic value meaning "use configured sample rate"
		result.m_nodes[0].m_rate.m_min_rate = 0;
		result.m_nodes[0].m_rate.m_max_rate = 0;
		result.m_nodes[0].m_sinks = 2;
		result.m_nodes[0].m_sources = 0;
		result.m_nodes[0].m_port_names.reserve(2);
		result.m_nodes[0].m_port_names.emplace_back("L");
		result.m_nodes[0].m_port_names.emplace_back("R");
		result.m_nodes[0].m_port_positions.reserve(2);
		result.m_nodes[0].m_port_positions.emplace_back(osd::channel_position::FL());
		result.m_nodes[0].m_port_positions.emplace_back(osd::channel_position::FR());
		if (m_current_stream_id) {
			result.m_streams.resize(1);
			result.m_streams[0].m_id = m_current_stream_id;
			result.m_streams[0].m_node = 1;
		}
		return result;
	}

	virtual uint32_t stream_sink_open(uint32_t node, std::string name, uint32_t rate) override
	{
		osd_printf_verbose("sound_myosd::stream_sink_open");

		if (m_current_stream_id)
			return 0;

		m_current_stream_id = m_next_stream_id++;
		return m_current_stream_id;
	}

	virtual void stream_close(uint32_t id) override
	{
		osd_printf_verbose("sound_myosd::stream_close");

		if (id == m_current_stream_id)
			m_current_stream_id = 0;
	}

	virtual void stream_sink_update(uint32_t id, int16_t const *buffer, int samples_this_frame) override
	{
		osd_printf_verbose("sound_myosd::stream_sink_update: samples=%d \n", samples_this_frame);

		if (m_osd == nullptr || m_osd->sample_rate() == 0 || m_osd->callbacks().sound_play == NULL
				|| buffer == NULL || id != m_current_stream_id)
			return;

		m_osd->callbacks().sound_play((void*)buffer, samples_this_frame * sizeof(int16_t) * 2);
	}

private:
	my_osd_interface *m_osd;
	uint32_t m_current_stream_id;
	uint32_t m_next_stream_id;
};

} // anonymous namespace


MODULE_DEFINITION(SOUND_MYOSD, sound_myosd)

//============================================================
//  default sound impl
//============================================================


static void myosd_sound_init(int rate, int stereo)
{

}

static void myosd_sound_exit(void)
{

}

static void myosd_sound_play(void *buff, int len)
{

}
