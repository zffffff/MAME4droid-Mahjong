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
 * 通用麻将软键盘：吃碰杠听和 / 开始翻转押注投币常驻；
 * 「打牌 / 更多」只切换字母数字区。横屏参考按键包左右栏，竖屏参考底栏两行。
 */
public class MahjongKeyboardPanel {

	private static final int PANEL_ID = View.generateViewId();
	private static final long MIN_HOLD_MS = 40L;
	private static final int TAB_PLAY = 0;
	private static final int TAB_MORE = 1;

	private final MAME4droid mm;
	private final Handler handler = new Handler(Looper.getMainLooper());
	private View panelRoot;
	private View playLetters;
	private View moreLetters;
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

	private static final KeySpec[] ACTIONS_MJ = {
			key("吃", KeyEvent.KEYCODE_SPACE, ' '),
			key("碰", KeyEvent.KEYCODE_ALT_LEFT, (char) 0),
			key("杠", KeyEvent.KEYCODE_CTRL_LEFT, (char) 0),
			key("听", KeyEvent.KEYCODE_SHIFT_LEFT, (char) 0),
			key("和", KeyEvent.KEYCODE_Z, 'Z'),
	};

	/** 横屏左栏：上→下 开始、翻转、押注、投币（对齐按键包） */
	private static final KeySpec[] ACTIONS_LEFT_LANDSCAPE = {
			key("开始", KeyEvent.KEYCODE_1, '1'),
			key("翻转", KeyEvent.KEYCODE_Y, 'Y'),
			key("押注", KeyEvent.KEYCODE_3, '3'),
			key("投币", KeyEvent.KEYCODE_5, '5'),
	};

