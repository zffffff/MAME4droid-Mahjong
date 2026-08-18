package com.seleuco.mame4droid.mahjong;

import android.content.Context;
import android.content.res.AssetManager;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.LinearGradient;
import android.graphics.Paint;
import android.graphics.Shader;
import android.graphics.drawable.BitmapDrawable;
import android.graphics.drawable.Drawable;
import android.util.DisplayMetrics;

import java.io.File;
import java.io.IOException;
import java.io.InputStream;

/**
 * List row art: per-rom hash gradient (base) → custom / snap / flavor {@code _default} (may be translucent).
 */
public final class ListArtLoader {

	private static final String[] ASSET_EXTS = {".webp", ".png", ".jpg", ".jpeg"};
	private static final String[] SNAP_EXTS = {".png", ".jpg", ".jpeg", ".webp"};

	private ListArtLoader() {
	}

	public static Drawable loadRowBackground(Context ctx, String rom, int widthPx, int heightPx) {
		if (widthPx <= 0 || heightPx <= 0) {
			DisplayMetrics dm = ctx.getResources().getDisplayMetrics();
			widthPx = dm.widthPixels;
			heightPx = (int) (80f * dm.density + 0.5f);
		}

		// Always paint a per-rom dark gradient first so translucent _default can show through.
		Bitmap base = makeGradient(widthPx, heightPx, gradientColorsFor(rom));

		Bitmap overlay = decodeAssetBgNamed(ctx.getAssets(), rom, widthPx, heightPx);
		if (overlay == null) {
			overlay = decodeSnap(ctx, rom, widthPx, heightPx);
		}
		if (overlay == null) {
			overlay = decodeAssetBgNamed(ctx.getAssets(), "_default", widthPx, heightPx);
		}
		if (overlay != null) {
			Canvas c = new Canvas(base);
			c.drawBitmap(overlay, 0, 0, null);
			overlay.recycle();
		}

		return new BitmapDrawable(ctx.getResources(), applyLeftFade(base));
	}

	private static Bitmap decodeAssetBgNamed(AssetManager assets, String baseName, int w, int h) {
		for (String ext : ASSET_EXTS) {
			String path = "mahjong_list/bg/" + baseName + ext;
			try (InputStream in = assets.open(path)) {
				return decodeSampled(in, w, h);
			} catch (IOException ignored) {
			}
		}
		return null;
	}

	private static Bitmap decodeSnap(Context ctx, String rom, int w, int h) {
		File snapDir = resolveSnapDir(ctx);
		if (snapDir == null) {
			return null;
		}

		// 1) snap/<rom>.png
		for (String ext : SNAP_EXTS) {
			Bitmap b = decodeFileScaled(new File(snapDir, rom + ext), w, h);
			if (b != null) {
				return b;
			}
		}
		// 2) snap/<rom>/0000.png (MAME title snap folder layout)
		File sub = new File(snapDir, rom);
		if (sub.isDirectory()) {
			for (String name : new String[]{"0000.png", "0000.jpg", "0000.jpeg", "0000.webp"}) {
				Bitmap b = decodeFileScaled(new File(sub, name), w, h);
				if (b != null) {
					return b;
				}
			}
			// Fallback: first image in the folder
			File[] kids = sub.listFiles();
			if (kids != null) {
				for (File f : kids) {
					if (!f.isFile()) {
						continue;
					}
					String n = f.getName().toLowerCase();
					if (n.endsWith(".png") || n.endsWith(".jpg") || n.endsWith(".jpeg") || n.endsWith(".webp")) {
						Bitmap b = decodeFileScaled(f, w, h);
						if (b != null) {
							return b;
						}
					}
				}
			}
		}
		return null;
	}

	private static File resolveSnapDir(Context ctx) {
		String install = null;
		try {
			if (ctx instanceof com.seleuco.mame4droid.MAME4droid) {
				install = ((com.seleuco.mame4droid.MAME4droid) ctx).getMainHelper().getInstallationDIR();
			}
		} catch (Exception ignored) {
		}
		if (install == null || install.isEmpty()) {
			File ext = ctx.getExternalFilesDir(null);
			if (ext != null) {
				install = ext.getAbsolutePath() + "/";
			}
		}
		if (install == null) {
			return null;
		}
		if (!install.endsWith("/")) {
			install += "/";
		}
		return new File(install + "snap");
	}

