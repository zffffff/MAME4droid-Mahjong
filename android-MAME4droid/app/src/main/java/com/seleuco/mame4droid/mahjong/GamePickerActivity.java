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
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.widget.BaseAdapter;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.ListView;
import android.widget.TextView;
import android.widget.Toast;

import com.seleuco.mame4droid.MAME4droid;
import com.seleuco.mame4droid.R;
import com.seleuco.mame4droid.helpers.PrefsHelper;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/**
 * Full-screen mahjong game picker. Launches {@link MAME4droid} with a ROM short name.
 */
public class GamePickerActivity extends Activity {

	public static final String EXTRA_ROM = "feijuchang_rom";
	public static final String EXTRA_FROM_PICKER = "feijuchang_from_picker";
	public static final String EXTRA_CLASSIC_UI = "feijuchang_classic_ui";

	private static final int REQ_ROMS = 33;
	private static final int REQ_SNAP = 34;
	private static final String TAG = "GamePicker";

	private final List<MahjongCatalog.Entry> all = new ArrayList<>();
	private final List<MahjongCatalog.Entry> shown = new ArrayList<>();
	private RowAdapter adapter;
	private TextView emptyHint;
	private SharedPreferences prefs;

	@Override
	protected void onCreate(Bundle savedInstanceState) {
		super.onCreate(savedInstanceState);
		getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
		setContentView(R.layout.activity_game_picker);

		prefs = PreferenceManager.getDefaultSharedPreferences(getApplicationContext());

		TextView brand = findViewById(R.id.picker_brand);
		brand.setText(getString(R.string.app_name));

		emptyHint = findViewById(R.id.picker_empty);
		ListView list = findViewById(R.id.picker_list);
		adapter = new RowAdapter();
		list.setAdapter(adapter);
		list.setOnItemClickListener((parent, view, position, id) ->
				launchRom(shown.get(position).rom));

		EditText search = findViewById(R.id.picker_search);
		search.addTextChangedListener(new TextWatcher() {
			@Override
			public void beforeTextChanged(CharSequence s, int start, int count, int after) {
			}

			@Override
			public void onTextChanged(CharSequence s, int start, int before, int count) {
				filter(s == null ? "" : s.toString());
			}

			@Override
			public void afterTextChanged(Editable s) {
			}
		});

		findViewById(R.id.picker_rom_btn).setOnClickListener(v -> openTree(REQ_ROMS));
		findViewById(R.id.picker_snap_btn).setOnClickListener(v -> openTree(REQ_SNAP));
		findViewById(R.id.picker_settings_btn).setOnClickListener(v ->
				startActivity(new Intent(this, com.seleuco.mame4droid.prefs.UserPreferences.class)));
		findViewById(R.id.picker_classic_btn).setOnClickListener(v -> launchClassicUi());

		all.clear();
		all.addAll(MahjongCatalog.load(this));
		filter("");
	}

	@Override
	protected void onResume() {
		super.onResume();
		// Refresh row art after snap import / return from a game.
		if (adapter != null) {
			adapter.notifyDataSetChanged();
		}
	}

	private void openTree(int requestCode) {
		try {
			Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE);
			startActivityForResult(intent, requestCode);
		} catch (ActivityNotFoundException e) {
			Toast.makeText(this, R.string.dlg_no_doc_picker, Toast.LENGTH_LONG).show();
		}
	}

	private void filter(String q) {
		String needle = q.trim().toLowerCase(Locale.ROOT);
		shown.clear();
		for (MahjongCatalog.Entry e : all) {
			if (needle.isEmpty()
					|| e.rom.contains(needle)
					|| e.title.toLowerCase(Locale.ROOT).contains(needle)) {
				shown.add(e);
			}
		}
		adapter.notifyDataSetChanged();
		if (all.isEmpty()) {
			emptyHint.setVisibility(View.VISIBLE);
			emptyHint.setText(R.string.picker_empty_catalog);
		} else if (shown.isEmpty()) {
			emptyHint.setVisibility(View.VISIBLE);
			emptyHint.setText(R.string.picker_no_match);
		} else if (prefs.getString(PrefsHelper.PREF_ROMsDIR, null) == null) {
			emptyHint.setVisibility(View.VISIBLE);
			emptyHint.setText(R.string.picker_need_rom_folder);
		} else {
			emptyHint.setVisibility(View.GONE);
		}
	}

	private void launchRom(String rom) {
		if (prefs.getString(PrefsHelper.PREF_ROMsDIR, null) == null) {
			openTree(REQ_ROMS);
			Toast.makeText(this, R.string.picker_need_rom_folder, Toast.LENGTH_SHORT).show();
			return;
		}
		Intent i = new Intent(this, MAME4droid.class);
		i.putExtra(EXTRA_ROM, rom);
		i.putExtra(EXTRA_FROM_PICKER, true);
		i.putExtra(EXTRA_CLASSIC_UI, false);
		i.putExtra("cli_params", "-skip_gameinfo");
		i.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP);
		startActivity(i);
	}

	/** Open stock MAME frontend without re-launching the last picked ROM. */
	private void launchClassicUi() {
		Intent i = new Intent(this, MAME4droid.class);
		i.putExtra(EXTRA_FROM_PICKER, true);
		i.putExtra(EXTRA_CLASSIC_UI, true);
		i.putExtra(EXTRA_ROM, "");
		i.removeExtra("cli_params");
		i.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP);
		startActivity(i);
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
					.putString(PrefsHelper.PREF_INSTALLATION_DIR, null)
					.apply();
			Toast.makeText(this, R.string.picker_rom_folder_ok, Toast.LENGTH_SHORT).show();
		} else if (requestCode == REQ_SNAP) {
			PickerSnapImporter.importTree(this, uri);
		}
		filter(((EditText) findViewById(R.id.picker_search)).getText().toString());
	}

	private final class RowAdapter extends BaseAdapter {
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
		public View getView(int position, View convertView, ViewGroup parent) {
			View v = convertView;
			if (v == null) {
				v = LayoutInflater.from(GamePickerActivity.this)
						.inflate(R.layout.item_game_picker_row, parent, false);
			}
			MahjongCatalog.Entry e = shown.get(position);
			TextView title = v.findViewById(R.id.row_title);
			TextView rom = v.findViewById(R.id.row_rom);
			FrameLayout bg = v.findViewById(R.id.row_bg);
			title.setText(e.title);
			rom.setText(e.rom);
			DisplayMetrics dm = getResources().getDisplayMetrics();
			int w = dm.widthPixels;
			int hPx = (int) (80f * dm.density + 0.5f);
			bg.setBackground(ListArtLoader.loadRowBackground(GamePickerActivity.this, e.rom, w, hPx));
			return v;
		}
	}
}
