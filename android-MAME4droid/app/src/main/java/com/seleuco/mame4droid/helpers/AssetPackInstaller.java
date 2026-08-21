package com.seleuco.mame4droid.helpers;

import android.content.res.AssetManager;
import android.graphics.Color;
import android.util.Log;

import com.seleuco.mame4droid.MAME4droid;
import com.seleuco.mame4droid.R;
import com.seleuco.mame4droid.widgets.WarnWidget;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

/**
 * Copies VERSION-gated asset packs into the MAME installation directory
 * ({@link MainHelper#getInstallationDIR()}, typically
 * {@code /storage/emulated/0/Android/data/.../files/}).
 * <p>
 * To ship another game pack later: put it under {@code assets/<id>/} with a
 * {@code VERSION.txt}, then add a {@link PackSpec} entry to {@link #PACKS}.
 */
public class AssetPackInstaller {

	private static final String TAG = "AssetPackInstaller";
	private static final String VERSION_FILE = "VERSION.txt";
	private static final String README_FILE = "README.txt";
	private static final String MARKER_DIR = ".asset_packs";
	private static final int BUFFER_SIZE = 8192;

	/**
	 * Registered packs. Contents (except VERSION.txt) are merged into the
	 * installation root. {@code requiredPaths} trigger a reinstall if missing
	 * even when the VERSION marker matches (e.g. after "restore default data").
	 */
	private static final PackSpec[] PACKS = {
			new PackSpec(
					"mahjong_pack",
					new String[]{
							"master_lamps.lua",
							"fei_mj_lamps",
							"ini/mame.ini",
							"mame.lst",
							"arcade.lst",
					}
			),
			// Future packs, e.g.:
			// new PackSpec("other_pack", new String[]{ "..." }),
	};

	private final MAME4droid mm;

	public AssetPackInstaller(MAME4droid mm) {
		this.mm = mm;
	}

	/** Install every registered pack that needs an update. */
	public void installAllIfNeeded() {
		String installDir = mm.getMainHelper().getInstallationDIR();
		if (installDir == null || installDir.isEmpty()) {
			return;
		}
		if (!installDir.endsWith("/")) {
			installDir += "/";
		}

		for (PackSpec pack : PACKS) {
			try {
				installPackIfNeeded(pack, installDir);
			} catch (Exception e) {
				Log.e(TAG, "Failed to install pack: " + pack.id, e);
				showError(mm.getString(R.string.asset_pack_install_failed, pack.id, e.getMessage()));
			}
		}
		// Even when VERSION matches, remove a leftover stub root mame.ini.
		scrubMahjongStubRootIni(installDir);
	}

	private void installPackIfNeeded(PackSpec pack, String installDir) throws IOException {
		AssetManager assets = mm.getAssets();
		String assetVersion = readAssetText(assets, pack.id + "/" + VERSION_FILE);
		if (assetVersion == null) {
			Log.i(TAG, "Pack not present in assets, skip: " + pack.id);
			return;
		}
		assetVersion = assetVersion.trim();
		if (assetVersion.isEmpty()) {
			Log.w(TAG, "Empty VERSION.txt for pack: " + pack.id);
			return;
		}

		// Placeholder only (VERSION/README, no real content yet) → do nothing.
		if (!hasPackContent(assets, pack)) {
			Log.i(TAG, "Pack has no installable content yet, skip: " + pack.id);
			return;
		}

		if (!needsInstall(pack, installDir, assetVersion, assets)) {
			Log.i(TAG, "Pack up to date: " + pack.id + " @" + assetVersion);
			return;
		}

		WarnWidget progress = null;
		try {
			progress = new WarnWidget(
					mm,
					mm.getString(R.string.asset_pack_installing_title),
					mm.getString(R.string.asset_pack_installing_wait, pack.id),
					Color.WHITE,
					false,
					true);
			progress.init();

			copyAssetTree(assets, pack.id, new File(installDir), pack.id, progress);

			// Pack ships a tiny ini/mame.ini (autoboot_script + cheat only). Never
			// mirror that stub over root mame.ini — a partial root file makes the
			// classic MAME frontend open as a black GL surface (OSC still draws).
			// Lamps are injected via CLI in Emulator.emulate(); scrub any old stub.
			scrubMahjongStubRootIni(installDir);

			// Stock MAME (0.237+) needs ui.ini system_names pointing at the .lst;
			// merely dropping mame.lst in files/ is not enough.
			ensureSystemNamesInUiIni(installDir);

			writeMarker(installDir, pack.id, assetVersion);
			Log.i(TAG, "Installed pack " + pack.id + " @" + assetVersion);
		} finally {
			if (progress != null) {
				progress.end();
			}
		}
	}

