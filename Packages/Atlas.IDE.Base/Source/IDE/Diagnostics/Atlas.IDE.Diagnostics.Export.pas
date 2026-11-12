unit Atlas.IDE.Diagnostics.Export;

// Befehl „Diagnoselog exportieren“ (#647) für das Menü Atlas und die
// Befehlspalette: sucht die Diagnoselogs des Servers der letzten Tage, zeigt
// die Vorschau und schreibt nach Bestätigung die ZIP-Datei. Ergebnis und
// „nichts gefunden“ gehen in die Meldungsansicht. Vorn steht atlas-info.txt
// mit Atlas-Version, IDE-Version und Plattform (#495). Gibt es letzte Daten
// des Diagnosemodus (#479, ohne Dateinamen geschrieben), kommen sie mit
// (#766).

interface

uses
  System.SysUtils;

type
  TAtlasIdeDiagnosticExport = record
  public
    /// <summary>AMessage: Zeile in die Meldungsansicht.</summary>
    class procedure Execute(const AMessage: TProc<string>); static;
  end;

implementation

uses
  Atlas.IDE.Foundation.DockWindow,
  Atlas.Core.Product.Version,
  Atlas.Core.Updates.Check,
  Atlas.Core.Diagnostics.Export,
  Atlas.UI.Diagnostics.ExportDialog,
  Atlas.UI.Diagnostics.Strings,
  Atlas.IDE.Diagnostics.Timing;

class procedure TAtlasIdeDiagnosticExport.Execute(const AMessage: TProc<string>);
var
  mFiles: TArray<string>;
  mTarget, mInfo, mPlatform: string;
begin
  {$IFDEF WIN64}
  mPlatform := 'Win64';
  {$ELSE}
  mPlatform := 'Win32';
  {$ENDIF}
  mInfo := TAtlasDiagnosticExport.Info(TAtlasPluginVersion.cVersion, TAtlasUpdates.IdeVersion, mPlatform);
  mFiles := TAtlasDiagnosticExport.Files(TAtlasDiagnosticExport.DefaultFolder, TAtlasDiagnosticExport.cDefaultDays,
    Now);
  if FileExists(TAtlasIdeDiagnosticMode.LastDataFile) then
  begin
    mFiles := mFiles + [TAtlasIdeDiagnosticMode.LastDataFile];
  end;
  if Length(mFiles) = 0 then
  begin
    AMessage(TAtlasDiagnosticsStrings.Fmt(TAtlasDiagnosticsTextId.DiagExportEmpty,
      [TAtlasDiagnosticExport.cDefaultDays]));
    Exit;
  end;
  if not TAtlasDiagnosticExportDialog.Execute(TAtlasDiagnosticsStrings.Fmt(TAtlasDiagnosticsTextId.DiagExportHint,
    [TAtlasDiagnosticExport.cDefaultDays]), TAtlasDiagnosticExport.Preview(mFiles, mInfo), mTarget,
    TAtlasIdeDockWindow.ApplyIdeTheme) then
  begin
    Exit;
  end;
  TAtlasDiagnosticExport.WriteZip(mFiles, mTarget, mInfo);
  AMessage(TAtlasDiagnosticsStrings.Fmt(TAtlasDiagnosticsTextId.DiagExportDone, [mTarget]));
end;

end.
