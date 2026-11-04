unit Atlas.IDE.Settings.ServerActions;

// Aktionen der Seiten „Atlas“ › Prüfregeln und „Atlas.Server“ (#227, #909),
// die AtlasServer.exe als Werkzeug aufrufen (TAtlasServerTool): Baseline des
// aktiven Projekts zählen, neu erzeugen und löschen, Unterdrückungen je Regel
// auswerten und den Index-Cache leeren. Beide Seiten rufen dieselben
// Funktionen, statt den Ablauf je Seite zu wiederholen. Den Pfad der
// AtlasServer.exe setzt die Registrierung der Optionsseiten (ServerPath).

interface

uses
  System.SysUtils;

type
  TAtlasIdeServerActions = class
  private class var
    FServerPath: TFunc<string>;
  public
    /// <summary>atlas-baseline.json des aktiven Projekts (oder der alte Name, wenn nur er existiert); '' ohne
    /// Projekt.</summary>
    class function BaselineFile: string; static;
    /// <summary>Stand der Baseline als Text für die Seite.</summary>
    class function BaselineText: string; static;
    /// <summary>Baseline über --check … --update-baseline neu erzeugen; danach der Stand oder die Fehlermeldung.
    /// </summary>
    class function UpdateBaseline: string; static;
    /// <summary>Baseline löschen; danach der Stand.</summary>
    class function DeleteBaseline: string; static;
    /// <summary>Unterdrückungen je Regel (--suppression-stats) als Zeilen; sonst eine Zeile mit der Meldung.
    /// </summary>
    class function Suppressions: TArray<string>; static;
    /// <summary>Index-Cache leeren (--clear-cache); Ausgabe des Werkzeugs oder die Meldung.</summary>
    class function ClearCache: string; static;
    /// <summary>Pfad der AtlasServer.exe nach den Einstellungen; nicht gesetzt: ''.</summary>
    class property ServerPath: TFunc<string> read FServerPath write FServerPath;
  end;

implementation

uses
  System.IOUtils,
  Atlas.Core.Settings.Baseline,
  Atlas.IDE.Settings.Project,
  Atlas.IDE.Settings.ServerTool,
  Atlas.UI.Strings;

function ServerExe: string;
begin
  Result := '';
  if Assigned(TAtlasIdeServerActions.ServerPath) then
  begin
    Result := TAtlasIdeServerActions.ServerPath();
  end;
end;

/// <summary>AtlasServer.exe mit AArguments im Projektordner; '' bei Erfolg, sonst die Meldung.</summary>
function RunTool(const AArguments: string; ATimeoutMs: Cardinal; out AOutput: string): string;
var
  mCall: TAtlasServerToolCall;
  mResult: TAtlasServerToolResult;
begin
  Result := '';
  mCall := TAtlasServerToolCall.Create(ServerExe, AArguments, ExtractFileDir(TAtlasProjectSettings.ActiveProject),
    ATimeoutMs);
  if not TAtlasServerTool.Run(mCall, mResult) then
  begin
    Result := TAtlasStrings.Fmt(TAtlasTextId.ServerPageToolFailed, [mResult.Error]);
  end
  else if mResult.ExitCode = 3 then
  begin
    Result := TAtlasStrings.Fmt(TAtlasTextId.ServerPageToolFailed, ['Exit-Code 3']);
  end;
  AOutput := mResult.Output;
end;

/// <summary>Zeilen der Auswertung in AFileName; ohne Unterdrückung eine Zeile, die das sagt.</summary>
function SuppressionRows(const AFileName: string): TArray<string>;
var
  mRow: TAtlasSuppressionRow;
