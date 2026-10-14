unit Atlas.IDE.Diagnostics.Export;

// Befehl „Diagnoselog exportieren“ (#647) für das Menü Atlas und die
// Befehlspalette: sucht die Diagnoselogs des Servers der letzten Tage, zeigt
// die Vorschau und schreibt nach Bestätigung die ZIP-Datei. Ergebnis und
// „nichts gefunden“ gehen in die Meldungsansicht.

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
  Atlas.Core.Diagnostics.Export,
  Atlas.UI.Diagnostics.ExportDialog,
  Atlas.UI.Strings;

class procedure TAtlasIdeDiagnosticExport.Execute(const AMessage: TProc<string>);
var
  Files: TArray<string>;
  Target: string;
begin
  Files := TAtlasDiagnosticExport.Files(TAtlasDiagnosticExport.DefaultFolder, TAtlasDiagnosticExport.DefaultDays, Now);
  if Length(Files) = 0 then
  begin
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.DiagExportEmpty, [TAtlasDiagnosticExport.DefaultDays]));
    Exit;
  end;
  if not TAtlasDiagnosticExportDialog.Execute(TAtlasStrings.Fmt(TAtlasTextId.DiagExportHint,
    [TAtlasDiagnosticExport.DefaultDays]), TAtlasDiagnosticExport.Preview(Files), Target) then
    Exit;
  TAtlasDiagnosticExport.WriteZip(Files, Target);
  AMessage(TAtlasStrings.Fmt(TAtlasTextId.DiagExportDone, [Target]));
end;

end.
