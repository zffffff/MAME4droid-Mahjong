package com.seleuco.mame4droid.mahjong;

import android.content.ContentResolver;
import android.content.Context;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.provider.DocumentsContract;
import android.util.Log;

import java.io.File;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Locale;
import java.util.Set;

/**
 * Lists zip/7z short names in the user-chosen ROM folder (SAF tree or filesystem).
 * Returns {@code null} when the folder cannot be read so the UI does not mark every game missing.
 */
public final class RomFolderScanner {

	private static final String TAG = "RomFolderScanner";
	private static final int MAX_DEPTH = 3;
	private static final int MAX_FILES = 8000;
	private static final Set<String> SKIP_DIRS = new HashSet<>(Arrays.asList(
			"snap", "artwork", "samples", "nvram", "cfg", "sta", "hi", "ini",
			"ctrlr", "plugins", "hash", "language", "shader", "titles", "cabinets"
	));

	private RomFolderScanner() {
	}

	/**
	 * @return lowercased short names, empty set if the folder is empty, {@code null} on failure / unset
	 */
	public static Set<String> scan(Context ctx, String safUriStr, String romsDir) {
		if (safUriStr != null && !safUriStr.isEmpty()) {
			try {
				Uri tree = Uri.parse(safUriStr);
				Uri rootDoc = DocumentsContract.buildDocumentUriUsingTree(
						tree, DocumentsContract.getTreeDocumentId(tree));
				Set<String> out = new HashSet<>();
				int[] budget = new int[]{MAX_FILES};
				scanSaf(ctx.getContentResolver(), tree, rootDoc, out, 0, budget);
				return out;
			} catch (Exception e) {
				Log.w(TAG, "SAF scan failed", e);
				return null;
			}
		}
		if (romsDir != null && !romsDir.isEmpty()) {
			File dir = new File(romsDir);
			if (dir.isDirectory()) {
				Set<String> out = new HashSet<>();
				int[] budget = new int[]{MAX_FILES};
				scanFileDir(dir, out, 0, budget);
				return out;
			}
		}
		return null;
	}

	private static void scanSaf(ContentResolver cr, Uri treeUri, Uri docUri, Set<String> out,
			int depth, int[] budget) {
		if (depth > MAX_DEPTH || budget[0] <= 0) {
			return;
		}
		Uri children = DocumentsContract.buildChildDocumentsUriUsingTree(
				treeUri, DocumentsContract.getDocumentId(docUri));
		String[] projection = new String[]{
				DocumentsContract.Document.COLUMN_DOCUMENT_ID,
				DocumentsContract.Document.COLUMN_DISPLAY_NAME,
				DocumentsContract.Document.COLUMN_MIME_TYPE
		};
		try (Cursor c = queryChildren(cr, children, projection)) {
			if (c == null) {
				return;
			}
			int idCol = c.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID);
			int nameCol = c.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME);
			int mimeCol = c.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE);
			if (idCol < 0 || nameCol < 0) {
				return;
			}
			while (c.moveToNext() && budget[0] > 0) {
				String id = c.getString(idCol);
				String name = c.getString(nameCol);
				String mime = mimeCol >= 0 ? c.getString(mimeCol) : null;
				if (name == null || name.isEmpty() || name.startsWith(".")) {
					continue;
				}
				budget[0]--;
				boolean zipLike = isZipOr7zName(name);
				if (zipLike) {
					addRomName(out, name);
					// Some providers expose a valid zip as a browsable directory.
					// Count it as a ROM and do not walk inside the archive.
					continue;
				}
				if (DocumentsContract.Document.MIME_TYPE_DIR.equals(mime)) {
					String lower = name.toLowerCase(Locale.US);
					if (SKIP_DIRS.contains(lower)) {
						continue;
					}
					if (name.indexOf('.') < 0) {
						out.add(lower);
					}
					Uri child = DocumentsContract.buildDocumentUriUsingTree(treeUri, id);
					scanSaf(cr, treeUri, child, out, depth + 1, budget);
				} else if (mime != null && (mime.contains("zip") || mime.contains("7z"))) {
					addRomName(out, name);
					if (!isZipOr7zName(name)) {
						out.add(name.toLowerCase(Locale.US));
					}
				}
			}
		} catch (Exception e) {
			Log.w(TAG, "SAF listing failed at depth " + depth, e);
		}
	}

	private static Cursor queryChildren(ContentResolver cr, Uri children, String[] projection) {
		if (Build.VERSION.SDK_INT >= 26) {
			Bundle extras = new Bundle();
			extras.putInt(ContentResolver.QUERY_ARG_LIMIT, MAX_FILES);
			try {
				return cr.query(children, projection, extras, null);
			} catch (Exception ignored) {
				// Provider may not honor query bundles; fall back.
			}
		}
		return cr.query(children, projection, null, null, null);
	}

	private static void scanFileDir(File dir, Set<String> out, int depth, int[] budget) {
		if (depth > MAX_DEPTH || budget[0] <= 0) {
			return;
		}
		File[] files = dir.listFiles();
		if (files == null) {
			return;
		}
		for (File f : files) {
			if (budget[0] <= 0) {
				break;
			}
			String name = f.getName();
			if (name.startsWith(".")) {
				continue;
			}
			budget[0]--;
			if (f.isDirectory()) {
				String lower = name.toLowerCase(Locale.US);
				if (SKIP_DIRS.contains(lower)) {
					continue;
				}
				if (isZipOr7zName(name)) {
					addRomName(out, name);
					continue;
				}
				if (name.indexOf('.') < 0) {
					out.add(lower);
				}
				scanFileDir(f, out, depth + 1, budget);
			} else {
				addRomName(out, name);
			}
		}
	}

	private static boolean isZipOr7zName(String fileName) {
		String lower = fileName.toLowerCase(Locale.US);
		return lower.endsWith(".zip") || lower.endsWith(".7z");
	}

	private static void addRomName(Set<String> out, String fileName) {
		String lower = fileName.toLowerCase(Locale.US);
		if (lower.endsWith(".zip")) {
			out.add(lower.substring(0, lower.length() - 4));
		} else if (lower.endsWith(".7z")) {
			out.add(lower.substring(0, lower.length() - 3));
		}
	}
}
