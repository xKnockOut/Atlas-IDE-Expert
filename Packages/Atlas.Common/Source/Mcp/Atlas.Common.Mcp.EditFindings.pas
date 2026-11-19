unit Atlas.Common.Mcp.EditFindings;

// Befunde nach schreibenden MCP-Werkzeugen (#2603): Nach jeder Änderung mit dryRun=false prüft der Server die
// geänderten Dateien vor und nach dem Schreiben mit derselben Prüfung wie get_diagnostics und meldet dem
// KI-Assistenten den Unterschied: neue Befunde mit Datei:Zeile, Regel und Text, die Zahl der behobenen und der
// unveränderten. Zugeordnet wird über Regel, Meldung und die Zeile, verschoben um den Zeilenversatz aus dem Diff;
// ein Befund in einer geänderten Zeile gilt als derselbe, wenn ein gleicher in einer geänderten Zeile davor stand.
// Nach dem Schreiben zählt der Text, der wirklich in der Datei bzw. im Editorpuffer steht (ReadText), nicht der
// geplante. TMcpEditEvaluation merkt sich die letzte Auswertung für die Ressource delphi://edits/last.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract;

type
  /// <summary>Befunde von AText (Inhalt von AFileName) wie get_diagnostics.</summary>
  TMcpFindingsFunc = reference to function(const AFileName, AText: string): TArray<TRuleFinding>;
  /// <summary>Liest den aktuellen Text einer Datei (Platte oder Editorpuffer); False, wenn nicht lesbar.</summary>
  TMcpEditReadText = reference to function(const AFileName: string; out AText: string): Boolean;

  /// <summary>Unterschied der Befunde einer Datei vor und nach einer Änderung.</summary>
  TMcpFindingDelta = record
    FileName: string;
    /// <summary>Neu entstandene Befunde (Zeilen im neuen Text).</summary>
    Added: TArray<TRuleFinding>;
    /// <summary>Behobene Befunde (Zeilen im alten Text).</summary>
    Fixed: TArray<TRuleFinding>;
    Unchanged: Integer;
  end;

  TMcpEditFindings = class
  public const
    /// <summary>Höchstens so viele neue Befunde in der Antwort, der Rest gezählt.</summary>
    cMaxShown = 50;
    /// <summary>Höchstens so viele behobene Befunde einzeln genannt.</summary>
    cMaxFixedShown = 10;
  public
    /// <summary>Je Zeile von AOld (0-basiert) die Zeile in ANew, -1 für geänderte oder gelöschte Zeilen.</summary>
    class function LineMap(const AOld, ANew: string): TArray<Integer>; static;
    /// <summary>Ordnet ABefore (Befunde von AOld) und AAfter (Befunde von ANew) einander zu.</summary>
    class function Compare(const AFileName, AOld, ANew: string;
      const ABefore, AAfter: TArray<TRuleFinding>): TMcpFindingDelta; static;
    /// <summary>Abschnitt „Befunde nach der Änderung“ für ADeltas; Pfade relativ zu ARoot. Ohne neue Befunde eine
    /// Zeile.</summary>
    class function Report(const ARoot: string; const ADeltas: TArray<TMcpFindingDelta>): string; static;
  end;

  /// <summary>Auswertung nach dem Schreiben für TMcpEditTools.AfterWrite und delphi://edits/last. Als Interface,
  /// damit die anonymen Methoden der Werkzeuge und der Ressource es gemeinsam halten.</summary>
  IMcpEditEvaluation = interface
    ['{5B0C6E0D-2E7A-4F3B-9D41-8C1E7A2F6B53}']
    /// <summary>Wertet die geschriebenen Dateien ANames aus (AOldTexts vorher, ANewTexts geplant) und liefert den
    /// Abschnitt für die Antwort; '' wenn abgeschaltet.</summary>
    function Run(const ATool: string; const ANames, AOldTexts, ANewTexts: TArray<string>): string;
    /// <summary>Inhalt von delphi://edits/last: letzte Auswertung oder ein Hinweis vor der ersten Änderung.</summary>
    function Last: string;
  end;

  TMcpEditEvaluation = class(TInterfacedObject, IMcpEditEvaluation)
  private
    FRoot: string;
    FFindingsOf: TMcpFindingsFunc;
    FReadText: TMcpEditReadText;
    FEnabled: TFunc<Boolean>;
    FLast: string;
    function CurrentText(const AFileName, APlanned: string): string;
  public
    /// <summary>ARoot für relative Pfade; AEnabled (mcp.reportFindingsAfterEdit) bei jedem Aufruf neu gefragt,
    /// nil = an; AReadText nil = der geplante Text gilt.</summary>
    constructor Create(const ARoot: string; const AFindingsOf: TMcpFindingsFunc; const AReadText: TMcpEditReadText;
      const AEnabled: TFunc<Boolean>);
    function Run(const ATool: string; const ANames, AOldTexts, ANewTexts: TArray<string>): string;
    function Last: string;
  end;

