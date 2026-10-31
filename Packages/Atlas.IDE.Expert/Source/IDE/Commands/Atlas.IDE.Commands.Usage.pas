unit Atlas.IDE.Commands.Usage;

// Gemeinsame Nutzungszählung und Tippquelle von Atlas in der IDE (#600, #757).
// Eine Instanz je IDE-Sitzung (Instance), angelegt von der Komposition vor den
// Tastenkürzel-Tipps und der Willkommensseite:
// - Usage (TAtlasCommandUsage): Zählung je Befehl in
//   %LOCALAPPDATA%\Atlas\usage.json (nur Kennung, Zähler, Datum) und der
//   Zustand der Tipps samt Abschnitt "discover" in
//   %LOCALAPPDATA%\Atlas\shortcut-tips.json. Die Tastenkürzel-Tipps (#600)
//   zählen hinein, die Karte „Atlas entdecken“ (#757) liest daraus und
//   schreibt ihren Abschnitt; beide teilen sich so eine Datei, ohne sich
//   gegenseitig zu überschreiben. Gespeichert wird SaveDelayMs nach der letzten
//   Änderung (Changed), sofort mit SaveNow und beim Entladen.
// - tips.usageTracking (TipsUsageTracking): aus = Count zählt nichts.
// - Tips: tips.json aus dem Installationsordner (neben den BPLs oder eine
//   Ebene darüber, wie whatsnew.json, #756), einmal je Sitzung gelesen.
// Nur lokal, nichts wird versendet; Protokoll ohne Pfade und Befehlsnamen.

interface

uses
  System.SysUtils,
  Vcl.ExtCtrls,
  Atlas.Core.Commands.Usage,
  Atlas.Core.Commands.Tips;

type
  TAtlasIdeCommandUsage = class
  public const
    /// <summary>Speichern so lange nach der letzten Änderung.</summary>
    SaveDelayMs = 5000;
  private class var
    FInstance: TAtlasIdeCommandUsage;
  private
    FUsage: TAtlasCommandUsage;
    FSaveTimer: TTimer;
    FTips: TAtlasTips;
    FFolder: string;
    FTipsLoaded: Boolean;
    FOnReset: TProc;
    procedure SaveTick(Sender: TObject);
    procedure LoadTips;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Die Zählung der Sitzung oder nil (vor dem Laden, im Minimalmodus).</summary>
    class function Instance: TAtlasIdeCommandUsage; static;
    /// <summary>%LOCALAPPDATA%\Atlas\shortcut-tips.json (Zustand der Tipps, Abschnitt "discover").</summary>
    class function TipsFile: string; static;
    /// <summary>%LOCALAPPDATA%\Atlas\usage.json (Zählung).</summary>
    class function UsageFile: string; static;
    /// <summary>Ordner mit tips.json: neben dem Plugin oder eine Ebene darüber; '' ohne Datei.</summary>
    class function FindFolder(const APluginDir: string): string; static;
    /// <summary>„Zählung zurücksetzen“ (Einstellungen): alle Zähler auf null und sofort speichern; ohne Instanz
    /// direkt in der Datei.</summary>
    class procedure ResetCounts; static;
    /// <summary>Nutzung je Befehl für die Tastenkürzel-Übersicht (#520, #600); False ohne Zählung der Sitzung.
    /// </summary>
    class function UsageOf(const AId: string; out AEntry: TAtlasCommandUsageEntry): Boolean; static;
    /// <summary>tips.usageTracking übernehmen (beim Laden und nach jeder Änderung der Einstellungen).</summary>
    procedure ApplySettings;
    /// <summary>Etwas geändert: gesammelt nach SaveDelayMs speichern.</summary>
    procedure Changed;
    /// <summary>Sofort speichern, was sich geändert hat („Nicht mehr zeigen“ soll einen Absturz überstehen).
    /// </summary>
    procedure SaveNow;
    /// <summary>Tipps aus tips.json; leer ohne Datei.</summary>
    function Tips: TAtlasTips;
    /// <summary>Installationsordner mit tips.json; '' ohne.</summary>
    function Folder: string;
    property Usage: TAtlasCommandUsage read FUsage;
    /// <summary>Nach „Zählung zurücksetzen“, z. B. für die Karte „Atlas entdecken“.</summary>
    property OnReset: TProc read FOnReset write FOnReset;
  end;

implementation

uses
  System.IOUtils,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.IDE.Foundation.Settings;

