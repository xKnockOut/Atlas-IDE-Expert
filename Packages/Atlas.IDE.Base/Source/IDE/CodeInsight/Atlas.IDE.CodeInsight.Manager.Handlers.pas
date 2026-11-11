unit Atlas.IDE.CodeInsight.Manager.Handlers;

// Antworten des Code Insight-Managers auf den Server, jeweils im Hauptthread: workspace/applyEdit in die Puffer
// (#397), window/showMessage ins Meldungsfenster (#121), Einträge der Benachrichtigungszentrale zu Neustart (#393,
// #601), Absturzfall und übersprungenen Anfragen (#1355) sowie diese Anfragen als Warnungen im Prüffenster.

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Lsp.CrashCases,
  Atlas.Core.Notifications.Contract;

type
  /// <summary>Was der Eintrag „Server neu gestartet“ nennt.</summary>
  TAtlasServerRestart = record
    /// <summary>Vom Server selbst beendet, nicht von Atlas.</summary>
    Crashed: Boolean;
    /// <summary>Exit-Code des abgestürzten Servers, falls bekannt.</summary>
    CodeKnown: Boolean;
    Code: Cardinal;
    /// <summary>Start der vorigen Sitzung; ein Absturzfall ab hier gehört zum Absturz.</summary>
    PreviousStart: TDateTime;
    /// <summary>Dateien, die der neue Server sofort wieder bekam (#393).</summary>
    Reopened: Integer;
    LogActions: TArray<TAtlasNotificationAction>;
    CrashIssue: TProc<TAtlasCrashCase>;
  end;

  /// <summary>Antworten auf den Server im Hauptthread.</summary>
  TAtlasServerHandlers = record
  public
    /// <summary>workspace/applyEdit in die Puffer übernehmen (#397); False mit AReason, wenn nicht übernommen.
    /// </summary>
    class function ApplyEdit(const AEdit: TLspWorkspaceEdit; const ADiagnose: TProc<string>;
      out AReason: string): Boolean; static;
    /// <summary>Fehler (1) rot, Warnung (2) gelb in die Benachrichtigungszentrale (#601); im Meldungsfenster nur
    /// bei der Einstellung „zeigen“.</summary>
    class procedure ServerMessage(AType: Integer; const AMessage: string;
      const ALogActions: TArray<TAtlasNotificationAction>); static;
    /// <summary>„Server neu gestartet“ (#601); drei innerhalb von 10 s fasst die Zentrale zusammen.</summary>
    class procedure NotifyRestarted(const ARestart: TAtlasServerRestart); static;
    /// <summary>„Fall öffnen“, „Issue anlegen“ (nur mit AIssue) und „Ausblenden“ (#1355).</summary>
    class function CrashActions(const ACase: TAtlasCrashCase;
      const AIssue: TProc<TAtlasCrashCase>): TArray<TAtlasNotificationAction>; static;
    /// <summary>Übersprungene Anfragen als Warnungen ins Prüffenster.</summary>
    class procedure UpdateCrashProblems(ASkips: TAtlasCrashSkips); static;
    /// <summary>Name einer übersprungenen Anfrage für die Meldung: Datei, sonst Uri.</summary>
    class function SkipName(const ASkip: TAtlasCrashSkip): string; static;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.ShellAPI,
  System.Generics.Collections,
  ToolsAPI,
  Atlas.UI.Strings,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Lsp.Crashes,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Problems.Store,
  Atlas.Core.Editor.WorkspacePlan,
  Atlas.Core.Notifications.Center,
  Atlas.Core.Notifications.Sources,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Problems.Controller,
  Atlas.Core.Localization.Language,
  Atlas.IDE.Foundation.Host;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  THandlersText = (FileOperationsCreateRenameDelete);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TAtlasLanguage, THandlersText] of string = (
    ('Dateioperationen (anlegen, umbenennen, löschen) werden nicht unterstützt.'),
    ('File operations (create, rename, delete) are not supported.'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: THandlersText): string;
begin
  Result := cTexts[TAtlasTextLanguage.Current, AId];
end;

class function TAtlasServerHandlers.ApplyEdit(const AEdit: TLspWorkspaceEdit; const ADiagnose: TProc<string>;
  out AReason: string): Boolean;
var
  mOutcome: TAtlasWorkspaceEditResult;
begin
  Result := False;
  if AEdit.Unsupported > 0 then
  begin
    AReason := UiText(THandlersText.FileOperationsCreateRenameDelete);
    Exit;
  end;
  try
    mOutcome := TAtlasIdeWorkspaceEdit.Apply(AEdit,
      TAtlasUnopenedPolicies.FromSetting(TAtlasIdeSettings.Current.OpenForEdits),
      TAtlasStrings.Text(TAtlasTextId.UndoActionServer));
    ADiagnose(Format('workspace/applyEdit: %d Änderungen in %d Dateien %s', [mOutcome.Edits, mOutcome.Files,
      mOutcome.Error]));
    Result := mOutcome.Error = '';
    AReason := mOutcome.Error;
  except
    on E: Exception do
    begin
      AReason := E.Message;
      TAtlasGuard.Report(TAtlasFeature.EditorCommands, E);
    end;
  end;
end;

class procedure TAtlasServerHandlers.ServerMessage(AType: Integer; const AMessage: string;
  const ALogActions: TArray<TAtlasNotificationAction>);
var
  mSeverity: TAtlasNotificationSeverity;
begin
  mSeverity := TAtlasNotificationSeverity.Warning;
  if AType = 1 then
  begin
    mSeverity := TAtlasNotificationSeverity.Error;
  end;
  if (TAtlasNotificationCenter.Default.Notify(TAtlasNotificationSources.cServer, mSeverity,
    TAtlasStrings.Text(TAtlasTextId.NotificationsServerMessage), AMessage, ALogActions) <>
    TAtlasNotificationMode.Show) then
  begin
    Exit;
  end;
  TAtlasIdeHost.Message('Atlas: ' + AMessage);
end;

/// <summary>Ursache des Neustarts und erneut geöffnete Dateien als Text des Eintrags.</summary>
function RestartText(const ARestart: TAtlasServerRestart): string;
begin
  Result := '';
  if ARestart.Crashed and ARestart.CodeKnown then
  begin
    Result := TAtlasStrings.Fmt(TAtlasTextId.ServerCrashedCause, [TAtlasServerExits.Describe(ARestart.Code)]);
  end
  else if ARestart.Crashed then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.NotificationsServerCrashed);
  end;
  if ARestart.Reopened > 0 then
  begin
    Result := Trim(Result + ' ' + TAtlasStrings.Fmt(TAtlasTextId.NotificationsServerReopened, [ARestart.Reopened]));
  end;
