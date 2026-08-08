package com.seleuco.mame4droid.helpers;

import android.content.res.Configuration;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Handler;
import android.os.Looper;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;
import android.widget.TextView;

import com.seleuco.mame4droid.Emulator;
import com.seleuco.mame4droid.MAME4droid;

/**
 * 通用麻将软键盘：两页「打牌 / 更多」，侧边标签切换，游戏中可随时切换。
 * 打牌页：吃碰杠听和等中文键 + 选牌 A–N；更多页：其余字母数字，以及海底/大小等少用键。
 */
public class MahjongKeyboardPanel {

	private static final int PANEL_ID = View.generateViewId();
	private static final long MIN_HOLD_MS = 40L;
	private static final int TAB_PLAY = 0;
	private static final int TAB_MORE = 1;

	private final MAME4droid mm;
	private final Handler handler = new Handler(Looper.getMainLooper());
	private View panelRoot;
	private LinearLayout playPage;
	private LinearLayout morePage;
	private TextView tabPlay;
	private TextView tabMore;
	private boolean visible = false;
	private int currentTab = TAB_PLAY;

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

	private static KeySpec key(String label, int keyCode, char unicode) {
		return new KeySpec(label, keyCode, unicode);
	}

	/** 打牌页 · 竖屏 */
	private static final KeySpec[][] PLAY_PORTRAIT = {
			{
					key("吃", KeyEvent.KEYCODE_SPACE, ' '),
					key("碰", KeyEvent.KEYCODE_ALT_LEFT, (char) 0),
					key("杠", KeyEvent.KEYCODE_CTRL_LEFT, (char) 0),
					key("听", KeyEvent.KEYCODE_SHIFT_LEFT, (char) 0),
					key("和", KeyEvent.KEYCODE_Z, 'Z'),
			},
			{
					key("开始", KeyEvent.KEYCODE_1, '1'),
					key("投币", KeyEvent.KEYCODE_5, '5'),
					key("押注", KeyEvent.KEYCODE_3, '3'),
					key("翻转", KeyEvent.KEYCODE_Y, 'Y'),
			},
			{
					key("A", KeyEvent.KEYCODE_A, 'A'),
					key("B", KeyEvent.KEYCODE_B, 'B'),
					key("C", KeyEvent.KEYCODE_C, 'C'),
					key("D", KeyEvent.KEYCODE_D, 'D'),
					key("E", KeyEvent.KEYCODE_E, 'E'),
					key("F", KeyEvent.KEYCODE_F, 'F'),
					key("G", KeyEvent.KEYCODE_G, 'G'),
			},
			{
					key("H", KeyEvent.KEYCODE_H, 'H'),
					key("I", KeyEvent.KEYCODE_I, 'I'),
					key("J", KeyEvent.KEYCODE_J, 'J'),
					key("K", KeyEvent.KEYCODE_K, 'K'),
					key("L", KeyEvent.KEYCODE_L, 'L'),
					key("M", KeyEvent.KEYCODE_M, 'M'),
					key("N", KeyEvent.KEYCODE_N, 'N'),
			},
	};

	/** 打牌页 · 横屏（更扁、每行更满） */
	private static final KeySpec[][] PLAY_LANDSCAPE = {
			{
					key("吃", KeyEvent.KEYCODE_SPACE, ' '),
					key("碰", KeyEvent.KEYCODE_ALT_LEFT, (char) 0),
					key("杠", KeyEvent.KEYCODE_CTRL_LEFT, (char) 0),
					key("听", KeyEvent.KEYCODE_SHIFT_LEFT, (char) 0),
					key("和", KeyEvent.KEYCODE_Z, 'Z'),
					key("开始", KeyEvent.KEYCODE_1, '1'),
					key("投币", KeyEvent.KEYCODE_5, '5'),
					key("押注", KeyEvent.KEYCODE_3, '3'),
					key("翻转", KeyEvent.KEYCODE_Y, 'Y'),
			},
			{
					key("A", KeyEvent.KEYCODE_A, 'A'),
					key("B", KeyEvent.KEYCODE_B, 'B'),
					key("C", KeyEvent.KEYCODE_C, 'C'),
					key("D", KeyEvent.KEYCODE_D, 'D'),
					key("E", KeyEvent.KEYCODE_E, 'E'),
					key("F", KeyEvent.KEYCODE_F, 'F'),
					key("G", KeyEvent.KEYCODE_G, 'G'),
					key("H", KeyEvent.KEYCODE_H, 'H'),
					key("I", KeyEvent.KEYCODE_I, 'I'),
					key("J", KeyEvent.KEYCODE_J, 'J'),
					key("K", KeyEvent.KEYCODE_K, 'K'),
					key("L", KeyEvent.KEYCODE_L, 'L'),
					key("M", KeyEvent.KEYCODE_M, 'M'),
					key("N", KeyEvent.KEYCODE_N, 'N'),
			},
	};

