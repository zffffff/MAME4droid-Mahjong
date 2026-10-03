/*
 * This file is part of MAME4droid.
 *
 * Copyright (C) 2025 David Valdeita (Seleuco)
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, see <http://www.gnu.org/licenses>.
 *
 * Linking MAME4droid statically or dynamically with other modules is
 * making a combined work based on MAME4droid. Thus, the terms and
 * conditions of the GNU General Public License cover the whole
 * combination.
 *
 * In addition, as a special exception, the copyright holders of MAME4droid
 * give you permission to combine MAME4droid with free software programs
 * or libraries that are released under the GNU LGPL and with code included
 * in the standard release of MAME under the MAME License (or modified
 * versions of such code, with unchanged license). You may copy and
 * distribute such a system following the terms of the GNU GPL for MAME4droid
 * and the licenses of the other code concerned, provided that you include
 * the source code of that other code when and as the GNU GPL requires
 * distribution of source code.
 *
 * Note that people who make modified versions of MAME4idroid are not
 * obligated to grant this special exception for their modified versions; it
 * is their choice whether to do so. The GNU General Public License
 * gives permission to release a modified version without this exception;
 * this exception also makes it possible to release a modified version
 * which carries forward this exception.
 *
 * MAME4droid is dual-licensed: Alternatively, you can license MAME4droid
 * under a MAME license, as set out in http://mamedev.org/
 */

package com.seleuco.mame4droid.views;

import android.content.Context;
import android.os.Build;
import android.os.Handler;
import android.util.AttributeSet;
import android.view.KeyEvent;
import android.view.View;

import com.seleuco.mame4droid.MAME4droid;
import com.seleuco.mame4droid.helpers.DialogHelper;
import com.seleuco.mame4droid.helpers.PrefsHelper;
import com.seleuco.mame4droid.input.InputHandler;
import com.seleuco.mame4droid.input.TouchController;

/**
 * EmulatorViewGLExt extends EmulatorViewGL to add advanced handling of the Android System UI,
 * such as the navigation bar and status bar. It implements OnSystemUiVisibilityChangeListener
 * to create an immersive, full-screen experience for the user, hiding system decorations
 * during gameplay and intelligently showing them when needed.
 */
public class EmulatorViewGLExt extends EmulatorViewGL implements android.view.View.OnSystemUiVisibilityChangeListener {

	//final String TAG = "EmulatorViewGLExt";

	// Stores the last known System UI visibility flags to detect changes.
	protected int mLastSystemUiVis;

	// A flag to track if a recent UI visibility change was caused by pressing volume keys.
	// This prevents certain dialogs from appearing when the user is just adjusting the volume.
	private boolean volumeChanges = false;

	/**
	 * Overrides the parent method to set up the System UI visibility listener.
	 * @param mm The main MAME4droid application instance.
	 */
	@Override
	public void setMAME4droid(MAME4droid mm) {
		if (mm == null) {
			// Clean up the listener if the context is being destroyed.
			setOnSystemUiVisibilityChangeListener(null);
			return;
		}
		super.setMAME4droid(mm);
		// Initially set the navigation visibility state.
		setNavVisibility(true);
		// Register this class to listen for changes in the system UI visibility.
		setOnSystemUiVisibilityChangeListener(this);
	}

	/** Standard View constructor */
	public EmulatorViewGLExt(Context context, AttributeSet attrs) {
		super(context, attrs);
	}

	/**
	 * A Runnable that, when executed, hides the system navigation bar.
	 * It is posted with a delay to automatically re-hide the UI after it has been shown.
	 */
	Runnable mNavHider = new Runnable() {
		@Override
		public void run() {
			// Reset the volume change flag when hiding the nav bar.
			volumeChanges = false;
			setNavVisibility(false);
		}
	};

	/**
	 * Called when the visibility of the window containing this view changes.
	 */
	@Override
	protected void onWindowVisibilityChanged(int visibility) {
		super.onWindowVisibilityChanged(visibility);

		if (mm == null) return;

		// When the view becomes visible, briefly show navigation elements and then schedule them to be hidden.
		// This gives the user a chance to interact with the system UI before entering immersive mode.
		if (mm.getPrefsHelper().getNavBarMode() == PrefsHelper.PREF_NAVBAR_IMMERSIVE) {
			setNavVisibility(false); // In immersive mode, hide immediately.
		} else {
			// In other modes, hide after a 3-second delay.
			getHandler().postDelayed(mNavHider, 3000);
		}
	}

