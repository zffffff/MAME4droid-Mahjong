package com.seleuco.mame4droid.helpers;

import android.content.SharedPreferences;
import android.content.pm.ActivityInfo;
import android.content.res.Configuration;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.util.Log;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.TextView;

import com.seleuco.mame4droid.BuildConfig;
import com.seleuco.mame4droid.Emulator;
import com.seleuco.mame4droid.MAME4droid;
import com.seleuco.mame4droid.R;
import com.seleuco.mame4droid.input.TouchController;

import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;

/**
 * Full-edition mahjong UX: defaults, orientation bridge, portrait-forced ROMs,
 * collapsible floating chrome, and the native mahjong keyboard panel.
 * Basic edition only installs the artwork key pack ({@link AssetPackInstaller});
 * all methods here no-op when {@code FEIJUCHANG_FULL_UX} is false.
 */
public class MahjongExperienceHelper {

	private static final String TAG = "MahjongExperience";
	private static final String PREF_SEEDED = "mahjong_defaults_v1";
	private static final String PREF_SEEDED_V2 = "mahjong_defaults_v2";
	private static final String PREF_SEEDED_V3 = "mahjong_defaults_v3";
	private static final String ORIENT_FILE = ".device_orientation";
	private static final int FLOAT_BAR_ID = 0x6D6A6261; // 'mjba'

	private static final String[] PORTRAIT_FORCED_ROMS = {
			"jantouki",
	};

	private final MAME4droid mm;
	private final MahjongKeyboardPanel keyboardPanel;
	private String lastWrittenOrient = null;
	private String lastForcedRom = null;
	private TextView chromeToggle = null;
	private TextView toggleBtn = null;
	private TextView mjKbBtn = null;
	private TextView menuBtn = null;
	private TextView romBtn = null;
	private TextView snapBtn = null;
	private LinearLayout panel = null;
	private LinearLayout floatBar = null;
	private boolean oscForceHidden = false;
	private boolean menuExpanded = false;

	public MahjongExperienceHelper(MAME4droid mm) {
		this.mm = mm;
		this.keyboardPanel = new MahjongKeyboardPanel(mm);
	}

	public MahjongKeyboardPanel getKeyboardPanel() {
		return keyboardPanel;
	}

	public void seedDefaultsIfNeeded() {
		if (!BuildConfig.FEIJUCHANG_FULL_UX) {
			return;
		}
		SharedPreferences p = mm.getPrefsHelper().getSharedPreferences();
		SharedPreferences.Editor e = null;

		if (!p.getBoolean(PREF_SEEDED, false)) {
			e = p.edit();
			e.putString(PrefsHelper.PREF_NUMBUTTONS, "0");
			e.putBoolean(PrefsHelper.PREF_TOUCH_UI, true);
			e.putBoolean(PREF_SEEDED, true);
		}

		if (!p.getBoolean(PREF_SEEDED_V2, false)) {
			if (e == null) e = p.edit();
			e.putString(PrefsHelper.PREF_CONTROLLER_TYPE, String.valueOf(PrefsHelper.PREF_DIGITAL_DPAD));
			e.putBoolean(PrefsHelper.PREF_HIDE_STICK, false);
			e.putBoolean(PREF_SEEDED_V2, true);
		}

		if (!p.getBoolean(PREF_SEEDED_V3, false)) {
			if (e == null) e = p.edit();
			e.putString(PrefsHelper.PREF_NUMBUTTONS, "2");
			e.putBoolean(PREF_SEEDED_V3, true);
		}

		if (e != null) {
			e.apply();
			Log.i(TAG, "Seeded mahjong SharedPreferences defaults");
		}
	}

	public boolean isOscForceHidden() {
		return oscForceHidden;
	}

	public void setOscForceHidden(boolean hidden) {
		oscForceHidden = hidden;
	}

