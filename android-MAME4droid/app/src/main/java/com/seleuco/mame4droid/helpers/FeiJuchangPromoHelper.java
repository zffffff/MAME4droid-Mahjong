package com.seleuco.mame4droid.helpers;

import android.content.ActivityNotFoundException;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.widget.Toast;

import com.seleuco.mame4droid.R;

/**
 * Homepage / Knowledge Planet promo links for 飞剧场 builds.
 */
public final class FeiJuchangPromoHelper {

	public static final String HOME_URL = "https://roxyweal.work/majiang/";
	public static final String ZSXQ_COUPON_URL = "https://t.zsxq.com/35B0X";

	private static final String WECHAT_PACKAGE = "com.tencent.mm";

	private FeiJuchangPromoHelper() {
	}

	public static boolean isZsxqHost(Uri uri) {
		if (uri == null) {
			return false;
		}
		String host = uri.getHost();
		if (host == null) {
			return false;
		}
		host = host.toLowerCase();
		return host.equals("zsxq.com") || host.endsWith(".zsxq.com");
	}

	/**
	 * Open 知识星球 coupon: always copy the link, try WeChat, else system browser.
	 * Toast reminds users they can paste to WeChat File Transfer.
	 */
	public static void openZsxqPreferWeChat(Context context, String url) {
		if (context == null || url == null || url.isEmpty()) {
			return;
		}
		Uri uri = Uri.parse(url);
		copyToClipboard(context, url);

		if (isWeChatInstalled(context)) {
			Intent wechat = new Intent(Intent.ACTION_VIEW, uri);
			wechat.setPackage(WECHAT_PACKAGE);
			wechat.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
			try {
				context.startActivity(wechat);
				Toast.makeText(context, R.string.fj_zsxq_wechat_or_file_helper, Toast.LENGTH_LONG).show();
				return;
			} catch (ActivityNotFoundException ignored) {
				// fall through
			}
		}

		Toast.makeText(context, R.string.fj_zsxq_copy_hint, Toast.LENGTH_LONG).show();
		openExternal(context, uri);
	}

	public static void openExternal(Context context, Uri uri) {
		if (context == null || uri == null) {
			return;
		}
		try {
			Intent intent = new Intent(Intent.ACTION_VIEW, uri);
			intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
			context.startActivity(intent);
		} catch (ActivityNotFoundException e) {
			Toast.makeText(context, R.string.fj_zsxq_no_browser, Toast.LENGTH_SHORT).show();
		}
	}

	private static boolean isWeChatInstalled(Context context) {
		try {
			context.getPackageManager().getPackageInfo(WECHAT_PACKAGE, 0);
			return true;
		} catch (PackageManager.NameNotFoundException e) {
			return false;
		}
	}

	private static void copyToClipboard(Context context, String text) {
		ClipboardManager cm = (ClipboardManager) context.getSystemService(Context.CLIPBOARD_SERVICE);
		if (cm != null) {
			cm.setPrimaryClip(ClipData.newPlainText("zsxq", text));
		}
	}
}
