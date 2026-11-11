unit Atlas.IDE.Diagnostics.PluginTimings;

// Plugin-Zeiten des Diagnose-Fensters in der IDE (Variante A):
// - Apply schaltet die Messung (TAtlasPluginTimings.Enabled) nach dem
//   Diagnosemodus und der Einstellung diagnosticMode.pluginTimings (Vorgabe an)
//   und übernimmt die Schwelle diagnosticMode.slowThresholdMs (Vorgabe 16 ms).
//   Beim Einschalten beginnt die Messung neu.
// - Wire verbindet die Knöpfe des Frames: Anhalten/Weiter, Zurücksetzen,
//   Funktion bis zum Neustart ausschalten (TAtlasGuard.Disable) und Zeile
//   kopieren (Zwischenablage). „Bericht kopieren“ verbindet der Diagnosemodus.
// - Refresh füllt den Frame bei neuem Stand (oder erzwungen).
// - Report liefert den Abschnitt für Bericht und letzte Diagnosedaten; ''
//   bei ausgeschalteter Messung.
// - Modale Dialoge (Application.OnModalBegin/OnModalEnd) meldet die Instanz
//   dem Rekorder: Ihre Zeit zählt nicht als Belegung des Hauptthreads.
// - Ebenso Menüs und Kontextmenüs (TrackPopupMenu) sowie Verschieben und
//   Größe ändern von Fenstern: Ein Hook (WH_CALLWNDPROC) des Hauptthreads
//   sieht WM_ENTERMENULOOP/WM_EXITMENULOOP und WM_ENTERSIZEMOVE/
//   WM_EXITSIZEMOVE. Er ist nur installiert, solange gemessen wird.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  Vcl.AppEvnts,
  Atlas.UI.Diagnostics.PluginFrame;

type
  TAtlasIdePluginTimings = class
  private
    FShownVersion: Integer;
    FEvents: TApplicationEvents;
    procedure ModalBegin(Sender: TObject);
    procedure ModalEnd(Sender: TObject);
    /// <summary>Hook für die eigenen Nachrichtenschleifen nur bei laufender Messung (AOn).</summary>
    class procedure HookLoops(AOn: Boolean); static;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Messung nach dem Diagnosemodus (AModeOn) und den Einstellungen; Frame nach Bedarf anpassen.
    /// </summary>
    procedure Apply(AModeOn: Boolean; AFrame: TAtlasDiagnosticsFrame);
    /// <summary>Knöpfe und Kontextmenü eines neuen Frames verbinden.</summary>
    class procedure Wire(AFrame: TAtlasDiagnosticsFrame); static;
    /// <summary>Frame mit dem aktuellen Stand füllen, ohne AForce nur bei neuem Stand.</summary>
    procedure Refresh(AFrame: TAtlasDiagnosticsFrame; AForce: Boolean);
    /// <summary>Zählt jede Änderung der Messung; 0, solange sie aus ist.</summary>
    class function Version: Integer; static;
    /// <summary>Abschnitt „Plugin-Zeiten“; '' bei ausgeschalteter Messung.</summary>
    class function Report: string; static;
  end;

implementation

uses
  Vcl.Clipbrd,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.TimeLimit,
  Atlas.Core.Diagnostics.PluginTimings,
  Atlas.Core.Diagnostics.PluginReport,
  Atlas.Core.Settings.Plugin,
  Atlas.IDE.Foundation.Settings;

const
  // Protokollzeile (nicht übersetzt, wie das übrige Protokoll).
  cLogTimingsOn = 'Diagnosemodus: Plugin-Zeiten werden gemessen';

var
  LoopHook: HHOOK = 0;

/// <summary>Menü, Kontextmenü, Verschieben: Beginn und Ende der Schleife an den Rekorder.</summary>
function LoopProc(ACode: Integer; AWParam: WPARAM; ALParam: LPARAM): LRESULT; stdcall;
var
  mChange: Integer;
begin
  try
    if (ACode = HC_ACTION) and TAtlasPluginTimings.Enabled then
    begin
      mChange := TAtlasMessageLoop.Change(PCWPStruct(ALParam).message);
      if mChange > 0 then
      begin
        TAtlasPluginTimings.Shared.ModalBegin;
      end
      else if mChange < 0 then
      begin
        TAtlasPluginTimings.Shared.ModalEnd;
      end;
    end;
  except
    // Keine Exception an die IDE (#493).
    on E: Exception do
      TAtlasGuard.Log('Diagnosemodus, Nachrichtenschleifen: ' + TAtlasGuard.ErrorText(E));
  end;
  Result := CallNextHookEx(LoopHook, ACode, AWParam, ALParam);
end;

