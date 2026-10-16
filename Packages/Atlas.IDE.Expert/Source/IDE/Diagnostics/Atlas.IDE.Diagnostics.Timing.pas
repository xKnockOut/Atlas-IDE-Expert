unit Atlas.IDE.Diagnostics.Timing;

// Diagnosemodus (#479) in der IDE:
// - Ein und aus über die Einstellung diagnosticMode.enabled (Seite Allgemein,
//   Registry DiagnosticMode, Vorgabe aus), den Schnellschalter „Diagnosemodus“
//   (#604, auch „Atlas: Diagnosemodus ein/aus“ in der Palette) oder das
//   Tastenkürzel (Vorgabe Strg+Alt+Umschalt+D, änderbar auf der Seite
//   „Tastenkonflikte“; Strg+Alt+Umschalt+A gehört den Schnellschaltern).
//   Taste und Schalter schreiben dieselbe Einstellung wie die Optionsseite.
// - An: TAtlasQueryTimings misst, das andockbare Fenster „Atlas-Diagnose“
//   öffnet, eine gelbe Zeile „Diagnosemodus: an“ steht im Atlas-Statusfeld
//   (#591; Klick öffnet das Fenster; die Zustandskachel #754 liest dieselbe
//   Zeile), ein Zeitgeber zeichnet das Fenster bei neuem Stand neu (alle
//   500 ms) und schreibt höchstens alle 30 s die letzten Diagnosedaten.
// - Aus: keine Messung, kein Zeitgeber, Fenster zu, keine Statuszeile; die
//   letzten Diagnosedaten werden noch einmal geschrieben.
// - Letzte Diagnosedaten (für „Problem melden“, #766): der Bericht ohne
//   Dateinamen in %LOCALAPPDATA%\Atlas\Logs\Diagnose\atlas-diagnosemodus.txt.
// - „Bericht kopieren“: Zeitwerte, Atlas- und IDE-Version, Einstellungen mit
//   gekürzten Pfaden, kein Quelltext, Dateinamen nur mit Häkchen.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.ExtCtrls,
  Atlas.Core.Status.Contract,
  Atlas.Core.Status.Registry,
  Atlas.Core.Status.Lines,
  Atlas.IDE.Foundation.Keys,
  Atlas.UI.Diagnostics.TimingFrame,
  Atlas.Core.Commands.Palette;

type
  TAtlasIdeDiagnosticMode = class
  public const
    /// <summary>Dieselbe Kennung liest die Zustandskachel (#754).</summary>
    StatusId = TAtlasStatusLines.DiagnosticModeId;
    StatusOrder = 3;
    RefreshMs = 500;
    SaveEveryMs = 30000;
    /// <summary>Name des Schnellschalters bzw. der Plugin-Einstellung.</summary>
    ToggleKey = 'DiagnosticMode';
  private class var
    FInstance: TAtlasIdeDiagnosticMode;
  private
    FRegistry: IAtlasStatusRegistry;
    FLine: TAtlasStatusLine;
    FLineRef: IAtlasStatusItem;
    FKey: TAtlasIdeKeyBinding;
    FTimer: TTimer;
    FActive: Boolean;
    FShownVersion: Integer;
    FSavedVersion: Integer;
    FSavedAt: UInt64;
    procedure TimerTick(Sender: TObject);
    procedure FrameCreated(AFrame: TAtlasTimingFrame);
    procedure Refresh(AFrame: TAtlasTimingFrame; AForce: Boolean);
    procedure CopyReport(AFileNames: Boolean);
    procedure AddStatusLine;
    procedure RemoveStatusLine;
    procedure SaveLastData;
  public
    constructor Create(const ARegistry: IAtlasStatusRegistry);
    destructor Destroy; override;
    /// <summary>Einstellung diagnosticMode.enabled übernehmen (nach jeder Änderung der Einstellungen).</summary>
    procedure ApplySettings;
    /// <summary>Tastenkürzel nach den Einstellungen (neu) belegen (#494).</summary>
    procedure Rebind;
    /// <summary>Fenster zeigen; der Modus bleibt, wie er ist.</summary>
    procedure ShowWindow;
    /// <summary>Befehl „Atlas: Diagnosefenster zeigen“ (schaltet bei Bedarf ein).</summary>
    procedure RegisterCommands(const ARegistry: IAtlasCommandRegistry);
    procedure ThemeChanged;
    /// <summary>Modus umschalten wie der Schnellschalter (Taste, Palette).</summary>
    class procedure Toggle; static;
    /// <summary>Bericht wie „Bericht kopieren“ aus dem aktuellen Stand.</summary>
    class function Report(AFileNames: Boolean): string; static;
    /// <summary>Datei der letzten Diagnosedaten (#766); kann fehlen.</summary>
    class function LastDataFile: string; static;
    property Active: Boolean read FActive;
  end;

implementation

