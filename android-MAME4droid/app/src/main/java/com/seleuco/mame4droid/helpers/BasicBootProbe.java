package com.seleuco.mame4droid.helpers;

import android.util.Log;

import com.seleuco.mame4droid.BuildConfig;
import com.seleuco.mame4droid.MAME4droid;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;

/**
 * Basic-edition boot trace: append-only log under the MAME install dir to
 * diagnose classic-frontend black screen / install regressions on device
 * (no adb required). Gated off for full flavor.
 */
public final class BasicBootProbe {

	private static final String TAG = "FJ_BASIC_PROBE";
	private static final String LOG_FILE = ".fj_basic_boot.log";
	private static final int MAX_LINES = 250;

	private BasicBootProbe() {
	}

	public static void markBootStart(MAME4droid mm) {
		if (BuildConfig.FEIJUCHANG_FULL_UX) {
			return;
		}
		String install = resolveInstallDir(mm);
		if (install == null) {
			return;
		}
		try {
			File f = new File(install, LOG_FILE);
			if (f.isFile()) {
				f.delete();
			}
			append(mm, "boot_start", "version=" + BuildConfig.VERSION_NAME);
		} catch (Exception e) {
			Log.w(TAG, "markBootStart failed", e);
		}
	}

	public static void log(MAME4droid mm, String step, String detail) {
		if (BuildConfig.FEIJUCHANG_FULL_UX) {
			return;
		}
		append(mm, step, detail);
	}

	public static void logUiIniState(MAME4droid mm, String phase) {
		if (BuildConfig.FEIJUCHANG_FULL_UX) {
			return;
		}
		String install = resolveInstallDir(mm);
		if (install == null) {
			return;
		}
		File ui = new File(install, "ui.ini");
		boolean hasLst = new File(install, "mame.lst").isFile();
		boolean hasLua = new File(install, "master_lamps.lua").isFile();
		boolean hasRootIni = new File(install, "mame.ini").isFile();
		String sysNames = ui.isFile() ? uiSystemNamesSummary(ui) : "no_ui_ini";
		log(mm, phase, "ui.ini=" + sysNames
				+ " mame.lst=" + hasLst
				+ " master_lamps.lua=" + hasLua
				+ " mame.ini=" + hasRootIni);
	}

	public static String readTail(MAME4droid mm, int maxLines) {
		if (BuildConfig.FEIJUCHANG_FULL_UX) {
			return "";
		}
		String install = resolveInstallDir(mm);
		if (install == null) {
			return "";
		}
		File f = new File(install, LOG_FILE);
		if (!f.isFile()) {
			return "";
		}
		List<String> lines = new ArrayList<>();
		try (BufferedReader r = new BufferedReader(new InputStreamReader(
				new FileInputStream(f), StandardCharsets.UTF_8))) {
			String line;
			while ((line = r.readLine()) != null) {
				lines.add(line);
			}
		} catch (IOException e) {
			return "";
		}
		int from = Math.max(0, lines.size() - maxLines);
		StringBuilder sb = new StringBuilder();
		for (int i = from; i < lines.size(); i++) {
			if (sb.length() > 0) {
				sb.append('\n');
			}
			sb.append(lines.get(i));
		}
		return sb.toString();
	}

	private static String uiSystemNamesSummary(File uiIni) {
		try (BufferedReader r = new BufferedReader(new InputStreamReader(
				new FileInputStream(uiIni), StandardCharsets.UTF_8))) {
			String line;
			while ((line = r.readLine()) != null) {
				String t = line.trim();
				if (t.isEmpty() || t.startsWith("#")) {
					continue;
				}
				if (t.regionMatches(true, 0, "system_names", 0, "system_names".length())) {
					String rest = t.substring("system_names".length()).trim();
					return rest.isEmpty() ? "system_names_empty" : "system_names=" + rest;
				}
			}
			return "no_system_names";
		} catch (IOException e) {
			return "ui_read_error";
		}
	}

	private static void append(MAME4droid mm, String step, String detail) {
		String install = resolveInstallDir(mm);
		if (install == null) {
			return;
		}
		String ts = new SimpleDateFormat("HH:mm:ss.SSS", Locale.US).format(new Date());
		String line = ts + " " + step + (detail != null && !detail.isEmpty() ? " | " + detail : "");
		Log.i(TAG, line);
		File f = new File(install, LOG_FILE);
		try {
			trimIfNeeded(f);
			try (BufferedWriter w = new BufferedWriter(new OutputStreamWriter(
					new FileOutputStream(f, true), StandardCharsets.UTF_8))) {
				w.write(line);
				w.write('\n');
			}
		} catch (IOException e) {
			Log.w(TAG, "append failed", e);
		}
	}

	private static void trimIfNeeded(File f) throws IOException {
		if (!f.isFile() || f.length() < 32_000) {
			return;
		}
		List<String> lines = new ArrayList<>();
		try (BufferedReader r = new BufferedReader(new InputStreamReader(
				new FileInputStream(f), StandardCharsets.UTF_8))) {
			String line;
			while ((line = r.readLine()) != null) {
				lines.add(line);
			}
		}
		int from = Math.max(0, lines.size() - MAX_LINES);
		try (BufferedWriter w = new BufferedWriter(new OutputStreamWriter(
				new FileOutputStream(f, false), StandardCharsets.UTF_8))) {
			for (int i = from; i < lines.size(); i++) {
				w.write(lines.get(i));
				w.write('\n');
			}
		}
	}

	private static String resolveInstallDir(MAME4droid mm) {
		if (mm == null || mm.getMainHelper() == null) {
			return null;
		}
		String installDir = mm.getMainHelper().getInstallationDIR();
		if (installDir == null || installDir.isEmpty()) {
			return null;
		}
		if (!installDir.endsWith("/")) {
			installDir += "/";
		}
		return installDir;
	}
}
