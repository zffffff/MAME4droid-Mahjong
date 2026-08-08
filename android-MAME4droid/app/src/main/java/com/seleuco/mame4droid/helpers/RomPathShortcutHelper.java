package com.seleuco.mame4droid.helpers;

import android.app.AlertDialog;
import android.content.ActivityNotFoundException;
import android.content.DialogInterface;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.TextView;

import com.seleuco.mame4droid.Emulator;
import com.seleuco.mame4droid.MAME4droid;
import com.seleuco.mame4droid.R;

/**
 * One-tap ROM folder shortcut on the MAME frontend (hidden while a game runs).
 */
public class RomPathShortcutHelper {

	private static final int BUTTON_ID = 0x726f6d70; // 'romp'

	private final MAME4droid mm;
	private TextView button;

	public RomPathShortcutHelper(MAME4droid mm) {
		this.mm = mm;
	}

	public void attach(FrameLayout emulatorFrame) {
		if (emulatorFrame == null) {
			return;
		}

		View existing = emulatorFrame.findViewById(BUTTON_ID);
		if (existing != null) {
			emulatorFrame.removeView(existing);
		}

		float density = mm.getResources().getDisplayMetrics().density;
		int padH = (int) (10 * density);
		int padV = (int) (6 * density);
		int margin = (int) (8 * density);

		TextView btn = new TextView(mm);
		btn.setId(BUTTON_ID);
		btn.setText(R.string.fj_rom_path_button);
		btn.setContentDescription(mm.getString(R.string.fj_rom_path_button));
		btn.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
		btn.setTypeface(Typeface.DEFAULT_BOLD);
		btn.setTextColor(Color.WHITE);
		btn.setPadding(padH, padV, padH, padV);
		GradientDrawable bg = new GradientDrawable();
		bg.setColor(0x99000000);
		bg.setCornerRadius(10f * density);
		btn.setBackground(bg);
		btn.setElevation(3 * density);
		btn.setClickable(true);
		btn.setFocusable(false);
		btn.setOnClickListener(v -> showChooser());

		// Top-center: landscape OSC puts Exit at top-left and Option at top-right.
		FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(
				ViewGroup.LayoutParams.WRAP_CONTENT,
				ViewGroup.LayoutParams.WRAP_CONTENT,
				Gravity.TOP | Gravity.CENTER_HORIZONTAL);
		lp.setMargins(margin, margin, margin, margin);
		btn.setLayoutParams(lp);

		emulatorFrame.addView(btn);
		button = btn;
		refreshVisibility();
	}

	public void refreshVisibility() {
		if (button == null) {
			return;
		}
		boolean show = Emulator.isEmulating() && !Emulator.isInGame();
		button.setVisibility(show ? View.VISIBLE : View.GONE);
		if (show) {
			button.bringToFront();
		}
	}

	private void showChooser() {
		new AlertDialog.Builder(mm)
				.setTitle(R.string.fj_rom_path_dialog_title)
				.setMessage(R.string.fj_rom_path_dialog_message)
				.setPositiveButton(R.string.fj_rom_path_pick_folder, new DialogInterface.OnClickListener() {
					@Override
					public void onClick(DialogInterface dialog, int which) {
						mm.getMainHelper().startRomsDirectoryPicker();
					}
				})
				.setNeutralButton(R.string.fj_rom_path_use_default, new DialogInterface.OnClickListener() {
					@Override
					public void onClick(DialogInterface dialog, int which) {
						mm.getMainHelper().applyDefaultRomsPathAndReload();
					}
				})
				.setNegativeButton(R.string.cancel, null)
				.show();
	}
}