	private static final KeySpec[][] LETTERS_PLAY_PORTRAIT = {
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

	private static final KeySpec[][] LETTERS_PLAY_LANDSCAPE = {
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

	/** 两行，与打牌字母区同高，避免标签随页忽大忽小 */
	private static final KeySpec[][] LETTERS_MORE_PORTRAIT = {
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
			},
			{
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

	private static final KeySpec[][] LETTERS_MORE_LANDSCAPE = {
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
		int keyH = (int) (36 * density);
		int keyMinW = (int) (40 * density);
		int gap = (int) (3 * density);
		int edge = (int) (6 * density);
		boolean landscape = mm.getResources().getConfiguration().orientation
				== Configuration.ORIENTATION_LANDSCAPE;

		PassThroughFrameLayout root = new PassThroughFrameLayout(mm);
		root.setId(PANEL_ID);
		root.setBackgroundColor(Color.TRANSPARENT);
		root.setLayoutParams(new FrameLayout.LayoutParams(
				ViewGroup.LayoutParams.MATCH_PARENT,
				ViewGroup.LayoutParams.MATCH_PARENT));
		root.setVisibility(visible ? View.VISIBLE : View.GONE);
		root.setClickable(false);
		root.setFocusable(false);

		if (landscape) {
			attachLandscape(root, keyH, keyMinW, density, gap, edge);
		} else {
			attachPortrait(root, keyH, keyMinW, density, gap, edge);
		}
		applyTab();

		emulatorFrame.addView(root);
		panelRoot = root;
		root.bringToFront();
	}

	private void attachLandscape(FrameLayout root, int keyH, int keyMinW,
			float density, int gap, int edge) {
		int sideKeyH = (int) (40 * density);
		int sideKeyW = (int) (48 * density);

		LinearLayout left = buildVerticalKeys(ACTIONS_LEFT_LANDSCAPE, sideKeyH, sideKeyW, density, gap);
		FrameLayout.LayoutParams leftLp = new FrameLayout.LayoutParams(
				ViewGroup.LayoutParams.WRAP_CONTENT,
				ViewGroup.LayoutParams.WRAP_CONTENT,
				Gravity.START | Gravity.CENTER_VERTICAL);
		leftLp.setMargins(edge, 0, 0, (int) (56 * density));
		left.setLayoutParams(leftLp);
		root.addView(left);

		LinearLayout right = buildVerticalKeys(ACTIONS_MJ, sideKeyH, sideKeyW, density, gap);
		FrameLayout.LayoutParams rightLp = new FrameLayout.LayoutParams(
				ViewGroup.LayoutParams.WRAP_CONTENT,
				ViewGroup.LayoutParams.WRAP_CONTENT,
				Gravity.END | Gravity.CENTER_VERTICAL);
		rightLp.setMargins(0, 0, edge, (int) (56 * density));
		right.setLayoutParams(rightLp);
		root.addView(right);

		root.addView(buildBottomLetterStrip(
				LETTERS_PLAY_LANDSCAPE, LETTERS_MORE_LANDSCAPE,
				keyH, keyMinW, density, gap, edge, true));
	}

	private void attachPortrait(FrameLayout root, int keyH, int keyMinW,
			float density, int gap, int edge) {
		LinearLayout column = new LinearLayout(mm);
		column.setOrientation(LinearLayout.VERTICAL);
		column.setBackgroundColor(Color.TRANSPARENT);
		FrameLayout.LayoutParams colLp = new FrameLayout.LayoutParams(
				ViewGroup.LayoutParams.MATCH_PARENT,
				ViewGroup.LayoutParams.WRAP_CONTENT,
				Gravity.BOTTOM);
		colLp.setMargins(edge, 0, edge, edge);
		column.setLayoutParams(colLp);

		// 第一行：开始 押注 …… 翻转 投币（对齐按键包竖屏底栏）
		LinearLayout row1 = new LinearLayout(mm);
		row1.setOrientation(LinearLayout.HORIZONTAL);
		row1.setGravity(Gravity.CENTER_VERTICAL);
		row1.setLayoutParams(new LinearLayout.LayoutParams(
				ViewGroup.LayoutParams.MATCH_PARENT,
				ViewGroup.LayoutParams.WRAP_CONTENT));
		row1.addView(makeKeyView(key("开始", KeyEvent.KEYCODE_1, '1'), keyH, keyMinW, density, gap));
		row1.addView(makeKeyView(key("押注", KeyEvent.KEYCODE_3, '3'), keyH, keyMinW, density, gap));
		View spacer = new View(mm);
		LinearLayout.LayoutParams spLp = new LinearLayout.LayoutParams(0, 1, 1f);
		spacer.setLayoutParams(spLp);
		row1.addView(spacer);
		row1.addView(makeKeyView(key("翻转", KeyEvent.KEYCODE_Y, 'Y'), keyH, keyMinW, density, gap));
		row1.addView(makeKeyView(key("投币", KeyEvent.KEYCODE_5, '5'), keyH, keyMinW, density, gap));
		LinearLayout.LayoutParams r1Lp = new LinearLayout.LayoutParams(
				ViewGroup.LayoutParams.MATCH_PARENT,
				ViewGroup.LayoutParams.WRAP_CONTENT);
		r1Lp.bottomMargin = gap;
		row1.setLayoutParams(r1Lp);
		column.addView(row1);

		// 第二行：吃碰杠听和
		LinearLayout row2 = buildHorizontalKeys(ACTIONS_MJ, keyH, keyMinW, density, gap, true);
		LinearLayout.LayoutParams r2Lp = new LinearLayout.LayoutParams(
				ViewGroup.LayoutParams.MATCH_PARENT,
				ViewGroup.LayoutParams.WRAP_CONTENT);
		r2Lp.bottomMargin = gap;
		row2.setLayoutParams(r2Lp);
		column.addView(row2);

		column.addView(buildBottomLetterStrip(
				LETTERS_PLAY_PORTRAIT, LETTERS_MORE_PORTRAIT,
				keyH, keyMinW, density, gap, 0, false));

		root.addView(column);
	}

	/**
	 * 底部字母区：左侧固定标签 + 可切换的字母页（标签不进滚动，避免被挤没）。
	 */
	private LinearLayout buildBottomLetterStrip(
			KeySpec[][] playRows, KeySpec[][] moreRows,
			int keyH, int keyMinW, float density, int gap, int edge, boolean landscape) {
		LinearLayout strip = new LinearLayout(mm);
		strip.setOrientation(LinearLayout.HORIZONTAL);
		strip.setGravity(Gravity.BOTTOM);
		strip.setBackgroundColor(Color.TRANSPARENT);

		FrameLayout.LayoutParams stripLp = new FrameLayout.LayoutParams(
				ViewGroup.LayoutParams.MATCH_PARENT,
				ViewGroup.LayoutParams.WRAP_CONTENT,
				Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL);
		if (landscape) {
			stripLp.setMargins(edge, 0, edge, edge);
		}
		strip.setLayoutParams(landscape
				? stripLp
				: new LinearLayout.LayoutParams(
						ViewGroup.LayoutParams.MATCH_PARENT,
						ViewGroup.LayoutParams.WRAP_CONTENT));

		int tabW = (int) (32 * density);
		int letterRows = Math.max(playRows.length, moreRows.length);
		int tabH = letterRows * keyH + Math.max(0, letterRows - 1) * gap;
		strip.addView(buildSideTabs(tabW, tabH, density, gap));

		FrameLayout pages = new FrameLayout(mm);
		LinearLayout.LayoutParams pagesLp = new LinearLayout.LayoutParams(
				0, tabH, 1f);
		pages.setLayoutParams(pagesLp);

		playLetters = buildKeyPage(playRows, keyH, keyMinW, density, gap);
		moreLetters = buildKeyPage(moreRows, keyH, keyMinW, density, gap);
		FrameLayout.LayoutParams pageLp = new FrameLayout.LayoutParams(
				ViewGroup.LayoutParams.MATCH_PARENT,
				ViewGroup.LayoutParams.MATCH_PARENT);
		playLetters.setLayoutParams(pageLp);
		moreLetters.setLayoutParams(new FrameLayout.LayoutParams(pageLp));
		pages.addView(playLetters);
		pages.addView(moreLetters);
		strip.addView(pages);

		return strip;
	}

	private LinearLayout buildSideTabs(int tabW, int tabH, float density, int gap) {
		LinearLayout tabs = new LinearLayout(mm);
		tabs.setOrientation(LinearLayout.VERTICAL);
		tabs.setGravity(Gravity.CENTER_HORIZONTAL);
		LinearLayout.LayoutParams tabsLp = new LinearLayout.LayoutParams(tabW, tabH);
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

		int halfGap = gap / 2;
		LinearLayout.LayoutParams tLp = new LinearLayout.LayoutParams(
				ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f);
		tLp.topMargin = halfGap;
		tLp.bottomMargin = halfGap;
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
		tab.setPadding((int) (4 * density), (int) (4 * density), (int) (4 * density), (int) (4 * density));
		tab.setClickable(true);
		tab.setFocusable(false);
		return tab;
	}

	private void applyTab() {
		if (playLetters != null) {
			playLetters.setVisibility(currentTab == TAB_PLAY ? View.VISIBLE : View.GONE);
		}
		if (moreLetters != null) {
			moreLetters.setVisibility(currentTab == TAB_MORE ? View.VISIBLE : View.GONE);
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
			bg.setColor(0xAA333333);
			tab.setTextColor(0xFFCCCCCC);
		}
		tab.setBackground(bg);
	}

	private LinearLayout buildVerticalKeys(KeySpec[] specs, int keyH, int keyMinW,
			float density, int gap) {
		LinearLayout col = new LinearLayout(mm);
		col.setOrientation(LinearLayout.VERTICAL);
		col.setGravity(Gravity.CENTER_HORIZONTAL);
		for (int i = 0; i < specs.length; i++) {
			TextView key = makeKeyView(specs[i], keyH, keyMinW, density, gap);
			LinearLayout.LayoutParams lp = (LinearLayout.LayoutParams) key.getLayoutParams();
			lp.setMargins(0, i == 0 ? 0 : gap / 2, 0, gap / 2);
			lp.width = keyMinW;
			key.setLayoutParams(lp);
			col.addView(key);
		}
		return col;
	}

	private LinearLayout buildHorizontalKeys(KeySpec[] specs, int keyH, int keyMinW,
			float density, int gap, boolean fillWidth) {
		LinearLayout row = new LinearLayout(mm);
		row.setOrientation(LinearLayout.HORIZONTAL);
		row.setGravity(Gravity.CENTER);
		for (KeySpec spec : specs) {
			TextView key = makeKeyView(spec, keyH, keyMinW, density, gap);
			if (fillWidth) {
				LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
						0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
				lp.setMargins(gap / 2, 0, gap / 2, 0);
				key.setLayoutParams(lp);
				key.setMinWidth(0);
			}
			row.addView(key);
		}
		return row;
	}

	private LinearLayout buildKeyPage(KeySpec[][] rows, int keyH, int keyMinW,
			float density, int gap) {
		LinearLayout column = new LinearLayout(mm);
		column.setOrientation(LinearLayout.VERTICAL);
		column.setGravity(Gravity.BOTTOM);

		for (int r = 0; r < rows.length; r++) {
			HorizontalScrollView scroll = new HorizontalScrollView(mm);
			scroll.setHorizontalScrollBarEnabled(false);
			scroll.setFillViewport(true);
			scroll.setOverScrollMode(View.OVER_SCROLL_IF_CONTENT_SCROLLS);

			LinearLayout rowLayout = new LinearLayout(mm);
			rowLayout.setOrientation(LinearLayout.HORIZONTAL);
			rowLayout.setGravity(Gravity.CENTER);
			for (KeySpec spec : rows[r]) {
				rowLayout.addView(makeKeyView(spec, keyH, keyMinW, density, gap));
			}
			scroll.addView(rowLayout, new ViewGroup.LayoutParams(
					ViewGroup.LayoutParams.WRAP_CONTENT,
					ViewGroup.LayoutParams.WRAP_CONTENT));

			LinearLayout.LayoutParams rowLp = new LinearLayout.LayoutParams(
					ViewGroup.LayoutParams.MATCH_PARENT,
					ViewGroup.LayoutParams.WRAP_CONTENT);
			if (r < rows.length - 1) {
				rowLp.bottomMargin = gap;
			}
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
		keyBg.setColor(0xB3333333);
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
				keyBg.setColor(0xB3333333);
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

	/** 仅子按键命中区域吃触摸，空白处放行给下方游戏画面。 */
	private static final class PassThroughFrameLayout extends FrameLayout {
		PassThroughFrameLayout(android.content.Context context) {
			super(context);
		}

		@Override
		public boolean onInterceptTouchEvent(MotionEvent ev) {
			return false;
		}

		@Override
		public boolean onTouchEvent(MotionEvent event) {
			return false;
		}

		@Override
		public boolean dispatchTouchEvent(MotionEvent ev) {
			final int x = (int) ev.getX();
			final int y = (int) ev.getY();
			for (int i = getChildCount() - 1; i >= 0; i--) {
				View child = getChildAt(i);
				if (child.getVisibility() != VISIBLE) {
					continue;
				}
				if (x < child.getLeft() || x >= child.getRight()
						|| y < child.getTop() || y >= child.getBottom()) {
					continue;
				}
				MotionEvent offset = MotionEvent.obtain(ev);
				offset.offsetLocation(-child.getLeft(), -child.getTop());
				boolean handled = child.dispatchTouchEvent(offset);
				offset.recycle();
				if (handled) {
					return true;
				}
			}
			return false;
		}
	}
}
