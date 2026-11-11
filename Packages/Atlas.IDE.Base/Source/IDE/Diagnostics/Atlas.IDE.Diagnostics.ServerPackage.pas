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
  Atlas.IDE.Foundation.DockWindow,
  Atlas.Core.Diagnostics.BugReport,
  Atlas.Core.Diagnostics.Package,
  Atlas.Core.Diagnostics.ServerPackage,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Diagnostics.ExportDialog,
  Atlas.UI.Diagnostics.Strings;

class procedure TAtlasIdeServerPackage.Execute(const AServer: TAtlasServerCommandWithArguments;
  const AMessage: TProc<string>);
var
  mInput: TAtlasBugReportInput;
  mMessage: TProc<string>;
  mServer: TAtlasServerCommandWithArguments;
begin
  if FBusy then
  begin
    Exit;
  end;
  mMessage := AMessage;
  mServer := AServer;
  mInput := TAtlasIdeBugReport.Collect;
  if not Assigned(mServer) then
  begin
    Finish(TAtlasIdeBugReport.ReportText(mInput, nil), mInput.Anonymize, nil, mMessage);
    Exit;
  end;
  FBusy := True;
  mMessage(TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.ServerPackageCollecting));
  try
    mServer(TAtlasBugReport.cServerCommand, TAtlasBugReport.ServerArguments(mInput),
      procedure(AReport: TJSONValue)
      var
        mReport: string;
      begin
        // Die Antwort gibt der Aufrufer nach diesem Aufruf frei: gleich zum Text machen.
        mReport := TAtlasIdeBugReport.ReportText(mInput, AReport);
        try
          mServer(TAtlasServerDiagnostics.cCommand, TAtlasServerDiagnostics.ServerArguments(mInput.Anonymize),
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
  begin
    AMessage(TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.ServerPackageNoServer));
  end;
  mFiles := TAtlasServerDiagnostics.Build(AReport, mServerFiles);
  if AAnonymize then
  begin
    mNote := TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.BugReportAnonymized);
  end
  else
  begin
    mNote := TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.BugReportPlain);
  end;
  if not TAtlasDiagnosticExportDialog.Execute(TAtlasExportDialogTexts.Create(
    TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.ServerPackageTitle),
    TAtlasDiagnosticsStrings.Fmt(TAtlasDiagnosticsTextId.ServerPackageHint, [mNote]),
    TAtlasServerDiagnostics.Preview(mFiles, TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.ServerPackageCut)),
    TAtlasServerDiagnostics.ZipName(Now), TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.ServerPackageFilter),
    'zip'),
    mTarget, TAtlasIdeDockWindow.ApplyIdeTheme) then
  begin
    Exit;
  end;
  TAtlasDiagnosticPackage.WriteZip(mFiles, mTarget);
  AMessage(TAtlasDiagnosticsStrings.Fmt(TAtlasDiagnosticsTextId.ServerPackageDone, [mTarget]));
end;

end.
