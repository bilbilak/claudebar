import GObject from 'gi://GObject';
import St from 'gi://St';
import Clutter from 'gi://Clutter';
import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import cairo from 'cairo';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import { Extension } from 'resource:///org/gnome/shell/extensions/extension.js';
import { UsageSource, UsageSnapshot, UsageStatus } from './lib/api.js';
import { Settings } from './lib/settings.js';

const BAR_WIDTH = 64;
const BAR_HEIGHT = 6;
const BAR_GAP = 6;

type RGBA = [number, number, number, number];

const COLORS: Record<'ok' | 'warn' | 'crit' | 'muted', RGBA> = {
  ok: [0.26, 0.73, 0.38, 1],
  warn: [0.96, 0.62, 0.25, 1],
  crit: [0.93, 0.27, 0.27, 1],
  muted: [0.55, 0.55, 0.55, 1],
};

function colorFor(percent: number, status: UsageStatus, warn: number, crit: number): RGBA {
  if (status !== 'ok') return COLORS.muted;
  if (percent >= crit) return COLORS.crit;
  if (percent >= warn) return COLORS.warn;
  return COLORS.ok;
}

function roundedRect(cr: any, x: number, y: number, w: number, h: number, r: number) {
  if (w < 2 * r) r = w / 2;
  if (h < 2 * r) r = h / 2;
  cr.newSubPath();
  cr.arc(x + w - r, y + r, r, -Math.PI / 2, 0);
  cr.arc(x + w - r, y + h - r, r, 0, Math.PI / 2);
  cr.arc(x + r, y + h - r, r, Math.PI / 2, Math.PI);
  cr.arc(x + r, y + r, r, Math.PI, 1.5 * Math.PI);
  cr.closePath();
}

function formatReset(d: Date | null): string {
  if (!d) return '—';
  const ms = d.getTime() - Date.now();
  if (ms <= 0) return 'now';
  const mins = Math.round(ms / 60_000);
  if (mins < 60) return `in ${mins} min`;
  const hrs = Math.floor(mins / 60);
  const rem = mins % 60;
  if (hrs < 24) return rem ? `in ${hrs}h ${rem}m` : `in ${hrs}h`;
  const days = Math.floor(hrs / 24);
  const remH = hrs % 24;
  return remH ? `in ${days}d ${remH}h` : `in ${days}d`;
}

class ClaudeIndicatorImpl extends PanelMenu.Button {
  declare _extension: Extension;
  declare _source: UsageSource;
  declare _settings: Settings;
  declare _snapshot: UsageSnapshot | null;
  declare _area: St.DrawingArea;
  declare _percentBox: St.BoxLayout;
  declare _sessionPct: St.Label;
  declare _weeklyPct: St.Label;
  declare _sessionLabel: St.Label;
  declare _sessionReset: St.Label;
  declare _weeklyLabel: St.Label;
  declare _weeklyReset: St.Label;
  declare _statusLabel: St.Label;
  declare _pollId: number;
  declare _settingsChangedId: number;

  _init(extension: Extension, source: UsageSource, settings: Settings) {
    super._init(0.0, 'ClaudeBar');
    this._extension = extension;
    this._source = source;
    this._settings = settings;
    this._snapshot = null;
    this._pollId = 0;
    this._settingsChangedId = 0;

    const box = new St.BoxLayout({
      y_align: Clutter.ActorAlign.CENTER,
      style_class: 'claudebar-indicator-box',
    });

    this._area = new St.DrawingArea({
      width: BAR_WIDTH,
      height: BAR_HEIGHT * 2 + BAR_GAP,
      y_align: Clutter.ActorAlign.CENTER,
      style_class: 'claudebar-bars',
    });
    this._area.connect('repaint', (a: St.DrawingArea) => this._draw(a));
    box.add_child(this._area);

    this._percentBox = new St.BoxLayout({
      vertical: true,
      y_align: Clutter.ActorAlign.CENTER,
      style_class: 'claudebar-percent-box',
      visible: settings.showPercentages,
    });
    this._sessionPct = new St.Label({ text: '', style_class: 'claudebar-percent-label' });
    this._weeklyPct = new St.Label({ text: '', style_class: 'claudebar-percent-label' });
    this._percentBox.add_child(this._sessionPct);
    this._percentBox.add_child(this._weeklyPct);
    box.add_child(this._percentBox);

    this.add_child(box);
    this._buildMenu();

    this._settingsChangedId = settings.raw().connect('changed', () => {
      this._percentBox.visible = settings.showPercentages;
      this._area.queue_repaint();
      this._restartPolling();
    });

    this._startPolling();
    this._refresh().catch((e) => logError(e as Error, 'claudebar: initial refresh failed'));
  }

