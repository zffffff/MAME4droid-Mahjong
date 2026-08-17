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
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

/**
 * Games shown on the custom picker: artwork folders in the mahjong pack + Chinese titles from mame.lst.
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
		Set<String> roms = listArtworkRoms(assets);
		Map<String, String> names = loadMameLst(assets);
		List<Entry> out = new ArrayList<>();
		List<String> sorted = new ArrayList<>(roms);
		Collections.sort(sorted);
		for (String rom : sorted) {
			String title = names.get(rom);
			if (title == null || title.isEmpty()) {
				title = rom;
			}
			out.add(new Entry(rom, title));
		}
		Log.i(TAG, "catalog size=" + out.size());
		return out;
	}

	private static Set<String> listArtworkRoms(AssetManager assets) {
		Set<String> roms = new HashSet<>();
		try {
			String[] names = assets.list("mahjong_pack/artwork");
			if (names != null) {
				for (String n : names) {
					if (n == null || n.isEmpty() || n.contains(".")) {
						continue;
					}
					roms.add(n.toLowerCase(Locale.US));
				}
			}
		} catch (Exception e) {
			Log.w(TAG, "list artwork failed", e);
		}
		return roms;
	}

	private static Map<String, String> loadMameLst(AssetManager assets) {
		Map<String, String> map = new HashMap<>();
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