	private boolean needsInstall(PackSpec pack, String installDir, String assetVersion,
			AssetManager assets) {
		File marker = markerFile(installDir, pack.id);
		if (!marker.isFile()) {
			return true;
		}
		try {
			String installed = readFileText(marker).trim();
			if (!assetVersion.equals(installed)) {
				return true;
			}
		} catch (IOException e) {
			return true;
		}
		for (String required : pack.requiredPaths) {
			if (!assetExists(assets, pack.id + "/" + required)) {
				continue; // not shipped in this APK build
			}
			File f = new File(installDir, required);
			if (!f.exists()) {
				Log.i(TAG, "Missing required path for " + pack.id + ": " + required);
				return true;
			}
		}
		// Old builds mirrored the stub to root; force a reinstall pass to scrub it.
		if (isMahjongStubIni(new File(installDir, "mame.ini"))) {
			return true;
		}
		if (new File(installDir, "mame.lst").isFile()
				&& !uiIniHasSystemNames(new File(installDir, "ui.ini"))) {
			return true;
		}
		return false;
	}

	/**
	 * Pack {@code ini/mame.ini} is only {@code autoboot_script}/{@code cheat}.
	 * If that stub was copied to {@code files/mame.ini}, delete it so stock
	 * defaults + CLI apply. Leave a full player-saved mame.ini alone.
	 */
	private void scrubMahjongStubRootIni(String installDir) {
		File rootMame = new File(installDir, "mame.ini");
		if (isMahjongStubIni(rootMame)) {
			if (rootMame.delete()) {
				Log.i(TAG, "Removed stub root mame.ini (lamps via CLI)");
			}
		}
	}

	/** True if file exists and every non-comment key is autoboot_script or cheat. */
	private static boolean isMahjongStubIni(File f) {
		if (f == null || !f.isFile()) {
			return false;
		}
		try {
			String text = readFileText(f);
			boolean sawPackKey = false;
			for (String line : text.split("\n")) {
				String t = line.trim();
				if (t.isEmpty() || t.startsWith("#") || t.startsWith(";")) {
					continue;
				}
				int sp = t.indexOf(' ');
				String key = (sp < 0 ? t : t.substring(0, sp)).toLowerCase(java.util.Locale.ROOT);
				if ("autoboot_script".equals(key) || "cheat".equals(key)) {
					sawPackKey = true;
				} else {
					return false;
				}
			}
			return sawPackKey;
		} catch (IOException e) {
			return false;
		}
	}

	/** True if ui.ini already selects a translated system-names list. */
	private static boolean uiIniHasSystemNames(File uiIni) {
		if (!uiIni.isFile()) {
			return false;
		}
		try {
			String text = readFileText(uiIni);
			for (String line : text.split("\n")) {
				String t = line.trim();
				if (t.startsWith("#") || t.isEmpty()) {
					continue;
				}
				if (t.regionMatches(true, 0, "system_names", 0, "system_names".length())) {
					String rest = t.substring("system_names".length()).trim();
					return !rest.isEmpty();
				}
			}
		} catch (IOException e) {
			return false;
		}
		return false;
	}

	/**
	 * Point UI at {@code mame.lst} for localised system names (MAME 0.237+).
	 * Merges into existing ui.ini without wiping other settings.
	 */
	private void ensureSystemNamesInUiIni(String installDir) throws IOException {
		File lst = new File(installDir, "mame.lst");
		if (!lst.isFile()) {
			return;
		}
		File uiIni = new File(installDir, "ui.ini");
		List<String> lines = new ArrayList<>();
		boolean replaced = false;
		if (uiIni.isFile()) {
			String text = readFileText(uiIni);
			String[] raw = text.split("\n", -1);
			for (int i = 0; i < raw.length; i++) {
				String line = raw[i];
				// Drop the empty trailing element produced by a final newline.
				if (i == raw.length - 1 && line.isEmpty()) {
					continue;
				}
				String trim = line.trim();
				if (trim.regionMatches(true, 0, "system_names", 0, "system_names".length())) {
					if (!replaced) {
						lines.add("system_names           mame.lst");
						replaced = true;
					}
					continue;
				}
				lines.add(line);
			}
		}
		if (!replaced) {
			lines.add("system_names           mame.lst");
		}
		File parent = uiIni.getParentFile();
		if (parent != null && !parent.exists() && !parent.mkdirs()) {
			throw new IOException("Cannot create: " + parent.getAbsolutePath());
		}
		StringBuilder out = new StringBuilder();
		for (String line : lines) {
			out.append(line).append('\n');
		}
		try (FileOutputStream fos = new FileOutputStream(uiIni)) {
			fos.write(out.toString().getBytes(StandardCharsets.UTF_8));
		}
		Log.i(TAG, "Ensured ui.ini system_names=mame.lst");
	}