/// <summary>Textdatei als UTF-8; ohne Byte-Order-Mark; '' bei Fehler.</summary>
function ReadText(const AFileName: string): string;
begin
  Result := '';
  try
    Result := TFile.ReadAllText(AFileName, TEncoding.UTF8);
  except
    on Exception do
      Exit('');
  end;
  if (Result <> '') and (Result[1] = #$FEFF) then
    Delete(Result, 1, 1);
end;

function LocalAppData: string;
begin
  Result := GetEnvironmentVariable('LOCALAPPDATA');
  if Result = '' then
    Result := TPath.GetTempPath;
end;

{ TAtlasIdeCommandUsage }

constructor TAtlasIdeCommandUsage.Create;
begin
  inherited Create;
  FUsage := TAtlasCommandUsage.Create;
  try
    FUsage.LoadFromFiles(TipsFile, UsageFile);
  except
    // Netz: Kaputte oder gesperrte Dateien behandelt TAtlasDataFile selbst (Bericht N3, .defekt bzw. nicht
    // überschreiben); hier landet nur Unerwartetes, und die IDE merkt nichts.
    on E: Exception do
      TAtlasGuard.Log('Nutzungszählung: Laden: ' + E.ClassName);
  end;
  FSaveTimer := TTimer.Create(nil);
  FSaveTimer.Enabled := False;
  FSaveTimer.Interval := SaveDelayMs;
  FSaveTimer.OnTimer := SaveTick;
  FInstance := Self;
  ApplySettings;
end;

destructor TAtlasIdeCommandUsage.Destroy;
begin
  if FInstance = Self then
    FInstance := nil;
  FreeAndNil(FSaveTimer);
  try
    FUsage.SaveToFiles(TipsFile, UsageFile);
  except
    // Beim Entladen nichts an die IDE.
    on E: Exception do
      TAtlasGuard.Log('Nutzungszählung: Speichern beim Entladen: ' + E.ClassName);
  end;
  FUsage.Free;
  inherited;
end;

class function TAtlasIdeCommandUsage.Instance: TAtlasIdeCommandUsage;
begin
  Result := FInstance;
end;

class function TAtlasIdeCommandUsage.TipsFile: string;
begin
  Result := TAtlasCommandUsage.DefaultFile(LocalAppData);
end;

class function TAtlasIdeCommandUsage.UsageFile: string;
begin
  Result := TAtlasCommandUsage.DefaultUsageFile(LocalAppData);
end;

class function TAtlasIdeCommandUsage.FindFolder(const APluginDir: string): string;
var
  Candidate: string;
begin
  Result := '';
  if APluginDir = '' then
    Exit;
  Candidate := IncludeTrailingPathDelimiter(APluginDir);
  if FileExists(Candidate + TAtlasTipCatalog.FileName) then
    Exit(Candidate);
  Candidate := IncludeTrailingPathDelimiter(ExpandFileName(Candidate + '..'));
  if FileExists(Candidate + TAtlasTipCatalog.FileName) then
    Result := Candidate;
end;

class function TAtlasIdeCommandUsage.UsageOf(const AId: string; out AEntry: TAtlasCommandUsageEntry): Boolean;
begin
  AEntry := TAtlasCommandUsageEntry.Create(AId);
  Result := (FInstance <> nil) and FInstance.Usage.Find(AId, AEntry);
end;

class procedure TAtlasIdeCommandUsage.ResetCounts;
var
  mUsage: TAtlasCommandUsage;
begin
  if FInstance <> nil then
  begin
    FInstance.FUsage.ResetCounts;
    FInstance.SaveNow;
    if Assigned(FInstance.FOnReset) then
      FInstance.FOnReset();
  end
  else
  begin
    mUsage := TAtlasCommandUsage.Create;
    try
      mUsage.LoadFromFiles(TipsFile, UsageFile);
      mUsage.ResetCounts;
      mUsage.SaveToFiles(TipsFile, UsageFile);
    finally
      mUsage.Free;
    end;
  end;
  // Anonym: nur die Aktion.
  TAtlasGuard.Log('Nutzungszählung zurückgesetzt (#757)');
end;

procedure TAtlasIdeCommandUsage.ApplySettings;
begin
  FUsage.Tracking := TAtlasIdeSettings.Current.TipsUsageTracking;
end;

procedure TAtlasIdeCommandUsage.Changed;
begin
  if FSaveTimer = nil then
    Exit;
  // Gesammelt speichern: nicht bei jedem Klick auf die Platte.
  FSaveTimer.Enabled := False;
  FSaveTimer.Enabled := True;
end;

procedure TAtlasIdeCommandUsage.SaveNow;
begin
  if FSaveTimer <> nil then
    FSaveTimer.Enabled := False;
  FUsage.SaveToFiles(TipsFile, UsageFile);
end;

procedure TAtlasIdeCommandUsage.SaveTick(Sender: TObject);
begin
  FSaveTimer.Enabled := False;
  TAtlasGuard.Run(TAtlasFeature.ShortcutTips,
    procedure
    begin
      FUsage.SaveToFiles(TipsFile, UsageFile);
    end);
end;

procedure TAtlasIdeCommandUsage.LoadTips;
begin
  FTipsLoaded := True;
  FTips := nil;
  FFolder := FindFolder(ExtractFilePath(GetModuleName(HInstance)));
  if FFolder <> '' then
    FTips := TAtlasTipCatalog.Parse(ReadText(FFolder + TAtlasTipCatalog.FileName));
  // Anonym: nur die Zahl.
  TAtlasGuard.Log(Format('Tipps (#757): %d aus tips.json', [Length(FTips)]));
end;

function TAtlasIdeCommandUsage.Tips: TAtlasTips;
begin
  if not FTipsLoaded then
    LoadTips;
  Result := FTips;
end;

function TAtlasIdeCommandUsage.Folder: string;
begin
  if not FTipsLoaded then
    LoadTips;
  Result := FFolder;
end;

end.
