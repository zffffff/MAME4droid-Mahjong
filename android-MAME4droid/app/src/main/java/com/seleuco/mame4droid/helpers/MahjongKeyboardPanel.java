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
	/** 默认键底 alpha（约 70%） */
	private static final int KEY_ALPHA = 0xB3;
	/** 横屏打牌页：高度约 2/3、透明度再降约 1/3 */
	private static final float PLAY_LAND_HEIGHT_FACTOR = 2f / 3f;
	private static final int PLAY_LAND_ALPHA = (int) (KEY_ALPHA * 2f / 3f); // ≈ 0x77
	private static final int PORTRAIT_COLS = 7;

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
	private boolean landscapeMode = false;
	private int currentTab = TAB_PLAY;
	private int sideKeyW;
	private int sideGap;
	private int edgePad;
	private int bottomReserve;
	private int lastStripLeft = Integer.MIN_VALUE;
	private int lastStripWidth = Integer.MIN_VALUE;

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

	private static final KeySpec[] LETTERS_PLAY_LANDSCAPE = {
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
	};

	/** 竖屏更多页：按 7 列对齐 */
	private static final KeySpec[][] LETTERS_MORE_PORTRAIT = {
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
					key("T", KeyEvent.KEYCODE_T, 'T'),
			},
			{
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
		landscapeMode = mm.getResources().getConfiguration().orientation
				== Configuration.ORIENTATION_LANDSCAPE;
		lastStripLeft = Integer.MIN_VALUE;
		lastStripWidth = Integer.MIN_VALUE;

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

		if (landscapeMode) {
			attachLandscape(root, keyH, keyMinW, density, gap);
		} else {
			attachPortrait(root, keyH, density, gap, edge);
		}
		applyTab();

		emulatorFrame.addView(root);
		panelRoot = root;
		root.bringToFront();
		attachGameFrameListener();
		root.post(this::syncToGameFrame);
	}

	private void attachLandscape(FrameLayout root, int keyH, int keyMinW,
			float density, int gap) {
		int sideKeyH = (int) (40 * density);

		leftRail = buildVerticalKeys(ACTIONS_LEFT_LANDSCAPE, sideKeyH, sideKeyW, density, gap);
		leftRail.setLayoutParams(new FrameLayout.LayoutParams(
				sideKeyW, ViewGroup.LayoutParams.WRAP_CONTENT));
		root.addView(leftRail);

		rightRail = buildVerticalKeys(ACTIONS_MJ, sideKeyH, sideKeyW, density, gap);
		rightRail.setLayoutParams(new FrameLayout.LayoutParams(
				sideKeyW, ViewGroup.LayoutParams.WRAP_CONTENT));
		root.addView(rightRail);

		bottomStrip = buildLandscapeLetterStrip(keyH, keyMinW, density, gap);
		root.addView(bottomStrip);
	}

	private void attachPortrait(FrameLayout root, int keyH, float density, int gap, int edge) {
		LinearLayout column = new LinearLayout(mm);
		column.setOrientation(LinearLayout.VERTICAL);
		column.setBackgroundColor(Color.TRANSPARENT);
		// 整体上移约 2 格按键高度
		FrameLayout.LayoutParams colLp = new FrameLayout.LayoutParams(
				ViewGroup.LayoutParams.MATCH_PARENT,
				ViewGroup.LayoutParams.WRAP_CONTENT,
				Gravity.BOTTOM);
		colLp.setMargins(edge, 0, edge, edge + keyH * 2);
		column.setLayoutParams(colLp);

		// 第一行：7 格对齐 —— 开始 押注 … 翻转 投币
		column.addView(buildPortraitSlotRow(new KeySpec[]{
				key("开始", KeyEvent.KEYCODE_1, '1'),
				key("押注", KeyEvent.KEYCODE_3, '3'),
				null, null, null,
				key("翻转", KeyEvent.KEYCODE_Y, 'Y'),
				key("投币", KeyEvent.KEYCODE_5, '5'),
		}, keyH, density, gap));

		// 第二行：打牌 | 吃碰杠听和 | 更多
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
			row2.addView(makeEqualKey(spec, keyH, density, gap, KEY_ALPHA));
		}
		row2.addView(tabMore);
		LinearLayout.LayoutParams r2Lp = new LinearLayout.LayoutParams(
				ViewGroup.LayoutParams.MATCH_PARENT,
				ViewGroup.LayoutParams.WRAP_CONTENT);
		r2Lp.bottomMargin = gap;
		row2.setLayoutParams(r2Lp);
		column.addView(row2);

		int playRows = LETTERS_PLAY_PORTRAIT.length;
		int moreRows = LETTERS_MORE_PORTRAIT.length;
		int pageH = Math.max(playRows, moreRows) * keyH + Math.max(0, Math.max(playRows, moreRows) - 1) * gap;

		FrameLayout pages = new FrameLayout(mm);
		pages.setLayoutParams(new LinearLayout.LayoutParams(
				ViewGroup.LayoutParams.MATCH_PARENT, pageH));

		playLetters = buildPortraitKeyPage(LETTERS_PLAY_PORTRAIT, keyH, density, gap);
		moreLetters = buildPortraitKeyPage(LETTERS_MORE_PORTRAIT, keyH, density, gap);
		FrameLayout.LayoutParams pageLp = new FrameLayout.LayoutParams(
				ViewGroup.LayoutParams.MATCH_PARENT,
				ViewGroup.LayoutParams.MATCH_PARENT);
		playLetters.setLayoutParams(pageLp);
		moreLetters.setLayoutParams(new FrameLayout.LayoutParams(pageLp));
		pages.addView(playLetters);
		pages.addView(moreLetters);
		column.addView(pages);
		bottomStrip = pages;

		root.addView(column);
	}

	/** 竖屏固定 7 列槽位，空位占格以保持整齐。 */
	private LinearLayout buildPortraitSlotRow(KeySpec[] slots, int keyH, float density, int gap) {
		LinearLayout row = new LinearLayout(mm);
		row.setOrientation(LinearLayout.HORIZONTAL);
		row.setGravity(Gravity.CENTER_VERTICAL);
		LinearLayout.LayoutParams rowLp = new LinearLayout.LayoutParams(
				ViewGroup.LayoutParams.MATCH_PARENT,
				ViewGroup.LayoutParams.WRAP_CONTENT);
		rowLp.bottomMargin = gap;
		row.setLayoutParams(rowLp);
		for (KeySpec spec : slots) {
			if (spec == null) {
				View spacer = new View(mm);
				LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, keyH, 1f);
				lp.setMargins(gap / 2, 0, gap / 2, 0);
				spacer.setLayoutParams(lp);
				row.addView(spacer);
			} else {
				row.addView(makeEqualKey(spec, keyH, density, gap, KEY_ALPHA));
			}
		}
		return row;
	}

	private LinearLayout buildPortraitKeyPage(KeySpec[][] rows, int keyH, float density, int gap) {
		LinearLayout column = new LinearLayout(mm);
		column.setOrientation(LinearLayout.VERTICAL);
		for (int r = 0; r < rows.length; r++) {
			KeySpec[] src = rows[r];
			KeySpec[] slots = new KeySpec[PORTRAIT_COLS];
			for (int i = 0; i < PORTRAIT_COLS; i++) {
				slots[i] = i < src.length ? src[i] : null;
			}
			LinearLayout row = buildPortraitSlotRow(slots, keyH, density, gap);
			if (r == rows.length - 1) {
				((LinearLayout.LayoutParams) row.getLayoutParams()).bottomMargin = 0;
			}
			column.addView(row);
		}
		return column;
	}

	/**
	 * 横屏底栏：打牌 | 字母区 | 更多。
	 * 打牌 / 更多 键高与透明度统一（更矮更透）；打牌页等分对齐画面，更多页可横滑。
	 */
	private LinearLayout buildLandscapeLetterStrip(int keyH, int keyMinW, float density, int gap) {
		LinearLayout strip = new LinearLayout(mm);
		strip.setOrientation(LinearLayout.HORIZONTAL);
		strip.setGravity(Gravity.CENTER_VERTICAL);
		strip.setBackgroundColor(Color.TRANSPARENT);
		FrameLayout.LayoutParams stripLp = new FrameLayout.LayoutParams(
				ViewGroup.LayoutParams.MATCH_PARENT,
				ViewGroup.LayoutParams.WRAP_CONTENT,
				Gravity.BOTTOM | Gravity.START);
		stripLp.setMargins(edgePad, 0, edgePad, edgePad);
		strip.setLayoutParams(stripLp);

		int landH = Math.max(1, Math.round(keyH * PLAY_LAND_HEIGHT_FACTOR));

		tabPlay = makeFlankingTab("打牌", landH, keyMinW, density, gap);
		tabMore = makeFlankingTab("更多", landH, keyMinW, density, gap);
		tabPlay.setOnClickListener(v -> {
			currentTab = TAB_PLAY;
			applyTab();
		});
		tabMore.setOnClickListener(v -> {
			currentTab = TAB_MORE;
			applyTab();
		});
		strip.addView(tabPlay);

		FrameLayout pages = new FrameLayout(mm);
		pages.setLayoutParams(new LinearLayout.LayoutParams(0, landH, 1f));

		playLetters = buildLandscapePlayRow(LETTERS_PLAY_LANDSCAPE, landH, density, gap);
		moreLetters = buildScrollKeyPage(LETTERS_MORE_LANDSCAPE, landH, keyMinW, density, gap,
				PLAY_LAND_ALPHA);
		FrameLayout.LayoutParams pageLp = new FrameLayout.LayoutParams(
				ViewGroup.LayoutParams.MATCH_PARENT,
				ViewGroup.LayoutParams.MATCH_PARENT);
		playLetters.setLayoutParams(pageLp);
		moreLetters.setLayoutParams(new FrameLayout.LayoutParams(pageLp));
		pages.addView(playLetters);
		pages.addView(moreLetters);
		strip.addView(pages);
		strip.addView(tabMore);

		return strip;
	}

	private LinearLayout buildLandscapePlayRow(KeySpec[] keys, int keyH, float density, int gap) {
		LinearLayout row = new LinearLayout(mm);
		row.setOrientation(LinearLayout.HORIZONTAL);
		row.setGravity(Gravity.CENTER_VERTICAL);
		for (KeySpec spec : keys) {
			row.addView(makeEqualKey(spec, keyH, density, gap, PLAY_LAND_ALPHA));
		}
		return row;
	}

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
		LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, keyH, 1f);
		lp.setMargins(gap / 2, 0, gap / 2, 0);
		tab.setLayoutParams(lp);
		return tab;
	}

	private TextView makeEqualKey(KeySpec spec, int keyH, float density, int gap, int alpha) {
		TextView key = makeKeyView(spec, keyH, 0, density, gap, alpha);
		LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, keyH, 1f);
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
		if (landscapeMode) {
			syncToGameFrame();
		}
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

	/** 横屏：常驻键贴游戏画面左右；打牌页底栏对齐游戏宽度。 */
	private void syncToGameFrame() {
		if (panelRoot == null || !landscapeMode) {
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

		if (leftRail != null && rightRail != null) {
			int stripH = bottomStrip != null ? Math.max(bottomStrip.getHeight(), bottomReserve) : bottomReserve;
			int availBottom = Math.min(emuBottom, rootH - stripH - edgePad);
			int availTop = Math.max(0, emuTop);
			layoutRail(leftRail, true, emuLeft, emuRight, rootW, availTop, availBottom);
			layoutRail(rightRail, false, emuLeft, emuRight, rootW, availTop, availBottom);
		}

		if (bottomStrip != null) {
			FrameLayout.LayoutParams lp = (FrameLayout.LayoutParams) bottomStrip.getLayoutParams();
			int left;
			int width;
			if (currentTab == TAB_PLAY) {
				left = Math.max(0, emuLeft);
				width = Math.max(sideKeyW * 2, emu.getWidth());
				if (left + width > rootW) {
					width = rootW - left;
				}
			} else {
				left = edgePad;
				width = Math.max(0, rootW - edgePad * 2);
			}
			if (left == lastStripLeft && width == lastStripWidth) {
				return;
			}
			lastStripLeft = left;
			lastStripWidth = width;
			lp.width = width;
			lp.height = ViewGroup.LayoutParams.WRAP_CONTENT;
			lp.gravity = Gravity.BOTTOM | Gravity.START;
			lp.leftMargin = left;
			lp.rightMargin = 0;
			lp.topMargin = 0;
			lp.bottomMargin = edgePad;
			bottomStrip.setLayoutParams(lp);
		}
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
			TextView key = makeKeyView(specs[i], keyH, keyMinW, density, gap, KEY_ALPHA);
			LinearLayout.LayoutParams lp = (LinearLayout.LayoutParams) key.getLayoutParams();
			lp.setMargins(0, i == 0 ? 0 : gap / 2, 0, gap / 2);
			lp.width = keyMinW;
			key.setLayoutParams(lp);
			col.addView(key);
		}
		return col;
	}

	private LinearLayout buildScrollKeyPage(KeySpec[][] rows, int keyH, int keyMinW,
			float density, int gap, int alpha) {
		LinearLayout column = new LinearLayout(mm);
		column.setOrientation(LinearLayout.VERTICAL);
		column.setGravity(Gravity.CENTER_VERTICAL);

		for (int r = 0; r < rows.length; r++) {
			HorizontalScrollView scroll = new HorizontalScrollView(mm);
			scroll.setHorizontalScrollBarEnabled(false);
			scroll.setFillViewport(true);
			scroll.setOverScrollMode(View.OVER_SCROLL_IF_CONTENT_SCROLLS);

			LinearLayout rowLayout = new LinearLayout(mm);
			rowLayout.setOrientation(LinearLayout.HORIZONTAL);
			rowLayout.setGravity(Gravity.CENTER);
			for (KeySpec spec : rows[r]) {
				rowLayout.addView(makeKeyView(spec, keyH, keyMinW, density, gap, alpha));
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

	private TextView makeKeyView(KeySpec spec, int keyH, int keyMinW, float density, int gap,
			int alpha) {
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
		int padV = Math.max((int) (2 * density), keyH / 8);
		key.setPadding((int) (6 * density), padV, (int) (6 * density), padV);
		final int idleColor = (alpha << 24) | 0x00333333;
		final int pressedColor = (Math.min(0xFF, alpha + 0x30) << 24) | 0x00666666;
		GradientDrawable keyBg = new GradientDrawable();
		keyBg.setColor(idleColor);
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
				keyBg.setColor(pressedColor);
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
				keyBg.setColor(idleColor);
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
