unit Atlas.IDE.Diagnostics.BugReport;

// Befehl „Fehlerbericht erstellen…“ (#108) für Menü Atlas, Befehlspalette und
// das Fenster des abgesicherten Starts: holt den Bericht des laufenden
// Servers (atlas.server.bugReport; ein gestoppter Server wird dafür nicht
// gestartet), ergänzt Plugin- und IDE-Version, Einstellungen, atlas.log und
// das Ende von server-stderr.log,
// zeigt die Vorschau und schreibt nach Bestätigung eine Markdown-Datei.
// Die Meldungsansicht nennt Datei und Adresse für ein neues Issue.
// Der Bericht des Servers kommt im Hintergrund (#874); bis dahin bleibt die IDE
// bedienbar, die Meldungsansicht sagt „wird zusammengestellt“, und ein zweiter
// Aufruf in der Zeit wird verworfen.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Diagnostics.BugReport;

type
  /// <summary>Befehl mit Argumenten (JSON-Array) an den laufenden Server im Hintergrund (#874); ADone im
  /// Hauptthread mit der Antwort, nil ohne Server oder bei Fehler. Den Wert gibt der Aufrufer von ADone frei.</summary>
  TAtlasServerCommandWithArguments = reference to procedure(const ACommand, AArgumentsJson: string;
    const ADone: TProc<TJSONValue>);

  TAtlasIdeBugReport = record
  private class var
    /// <summary>Ein Bericht wartet auf den Server.</summary>
    FBusy: Boolean;
  private
    /// <summary>Bericht bauen, Vorschau zeigen, nach Bestätigung schreiben (Hauptthread).</summary>
    class procedure Finish(const AInput: TAtlasBugReportInput; const AAnswer: TJSONValue;
      const AMessage: TProc<string>); static;
  public
    class procedure Execute(const AServer: TAtlasServerCommandWithArguments; const AMessage: TProc<string>); static;
    /// <summary>Eingaben des Berichts ohne den Teil des Servers (auch für das Diagnosepaket, #1356).</summary>
    class function Collect: TAtlasBugReportInput; static;
    /// <summary>Bericht aus AInput und der Antwort von atlas.server.bugReport (nil = Server fehlt).</summary>
    class function ReportText(const AInput: TAtlasBugReportInput; const AAnswer: TJSONValue): string; static;
    /// <summary>Ordner der Projekte der geöffneten Projektgruppe (für &lt;ws&gt;); auch für „Problem melden“
    /// (#766).</summary>
    class function ProjectRoots: TArray<string>; static;
    /// <summary>Einstellungen des Plugins als JSON.</summary>
    class function SettingsJson: string; static;
    /// <summary>Benutzer-, Rechner- und Domänenname, die anonymisiert werden.</summary>
    class function Identity: TArray<string>; static;
  end;

implementation

uses
  Atlas.IDE.Foundation.DockWindow,
  System.IOUtils,
  ToolsAPI,
  Atlas.Core.Product.Version,
  Atlas.Core.Updates.Check,
  Atlas.Core.Settings.History,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Lsp.Crashes,
  Atlas.UI.Diagnostics.ExportDialog,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.Settings;

class function TAtlasIdeBugReport.ProjectRoots: TArray<string>;
var
  mModules: IOTAModuleServices;
  mGroup: IOTAProjectGroup;
  mIndex: Integer;
  mFolder: string;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    Exit;
  end;
  mGroup := mModules.MainProjectGroup;
  if mGroup = nil then
  begin
    Exit;
  end;
  mFolder := ExtractFileDir(mGroup.FileName);
  if mFolder <> '' then
  begin
    Result := Result + [mFolder];
  end;
  for mIndex := 0 to mGroup.ProjectCount - 1 do
  begin
    mFolder := ExtractFileDir(mGroup.Projects[mIndex].FileName);
    if mFolder <> '' then
    begin
      Result := Result + [mFolder];
    end;
  end;
end;

class function TAtlasIdeBugReport.SettingsJson: string;
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

class function TAtlasIdeBugReport.Identity: TArray<string>;
begin
  Result := [GetEnvironmentVariable('USERNAME'), GetEnvironmentVariable('COMPUTERNAME'),
    GetEnvironmentVariable('USERDOMAIN')];
end;

