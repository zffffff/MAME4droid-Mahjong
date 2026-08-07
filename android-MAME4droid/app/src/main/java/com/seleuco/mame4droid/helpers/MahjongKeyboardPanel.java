package com.seleuco.mame4droid.helpers;

import android.content.SharedPreferences;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Handler;
import android.os.Looper;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;
import android.widget.TextView;

import com.seleuco.mame4droid.Emulator;
import com.seleuco.mame4droid.MAME4droid;
import com.seleuco.mame4droid.R;

import android.view.KeyEvent;

/**
 * On-screen mahjong "keyboard" that injects the same Android key codes MAME
 * expects for its default mahjong PC-keyboard mapping (see MAME defaultkeys /
 * inpttype.ipp). Analogous to the virtual gamepad, but for mahjong keys.
 */
public class MahjongKeyboardPanel {

	private static final String PREF_VISIBLE = "mahjong_kb_panel_visible";
	private static final int PANEL_ID = 0x6D6A6B62; // 'mjkb'
	private static final int MIN_HOLD_MS = 45;

	private static final class KeySpec {
		final String label;
		final int keyCode;
		final char unicode;

		KeySpec(String label, int keyCode, char unicode) {
			this.label = label;
			this.keyCode = keyCode;
			this.unicode = unicode;
		}
	}

	/** Defaults match MAME Player1 mahjong keyboard bindings. */
	private static final KeySpec[][] ROWS = {
			{
					new KeySpec("吃", KeyEvent.KEYCODE_SPACE, ' '),
					new KeySpec("碰", KeyEvent.KEYCODE_ALT_LEFT, '\0'),
					new KeySpec("杠", KeyEvent.KEYCODE_CTRL_LEFT, '\0'),
					new KeySpec("听", KeyEvent.KEYCODE_SHIFT_LEFT, '\0'),
					new KeySpec("和", KeyEvent.KEYCODE_Z, 'z'),
					new KeySpec("开始", KeyEvent.KEYCODE_1, '1'),
					new KeySpec("投币", KeyEvent.KEYCODE_5, '5'),
					new KeySpec("押注", KeyEvent.KEYCODE_3, '3'),
					new KeySpec("翻转", KeyEvent.KEYCODE_Y, 'y'),
			},
			{
					new KeySpec("A", KeyEvent.KEYCODE_A, 'a'),
					new KeySpec("B", KeyEvent.KEYCODE_B, 'b'),
					new KeySpec("C", KeyEvent.KEYCODE_C, 'c'),
					new KeySpec("D", KeyEvent.KEYCODE_D, 'd'),
					new KeySpec("E", KeyEvent.KEYCODE_E, 'e'),
					new KeySpec("F", KeyEvent.KEYCODE_F, 'f'),
					new KeySpec("G", KeyEvent.KEYCODE_G, 'g'),
			},
			{
					new KeySpec("H", KeyEvent.KEYCODE_H, 'h'),
					new KeySpec("I", KeyEvent.KEYCODE_I, 'i'),
					new KeySpec("J", KeyEvent.KEYCODE_J, 'j'),
					new KeySpec("K", KeyEvent.KEYCODE_K, 'k'),
					new KeySpec("L", KeyEvent.KEYCODE_L, 'l'),
					new KeySpec("M", KeyEvent.KEYCODE_M, 'm'),
					new KeySpec("N", KeyEvent.KEYCODE_N, 'n'),
			},
			{
					new KeySpec("O", KeyEvent.KEYCODE_O, 'o'),
					new KeySpec("P", KeyEvent.KEYCODE_SEMICOLON, ';'),
					new KeySpec("Q", KeyEvent.KEYCODE_Q, 'q'),
					new KeySpec("得分", KeyEvent.KEYCODE_CTRL_RIGHT, '\0'),
					new KeySpec("比倍", KeyEvent.KEYCODE_SHIFT_RIGHT, '\0'),
					new KeySpec("大", KeyEvent.KEYCODE_ENTER, '\n'),
					new KeySpec("小", KeyEvent.KEYCODE_DEL, '\0'),
					new KeySpec("海底", KeyEvent.KEYCODE_ALT_RIGHT, '\0'),
			},
	};

	private final MAME4droid mm;
	private final Handler handler = new Handler(Looper.getMainLooper());
	private View panelRoot = null;
	private boolean visible;

	public MahjongKeyboardPanel(MAME4droid mm) {
		this.mm = mm;
		this.visible = mm.getPrefsHelper().getSharedPreferences()
				.getBoolean(PREF_VISIBLE, true);
	}

	public boolean isVisible() {
		return visible;
	}

	public void setVisible(boolean show) {
		visible = show;
		SharedPreferences.Editor e = mm.getPrefsHelper().getSharedPreferences().edit();
		e.putBoolean(PREF_VISIBLE, show);
		e.apply();
		if (panelRoot != null) {
			panelRoot.setVisibility(show ? View.VISIBLE : View.GONE);
		}
	}

