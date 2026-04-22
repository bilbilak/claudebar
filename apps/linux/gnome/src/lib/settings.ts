import Gio from 'gi://Gio';

export class Settings {
  constructor(private gsettings: Gio.Settings) {}

  get pollInterval(): number {
    return this.gsettings.get_int('poll-interval-seconds');
  }
  get showPercentages(): boolean {
    return this.gsettings.get_boolean('show-percentages');
  }
  get warnThreshold(): number {
    return this.gsettings.get_int('warn-threshold');
  }
  get criticalThreshold(): number {
    return this.gsettings.get_int('critical-threshold');
  }

  connect(signal: string, cb: () => void): number {
    return this.gsettings.connect(signal, cb);
  }
  disconnect(id: number): void {
    this.gsettings.disconnect(id);
  }

  raw(): Gio.Settings {
    return this.gsettings;
  }
}
