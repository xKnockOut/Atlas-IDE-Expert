unit Atlas.IDE.Diagnostics.ServerPackage;

// „Diagnosepaket erstellen …“ im Fenster „Atlas-Server“ (#1356): holt im
// Hintergrund den Fehlerbericht des Servers (#108, atlas.server.bugReport)
// und danach dessen Dateien (atlas.server.diagnosticPackage: Status,
// Protokoll der Sitzung, Trace der letzten Minuten mit --trace), baut daraus
// mit dem Bericht des Plugins die Dateien der ZIP-Datei, zeigt sie in der
// Vorschau (dieselbe wie beim Fehlerbericht) und schreibt nach Bestätigung
// die ZIP-Datei. Anonymisiert nach diagnostics.bugReport.anonymize;
// Zugangsdaten entfernt der Server immer. Ein gestoppter Server wird nicht
// gestartet; dann enthält das Paket nur den Bericht. Ein zweiter Aufruf
// während des Sammelns wird verworfen.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.IDE.Diagnostics.BugReport;

type
  TAtlasIdeServerPackage = record
  private class var
    FBusy: Boolean;
  private
    class procedure Finish(const AReport: string; AAnonymize: Boolean; const AServerAnswer: TJSONValue;
      const AMessage: TProc<string>); static;
  public
    class procedure Execute(const AServer: TAtlasServerCommandWithArguments; const AMessage: TProc<string>); static;
  end;

implementation

uses
  Atlas.Core.Diagnostics.BugReport,
  Atlas.Core.Diagnostics.Package,
  Atlas.Core.Diagnostics.ServerPackage,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Diagnostics.ExportDialog,
  Atlas.UI.Strings;

class procedure TAtlasIdeServerPackage.Execute(const AServer: TAtlasServerCommandWithArguments;
  const AMessage: TProc<string>);
var
  mInput: TAtlasBugReportInput;
  mMessage: TProc<string>;
  mServer: TAtlasServerCommandWithArguments;
begin
  if FBusy then
    Exit;
  mMessage := AMessage;
  mServer := AServer;
  mInput := TAtlasIdeBugReport.Collect;
  if not Assigned(mServer) then
  begin
    Finish(TAtlasIdeBugReport.ReportText(mInput, nil), mInput.Anonymize, nil, mMessage);
    Exit;
  end;
  FBusy := True;
  mMessage(TAtlasStrings.Text(TAtlasTextId.ServerPackageCollecting));
  try
    mServer(TAtlasBugReport.ServerCommand, TAtlasBugReport.ServerArguments(mInput),
      procedure(AReport: TJSONValue)
      var
        mReport: string;
      begin
        // Die Antwort gibt der Aufrufer nach diesem Aufruf frei: gleich zum Text machen.
        mReport := TAtlasIdeBugReport.ReportText(mInput, AReport);
        try
          mServer(TAtlasServerDiagnostics.Command, TAtlasServerDiagnostics.ServerArguments(mInput.Anonymize),
            procedure(AFiles: TJSONValue)
            begin
              FBusy := False;
              TAtlasGuard.Run(TAtlasFeature.Menu,
                procedure
                begin
                  Finish(mReport, mInput.Anonymize, AFiles, mMessage);
                end);
            end);
        except
          FBusy := False;
          raise;
        end;
      end);
  except
    FBusy := False;
    raise;
  end;
end;

class procedure TAtlasIdeServerPackage.Finish(const AReport: string; AAnonymize: Boolean;
  const AServerAnswer: TJSONValue; const AMessage: TProc<string>);
var
  mServerFiles, mFiles: TAtlasPackageFiles;
  mNote, mTarget: string;
begin
  mServerFiles := TAtlasServerDiagnostics.ServerFiles(AServerAnswer);
  if Length(mServerFiles) = 0 then
    AMessage(TAtlasStrings.Text(TAtlasTextId.ServerPackageNoServer));
  mFiles := TAtlasServerDiagnostics.Build(AReport, mServerFiles);
  if AAnonymize then
    mNote := TAtlasStrings.Text(TAtlasTextId.BugReportAnonymized)
  else
    mNote := TAtlasStrings.Text(TAtlasTextId.BugReportPlain);
  if not TAtlasDiagnosticExportDialog.Execute(TAtlasStrings.Text(TAtlasTextId.ServerPackageTitle),
    TAtlasStrings.Fmt(TAtlasTextId.ServerPackageHint, [mNote]),
    TAtlasServerDiagnostics.Preview(mFiles, TAtlasStrings.Text(TAtlasTextId.ServerPackageCut)),
    TAtlasServerDiagnostics.ZipName(Now), TAtlasStrings.Text(TAtlasTextId.ServerPackageFilter), 'zip',
    mTarget) then
    Exit;
  TAtlasDiagnosticPackage.WriteZip(mFiles, mTarget);
  AMessage(TAtlasStrings.Fmt(TAtlasTextId.ServerPackageDone, [mTarget]));
end;

end.
