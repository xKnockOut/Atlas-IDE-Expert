unit Atlas.Common.Findings.GitHub;

// Ausgabe des Kommandozeilen-Linters als GitHub-Workflow-Befehle (--format github, #1432): je Befund eine Zeile
// ::error, ::warning bzw. ::notice, die GitHub als Anmerkung an der Zeile im Pull Request und in der
// Zusammenfassung des Jobs zeigt. Anders als SARIF braucht das weder Code Scanning noch security-events: write.
//
// - Pfade relativ zur Quellwurzel mit "/", sonst der Pfad aus TCheckedFile.Path; Positionen ab 1.
// - Kodierung nach den Regeln der Workflow-Befehle: in der Meldung %, CR und LF, in den Eigenschaften dazu
//   ":" und ",".
// - GitHub zeigt je Schritt nur wenige Anmerkungen je Art. Darum gibt es zusätzlich eine Zusammenfassung als
//   Markdown für $GITHUB_STEP_SUMMARY: Anzahl je Regel und Schweregrad und die ersten cSummaryRows Befunde,
//   mit Link auf die Zeile, wenn der Aufrufer eine Basisadresse kennt.

interface

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Findings.Contract,
  Atlas.Common.Findings.Output;

type
  TGitHubAnnotations = class
  public const
    /// <summary>So viele Befunde zeigt die Tabelle der Zusammenfassung höchstens.</summary>
    cSummaryRows = 100;
  public
    /// <summary>Je Befund eine Zeile mit Workflow-Befehl; ASourceRoot: Quellwurzel für relative Pfade ('' = Pfade
    /// aus TCheckedFile.Path).</summary>
    class function Render(const AFiles: TArray<TCheckedFile>; const ASourceRoot: string): string; static;
    /// <summary>Zusammenfassung als Markdown. ALinkBase: Adresse, an die der Pfad gehängt wird
    /// (https://github.com/o/r/blob/&lt;sha&gt;/); '' = ohne Links.</summary>
    class function Summary(const AFiles: TArray<TCheckedFile>; const ASourceRoot, ALinkBase: string): string;
      static;
    /// <summary>Basis der Links aus den Variablen des Laufs (GITHUB_SERVER_URL, GITHUB_REPOSITORY, GITHUB_SHA);
    /// '' wenn eine fehlt.</summary>
    class function LinkBase(const AServerUrl, ARepository, ASha: string): string; static;
    /// <summary>Workflow-Befehl zum Schweregrad: error, warning, sonst notice.</summary>
    class function Command(ASeverity: TRuleSeverity): string; static;
    /// <summary>Meldungstext kodiert (%, CR, LF).</summary>
    class function EscapeData(const AText: string): string; static;
    /// <summary>Wert einer Eigenschaft kodiert (wie EscapeData, dazu ":" und ",").</summary>
    class function EscapeProperty(const AText: string): string; static;
    /// <summary>Pfad für file=: relativ zu ASourceRoot mit "/", sonst AFile.Path mit "/".</summary>
    class function PathOf(const AFile: TCheckedFile; const ASourceRoot: string): string; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  TGitHubText = (Heading, NoFindings, RuleTable, FirstFindings, MoreFindings);

const
  cTexts: array[TGitHubText] of TAtlasText = (
    (De: '## Atlas: %d Befunde in %d Dateien'; En: '## Atlas: %d findings in %d files'),
    (De: 'Keine Befunde.'; En: 'No findings.'),
    (De: '| Regel | Fehler | Warnungen | Hinweise |'; En: '| Rule | Errors | Warnings | Notices |'),
    (De: '| Schwere | Stelle | Regel | Meldung |'; En: '| Severity | Location | Rule | Message |'),
    (De: '… und %d weitere Befunde.'; En: '… and %d more findings.'));

{$SCOPEDENUMS OFF}

type
  /// <summary>Zähler je Regel für die Zusammenfassung.</summary>
  TRuleCount = record
    Errors, Warnings, Notices: Integer;
  end;

