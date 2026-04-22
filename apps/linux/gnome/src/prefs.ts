import Adw from 'gi://Adw';
import Gtk from 'gi://Gtk';
import Gio from 'gi://Gio';
import { ExtensionPreferences } from 'resource:///org/gnome/Shell/Extensions/js/extensions/prefs.js';
import { loadTokens, storeTokens, clearTokens } from './lib/auth.js';
import { startLoginFlow } from './lib/oauth.js';

export default class ClaudeBarPrefs extends ExtensionPreferences {
  fillPreferencesWindow(window: Adw.PreferencesWindow): void {
    try {
      const settings = this.getSettings();
      window.add(this._buildAccountPage(window));
      window.add(this._buildDisplayPage(settings));
      window.add(this._buildAdvancedPage(settings));
    } catch (e) {
      logError(e as Error, 'claudebar: fillPreferencesWindow failed');
      throw e;
    }
  }

  _buildAccountPage(window: Adw.PreferencesWindow): Adw.PreferencesPage {
    const page = new Adw.PreferencesPage({
      title: 'Account',
      icon_name: 'avatar-default-symbolic',
    });

    const group = new Adw.PreferencesGroup({
      title: 'Authentication',
      description:
        'Sign in with your Claude account to fetch Max plan usage. Tokens are stored in GNOME Keyring via libsecret.',
    });

    const statusRow = new Adw.ActionRow({
      title: 'Status',
      subtitle: 'Checking…',
    });
    const signInBtn = new Gtk.Button({
      label: 'Sign in with Claude',
      valign: Gtk.Align.CENTER,
      css_classes: ['suggested-action'],
    });
    const signOutBtn = new Gtk.Button({
      label: 'Sign out',
      valign: Gtk.Align.CENTER,
      css_classes: ['destructive-action'],
      visible: false,
    });
    statusRow.add_suffix(signInBtn);
    statusRow.add_suffix(signOutBtn);
    group.add(statusRow);

    page.add(group);

    const refreshStatus = async () => {
      try {
        const tokens = await loadTokens();
        if (tokens) {
          const tail = tokens.access_token.slice(-6);
          statusRow.subtitle = `Signed in (token ends ‘…${tail}’)`;
          signInBtn.visible = false;
          signOutBtn.visible = true;
        } else {
          statusRow.subtitle = 'Not signed in';
          signInBtn.visible = true;
          signOutBtn.visible = false;
        }
      } catch (e) {
        logError(e as Error, 'claudebar: loadTokens failed');
        statusRow.subtitle = 'Keyring error — see logs';
        signInBtn.visible = true;
        signOutBtn.visible = false;
      }
    };

    signInBtn.connect('clicked', () => {
      try {
        const flow = startLoginFlow();
        statusRow.subtitle = 'Waiting for browser sign-in…';
        signInBtn.sensitive = false;

        const cancelDialog = new Adw.MessageDialog({
          transient_for: window,
          heading: 'Sign in with Claude',
          body:
            'Your browser should have opened to claude.ai. Complete sign-in there, then return here. This dialog will close automatically.',
        });
        cancelDialog.add_response('cancel', 'Cancel');
        cancelDialog.set_default_response('cancel');
        cancelDialog.set_close_response('cancel');
        cancelDialog.connect('response', (_d: Adw.MessageDialog, resp: string) => {
          if (resp === 'cancel') flow.cancel();
        });
        cancelDialog.present();

        Gio.AppInfo.launch_default_for_uri(flow.authorizeUrl, null);

        flow.result
          .then(async (tokens) => {
            await storeTokens(tokens);
            cancelDialog.close();
            signInBtn.sensitive = true;
            await refreshStatus();
          })
          .catch((e) => {
            logError(e as Error, 'claudebar: sign-in failed');
            cancelDialog.close();
            signInBtn.sensitive = true;
            const errDialog = new Adw.MessageDialog({
              transient_for: window,
              heading: 'Sign-in failed',
              body: (e as Error).message,
            });
            errDialog.add_response('ok', 'OK');
            errDialog.present();
            refreshStatus().catch(() => {});
          });
      } catch (e) {
        logError(e as Error, 'claudebar: startLoginFlow failed');
        signInBtn.sensitive = true;
        const errDialog = new Adw.MessageDialog({
          transient_for: window,
          heading: 'Could not start sign-in',
          body: (e as Error).message,
        });
        errDialog.add_response('ok', 'OK');
        errDialog.present();
      }
    });

    signOutBtn.connect('clicked', () => {
      clearTokens()
        .then(() => refreshStatus())
        .catch((e) => logError(e as Error, 'claudebar: clearTokens failed'));
    });

    refreshStatus().catch((e) => logError(e as Error, 'claudebar: initial refreshStatus failed'));
    return page;
  }

  _buildDisplayPage(settings: Gio.Settings): Adw.PreferencesPage {
    const page = new Adw.PreferencesPage({
      title: 'Display',
      icon_name: 'applications-graphics-symbolic',
    });

    const topbarGroup = new Adw.PreferencesGroup({ title: 'Top bar' });

    const showPct = new Adw.SwitchRow({
      title: 'Show numeric percentages next to bars',
      subtitle: 'Small session and weekly percentages, stacked beside the bars.',
    });
    settings.bind('show-percentages', showPct, 'active', Gio.SettingsBindFlags.DEFAULT);
    topbarGroup.add(showPct);
    page.add(topbarGroup);

    const thresholdGroup = new Adw.PreferencesGroup({
      title: 'Color thresholds',
      description: 'When bars switch from green to orange to red.',
    });
    thresholdGroup.add(this._spinRow(settings, 'warn-threshold', 'Orange at (%)', 0, 100, 5));
    thresholdGroup.add(this._spinRow(settings, 'critical-threshold', 'Red at (%)', 0, 100, 5));
    page.add(thresholdGroup);

    return page;
  }

  _buildAdvancedPage(settings: Gio.Settings): Adw.PreferencesPage {
    const page = new Adw.PreferencesPage({
      title: 'Advanced',
      icon_name: 'preferences-system-symbolic',
    });

    const refreshGroup = new Adw.PreferencesGroup({ title: 'Refresh' });
    refreshGroup.add(this._spinRow(settings, 'poll-interval-seconds', 'Poll interval (seconds)', 60, 3600, 30));
    page.add(refreshGroup);

    return page;
  }

  _spinRow(settings: Gio.Settings, key: string, title: string, lo: number, hi: number, step: number): Adw.SpinRow {
    const adj = new Gtk.Adjustment({
      lower: lo,
      upper: hi,
      step_increment: step,
      page_increment: step * 2,
    });
    const row = new Adw.SpinRow({ title, adjustment: adj });
    settings.bind(key, row, 'value', Gio.SettingsBindFlags.DEFAULT);
    return row;
  }
}