procedure Fill(AFrame: TAtlasDiagnosticsFrame);
begin
  AFrame.SetSnapshot(TAtlasPluginTimings.Shared.Snapshot, TAtlasTimeLimit.BusyCount);
end;

{ TAtlasIdePluginTimings }

constructor TAtlasIdePluginTimings.Create;
begin
  inherited Create;
  FShownVersion := -1;
  FEvents := TApplicationEvents.Create(nil);
  FEvents.OnModalBegin := ModalBegin;
  FEvents.OnModalEnd := ModalEnd;
end;

destructor TAtlasIdePluginTimings.Destroy;
begin
  HookLoops(False);
  FEvents.Free;
  inherited;
end;

procedure TAtlasIdePluginTimings.ModalBegin(Sender: TObject);
begin
  if TAtlasPluginTimings.Enabled then
  begin
    TAtlasPluginTimings.Shared.ModalBegin;
  end;
end;

procedure TAtlasIdePluginTimings.ModalEnd(Sender: TObject);
begin
  if TAtlasPluginTimings.Enabled then
  begin
    TAtlasPluginTimings.Shared.ModalEnd;
  end;
end;

class procedure TAtlasIdePluginTimings.HookLoops(AOn: Boolean);
begin
  if AOn and (LoopHook = 0) then
  begin
    // Nur der Hauptthread: Dort laufen die Aufrufe, die der Rekorder misst.
    LoopHook := SetWindowsHookEx(WH_CALLWNDPROC, @LoopProc, 0, MainThreadID);
  end
  else if not AOn and (LoopHook <> 0) then
  begin
    UnhookWindowsHookEx(LoopHook);
    LoopHook := 0;
  end;
end;

procedure TAtlasIdePluginTimings.Apply(AModeOn: Boolean; AFrame: TAtlasDiagnosticsFrame);
var
  mSettings: TAtlasPluginSettings;
  mWanted: Boolean;
begin
  mSettings := TAtlasIdeSettings.Current;
  mWanted := AModeOn and mSettings.DiagnosticPluginTimings;
  if mWanted and not TAtlasPluginTimings.Enabled then
  begin
    TAtlasPluginTimings.Shared.Reset;
    TAtlasGuard.Log(cLogTimingsOn);
  end;
  TAtlasPluginTimings.Shared.ThresholdMs := mSettings.DiagnosticSlowMs;
  TAtlasPluginTimings.Enabled := mWanted;
  HookLoops(mWanted);
  if AFrame <> nil then
  begin
    AFrame.SetPluginTimings(mWanted);
    Refresh(AFrame, True);
  end;
end;

class procedure TAtlasIdePluginTimings.Wire(AFrame: TAtlasDiagnosticsFrame);
var
  mFrame: TAtlasDiagnosticsFrame;
begin
  mFrame := AFrame;
  mFrame.SetPluginTimings(TAtlasPluginTimings.Enabled);
  mFrame.Bar.OnPause :=
    procedure(APause: Boolean)
    begin
      TAtlasPluginTimings.Shared.Paused := APause;
      Fill(mFrame);
    end;
  mFrame.Bar.OnReset :=
    procedure
    begin
      TAtlasPluginTimings.Shared.Reset;
      Fill(mFrame);
    end;
  mFrame.MainThread.OnDisable :=
    procedure(AFeature: TAtlasFeature)
    begin
      TAtlasGuard.Disable(AFeature);
      mFrame.FeatureDisabled(AFeature);
    end;
  mFrame.MainThread.OnCopyText :=
    procedure(AText: string)
    begin
      Clipboard.AsText := AText;
    end;
end;

procedure TAtlasIdePluginTimings.Refresh(AFrame: TAtlasDiagnosticsFrame; AForce: Boolean);
var
  mVersion: Integer;
begin
  if (AFrame = nil) or not TAtlasPluginTimings.Enabled then
  begin
    Exit;
  end;
  mVersion := Version;
  if not AForce and (mVersion = FShownVersion) then
  begin
    Exit;
  end;
  FShownVersion := mVersion;
  Fill(AFrame);
end;

class function TAtlasIdePluginTimings.Version: Integer;
begin
  Result := 0;
  if TAtlasPluginTimings.Enabled then
  begin
    Result := TAtlasPluginTimings.Shared.Version;
  end;
end;

class function TAtlasIdePluginTimings.Report: string;
begin
  Result := '';
  if TAtlasPluginTimings.Enabled then
  begin
    Result := TAtlasPluginReport.Build(TAtlasPluginTimings.Shared.Snapshot);
  end;
end;

initialization

finalization
  if LoopHook <> 0 then
  begin
    UnhookWindowsHookEx(LoopHook);
  end;

end.
