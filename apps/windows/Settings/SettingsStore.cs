using System.ComponentModel;
using System.IO;
using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace ClaudeBar.Settings;

public sealed class SettingsStore : INotifyPropertyChanged
{
    public static SettingsStore Instance { get; } = Load();

    public event PropertyChangedEventHandler? PropertyChanged;

    private int _pollInterval = 300;
    private bool _showPercentages;
    private int _warnThreshold = 60;
    private int _criticalThreshold = 85;

    // --- Floating meter (always-on-top desktop widget) ---
    private bool _floatingMeterEnabled;
    private double _floatingMeterX = double.NaN;
    private double _floatingMeterY = double.NaN;
    private int _floatingMeterOpacity = 92;
    private int _floatingMeterWidth = 168;
    private bool _floatingMeterLocked;

    [JsonPropertyName("pollIntervalSeconds")]
    public int PollInterval
    {
        get => _pollInterval;
        set { if (SetField(ref _pollInterval, Clamp(value, 60, 3600))) Save(); }
    }

    [JsonPropertyName("showPercentages")]
    public bool ShowPercentages
    {
        get => _showPercentages;
        set { if (SetField(ref _showPercentages, value)) Save(); }
    }

    [JsonPropertyName("warnThreshold")]
    public int WarnThreshold
    {
        get => _warnThreshold;
        set { if (SetField(ref _warnThreshold, Clamp(value, 0, 100))) Save(); }
    }

    [JsonPropertyName("criticalThreshold")]
    public int CriticalThreshold
    {
        get => _criticalThreshold;
        set { if (SetField(ref _criticalThreshold, Clamp(value, 0, 100))) Save(); }
    }

    [JsonPropertyName("floatingMeterEnabled")]
    public bool FloatingMeterEnabled
    {
        get => _floatingMeterEnabled;
        set { if (SetField(ref _floatingMeterEnabled, value)) Save(); }
    }

    [JsonPropertyName("floatingMeterX")]
    public double FloatingMeterX
    {
        get => _floatingMeterX;
        set { if (SetField(ref _floatingMeterX, value)) Save(); }
    }

    [JsonPropertyName("floatingMeterY")]
    public double FloatingMeterY
    {
        get => _floatingMeterY;
        set { if (SetField(ref _floatingMeterY, value)) Save(); }
    }

    [JsonPropertyName("floatingMeterOpacity")]
    public int FloatingMeterOpacity
    {
        get => _floatingMeterOpacity;
        set { if (SetField(ref _floatingMeterOpacity, Clamp(value, 40, 100))) Save(); }
    }

    [JsonPropertyName("floatingMeterWidth")]
    public int FloatingMeterWidth
    {
        get => _floatingMeterWidth;
        set { if (SetField(ref _floatingMeterWidth, Clamp(value, 120, 320))) Save(); }
    }

    [JsonPropertyName("floatingMeterLocked")]
    public bool FloatingMeterLocked
    {
        get => _floatingMeterLocked;
        set { if (SetField(ref _floatingMeterLocked, value)) Save(); }
    }

    private static string FilePath
    {
        get
        {
            var dir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                "ClaudeBar");
            Directory.CreateDirectory(dir);
            return Path.Combine(dir, "settings.json");
        }
    }

    private static SettingsStore Load()
    {
        try
        {
            if (!File.Exists(FilePath)) return new SettingsStore();
            var text = File.ReadAllText(FilePath);
            var loaded = JsonSerializer.Deserialize<Persisted>(text);
            if (loaded is null) return new SettingsStore();
            return new SettingsStore
            {
                _pollInterval = Clamp(loaded.PollIntervalSeconds ?? 300, 60, 3600),
                _showPercentages = loaded.ShowPercentages ?? false,
                _warnThreshold = Clamp(loaded.WarnThreshold ?? 60, 0, 100),
                _criticalThreshold = Clamp(loaded.CriticalThreshold ?? 85, 0, 100),
                _floatingMeterEnabled = loaded.FloatingMeterEnabled ?? false,
                _floatingMeterX = loaded.FloatingMeterX ?? double.NaN,
                _floatingMeterY = loaded.FloatingMeterY ?? double.NaN,
                _floatingMeterOpacity = Clamp(loaded.FloatingMeterOpacity ?? 92, 40, 100),
                _floatingMeterWidth = Clamp(loaded.FloatingMeterWidth ?? 168, 120, 320),
                _floatingMeterLocked = loaded.FloatingMeterLocked ?? false,
            };
        }
        catch
        {
            return new SettingsStore();
        }
    }

    private void Save()
    {
        try
        {
            var snapshot = new Persisted
            {
                PollIntervalSeconds = _pollInterval,
                ShowPercentages = _showPercentages,
                WarnThreshold = _warnThreshold,
                CriticalThreshold = _criticalThreshold,
                FloatingMeterEnabled = _floatingMeterEnabled,
                FloatingMeterX = double.IsFinite(_floatingMeterX) ? _floatingMeterX : null,
                FloatingMeterY = double.IsFinite(_floatingMeterY) ? _floatingMeterY : null,
                FloatingMeterOpacity = _floatingMeterOpacity,
                FloatingMeterWidth = _floatingMeterWidth,
                FloatingMeterLocked = _floatingMeterLocked,
            };
            var json = JsonSerializer.Serialize(snapshot, new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(FilePath, json);
        }
        catch
        {
            // ignored
        }
    }

    private bool SetField<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return false;
        field = value;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
        return true;
    }

    private static int Clamp(int v, int lo, int hi) => Math.Min(Math.Max(v, lo), hi);

    private sealed class Persisted
    {
        [JsonPropertyName("pollIntervalSeconds")]
        public int? PollIntervalSeconds { get; set; }

        [JsonPropertyName("showPercentages")]
        public bool? ShowPercentages { get; set; }

        [JsonPropertyName("warnThreshold")]
        public int? WarnThreshold { get; set; }

        [JsonPropertyName("criticalThreshold")]
        public int? CriticalThreshold { get; set; }

        [JsonPropertyName("floatingMeterEnabled")]
        public bool? FloatingMeterEnabled { get; set; }

        [JsonPropertyName("floatingMeterX")]
        public double? FloatingMeterX { get; set; }

        [JsonPropertyName("floatingMeterY")]
        public double? FloatingMeterY { get; set; }

        [JsonPropertyName("floatingMeterOpacity")]
        public int? FloatingMeterOpacity { get; set; }

        [JsonPropertyName("floatingMeterWidth")]
        public int? FloatingMeterWidth { get; set; }

        [JsonPropertyName("floatingMeterLocked")]
        public bool? FloatingMeterLocked { get; set; }
    }
}