uses
  Atlas.Core.Diagnostics.MainThread,
  System.IOUtils,
  System.JSON,
  Vcl.Clipbrd,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.Timing,
  Atlas.Core.Diagnostics.Export,
  Atlas.Core.Product.Version,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.History,
  Atlas.Core.Updates.Check,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Settings.QuickToggles,
  Atlas.IDE.Diagnostics.TimingWindow;

{ TAtlasIdeDiagnosticMode }

constructor TAtlasIdeDiagnosticMode.Create(const ARegistry: IAtlasStatusRegistry);
begin
  inherited Create;
  FInstance := Self;
  FRegistry := ARegistry;
  FSavedVersion := -1;
  FShownVersion := -1;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := RefreshMs;
  FTimer.OnTimer := TimerTick;
  TAtlasIdeTimingWindow.OnFrame :=
    procedure(AFrame: TAtlasTimingFrame)
    begin
      if FInstance <> nil then
        FInstance.FrameCreated(AFrame);
    end;
  FKey := TAtlasIdeKeyBinding.Create('Atlas.DiagnosticMode', 'Atlas-Diagnosemodus', TAtlasFeature.Settings,
    procedure
    begin
      Toggle;
    end);
  Rebind;
  ApplySettings;
end;

destructor TAtlasIdeDiagnosticMode.Destroy;
begin
  if FInstance = Self then
    FInstance := nil;
  // Erst abmelden, dann freigeben (#493).
  FreeAndNil(FKey);
  FTimer.Free;
  if FActive then
    SaveLastData;
  FActive := False;
  TAtlasQueryTimings.Enabled := False;
  RemoveStatusLine;
  TAtlasIdeTimingWindow.Release;
  inherited;
end;

procedure TAtlasIdeDiagnosticMode.Rebind;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasIdeSettings.Current;
  FKey.Rebind(Word(Settings.DiagnosticModeKey), Settings.DiagnosticModeKeyPriority,
    TAtlasStrings.Text(TAtlasTextId.SettingsDiagnosticModeKey));
end;

class procedure TAtlasIdeDiagnosticMode.Toggle;
begin
  TAtlasGuard.Run(TAtlasFeature.Settings,
    procedure
    begin
      // Dieselbe Einstellung wie Optionsseite und Schnellschalter; Update meldet OnChanged → ApplySettings.
      TAtlasIdeQuickToggles.Switch(ToggleKey);
    end);
end;

procedure TAtlasIdeDiagnosticMode.ApplySettings;
var
  Wanted: Boolean;
begin
  Wanted := TAtlasIdeSettings.Current.DiagnosticMode;
  if Wanted = FActive then
    Exit;
  FActive := Wanted;
  TAtlasQueryTimings.Enabled := Wanted;
  if Wanted then
  begin
    TAtlasGuard.Log('Diagnosemodus an (#479)');
    FShownVersion := -1;
    FSavedAt := TThread.GetTickCount64;
    FTimer.Enabled := True;
    AddStatusLine;
    // Nicht mitten im Laden des Packages bzw. im Optionsdialog andocken: erst in der nächsten Runde.
    TAtlasMainThread.ForceQueue(TAtlasFeature.Settings,
      procedure
      begin
        if (FInstance <> nil) and FInstance.FActive then
          TAtlasGuard.Run(TAtlasFeature.Settings,
            procedure
            begin
              FInstance.ShowWindow;
            end);
      end);
  end
  else
  begin
    TAtlasGuard.Log('Diagnosemodus aus (#479)');
    FTimer.Enabled := False;
    SaveLastData;
    RemoveStatusLine;
    TAtlasIdeTimingWindow.Hide;
  end;
end;

procedure TAtlasIdeDiagnosticMode.AddStatusLine;
begin
  if (FRegistry = nil) or (FLineRef <> nil) then
    Exit;
  FLine := TAtlasStatusLine.Create(FRegistry, StatusId, StatusOrder,
    procedure
    begin
      if FInstance <> nil then
        FInstance.ShowWindow;
    end);
  FLineRef := FLine;
  // Gelb: Der Modus misst und schreibt Diagnosedaten (#754).
  FLine.Update(TAtlasStrings.Text(TAtlasTextId.DiagnosticStatusLine), TAtlasStatusState.Yellow,
    TAtlasStrings.Text(TAtlasTextId.DiagnosticStatusSummary), TAtlasStrings.Text(TAtlasTextId.WelcomeStateDiagnosticOn),
    TAtlasStrings.Text(TAtlasTextId.WelcomeStateDiagnosticDetail));
  FRegistry.Add(FLineRef);
end;

procedure TAtlasIdeDiagnosticMode.RemoveStatusLine;
begin
  if FLineRef = nil then
    Exit;
  if FRegistry <> nil then
    FRegistry.Remove(StatusId);
  FLine := nil;
  FLineRef := nil;
end;

procedure TAtlasIdeDiagnosticMode.ShowWindow;
var
  Frame: TAtlasTimingFrame;
