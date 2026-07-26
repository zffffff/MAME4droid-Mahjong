package com.seleuco.mame4droid.helpers;

import android.content.SharedPreferences;
import android.content.pm.ActivityInfo;
import android.content.res.Configuration;
import android.util.Log;

import com.seleuco.mame4droid.Emulator;
import com.seleuco.mame4droid.MAME4droid;

import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;

/**
 * Mahjong-edition UX helpers: one-time defaults, orientation bridge for Lua
 * artwork-view switching, and portrait-forced dual-screen ROMs.
 */
public class MahjongExperienceHelper {

	private static final String TAG = "MahjongExperience";
	private static final String PREF_SEEDED = "mahjong_defaults_v1";
	private static final String ORIENT_FILE = ".device_orientation";

	/** Dual-screen portrait-only ROMs (extend as more are added). */
	private static final String[] PORTRAIT_FORCED_ROMS = {
			"jantouki",
			// future: "qyjdzjp" / other dual-screen hunting variants if needed
	};

	private final MAME4droid mm;
	private String lastWrittenOrient = null;
	private String lastForcedRom = null;

	public MahjongExperienceHelper(MAME4droid mm) {
		this.mm = mm;
	}

	/** Seed mahjong-friendly SharedPreferences once (does not override later user changes). */
	public void seedDefaultsIfNeeded() {
		SharedPreferences p = mm.getPrefsHelper().getSharedPreferences();
		if (p.getBoolean(PREF_SEEDED, false)) {
			return;
		}
		SharedPreferences.Editor e = p.edit();
		// Landscape / portrait-fullscreen: hide face buttons + stick so OSC is only
		// Exit/Option/Coin/Start. Portrait non-fullscreen still shows the full pad.
		e.putString(PrefsHelper.PREF_NUMBUTTONS, "0");
		e.putBoolean(PrefsHelper.PREF_HIDE_STICK, true);
		e.putBoolean(PrefsHelper.PREF_TOUCH_UI, true);
		e.putBoolean(PREF_SEEDED, true);
		e.apply();
		Log.i(TAG, "Seeded mahjong SharedPreferences defaults");
	}

	/**
	 * Write current device orientation for master_lamps.lua to pick Portrait_* /
	 * Landscape_* artwork views. Safe to call often.
	 */
	public void syncOrientationBridge() {
		String dir = mm.getMainHelper().getInstallationDIR();
		if (dir == null || dir.isEmpty()) {
			return;
		}
		if (!dir.endsWith("/")) {
			dir += "/";
		}

		int o = mm.getResources().getConfiguration().orientation;
		String value = (o == Configuration.ORIENTATION_LANDSCAPE) ? "landscape" : "portrait";
		if (value.equals(lastWrittenOrient)) {
			File f = new File(dir + ORIENT_FILE);
			if (f.isFile()) {
				return;
			}
		}

		try (FileOutputStream out = new FileOutputStream(dir + ORIENT_FILE)) {
			out.write(value.getBytes(StandardCharsets.UTF_8));
			lastWrittenOrient = value;
		} catch (Exception e) {
			Log.w(TAG, "Failed writing " + ORIENT_FILE, e);
		}
	}

	/**
	 * Force portrait while a dual-screen mahjong ROM is running; otherwise honour
	 * the user's orientation preference (usually Auto).
	 */
	public void applyRomOrientationPolicy() {
		String rom = null;
		try {
			if (Emulator.isInGame()) {
				rom = Emulator.getValueStr(Emulator.ROM_NAME);
				if (rom == null || rom.isEmpty() || "___empty".equals(rom)) {
					rom = Emulator.getValueStr(Emulator.GAME_SELECTED);
				}
			}
		} catch (Throwable t) {
			return;
		}

		boolean forcePortrait = isPortraitForcedRom(rom);
		if (forcePortrait) {
			if (!rom.equals(lastForcedRom)) {
				mm.setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT);
				lastForcedRom = rom;
				Log.i(TAG, "Force portrait for ROM: " + rom);
			}
			return;
		}

		if (lastForcedRom != null) {
			lastForcedRom = null;
			int mode = mm.getMainHelper().getScreenOrientation();
			mm.setRequestedOrientation(mode);
		}
	}

	public static boolean isPortraitForcedRom(String rom) {
		if (rom == null || rom.isEmpty()) {
			return false;
		}
		String base = rom;
		int slash = Math.max(rom.lastIndexOf('/'), rom.lastIndexOf('\\'));
		if (slash >= 0 && slash + 1 < rom.length()) {
			base = rom.substring(slash + 1);
		}
		int dot = base.lastIndexOf('.');
		if (dot > 0) {
			base = base.substring(0, dot);
		}
		base = base.toLowerCase();
		for (String id : PORTRAIT_FORCED_ROMS) {
			if (base.equals(id) || base.startsWith(id)) {
				return true;
			}
		}
		return false;
	}
}
