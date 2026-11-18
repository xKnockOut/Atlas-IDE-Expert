unit Shell.Mcp.IssueTools;

// Host-Rolle Shell: MCP-Modus (--mcp, #48), das begonnene Tracker-Issue für KI-Assistenten (#2051):
// get_current_issue liest <gitdir>/atlas-current-issue.json, die das Plugin neben atlas-commit-prefix schreibt
// (Atlas.Core.Tracker.CurrentIssue), und gibt sie als Text oder JSON aus. Nur lesend; der Server fragt den Tracker
// nie selbst (keine Zugangsdaten im Server-Prozess). <gitdir> findet er wie prepare_commit: die Arbeitskopie über
// dem Projektordner, bei Worktrees deren eigener Ordner.

interface

uses
  System.JSON,
  Shell.Mcp.Context;

/// <summary>get_current_issue (#2051).</summary>
procedure RegisterIssueTools(const AContext: TMcpToolContext);
/// <summary>&lt;gitdir&gt; der Git-Arbeitskopie, in der AFolder liegt; '' ohne.</summary>
function GitDirAbove(const AFolder: string): string;
/// <summary>Datei AName aus AGitDir als UTF-8 (BOM übergangen), höchstens AMaxBytes; '' ohne bzw. zu groß.</summary>
function ReadGitDirFile(const AGitDir, AName: string; AMaxBytes: Integer): string;
/// <summary>Antwort von get_current_issue für den Projektordner ARoot; ANow (UTC) für „vor 5 Min.“. Wirft
/// EMcpToolError bei falschen Argumenten oder kaputter Datei.</summary>
function CurrentIssueOf(const ARoot: string; const AArguments: TJSONObject; ANow: TDateTime): string;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.DateUtils,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Localization.Texts,
  Atlas.Core.VersionControl.Providers.Git,
  Atlas.Core.Tracker.CurrentIssue,
  Shell.Mcp.IssueText,
  Shell.Texts;

type
{$SCOPEDENUMS ON}
  TMcpIssueText = (Tool, Section, Format, NoGit, NoIssue, Unreadable);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TMcpIssueText] of TAtlasText = (
    (De: 'Das begonnene Tracker-Issue dieser Arbeitskopie (#2051), wie es das Atlas-Plugin nach „Beginnen“ ablegt: ' +
    'Kennung, Titel, Tracker und Projekt, Zustand, Meilenstein, Branch, Beschreibung (Markdown), Checkliste mit ' +
    'Erledigt-Stand, Codeverweise (Datei, Zeile, Symbol) und die letzten Kommentare, mit dem Stand der letzten ' +
    'Abfrage. Hakt jemand im Tracker etwas ab, steht es nach der nächsten Auffrischung der IDE hier. Nur lesend; ' +
    'abhaken oder kommentieren geht nicht.';
    En: 'The started tracker issue of this working copy (#2051) as the Atlas plugin stores it after "Start": key, ' +
    'title, tracker and project, state, milestone, branch, description (Markdown), checklist with done state, code ' +
    'references (file, line, symbol) and the latest comments, with the time of the last fetch. When someone ticks ' +
    'an item in the tracker, it shows here after the next refresh in the IDE. Read-only; ticking or commenting is ' +
    'not possible.'),
    (De: 'summary (Vorgabe: Kopf, Checkliste, Codeverweise, Länge der Beschreibung), checklist, body, comments ' +
    'oder all';
    En: 'summary (default: head, checklist, code references, length of the description), checklist, body, ' +
    'comments or all'),
    (De: 'text (Vorgabe) oder json'; En: 'text (default) or json'),
    (De: 'Kein Git-Repository über %s: Das Plugin legt das begonnene Issue in <gitdir>/%s ab.';
    En: 'No Git repository above %s: the plugin stores the started issue in <gitdir>/%s.'),
    (De: 'Kein begonnenes Issue in dieser Arbeitskopie. Ein Issue in der IDE unter „Meine Issues“ mit „Beginnen“ ' +
    'aufnehmen; die Einstellung issues.shareWithAssistants des Plugins muss an sein.';
    En: 'No started issue in this working copy. Take up an issue in the IDE under "My issues" with "Start"; the ' +
    'plugin setting issues.shareWithAssistants must be on.'),
    (De: '%s ist nicht lesbar oder hat eine andere Version.'; En: '%s is not readable or has another version.'));

  /// <summary>So groß wird die Datei höchstens (Beschreibung bis 100 000 Zeichen, fünf Kommentare).</summary>
  cMaxFileBytes = 4 * 1024 * 1024;
  cMaxDepth = 32;

function GitDirAbove(const AFolder: string): string;
var
  mFolder, mParent: string;
  mDepth: Integer;
