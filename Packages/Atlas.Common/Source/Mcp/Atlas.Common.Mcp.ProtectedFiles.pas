unit Atlas.Common.Mcp.ProtectedFiles;

// Geschützte Dateien (#2608): Dateien aus assistants.protected dürfen KI-Assistenten nicht ändern. Die schreibenden
// MCP-Werkzeuge (TMcpEditTools.ProtectedReport) lehnen eine Änderung daran ab, bevor sie etwas schreiben, und nennen in der Vorschau
// (dryRun) die betroffenen Dateien; hook_check meldet eine Bearbeitung mit den eigenen Werkzeugen des Assistenten
// (nach dem Schreiben) bzw. lehnt sie ab (vor dem Schreiben). delphi://conventions listet die Dateien.
// Muster wie architecture.exclude (MatchesGlob): relativ zum Ordner der Konfiguration, "/" und "\" gleich, ohne
// Groß-/Kleinschreibung.

interface

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract;

{$SCOPEDENUMS ON}

type
  /// <summary>Ob ein Hook vor oder nach dem Schreiben fragt (hook_check, Argument mode).</summary>
  TMcpHookMoment = (Before, After);

{$SCOPEDENUMS OFF}

type
  TMcpProtectedFiles = class
  private
    FRoot: string;
    FEntries: TArray<TProtectedPath>;
    function Block(const AFileName: string; const AEntry: TProtectedPath; const AIndent: string): string;
  public
    /// <summary>ARoot: Ordner der Konfiguration (Bezug der Muster); AEntries: assistants.protected. Die Werkzeuge
    /// legen das Objekt je Aufruf an, damit Änderungen an atlas.json sofort gelten.</summary>
    constructor Create(const ARoot: string; const AEntries: TArray<TProtectedPath>);
    /// <summary>AFileName relativ zu ARoot mit "/" (ohne Groß-/Kleinschreibung verglichen); relativ angegebene
    /// Pfade bleiben, Pfade außerhalb von ARoot ebenfalls.</summary>
    class function RelativePath(const ARoot, AFileName: string): string; static;
    /// <summary>Passt APattern auf AFileName (relativ zu ARoot oder absolut)?</summary>
    class function Matches(const ARoot, APattern, AFileName: string): Boolean; static;
    /// <summary>Erster Eintrag, der AFileName schützt.</summary>
    function Find(const AFileName: string; out AEntry: TProtectedPath): Boolean;
    /// <summary>Die geschützten unter AFileNames mit Grund und richtigem Weg; '' ohne. ADryRun: Abschnitt der
    /// Vorschau, sonst die Ablehnung.</summary>
    function Report(const AFileNames: TArray<string>; ADryRun: Boolean): string;
    /// <summary>EMcpToolError mit der Ablehnung, wenn eine der Dateien geschützt ist.</summary>
    procedure EnsureAllowed(const AFileNames: TArray<string>);
    /// <summary>Ausgabe von hook_check für AFileName (Format der Hooks von Claude Code); '' ohne Schutz.
    /// Before: PreToolUse lehnt ab, After: PostToolUse meldet die Bearbeitung als Fehler.</summary>
    function HookOutput(const AFileName: string; AMoment: TMcpHookMoment): string;
    /// <summary>Argument mode von hook_check: "post" (Vorgabe bei leerem Text) oder "pre"; EMcpToolError sonst.
    /// </summary>
    class function ParseHookMoment(const AText: string): TMcpHookMoment; static;
    /// <summary>Abschnitt „Geschützte Dateien“ für delphi://conventions; '' ohne Einträge.</summary>
    class function Markdown(const AEntries: TArray<TProtectedPath>): string; static;
    property Root: string read FRoot;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Rules.Output,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TProtectedFilesText = (Reason, Instead, RefusedOne, RefusedMany, PreviewOne, PreviewMany, HookAfter, HookBefore,
    Heading, Intro, Column, ModeIsPostOrPre);

