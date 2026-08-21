package com.seleuco.mame4droid.mahjong;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.Uri;
import android.os.Bundle;
import android.preference.PreferenceManager;
import android.text.Editable;
import android.text.TextWatcher;
import android.util.DisplayMetrics;
import android.util.Log;
import android.view.MenuItem;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.widget.BaseAdapter;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.ListView;
import android.widget.PopupMenu;
import android.widget.TextView;
import android.widget.Toast;

import com.seleuco.mame4droid.MAME4droid;
import com.seleuco.mame4droid.R;
import com.seleuco.mame4droid.helpers.PrefsHelper;

import java.io.File;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

/**
 * Full-edition mahjong game picker (LAUNCHER). Basic edition uses stock
 * {@link MAME4droid} as home and does not open this activity.
 */
public class GamePickerActivity extends Activity {

	public static final String EXTRA_ROM = "feijuchang_rom";
	public static final String EXTRA_FROM_PICKER = "feijuchang_from_picker";
	/** @deprecated Full edition no longer offers classic UI; kept for old intents. */
	@Deprecated
	public static final String EXTRA_CLASSIC_UI = "feijuchang_classic_ui";

	private static final int MENU_ROM = 1;
	private static final int MENU_SNAP = 2;
	private static final int MENU_COMPACT = 3;
	private static final int MENU_SETTINGS = 4;
	private static final int MENU_HELP = 5;
	private static final int REQ_ROMS = 33;
	private static final int REQ_SNAP = 34;
	private static final int SETUP_HIDDEN = 0;
	private static final int SETUP_ROM = 1;
	private static final int SETUP_SNAP = 2;
	private static final int RECENT_MAX = 3;
	private static final int ROW_COMFORT_DP = 80;
	private static final int ROW_COMPACT_DP = 56;
	private static final String PREF_RECENT = "fj_picker_recent";
	private static final String PREF_LAST = "fj_picker_last";
	private static final String PREF_SETUP_DONE = "fj_picker_setup_done";
	private static final String PREF_COMPACT = "fj_picker_compact";
	private static final String TAG = "GamePicker";

	private final List<MahjongCatalog.Entry> all = new ArrayList<>();
	private final Map<String, MahjongCatalog.Entry> byRom = new HashMap<>();
	private final Set<String> recentSet = new HashSet<>();
	private final List<Row> shown = new ArrayList<>();
	private RowAdapter adapter;
	private TextView emptyHint;
	private EditText searchBox;
	private ListView list;
	private View setupPanel;
	private TextView setupTitle;
	private TextView setupBody;
	private TextView setupPrimary;
	private TextView setupSkip;
	private View launchVeil;
	private SharedPreferences prefs;
	private Set<String> presentRoms;
	private boolean scanDone;
	private int scanGen;
	private int setupStep = SETUP_HIDDEN;
	private String pendingScrollRom;
	private String query = "";

	@Override
	protected void onCreate(Bundle savedInstanceState) {
		super.onCreate(savedInstanceState);
		getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
		setContentView(R.layout.activity_game_picker);

		prefs = PreferenceManager.getDefaultSharedPreferences(getApplicationContext());

		TextView brand = findViewById(R.id.picker_brand);
		brand.setText(getString(R.string.app_name));

		emptyHint = findViewById(R.id.picker_empty);
		searchBox = findViewById(R.id.picker_search);
		list = findViewById(R.id.picker_list);
		setupPanel = findViewById(R.id.picker_setup);
		setupTitle = findViewById(R.id.picker_setup_title);
		setupBody = findViewById(R.id.picker_setup_body);
		setupPrimary = findViewById(R.id.picker_setup_primary);
		setupSkip = findViewById(R.id.picker_setup_skip);
		launchVeil = findViewById(R.id.picker_launch_veil);

		adapter = new RowAdapter();
		list.setAdapter(adapter);
		list.setOnItemClickListener((parent, view, position, id) -> {
			Row row = shown.get(position);
			if (row.entry != null) {
				onGameClicked(row.entry);
			}
		});

		searchBox.addTextChangedListener(new TextWatcher() {
			@Override
			public void beforeTextChanged(CharSequence s, int start, int count, int after) {
			}

			@Override
			public void onTextChanged(CharSequence s, int start, int before, int count) {
				query = s == null ? "" : s.toString();
				rebuildRows();
			}

			@Override
			public void afterTextChanged(Editable s) {
			}
		});

		findViewById(R.id.picker_menu_btn).setOnClickListener(this::showOverflowMenu);
		setupPrimary.setOnClickListener(v -> {
			if (setupStep == SETUP_ROM) {
				openTree(REQ_ROMS);
			} else if (setupStep == SETUP_SNAP) {
				openTree(REQ_SNAP);
			}
		});
		setupSkip.setOnClickListener(v -> finishSetup());

		all.clear();
		all.addAll(MahjongCatalog.load(this));
		byRom.clear();
		for (MahjongCatalog.Entry e : all) {
			byRom.put(e.rom, e);
		}

		if (!hasRomFolder()) {
			setupStep = SETUP_ROM;
		} else if (!prefs.getBoolean(PREF_SETUP_DONE, false)) {
			prefs.edit().putBoolean(PREF_SETUP_DONE, true).apply();
		}
		persistInstallDirIfNeeded();
		applySetupUi();
		rebuildRows();
	}

