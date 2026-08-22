package com.seleuco.mame4droid.helpers;

import android.app.AlertDialog;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

import com.seleuco.mame4droid.BuildConfig;
import com.seleuco.mame4droid.Emulator;
import com.seleuco.mame4droid.MAME4droid;
import com.seleuco.mame4droid.R;

/**
 * Basic edition: collapsible top-right toolbox (ROM / snap / Chinese names).
 * Full edition uses {@link MahjongExperienceHelper} instead.
 */
public class FrontendFolderShortcutsHelper {

	private static final int BAR_ID = 0x666a6261; // 'fjba'

	private final MAME4droid mm;
	private LinearLayout floatBar;
	private LinearLayout panel;
	private TextView chromeToggle;
	private TextView cnBtn;
	private boolean menuExpanded;

	public FrontendFolderShortcutsHelper(MAME4droid mm) {
		this.mm = mm;
	}

	public void attach(FrameLayout emulatorFrame) {
		if (emulatorFrame == null) {
			return;
		}

		if (BuildConfig.FEIJUCHANG_FULL_UX) {
			View existingFull = emulatorFrame.findViewById(BAR_ID);
			if (existingFull != null) {
				emulatorFrame.removeView(existingFull);
			}
			floatBar = null;
			panel = null;
			return;
		}

		View existing = emulatorFrame.findViewById(BAR_ID);
		if (existing != null) {
			emulatorFrame.removeView(existing);
		}

		float density = mm.getResources().getDisplayMetrics().density;
		int padH = (int) (10 * density);
		int padV = (int) (6 * density);
		int margin = (int) (8 * density);
		int gap = (int) (6 * density);

		LinearLayout bar = new LinearLayout(mm);
		bar.setId(BAR_ID);
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
			bringToFront();
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

		TextView romBtn = addPanelButton(panel, padH, padV, density, gap, v -> {
			collapseMenu();
			showRomChooser();
		});
		romBtn.setText(mm.getString(R.string.mj_set_rom));
		romBtn.setContentDescription(mm.getString(R.string.fj_rom_path_button));

		TextView snapBtn = addPanelButton(panel, padH, padV, density, gap, v -> {
			collapseMenu();
			showSnapChooser();
		});
		snapBtn.setText(mm.getString(R.string.mj_set_snap));
		snapBtn.setContentDescription(mm.getString(R.string.fj_snap_path_button));

		cnBtn = addPanelButton(panel, padH, padV, density, 0, v -> toggleChineseNames());
		LinearLayout.LayoutParams cnLp = (LinearLayout.LayoutParams) cnBtn.getLayoutParams();
		cnLp.bottomMargin = 0;
		cnBtn.setLayoutParams(cnLp);
		refreshChineseLabel();

		bar.addView(panel);
		emulatorFrame.addView(bar);
		floatBar = bar;

		menuExpanded = false;
		applyMenuExpanded();
		refreshVisibility();
	}

	public void refreshVisibility() {
		if (BuildConfig.FEIJUCHANG_FULL_UX) {
			if (mm.getMahjongHelper() != null) {
				mm.getMahjongHelper().refreshFolderActionsVisibility();
			}
			return;
		}
		if (floatBar == null) {
			return;
		}
		boolean show = Emulator.isEmulating() && !Emulator.isInGame();
		floatBar.setVisibility(show ? View.VISIBLE : View.GONE);
		if (show) {
			refreshChineseLabel();
			bringToFront();
		}
	}

	private void toggleChineseNames() {
		collapseMenu();
		AssetPackInstaller installer = new AssetPackInstaller(mm);
		if (chineseNamesActive()) {
			installer.removeBasicChineseNames();
			Toast.makeText(mm, R.string.fj_basic_chinese_names_disabled_toast, Toast.LENGTH_LONG).show();
		} else {
			installer.applyBasicChineseNamesInSession();
			Toast.makeText(mm, R.string.fj_basic_chinese_names_enabled_toast, Toast.LENGTH_LONG).show();
		}
		refreshChineseLabel();
	}

	private boolean chineseNamesActive() {
		return mm.getPrefsHelper().isBasicChineseNamesEnabled();
	}

	private void refreshChineseLabel() {
		if (cnBtn == null) {
			return;
		}
		boolean active = chineseNamesActive();
		cnBtn.setText(active
				? mm.getString(R.string.fj_basic_chinese_names_disable)
				: mm.getString(R.string.fj_basic_chinese_names_enable));
		cnBtn.setContentDescription(cnBtn.getText());
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

	private TextView addPanelButton(LinearLayout parent, int padH, int padV, float density,
			int gap, View.OnClickListener listener) {
		TextView btn = makeFloatButton(padH, padV, density);
		btn.setOnClickListener(listener);
		LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
				ViewGroup.LayoutParams.WRAP_CONTENT,
				ViewGroup.LayoutParams.WRAP_CONTENT);
		lp.bottomMargin = gap;
		btn.setLayoutParams(lp);
		parent.addView(btn);
		return btn;
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

	private void bringToFront() {
		if (floatBar != null) {
			floatBar.bringToFront();
		}
	}

	public void showRomChooser() {
		new AlertDialog.Builder(mm)
				.setTitle(R.string.fj_rom_path_dialog_title)
				.setMessage(R.string.fj_rom_path_dialog_message)
				.setPositiveButton(R.string.fj_rom_path_pick_folder, (d, w) ->
						mm.getMainHelper().startRomsDirectoryPicker())
				.setNeutralButton(R.string.fj_rom_path_use_default, (d, w) ->
						mm.getMainHelper().applyDefaultRomsPathAndReload())
				.setNegativeButton(R.string.cancel, null)
				.show();
	}

	public void showSnapChooser() {
		final String snapPath = mm.getMainHelper().getSnapDirectoryPath();
		String msg = mm.getString(R.string.fj_snap_path_dialog_message, snapPath);
		new AlertDialog.Builder(mm)
				.setTitle(R.string.fj_snap_path_dialog_title)
				.setMessage(msg)
				.setPositiveButton(R.string.fj_snap_path_import, (d, w) ->
						mm.getMainHelper().startSnapDirectoryPicker())
				.setNeutralButton(R.string.fj_snap_path_copy, (d, w) -> {
					ClipboardManager cm = (ClipboardManager) mm.getSystemService(Context.CLIPBOARD_SERVICE);
					if (cm != null) {
						cm.setPrimaryClip(ClipData.newPlainText("snap", snapPath));
					}
					Toast.makeText(mm, R.string.fj_snap_path_copied, Toast.LENGTH_SHORT).show();
				})
				.setNegativeButton(R.string.cancel, null)
				.show();
	}
}
