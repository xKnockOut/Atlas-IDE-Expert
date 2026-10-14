unit Atlas.IDE.Diagnostics.BugReport;

// Befehl „Fehlerbericht erstellen…“ (#108) für Menü Atlas, Befehlspalette und
// das Fenster des abgesicherten Starts: holt den Bericht des laufenden
// Servers (atlas.server.bugReport; ein gestoppter Server wird dafür nicht
// gestartet), ergänzt Plugin- und IDE-Version, Einstellungen und atlas.log,
// zeigt die Vorschau und schreibt nach Bestätigung eine Markdown-Datei.
// Die Meldungsansicht nennt Datei und Adresse für ein neues Issue.

interface

uses
  System.SysUtils,
  System.JSON;

type
  /// <summary>Befehl an den laufenden Server mit Argumenten (JSON-Array); nil ohne Server oder bei Fehler.</summary>
  TAtlasServerCommandWithArguments = reference to function(const ACommand, AArgumentsJson: string): TJSONValue;

  TAtlasIdeBugReport = record
  public
    class procedure Execute(const AServer: TAtlasServerCommandWithArguments; const AMessage: TProc<string>); static;
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
  Atlas.Core.Diagnostics.BugReport,
  Atlas.UI.Diagnostics.ExportDialog,
  Atlas.UI.Strings,
  Atlas.IDE.Settings.Store;

/// <summary>Ordner der Projekte der geöffneten Projektgruppe (für &lt;ws&gt;).</summary>
function ProjectRoots: TArray<string>;
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

function SettingsJson: string;
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

class procedure TAtlasIdeBugReport.Execute(const AServer: TAtlasServerCommandWithArguments;
  const AMessage: TProc<string>);
var
  Input: TAtlasBugReportInput;
  Answer: TJSONValue;
  Report, Target, Note: string;
begin
  Input := Default(TAtlasBugReportInput);
  Input.PluginVersion := TAtlasPluginVersion.Version;
  Input.IdeVersion := TAtlasUpdates.IdeVersion;
  {$IFDEF WIN64}
  Input.Platform := 'Win64';
  {$ELSE}
  Input.Platform := 'Win32';
  {$ENDIF}
  Input.Anonymize := TAtlasIdeSettings.Current.BugReportAnonymize;
  Input.Created := Now;
  Input.Roots := ProjectRoots;
  Input.Identity := [GetEnvironmentVariable('USERNAME'), GetEnvironmentVariable('COMPUTERNAME'),
    GetEnvironmentVariable('USERDOMAIN')];
  Input.Settings := SettingsJson;
  Input.PluginLog := TAtlasBugReport.Tail(TPath.Combine(TAtlasRotatingLog.DefaultFolder, 'atlas.log'),
    TAtlasBugReport.LogLines);
  Answer := nil;
  if Assigned(AServer) then
    Answer := AServer(TAtlasBugReport.ServerCommand, TAtlasBugReport.ServerArguments(Input));
  try
    if (Answer is TJSONObject) and (TJSONObject(Answer).GetValue('text') is TJSONString) then
      Input.ServerReport := TJSONObject(Answer).GetValue('text').Value
    else
      Input.ServerMissing := TAtlasStrings.Text(TAtlasTextId.BugReportNoServer);
  finally
    Answer.Free;
  end;
  Report := TAtlasBugReport.Build(Input);
  if Input.Anonymize then
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
