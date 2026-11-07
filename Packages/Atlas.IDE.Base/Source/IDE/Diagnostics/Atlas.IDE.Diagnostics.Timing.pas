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
//   Das Fenster öffnet erst, wenn kein Compile läuft (TAtlasIdeBuildIdleGate):
//   Lädt die IDE das Plugin mitten in einem Gruppen-Build neu, stürzte sie
//   sonst am nächsten Projekt ab.
// - Aus: keine Messung, kein Zeitgeber, Fenster zu, keine Statuszeile; die
//   letzten Diagnosedaten werden noch einmal geschrieben.
// - Letzte Diagnosedaten (für „Problem melden“, #766): der Bericht ohne
//   Dateinamen in %LOCALAPPDATA%\Atlas\Logs\Diagnose\atlas-diagnosemodus.txt.
// - „Bericht kopieren“: Zeitwerte, Atlas- und IDE-Version, Einstellungen mit
//   gekürzten Pfaden, kein Quelltext, Dateinamen nur mit Häkchen.
// - Plugin-Zeiten (Variante A): Mit dem Modus misst TAtlasIdePluginTimings
//   auch Hauptthread je Funktion, Server, Hintergrund und Hänger (abschaltbar
//   mit diagnosticMode.pluginTimings); Bericht und letzte Diagnosedaten
//   enthalten dann den Abschnitt „Plugin-Zeiten“.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.ExtCtrls,
  Atlas.Core.Status.Contract,
  Atlas.Core.Status.Registry,
  Atlas.Core.Status.Lines,
  Atlas.IDE.Foundation.Keys,
  Atlas.IDE.Build.IdleGate,
  Atlas.IDE.Diagnostics.PluginTimings,
  Atlas.UI.Diagnostics.PluginFrame,
  Atlas.Core.Commands.Palette;

type
  TAtlasIdeDiagnosticMode = class
  public const
    /// <summary>Dieselbe Kennung liest die Zustandskachel (#754).</summary>
    cStatusId = TAtlasStatusLines.cDiagnosticModeId;
    cStatusOrder = 3;
    cRefreshMs = 500;
    cSaveEveryMs = 30000;
    /// <summary>Name des Schnellschalters bzw. der Plugin-Einstellung.</summary>
    cToggleKey = 'DiagnosticMode';
  private class var
    FInstance: TAtlasIdeDiagnosticMode;
  private
    FRegistry: IAtlasStatusRegistry;
    FLine: TAtlasStatusLine;
    FLineRef: IAtlasStatusItem;
    FKey: TAtlasIdeKeyBinding;
    FTimer: TTimer;
    /// <summary>Öffnet das Fenster erst ohne laufenden Compile.</summary>
    FGate: TAtlasIdeBuildIdleGate;
    FActive: Boolean;
    FPlugin: TAtlasIdePluginTimings;
    FShownVersion: Integer;
    FSavedVersion: Integer;
    FSavedAt: UInt64;
    procedure TimerTick(Sender: TObject);
    procedure FrameCreated(AFrame: TAtlasDiagnosticsFrame);
    procedure Refresh(AFrame: TAtlasDiagnosticsFrame; AForce: Boolean);
    /// <summary>Stand von Vervollständigung und Plugin-Zeiten; ändert sich mit jeder neuen Messung.</summary>
    class function DataVersion: Integer; static;
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
  FPlugin := TAtlasIdePluginTimings.Create;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := cRefreshMs;
  FTimer.OnTimer := TimerTick;
  FGate := TAtlasIdeBuildIdleGate.Create(TAtlasFeature.Settings);
  TAtlasIdeTimingWindow.OnFrame :=
    procedure(AFrame: TAtlasDiagnosticsFrame)
    begin
      if FInstance <> nil then
      begin
        FInstance.FrameCreated(AFrame);
      end;
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
  begin
    FInstance := nil;
  end;
  // Erst abmelden, dann freigeben (#493).
  FreeAndNil(FKey);
  FreeAndNil(FGate);
  FTimer.Free;
  if FActive then
  begin
    SaveLastData;
  end;
  FActive := False;
  TAtlasQueryTimings.Enabled := False;
  FPlugin.Apply(False, nil);
  RemoveStatusLine;
  TAtlasIdeTimingWindow.Release;
  FPlugin.Free;
  inherited;