	/**
	 * Collapsible top-right chrome + mahjong keyboard (full edition only).
	 */
	public void attachFloatingControls(FrameLayout emulatorFrame) {
		if (!BuildConfig.FEIJUCHANG_FULL_UX || emulatorFrame == null) {
			return;
		}

		View existing = emulatorFrame.findViewById(FLOAT_BAR_ID);
		if (existing != null) {
			emulatorFrame.removeView(existing);
		}

		float density = mm.getResources().getDisplayMetrics().density;
		int padH = (int) (10 * density);
		int padV = (int) (6 * density);
		int margin = (int) (8 * density);
		int gap = (int) (6 * density);

		LinearLayout bar = new LinearLayout(mm);
		bar.setId(FLOAT_BAR_ID);
		bar.setOrientation(LinearLayout.VERTICAL);
		bar.setGravity(Gravity.END);
		FrameLayout.LayoutParams barLp = new FrameLayout.LayoutParams(
				ViewGroup.LayoutParams.WRAP_CONTENT,
				ViewGroup.LayoutParams.WRAP_CONTENT,
				Gravity.TOP | Gravity.END);
		barLp.setMargins(margin, margin, margin, margin);
		bar.setLayoutParams(barLp);

		chromeToggle = makeFloatButton(padH, padV, density);
		chromeToggle.setOnClickListener(v -> {
			menuExpanded = !menuExpanded;
			applyMenuExpanded();
			bringChromeFront();
		});
		bar.addView(chromeToggle);

		panel = new LinearLayout(mm);
		panel.setOrientation(LinearLayout.VERTICAL);
		panel.setGravity(Gravity.END);
		LinearLayout.LayoutParams panelLp = new LinearLayout.LayoutParams(
				ViewGroup.LayoutParams.WRAP_CONTENT,
				ViewGroup.LayoutParams.WRAP_CONTENT);
		panelLp.topMargin = gap;
		panel.setLayoutParams(panelLp);

		toggleBtn = addPanelButton(panel, padH, padV, density, gap, v -> {
			if (mm.getInputHandler() == null || mm.getInputHandler().getTouchController() == null) {
				return;
			}
			TouchController tc = mm.getInputHandler().getTouchController();
			boolean showing = tc.getState() == TouchController.STATE_SHOWING_CONTROLLER && !oscForceHidden;
			setOscForceHidden(showing);
			mm.getMainHelper().updateMAME4droid();
			refreshToggleLabel();
			collapseMenu();
		});
		toggleBtn.setContentDescription(mm.getString(R.string.mj_toggle_controller));

		mjKbBtn = addPanelButton(panel, padH, padV, density, gap, v -> {
			keyboardPanel.toggleVisible();
			refreshMjKbLabel();
			collapseMenu();
		});

		menuBtn = addPanelButton(panel, padH, padV, density, gap, v -> {
			collapseMenu();
			if (Emulator.isInOptions()) {
				return;
			}
			Emulator.setInOptions(true);
			mm.showDialog(DialogHelper.DIALOG_OPTIONS);
		});
		menuBtn.setText(mm.getString(R.string.mj_menu_button));
		menuBtn.setContentDescription(mm.getString(R.string.mj_menu_button_desc));

		romBtn = addPanelButton(panel, padH, padV, density, gap, v -> {
			collapseMenu();
			FrontendFolderShortcutsHelper folders = mm.getFolderShortcutsHelper();
			if (folders != null) {
				folders.showRomChooser();
			}
		});
		romBtn.setText(mm.getString(R.string.mj_set_rom));
		romBtn.setContentDescription(mm.getString(R.string.fj_rom_path_button));

		snapBtn = addPanelButton(panel, padH, padV, density, gap, v -> {
			collapseMenu();
			FrontendFolderShortcutsHelper folders = mm.getFolderShortcutsHelper();
			if (folders != null) {
				folders.showSnapChooser();
			}
		});
		snapBtn.setText(mm.getString(R.string.mj_set_snap));
		snapBtn.setContentDescription(mm.getString(R.string.fj_snap_path_button));

		// last item: no bottom margin
		LinearLayout.LayoutParams snapLp = (LinearLayout.LayoutParams) snapBtn.getLayoutParams();
		snapLp.bottomMargin = 0;
		snapBtn.setLayoutParams(snapLp);

		bar.addView(panel);
		emulatorFrame.addView(bar);
		floatBar = bar;

		menuExpanded = false;
		keyboardPanel.attach(emulatorFrame);
		refreshToggleLabel();
		refreshMjKbLabel();
		refreshFolderActionsVisibility();
		applyMenuExpanded();
		bringChromeFront();
	}