const
  cTexts: array[TProtectedFilesText] of TAtlasText = (
    (De: 'Grund: %s'; En: 'Reason: %s'),
    (De: 'Stattdessen: %s'; En: 'Instead: %s'),
    (De: 'Abgelehnt, nichts geschrieben: %s ist geschützt (assistants.protected in atlas.json).';
     En: 'Refused, nothing written: %s is protected (assistants.protected in atlas.json).'),
    (De: 'Abgelehnt, nichts geschrieben: %d Dateien sind geschützt (assistants.protected in atlas.json):';
     En: 'Refused, nothing written: %d files are protected (assistants.protected in atlas.json):'),
    (De: 'Geschützt, mit dryRun=false abgelehnt: %s (assistants.protected in atlas.json).';
     En: 'Protected, refused with dryRun=false: %s (assistants.protected in atlas.json).'),
    (De: 'Geschützt, mit dryRun=false abgelehnt: %d Dateien (assistants.protected in atlas.json):';
     En: 'Protected, refused with dryRun=false: %d files (assistants.protected in atlas.json):'),
    (De: 'Atlas: %s ist geschützt und darf von KI-Assistenten nicht geändert werden (assistants.protected in ' +
      'atlas.json). Die Änderung rückgängig machen.';
     En: 'Atlas: %s is protected and must not be changed by AI assistants (assistants.protected in atlas.json). ' +
      'Undo the change.'),
    (De: 'Atlas: %s ist geschützt und darf von KI-Assistenten nicht geändert werden (assistants.protected in ' +
      'atlas.json).';
     En: 'Atlas: %s is protected and must not be changed by AI assistants (assistants.protected in atlas.json).'),
    (De: '## Geschützte Dateien'; En: '## Protected files'),
    (De: 'KI-Assistenten dürfen diese Dateien nicht ändern; die schreibenden Werkzeuge und hook_check lehnen es ab ' +
      '(assistants.protected in atlas.json).';
     En: 'AI assistants must not change these files; the writing tools and hook_check refuse it ' +
      '(assistants.protected in atlas.json).'),
    (De: '| Muster | Grund | Stattdessen |'; En: '| Pattern | Reason | Instead |'),
    (De: '"mode" ist post (nach dem Schreiben, Vorgabe) oder pre (vor dem Schreiben)';
     En: '"mode" is post (after writing, default) or pre (before writing)'));

{$SCOPEDENUMS OFF}

{ TMcpProtectedFiles }

constructor TMcpProtectedFiles.Create(const ARoot: string; const AEntries: TArray<TProtectedPath>);
begin
  inherited Create;
  FRoot := ARoot;
  FEntries := AEntries;
end;

class function TMcpProtectedFiles.RelativePath(const ARoot, AFileName: string): string;
var
  mRoot, mFileName: string;