begin
  Frame := TAtlasIdeTimingWindow.Show;
  if Frame <> nil then
    Refresh(Frame, True);
end;

procedure TAtlasIdeDiagnosticMode.FrameCreated(AFrame: TAtlasTimingFrame);
begin
  AFrame.OnCopy :=
    procedure(AFileNames: Boolean)
    begin
      TAtlasGuard.Run(TAtlasFeature.Settings,
        procedure
        begin
          if FInstance <> nil then
            FInstance.CopyReport(AFileNames);
        end);
    end;
  Refresh(AFrame, True);
end;

procedure TAtlasIdeDiagnosticMode.Refresh(AFrame: TAtlasTimingFrame; AForce: Boolean);
var
  Version: Integer;
begin
  if AFrame = nil then
    Exit;
  Version := TAtlasQueryTimings.Shared.Version;
  if AForce then
    AFrame.SetColors(TAtlasIdeStyle.Colors)
  else if Version = FShownVersion then
    Exit;
  FShownVersion := Version;
  AFrame.SetQueries(TAtlasQueryTimings.Shared.Snapshot);
end;

procedure TAtlasIdeDiagnosticMode.TimerTick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Settings,
    procedure
    begin
      if TAtlasIdeTimingWindow.Visible then
        Refresh(TAtlasIdeTimingWindow.ExistingFrame, False);
      if (TAtlasQueryTimings.Shared.Version <> FSavedVersion) and
        (TThread.GetTickCount64 - FSavedAt >= SaveEveryMs) then
        SaveLastData;
    end);
end;

procedure TAtlasIdeDiagnosticMode.ThemeChanged;
begin
  TAtlasIdeTimingWindow.ApplyTheme;
  Refresh(TAtlasIdeTimingWindow.ExistingFrame, True);
end;

procedure TAtlasIdeDiagnosticMode.CopyReport(AFileNames: Boolean);
var
  Frame: TAtlasTimingFrame;
begin
  Clipboard.AsText := Report(AFileNames);
  Frame := TAtlasIdeTimingWindow.ExistingFrame;
  if Frame <> nil then
    Frame.ShowNote(TAtlasStrings.Text(TAtlasTextId.DiagnosticCopied));
end;

procedure TAtlasIdeDiagnosticMode.RegisterCommands(const ARegistry: IAtlasCommandRegistry);
begin
  ARegistry.RegisterCommand('Atlas.DiagnosticWindow', TAtlasStrings.Text(TAtlasTextId.DiagnosticPaletteShow), '',
    procedure
    begin
      if FInstance = nil then
        Exit;
      if FInstance.FActive then
        FInstance.ShowWindow
      else
        Toggle;
    end);
end;

function SettingsJson: string;
var
  Values: TJSONObject;
begin
  Values := TAtlasMemorySettingsStore.FromSettings(TAtlasIdeSettings.Current).ToJson;
  try
    Result := Values.Format(2);
  finally
    Values.Free;
  end;
end;

class function TAtlasIdeDiagnosticMode.Report(AFileNames: Boolean): string;
var
  Input: TAtlasTimingReportInput;
begin
  Input := Default(TAtlasTimingReportInput);
  Input.AtlasVersion := TAtlasPluginVersion.Version;
  Input.IdeVersion := TAtlasUpdates.IdeVersion;
  {$IFDEF WIN64}
  Input.Platform := 'Win64';
  {$ELSE}
  Input.Platform := 'Win32';
  {$ENDIF}
  Input.Settings := SettingsJson;
  Input.Identity := [GetEnvironmentVariable('USERNAME'), GetEnvironmentVariable('COMPUTERNAME'),
    GetEnvironmentVariable('USERDOMAIN')];
  Input.FileNames := AFileNames;
  Input.Created := Now;
  Result := TAtlasTimingReport.Build(TAtlasQueryTimings.Shared.Snapshot, Input);
end;

class function TAtlasIdeDiagnosticMode.LastDataFile: string;
begin
  Result := TPath.Combine(TAtlasDiagnosticExport.DefaultFolder, TAtlasTimingReport.FileName);
end;

procedure TAtlasIdeDiagnosticMode.SaveLastData;
var
  Version: Integer;
begin
  Version := TAtlasQueryTimings.Shared.Version;
  FSavedAt := TThread.GetTickCount64;
  if (Version = FSavedVersion) or (Length(TAtlasQueryTimings.Shared.Snapshot) = 0) then
    Exit;
  FSavedVersion := Version;
  try
    ForceDirectories(ExtractFileDir(LastDataFile));
    // Ohne Dateinamen: Die Datei soll ohne Rückfrage in ein Diagnosepaket dürfen (#766).
    TFile.WriteAllText(LastDataFile, Report(False), TEncoding.UTF8);
  except
    on E: Exception do
      TAtlasGuard.Log('Diagnosemodus: letzte Diagnosedaten nicht geschrieben (' + E.ClassName + ')');
  end;
end;

end.
