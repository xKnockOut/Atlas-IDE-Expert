unit Atlas.IDE.Diagnostics.BugReport;

// Befehl „Fehlerbericht erstellen…“ (#108) für Menü Atlas, Befehlspalette und
// das Fenster des abgesicherten Starts: holt den Bericht des laufenden
// Servers (atlas.server.bugReport; ein gestoppter Server wird dafür nicht
// gestartet), ergänzt Plugin- und IDE-Version, Einstellungen, atlas.log und
// das Ende von server-stderr.log (Bericht H5),
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
  System.IOUtils,
  ToolsAPI,
  Atlas.Core.Product.Version,
  Atlas.Core.Updates.Check,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.History,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Lsp.Crashes,
  Atlas.UI.Diagnostics.ExportDialog,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.Settings;

class function TAtlasIdeBugReport.ProjectRoots: TArray<string>;
var
  Modules: IOTAModuleServices;
  Group: IOTAProjectGroup;
  Index: Integer;
  Folder: string;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
    Exit;
  Group := Modules.MainProjectGroup;
  if Group = nil then
    Exit;
  Folder := ExtractFileDir(Group.FileName);
  if Folder <> '' then
    Result := Result + [Folder];
  for Index := 0 to Group.ProjectCount - 1 do
  begin
    Folder := ExtractFileDir(Group.Projects[Index].FileName);
    if Folder <> '' then
      Result := Result + [Folder];
  end;
end;

class function TAtlasIdeBugReport.SettingsJson: string;
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

class function TAtlasIdeBugReport.Identity: TArray<string>;
begin
  Result := [GetEnvironmentVariable('USERNAME'), GetEnvironmentVariable('COMPUTERNAME'),
    GetEnvironmentVariable('USERDOMAIN')];
end;

class function TAtlasIdeBugReport.Collect: TAtlasBugReportInput;
begin
  Result := Default(TAtlasBugReportInput);
  Result.PluginVersion := TAtlasPluginVersion.Version;
  Result.IdeVersion := TAtlasUpdates.IdeVersion;
  {$IFDEF WIN64}
  Result.Platform := 'Win64';
  {$ELSE}
  Result.Platform := 'Win32';
  {$ENDIF}
  Result.Anonymize := TAtlasIdeSettings.Current.BugReportAnonymize;
  Result.Created := Now;
  Result.Roots := ProjectRoots;
  Result.Identity := Identity;
  Result.Settings := SettingsJson;
  Result.Experimental := TAtlasIdeSettings.ActiveExperimental;
  Result.PluginLog := TAtlasBugReport.Tail(TPath.Combine(TAtlasRotatingLog.DefaultFolder, 'atlas.log'),
    TAtlasBugReport.LogLines);
  Result.ServerErrorOutput := TAtlasBugReport.Tail(TAtlasServerExits.StderrFileName(TAtlasRotatingLog.DefaultFolder),
    TAtlasBugReport.ErrorOutputLines);
end;

class function TAtlasIdeBugReport.ReportText(const AInput: TAtlasBugReportInput; const AAnswer: TJSONValue): string;
var
  Input: TAtlasBugReportInput;
begin
  Input := AInput;
  if (AAnswer is TJSONObject) and (TJSONObject(AAnswer).GetValue('text') is TJSONString) then
    Input.ServerReport := TJSONObject(AAnswer).GetValue('text').Value
  else
    Input.ServerMissing := TAtlasStrings.Text(TAtlasTextId.BugReportNoServer);
  Result := TAtlasBugReport.Build(Input);
end;

class procedure TAtlasIdeBugReport.Execute(const AServer: TAtlasServerCommandWithArguments;
  const AMessage: TProc<string>);
var
  Input: TAtlasBugReportInput;
  Message: TProc<string>;
begin
  if FBusy then
    Exit;
  Message := AMessage;
  Input := Collect;
  if not Assigned(AServer) then
  begin
    Finish(Input, nil, Message);
    Exit;
  end;
  FBusy := True;
  Message(TAtlasStrings.Text(TAtlasTextId.BugReportCollecting));
  try
    AServer(TAtlasBugReport.ServerCommand, TAtlasBugReport.ServerArguments(Input),
      procedure(AAnswer: TJSONValue)
      begin
        FBusy := False;
        TAtlasGuard.Run(TAtlasFeature.Menu,
          procedure
          begin
            Finish(Input, AAnswer, Message);
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
  Report, Target, Note: string;
begin
  Report := ReportText(AInput, AAnswer);
  if AInput.Anonymize then
    Note := TAtlasStrings.Text(TAtlasTextId.BugReportAnonymized)
  else
    Note := TAtlasStrings.Text(TAtlasTextId.BugReportPlain);
  if not TAtlasDiagnosticExportDialog.Execute(TAtlasStrings.Text(TAtlasTextId.BugReportTitle),
    TAtlasStrings.Fmt(TAtlasTextId.BugReportHint, [Note, TAtlasBugReport.IssuesUrl]), Report,
    TAtlasBugReport.DefaultFileName(Now), TAtlasStrings.Text(TAtlasTextId.BugReportFilter), 'md', Target) then
    Exit;
  TFile.WriteAllText(Target, Report, TEncoding.UTF8);
  AMessage(TAtlasStrings.Fmt(TAtlasTextId.BugReportDone, [Target, TAtlasBugReport.IssuesUrl]));
end;

end.