  _buildMenu() {
    const headerItem = new PopupMenu.PopupBaseMenuItem({ reactive: false, style_class: 'claudebar-menu-header-item' });
    const header = new St.Label({ text: 'ClaudeBar', style_class: 'claudebar-menu-header' });
    headerItem.add_child(header);
    this.menu.addMenuItem(headerItem);

    this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

    this._sessionLabel = new St.Label({ text: 'Current session: —', style_class: 'claudebar-menu-line' });
    this._sessionReset = new St.Label({ text: '', style_class: 'claudebar-menu-sub' });
    const sessionItem = new PopupMenu.PopupBaseMenuItem({ reactive: false, can_focus: false });
    const sessionBox = new St.BoxLayout({ vertical: true });
    sessionBox.add_child(this._sessionLabel);
    sessionBox.add_child(this._sessionReset);
    sessionItem.add_child(sessionBox);
    this.menu.addMenuItem(sessionItem);

    this._weeklyLabel = new St.Label({ text: 'Weekly (all models): —', style_class: 'claudebar-menu-line' });
    this._weeklyReset = new St.Label({ text: '', style_class: 'claudebar-menu-sub' });
    const weeklyItem = new PopupMenu.PopupBaseMenuItem({ reactive: false, can_focus: false });
    const weeklyBox = new St.BoxLayout({ vertical: true });
    weeklyBox.add_child(this._weeklyLabel);
    weeklyBox.add_child(this._weeklyReset);
    weeklyItem.add_child(weeklyBox);
    this.menu.addMenuItem(weeklyItem);

    this._statusLabel = new St.Label({ text: '', style_class: 'claudebar-menu-status', visible: false });
    const statusItem = new PopupMenu.PopupBaseMenuItem({ reactive: false, can_focus: false });
    statusItem.add_child(this._statusLabel);
    this.menu.addMenuItem(statusItem);

    this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

    const refresh = new PopupMenu.PopupMenuItem('Refresh now');
    refresh.connect('activate', () => this._refresh());
    this.menu.addMenuItem(refresh);

    const open = new PopupMenu.PopupMenuItem('Open claude.ai/settings/usage');
    open.connect('activate', () => {
      Gio.AppInfo.launch_default_for_uri('https://claude.ai/settings/usage', null);
    });
    this.menu.addMenuItem(open);

    const prefs = new PopupMenu.PopupMenuItem('Settings…');
    prefs.connect('activate', () => {
      this._extension.openPreferences();
    });
    this.menu.addMenuItem(prefs);
  }

