package com.seleuco.mame4droid.helpers;

import android.content.res.AssetManager;
import android.graphics.Color;
import android.util.Log;

import com.seleuco.mame4droid.BuildConfig;
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
 * Copies VERSION-gated asset packs into the MAME installation directory.
 * <p>
 * <b>full</b>: artwork + lamp Lua + Chinese lists; scrubs stub ini after install.<br>
 * <b>basic</b>: mj2 boot path — full {@code mahjong_pack} tree before {@code emulate}
 * (same as {@code 1.38.1-mj2}).
 */
public class AssetPackInstaller {

	private static final String TAG = "AssetPackInstaller";
	private static final String VERSION_FILE = "VERSION.txt";
	private static final String README_FILE = "README.txt";
	private static final String MARKER_DIR = ".asset_packs";
	private static final int BUFFER_SIZE = 8192;

	private static final PackSpec[] PACKS = {
			new PackSpec(
					"mahjong_pack",
					new String[]{
							"master_lamps.lua",
							"fei_mj_lamps",
							"mame.lst",
							"arcade.lst",
					},
					new String[]{
							"master_lamps.lua",
							"fei_mj_lamps",
							"ini/mame.ini",
							"mame.lst",
							"arcade.lst",
					}
			),
	};

	private final MAME4droid mm;

	public AssetPackInstaller(MAME4droid mm) {
		this.mm = mm;
	}

	/** Install every registered pack that needs an update. */
	public void installAllIfNeeded() {
		String installDir = resolveInstallDir();
		if (installDir == null) {
			return;
		}

		for (PackSpec pack : PACKS) {
			try {
				installPackIfNeeded(pack, installDir);
			} catch (Exception e) {
				Log.e(TAG, "Failed to install pack: " + pack.id, e);
				showError(mm.getString(R.string.asset_pack_install_failed, pack.id, e.getMessage()));
			}
		}

		if (BuildConfig.FEIJUCHANG_FULL_UX) {
			scrubMahjongStubRootIni(installDir);
			scrubStubUiIni(installDir);
		}
	}

	private String resolveInstallDir() {
		String installDir = mm.getMainHelper().getInstallationDIR();
		if (installDir == null || installDir.isEmpty()) {
			return null;
		}
		if (!installDir.endsWith("/")) {
			installDir += "/";
		}
		return installDir;
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

		if (!hasPackContent(assets, pack)) {
			Log.i(TAG, "Pack has no installable content yet, skip: " + pack.id);
			return;
		}

		boolean fullUx = BuildConfig.FEIJUCHANG_FULL_UX;
		if (!needsInstall(pack, installDir, assetVersion, assets, fullUx)) {
			Log.i(TAG, "Pack up to date: " + pack.id + " @" + assetVersion
					+ (fullUx ? " (full)" : " (basic/mj2)"));
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

			if (fullUx) {
				installFullPack(assets, pack, installDir, progress);
			} else {
				installBasicPackMj2(assets, pack, installDir, progress);
			}

			writeMarker(installDir, pack.id, assetVersion);
			Log.i(TAG, "Installed pack " + pack.id + " @" + assetVersion
					+ (fullUx ? " (full)" : " (basic/mj2)"));
		} finally {
			if (progress != null) {
				progress.end();
			}
		}
	}

	private void installFullPack(AssetManager assets, PackSpec pack, String installDir,
			WarnWidget progress) throws IOException {
		copyAssetTree(assets, pack.id, new File(installDir), pack.id, progress, true);
		scrubMahjongStubRootIni(installDir);
		File iniStub = new File(installDir, "ini/mame.ini");
		if (isMahjongStubIni(iniStub) && iniStub.delete()) {
			Log.i(TAG, "Removed stub ini/mame.ini");
		}
		scrubStubUiIni(installDir);
		ensureSystemNamesInUiIni(installDir);
	}

	/** Same steps as {@code 1.38.1-mj2} before {@code Emulator.emulate}. */
	private void installBasicPackMj2(AssetManager assets, PackSpec pack, String installDir,
			WarnWidget progress) throws IOException {
		copyAssetTree(assets, pack.id, new File(installDir), pack.id, progress, false);

		File iniMame = new File(installDir, "ini/mame.ini");
		File rootMame = new File(installDir, "mame.ini");
		if (iniMame.isFile()) {
			copyFile(iniMame, rootMame);
		} else if (rootMame.isFile()) {
			File iniDir = new File(installDir, "ini");
			if (!iniDir.exists() && !iniDir.mkdirs()) {
				throw new IOException("Cannot create: " + iniDir.getAbsolutePath());
			}
			copyFile(rootMame, iniMame);
		}

		ensureSystemNamesInUiIni(installDir);
	}

