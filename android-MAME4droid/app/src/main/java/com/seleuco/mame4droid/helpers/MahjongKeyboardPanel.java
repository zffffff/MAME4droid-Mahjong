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
import android.view.ViewTreeObserver;
import android.widget.FrameLayout;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;
import android.widget.TextView;

import com.seleuco.mame4droid.Emulator;
import com.seleuco.mame4droid.MAME4droid;

/**
 * 通用麻将软键盘：吃碰杠听和 / 开始翻转押注投币常驻；
 * 「打牌 / 更多」只切换字母数字区。横屏常驻键贴游戏画面两侧（非屏幕边缘）。
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
	private View leftRail;
	private View rightRail;
	private View bottomStrip;
	private ViewTreeObserver.OnGlobalLayoutListener gameFrameListener;
	private boolean visible = false;
	private int currentTab = TAB_PLAY;
	private int sideKeyW;
	private int sideGap;
	private int edgePad;
	private int bottomReserve;

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

	/** 横屏左栏：上→下 开始、翻转、押注、投币 */
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
				syncToGameFrame();
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
		detachGameFrameListener();
		View existing = emulatorFrame.findViewById(PANEL_ID);
		if (existing != null) {
			emulatorFrame.removeView(existing);
		}

		float density = mm.getResources().getDisplayMetrics().density;
		int keyH = (int) (36 * density);
		int keyMinW = (int) (40 * density);
		int gap = (int) (3 * density);
		int edge = (int) (6 * density);
		sideKeyW = (int) (48 * density);
		sideGap = gap;
		edgePad = edge;
		bottomReserve = keyH + edge * 2 + (int) (4 * density);
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

		leftRail = null;
		rightRail = null;
		bottomStrip = null;

		if (landscape) {
			attachLandscape(root, keyH, keyMinW, density, gap, edge);
		} else {
			attachPortrait(root, keyH, keyMinW, density, gap, edge);
		}
		applyTab();

		emulatorFrame.addView(root);
		panelRoot = root;
		root.bringToFront();
		attachGameFrameListener();
		root.post(this::syncToGameFrame);
	}

	private void attachLandscape(FrameLayout root, int keyH, int keyMinW,
			float density, int gap, int edge) {
		int sideKeyH = (int) (40 * density);

		leftRail = buildVerticalKeys(ACTIONS_LEFT_LANDSCAPE, sideKeyH, sideKeyW, density, gap);
		FrameLayout.LayoutParams leftLp = new FrameLayout.LayoutParams(
				sideKeyW, ViewGroup.LayoutParams.WRAP_CONTENT);
		leftRail.setLayoutParams(leftLp);
		root.addView(leftRail);

		rightRail = buildVerticalKeys(ACTIONS_MJ, sideKeyH, sideKeyW, density, gap);
		FrameLayout.LayoutParams rightLp = new FrameLayout.LayoutParams(
				sideKeyW, ViewGroup.LayoutParams.WRAP_CONTENT);
		rightRail.setLayoutParams(rightLp);
		root.addView(rightRail);

		bottomStrip = buildBottomLetterStrip(
				LETTERS_PLAY_LANDSCAPE, LETTERS_MORE_LANDSCAPE,
				keyH, keyMinW, density, gap, true);
		root.addView(bottomStrip);
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

		// 第一行：开始 押注 …… 翻转 投币
		LinearLayout row1 = new LinearLayout(mm);
		row1.setOrientation(LinearLayout.HORIZONTAL);
		row1.setGravity(Gravity.CENTER_VERTICAL);
		row1.addView(makeKeyView(key("开始", KeyEvent.KEYCODE_1, '1'), keyH, keyMinW, density, gap));
		row1.addView(makeKeyView(key("押注", KeyEvent.KEYCODE_3, '3'), keyH, keyMinW, density, gap));
		View spacer = new View(mm);
		spacer.setLayoutParams(new LinearLayout.LayoutParams(0, 1, 1f));
		row1.addView(spacer);
		row1.addView(makeKeyView(key("翻转", KeyEvent.KEYCODE_Y, 'Y'), keyH, keyMinW, density, gap));
		row1.addView(makeKeyView(key("投币", KeyEvent.KEYCODE_5, '5'), keyH, keyMinW, density, gap));
		LinearLayout.LayoutParams r1Lp = new LinearLayout.LayoutParams(
				ViewGroup.LayoutParams.MATCH_PARENT,
				ViewGroup.LayoutParams.WRAP_CONTENT);
		r1Lp.bottomMargin = gap;
		row1.setLayoutParams(r1Lp);
		column.addView(row1);

		// 第二行：打牌 | 吃碰杠听和 | 更多（同高同宽）
		LinearLayout row2 = new LinearLayout(mm);
		row2.setOrientation(LinearLayout.HORIZONTAL);
		row2.setGravity(Gravity.CENTER_VERTICAL);
		tabPlay = makeTabKey("打牌", keyH, density, gap);
		tabMore = makeTabKey("更多", keyH, density, gap);
		tabPlay.setOnClickListener(v -> {
			currentTab = TAB_PLAY;
			applyTab();
		});
		tabMore.setOnClickListener(v -> {
			currentTab = TAB_MORE;
			applyTab();
		});
		row2.addView(tabPlay);
		for (KeySpec spec : ACTIONS_MJ) {
			row2.addView(makeEqualKey(spec, keyH, density, gap));
		}
		row2.addView(tabMore);
		LinearLayout.LayoutParams r2Lp = new LinearLayout.LayoutParams(
				ViewGroup.LayoutParams.MATCH_PARENT,
				ViewGroup.LayoutParams.WRAP_CONTENT);
		r2Lp.bottomMargin = gap;
		row2.setLayoutParams(r2Lp);
		column.addView(row2);

		bottomStrip = buildBottomLetterStrip(
				LETTERS_PLAY_PORTRAIT, LETTERS_MORE_PORTRAIT,
				keyH, keyMinW, density, gap, false);
		column.addView(bottomStrip);

		root.addView(column);
	}

	/**
	 * 底部字母区。
	 * 横屏：打牌 | A…N/更多键 | 更多（与字母同高，分列两端）；竖屏标签已在第二排。
	 */
	private LinearLayout buildBottomLetterStrip(
			KeySpec[][] playRows, KeySpec[][] moreRows,
			int keyH, int keyMinW, float density, int gap, boolean landscape) {
		LinearLayout strip = new LinearLayout(mm);
		strip.setOrientation(LinearLayout.HORIZONTAL);
		strip.setGravity(Gravity.CENTER_VERTICAL);
		strip.setBackgroundColor(Color.TRANSPARENT);

		if (landscape) {
			FrameLayout.LayoutParams stripLp = new FrameLayout.LayoutParams(
					ViewGroup.LayoutParams.MATCH_PARENT,
					ViewGroup.LayoutParams.WRAP_CONTENT,
					Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL);
			stripLp.setMargins(edgePad, 0, edgePad, edgePad);
			strip.setLayoutParams(stripLp);
		} else {
			strip.setLayoutParams(new LinearLayout.LayoutParams(
					ViewGroup.LayoutParams.MATCH_PARENT,
					ViewGroup.LayoutParams.WRAP_CONTENT));
		}

		int letterRows = Math.max(playRows.length, moreRows.length);
		int pageH = letterRows * keyH + Math.max(0, letterRows - 1) * gap;

		if (landscape) {
			tabPlay = makeFlankingTab("打牌", keyH, keyMinW, density, gap);
			tabMore = makeFlankingTab("更多", keyH, keyMinW, density, gap);
			tabPlay.setOnClickListener(v -> {
				currentTab = TAB_PLAY;
				applyTab();
			});
			tabMore.setOnClickListener(v -> {
				currentTab = TAB_MORE;
				applyTab();
			});
			strip.addView(tabPlay);
		}

		FrameLayout pages = new FrameLayout(mm);
		pages.setLayoutParams(new LinearLayout.LayoutParams(0, pageH, 1f));

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

		if (landscape) {
			strip.addView(tabMore);
		}

		return strip;
	}

	/** 横屏底栏两端标签：与字母键同高，便于点按。 */
	private TextView makeFlankingTab(String label, int keyH, int keyMinW, float density, int gap) {
		TextView tab = new TextView(mm);
		tab.setText(label);
		tab.setGravity(Gravity.CENTER);
		tab.setTypeface(Typeface.DEFAULT_BOLD);
		tab.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11);
		tab.setMinWidth(keyMinW);
		tab.setMinHeight(keyH);
		tab.setPadding((int) (8 * density), (int) (4 * density), (int) (8 * density), (int) (4 * density));
		tab.setClickable(true);
		tab.setFocusable(false);
		LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
				ViewGroup.LayoutParams.WRAP_CONTENT, keyH);
		lp.setMargins(gap / 2, 0, gap / 2, 0);
		tab.setLayoutParams(lp);
		return tab;
	}

	/** 竖屏第二排标签：与动作键同尺寸。 */
	private TextView makeTabKey(String label, int keyH, float density, int gap) {
		TextView tab = new TextView(mm);
		tab.setText(label);
		tab.setGravity(Gravity.CENTER);
		tab.setTypeface(Typeface.DEFAULT_BOLD);
		tab.setTextSize(TypedValue.COMPLEX_UNIT_SP, label.length() > 1 ? 11 : 14);
		tab.setMinHeight(keyH);
		tab.setPadding((int) (4 * density), (int) (4 * density), (int) (4 * density), (int) (4 * density));
		tab.setClickable(true);
		tab.setFocusable(false);
		LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
				0, keyH, 1f);
		lp.setMargins(gap / 2, 0, gap / 2, 0);
		tab.setLayoutParams(lp);
		return tab;
	}

	private TextView makeEqualKey(KeySpec spec, int keyH, float density, int gap) {
		TextView key = makeKeyView(spec, keyH, 0, density, gap);
		LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
				0, keyH, 1f);
		lp.setMargins(gap / 2, 0, gap / 2, 0);
		key.setLayoutParams(lp);
		key.setMinWidth(0);
		return key;
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
			bg.setColor(0xB3333333);
			tab.setTextColor(0xFFCCCCCC);
		}
		tab.setBackground(bg);
	}

	private void attachGameFrameListener() {
		View emu = mm.getEmuView();
		if (emu == null) {
			return;
		}
		gameFrameListener = () -> syncToGameFrame();
		emu.getViewTreeObserver().addOnGlobalLayoutListener(gameFrameListener);
		if (panelRoot != null) {
			panelRoot.getViewTreeObserver().addOnGlobalLayoutListener(gameFrameListener);
		}
	}

	private void detachGameFrameListener() {
		View emu = mm.getEmuView();
		if (gameFrameListener != null) {
			if (emu != null && emu.getViewTreeObserver().isAlive()) {
				emu.getViewTreeObserver().removeOnGlobalLayoutListener(gameFrameListener);
			}
			if (panelRoot != null && panelRoot.getViewTreeObserver().isAlive()) {
				panelRoot.getViewTreeObserver().removeOnGlobalLayoutListener(gameFrameListener);
			}
		}
		gameFrameListener = null;
	}

	/** 横屏：常驻键贴游戏画面左右；底栏对齐游戏宽度。 */
	private void syncToGameFrame() {
		if (panelRoot == null || leftRail == null || rightRail == null) {
			return;
		}
		View emu = mm.getEmuView();
		if (emu == null || emu.getWidth() <= 0 || panelRoot.getWidth() <= 0) {
			return;
		}

		int[] emuLoc = new int[2];
		int[] rootLoc = new int[2];
		emu.getLocationOnScreen(emuLoc);
		panelRoot.getLocationOnScreen(rootLoc);
		int emuLeft = emuLoc[0] - rootLoc[0];
		int emuTop = emuLoc[1] - rootLoc[1];
		int emuRight = emuLeft + emu.getWidth();
		int emuBottom = emuTop + emu.getHeight();
		int rootW = panelRoot.getWidth();
		int rootH = panelRoot.getHeight();

		int stripH = bottomStrip != null ? Math.max(bottomStrip.getHeight(), bottomReserve) : bottomReserve;
		int availBottom = Math.min(emuBottom, rootH - stripH - edgePad);
		int availTop = Math.max(0, emuTop);

		layoutRail(leftRail, true, emuLeft, emuRight, rootW, availTop, availBottom);
		layoutRail(rightRail, false, emuLeft, emuRight, rootW, availTop, availBottom);
	}

	private void layoutRail(View rail, boolean leftSide, int emuLeft, int emuRight,
			int rootW, int availTop, int availBottom) {
		rail.measure(
				View.MeasureSpec.makeMeasureSpec(sideKeyW, View.MeasureSpec.EXACTLY),
				View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED));
		int colH = rail.getMeasuredHeight();
		int availH = Math.max(colH, availBottom - availTop);
		int y = availTop + Math.max(0, (availH - colH) / 2);
		if (y + colH > availBottom) {
			y = Math.max(availTop, availBottom - colH);
		}

		int x;
		if (leftSide) {
			// 贴在游戏画面左边外侧；空隙不够则贴画面左缘内侧
			x = emuLeft - sideKeyW - sideGap;
			if (x < edgePad) {
				x = Math.max(edgePad, emuLeft + sideGap);
			}
		} else {
			x = emuRight + sideGap;
			if (x + sideKeyW > rootW - edgePad) {
				x = Math.min(rootW - edgePad - sideKeyW, emuRight - sideKeyW - sideGap);
			}
		}
		x = Math.max(0, Math.min(x, rootW - sideKeyW));

		FrameLayout.LayoutParams lp = (FrameLayout.LayoutParams) rail.getLayoutParams();
		if (lp.leftMargin == x && lp.topMargin == y && lp.width == sideKeyW) {
			return;
		}
		lp.width = sideKeyW;
		lp.height = ViewGroup.LayoutParams.WRAP_CONTENT;
		lp.gravity = Gravity.TOP | Gravity.START;
		lp.leftMargin = x;
		lp.topMargin = y;
		lp.rightMargin = 0;
		lp.bottomMargin = 0;
		rail.setLayoutParams(lp);
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
		if (keyMinW > 0) {
			key.setMinWidth(keyMinW);
		}
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
