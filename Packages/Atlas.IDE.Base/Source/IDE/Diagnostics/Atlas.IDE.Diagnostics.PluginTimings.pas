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

interface

uses
  System.SysUtils,
  Atlas.UI.Diagnostics.PluginFrame;

type
  TAtlasIdePluginTimings = class
  private
    FShownVersion: Integer;
  public
    constructor Create;
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

procedure Fill(AFrame: TAtlasDiagnosticsFrame);
begin
  AFrame.SetSnapshot(TAtlasPluginTimings.Shared.Snapshot, TAtlasTimeLimit.BusyCount);
end;

{ TAtlasIdePluginTimings }

constructor TAtlasIdePluginTimings.Create;
begin
  inherited Create;
  FShownVersion := -1;
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
    TAtlasGuard.Log('Diagnosemodus: Plugin-Zeiten werden gemessen');
  end;
  TAtlasPluginTimings.Shared.ThresholdMs := mSettings.DiagnosticSlowMs;
  TAtlasPluginTimings.Enabled := mWanted;
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

end.
