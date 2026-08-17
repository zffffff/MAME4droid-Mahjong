package com.seleuco.mame4droid.mahjong;

import android.app.Activity;
import android.app.ProgressDialog;
import android.content.ContentResolver;
import android.database.Cursor;
import android.net.Uri;
import android.provider.DocumentsContract;
import android.util.Log;
import android.widget.Toast;

import com.seleuco.mame4droid.R;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

/**
 * Import a SAF folder tree into the app's {@code snap/} directory (same as classic UI 🖼).
 */
public final class PickerSnapImporter {

	private static final String TAG = "PickerSnapImporter";
	private static final int BUFFER_SIZE = 8192;

	private PickerSnapImporter() {
	}

	public static File snapDir(Activity activity) {
		File root = activity.getExternalFilesDir(null);
		if (root == null) {
			root = activity.getFilesDir();
		}
		return new File(root, "snap");
	}

	@SuppressWarnings("deprecation")
	public static void importTree(Activity activity, Uri treeUri) {
		final File destRoot = snapDir(activity);
		Toast.makeText(activity, R.string.fj_snap_import_started, Toast.LENGTH_SHORT).show();

		final ProgressDialog[] dlg = new ProgressDialog[1];
		activity.runOnUiThread(() -> {
			ProgressDialog d = new ProgressDialog(activity);
			d.setTitle(R.string.fj_snap_import_title);
			d.setMessage(activity.getString(R.string.fj_snap_import_wait));
			d.setCancelable(false);
			d.show();
			dlg[0] = d;
		});

		new Thread(() -> {
			try {
				if (!destRoot.exists() && !destRoot.mkdirs()) {
					throw new IOException("Cannot create " + destRoot.getAbsolutePath());
				}
				Uri dirUri = DocumentsContract.buildDocumentUriUsingTree(
						treeUri, DocumentsContract.getTreeDocumentId(treeUri));
				int copied = copySafTree(activity, treeUri, dirUri, destRoot, dlg);
				final int count = copied;
				activity.runOnUiThread(() -> {
					dismiss(dlg);
					Toast.makeText(activity,
							activity.getString(R.string.fj_snap_import_done, count),
							Toast.LENGTH_LONG).show();
				});
			} catch (Exception e) {
				Log.e(TAG, "Snap import failed", e);
				activity.runOnUiThread(() -> {
					dismiss(dlg);
					Toast.makeText(activity, R.string.fj_snap_import_failed, Toast.LENGTH_LONG).show();
				});
			}
		}, "picker-snap-import").start();
	}

	@SuppressWarnings("deprecation")
	private static void dismiss(ProgressDialog[] dlg) {
		try {
			if (dlg[0] != null && dlg[0].isShowing()) {
				dlg[0].dismiss();
			}
		} catch (Exception ignored) {
		}
	}

	@SuppressWarnings("deprecation")
	private static int copySafTree(Activity activity, Uri treeUri, Uri docUri, File destDir,
			ProgressDialog[] dlg) throws IOException {
		int count = 0;
		final ContentResolver cr = activity.getContentResolver();
		Uri children = DocumentsContract.buildChildDocumentsUriUsingTree(
				treeUri, DocumentsContract.getDocumentId(docUri));
		String[] projection = new String[]{
				DocumentsContract.Document.COLUMN_DOCUMENT_ID,
				DocumentsContract.Document.COLUMN_DISPLAY_NAME,
				DocumentsContract.Document.COLUMN_MIME_TYPE
		};
		try (Cursor c = cr.query(children, projection, null, null, null)) {
			if (c == null) {
				return 0;
			}
			while (c.moveToNext()) {
				String id = c.getString(0);
				String name = c.getString(1);
				String mime = c.getString(2);
				if (name == null || name.isEmpty() || name.startsWith(".")) {
					continue;
				}
				Uri child = DocumentsContract.buildDocumentUriUsingTree(treeUri, id);
				if (DocumentsContract.Document.MIME_TYPE_DIR.equals(mime)) {
					File sub = new File(destDir, name);
					if (!sub.exists() && !sub.mkdirs()) {
						throw new IOException("Cannot create " + sub.getAbsolutePath());
					}
					count += copySafTree(activity, treeUri, child, sub, dlg);
				} else {
					File out = new File(destDir, name);
					try (InputStream in = cr.openInputStream(child);
						 OutputStream os = new FileOutputStream(out)) {
						if (in == null) {
							continue;
						}
						byte[] buf = new byte[BUFFER_SIZE];
						int n;
						while ((n = in.read(buf)) >= 0) {
							os.write(buf, 0, n);
						}
					}
					count++;
					if (count % 25 == 0) {
						final int nCopy = count;
						activity.runOnUiThread(() -> {
							if (dlg[0] != null && dlg[0].isShowing()) {
								dlg[0].setMessage(activity.getString(R.string.fj_snap_import_progress, nCopy));
							}
						});
					}
				}
			}
		}
		return count;
	}
}