	private boolean needsInstall(PackSpec pack, String installDir, String assetVersion,
			AssetManager assets, boolean fullUx) {
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

		String[] required = fullUx ? pack.requiredPathsFull : pack.requiredPathsBasic;
		for (String requiredPath : required) {
			if (!assetExists(assets, pack.id + "/" + requiredPath)) {
				continue;
			}
			File f = new File(installDir, requiredPath);
			if (!f.exists()) {
				Log.i(TAG, "Missing required path for " + pack.id + ": " + requiredPath);
				return true;
			}
		}

		if (fullUx) {
			if (isMahjongStubIni(new File(installDir, "mame.ini"))) {
				return true;
			}
			if (isStubUiIni(new File(installDir, "ui.ini"))) {
				return true;
			}
			if (new File(installDir, "mame.lst").isFile()
					&& new File(installDir, "ui.ini").isFile()
					&& !isStubUiIni(new File(installDir, "ui.ini"))
					&& !uiIniHasSystemNames(new File(installDir, "ui.ini"))) {
				return true;
			}
		} else {
			File iniMame = new File(installDir, "ini/mame.ini");
			File rootMame = new File(installDir, "mame.ini");
			if (iniMame.isFile() && !rootMame.isFile()) {
				return true;
			}
			if (new File(installDir, "mame.lst").isFile()
					&& !uiIniHasSystemNames(new File(installDir, "ui.ini"))) {
				return true;
			}
		}
		return false;
	}

	private void scrubMahjongStubRootIni(String installDir) {
		File rootMame = new File(installDir, "mame.ini");
		if (isMahjongStubIni(rootMame)) {
			if (rootMame.delete()) {
				Log.i(TAG, "Removed stub root mame.ini (lamps via CLI)");
			}
		}
	}

	private void scrubStubUiIni(String installDir) {
		File uiIni = new File(installDir, "ui.ini");
		if (isStubUiIni(uiIni)) {
			if (uiIni.delete()) {
				Log.i(TAG, "Removed stub ui.ini (classic frontend)");
			}
		}
	}

	private static boolean isStubUiIni(File f) {
		if (f == null || !f.isFile()) {
			return false;
		}
		try {
			String text = readFileText(f);
			boolean sawSystemNames = false;
			for (String line : text.split("\n")) {
				String t = line.trim();
				if (t.isEmpty() || t.startsWith("#") || t.startsWith(";")) {
					continue;
				}
				int sp = t.indexOf(' ');
				String key = (sp < 0 ? t : t.substring(0, sp)).toLowerCase(java.util.Locale.ROOT);
				if ("system_names".equals(key)) {
					sawSystemNames = true;
				} else {
					return false;
				}
			}
			return sawSystemNames;
		} catch (IOException e) {
			return false;
		}
	}

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

	private boolean hasPackContent(AssetManager assets, PackSpec pack) {
		for (String required : pack.requiredPathsFull) {
			if (assetExists(assets, pack.id + "/" + required)) {
				return true;
			}
		}
		for (String required : pack.requiredPathsBasic) {
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
				return true;
			}
			try (InputStream in = assets.open(path)) {
				return true;
			}
		} catch (IOException e) {
			return false;
		}
	}

	private void copyAssetTree(AssetManager assets, String assetPath, File destDir,
			String packRoot, WarnWidget progress, boolean fullUx) throws IOException {
		String[] children = assets.list(assetPath);
		if (children == null) {
			return;
		}

		if (children.length == 0) {
			copyAssetFile(assets, assetPath, destDir, progress);
			return;
		}

		if (!destDir.exists() && !destDir.mkdirs()) {
			throw new IOException("Cannot create: " + destDir.getAbsolutePath());
		}

		for (String child : children) {
			if (assetPath.equals(packRoot)
					&& (VERSION_FILE.equals(child) || README_FILE.equals(child)
					|| (fullUx && "LICENSE.txt".equals(child)))) {
				continue;
			}
			if (fullUx && assetPath.equals(packRoot) && "ini".equals(child)) {
				continue;
			}
			String childAsset = assetPath + "/" + child;
			String[] grandChildren = assets.list(childAsset);
			if (grandChildren != null && grandChildren.length > 0) {
				copyAssetTree(assets, childAsset, new File(destDir, child), packRoot, progress, fullUx);
			} else {
				try {
					copyAssetFile(assets, childAsset, new File(destDir, child), progress);
				} catch (IOException openAsFileFailed) {
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

	private static void copyFile(File src, File dest) throws IOException {
		File parent = dest.getParentFile();
		if (parent != null && !parent.exists() && !parent.mkdirs()) {
			throw new IOException("Cannot create: " + parent.getAbsolutePath());
		}
		try (InputStream in = new BufferedInputStream(new FileInputStream(src));
			 BufferedOutputStream out = new BufferedOutputStream(new FileOutputStream(dest), BUFFER_SIZE)) {
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
		final String[] requiredPathsFull;
		final String[] requiredPathsBasic;

		PackSpec(String id, String[] requiredPathsFull, String[] requiredPathsBasic) {
			this.id = id;
			this.requiredPathsFull = requiredPathsFull;
			this.requiredPathsBasic = requiredPathsBasic;
		}
	}
}
