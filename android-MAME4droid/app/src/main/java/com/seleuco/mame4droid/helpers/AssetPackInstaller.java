package com.seleuco.mame4droid.helpers;

import android.content.res.AssetManager;
import android.graphics.Color;
import android.util.Log;

import com.seleuco.mame4droid.BuildConfig;
import com.seleuco.mame4droid.Emulator;
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
 * <b>basic</b>: artwork always; Chinese {@code mame.lst} only after MAME has
 * written a full {@code ui.ini} (typically second cold start). Never install
 * lamp Lua / stub ini on the classic frontend boot path.
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
					}
			),
	};

	private static final String BASIC_MARKER_SUFFIX = "-basic-cn15";

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
			scrubBasicClassicPoisons(installDir);
		}
	}

	/**
	 * Basic only: scrub lamp/stub poison before {@code Emulator.emulate}. Stage
	 * Chinese name lists only when a full {@code ui.ini} exists from a previous
	 * session (never on a clean first install).
	 */
	public void prepareBasicClassicBoot() {
		if (BuildConfig.FEIJUCHANG_FULL_UX) {
			return;
		}
		String installDir = resolveInstallDir();
		if (installDir == null) {
			return;
		}
		scrubBasicClassicPoisons(installDir);
		try {
			stageBasicChineseNamesIfReady(installDir, mm.getAssets(), null);
		} catch (IOException e) {
			Log.w(TAG, "basic Chinese name prep failed", e);
		}
	}

	/**
	 * Basic only: after the native emulator thread returns, MAME should have
	 * written a full {@code ui.ini}. Merge {@code mame.lst} then so the next
	 * cold start shows Chinese titles without touching the first-boot list.
	 */
	public void stageBasicChineseNamesAfterSession() {
		if (BuildConfig.FEIJUCHANG_FULL_UX) {
			return;
		}
		String installDir = resolveInstallDir();
		if (installDir == null) {
			return;
		}
		try {
			stageBasicChineseNamesInternal(installDir, mm.getAssets(), null, true);
		} catch (IOException e) {
			Log.w(TAG, "basic Chinese name post-session failed", e);
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
					+ (fullUx ? " (full)" : " (basic)"));
			if (!fullUx) {
				if (!Emulator.isEmulating()) {
					scrubBasicClassicPoisons(installDir);
					stageBasicChineseNamesIfReady(installDir, assets, null);
				}
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
				// Classic home: artwork only. Chinese lists are staged separately
				// once a full ui.ini exists; never during an active emulate session.
				copyAssetTree(assets, pack.id + "/artwork",
						new File(installDir, "artwork"), pack.id, progress);
				if (!Emulator.isEmulating()) {
					scrubBasicClassicPoisons(installDir);
					stageBasicChineseNamesIfReady(installDir, assets, progress);
				}
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

	/**
	 * Leftovers that blank classic UI on MAME 1.38.3: lamp Lua, stub ini, and
	 * any {@code system_names} hook in {@code ui.ini} (stock files.zip ships an
	 * empty {@code system_names} line that blacks out the system list).
	 */
	private void scrubBasicClassicPoisons(String installDir) {
		deleteIfExists(new File(installDir, "mame.ini"));
		scrubMahjongStubRootIni(installDir);
		scrubStubUiIni(installDir);
		stripSystemNamesFromUiIni(installDir);
		deleteIfExists(new File(installDir, "ini/mame.ini"));
		deleteIfExists(new File(installDir, "master_lamps.lua"));
		deleteTree(new File(installDir, "fei_mj_lamps"));
		deleteIfExists(new File(installDir, "mame.lst"));
		deleteIfExists(new File(installDir, "arcade.lst"));
	}

	private void stageBasicChineseNamesIfReady(String installDir, AssetManager assets,
			WarnWidget progress) throws IOException {
		stageBasicChineseNamesInternal(installDir, assets, progress, false);
	}

	private void stageBasicChineseNamesInternal(String installDir, AssetManager assets,
			WarnWidget progress, boolean allowDuringEmulate) throws IOException {
		// Disabled on 1.38.3: system_names + mame.lst blacks the classic frontend.
		// Basic stays on English system names until a safe path is found.
		if (BuildConfig.FEIJUCHANG_FULL_UX) {
			return;
		}
		scrubBasicClassicPoisons(installDir);
	}

	private static boolean hasFullUiIni(String installDir) {
		File uiIni = new File(installDir, "ui.ini");
		return uiIni.isFile() && !isStubUiIni(uiIni);
	}

	/** Remove {@code system_names} from stock/custom ui.ini (classic list poison on 1.38.3). */
	private static void stripSystemNamesFromUiIni(String installDir) {
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
			Log.i(TAG, "Stripped system_names from ui.ini for basic classic");
		} catch (IOException e) {
			Log.w(TAG, "stripSystemNamesFromUiIni failed", e);
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
		} else if (new File(installDir, "master_lamps.lua").isFile()
				|| isMahjongStubIni(new File(installDir, "mame.ini"))
				|| isStubUiIni(new File(installDir, "ui.ini"))
				|| hasUiIniSystemNames(new File(installDir, "ui.ini"))
				|| new File(installDir, "mame.lst").isFile()) {
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

	private static boolean hasUiIniSystemNames(File uiIni) {
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
					return true;
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