	/** @deprecated use {@link #attachFloatingControls} */
	public void attachControllerToggle(FrameLayout emulatorFrame) {
		attachFloatingControls(emulatorFrame);
	}

	private TextView addPanelButton(LinearLayout panel, int padH, int padV, float density,
			int gap, View.OnClickListener listener) {
		TextView btn = makeFloatButton(padH, padV, density);
		btn.setOnClickListener(listener);
		LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
				ViewGroup.LayoutParams.WRAP_CONTENT,
				ViewGroup.LayoutParams.WRAP_CONTENT);
		lp.bottomMargin = gap;
		btn.setLayoutParams(lp);
		panel.addView(btn);
		return btn;
	}

	private void collapseMenu() {
		menuExpanded = false;
		applyMenuExpanded();
	}

	private void applyMenuExpanded() {
		if (panel != null) {
			panel.setVisibility(menuExpanded ? View.VISIBLE : View.GONE);
		}
		if (chromeToggle != null) {
			chromeToggle.setText(menuExpanded
					? mm.getString(R.string.mj_chrome_close)
					: mm.getString(R.string.mj_chrome_open));
			chromeToggle.setContentDescription(menuExpanded
					? mm.getString(R.string.mj_chrome_close_desc)
					: mm.getString(R.string.mj_chrome_open_desc));
		}
	}

	/** ROM/snap entries: frontend only (same rule as former folder chips). */
	public void refreshFolderActionsVisibility() {
		boolean show = Emulator.isEmulating() && !Emulator.isInGame();
		if (romBtn != null) {
			romBtn.setVisibility(show ? View.VISIBLE : View.GONE);
		}
		if (snapBtn != null) {
			snapBtn.setVisibility(show ? View.VISIBLE : View.GONE);
		}
		bringChromeFront();
	}

	private TextView makeFloatButton(int padH, int padV, float density) {
		TextView btn = new TextView(mm);
		btn.setTextSize(TypedValue.COMPLEX_UNIT_SP, 18);
		btn.setTypeface(Typeface.DEFAULT);
		btn.setTextColor(Color.WHITE);
		btn.setGravity(Gravity.CENTER);
		btn.setPadding(padH, padV, padH, padV);
		btn.setMinWidth((int) (40 * density));
		btn.setMinHeight((int) (40 * density));
		GradientDrawable bg = new GradientDrawable();
		bg.setColor(0x99000000);
		bg.setCornerRadius(10f * density);
		btn.setBackground(bg);
		btn.setElevation(3 * density);
		btn.setClickable(true);
		btn.setFocusable(false);
		return btn;
	}

	private void bringChromeFront() {
		if (keyboardPanel != null) {
			keyboardPanel.bringToFront();
		}
		if (floatBar != null) {
			floatBar.bringToFront();
		}
	}

	public void refreshToggleLabel() {
		if (toggleBtn == null) {
			return;
		}
		TouchController tc = mm.getInputHandler() != null
				? mm.getInputHandler().getTouchController() : null;
		boolean showing = tc != null && tc.getState() == TouchController.STATE_SHOWING_CONTROLLER
				&& !oscForceHidden;
		toggleBtn.setText(showing
				? mm.getString(R.string.mj_hide_controller)
				: mm.getString(R.string.mj_show_controller));
		toggleBtn.setContentDescription(showing
				? mm.getString(R.string.mj_hide_controller_desc)
				: mm.getString(R.string.mj_show_controller_desc));
		bringChromeFront();
	}

	public void refreshMjKbLabel() {
		if (mjKbBtn == null) {
			return;
		}
		boolean showing = keyboardPanel != null && keyboardPanel.isVisible();
		mjKbBtn.setText(showing
				? mm.getString(R.string.mj_hide_keyboard)
				: mm.getString(R.string.mj_show_keyboard));
		mjKbBtn.setContentDescription(showing
				? mm.getString(R.string.mj_hide_keyboard_desc)
				: mm.getString(R.string.mj_show_keyboard_desc));
		bringChromeFront();
	}

	public void syncOrientationBridge() {
		if (!BuildConfig.FEIJUCHANG_FULL_UX) {
			return;
		}
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

	public void applyRomOrientationPolicy() {
		if (!BuildConfig.FEIJUCHANG_FULL_UX) {
			return;
		}
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