end;

procedure TAtlasIdeDiagnosticMode.Rebind;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  FKey.Rebind(Word(mSettings.DiagnosticModeKey), mSettings.DiagnosticModeKeyPriority,
    TAtlasStrings.Text(TAtlasTextId.SettingsDiagnosticModeKey));
end;

class procedure TAtlasIdeDiagnosticMode.Toggle;
begin
  TAtlasGuard.Run(TAtlasFeature.Settings,
    procedure
    begin
      // Dieselbe Einstellung wie Optionsseite und Schnellschalter; Update meldet OnChanged → ApplySettings.
      TAtlasIdeQuickToggles.Switch(cToggleKey);
    end);
end;

procedure TAtlasIdeDiagnosticMode.ApplySettings;
var
  mWanted: Boolean;
begin
  mWanted := TAtlasIdeSettings.Current.DiagnosticMode;
  // Schalter und Schwelle der Plugin-Zeiten gelten auch bei unverändertem Modus.
  FPlugin.Apply(mWanted, TAtlasIdeTimingWindow.ExistingFrame);
  if mWanted = FActive then
  begin
    Exit;
  end;
  FActive := mWanted;
  TAtlasQueryTimings.Enabled := mWanted;
  if mWanted then
  begin
    TAtlasGuard.Log('Diagnosemodus an (#479)');
    FShownVersion := -1;
    FSavedAt := TThread.GetTickCount64;
    FTimer.Enabled := True;
    AddStatusLine;
    // Nicht mitten im Laden des Packages, im Optionsdialog oder während eines Compiles andocken: Nach dem
    // Neuladen mitten im Gruppen-Build ließe ein neues Dockfenster die IDE am nächsten Projekt abstürzen.
    FGate.Run(
      procedure
      begin
        if (FInstance <> nil) and FInstance.FActive then
        begin
          FInstance.ShowWindow;
        end;
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
  begin
    Exit;
  end;
  FLine := TAtlasStatusLine.Create(FRegistry, cStatusId, cStatusOrder,
    procedure
    begin
      if FInstance <> nil then
      begin
        FInstance.ShowWindow;
      end;
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
  begin
    Exit;
  end;
  if FRegistry <> nil then
  begin
    FRegistry.Remove(cStatusId);
  end;
  FLine := nil;
  FLineRef := nil;
end;

procedure TAtlasIdeDiagnosticMode.ShowWindow;
var
  mFrame: TAtlasDiagnosticsFrame;
begin
  mFrame := TAtlasIdeTimingWindow.Show;
  if mFrame <> nil then
  begin
    Refresh(mFrame, True);
  end;
end;

function CopyHandler: TProc<Boolean>;
begin
  // Eigene Routine: Die Methodenreferenz fängt nur AFileNames ein (kein gemeinsamer Rahmen).
  Result :=
    procedure(AFileNames: Boolean)
    var
      mFileNames: Boolean;
    begin
      mFileNames := AFileNames;
      TAtlasGuard.Run(TAtlasFeature.Settings,
        procedure
        begin
          if TAtlasIdeDiagnosticMode.FInstance <> nil then
          begin
            TAtlasIdeDiagnosticMode.FInstance.CopyReport(mFileNames);
          end;
        end);
    end;
end;

procedure TAtlasIdeDiagnosticMode.FrameCreated(AFrame: TAtlasDiagnosticsFrame);
var
  mCopy: TProc<Boolean>;
begin
  mCopy := CopyHandler();
  AFrame.Completion.OnCopy := mCopy;
  AFrame.Bar.OnCopy :=
    procedure
    begin
      mCopy(False);
    end;
  TAtlasIdePluginTimings.Wire(AFrame);
  Refresh(AFrame, True);
end;

class function TAtlasIdeDiagnosticMode.DataVersion: Integer;
begin
  // Beide Zähler steigen nur; die Summe ändert sich, sobald sich einer ändert.
  Result := TAtlasQueryTimings.Shared.Version + TAtlasIdePluginTimings.Version;
end;

procedure TAtlasIdeDiagnosticMode.Refresh(AFrame: TAtlasDiagnosticsFrame; AForce: Boolean);
var
  mVersion: Integer;
begin
  if AFrame = nil then
  begin
    Exit;
  end;
  FPlugin.Refresh(AFrame, AForce);
  mVersion := TAtlasQueryTimings.Shared.Version;
  if AForce then
  begin
    AFrame.SetColors(TAtlasIdeStyle.Colors);
  end
  else if mVersion = FShownVersion then
  begin
    Exit;
  end;
  FShownVersion := mVersion;
  AFrame.Completion.SetQueries(TAtlasQueryTimings.Shared.Snapshot);
end;

procedure TAtlasIdeDiagnosticMode.TimerTick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Settings,
    procedure
    begin
      if TAtlasIdeTimingWindow.Visible then
      begin
        Refresh(TAtlasIdeTimingWindow.ExistingFrame, False);
      end;
      if (DataVersion <> FSavedVersion) and
        (TThread.GetTickCount64 - FSavedAt >= cSaveEveryMs) then
      begin
        SaveLastData;
      end;
    end);
end;

procedure TAtlasIdeDiagnosticMode.ThemeChanged;
begin
  TAtlasIdeTimingWindow.ApplyTheme;
  Refresh(TAtlasIdeTimingWindow.ExistingFrame, True);
end;

procedure TAtlasIdeDiagnosticMode.CopyReport(AFileNames: Boolean);
var
  mFrame: TAtlasDiagnosticsFrame;
begin
  Clipboard.AsText := Report(AFileNames);
  mFrame := TAtlasIdeTimingWindow.ExistingFrame;
  if mFrame <> nil then
  begin
    mFrame.Completion.ShowNote(TAtlasStrings.Text(TAtlasTextId.DiagnosticCopied));
    mFrame.Bar.ShowNote(TAtlasStrings.Text(TAtlasTextId.DiagnosticCopied));
  end;
end;

procedure TAtlasIdeDiagnosticMode.RegisterCommands(const ARegistry: IAtlasCommandRegistry);
begin
  ARegistry.RegisterCommand('Atlas.DiagnosticWindow', TAtlasStrings.Text(TAtlasTextId.DiagnosticPaletteShow), '',
    procedure
    begin
      if FInstance = nil then
      begin
        Exit;
      end;
      if FInstance.FActive then
      begin
        FInstance.ShowWindow;
      end
      else
      begin
        Toggle;
      end;
    end);
end;

function SettingsJson: string;
var
  mValues: TJSONObject;
begin
  mValues := TAtlasMemorySettingsStore.FromSettings(TAtlasIdeSettings.Current).ToJson;
  try
    Result := mValues.Format(2);
  finally
    mValues.Free;
  end;
end;

class function TAtlasIdeDiagnosticMode.Report(AFileNames: Boolean): string;
var
  mInput: TAtlasTimingReportInput;
begin
  mInput := Default(TAtlasTimingReportInput);
  mInput.AtlasVersion := TAtlasPluginVersion.cVersion;
  mInput.IdeVersion := TAtlasUpdates.IdeVersion;
  {$IFDEF WIN64}
  mInput.Platform := 'Win64';
  {$ELSE}
  mInput.Platform := 'Win32';
  {$ENDIF}
  mInput.Settings := SettingsJson;
  mInput.Identity := [GetEnvironmentVariable('USERNAME'), GetEnvironmentVariable('COMPUTERNAME'),
    GetEnvironmentVariable('USERDOMAIN')];
  mInput.FileNames := AFileNames;
  mInput.Created := Now;
  mInput.Plugin := TAtlasIdePluginTimings.Report;
  Result := TAtlasTimingReport.Build(TAtlasQueryTimings.Shared.Snapshot, mInput);
end;

class function TAtlasIdeDiagnosticMode.LastDataFile: string;
begin
  Result := TPath.Combine(TAtlasDiagnosticExport.DefaultFolder, TAtlasTimingReport.cFileName);
end;

procedure TAtlasIdeDiagnosticMode.SaveLastData;
var
  mVersion: Integer;
begin
  mVersion := DataVersion;
  FSavedAt := TThread.GetTickCount64;
  if (mVersion = FSavedVersion) or ((Length(TAtlasQueryTimings.Shared.Snapshot) = 0) and
    (TAtlasIdePluginTimings.Version = 0)) then
  begin
    Exit;
  end;
  FSavedVersion := mVersion;
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
