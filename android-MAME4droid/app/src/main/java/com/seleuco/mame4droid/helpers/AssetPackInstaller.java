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
 * Copies VERSION-gated asset packs into the MAME installation directory
 * ({@link MainHelper#getInstallationDIR()}, typically
 * {@code /storage/emulated/0/Android/data/.../files/}).
 * <p>
 * <b>full</b>: artwork + lamp Lua + Chinese name lists (lamps via CLI when a
 * game is selected).<br>
 * <b>basic</b>: artwork + per-game lamp ini; classic list stays English on
 * MAME 1.38.3 ({@code system_names} does not refresh the native list). Chinese
 * titles are on the full picker ({@link com.seleuco.mame4droid.mahjong.MahjongCatalog}).
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
					// Never require ini/mame.ini — stub is not installed, and
					// requiring it forced a full reinstall every cold start.
					new String[]{
							"master_lamps.lua",
							"fei_mj_lamps",
							"mame.lst",
							"arcade.lst",
					},
					new String[]{
							"artwork",
							"master_lamps.lua",
					}
			),
	};

	private static final String BASIC_MARKER_SUFFIX = "-basic22";

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
		scrubMahjongStubRootIni(installDir);
		scrubStubUiIni(installDir);
		if (!BuildConfig.FEIJUCHANG_FULL_UX) {
			scrubBasicBootInis(installDir);
		}
	}

	/**
	 * Safe classic MAME frontend boot on 1.38.3 — English list, no black screen.
	 * Strips {@code system_names} / install-dir {@code mame.lst} before emulate.
	 */
	public void prepareClassicFrontendBoot() {
		String installDir = resolveInstallDir();
		if (installDir == null) {
			return;
		}
		scrubBasicBootInis(installDir);
		scrubBasicChineseBeforeEmulate(installDir);
		BasicBootProbe.log(mm, "classic_boot_english", "frontend");
	}

	/**
	 * Basic only: same scrub as {@link #prepareClassicFrontendBoot()} before emulate.
	 */
	public void prepareBasicClassicBoot() {
		if (BuildConfig.FEIJUCHANG_FULL_UX) {
			return;
		}
		prepareClassicFrontendBoot();
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
					+ (fullUx ? " (full)" : " (basic)"));
			if (!fullUx) {
				scrubBasicBootInis(installDir);
			}
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
				copyAssetTree(assets, pack.id, new File(installDir), pack.id, progress);
				scrubMahjongStubRootIni(installDir);
				File iniStub = new File(installDir, "ini/mame.ini");
				if (isMahjongStubIni(iniStub) && iniStub.delete()) {
					Log.i(TAG, "Removed stub ini/mame.ini");
				}
				scrubStubUiIni(installDir);
				ensureSystemNamesInUiIni(installDir);
			} else {
				installBasicLampPack(assets, pack, installDir, progress);
				scrubBasicBootInis(installDir);
			}

			writeMarker(installDir, pack.id, assetVersion + (fullUx ? "" : BASIC_MARKER_SUFFIX));
			Log.i(TAG, "Installed pack " + pack.id + " @" + assetVersion
					+ (fullUx ? " (full)" : " (basic)"));
		} finally {
			if (progress != null) {
				progress.end();
			}
		}
	}

	/** Stub root/ini mame.ini, stub-only ui.ini, and empty {@code system_names}. */
	private void scrubBasicBootInis(String installDir) {
		deleteIfExists(new File(installDir, "mame.ini"));
		scrubMahjongStubRootIni(installDir);
		scrubStubUiIni(installDir);
		stripEmptySystemNamesFromUiIni(installDir);
		deleteIfExists(new File(installDir, "ini/mame.ini"));
		BasicBootProbe.log(mm, "scrub_basic_boot", "done");
		BasicBootProbe.logUiIniState(mm, "after_scrub");
	}

	private void installBasicLampPack(AssetManager assets, PackSpec pack, String installDir,
			WarnWidget progress) throws IOException {
		copyAssetTree(assets, pack.id + "/artwork",
				new File(installDir, "artwork"), pack.id, progress);
		copyAssetFileIfPresent(assets, pack.id + "/master_lamps.lua",
				new File(installDir, "master_lamps.lua"), progress);
		if (assetExists(assets, pack.id + "/fei_mj_lamps")) {
			copyAssetTree(assets, pack.id + "/fei_mj_lamps",
					new File(installDir, "fei_mj_lamps"), pack.id, progress);
		}
		writePerGameLampInis(installDir, assets);
		BasicBootProbe.log(mm, "basic_lamp_pack", "installed");
	}

	/**
	 * Per-game {@code ini/<rom>.ini} with autoboot — lamps in-game only, not on
	 * the classic system list ({@code ___empty}).
	 */
	private void writePerGameLampInis(String installDir, AssetManager assets) throws IOException {
		String[] roms = assets.list("mahjong_pack/artwork");
		if (roms == null || roms.length == 0) {
			return;
		}
		File iniDir = new File(installDir, "ini");
		if (!iniDir.exists() && !iniDir.mkdirs()) {
			throw new IOException("Cannot create ini/");
		}
		byte[] body = ("autoboot_script master_lamps.lua\ncheat 1\n")
				.getBytes(StandardCharsets.UTF_8);
		int n = 0;
		for (String rom : roms) {
			if (rom == null || rom.isEmpty() || rom.startsWith(".")) {
				continue;
			}
			String[] kids = assets.list("mahjong_pack/artwork/" + rom);
			if (kids == null || kids.length == 0) {
				continue;
			}
			try (FileOutputStream out = new FileOutputStream(new File(iniDir, rom + ".ini"))) {
				out.write(body);
				n++;
			}
		}
		Log.i(TAG, "Wrote " + n + " per-game lamp ini files");
	}

	/** Remove Chinese hooks before every {@code emulate} (classic list poison). */
	private void scrubBasicChineseBeforeEmulate(String installDir) {
		deleteIfExists(new File(installDir, "mame.lst"));
		deleteIfExists(new File(installDir, "arcade.lst"));
		stripAllSystemNamesFromUiIni(installDir);
	}

	private void stripAllSystemNamesFromUiIni(String installDir) {
		File uiIni = new File(installDir, "ui.ini");
		if (!uiIni.isFile()) {
			return;
		}
		try {
			List<String> lines = new ArrayList<>();
			boolean changed = false;
			String text = readFileText(uiIni);
			String[] raw = text.split("\n", -1);
			for (int i = 0; i < raw.length; i++) {
				String line = raw[i];
				if (i == raw.length - 1 && line.isEmpty()) {
					continue;
				}
				if (line.trim().regionMatches(true, 0, "system_names", 0,
						"system_names".length())) {
					changed = true;
					continue;
				}
				lines.add(line);
			}
			if (!changed) {
				return;
			}
			StringBuilder out = new StringBuilder();
			for (String line : lines) {
				out.append(line).append('\n');
			}
			try (FileOutputStream fos = new FileOutputStream(uiIni)) {
				fos.write(out.toString().getBytes(StandardCharsets.UTF_8));
			}
			Log.i(TAG, "Stripped system_names from ui.ini for classic boot");
			BasicBootProbe.log(mm, "strip_system_names", "ui.ini");
		} catch (IOException e) {
			Log.w(TAG, "stripAllSystemNamesFromUiIni failed", e);
		}
	}

	/** Remove only <em>empty</em> {@code system_names} lines (stock poison on 1.38.3). */
	private void stripEmptySystemNamesFromUiIni(String installDir) {
		File uiIni = new File(installDir, "ui.ini");
		if (!uiIni.isFile()) {
			return;
		}
		try {
			List<String> lines = new ArrayList<>();
			boolean changed = false;
			String text = readFileText(uiIni);
			String[] raw = text.split("\n", -1);
			for (int i = 0; i < raw.length; i++) {
				String line = raw[i];
				if (i == raw.length - 1 && line.isEmpty()) {
					continue;
				}
				String trim = line.trim();
				if (trim.regionMatches(true, 0, "system_names", 0, "system_names".length())) {
					String rest = trim.substring("system_names".length()).trim();
					if (rest.isEmpty()) {
						changed = true;
						continue;
					}
				}
				lines.add(line);
			}
			if (!changed) {
				return;
			}
			StringBuilder out = new StringBuilder();
			for (String line : lines) {
				out.append(line).append('\n');
			}
			try (FileOutputStream fos = new FileOutputStream(uiIni)) {
				fos.write(out.toString().getBytes(StandardCharsets.UTF_8));
			}
			Log.i(TAG, "Stripped empty system_names from ui.ini");
			BasicBootProbe.log(mm, "strip_empty_system_names", "ui.ini");
		} catch (IOException e) {
			Log.w(TAG, "stripEmptySystemNamesFromUiIni failed", e);
		}
	}

	private static void deleteIfExists(File f) {
		if (f != null && f.isFile() && f.delete()) {
			Log.i(TAG, "Removed for basic classic: " + f.getName());
		}
	}

	private static void deleteTree(File root) {
		if (root == null || !root.exists()) {
			return;
		}
		if (root.isDirectory()) {
			File[] kids = root.listFiles();
			if (kids != null) {
				for (File k : kids) {
					deleteTree(k);
				}
			}
		}
		if (root.delete()) {
			Log.i(TAG, "Removed for basic classic: " + root.getName());
		}
	}

	private boolean needsInstall(PackSpec pack, String installDir, String assetVersion,
			AssetManager assets, boolean fullUx) {
		File marker = markerFile(installDir, pack.id);
		String wantMarker = assetVersion + (fullUx ? "" : BASIC_MARKER_SUFFIX);
		if (!marker.isFile()) {
			return true;
		}
		try {
			String installed = readFileText(marker).trim();
			if (!wantMarker.equals(installed)) {
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
		} else if (isMahjongStubIni(new File(installDir, "mame.ini"))
				|| isStubUiIni(new File(installDir, "ui.ini"))
				|| hasEmptySystemNamesInUiIni(new File(installDir, "ui.ini"))) {
			return true;
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

	private static boolean hasEmptySystemNamesInUiIni(File uiIni) {
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
					return rest.isEmpty();
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
		if (!uiIni.isFile() || isStubUiIni(uiIni)) {
			Log.i(TAG, "Defer system_names until MAME writes a full ui.ini");
			return;
		}
		List<String> lines = new ArrayList<>();
		boolean replaced = false;
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
		if (!replaced) {
			lines.add("system_names           mame.lst");
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
			String packRoot, WarnWidget progress) throws IOException {
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
					|| "LICENSE.txt".equals(child))) {
				continue;
			}
			// Never land stub ini/ under files/ (classic UI blacks out).
			if (assetPath.equals(packRoot) && "ini".equals(child)) {
				continue;
			}
			String childAsset = assetPath + "/" + child;
			String[] grandChildren = assets.list(childAsset);
			if (grandChildren != null && grandChildren.length > 0) {
				copyAssetTree(assets, childAsset, new File(destDir, child), packRoot, progress);
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

	private void copyAssetFileIfPresent(AssetManager assets, String assetPath, File destFile,
			WarnWidget progress) throws IOException {
		if (!assetExists(assets, assetPath)) {
			return;
		}
		copyAssetFile(assets, assetPath, destFile, progress);
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
		final String[] requiredPathsFull;
		final String[] requiredPathsBasic;

		PackSpec(String id, String[] requiredPathsFull, String[] requiredPathsBasic) {
			this.id = id;
			this.requiredPathsFull = requiredPathsFull;
			this.requiredPathsBasic = requiredPathsBasic;
		}
	}
}