  _startPolling() {
    if (this._pollId) return;
    const interval = Math.max(60, this._settings.pollInterval);
    this._pollId = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, interval, () => {
      this._refresh().catch((e) => logError(e as Error, 'claudebar: poll refresh failed'));
      return GLib.SOURCE_CONTINUE;
    });
  }

  _restartPolling() {
    if (this._pollId) {
      GLib.source_remove(this._pollId);
      this._pollId = 0;
    }
    this._startPolling();
  }

  async _refresh() {
    try {
      this._snapshot = await this._source.fetch();
    } catch (_e) {
      this._snapshot = {
        session: { percent: 0, resetsAt: null },
        weekly: { percent: 0, resetsAt: null },
        status: 'offline',
        fetchedAt: new Date(),
      };
    }
    this._area.queue_repaint();
    this._updateMenuLabels();
    this._updatePercentLabel();
    this._updateAccessibleName();
  }

  _updateMenuLabels() {
    const s = this._snapshot;
    if (!s) return;
    this._sessionLabel.text = `Current session: ${s.session.percent.toFixed(0)}%`;
    this._sessionReset.text = `Resets ${formatReset(s.session.resetsAt)}`;
    this._weeklyLabel.text = `Weekly (all models): ${s.weekly.percent.toFixed(0)}%`;
    this._weeklyReset.text = `Resets ${formatReset(s.weekly.resetsAt)}`;

    const statusText: Record<UsageStatus, string> = {
      ok: '',
      offline: 'Offline — last value may be stale',
      'rate-limited': 'Rate limited by Claude API',
      unauthenticated: 'Not signed in — open Settings to add a token',
    };
    const text = statusText[s.status];
    this._statusLabel.text = text;
    this._statusLabel.visible = text.length > 0;
  }

  _updatePercentLabel() {
    if (!this._settings.showPercentages) return;
    const s = this._snapshot;
    if (!s) {
      this._sessionPct.text = '';
      this._weeklyPct.text = '';
      return;
    }
    this._sessionPct.text = `${s.session.percent.toFixed(0)}%`;
    this._weeklyPct.text = `${s.weekly.percent.toFixed(0)}%`;
  }

  _updateAccessibleName() {
    const s = this._snapshot;
    if (!s) return;
    this.accessible_name = `ClaudeBar. Session ${s.session.percent.toFixed(0)} percent. Weekly ${s.weekly.percent.toFixed(0)} percent.`;
  }

  _draw(area: St.DrawingArea) {
    const [w, h] = area.get_surface_size();
    const cr: any = area.get_context();
    cr.setOperator(cairo.Operator.CLEAR);
    cr.paint();
    cr.setOperator(cairo.Operator.OVER);

    const warn = this._settings.warnThreshold;
    const crit = this._settings.criticalThreshold;
    const snap = this._snapshot;
    const status: UsageStatus = snap?.status ?? 'offline';
    const sessPct = snap?.session.percent ?? 0;
    const weekPct = snap?.weekly.percent ?? 0;

    const fg = (area as any).get_theme_node().get_foreground_color();
    const track: RGBA = [fg.red / 255, fg.green / 255, fg.blue / 255, 0.2];

    this._drawBar(cr, 0, 0, w, BAR_HEIGHT, sessPct, status, warn, crit, track);
    this._drawBar(cr, 0, BAR_HEIGHT + BAR_GAP, w, BAR_HEIGHT, weekPct, status, warn, crit, track);

    cr.$dispose();
  }

  _drawBar(
    cr: any,
    x: number,
    y: number,
    w: number,
    h: number,
    percent: number,
    status: UsageStatus,
    warn: number,
    crit: number,
    track: RGBA,
  ) {
    const r = h / 2;
    cr.setSourceRGBA(track[0], track[1], track[2], track[3]);
    roundedRect(cr, x, y, w, h, r);
    cr.fill();

    const p = Math.max(0, Math.min(100, percent));
    if (p <= 0) return;
    const fw = Math.max(h, (w * p) / 100);
    const [rC, gC, bC, aC] = colorFor(p, status, warn, crit);
    cr.setSourceRGBA(rC, gC, bC, aC);
    roundedRect(cr, x, y, fw, h, r);
    cr.fill();
  }

  destroy() {
    if (this._pollId) {
      GLib.source_remove(this._pollId);
      this._pollId = 0;
    }
    if (this._settingsChangedId) {
      this._settings.disconnect(this._settingsChangedId);
      this._settingsChangedId = 0;
    }
    super.destroy();
  }
}

export const ClaudeIndicator = GObject.registerClass(ClaudeIndicatorImpl);
export type ClaudeIndicator = InstanceType<typeof ClaudeIndicator>;