implementation

uses
  Atlas.Text.Lines,
  Atlas.Text.Diff,
  Atlas.Common.Mcp.ProtectedFiles,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TEditFindingsText = (Heading, NoNew, NewCount, Fixed, FixedAt, Unchanged, More, NoEditYet, LastHeader);

const
  cTexts: array[TEditFindingsText] of TAtlasText = (
    (De: 'Befunde nach der Änderung:'; En: 'Findings after the change:'),
    (De: 'Befunde nach der Änderung: keine neuen; behoben: %d%s; unverändert: %d.';
     En: 'Findings after the change: no new ones; fixed: %d%s; unchanged: %d.'),
    (De: 'Neue Befunde (%d):'; En: 'New findings (%d):'),
    (De: 'Behoben: %d%s'; En: 'Fixed: %d%s'),
    (De: '%s in Zeile %d'; En: '%s in line %d'),
    (De: 'Unverändert: %d'; En: 'Unchanged: %d'),
    (De: '  … und %d weitere'; En: '  … and %d more'),
    (De: 'Noch keine Änderung über ein schreibendes Werkzeug in diesem MCP-Prozess (dryRun=false).';
     En: 'No change through a writing tool in this MCP process yet (dryRun=false).'),
    (De: 'Letzte Änderung: %s um %s, %s'; En: 'Last change: %s at %s, %s'));

{$SCOPEDENUMS OFF}

{ TMcpEditFindings }

class function TMcpEditFindings.LineMap(const AOld, ANew: string): TArray<Integer>;
var
  mHunks: TArray<TTextLineHunk>;
  mHunk: TTextLineHunk;
  mOld: Integer;
  mOffset: Integer;
  mIndex: Integer;
begin
  Result := nil;
  SetLength(Result, Length(TTextLines.SplitLines(AOld)));
  mHunks := TTextDiff.Hunks(TTextLines.SplitLines(AOld), TTextLines.SplitLines(ANew));
  mOffset := 0;
  mOld := 0;
  for mHunk in mHunks do
  begin
    while mOld < mHunk.OldStart do
    begin
      Result[mOld] := mOld + mOffset;
      Inc(mOld);
    end;
    for mIndex := 0 to mHunk.OldCount - 1 do
    begin
      Result[mOld] := -1;
      Inc(mOld);
    end;
    mOffset := mOffset + mHunk.NewCount - mHunk.OldCount;
  end;
  while mOld < Length(Result) do
  begin
    Result[mOld] := mOld + mOffset;
    Inc(mOld);
  end;
end;

/// <summary>Gleicher Befund ohne Ort: Regel und Meldung.</summary>
function SameFinding(const A, B: TRuleFinding): Boolean;
begin
  Result := SameText(A.RuleId, B.RuleId) and (A.Message = B.Message);
end;

/// <summary>Zeile von AFinding in AMap; -1 außerhalb.</summary>
function MappedLine(const AMap: TArray<Integer>; const AFinding: TRuleFinding): Integer;
begin
  Result := -1;
  if (AFinding.Range.StartPos.Line >= 0) and (AFinding.Range.StartPos.Line < Length(AMap)) then
  begin
    Result := AMap[AFinding.Range.StartPos.Line];
  end;
end;

/// <summary>Zeilen des neuen Texts, die unverändert aus dem alten stammen.</summary>
function KeptLines(const AMap: TArray<Integer>; ANewCount: Integer): TArray<Boolean>;
var
  mLine: Integer;
begin
  Result := nil;
  SetLength(Result, ANewCount);
  for mLine in AMap do
  begin
    if (mLine >= 0) and (mLine < ANewCount) then
    begin
      Result[mLine] := True;
    end;
  end;
end;