	/** True if assets contain at least one required path for this pack. */
	private boolean hasPackContent(AssetManager assets, PackSpec pack) {
		for (String required : pack.requiredPaths) {
			if (assetExists(assets, pack.id + "/" + required)) {
				return true;
			}
		}
		return false;
	}

	private static boolean assetExists(AssetManager assets, String path) {
		try {
			String[] kids = assets.list(path);
			if (kids != null && kids.length > 0) {
				return true; // directory with entries
			}
			try (InputStream in = assets.open(path)) {
				return true; // file
			}
		} catch (IOException e) {
			return false;
		}
	}

	private void copyAssetTree(AssetManager assets, String assetPath, File destDir,
			String packRoot, WarnWidget progress) throws IOException {
		String[] children = assets.list(assetPath);
		if (children == null) {
			return;
		}

		// File leaf: list() returns empty; try open().
		if (children.length == 0) {
			copyAssetFile(assets, assetPath, destDir, progress);
			return;
		}

		if (!destDir.exists() && !destDir.mkdirs()) {
			throw new IOException("Cannot create: " + destDir.getAbsolutePath());
		}

		for (String child : children) {
			if (assetPath.equals(packRoot)
					&& (VERSION_FILE.equals(child) || README_FILE.equals(child))) {
				continue; // meta files stay in APK only
			}
			String childAsset = assetPath + "/" + child;
			String[] grandChildren = assets.list(childAsset);
			if (grandChildren != null && grandChildren.length > 0) {
				copyAssetTree(assets, childAsset, new File(destDir, child), packRoot, progress);
			} else {
				try {
					copyAssetFile(assets, childAsset, new File(destDir, child), progress);
				} catch (IOException openAsFileFailed) {
					// Empty directory in assets
					File emptyDir = new File(destDir, child);
					if (!emptyDir.exists() && !emptyDir.mkdirs()) {
						throw new IOException("Cannot create: " + emptyDir.getAbsolutePath());
					}
				}
			}
		}
	}

	private void copyAssetFile(AssetManager assets, String assetPath, File destFile,
			WarnWidget progress) throws IOException {
		File parent = destFile.getParentFile();
		if (parent != null && !parent.exists() && !parent.mkdirs()) {
			throw new IOException("Cannot create: " + parent.getAbsolutePath());
		}

		if (progress != null) {
			progress.notifyText(mm.getString(R.string.asset_pack_installing_file, destFile.getName()));
		}

		try (InputStream in = new BufferedInputStream(assets.open(assetPath));
			 BufferedOutputStream out = new BufferedOutputStream(new FileOutputStream(destFile), BUFFER_SIZE)) {
			byte[] buf = new byte[BUFFER_SIZE];
			int n;
			while ((n = in.read(buf)) != -1) {
				out.write(buf, 0, n);
			}
			out.flush();
		}
	}

	private void writeMarker(String installDir, String packId, String version) throws IOException {
		File dir = new File(installDir, MARKER_DIR);
		if (!dir.exists() && !dir.mkdirs()) {
			throw new IOException("Cannot create: " + dir.getAbsolutePath());
		}
		File marker = markerFile(installDir, packId);
		try (FileOutputStream out = new FileOutputStream(marker)) {
			out.write(version.getBytes(StandardCharsets.UTF_8));
		}
	}

	private static File markerFile(String installDir, String packId) {
		return new File(installDir + MARKER_DIR + "/" + packId + ".version");
	}

	private static String readAssetText(AssetManager assets, String path) {
		try (InputStream in = assets.open(path);
			 BufferedReader reader = new BufferedReader(new InputStreamReader(in, StandardCharsets.UTF_8))) {
			StringBuilder sb = new StringBuilder();
			String line;
			while ((line = reader.readLine()) != null) {
				if (sb.length() > 0) {
					sb.append('\n');
				}
				sb.append(line);
			}
			return sb.toString();
		} catch (IOException e) {
			return null;
		}
	}

	private static String readFileText(File file) throws IOException {
		try (InputStream in = new FileInputStream(file);
			 BufferedReader reader = new BufferedReader(new InputStreamReader(in, StandardCharsets.UTF_8))) {
			StringBuilder sb = new StringBuilder();
			String line;
			while ((line = reader.readLine()) != null) {
				if (sb.length() > 0) {
					sb.append('\n');
				}
				sb.append(line);
			}
			return sb.toString();
		}
	}

	private void showError(final String msg) {
		mm.runOnUiThread(() -> {
			mm.getDialogHelper().setErrorMsg(msg);
			mm.showDialog(DialogHelper.DIALOG_ERROR_WRITING);
		});
	}

	private static final class PackSpec {
		final String id;
		final String[] requiredPaths;

		PackSpec(String id, String[] requiredPaths) {
			this.id = id;
			this.requiredPaths = requiredPaths;
		}
	}
}