	public void toggleVisible() {
		setVisible(!visible);
	}

	public void attach(FrameLayout emulatorFrame) {
		if (emulatorFrame == null) {
			return;
		}
		View existing = emulatorFrame.findViewById(PANEL_ID);
		if (existing != null) {
			emulatorFrame.removeView(existing);
		}

		float density = mm.getResources().getDisplayMetrics().density;
		int pad = (int) (4 * density);
		int keyH = (int) (36 * density);
		int keyMinW = (int) (40 * density);
		int gap = (int) (3 * density);

		LinearLayout column = new LinearLayout(mm);
		column.setOrientation(LinearLayout.VERTICAL);
		column.setPadding(pad, pad, pad, pad);
		GradientDrawable bg = new GradientDrawable();
		bg.setColor(0x99000000);
		bg.setCornerRadius(10f * density);
		column.setBackground(bg);
		column.setElevation(6 * density);

		for (KeySpec[] row : ROWS) {
			LinearLayout rowLayout = new LinearLayout(mm);
			rowLayout.setOrientation(LinearLayout.HORIZONTAL);
			rowLayout.setGravity(Gravity.CENTER);
			LinearLayout.LayoutParams rowLp = new LinearLayout.LayoutParams(
					ViewGroup.LayoutParams.WRAP_CONTENT,
					ViewGroup.LayoutParams.WRAP_CONTENT);
			rowLp.bottomMargin = gap;
			rowLayout.setLayoutParams(rowLp);

			for (KeySpec spec : row) {
				TextView key = makeKeyView(spec, keyH, keyMinW, density, gap);
				rowLayout.addView(key);
			}
			column.addView(rowLayout);
		}

		HorizontalScrollView scroll = new HorizontalScrollView(mm);
		scroll.setId(PANEL_ID);
		scroll.setHorizontalScrollBarEnabled(false);
		scroll.setFillViewport(true);
		scroll.addView(column, new ViewGroup.LayoutParams(
				ViewGroup.LayoutParams.WRAP_CONTENT,
				ViewGroup.LayoutParams.WRAP_CONTENT));

		FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(
				ViewGroup.LayoutParams.MATCH_PARENT,
				ViewGroup.LayoutParams.WRAP_CONTENT,
				Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL);
		lp.setMargins((int) (6 * density), 0, (int) (6 * density), (int) (6 * density));
		scroll.setLayoutParams(lp);
		scroll.setVisibility(visible ? View.VISIBLE : View.GONE);

		emulatorFrame.addView(scroll);
		panelRoot = scroll;
		scroll.bringToFront();
	}

	private TextView makeKeyView(KeySpec spec, int keyH, int keyMinW, float density, int gap) {
		TextView key = new TextView(mm);
		key.setText(spec.label);
		key.setGravity(Gravity.CENTER);
		key.setTextColor(Color.WHITE);
		key.setTypeface(Typeface.DEFAULT_BOLD);
		key.setTextSize(TypedValue.COMPLEX_UNIT_SP, spec.label.length() > 1 ? 11 : 14);
		key.setMinWidth(keyMinW);
		key.setMinHeight(keyH);
		key.setPadding((int) (8 * density), (int) (4 * density), (int) (8 * density), (int) (4 * density));
		GradientDrawable keyBg = new GradientDrawable();
		keyBg.setColor(0xCC333333);
		keyBg.setCornerRadius(8f * density);
		key.setBackground(keyBg);
		key.setClickable(true);
		key.setFocusable(false);

		LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
				ViewGroup.LayoutParams.WRAP_CONTENT,
				ViewGroup.LayoutParams.WRAP_CONTENT);
		lp.setMargins(gap / 2, 0, gap / 2, 0);
		key.setLayoutParams(lp);

		final int keyCode = spec.keyCode;
		final char unicode = spec.unicode;
		final Runnable[] pendingUp = new Runnable[1];

		key.setOnTouchListener((v, event) -> {
			int action = event.getActionMasked();
			if (action == MotionEvent.ACTION_DOWN) {
				if (pendingUp[0] != null) {
					handler.removeCallbacks(pendingUp[0]);
					pendingUp[0] = null;
				}
				Emulator.setKeyData(keyCode, Emulator.KEY_DOWN, unicode);
				keyBg.setColor(0xCC666666);
				key.setBackground(keyBg);
				return true;
			}
			if (action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_CANCEL) {
				long hold = event.getEventTime() - event.getDownTime();
				Runnable up = () -> {
					Emulator.setKeyData(keyCode, Emulator.KEY_UP, unicode);
					pendingUp[0] = null;
				};
				if (hold < MIN_HOLD_MS) {
					pendingUp[0] = up;
					handler.postDelayed(up, MIN_HOLD_MS - hold);
				} else {
					up.run();
				}
				keyBg.setColor(0xCC333333);
				key.setBackground(keyBg);
				return true;
			}
			return false;
		});
		return key;
	}

	public void bringToFront() {
		if (panelRoot != null) {
			panelRoot.bringToFront();
		}
	}
}
