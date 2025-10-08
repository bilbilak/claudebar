import { Extension } from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import { ClaudeIndicator } from './indicator.js';
import { ClaudeBarSource } from './lib/api.js';
import { Settings } from './lib/settings.js';

export default class ClaudeBarExtension extends Extension {
  private _indicator: InstanceType<typeof ClaudeIndicator> | null = null;

  enable(): void {
    const settings = new Settings(this.getSettings());
    const source = new ClaudeBarSource();
    this._indicator = new ClaudeIndicator(this, source, settings);
    Main.panel.addToStatusArea(this.uuid, this._indicator);
  }

  disable(): void {
    this._indicator?.destroy();
    this._indicator = null;
  }
}