begin
  mFileName := StringReplace(AFileName, '\', '/', [rfReplaceAll]);
  mRoot := StringReplace(ARoot, '\', '/', [rfReplaceAll]);
  if (mRoot <> '') and (mRoot[Length(mRoot)] <> '/') then
  begin
    mRoot := mRoot + '/';
  end;
  Result := mFileName;
  if (mRoot <> '/') and (mRoot <> '') and StartsText(mRoot, mFileName) then
  begin
    Result := Copy(mFileName, Length(mRoot) + 1, MaxInt);
  end;
end;

class function TMcpProtectedFiles.Matches(const ARoot, APattern, AFileName: string): Boolean;
begin
  Result := (Trim(APattern) <> '') and (MatchesGlob(APattern, RelativePath(ARoot, AFileName)) or
    MatchesGlob(APattern, AFileName));
end;

function TMcpProtectedFiles.Find(const AFileName: string; out AEntry: TProtectedPath): Boolean;
var
  mEntry: TProtectedPath;
begin
  AEntry := Default(TProtectedPath);
  for mEntry in FEntries do
  begin
    if Matches(FRoot, mEntry.Path, AFileName) then
    begin
      AEntry := mEntry;
      Exit(True);
    end;
  end;
  Result := False;
end;

function TMcpProtectedFiles.Block(const AFileName: string; const AEntry: TProtectedPath;
  const AIndent: string): string;
begin
  Result := AFileName;
  if AEntry.Reason <> '' then
  begin
    Result := Result + sLineBreak + AIndent + cTexts[TProtectedFilesText.Reason].Fmt([AEntry.Reason]);
  end;
  if AEntry.Use <> '' then
  begin
    Result := Result + sLineBreak + AIndent + cTexts[TProtectedFilesText.Instead].Fmt([AEntry.Use]);
  end;
end;

function TMcpProtectedFiles.Report(const AFileNames: TArray<string>; ADryRun: Boolean): string;
var
  mFileName: string;
  mEntry: TProtectedPath;
  mNames: TArray<string>;
  mEntries: TArray<TProtectedPath>;
  mIndex: Integer;
begin
  Result := '';
  mNames := nil;
  mEntries := nil;
  for mFileName in AFileNames do
  begin
    if Find(mFileName, mEntry) then
    begin
      mNames := mNames + [RelativePath(FRoot, mFileName)];
      mEntries := mEntries + [mEntry];
    end;
  end;
  if Length(mNames) = 1 then
  begin
    if ADryRun then
    begin
      Result := cTexts[TProtectedFilesText.PreviewOne].Fmt([mNames[0]]);
    end
    else
    begin
      Result := cTexts[TProtectedFilesText.RefusedOne].Fmt([mNames[0]]);
    end;
    Result := Result + Block('', mEntries[0], '  ');
  end
  else if Length(mNames) > 1 then
  begin
    if ADryRun then
    begin
      Result := cTexts[TProtectedFilesText.PreviewMany].Fmt([Length(mNames)]);
    end
    else
    begin
      Result := cTexts[TProtectedFilesText.RefusedMany].Fmt([Length(mNames)]);
    end;
    for mIndex := 0 to High(mNames) do
    begin
      Result := Result + sLineBreak + Block('- ' + mNames[mIndex], mEntries[mIndex], '  ');
    end;
  end;
end;

procedure TMcpProtectedFiles.EnsureAllowed(const AFileNames: TArray<string>);
var
  mReport: string;
begin
  mReport := Report(AFileNames, False);
  if mReport <> '' then
  begin
    raise EMcpToolError.Create(mReport);
  end;
end;

function TMcpProtectedFiles.HookOutput(const AFileName: string; AMoment: TMcpHookMoment): string;
var
  mEntry: TProtectedPath;
  mText: string;
begin
  Result := '';
  if not Find(AFileName, mEntry) then
  begin
    Exit;
  end;
  if AMoment = TMcpHookMoment.Before then
  begin
    mText := Block(cTexts[TProtectedFilesText.HookBefore].Fmt([RelativePath(FRoot, AFileName)]), mEntry, '');
    Result := '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny",' +
      '"permissionDecisionReason":' + TFindingsOutput.JsonString(mText) + '}}';
  end
  else
  begin
    mText := Block(cTexts[TProtectedFilesText.HookAfter].Fmt([RelativePath(FRoot, AFileName)]), mEntry, '');
    Result := '{"decision":"block","reason":' + TFindingsOutput.JsonString(mText) + '}';
  end;
end;

class function TMcpProtectedFiles.ParseHookMoment(const AText: string): TMcpHookMoment;
begin
  if (Trim(AText) = '') or SameText(Trim(AText), 'post') then
  begin
    Result := TMcpHookMoment.After;
  end
  else if SameText(Trim(AText), 'pre') then
  begin
    Result := TMcpHookMoment.Before;
  end
  else
  begin
    raise EMcpToolError.Create(cTexts[TProtectedFilesText.ModeIsPostOrPre].Text);
  end;
end;

/// <summary>Text für eine Zelle einer Markdown-Tabelle.</summary>
function Cell(const AText: string): string;
begin
  Result := StringReplace(AText, '|', '\|', [rfReplaceAll]);
end;

class function TMcpProtectedFiles.Markdown(const AEntries: TArray<TProtectedPath>): string;
var
  mEntry: TProtectedPath;
begin
  Result := '';
  if Length(AEntries) = 0 then
  begin
    Exit;
  end;
  Result := cTexts[TProtectedFilesText.Heading].Text + sLineBreak + sLineBreak +
    cTexts[TProtectedFilesText.Intro].Text + sLineBreak + sLineBreak + cTexts[TProtectedFilesText.Column].Text +
    sLineBreak + '| --- | --- | --- |';
  for mEntry in AEntries do
  begin
    Result := Result + sLineBreak + Format('| `%s` | %s | %s |', [Cell(mEntry.Path), Cell(mEntry.Reason),
      Cell(mEntry.Use)]);
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Mcp.ProtectedFiles', cTexts);

end.
