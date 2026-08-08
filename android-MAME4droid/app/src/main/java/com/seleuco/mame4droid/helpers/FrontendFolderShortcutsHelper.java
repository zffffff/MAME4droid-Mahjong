package com.seleuco.mame4droid.helpers;

import android.app.AlertDialog;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.DialogInterface;
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
 * Compact frontend-only shortcuts for ROM / snap folders (hidden in-game).
 * Basic and full use different screen corners so they do not fight OSC / chrome.
 */
public class FrontendFolderShortcutsHelper {

	private static final int BAR_ID = 0x666a6261; // 'fjba'

	private final MAME4droid mm;
	private LinearLayout bar;

	public FrontendFolderShortcutsHelper(MAME4droid mm) {
		this.mm = mm;
	}

	public void attach(FrameLayout emulatorFrame) {
		if (emulatorFrame == null) {
			return;
		}

		View existing = emulatorFrame.findViewById(BAR_ID);
		if (existing != null) {
			emulatorFrame.removeView(existing);
		}

		float density = mm.getResources().getDisplayMetrics().density;
		int pad = (int) (6 * density);
		int margin = (int) (8 * density);
		int gap = (int) (4 * density);

		LinearLayout row = new LinearLayout(mm);
		row.setId(BAR_ID);
		row.setOrientation(LinearLayout.HORIZONTAL);
		row.setGravity(Gravity.CENTER);

		TextView romBtn = makeChip(pad, density);
		romBtn.setText(R.string.fj_rom_path_button_short);
		romBtn.setContentDescription(mm.getString(R.string.fj_rom_path_button));
		romBtn.setOnClickListener(v -> showRomChooser());
		row.addView(romBtn);

		TextView snapBtn = makeChip(pad, density);
		LinearLayout.LayoutParams snapLp = new LinearLayout.LayoutParams(
				ViewGroup.LayoutParams.WRAP_CONTENT,
				ViewGroup.LayoutParams.WRAP_CONTENT);
		snapLp.leftMargin = gap;
		snapBtn.setLayoutParams(snapLp);
		snapBtn.setText(R.string.fj_snap_path_button_short);
		snapBtn.setContentDescription(mm.getString(R.string.fj_snap_path_button));
		snapBtn.setOnClickListener(v -> showSnapChooser());
		row.addView(snapBtn);

		FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(
				ViewGroup.LayoutParams.WRAP_CONTENT,
				ViewGroup.LayoutParams.WRAP_CONTENT,
				resolveGravity());
		lp.setMargins(margin, margin, margin, margin);
		row.setLayoutParams(lp);

		emulatorFrame.addView(row);
		bar = row;
		refreshVisibility();
	}

	public void refreshVisibility() {
		if (bar == null) {
			return;
		}
		boolean show = Emulator.isEmulating() && !Emulator.isInGame();
		bar.setVisibility(show ? View.VISIBLE : View.GONE);
		if (show) {
			bar.bringToFront();
		}
	}

	private int resolveGravity() {
		// Full: bottom-center — clears top-right float chrome and top-left Exit on stock layouts.
		// Basic: top-center — clears landscape Exit/Option; may sit near the search field.
		if (BuildConfig.FEIJUCHANG_FULL_UX) {
			return Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL;
		}
		return Gravity.TOP | Gravity.CENTER_HORIZONTAL;
	}

	private TextView makeChip(int pad, float density) {
		TextView btn = new TextView(mm);
		btn.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16);
		btn.setTypeface(Typeface.DEFAULT_BOLD);
		btn.setTextColor(Color.WHITE);
		btn.setPadding(pad, pad, pad, pad);
		btn.setMinWidth((int) (36 * density));
		btn.setGravity(Gravity.CENTER);
		GradientDrawable bg = new GradientDrawable();
		bg.setColor(0x99000000);
		bg.setCornerRadius(10f * density);
		btn.setBackground(bg);
		btn.setElevation(3 * density);
		btn.setClickable(true);
		btn.setFocusable(false);
		return btn;
	}

	private void showRomChooser() {
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

	private void showSnapChooser() {
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