	@Override
	protected void onResume() {
		super.onResume();
		hideLaunchVeil();
		if (pendingScrollRom != null) {
			rebuildRows();
		} else if (adapter != null) {
			adapter.notifyDataSetChanged();
		}
		if (hasRomFolder()) {
			scanPresentRoms();
		}
		maybeScrollToLast();
	}

	private void showOverflowMenu(View anchor) {
		PopupMenu pm = new PopupMenu(this, anchor);
		pm.getMenu().add(0, MENU_ROM, 0, R.string.picker_btn_rom);
		pm.getMenu().add(0, MENU_SNAP, 1, R.string.picker_btn_snap);
		MenuItem compact = pm.getMenu().add(0, MENU_COMPACT, 2, R.string.picker_btn_compact);
		compact.setCheckable(true);
		compact.setChecked(isCompact());
		pm.getMenu().add(0, MENU_SETTINGS, 3, R.string.picker_btn_settings);
		pm.getMenu().add(0, MENU_HELP, 4, R.string.picker_btn_help);
		pm.setOnMenuItemClickListener(item -> {
			int id = item.getItemId();
			if (id == MENU_ROM) {
				openTree(REQ_ROMS);
				return true;
			}
			if (id == MENU_SNAP) {
				openTree(REQ_SNAP);
				return true;
			}
			if (id == MENU_COMPACT) {
				prefs.edit().putBoolean(PREF_COMPACT, !isCompact()).apply();
				list.invalidateViews();
				return true;
			}
			if (id == MENU_SETTINGS) {
				startActivity(new Intent(this, com.seleuco.mame4droid.prefs.UserPreferences.class));
				return true;
			}
			if (id == MENU_HELP) {
				openHelp();
				return true;
			}
			return false;
		});
		pm.show();
	}