/// <summary>Liegt ALine in einer geänderten (neuen) Zeile?</summary>
function IsChangedLine(const AKept: TArray<Boolean>; ALine: Integer): Boolean;
begin
  Result := (ALine < 0) or (ALine >= Length(AKept)) or not AKept[ALine];
end;

/// <summary>Zuordnung der Befunde vorher und nachher mit Zeilenversatz und geänderten Zeilen.</summary>
type
  TFindingMatcher = record
    Map: TArray<Integer>;
    Kept: TArray<Boolean>;
    Before, After: TArray<TRuleFinding>;
    Used, Matched: TArray<Boolean>;
    /// <summary>Ordnet After[AAfter] einem freien gleichen Befund zu: AShifted über den Zeilenversatz, sonst einem
    /// aus einer geänderten Zeile.</summary>
    procedure Match(AAfter: Integer; AShifted: Boolean);
    function Fits(ABefore, AAfter: Integer; AShifted: Boolean): Boolean;
  end;

function TFindingMatcher.Fits(ABefore, AAfter: Integer; AShifted: Boolean): Boolean;
begin
  Result := not Used[ABefore] and SameFinding(Before[ABefore], After[AAfter]);
  if Result and AShifted then
  begin
    Result := MappedLine(Map, Before[ABefore]) = After[AAfter].Range.StartPos.Line;
  end
  else if Result then
  begin
    Result := MappedLine(Map, Before[ABefore]) < 0;
  end;
end;

procedure TFindingMatcher.Match(AAfter: Integer; AShifted: Boolean);
var
  mBefore: Integer;
begin
  if Matched[AAfter] or (not AShifted and not IsChangedLine(Kept, After[AAfter].Range.StartPos.Line)) then
  begin
    Exit;
  end;
  for mBefore := 0 to High(Before) do
  begin
    if Fits(mBefore, AAfter, AShifted) then
    begin
      Used[mBefore] := True;
      Matched[AAfter] := True;
      Exit;
    end;
  end;
end;

class function TMcpEditFindings.Compare(const AFileName, AOld, ANew: string;
  const ABefore, AAfter: TArray<TRuleFinding>): TMcpFindingDelta;
var
  mMatcher: TFindingMatcher;
  mIndex: Integer;
begin
  Result := Default(TMcpFindingDelta);
  Result.FileName := AFileName;
  mMatcher := Default(TFindingMatcher);
  mMatcher.Map := LineMap(AOld, ANew);
  mMatcher.Kept := KeptLines(mMatcher.Map, Length(TTextLines.SplitLines(ANew)));
  mMatcher.Before := ABefore;
  mMatcher.After := AAfter;
  SetLength(mMatcher.Used, Length(ABefore));
  SetLength(mMatcher.Matched, Length(AAfter));
  // Erst verschobene Befunde (gleiche Zeile nach dem Versatz), dann gleiche Befunde in geänderten Zeilen.
  for mIndex := 0 to High(AAfter) do
  begin
    mMatcher.Match(mIndex, True);
  end;
  for mIndex := 0 to High(AAfter) do
  begin
    mMatcher.Match(mIndex, False);
  end;
  for mIndex := 0 to High(AAfter) do
  begin
    if mMatcher.Matched[mIndex] then
    begin
      Inc(Result.Unchanged);
    end
    else
    begin
      Result.Added := Result.Added + [AAfter[mIndex]];
    end;
  end;
  for mIndex := 0 to High(ABefore) do
  begin
    if not mMatcher.Used[mIndex] then
    begin
      Result.Fixed := Result.Fixed + [ABefore[mIndex]];
    end;
  end;
end;

/// <summary>Behobene als " (regel in Zeile n, …)"; höchstens MaxFixedShown, '' ohne.</summary>
function FixedList(const ADeltas: TArray<TMcpFindingDelta>; ACount: Integer): string;
var
  mDelta: TMcpFindingDelta;
  mFinding: TRuleFinding;
  mParts: TArray<string>;
begin
  Result := '';
  mParts := nil;
  for mDelta in ADeltas do
  begin
    for mFinding in mDelta.Fixed do
    begin
      if Length(mParts) < TMcpEditFindings.cMaxFixedShown then
      begin
        mParts := mParts + [cTexts[TEditFindingsText.FixedAt].Fmt([mFinding.RuleId,
          mFinding.Range.StartPos.Line + 1])];
      end;
    end;
  end;
  if Length(mParts) = 0 then
  begin
    Exit;
  end;
  if ACount > Length(mParts) then
  begin
    mParts := mParts + ['…'];
  end;
  Result := ' (' + string.Join(', ', mParts) + ')';