end;

class procedure TAtlasServerHandlers.NotifyRestarted(const ARestart: TAtlasServerRestart);
var
  mText: string;
  mCase: TAtlasCrashCase;
  mSeverity: TAtlasNotificationSeverity;
begin
  mText := RestartText(ARestart);
  // Absturzfall des abgestürzten Servers (#1355): Methode, Datei, Zeile und Ausnahme statt nur des Codes. Mit
  // server.crashCases aus schreibt der Server keinen, dann bleibt es beim Code.
  if ARestart.Crashed and (ARestart.PreviousStart > 0) and
    TAtlasCrashCases.Newest(TAtlasCrashCases.DefaultRoot, ARestart.PreviousStart, mCase) then
  begin
    TAtlasNotificationCenter.Default.Notify(TAtlasNotificationSources.cServer, TAtlasNotificationSeverity.Warning,
      TAtlasStrings.Text(TAtlasTextId.CrashRestartedTitle), TAtlasCrashCases.SummaryText(mCase) + ' ' + mText,
      CrashActions(mCase, ARestart.CrashIssue));
    Exit;
  end;
  mSeverity := TAtlasNotificationSeverity.Info;
  if ARestart.Crashed then
  begin
    mSeverity := TAtlasNotificationSeverity.Warning;
  end;
  TAtlasNotificationCenter.Default.Notify(TAtlasNotificationSources.cServer, mSeverity,
    TAtlasStrings.Text(TAtlasTextId.NotificationsServerRestarted), mText, ARestart.LogActions);
