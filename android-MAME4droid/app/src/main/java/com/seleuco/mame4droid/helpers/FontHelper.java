/*
 * This file is part of MAME4droid.
 *
 * Copyright (C) 2026 David Valdeita (Seleuco)
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, see <http://www.gnu.org/licenses>.
 *
 * Linking MAME4droid statically or dynamically with other modules is
 * making a combined work based on MAME4droid. Thus, the terms and
 * conditions of the GNU General Public License cover the whole
 * combination.
 *
 * In addition, as a special exception, the copyright holders of MAME4droid
 * give you permission to combine MAME4droid with free software programs
 * or libraries that are released under the GNU LGPL and with code included
 * in the standard release of MAME under the MAME License (or modified
 * versions of such code, with unchanged license). You may copy and
 * distribute such a system following the terms of the GNU GPL for MAME4droid
 * and the licenses of the other code concerned, provided that you include
 * the source code of that other code when and as the GNU GPL requires
 * distribution of source code.
 *
 * Note that people who make modified versions of MAME4idroid are not
 * obligated to grant this special exception for their modified versions; it
 * is their choice whether to do so. The GNU General Public License
 * gives permission to release a modified version without this exception;
 * this exception also makes it possible to release a modified version
 * which carries forward this exception.
 *
 * MAME4droid is dual-licensed: Alternatively, you can license MAME4droid
 * under a MAME license, as set out in http://mamedev.org/
 */

package com.seleuco.mame4droid.helpers;

import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Rect;

/**
 * Renders single glyphs with the Android font stack for the native OSD
 * font provider (myosd_font.cpp). Used for characters stb_truetype cannot
 * extract from the system font files: CFF2 variable fonts (NotoSansCJK on
 * Android 15+), color emoji, and any future format the platform adopts.
 */
public class FontHelper {

	/**
	 * Called from native code (mame4droid-jni) on the emulation thread.
	 *
	 * @param codepoint  unicode codepoint to render
	 * @param textSize   em size in pixels (matches the native rasterizer)
	 * @param cellHeight full line box height of the returned bitmap
	 * @param baseline   baseline row inside the cell
	 * @return {width, height, advance, xoffs, width*height ARGB pixels},
	 *         or null if no system font covers the codepoint
	 */
	static public int[] renderFontChar(int codepoint, int textSize, int cellHeight, int baseline) {

		String str = new String(Character.toChars(codepoint));

		Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
		p.setTextSize(textSize);
		p.setARGB(255, 255, 255, 255);

		if (!p.hasGlyph(str))
			return null;

		Rect bounds = new Rect();
		p.getTextBounds(str, 0, str.length(), bounds);
		int advance = Math.round(p.measureText(str));
		if (advance <= 0 && bounds.width() <= 0)
			return null;

		//full cell height with the glyph on the baseline; blank glyphs
		//(spaces) still return a valid transparent bitmap so the advance
		//is not lost
		int w = Math.max(bounds.width(), 1);
		Bitmap bmp = Bitmap.createBitmap(w, cellHeight, Bitmap.Config.ARGB_8888);
		Canvas c = new Canvas(bmp);
		c.drawText(str, -bounds.left, baseline, p);

		int[] out = new int[4 + w * cellHeight];
		out[0] = w;
		out[1] = cellHeight;
		out[2] = advance;
		out[3] = bounds.left;
		bmp.getPixels(out, 4, w, 0, 0, w, cellHeight);
		bmp.recycle();
		return out;
	}
}