class function TAtlasIdeBugReport.Collect: TAtlasBugReportInput;
begin
  Result := Default(TAtlasBugReportInput);
  Result.PluginVersion := TAtlasPluginVersion.cVersion;
  Result.IdeVersion := TAtlasUpdates.IdeVersion;
  {$IFDEF WIN64}
  Result.Platform := 'Win64';
  {$ELSE}
  Result.Platform := 'Win32';
  {$ENDIF}
  Result.Anonymize := TAtlasIdeSettings.Current.BugReportAnonymize;
  Result.PluginLogNames := TAtlasIdeSettings.Current.LogNames;
  Result.Created := Now;
  Result.Roots := ProjectRoots;
  Result.Identity := Identity;
  Result.Settings := SettingsJson;
  Result.Experimental := TAtlasIdeSettings.ActiveExperimental;
  Result.PluginLog := TAtlasBugReport.Tail(TPath.Combine(TAtlasRotatingLog.DefaultFolder, 'atlas.log'),
    TAtlasBugReport.cLogLines);
  Result.ServerErrorOutput := TAtlasBugReport.Tail(TAtlasServerExits.StderrFileName(TAtlasRotatingLog.DefaultFolder),
    TAtlasBugReport.cErrorOutputLines);
end;

class function TAtlasIdeBugReport.ReportText(const AInput: TAtlasBugReportInput; const AAnswer: TJSONValue): string;
var
  mInput: TAtlasBugReportInput;
begin
  mInput := AInput;
  if (AAnswer is TJSONObject) and (TJSONObject(AAnswer).GetValue('text') is TJSONString) then
  begin
    mInput.ServerReport := TJSONObject(AAnswer).GetValue('text').Value;
  end
  else
  begin
    mInput.ServerMissing := TAtlasStrings.Text(TAtlasTextId.BugReportNoServer);
  end;
  Result := TAtlasBugReport.Build(mInput);
end;

class procedure TAtlasIdeBugReport.Execute(const AServer: TAtlasServerCommandWithArguments;
  const AMessage: TProc<string>);
var
  mInput: TAtlasBugReportInput;
  mMessage: TProc<string>;
begin
  if FBusy then
  begin
    Exit;
  end;
  mMessage := AMessage;
  mInput := Collect;
  if not Assigned(AServer) then
  begin
    Finish(mInput, nil, mMessage);
    Exit;
  end;
  FBusy := True;
  mMessage(TAtlasStrings.Text(TAtlasTextId.BugReportCollecting));
  try
    AServer(TAtlasBugReport.cServerCommand, TAtlasBugReport.ServerArguments(mInput),
      procedure(AAnswer: TJSONValue)
      begin
        FBusy := False;
        TAtlasGuard.Run(TAtlasFeature.Menu,
          procedure
          begin
            Finish(mInput, AAnswer, mMessage);
          end);
      end);
  except
    FBusy := False;
    raise;
  end;
end;

class procedure TAtlasIdeBugReport.Finish(const AInput: TAtlasBugReportInput; const AAnswer: TJSONValue;
  const AMessage: TProc<string>);
var
  mReport, mTarget, mNote: string;
begin
  mReport := ReportText(AInput, AAnswer);
  if AInput.Anonymize then
  begin
    mNote := TAtlasStrings.Text(TAtlasTextId.BugReportAnonymized);
  end
  else
  begin
    mNote := TAtlasStrings.Text(TAtlasTextId.BugReportPlain);
  end;
  if not TAtlasDiagnosticExportDialog.Execute(TAtlasExportDialogTexts.Create(
    TAtlasStrings.Text(TAtlasTextId.BugReportTitle),
    TAtlasStrings.Fmt(TAtlasTextId.BugReportHint, [mNote, TAtlasBugReport.cIssuesUrl]), mReport,
    TAtlasBugReport.DefaultFileName(Now), TAtlasStrings.Text(TAtlasTextId.BugReportFilter), 'md'), mTarget,
    TAtlasIdeDockWindow.ApplyIdeTheme) then
  begin
    Exit;
  end;
  TFile.WriteAllText(mTarget, mReport, TEncoding.UTF8);
  AMessage(TAtlasStrings.Fmt(TAtlasTextId.BugReportDone, [mTarget, TAtlasBugReport.cIssuesUrl]));
end;

end.