end;

class function TAtlasServerHandlers.CrashActions(const ACase: TAtlasCrashCase;
  const AIssue: TProc<TAtlasCrashCase>): TArray<TAtlasNotificationAction>;
var
  mFolder: string;
  mCase: TAtlasCrashCase;
  mIssue: TProc<TAtlasCrashCase>;
begin
  mFolder := ACase.Folder;
  mCase := ACase;
  mIssue := AIssue;
  Result := [TAtlasNotificationCenter.Action(TAtlasStrings.Text(TAtlasTextId.CrashOpenCase),
    procedure
    begin
      if DirectoryExists(mFolder) then
      begin
        ShellExecute(0, 'open', 'explorer.exe', PChar('"' + mFolder + '"'), nil, SW_SHOWNORMAL);
      end;
    end)];
  if Assigned(mIssue) then
  begin
    Result := Result + [TAtlasNotificationCenter.Action(TAtlasStrings.Text(TAtlasTextId.CrashCreateIssue),
      procedure
      begin
        mIssue(mCase);
      end)];
  end;
  // Ausblenden: nur den Eintrag schließen, der Fall bleibt im Ordner.
  Result := Result + [TAtlasNotificationCenter.Action(TAtlasStrings.Text(TAtlasTextId.CrashHide),
    procedure
    begin
    end)];
end;

/// <summary>Warnung im Prüffenster zu einer übersprungenen Anfrage.</summary>
function SkipProblem(const ASkip: TAtlasCrashSkip): TAtlasProblem;
begin
  Result := Default(TAtlasProblem);
  Result.EndCharacter := 1;
  Result.Severity := TAtlasProblemSeverity.Warning;
  Result.Code := TAtlasCrashCases.cProblemCode;
  Result.Source := TAtlasCrashCases.cProblemSource;
  Result.Message := TAtlasStrings.Fmt(TAtlasTextId.CrashSkipProblem, [ASkip.Method, ASkip.Crashes,
    ASkip.ExceptionClass, ExtractFileName(ASkip.Folder)]);
end;

class procedure TAtlasServerHandlers.UpdateCrashProblems(ASkips: TAtlasCrashSkips);
var
  mStore: TAtlasProblemStore;
  mSkip: TAtlasCrashSkip;
  mProblems: TArray<TPair<string, TAtlasProblem>>;
begin
  mStore := TAtlasProblemsController.Current;
  if mStore = nil then
  begin
    Exit;
  end;
  mProblems := nil;
  for mSkip in ASkips.Items do
  begin
    if mSkip.FileName <> '' then
    begin
      mProblems := mProblems + [TPair<string, TAtlasProblem>.Create(mSkip.FileName, SkipProblem(mSkip))];
    end;
  end;
  if Length(mProblems) = 0 then
  begin
    mStore.ClearTask(TAtlasCrashCases.cProblemSource);
  end
  else
  begin
    mStore.SetTaskProblems(TAtlasCrashCases.cProblemSource, mProblems);
  end;
end;

class function TAtlasServerHandlers.SkipName(const ASkip: TAtlasCrashSkip): string;
begin
  Result := ExtractFileName(ASkip.FileName);
  if Result = '' then
  begin
    Result := ASkip.Uri;
  end;
end;

initialization
  TAtlasTextLanguage.AddTable('Atlas.IDE.CodeInsight.Manager.Handlers', cTexts[TAtlasLanguage.German], cTexts[TAtlasLanguage.English]);

end.
