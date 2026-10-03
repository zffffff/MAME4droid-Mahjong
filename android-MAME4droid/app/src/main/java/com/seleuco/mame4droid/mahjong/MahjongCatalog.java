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
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * Picker catalog: titles from {@code mame.lst}, grouping from {@code mahjong_list/groups.txt}.
 * List order follows mame.lst (parent first, clones under it).
 */
public final class MahjongCatalog {

	private static final String TAG = "MahjongCatalog";

	public static final class Entry {
		public final String rom;
		public final String title;
		public final String groupKey;
		public final boolean clone;
		final int lstIndex;

		public Entry(String rom, String title, String groupKey, boolean clone, int lstIndex) {
			this.rom = rom;
			this.title = title;
			this.groupKey = groupKey;
			this.clone = clone;
			this.lstIndex = lstIndex;
		}
	}

	private MahjongCatalog() {
	}

	public static List<Entry> load(Context ctx) {
		AssetManager assets = ctx.getAssets();
		Map<String, String> names = loadMap(assets, "mahjong_pack/mame.lst", false);
		Map<String, String> groups = loadMap(assets, "mahjong_list/groups.txt", true);

		List<Entry> out = new ArrayList<>();
		int i = 0;
		for (Map.Entry<String, String> e : names.entrySet()) {
			String rom = e.getKey();
			String title = e.getValue();
			String group = groups.get(rom);
			if (group == null || group.isEmpty()) {
				group = rom;
			}
			out.add(new Entry(rom, title, group, !rom.equals(group), i++));
		}

		Map<String, Integer> groupOrder = new HashMap<>();
		for (Entry e : out) {
			if (!e.clone) {
				groupOrder.putIfAbsent(e.groupKey, e.lstIndex);
			}
		}
		for (Entry e : out) {
			groupOrder.putIfAbsent(e.groupKey, e.lstIndex);
		}

		Collections.sort(out, (a, b) -> {
			int ga = groupOrder.getOrDefault(a.groupKey, a.lstIndex);
			int gb = groupOrder.getOrDefault(b.groupKey, b.lstIndex);
			if (ga != gb) {
				return Integer.compare(ga, gb);
			}
			if (a.clone != b.clone) {
				return a.clone ? 1 : -1;
			}
			return Integer.compare(a.lstIndex, b.lstIndex);
		});

		Log.i(TAG, "catalog size=" + out.size());
		return out;
	}

	/** Key is always lowercased. Value lowercased only when {@code lowerValue}. */
	private static Map<String, String> loadMap(AssetManager assets, String path, boolean lowerValue) {
		Map<String, String> map = new LinkedHashMap<>();
		try (InputStream in = assets.open(path);
			 BufferedReader br = new BufferedReader(new InputStreamReader(in, StandardCharsets.UTF_8))) {
			String line;
			while ((line = br.readLine()) != null) {
				if (!line.isEmpty() && line.charAt(0) == '\uFEFF') {
					line = line.substring(1);
				}
				line = line.trim();
				if (line.isEmpty() || line.startsWith("#")) {
					continue;
				}
				String key;
				String val;
				int tab = line.indexOf('\t');
				if (tab > 0) {
					key = line.substring(0, tab).trim();
					val = line.substring(tab + 1).trim();
					int tab2 = val.indexOf('\t');
					if (tab2 >= 0) {
						val = val.substring(0, tab2).trim();
					}
				} else {
					String[] parts = line.split("\\s+", 2);
					if (parts.length < 2) {
						continue;
					}
					key = parts[0].trim();
					val = parts[1].trim();
				}
				if (key.isEmpty() || val.isEmpty()) {
					continue;
				}
				key = key.toLowerCase(Locale.US);
				if (lowerValue) {
					val = val.toLowerCase(Locale.US);
				}
				map.put(key, val);
			}
		} catch (Exception e) {
			Log.w(TAG, "read failed: " + path, e);
		}
		return map;
	}
}