function Slashes(const APath: string): string;
begin
  Result := StringReplace(APath, '\', '/', [rfReplaceAll]);
end;

class function TGitHubAnnotations.Command(ASeverity: TRuleSeverity): string;
begin
  case ASeverity of
    TRuleSeverity.Error:
      Result := 'error';
    TRuleSeverity.Warning:
      Result := 'warning';
  else
    Result := 'notice';
  end;
end;

class function TGitHubAnnotations.EscapeData(const AText: string): string;
begin
  // Erst das Prozentzeichen, sonst würden die Ersetzungen danach doppelt kodiert.
  Result := StringReplace(AText, '%', '%25', [rfReplaceAll]);
  Result := StringReplace(Result, #13, '%0D', [rfReplaceAll]);
  Result := StringReplace(Result, #10, '%0A', [rfReplaceAll]);
end;

class function TGitHubAnnotations.EscapeProperty(const AText: string): string;
begin
  Result := EscapeData(AText);
  Result := StringReplace(Result, ':', '%3A', [rfReplaceAll]);
  Result := StringReplace(Result, ',', '%2C', [rfReplaceAll]);
end;

class function TGitHubAnnotations.PathOf(const AFile: TCheckedFile; const ASourceRoot: string): string;
var
  mPath, mRoot: string;
begin
  mPath := Slashes(AFile.FullPath);
  mRoot := Slashes(ASourceRoot);
  if (mRoot <> '') and (mRoot[Length(mRoot)] <> '/') then
  begin
    mRoot := mRoot + '/';
  end;
  // Windows-Pfade unterscheiden keine Groß- und Kleinschreibung (wie TFindingsOutput.SarifUri).
  if (mRoot <> '') and (Length(mPath) > Length(mRoot)) and SameText(Copy(mPath, 1, Length(mRoot)), mRoot) then
  begin
    Exit(Copy(mPath, Length(mRoot) + 1, MaxInt));
  end;
  Result := Slashes(AFile.Path);
end;

/// <summary>Letzte Spalte ab 1: das exklusive Ende des Bereichs, mindestens die erste Spalte.</summary>
function EndColumn(const AFinding: TRuleFinding): Integer;
begin
  Result := AFinding.Range.EndPos.Character;
  if (AFinding.Range.EndPos.Line = AFinding.Range.StartPos.Line) and (Result <= AFinding.Range.StartPos.Character) then
  begin
    Result := AFinding.Range.StartPos.Character + 1;
  end;
end;

function AnnotationLine(const APath: string; const AFinding: TRuleFinding): string;
begin
  Result := Format('::%s file=%s,line=%d,col=%d,endLine=%d,endColumn=%d,title=%s::%s',
    [TGitHubAnnotations.Command(AFinding.Severity), TGitHubAnnotations.EscapeProperty(APath),
    AFinding.Range.StartPos.Line + 1, AFinding.Range.StartPos.Character + 1, AFinding.Range.EndPos.Line + 1,
    EndColumn(AFinding), TGitHubAnnotations.EscapeProperty(AFinding.RuleId),
    TGitHubAnnotations.EscapeData(AFinding.Message)]);
end;

class function TGitHubAnnotations.Render(const AFiles: TArray<TCheckedFile>; const ASourceRoot: string): string;
var
  mBuilder: TStringBuilder;
  mFile: TCheckedFile;
  mFinding: TRuleFinding;
  mPath: string;
begin
  mBuilder := TStringBuilder.Create;
  try
    for mFile in AFiles do
    begin
      mPath := PathOf(mFile, ASourceRoot);
      for mFinding in mFile.Findings do
      begin
        mBuilder.Append(AnnotationLine(mPath, mFinding)).Append(sLineBreak);
      end;
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

class function TGitHubAnnotations.LinkBase(const AServerUrl, ARepository, ASha: string): string;
begin
  Result := '';
  if (AServerUrl <> '') and (ARepository <> '') and (ASha <> '') then
  begin
    Result := Slashes(AServerUrl);
    // ExcludeTrailingPathDelimiter kennt unter Windows nur "\": Den Schrägstrich am Ende selbst abschneiden.
    while (Result <> '') and (Result[Length(Result)] = '/') do
    begin
      Delete(Result, Length(Result), 1);
    end;
    Result := Format('%s/%s/blob/%s/', [Result, ARepository, ASha]);
  end;
end;

/// <summary>Zelleninhalt einer Markdown-Tabelle: "|" und Zeilenumbrüche würden die Tabelle zerreißen.</summary>
function Cell(const AText: string): string;
begin
  Result := StringReplace(AText, '|', '\|', [rfReplaceAll]);
  Result := StringReplace(Result, #13#10, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #10, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #13, ' ', [rfReplaceAll]);
end;

procedure CountFinding(ACounts: TDictionary<string, TRuleCount>; const AFinding: TRuleFinding);
var
  mCount: TRuleCount;
begin
  if not ACounts.TryGetValue(AFinding.RuleId, mCount) then
  begin
    mCount := Default(TRuleCount);
  end;
  case AFinding.Severity of
    TRuleSeverity.Error:
      Inc(mCount.Errors);
    TRuleSeverity.Warning:
      Inc(mCount.Warnings);
  else
    Inc(mCount.Notices);
  end;
  ACounts.AddOrSetValue(AFinding.RuleId, mCount);
end;

procedure AppendRuleTable(ABuilder: TStringBuilder; ACounts: TDictionary<string, TRuleCount>);
var
  mRules: TArray<string>;
  mRule: string;
  mCount: TRuleCount;
begin
  mRules := ACounts.Keys.ToArray;
  TArray.Sort<string>(mRules);
  ABuilder.Append(cTexts[TGitHubText.RuleTable].Text).Append(sLineBreak);
  ABuilder.Append('|---|--:|--:|--:|').Append(sLineBreak);
  for mRule in mRules do
  begin
    mCount := ACounts[mRule];
    ABuilder.Append(Format('| `%s` | %d | %d | %d |', [Cell(mRule), mCount.Errors, mCount.Warnings,
      mCount.Notices])).Append(sLineBreak);
  end;
end;

function Location(const APath: string; const AFinding: TRuleFinding; const ALinkBase: string): string;
var
  mLine: Integer;
begin
  mLine := AFinding.Range.StartPos.Line + 1;
  Result := Format('%s:%d', [APath, mLine]);
  if ALinkBase <> '' then
  begin
    Result := Format('[%s](%s%s#L%d)', [Cell(Result), ALinkBase, APath, mLine]);
  end
  else
  begin
    Result := Cell(Result);
  end;
end;

class function TGitHubAnnotations.Summary(const AFiles: TArray<TCheckedFile>; const ASourceRoot,
  ALinkBase: string): string;
var
  mBuilder, mRows: TStringBuilder;
  mCounts: TDictionary<string, TRuleCount>;
  mFile: TCheckedFile;
  mFinding: TRuleFinding;
  mPath: string;
  mTotal, mShown, mWithFindings: Integer;
begin
  mBuilder := TStringBuilder.Create;
  mRows := TStringBuilder.Create;
  mCounts := TDictionary<string, TRuleCount>.Create;
  try
    mTotal := 0;
    mShown := 0;
    mWithFindings := 0;
    for mFile in AFiles do
    begin
      if Length(mFile.Findings) > 0 then
      begin
        Inc(mWithFindings);
      end;
      mPath := PathOf(mFile, ASourceRoot);
      for mFinding in mFile.Findings do
      begin
        Inc(mTotal);
        CountFinding(mCounts, mFinding);
        if mShown < cSummaryRows then
        begin
          Inc(mShown);
          mRows.Append(Format('| %s | %s | `%s` | %s |', [Command(mFinding.Severity),
            Location(mPath, mFinding, ALinkBase), Cell(mFinding.RuleId), Cell(mFinding.Message)])).Append(sLineBreak);
        end;
      end;
    end;
    mBuilder.Append(cTexts[TGitHubText.Heading].Fmt([mTotal, mWithFindings])).Append(sLineBreak).Append(sLineBreak);
    if mTotal = 0 then
    begin
      mBuilder.Append(cTexts[TGitHubText.NoFindings].Text).Append(sLineBreak);
      Exit(mBuilder.ToString);
    end;
    AppendRuleTable(mBuilder, mCounts);
    mBuilder.Append(sLineBreak).Append(cTexts[TGitHubText.FirstFindings].Text).Append(sLineBreak);
    mBuilder.Append('|---|---|---|---|').Append(sLineBreak);
    mBuilder.Append(mRows.ToString);
    if mTotal > mShown then
    begin
      mBuilder.Append(sLineBreak).Append(cTexts[TGitHubText.MoreFindings].Fmt([mTotal - mShown])).Append(sLineBreak);
    end;
    Result := mBuilder.ToString;
  finally
    mCounts.Free;
    mRows.Free;
    mBuilder.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Findings.GitHub', cTexts);

end.