begin
  Result := nil;
  for mRow in TAtlasBaselineInfo.Suppressions(TFile.ReadAllText(AFileName, TEncoding.UTF8)) do
  begin
    Result := Result + [TAtlasStrings.Fmt(TAtlasTextId.ServerPageSuppressionRow,
      [mRow.Rule, mRow.Total, mRow.Unused, mRow.Files])];
  end;
  if Length(Result) = 0 then
  begin
    Result := [TAtlasStrings.Text(TAtlasTextId.ServerPageSuppressionsNone)];
  end;
end;

{ TAtlasIdeServerActions }

class function TAtlasIdeServerActions.BaselineFile: string;
var
  mFolder: string;
begin
  Result := '';
  if TAtlasProjectSettings.SettingsFile = '' then
  begin
    Exit;
  end;
  mFolder := IncludeTrailingPathDelimiter(ExtractFileDir(TAtlasProjectSettings.SettingsFile));
  Result := mFolder + TAtlasBaselineInfo.FileName;
  if not FileExists(Result) and FileExists(mFolder + TAtlasBaselineInfo.LegacyFileName) then
  begin
    Result := mFolder + TAtlasBaselineInfo.LegacyFileName;
  end;
end;

class function TAtlasIdeServerActions.BaselineText: string;
var
  mFileName: string;
  mCount, mEntries: Integer;
begin
  mFileName := BaselineFile;
  if mFileName = '' then
  begin
    Exit(TAtlasStrings.Text(TAtlasTextId.ProjectSettingsNoProject));
  end;
  mCount := -1;
  mEntries := 0;
  if FileExists(mFileName) then
  begin
    mCount := TAtlasBaselineInfo.Count(TFile.ReadAllText(mFileName, TEncoding.UTF8), mEntries);
  end;
  if mCount < 0 then
  begin
    Exit(TAtlasStrings.Text(TAtlasTextId.ServerPageBaselineNone));
  end;
  Result := TAtlasStrings.Fmt(TAtlasTextId.ServerPageBaselineCount, [mCount, mEntries]);
end;

class function TAtlasIdeServerActions.UpdateBaseline: string;
var
  mOutput: string;
begin
  if TAtlasProjectSettings.ActiveProject = '' then
  begin
    Exit(TAtlasStrings.Text(TAtlasTextId.ProjectSettingsNoProject));
  end;
  Result := RunTool('--check "' + TAtlasProjectSettings.ActiveProject + '" --update-baseline',
    TAtlasServerTool.CheckTimeoutMs, mOutput);
  if Result = '' then
  begin
    Result := BaselineText;
  end;
end;

class function TAtlasIdeServerActions.DeleteBaseline: string;
var
  mFileName: string;
begin
  mFileName := BaselineFile;
  if (mFileName <> '') and FileExists(mFileName) then
  begin
    TFile.Delete(mFileName);
  end;
  Result := BaselineText;
end;

class function TAtlasIdeServerActions.Suppressions: TArray<string>;
var
  mOutputFile, mOutput, mError: string;
begin
  if TAtlasProjectSettings.ActiveProject = '' then
  begin
    Result := [TAtlasStrings.Text(TAtlasTextId.ProjectSettingsNoProject)];
    Exit;
  end;
  mOutputFile := TPath.GetTempFileName;
  try
    mError := RunTool('--check "' + TAtlasProjectSettings.ActiveProject +
      '" --suppression-stats --format json --output "' + mOutputFile + '"', TAtlasServerTool.CheckTimeoutMs,
      mOutput);
    if mError <> '' then
    begin
      Result := [mError];
    end
    else
    begin
      Result := SuppressionRows(mOutputFile);
    end;
  finally
    if FileExists(mOutputFile) then
    begin
      TFile.Delete(mOutputFile);
    end;
  end;
end;

class function TAtlasIdeServerActions.ClearCache: string;
var
  mOutput: string;
begin
  Result := RunTool('--clear-cache', TAtlasServerTool.ShortTimeoutMs, mOutput);
  if Result = '' then
  begin
    Result := Trim(mOutput);
  end;
  if Result = '' then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.ServerPageToolDone);
  end;
end;

end.