	private static Bitmap decodeFileScaled(File f, int w, int h) {
		if (f == null || !f.isFile()) {
			return null;
		}
		BitmapFactory.Options bounds = new BitmapFactory.Options();
		bounds.inJustDecodeBounds = true;
		BitmapFactory.decodeFile(f.getAbsolutePath(), bounds);
		if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
			return null;
		}
		BitmapFactory.Options opts = new BitmapFactory.Options();
		opts.inSampleSize = calcInSampleSize(bounds, w, h);
		opts.inPreferredConfig = Bitmap.Config.ARGB_8888;
		Bitmap raw = BitmapFactory.decodeFile(f.getAbsolutePath(), opts);
		if (raw == null) {
			return null;
		}
		return scaleCenterCrop(raw, w, h);
	}

	private static Bitmap decodeSampled(InputStream in, int w, int h) {
		try {
			byte[] data = readAll(in);
			BitmapFactory.Options bounds = new BitmapFactory.Options();
			bounds.inJustDecodeBounds = true;
			BitmapFactory.decodeByteArray(data, 0, data.length, bounds);
			BitmapFactory.Options opts = new BitmapFactory.Options();
			opts.inSampleSize = calcInSampleSize(bounds, w, h);
			opts.inPreferredConfig = Bitmap.Config.ARGB_8888;
			Bitmap raw = BitmapFactory.decodeByteArray(data, 0, data.length, opts);
			if (raw == null) {
				return null;
			}
			return scaleCenterCrop(raw, w, h);
		} catch (IOException e) {
			return null;
		}
	}

	private static byte[] readAll(InputStream in) throws IOException {
		byte[] buf = new byte[16 * 1024];
		java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
		int n;
		while ((n = in.read(buf)) >= 0) {
			out.write(buf, 0, n);
		}
		return out.toByteArray();
	}

	private static int calcInSampleSize(BitmapFactory.Options bounds, int reqW, int reqH) {
		int h = bounds.outHeight;
		int w = bounds.outWidth;
		int inSampleSize = 1;
		if (h > reqH || w > reqW) {
			int halfH = h / 2;
			int halfW = w / 2;
			while ((halfH / inSampleSize) >= reqH && (halfW / inSampleSize) >= reqW) {
				inSampleSize *= 2;
			}
		}
		return Math.max(1, inSampleSize);
	}

	private static Bitmap scaleCenterCrop(Bitmap src, int w, int h) {
		if (src.getWidth() == w && src.getHeight() == h) {
			return src;
		}
		float scale = Math.max((float) w / src.getWidth(), (float) h / src.getHeight());
		int scaledW = Math.round(src.getWidth() * scale);
		int scaledH = Math.round(src.getHeight() * scale);
		Bitmap scaled = Bitmap.createScaledBitmap(src, scaledW, scaledH, true);
		if (scaled != src) {
			src.recycle();
		}
		int x = Math.max(0, (scaledW - w) / 2);
		int y = Math.max(0, (scaledH - h) / 2);
		Bitmap out = Bitmap.createBitmap(scaled, x, y, Math.min(w, scaledW), Math.min(h, scaledH));
		if (out != scaled) {
			scaled.recycle();
		}
		return out;
	}

	/** Strong left veil across ~2/3 width so titles stay readable. */
	private static Bitmap applyLeftFade(Bitmap src) {
		int w = src.getWidth();
		int h = src.getHeight();
		Bitmap out = src.getConfig() == Bitmap.Config.ARGB_8888
				? src
				: src.copy(Bitmap.Config.ARGB_8888, true);
		if (out != src) {
			src.recycle();
		} else if (!out.isMutable()) {
			out = src.copy(Bitmap.Config.ARGB_8888, true);
			src.recycle();
		}
		Canvas c = new Canvas(out);
		Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
		// Higher opacity on the left; fade out through 2/3 of the row.
		p.setShader(new LinearGradient(
				0, 0, w * (2f / 3f), 0,
				0xF00B1218, 0x000B1218,
				Shader.TileMode.CLAMP));
		c.drawRect(0, 0, w, h, p);
		return out;
	}

	private static Bitmap makeGradient(int w, int h, int[] colors) {
		Bitmap bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
		Canvas c = new Canvas(bmp);
		Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
		p.setShader(new LinearGradient(0, 0, w, h, colors[0], colors[1], Shader.TileMode.CLAMP));
		c.drawRect(0, 0, w, h, p);
		return bmp;
	}

	/** Decorative per-rom hues under translucent defaults — not ROM status. */
	private static int[] gradientColorsFor(String rom) {
		int hash = rom == null ? 0 : rom.hashCode();
		int[][] palette = {
				{0xFF1A2A28, 0xFF0B1218},
				{0xFF2A1F18, 0xFF120C08},
				{0xFF1C2430, 0xFF0A0E14},
				{0xFF243018, 0xFF0C1208},
				{0xFF302018, 0xFF140A08},
		};
		return palette[Math.floorMod(hash, palette.length)];
	}
}