begin
  Result := '';
  mFolder := ExcludeTrailingPathDelimiter(AFolder);
  for mDepth := 1 to cMaxDepth do
  begin
    if mFolder = '' then
    begin
      Exit;
    end;
    Result := TAtlasGitVersionControl.GitDir(mFolder);
    if Result <> '' then
    begin
      Exit;
    end;
    mParent := ExcludeTrailingPathDelimiter(ExtractFileDir(mFolder));
    if SameText(mParent, mFolder) then
    begin
      Exit;
    end;
    mFolder := mParent;
  end;
end;

function ReadGitDirFile(const AGitDir, AName: string; AMaxBytes: Integer): string;
var
  mFile: string;
  mStream: TFileStream;
  mBytes: TBytes;
  mStart: Integer;
begin
  Result := '';
  mFile := IncludeTrailingPathDelimiter(AGitDir) + AName;
  if (AGitDir = '') or not FileExists(mFile) then
  begin
    Exit;
  end;
  try
    mStream := TFileStream.Create(mFile, fmOpenRead or fmShareDenyNone);
    try
      if mStream.Size > AMaxBytes then
      begin
        Exit;
      end;
      SetLength(mBytes, mStream.Size);
      if Length(mBytes) > 0 then
      begin
        mStream.ReadBuffer(mBytes[0], Length(mBytes));
      end;
    finally
      mStream.Free;
    end;
  except
    // Gesperrt oder gerade ersetzt: wie ohne Datei.
    on EStreamError do
      Exit;
    on EOSError do
      Exit;
  end;
  mStart := 0;
  if (Length(mBytes) >= 3) and (mBytes[0] = $EF) and (mBytes[1] = $BB) and (mBytes[2] = $BF) then
  begin
    mStart := 3;
  end;
  Result := TEncoding.UTF8.GetString(mBytes, mStart, Length(mBytes) - mStart);
end;

/// <summary>Argumente section und format; EMcpToolError bei anderem Text.</summary>
procedure ParseArguments(const AArguments: TJSONObject; out ASection: TAtlasCurrentIssueSection; out AJson: Boolean);
var
  mFormat: string;
begin
  if not TMcpCurrentIssueText.ParseSection(TMcpArgs.OptionalString(AArguments, 'section'), ASection) then
  begin
    raise EMcpToolError.Create(TShellTexts.Choice('section', ['summary', 'checklist', 'body', 'comments', 'all']));
  end;
  mFormat := TMcpArgs.OptionalString(AArguments, 'format');
  if (mFormat <> '') and not SameText(mFormat, 'text') and not SameText(mFormat, 'json') then
  begin
    raise EMcpToolError.Create(TShellTexts.Choice('format', ['text', 'json']));
  end;
  AJson := SameText(mFormat, 'json');
end;

function CurrentIssueOf(const ARoot: string; const AArguments: TJSONObject; ANow: TDateTime): string;
var
  mSection: TAtlasCurrentIssueSection;
  mJson: Boolean;
  mGitDir, mText: string;
  mIssue: TAtlasCurrentIssue;
begin
  ParseArguments(AArguments, mSection, mJson);
  mGitDir := GitDirAbove(ARoot);
  if mGitDir = '' then
  begin
    Exit(cTexts[TMcpIssueText.NoGit].Fmt([ARoot, TAtlasCurrentIssue.cFileName]));
  end;
  mText := ReadGitDirFile(mGitDir, TAtlasCurrentIssue.cFileName, cMaxFileBytes);
  if Trim(mText) = '' then
  begin
    Exit(cTexts[TMcpIssueText.NoIssue].Text);
  end;
  if not TAtlasCurrentIssue.FromJson(mText, mIssue) then
  begin
    raise EMcpToolError.Create(cTexts[TMcpIssueText.Unreadable].Fmt([TAtlasCurrentIssue.cFileName]));
  end;
  if mJson then
  begin
    Result := TMcpCurrentIssueText.Json(mIssue, mSection);
  end
  else
  begin
    Result := TMcpCurrentIssueText.Text(mIssue, mSection, ANow);
  end;
end;

function ToolGetCurrentIssue(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
begin
  Result := CurrentIssueOf(AContext.Root, AArguments, TTimeZone.Local.ToUniversalTime(Now));
end;

procedure RegisterIssueTools(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('get_current_issue', cTexts[TMcpIssueText.Tool].Text,
    SchemaWith('{"type":"object","properties":{' +
      '"section":{"type":"string","enum":["summary","checklist","body","comments","all"],"description":%s},' +
      '"format":{"type":"string","enum":["text","json"],"description":%s}}}',
      [cTexts[TMcpIssueText.Section].Text, cTexts[TMcpIssueText.Format].Text]),
    ContextTool(AContext, ToolGetCurrentIssue));
end;

initialization
  TAtlasTextTables.Add('Shell.Mcp.IssueTools', cTexts);

end.