end;

class function TMcpEditFindings.Report(const ARoot: string; const ADeltas: TArray<TMcpFindingDelta>): string;
var
  mDelta: TMcpFindingDelta;
  mFinding: TRuleFinding;
  mAdded, mFixed, mUnchanged, mShown: Integer;
  mLines: TArray<string>;
begin
  mAdded := 0;
  mFixed := 0;
  mUnchanged := 0;
  for mDelta in ADeltas do
  begin
    Inc(mAdded, Length(mDelta.Added));
    Inc(mFixed, Length(mDelta.Fixed));
    Inc(mUnchanged, mDelta.Unchanged);
  end;
  if mAdded = 0 then
  begin
    Exit(cTexts[TEditFindingsText.NoNew].Fmt([mFixed, FixedList(ADeltas, mFixed), mUnchanged]));
  end;
  mLines := [cTexts[TEditFindingsText.Heading].Text, cTexts[TEditFindingsText.NewCount].Fmt([mAdded])];
  mShown := 0;
  for mDelta in ADeltas do
  begin
    for mFinding in mDelta.Added do
    begin
      if mShown < cMaxShown then
      begin
        mLines := mLines + [Format('  %s:%d  %s – %s', [TMcpProtectedFiles.RelativePath(ARoot,
          mDelta.FileName), mFinding.Range.StartPos.Line + 1, mFinding.RuleId, mFinding.Message])];
      end;
      Inc(mShown);
    end;
  end;
  if mAdded > cMaxShown then
  begin
    mLines := mLines + [cTexts[TEditFindingsText.More].Fmt([mAdded - cMaxShown])];
  end;
  mLines := mLines + [cTexts[TEditFindingsText.Fixed].Fmt([mFixed, FixedList(ADeltas, mFixed)]),
    cTexts[TEditFindingsText.Unchanged].Fmt([mUnchanged])];
  Result := string.Join(sLineBreak, mLines);
end;

{ TMcpEditEvaluation }

constructor TMcpEditEvaluation.Create(const ARoot: string; const AFindingsOf: TMcpFindingsFunc;
  const AReadText: TMcpEditReadText; const AEnabled: TFunc<Boolean>);
begin
  inherited Create;
  FRoot := ARoot;
  FFindingsOf := AFindingsOf;
  FReadText := AReadText;
  FEnabled := AEnabled;
end;

function TMcpEditEvaluation.CurrentText(const AFileName, APlanned: string): string;
begin
  // Über den Bearbeitungseingang der IDE zählt, was wirklich im Puffer bzw. in der Datei steht.
  if not (Assigned(FReadText) and FReadText(AFileName, Result)) then
  begin
    Result := APlanned;
  end;
end;

function TMcpEditEvaluation.Run(const ATool: string; const ANames, AOldTexts, ANewTexts: TArray<string>): string;
var
  mDeltas: TArray<TMcpFindingDelta>;
  mIndex: Integer;
  mText: string;
  mShortNames: TArray<string>;
begin
  Result := '';
  if not Assigned(FFindingsOf) or (Assigned(FEnabled) and not FEnabled()) or (Length(ANames) = 0) then
  begin
    Exit;
  end;
  mDeltas := nil;
  mShortNames := nil;
  for mIndex := 0 to High(ANames) do
  begin
    mShortNames := mShortNames + [TMcpProtectedFiles.RelativePath(FRoot, ANames[mIndex])];
    mText := CurrentText(ANames[mIndex], ANewTexts[mIndex]);
    mDeltas := mDeltas + [TMcpEditFindings.Compare(ANames[mIndex], AOldTexts[mIndex], mText,
      FFindingsOf(ANames[mIndex], AOldTexts[mIndex]), FFindingsOf(ANames[mIndex], mText))];
  end;
  Result := TMcpEditFindings.Report(FRoot, mDeltas);
  FLast := cTexts[TEditFindingsText.LastHeader].Fmt([ATool, FormatDateTime('hh:nn:ss', Now, TFormatSettings.Invariant),
    string.Join(', ', mShortNames)]) + sLineBreak + Result;
end;

function TMcpEditEvaluation.Last: string;
begin
  Result := FLast;
  if Result = '' then
  begin
    Result := cTexts[TEditFindingsText.NoEditYet].Text;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Mcp.EditFindings', cTexts);

end.
