unit Atlas.IDE.Rules.Maintenance;

// Baseline und Unterdrückungen des aktiven Projekts im Modul Prüfregeln (#97,
// #147, #1755; vorher Atlas.IDE.Settings.ServerActions in Base): Stand der
// Baseline zählen, neu erzeugen (--check … --update-baseline) und löschen,
// Unterdrückungen je Regel auswerten (--suppression-stats). AtlasServer.exe
// läuft über TAtlasIdeServerActions.RunTool von Base. Die Seite Prüfregeln
// (Abschnitt des Moduls, Atlas.IDE.Rules.Settings) ruft diese Funktionen. Das
// Format der Baseline-Datei bleibt in Base (TAtlasBaselineInfo).

interface

type
  TAtlasIdeRulesMaintenance = class
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
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Core.Settings.Baseline,
  Atlas.IDE.Settings.Project,
  Atlas.IDE.Settings.ServerActions,
  Atlas.IDE.Settings.ServerTool,
  Atlas.UI.Strings,
  Atlas.UI.Rules.Strings;

/// <summary>Zeilen der Auswertung in AFileName; ohne Unterdrückung eine Zeile, die das sagt.</summary>
function SuppressionRows(const AFileName: string): TArray<string>;
var
  mRow: TAtlasSuppressionRow;
begin
  Result := nil;
  for mRow in TAtlasBaselineInfo.Suppressions(TFile.ReadAllText(AFileName, TEncoding.UTF8)) do
  begin
    Result := Result + [TAtlasRulesStrings.Fmt(TAtlasRulesTextId.ServerPageSuppressionRow,
      [mRow.Rule, mRow.Total, mRow.Unused, mRow.Files])];
  end;
  if Length(Result) = 0 then
  begin
    Result := [TAtlasRulesStrings.Text(TAtlasRulesTextId.ServerPageSuppressionsNone)];
  end;
end;

{ TAtlasIdeRulesMaintenance }

class function TAtlasIdeRulesMaintenance.BaselineFile: string;
var
  mFolder: string;
begin
  Result := '';
  if TAtlasProjectSettings.SettingsFile = '' then
  begin
    Exit;
  end;
  mFolder := IncludeTrailingPathDelimiter(ExtractFileDir(TAtlasProjectSettings.SettingsFile));
  Result := mFolder + TAtlasBaselineInfo.cFileName;
  if not FileExists(Result) and FileExists(mFolder + TAtlasBaselineInfo.cLegacyFileName) then
  begin
    Result := mFolder + TAtlasBaselineInfo.cLegacyFileName;
  end;
end;

class function TAtlasIdeRulesMaintenance.BaselineText: string;
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
    Exit(TAtlasRulesStrings.Text(TAtlasRulesTextId.ServerPageBaselineNone));
  end;
  Result := TAtlasRulesStrings.Fmt(TAtlasRulesTextId.ServerPageBaselineCount, [mCount, mEntries]);
end;

class function TAtlasIdeRulesMaintenance.UpdateBaseline: string;
var
  mOutput: string;
begin
  if TAtlasProjectSettings.ActiveProject = '' then
  begin
    Exit(TAtlasStrings.Text(TAtlasTextId.ProjectSettingsNoProject));
  end;
  Result := TAtlasIdeServerActions.RunTool('--check "' + TAtlasProjectSettings.ActiveProject + '" --update-baseline',
    TAtlasServerTool.cCheckTimeoutMs, mOutput);
  if Result = '' then
  begin
    Result := BaselineText;
  end;
end;

class function TAtlasIdeRulesMaintenance.DeleteBaseline: string;
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

class function TAtlasIdeRulesMaintenance.Suppressions: TArray<string>;
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
    mError := TAtlasIdeServerActions.RunTool('--check "' + TAtlasProjectSettings.ActiveProject +
      '" --suppression-stats --format json --output "' + mOutputFile + '"', TAtlasServerTool.cCheckTimeoutMs,
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

end.
