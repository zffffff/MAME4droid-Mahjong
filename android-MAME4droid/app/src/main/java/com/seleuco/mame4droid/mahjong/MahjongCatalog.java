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
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

/**
 * Picker catalog from {@code mame.lst}. Parents = artwork folder names; other lst entries
 * are grouped as clones under the longest matching parent prefix.
 */
public final class MahjongCatalog {

	private static final String TAG = "MahjongCatalog";

	public static final class Entry {
		public final String rom;
		public final String title;
		/** Parent short name for grouping; equals {@link #rom} when this row is the parent. */
		public final String groupKey;
		public final boolean clone;

		public Entry(String rom, String title, String groupKey, boolean clone) {
			this.rom = rom;
			this.title = title;
			this.groupKey = groupKey;
			this.clone = clone;
		}
	}

	private MahjongCatalog() {
	}

	public static List<Entry> load(Context ctx) {
		AssetManager assets = ctx.getAssets();
		Map<String, String> names = loadMameLst(assets);
		Set<String> parents = listArtworkRoms(assets);

		List<Entry> out = new ArrayList<>();
		if (names.isEmpty()) {
			for (String rom : parents) {
				out.add(new Entry(rom, rom, rom, false));
			}
		} else {
			for (Map.Entry<String, String> e : names.entrySet()) {
				String rom = e.getKey();
				String title = e.getValue();
				String group = resolveGroup(rom, parents);
				boolean clone = !rom.equals(group);
				out.add(new Entry(rom, title, group, clone));
			}
		}

		// Parent first within group; groups by parent title then rom.
		Map<String, String> groupTitle = new LinkedHashMap<>();
		for (Entry e : out) {
			if (!e.clone) {
				groupTitle.put(e.groupKey, e.title);
			}
		}
		for (Entry e : out) {
			if (!groupTitle.containsKey(e.groupKey)) {
				String t = names.get(e.groupKey);
				groupTitle.put(e.groupKey, t != null ? t : e.groupKey);
			}
		}

		Collections.sort(out, (a, b) -> {
			String ta = groupTitle.get(a.groupKey);
			String tb = groupTitle.get(b.groupKey);
			if (ta == null) ta = a.groupKey;
			if (tb == null) tb = b.groupKey;
			int c = ta.compareToIgnoreCase(tb);
			if (c != 0) {
				return c;
			}
			c = a.groupKey.compareTo(b.groupKey);
			if (c != 0) {
				return c;
			}
			if (a.clone != b.clone) {
				return a.clone ? 1 : -1;
			}
			return a.title.compareToIgnoreCase(b.title);
		});

		Log.i(TAG, "catalog size=" + out.size() + " parents=" + parents.size());
		return out;
	}

	/**
	 * Prefer exact artwork folder as parent; else longest artwork name that is a prefix of rom.
	 */
	private static String resolveGroup(String rom, Set<String> parents) {
		if (parents.contains(rom)) {
			return rom;
		}
		String best = null;
		for (String p : parents) {
			if (rom.startsWith(p) && (best == null || p.length() > best.length())) {
				best = p;
			}
		}
		return best != null ? best : rom;
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