	private void openTree(int requestCode) {
		try {
			Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE);
			startActivityForResult(intent, requestCode);
		} catch (ActivityNotFoundException e) {
			Toast.makeText(this, R.string.dlg_no_doc_picker, Toast.LENGTH_LONG).show();
		}
	}

	private boolean hasRomFolder() {
		String dir = prefs.getString(PrefsHelper.PREF_ROMsDIR, null);
		return dir != null && !dir.isEmpty();
	}

	/**
	 * MAME4droid shows the ROM-folder dialog when {@code PREF_INSTALLATION_DIR} is
	 * still null. Picker used to clear that pref; persist the same default path
	 * the emulator would compute so classic UI does not ask again.
	 */
	private void persistInstallDirIfNeeded() {
		if (prefs.getString(PrefsHelper.PREF_INSTALLATION_DIR, null) != null) {
			return;
		}
		File ext = getExternalFilesDir(null);
		String dir = (ext != null ? ext.getAbsolutePath() : getFilesDir().getAbsolutePath()) + "/";
		prefs.edit().putString(PrefsHelper.PREF_INSTALLATION_DIR, dir).apply();
	}

	private boolean isCompact() {
		return prefs.getBoolean(PREF_COMPACT, false);
	}

	private int rowHeightPx() {
		float density = getResources().getDisplayMetrics().density;
		int dp = isCompact() ? ROW_COMPACT_DP : ROW_COMFORT_DP;
		return (int) (dp * density + 0.5f);
	}

	private void openHelp() {
		Intent i = new Intent(this, com.seleuco.mame4droid.WebHelpActivity.class);
		String path = prefs.getString(PrefsHelper.PREF_INSTALLATION_DIR, null);
		if (path == null) {
			File ext = getExternalFilesDir(null);
			path = (ext != null ? ext.getAbsolutePath() : getFilesDir().getAbsolutePath()) + "/";
		}
		i.putExtra("INSTALLATION_PATH", path);
		startActivity(i);
	}

	private void startWithVeil(Intent i) {
		if (launchVeil == null) {
			startActivity(i);
			return;
		}
		launchVeil.setVisibility(View.VISIBLE);
		launchVeil.setAlpha(0f);
		launchVeil.animate().cancel();
		launchVeil.animate().alpha(1f).setDuration(180).withEndAction(() -> startActivity(i));
	}

	private void hideLaunchVeil() {
		if (launchVeil == null) {
			return;
		}
		launchVeil.animate().cancel();
		launchVeil.setVisibility(View.GONE);
		launchVeil.setAlpha(0f);
	}

	private void applySetupUi() {
		boolean setup = setupStep != SETUP_HIDDEN;
		searchBox.setVisibility(setup ? View.GONE : View.VISIBLE);
		list.setVisibility(setup ? View.GONE : View.VISIBLE);
		setupPanel.setVisibility(setup ? View.VISIBLE : View.GONE);
		if (setupStep == SETUP_ROM) {
			setupTitle.setText(R.string.picker_setup_rom_title);
			setupBody.setText(R.string.picker_setup_rom_body);
			setupPrimary.setText(R.string.picker_setup_rom_btn);
			setupSkip.setVisibility(View.GONE);
		} else if (setupStep == SETUP_SNAP) {
			setupTitle.setText(R.string.picker_setup_snap_title);
			setupBody.setText(R.string.picker_setup_snap_body);
			setupPrimary.setText(R.string.picker_setup_snap_btn);
			setupSkip.setText(R.string.picker_setup_snap_skip);
			setupSkip.setVisibility(View.VISIBLE);
		}
		updateEmptyHint();
	}

	private void finishSetup() {
		setupStep = SETUP_HIDDEN;
		prefs.edit().putBoolean(PREF_SETUP_DONE, true).apply();
		applySetupUi();
		rebuildRows();
	}

	private void rebuildRows() {
		shown.clear();
		String needle = query.trim().toLowerCase(Locale.ROOT);
		List<MahjongCatalog.Entry> matched = new ArrayList<>();
		for (MahjongCatalog.Entry e : all) {
			if (needle.isEmpty()
					|| e.rom.contains(needle)
					|| e.title.toLowerCase(Locale.ROOT).contains(needle)) {
				matched.add(e);
			}
		}

		recentSet.clear();
		if (needle.isEmpty()) {
			List<MahjongCatalog.Entry> recents = resolveRecents();
			for (MahjongCatalog.Entry e : recents) {
				recentSet.add(e.rom);
			}
			if (!recents.isEmpty()) {
				shown.add(Row.header(getString(R.string.picker_section_recent)));
				for (MahjongCatalog.Entry e : recents) {
					shown.add(Row.game(e, true));
				}
				shown.add(Row.header(getString(R.string.picker_section_all)));
			}
		} else {
			recentSet.addAll(loadRecentRoms());
		}
		for (MahjongCatalog.Entry e : matched) {
			shown.add(Row.game(e, false));
		}

		adapter.notifyDataSetChanged();
		updateEmptyHint();
	}

	private void updateEmptyHint() {
		if (setupStep != SETUP_HIDDEN) {
			emptyHint.setVisibility(View.GONE);
			return;
		}
		if (all.isEmpty()) {
			emptyHint.setVisibility(View.VISIBLE);
			emptyHint.setText(R.string.picker_empty_catalog);
		} else if (shown.isEmpty() || onlyHeaders()) {
			emptyHint.setVisibility(View.VISIBLE);
			emptyHint.setText(R.string.picker_no_match);
		} else if (!hasRomFolder()) {
			emptyHint.setVisibility(View.VISIBLE);
			emptyHint.setText(R.string.picker_need_rom_folder);
		} else {
			emptyHint.setVisibility(View.GONE);
		}
	}

	private boolean onlyHeaders() {
		for (Row r : shown) {
			if (r.entry != null) {
				return false;
			}
		}
		return !shown.isEmpty();
	}

	private List<MahjongCatalog.Entry> resolveRecents() {
		List<MahjongCatalog.Entry> out = new ArrayList<>();
		for (String rom : loadRecentRoms()) {
			MahjongCatalog.Entry e = byRom.get(rom);
			if (e != null) {
				out.add(e);
			}
		}
		return out;
	}

	private List<String> loadRecentRoms() {
		List<String> out = new ArrayList<>();
		String raw = prefs.getString(PREF_RECENT, "");
		if (raw == null || raw.isEmpty()) {
			return out;
		}
		for (String part : raw.split(",")) {
			String rom = part.trim().toLowerCase(Locale.US);
			if (!rom.isEmpty() && !out.contains(rom)) {
				out.add(rom);
			}
			if (out.size() >= RECENT_MAX) {
				break;
			}
		}
		return out;
	}

	private void rememberPlayed(String rom) {
		List<String> recents = loadRecentRoms();
		recents.remove(rom);
		recents.add(0, rom);
		while (recents.size() > RECENT_MAX) {
			recents.remove(recents.size() - 1);
		}
		StringBuilder sb = new StringBuilder();
		for (int i = 0; i < recents.size(); i++) {
			if (i > 0) {
				sb.append(',');
			}
			sb.append(recents.get(i));
		}
		prefs.edit()
				.putString(PREF_RECENT, sb.toString())
				.putString(PREF_LAST, rom)
				.apply();
		pendingScrollRom = rom;
	}

	private void maybeScrollToLast() {
		if (pendingScrollRom == null || setupStep != SETUP_HIDDEN) {
			return;
		}
		final String rom = pendingScrollRom;
		pendingScrollRom = null;
		int target = -1;
		for (int i = 0; i < shown.size(); i++) {
			Row r = shown.get(i);
			if (r.entry != null && !r.recentSlot && rom.equals(r.entry.rom)) {
				target = i;
			}
		}
		if (target < 0) {
			for (int i = 0; i < shown.size(); i++) {
				Row r = shown.get(i);
				if (r.entry != null && rom.equals(r.entry.rom)) {
					target = i;
					break;
				}
			}
		}
		if (target >= 0) {
			final int pos = target;
			list.post(() -> list.setSelection(pos));
		}
	}

	private boolean isMissing(String rom) {
		return scanDone && presentRoms != null && !presentRoms.contains(rom);
	}

	private void scanPresentRoms() {
		if (!hasRomFolder()) {
			presentRoms = null;
			scanDone = false;
			return;
		}
		final int gen = ++scanGen;
		final String saf = prefs.getString(PrefsHelper.PREF_SAF_URI, null);
		final String dir = prefs.getString(PrefsHelper.PREF_ROMsDIR, null);
		new Thread(() -> {
			Set<String> found = RomFolderScanner.scan(GamePickerActivity.this, saf, dir);
			runOnUiThread(() -> {
				if (gen != scanGen) {
					return;
				}
				presentRoms = found;
				scanDone = true;
				adapter.notifyDataSetChanged();
			});
		}, "picker-rom-scan").start();
	}

	private void onGameClicked(MahjongCatalog.Entry entry) {
		if (!hasRomFolder()) {
			Toast.makeText(this, R.string.picker_need_rom_folder, Toast.LENGTH_SHORT).show();
			if (setupStep == SETUP_HIDDEN) {
				setupStep = SETUP_ROM;
				applySetupUi();
			} else {
				openTree(REQ_ROMS);
			}
			return;
		}
		if (isMissing(entry.rom)) {
			Toast.makeText(this, getString(R.string.picker_rom_missing, entry.rom), Toast.LENGTH_LONG).show();
			return;
		}
		launchRom(entry.rom);
	}

	private void launchRom(String rom) {
		rememberPlayed(rom);
		Intent i = new Intent(this, MAME4droid.class);
		i.putExtra(EXTRA_ROM, rom);
		i.putExtra(EXTRA_FROM_PICKER, true);
		i.putExtra("cli_params", "-skip_gameinfo");
		i.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP);
		startWithVeil(i);
	}

	@Override
	protected void onActivityResult(int requestCode, int resultCode, Intent data) {
		super.onActivityResult(requestCode, resultCode, data);
		if (resultCode != RESULT_OK || data == null || data.getData() == null) {
			return;
		}
		Uri uri = data.getData();
		final int takeFlags = Intent.FLAG_GRANT_READ_URI_PERMISSION
				| Intent.FLAG_GRANT_WRITE_URI_PERMISSION;
		try {
			getContentResolver().takePersistableUriPermission(uri, takeFlags);
		} catch (SecurityException e) {
			Log.w(TAG, "persist uri failed", e);
		}

		if (requestCode == REQ_ROMS) {
			String romsPath = uri.getPath();
			if (romsPath == null) {
				romsPath = "/Your_Selected_Folder";
			}
			prefs.edit()
					.putString(PrefsHelper.PREF_ROMsDIR, romsPath)
					.putString(PrefsHelper.PREF_SAF_URI, uri.toString())
					.apply();
			persistInstallDirIfNeeded();
			Toast.makeText(this, R.string.picker_rom_folder_ok, Toast.LENGTH_SHORT).show();
			scanPresentRoms();
			if (setupStep == SETUP_ROM) {
				setupStep = SETUP_SNAP;
				applySetupUi();
			} else {
				rebuildRows();
			}
		} else if (requestCode == REQ_SNAP) {
			PickerSnapImporter.importTree(this, uri);
			if (setupStep == SETUP_SNAP) {
				finishSetup();
			} else {
				rebuildRows();
			}
		}
	}

	private static final class Row {
		final String header;
		final MahjongCatalog.Entry entry;
		final boolean recentSlot;

		private Row(String header, MahjongCatalog.Entry entry, boolean recentSlot) {
			this.header = header;
			this.entry = entry;
			this.recentSlot = recentSlot;
		}

		static Row header(String title) {
			return new Row(title, null, false);
		}

		static Row game(MahjongCatalog.Entry entry, boolean recentSlot) {
			return new Row(null, entry, recentSlot);
		}
	}

	private final class RowAdapter extends BaseAdapter {
		private static final int TYPE_HEADER = 0;
		private static final int TYPE_GAME = 1;

		@Override
		public int getCount() {
			return shown.size();
		}

		@Override
		public Object getItem(int position) {
			return shown.get(position);
		}

		@Override
		public long getItemId(int position) {
			return position;
		}

		@Override
		public int getViewTypeCount() {
			return 2;
		}

		@Override
		public int getItemViewType(int position) {
			return shown.get(position).entry == null ? TYPE_HEADER : TYPE_GAME;
		}

		@Override
		public boolean areAllItemsEnabled() {
			return false;
		}

		@Override
		public boolean isEnabled(int position) {
			return shown.get(position).entry != null;
		}

		@Override
		public View getView(int position, View convertView, ViewGroup parent) {
			Row row = shown.get(position);
			if (row.entry == null) {
				View v = convertView;
				if (v == null || v.getId() != R.id.picker_header_title) {
					v = LayoutInflater.from(GamePickerActivity.this)
							.inflate(R.layout.item_game_picker_header, parent, false);
				}
				((TextView) v).setText(row.header);
				return v;
			}

			View v = convertView;
			if (v == null || v.findViewById(R.id.row_title) == null) {
				v = LayoutInflater.from(GamePickerActivity.this)
						.inflate(R.layout.item_game_picker_row, parent, false);
			}
			MahjongCatalog.Entry e = row.entry;
			TextView title = v.findViewById(R.id.row_title);
			TextView rom = v.findViewById(R.id.row_rom);
			FrameLayout bg = v.findViewById(R.id.row_bg);
			title.setText(e.title);
			boolean missing = isMissing(e.rom);
			boolean compact = isCompact();
			if (missing) {
				rom.setText(getString(R.string.picker_rom_absent, e.rom));
				rom.setVisibility(View.VISIBLE);
			} else if (compact) {
				rom.setVisibility(View.GONE);
			} else {
				rom.setText(e.rom);
				rom.setVisibility(View.VISIBLE);
			}
			boolean indentClone = e.clone && !row.recentSlot;
			float density = getResources().getDisplayMetrics().density;
			int padL = (int) ((indentClone ? 28f : 16f) * density + 0.5f);
			int padR = (int) (24f * density + 0.5f);
			View textCol = (View) title.getParent();
			textCol.setPadding(padL, textCol.getPaddingTop(), padR, textCol.getPaddingBottom());
			float titleSp = compact ? (indentClone ? 13f : 15f) : (indentClone ? 15f : 17f);
			if (indentClone) {
				title.setTextColor(0xFFC5CCD4);
				title.setTextSize(titleSp);
				title.setTypeface(android.graphics.Typeface.create(
						android.graphics.Typeface.DEFAULT, android.graphics.Typeface.NORMAL));
				rom.setTextColor(0x88A8B0B8);
			} else {
				title.setTextColor(0xFFF7F0E6);
				title.setTextSize(titleSp);
				title.setTypeface(android.graphics.Typeface.create(
						android.graphics.Typeface.DEFAULT, android.graphics.Typeface.BOLD));
				rom.setTextColor(0x99D8CFC0);
			}
			int hPx = rowHeightPx();
			ViewGroup.LayoutParams lp = v.getLayoutParams();
			if (lp != null) {
				lp.height = hPx;
				v.setLayoutParams(lp);
			}
			DisplayMetrics dm = getResources().getDisplayMetrics();
			bg.setBackground(ListArtLoader.loadRowBackground(
					GamePickerActivity.this, e.rom, dm.widthPixels, hPx));
			View played = v.findViewById(R.id.row_played);
			played.setVisibility(recentSet.contains(e.rom) ? View.VISIBLE : View.GONE);
			v.setAlpha(missing ? 0.42f : 1f);
			return v;
		}
	}
}