	/**
	 * 更多页：其余数字/字母 + 通用键盘较少用的海底/大小。
	 * 打牌已占：1 3 5、A–N、Y、Z；洗分先标 W。
	 */
	private static final KeySpec[][] MORE_PORTRAIT = {
			{
					key("0", KeyEvent.KEYCODE_0, '0'),
					key("2", KeyEvent.KEYCODE_2, '2'),
					key("4", KeyEvent.KEYCODE_4, '4'),
					key("6", KeyEvent.KEYCODE_6, '6'),
					key("7", KeyEvent.KEYCODE_7, '7'),
					key("8", KeyEvent.KEYCODE_8, '8'),
					key("9", KeyEvent.KEYCODE_9, '9'),
			},
			{
					key("海底", KeyEvent.KEYCODE_O, 'O'),
					key("大", KeyEvent.KEYCODE_R, 'R'),
					key("小", KeyEvent.KEYCODE_DEL, (char) 0),
					key("P", KeyEvent.KEYCODE_P, 'P'),
					key("Q", KeyEvent.KEYCODE_Q, 'Q'),
					key("S", KeyEvent.KEYCODE_S, 'S'),
			},
			{
					key("T", KeyEvent.KEYCODE_T, 'T'),
					key("U", KeyEvent.KEYCODE_U, 'U'),
					key("V", KeyEvent.KEYCODE_V, 'V'),
					key("W", KeyEvent.KEYCODE_W, 'W'),
					key("X", KeyEvent.KEYCODE_X, 'X'),
			},
	};

	private static final KeySpec[][] MORE_LANDSCAPE = {
			{
					key("0", KeyEvent.KEYCODE_0, '0'),
					key("2", KeyEvent.KEYCODE_2, '2'),
					key("4", KeyEvent.KEYCODE_4, '4'),
					key("6", KeyEvent.KEYCODE_6, '6'),
					key("7", KeyEvent.KEYCODE_7, '7'),
					key("8", KeyEvent.KEYCODE_8, '8'),
					key("9", KeyEvent.KEYCODE_9, '9'),
					key("海底", KeyEvent.KEYCODE_O, 'O'),
					key("大", KeyEvent.KEYCODE_R, 'R'),
					key("小", KeyEvent.KEYCODE_DEL, (char) 0),
					key("P", KeyEvent.KEYCODE_P, 'P'),
					key("Q", KeyEvent.KEYCODE_Q, 'Q'),
					key("S", KeyEvent.KEYCODE_S, 'S'),
					key("T", KeyEvent.KEYCODE_T, 'T'),
					key("U", KeyEvent.KEYCODE_U, 'U'),
					key("V", KeyEvent.KEYCODE_V, 'V'),
					key("W", KeyEvent.KEYCODE_W, 'W'),
					key("X", KeyEvent.KEYCODE_X, 'X'),
			},
	};

	public MahjongKeyboardPanel(MAME4droid mm) {
		this.mm = mm;
	}

	public void setVisible(boolean show) {
		visible = show;
		if (panelRoot != null) {
			panelRoot.setVisibility(show ? View.VISIBLE : View.GONE);
			if (show) {
				panelRoot.bringToFront();
			}
		}
	}

	public boolean isVisible() {
		return visible;
	}

	public void toggle() {
		setVisible(!visible);
	}

