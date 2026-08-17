package com.seleuco.mame4droid.mahjong;

import android.content.Context;
import android.content.res.AssetManager;
import android.util.Log;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * Picker catalog: every rom in pack {@code mame.lst} (parents + clones), with Chinese titles.
 * Artwork folders alone are not enough — many playable sets are clones without their own lay folder.
 */
public final class MahjongCatalog {

	private static final String TAG = "MahjongCatalog";

	public static final class Entry {
		public final String rom;
		public final String title;

		public Entry(String rom, String title) {
			this.rom = rom;
			this.title = title;
		}
	}

	private MahjongCatalog() {
	}

	public static List<Entry> load(Context ctx) {
		AssetManager assets = ctx.getAssets();
		Map<String, String> names = loadMameLst(assets);
		List<Entry> out = new ArrayList<>();
		if (!names.isEmpty()) {
			for (Map.Entry<String, String> e : names.entrySet()) {
				out.add(new Entry(e.getKey(), e.getValue()));
			}
		} else {
			// Fallback if lst missing: artwork folders only.
			try {
				String[] dirs = assets.list("mahjong_pack/artwork");
				if (dirs != null) {
					for (String n : dirs) {
						if (n == null || n.isEmpty() || n.contains(".")) {
							continue;
						}
						String rom = n.toLowerCase(Locale.US);
						out.add(new Entry(rom, rom));
					}
				}
			} catch (Exception e) {
				Log.w(TAG, "list artwork failed", e);
			}
		}
		Collections.sort(out, Comparator.comparing((Entry e) -> e.title)
				.thenComparing(e -> e.rom));
		Log.i(TAG, "catalog size=" + out.size());
		return out;
	}

	/** Preserve file order from mame.lst (LinkedHashMap). */
	private static Map<String, String> loadMameLst(AssetManager assets) {
		Map<String, String> map = new LinkedHashMap<>();
		try (InputStream in = assets.open("mahjong_pack/mame.lst");
			 BufferedReader br = new BufferedReader(new InputStreamReader(in, StandardCharsets.UTF_8))) {
			String line;
			while ((line = br.readLine()) != null) {
				line = line.trim();
				if (line.isEmpty() || line.startsWith("#")) {
					continue;
				}
				String rom;
				String title;
				int tab = line.indexOf('\t');
				if (tab > 0) {
					rom = line.substring(0, tab).trim();
					title = line.substring(tab + 1).trim();
				} else {
					String[] parts = line.split("\\s+", 2);
					if (parts.length < 2) {
						continue;
					}
					rom = parts[0].trim();
					title = parts[1].trim();
				}
				if (!rom.isEmpty() && !title.isEmpty()) {
					map.put(rom.toLowerCase(Locale.US), title);
				}
			}
		} catch (Exception e) {
			Log.w(TAG, "mame.lst read failed", e);
		}
		return map;
	}
}
