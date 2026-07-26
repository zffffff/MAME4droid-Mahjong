package com.seleuco.mame4droid.helpers;

import android.content.SharedPreferences;
import android.content.pm.ActivityInfo;
import android.content.res.Configuration;
import android.graphics.Color;
import android.graphics.Typeface;
import android.util.Log;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.TextView;

import com.seleuco.mame4droid.Emulator;
import com.seleuco.mame4droid.MAME4droid;
import com.seleuco.mame4droid.R;
import com.seleuco.mame4droid.input.TouchController;

import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;

/**
 * Mahjong-edition UX helpers: defaults, orientation bridge, portrait-forced ROMs,
 * and an always-visible toggle to show/hide the on-screen controller.
 */
public class MahjongExperienceHelper {

	private static final String TAG = "MahjongExperience";
	private static final String PREF_SEEDED = "mahjong_defaults_v1";
	private static final String PREF_SEEDED_V2 = "mahjong_defaults_v2";
	private static final String ORIENT_FILE = ".device_orientation";
	private static final int TOGGLE_BTN_ID = 0x6D6A7467; // 'mjtg'

	/** Dual-screen portrait-only ROMs (extend as more are added). */
	private static final String[] PORTRAIT_FORCED_ROMS = {
			"jantouki",
	};

	private final MAME4droid mm;
	private String lastWrittenOrient = null;
	private String lastForcedRom = null;
	private TextView toggleBtn = null;

	public MahjongExperienceHelper(MAME4droid mm) {
		this.mm = mm;
	}

	/** Seed mahjong-friendly SharedPreferences (incremental, won't clobber later user edits of the same keys after seed). */
	public void seedDefaultsIfNeeded() {
		SharedPreferences p = mm.getPrefsHelper().getSharedPreferences();
		SharedPreferences.Editor e = null;

		if (!p.getBoolean(PREF_SEEDED, false)) {
			e = p.edit();
			// Hide face buttons A–H in landscape / portrait-fullscreen; portrait dock still shows full pad.
			e.putString(PrefsHelper.PREF_NUMBUTTONS, "0");
			e.putBoolean(PrefsHelper.PREF_TOUCH_UI, true);
			e.putBoolean(PREF_SEEDED, true);
		}

		if (!p.getBoolean(PREF_SEEDED_V2, false)) {
			if (e == null) e = p.edit();
			// Digital D-Pad instead of analog stick; keep D-Pad visible when OSC is shown.
			e.putString(PrefsHelper.PREF_CONTROLLER_TYPE, String.valueOf(PrefsHelper.PREF_DIGITAL_DPAD));
			e.putBoolean(PrefsHelper.PREF_HIDE_STICK, false);
			e.putBoolean(PREF_SEEDED_V2, true);
		}

		if (e != null) {
			e.apply();
			Log.i(TAG, "Seeded mahjong SharedPreferences defaults");
		}
	}

	/**
	 * Attach (or refresh) a floating button on EmulatorFrame that toggles the
	 * on-screen controller. Works in portrait and landscape, including when the
	 * controller strip is hidden (fullscreen game area).
	 */
	public void attachControllerToggle(FrameLayout emulatorFrame) {
		if (emulatorFrame == null) {
			return;
		}

		View existing = emulatorFrame.findViewById(TOGGLE_BTN_ID);
		if (existing != null) {
			emulatorFrame.removeView(existing);
		}

		float density = mm.getResources().getDisplayMetrics().density;
		int padH = (int) (10 * density);
		int padV = (int) (6 * density);
		int margin = (int) (8 * density);

		TextView btn = new TextView(mm);
		btn.setId(TOGGLE_BTN_ID);
		btn.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
		btn.setTypeface(Typeface.DEFAULT_BOLD);
		btn.setTextColor(Color.WHITE);
		btn.setPadding(padH, padV, padH, padV);
		btn.setBackgroundColor(0x99000000);
		btn.setElevation(4 * density);
		btn.setClickable(true);
		btn.setFocusable(false);
		btn.setContentDescription(mm.getString(R.string.mj_toggle_controller));

		FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(
				ViewGroup.LayoutParams.WRAP_CONTENT,
				ViewGroup.LayoutParams.WRAP_CONTENT,
				Gravity.TOP | Gravity.END);
		lp.setMargins(margin, margin, margin, margin);
		btn.setLayoutParams(lp);

		btn.setOnClickListener(v -> {
			if (mm.getInputHandler() == null || mm.getInputHandler().getTouchController() == null) {
				return;
			}
			mm.getInputHandler().getTouchController().changeState();
			mm.getMainHelper().updateMAME4droid();
			refreshToggleLabel();
		});

		emulatorFrame.addView(btn);
		btn.bringToFront();
		toggleBtn = btn;
		refreshToggleLabel();
	}

	public void refreshToggleLabel() {
		if (toggleBtn == null) {
			return;
		}
		TouchController tc = mm.getInputHandler() != null
				? mm.getInputHandler().getTouchController() : null;
		boolean showing = tc != null && tc.getState() == TouchController.STATE_SHOWING_CONTROLLER;
		toggleBtn.setText(showing
				? mm.getString(R.string.mj_hide_controller)
				: mm.getString(R.string.mj_show_controller));
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
