unit Atlas.IDE.Settings.ServerActions;

// Aktionen der Seite „Atlas.Server“ (#227), die AtlasServer.exe als Werkzeug
// aufrufen (TAtlasServerTool): RunTool im Projektordner und „Index-Cache
// löschen“. Baseline und Unterdrückungen je Regel ruft das Modul Prüfregeln
// über RunTool (Atlas.IDE.Rules.Maintenance, #1755). Den Pfad der
// AtlasServer.exe setzt die Registrierung der Optionsseiten (ServerPath).

interface

uses
  System.SysUtils;

type
  TAtlasIdeServerActions = class
  private class var
    FServerPath: TFunc<string>;
  public
    /// <summary>AtlasServer.exe mit AArguments im Projektordner; '' bei Erfolg, sonst die Meldung. AOutput: Ausgabe
    /// des Werkzeugs.</summary>
    class function RunTool(const AArguments: string; ATimeoutMs: Cardinal; out AOutput: string): string; static;
    /// <summary>Index-Cache leeren (--clear-cache); Ausgabe des Werkzeugs oder die Meldung.</summary>
    class function ClearCache: string; static;
    /// <summary>Pfad der AtlasServer.exe nach den Einstellungen; nicht gesetzt: ''.</summary>
    class property ServerPath: TFunc<string> read FServerPath write FServerPath;
  end;

implementation

uses
  Atlas.Core.Localization.Language,
  Atlas.IDE.Settings.Project,
  Atlas.IDE.Settings.ServerTool,
  Atlas.UI.Settings.Strings;

function ServerExe: string;
begin
  Result := '';
  if Assigned(TAtlasIdeServerActions.ServerPath) then
  begin
    Result := TAtlasIdeServerActions.ServerPath();
  end;
end;

{ TAtlasIdeServerActions }

class function TAtlasIdeServerActions.RunTool(const AArguments: string; ATimeoutMs: Cardinal;
  out AOutput: string): string;
var
  mCall: TAtlasServerToolCall;
  mResult: TAtlasServerToolResult;
begin
  Result := '';
  // Ausgabe des Werkzeugs in der Sprache der Oberfläche (#1458): Ohne --locale nähme es language aus
  // settings.json und sonst Englisch.
  mCall := TAtlasServerToolCall.Create(ServerExe, AArguments + ' --locale ' + TAtlasTextLanguage.Code,
    ExtractFileDir(TAtlasProjectSettings.ActiveProject), ATimeoutMs);
  if not TAtlasServerTool.Run(mCall, mResult) then
  begin
    Result := TAtlasSettingsStrings.Fmt(TAtlasSettingsTextId.ServerPageToolFailed, [mResult.Error]);
  end
  else if mResult.ExitCode = 3 then
  begin
    Result := TAtlasSettingsStrings.Fmt(TAtlasSettingsTextId.ServerPageToolFailed, ['Exit-Code 3']);
  end;
  AOutput := mResult.Output;
end;

class function TAtlasIdeServerActions.ClearCache: string;
var
  mOutput: string;
begin
  Result := RunTool('--clear-cache', TAtlasServerTool.cShortTimeoutMs, mOutput);
  if Result = '' then
  begin
    Result := Trim(mOutput);
  end;
  if Result = '' then
  begin
    Result := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.ServerPageToolDone);
  end;
end;

end.
