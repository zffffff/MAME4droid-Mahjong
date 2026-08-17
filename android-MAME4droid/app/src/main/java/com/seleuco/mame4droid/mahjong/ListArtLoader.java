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
 * List row art: custom assets → snap → brand gradient.
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

		Bitmap bmp = decodeAssetBg(ctx.getAssets(), rom, widthPx, heightPx);
		if (bmp == null) {
			bmp = decodeSnap(ctx, rom, widthPx, heightPx);
		}
		if (bmp == null) {
			// Flavor-specific default: src/full|basic/assets/mahjong_list/bg/_default.webp
			bmp = decodeAssetBgNamed(ctx.getAssets(), "_default", widthPx, heightPx);
		}
		if (bmp == null) {
			// Last resort only — hash palette is decorative, NOT rom working status.
			bmp = makeGradient(widthPx, heightPx, gradientColorsFor(rom));
		} else {
			bmp = applyLeftFade(bmp);
		}
		return new BitmapDrawable(ctx.getResources(), bmp);
	}

	private static Bitmap decodeAssetBg(AssetManager assets, String rom, int w, int h) {
		return decodeAssetBgNamed(assets, rom, w, h);
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
		String install = null;
		try {
			// Prefer live install dir when Activity is MAME4droid; picker may pass files dir.
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
		File snapDir = new File(install + "snap");
		for (String ext : SNAP_EXTS) {
			File f = new File(snapDir, rom + ext);
			if (!f.isFile()) {
				continue;
			}
			BitmapFactory.Options bounds = new BitmapFactory.Options();
			bounds.inJustDecodeBounds = true;
			BitmapFactory.decodeFile(f.getAbsolutePath(), bounds);
			BitmapFactory.Options opts = new BitmapFactory.Options();
			opts.inSampleSize = calcInSampleSize(bounds, w, h);
			opts.inPreferredConfig = Bitmap.Config.RGB_565;
			Bitmap raw = BitmapFactory.decodeFile(f.getAbsolutePath(), opts);
			if (raw != null) {
				return scaleCenterCrop(raw, w, h);
			}
		}
		return null;
	}

	private static Bitmap decodeSampled(InputStream in, int w, int h) {
		try {
			byte[] data = readAll(in);
			BitmapFactory.Options bounds = new BitmapFactory.Options();
			bounds.inJustDecodeBounds = true;
			BitmapFactory.decodeByteArray(data, 0, data.length, bounds);
			BitmapFactory.Options opts = new BitmapFactory.Options();
			opts.inSampleSize = calcInSampleSize(bounds, w, h);
			opts.inPreferredConfig = Bitmap.Config.RGB_565;
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

	/** Darken left ~55% so title stays readable. */
	private static Bitmap applyLeftFade(Bitmap src) {
		int w = src.getWidth();
		int h = src.getHeight();
		Bitmap out = src.copy(Bitmap.Config.ARGB_8888, true);
		src.recycle();
		Canvas c = new Canvas(out);
		Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
		p.setShader(new LinearGradient(
				0, 0, w * 0.62f, 0,
				0xCC0B1218, 0x000B1218,
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

	/** Stable per-rom brand hues (ink / lacquer, avoid purple defaults). */
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
