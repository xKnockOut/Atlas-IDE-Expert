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
  Atlas.Core.Product.Version,
  Atlas.Core.Updates.Check,
  Atlas.Core.Diagnostics.Export,
  Atlas.UI.Diagnostics.ExportDialog,
  Atlas.UI.Strings,
  Atlas.IDE.Diagnostics.Timing;

class procedure TAtlasIdeDiagnosticExport.Execute(const AMessage: TProc<string>);
var
  Files: TArray<string>;
  Target, Info, Platform: string;
begin
  {$IFDEF WIN64}
  Platform := 'Win64';
  {$ELSE}
  Platform := 'Win32';
  {$ENDIF}
  Info := TAtlasDiagnosticExport.Info(TAtlasPluginVersion.Version, TAtlasUpdates.IdeVersion, Platform);
  Files := TAtlasDiagnosticExport.Files(TAtlasDiagnosticExport.DefaultFolder, TAtlasDiagnosticExport.DefaultDays, Now);
  if FileExists(TAtlasIdeDiagnosticMode.LastDataFile) then
    Files := Files + [TAtlasIdeDiagnosticMode.LastDataFile];
  if Length(Files) = 0 then
  begin
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.DiagExportEmpty, [TAtlasDiagnosticExport.DefaultDays]));
    Exit;
  end;
  if not TAtlasDiagnosticExportDialog.Execute(TAtlasStrings.Fmt(TAtlasTextId.DiagExportHint,
    [TAtlasDiagnosticExport.DefaultDays]), TAtlasDiagnosticExport.Preview(Files, Info), Target) then
    Exit;
  TAtlasDiagnosticExport.WriteZip(Files, Target, Info);
  AMessage(TAtlasStrings.Fmt(TAtlasTextId.DiagExportDone, [Target]));
end;

end.