	public void toggleVisible() {
		toggle();
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
		boolean landscape = mm.getResources().getConfiguration().orientation
				== Configuration.ORIENTATION_LANDSCAPE;

		LinearLayout root = new LinearLayout(mm);
		root.setId(PANEL_ID);
		root.setOrientation(LinearLayout.HORIZONTAL);
		root.setGravity(Gravity.CENTER_VERTICAL);
		root.setPadding(pad, pad, pad, pad);
		GradientDrawable bg = new GradientDrawable();
		bg.setColor(0x99000000);
		bg.setCornerRadius(10f * density);
		root.setBackground(bg);
		root.setElevation(6 * density);

		root.addView(buildSideTabs(density, gap));

		LinearLayout pages = new LinearLayout(mm);
		pages.setOrientation(LinearLayout.VERTICAL);
		pages.setLayoutParams(new LinearLayout.LayoutParams(
				0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
		playPage = buildKeyPage(landscape ? PLAY_LANDSCAPE : PLAY_PORTRAIT, keyH, keyMinW, density, gap);
		morePage = buildKeyPage(landscape ? MORE_LANDSCAPE : MORE_PORTRAIT, keyH, keyMinW, density, gap);
		pages.addView(playPage);
		pages.addView(morePage);
		root.addView(pages);
		applyTab();

		FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(
				ViewGroup.LayoutParams.MATCH_PARENT,
				ViewGroup.LayoutParams.WRAP_CONTENT,
				Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL);
		lp.setMargins((int) (6 * density), 0, (int) (6 * density), (int) (6 * density));
		root.setLayoutParams(lp);
		root.setVisibility(visible ? View.VISIBLE : View.GONE);

		emulatorFrame.addView(root);
		panelRoot = root;
		root.bringToFront();
	}

	/** 左侧竖排标签，避免再占一整行高度。 */
	private LinearLayout buildSideTabs(float density, int gap) {
		LinearLayout tabs = new LinearLayout(mm);
		tabs.setOrientation(LinearLayout.VERTICAL);
		tabs.setGravity(Gravity.CENTER_HORIZONTAL);
		LinearLayout.LayoutParams tabsLp = new LinearLayout.LayoutParams(
				ViewGroup.LayoutParams.WRAP_CONTENT,
				ViewGroup.LayoutParams.MATCH_PARENT);
		tabsLp.rightMargin = gap;
		tabs.setLayoutParams(tabsLp);

		tabPlay = makeTab("打\n牌", density);
		tabMore = makeTab("更\n多", density);
		tabPlay.setOnClickListener(v -> {
			currentTab = TAB_PLAY;
			applyTab();
		});
		tabMore.setOnClickListener(v -> {
			currentTab = TAB_MORE;
			applyTab();
		});

		LinearLayout.LayoutParams tLp = new LinearLayout.LayoutParams(
				ViewGroup.LayoutParams.WRAP_CONTENT, 0, 1f);
		tLp.setMargins(0, gap / 2, 0, gap / 2);
		tabPlay.setLayoutParams(tLp);
		tabMore.setLayoutParams(new LinearLayout.LayoutParams(tLp));

		tabs.addView(tabPlay);
		tabs.addView(tabMore);
		return tabs;
	}

	private TextView makeTab(String label, float density) {
		TextView tab = new TextView(mm);
		tab.setText(label);
		tab.setGravity(Gravity.CENTER);
		tab.setTypeface(Typeface.DEFAULT_BOLD);
		tab.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
		tab.setPadding((int) (6 * density), (int) (8 * density), (int) (6 * density), (int) (8 * density));
		tab.setMinWidth((int) (28 * density));
		tab.setClickable(true);
		tab.setFocusable(false);
		return tab;
	}

	private void applyTab() {
		if (playPage != null) {
			playPage.setVisibility(currentTab == TAB_PLAY ? View.VISIBLE : View.GONE);
		}
		if (morePage != null) {
			morePage.setVisibility(currentTab == TAB_MORE ? View.VISIBLE : View.GONE);
		}
		styleTab(tabPlay, currentTab == TAB_PLAY);
		styleTab(tabMore, currentTab == TAB_MORE);
	}

	private void styleTab(TextView tab, boolean selected) {
		if (tab == null) {
			return;
		}
		float density = mm.getResources().getDisplayMetrics().density;
		GradientDrawable bg = new GradientDrawable();
		bg.setCornerRadius(8f * density);
		if (selected) {
			bg.setColor(0xCC555555);
			tab.setTextColor(Color.WHITE);
		} else {
			bg.setColor(0x66222222);
			tab.setTextColor(0xFFCCCCCC);
		}
		tab.setBackground(bg);
	}

	private LinearLayout buildKeyPage(KeySpec[][] rows, int keyH, int keyMinW, float density, int gap) {
		LinearLayout column = new LinearLayout(mm);
		column.setOrientation(LinearLayout.VERTICAL);
		column.setLayoutParams(new LinearLayout.LayoutParams(
				ViewGroup.LayoutParams.MATCH_PARENT,
				ViewGroup.LayoutParams.WRAP_CONTENT));

		for (KeySpec[] row : rows) {
			HorizontalScrollView scroll = new HorizontalScrollView(mm);
			scroll.setHorizontalScrollBarEnabled(false);
			scroll.setFillViewport(true);

			LinearLayout rowLayout = new LinearLayout(mm);
			rowLayout.setOrientation(LinearLayout.HORIZONTAL);
			rowLayout.setGravity(Gravity.CENTER);
			for (KeySpec spec : row) {
				rowLayout.addView(makeKeyView(spec, keyH, keyMinW, density, gap));
			}
			scroll.addView(rowLayout, new ViewGroup.LayoutParams(
					ViewGroup.LayoutParams.WRAP_CONTENT,
					ViewGroup.LayoutParams.WRAP_CONTENT));

			LinearLayout.LayoutParams rowLp = new LinearLayout.LayoutParams(
					ViewGroup.LayoutParams.MATCH_PARENT,
					ViewGroup.LayoutParams.WRAP_CONTENT);
			rowLp.bottomMargin = gap;
			scroll.setLayoutParams(rowLp);
			column.addView(scroll);
		}
		return column;
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