	/**
	 * This is the callback that fires when the system UI visibility changes
	 * (e.g., when the navigation bar appears or disappears).
	 */
	@Override
	public void onSystemUiVisibilityChange(int visibility) {
		// Calculate which visibility flags have changed since the last update.
		int diff = mLastSystemUiVis ^ visibility;
		mLastSystemUiVis = visibility;

		// Check if the navigation bar was previously hidden and is now visible.
		if ((diff & SYSTEM_UI_FLAG_HIDE_NAVIGATION) != 0
			&& (visibility & SYSTEM_UI_FLAG_HIDE_NAVIGATION) == 0) {
			// Make sure the UI is in a consistent "visible" state.
			setNavVisibility(true);

			// If no dialogs are open, not in immersive mode, and the change wasn't from a volume press,
			// prompt the user to re-enter fullscreen.
			if (DialogHelper.savedDialog == DialogHelper.DIALOG_NONE &&
				mm.getPrefsHelper().getNavBarMode() != PrefsHelper.PREF_NAVBAR_IMMERSIVE &&
				!volumeChanges) {
				mm.showDialog(DialogHelper.DIALOG_FULLSCREEN);
			}
			// Also handle the older "low profile" mode change for older Android versions.
		} else if ((diff & SYSTEM_UI_FLAG_LOW_PROFILE) != 0
			&& (visibility & SYSTEM_UI_FLAG_LOW_PROFILE) == 0) {
			setNavVisibility(true);
		}
	}

	/**
	 * The core method that sets the desired system UI visibility flags.
	 * @param visible True to show the navigation bar, false to hide it.
	 */
	void setNavVisibility(boolean visible) {
		if (mm == null) return;

		int newVis;
		// Check if the on-screen controls are hidden, which implies a more "full-screen" intent.
		boolean full = mm.getInputHandler().getTouchController().getState() == TouchController.STATE_SHOWING_NONE;

		// Start with base flags that allow the layout to extend behind the system bars.
		if (full || (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT && mm.getPrefsHelper().getNavBarMode() == PrefsHelper.PREF_NAVBAR_IMMERSIVE)) {
			newVis = SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
				| SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
				| SYSTEM_UI_FLAG_LAYOUT_STABLE;
		} else {
			newVis = SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
				| SYSTEM_UI_FLAG_LAYOUT_STABLE;
		}

		if (!visible) {
			// If hiding, add the necessary flags.
			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT && mm.getPrefsHelper().getNavBarMode() == PrefsHelper.PREF_NAVBAR_IMMERSIVE) {
				// Use the modern "immersive sticky" mode on Android 4.4+
				newVis |= View.SYSTEM_UI_FLAG_HIDE_NAVIGATION // hide nav bar
					| View.SYSTEM_UI_FLAG_FULLSCREEN // hide status bar
					| View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY; // system bars reappear with a swipe and are semi-transparent
			} else if (full) {
				// On older systems, use a combination of flags to hide everything.
				newVis |= SYSTEM_UI_FLAG_LOW_PROFILE | SYSTEM_UI_FLAG_FULLSCREEN | SYSTEM_UI_FLAG_HIDE_NAVIGATION;
			} else {
				// If on-screen controls are visible, just hide the status bar and dim the nav bar.
				newVis |= SYSTEM_UI_FLAG_LOW_PROFILE | SYSTEM_UI_FLAG_FULLSCREEN;
			}
		}

		// If we are making the UI visible, schedule it to become invisible again after a delay.
		if (visible) {
			Handler h = getHandler();
			if (h != null) {
				h.removeCallbacks(mNavHider); // Remove any pending hide requests.
				// Schedule a new hide request. The delay is shorter in immersive mode.
				h.postDelayed(mNavHider, mm.getPrefsHelper().getNavBarMode() == PrefsHelper.PREF_NAVBAR_IMMERSIVE ? 1000 : 3000);
			}
		}

		// Apply the newly calculated visibility flags to the view.
		setSystemUiVisibility(newVis);
	}

	/**
	 * Intercepts key events to detect volume button presses.
	 */
	@Override
	public boolean dispatchKeyEvent(KeyEvent event) {
		// Check if the volume up or down key was pressed.
		if (event.getKeyCode() == KeyEvent.KEYCODE_VOLUME_DOWN || event.getKeyCode() == KeyEvent.KEYCODE_VOLUME_UP) {
			// Set a flag to indicate the UI change was likely due to a volume adjustment.
			volumeChanges = true;

			// When volume is changed, the system UI appears. We want to extend the timer
			// for re-hiding it to give the user time to see the volume level.
			Handler h = getHandler();
			if (h != null) {
				h.removeCallbacks(mNavHider);
				h.postDelayed(mNavHider, 4000);
			}
		}
		return super.dispatchKeyEvent(event);
	}

	/**
	 * Called when the window containing this view gains or loses focus.
	 */
	@Override
	public void onWindowFocusChanged(boolean hasWindowFocus) {
		if (hasWindowFocus) {
			// When the app regains focus (e.g., after switching apps),
			// ensure we re-enter our immersive state by scheduling the nav bar to hide.
			if (mm.getPrefsHelper().getNavBarMode() == PrefsHelper.PREF_NAVBAR_IMMERSIVE) {
				setNavVisibility(false);
			} else {
				getHandler().postDelayed(mNavHider, 3000);
			}
		}
		// It is CRITICAL to call the super method, as it contains the logic
		// for showing the soft keyboard from the parent class.
		super.onWindowFocusChanged(hasWindowFocus);
	}
}
