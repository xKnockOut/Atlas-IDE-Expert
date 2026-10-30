unit Atlas.Common.Rules.BulkFix;

// Sammelkorrektur (#1352): wendet die sicheren Korrekturen ausgewählter Regeln
// auf ganze Dateien an, für die Kommandozeile (--fix), MCP (fix_findings) und
// den Befehl „Alle sicheren Treffer korrigieren …“ des Plugins.
//
// - Ein Treffer zählt nur mit Konfidenz ab MinConfidence (fix.minConfidence,
//   Vorgabe hoch) und nur mit genau einer Korrektur, die Text der geprüften
//   Datei ändert, als sicher markiert ist (TRuleFix.Safe) und zu einer Regel
//   gehört, die der Katalog mit "safeFix" kennzeichnet. Korrekturen mit Auswahl
//   (mehrere Kandidaten, Alternative), in anderen Dateien oder in der
//   Formulardatei sind nie sicher.
// - Je Durchgang werden die Korrekturen nach Position von hinten nach vorn
//   genommen; überlappt eine eine schon genommene, bleibt sie für den nächsten
//   Durchgang, der den geänderten Text neu prüft. Höchstens MaxPasses
//   Durchgänge; was danach noch überlappt, zählt als Konflikt.
// - Am Ende darf der Text nicht mehr Syntaxfehler haben als vorher, sonst
//   bleibt die Datei unverändert (Rejected).
// - Die Zeilentabelle (TBulkFixLineMap) führt jede Zeile des geänderten Texts
//   auf ihre Zeile im Ausgangstext zurück; so wirken --changed-lines und
//   Filter nach Zeilen auch im zweiten und dritten Durchgang.
// - WriteAll schreibt alle Dateien oder keine: Scheitert eine, werden die schon
//   geschriebenen zurückgesetzt (derselbe Weg wie rename_symbol, #61).

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Scopes,
  Atlas.Common.Rules.Baseline,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Rules.Catalog;

type
  /// <summary>Warum ein Treffer nicht korrigiert wurde.</summary>
{$SCOPEDENUMS ON}
  TBulkFixSkip = (
    /// <summary>Konfidenz unter fix.minConfidence (bzw. minConfidence des Aufrufs).</summary>
    Confidence,
    /// <summary>Die Regel bietet keine Korrektur an, die Text ändert.</summary>
    NoFix,
    /// <summary>Keine sichere Korrektur: Regel ohne safeFix, Korrektur nicht sicher, mehrere Kandidaten, andere
    /// Dateien.</summary>
    Unsafe,
    /// <summary>Überlappt nach dem letzten Durchgang noch eine andere Korrektur.</summary>
    Conflict);
{$SCOPEDENUMS OFF}

  TBulkFixSkipCounts = array[TBulkFixSkip] of Integer;

  /// <summary>Was korrigiert werden soll.</summary>
  TBulkFixOptions = record
    /// <summary>Kennungen der Regeln (klein); nur mit All = False.</summary>
    Rules: TArray<string>;
    /// <summary>--fix all: alle Regeln.</summary>
    All: Boolean;
    /// <summary>Untergrenze der Konfidenz (fix.minConfidence, Vorgabe High).</summary>
    MinConfidence: TRuleConfidence;
    /// <summary>Regeln mit "safeFix" im Katalog (klein).</summary>
    SafeRules: TArray<string>;
    /// <summary>Regeln aus der Liste von --fix bzw. fix_findings ("all" = alle), Untergrenze und Katalog.</summary>
    class function Create(const ARules: TArray<string>; AMinConfidence: TRuleConfidence;
      const ACatalog: TArray<TRuleCatalogEntry>): TBulkFixOptions; static;
    function Wants(const ARuleId: string): Boolean;
  end;

  /// <summary>Zeile im Ausgangstext zu jeder Zeile des geänderten Texts.</summary>
  TBulkFixLineMap = record
  private
    /// <summary>nil = unverändert (Zeile n ist Zeile n).</summary>
    FLines: TArray<Integer>;
  public
    class function Identity: TBulkFixLineMap; static;
    /// <summary>Zeile im Ausgangstext; außerhalb der Tabelle die Zeile selbst.</summary>
    function Original(ALine: Integer): Integer;
    /// <summary>Tabelle für den Text nach AEdits (ohne Überlappung) auf einem Text mit ALineCount Zeilen. Neue Zeilen
    /// einer Korrektur gehören zu deren erster Zeile, die Zeile mit ihrem Ende zu deren letzter.</summary>
    function After(ALineCount: Integer; const AEdits: TArray<TTextEdit>): TBulkFixLineMap;
  end;

  /// <summary>Treffer für AText; ALines führt dessen Zeilen auf den Ausgangstext zurück, etwa für --changed-lines.
  /// Gibt schon gefilterte Treffer zurück (Baseline, Bereich, Regeln).</summary>
  TBulkFixCheck = reference to function(const AText: string; const ALines: TBulkFixLineMap): TArray<TRuleFinding>;
  /// <summary>Anzahl der Syntaxfehler in AText mit den Symbolen der Datei.</summary>
  TBulkFixSyntaxErrors = reference to function(const AText: string): Integer;
  /// <summary>Schreibt AText nach AFileName (Kodierung und Zeilenenden erhalten); Fehler als Exception.</summary>
  TBulkFixWrite = reference to procedure(const AFileName, AText: string);

  TBulkFixRuleCount = record
    RuleId: string;
    Count: Integer;
  end;

  /// <summary>Ergebnis einer Datei.</summary>
  TBulkFixFile = record
    FileName: string;
    OldText: string;
    /// <summary>Text nach den Korrekturen; gleich OldText, wenn nichts geändert oder verworfen wurde.</summary>
    NewText: string;
    /// <summary>Korrekturen je Regel, in der Reihenfolge des ersten Auftretens.</summary>
    Applied: TArray<TBulkFixRuleCount>;
    Skipped: TBulkFixSkipCounts;
    Passes: Integer;
    /// <summary>Verworfen, weil neue Syntaxfehler entstanden wären; NewText = OldText.</summary>
    Rejected: Boolean;
    /// <summary>Zeilen von NewText im Ausgangstext, etwa um danach verbliebene Treffer zu filtern.</summary>
    Lines: TBulkFixLineMap;
    /// <summary>Text geändert und nicht verworfen.</summary>
    function Changed: Boolean;
    /// <summary>Anzahl der angewendeten Korrekturen.</summary>
    function FixCount: Integer;
  end;

  EBulkFixWrite = class(Exception);

  TBulkFix = class
  public const
    MaxPasses = 3;
    /// <summary>Kontextzeilen im vereinigten Diff.</summary>
    DiffContext = 3;
  public
    /// <summary>Die eine sichere Korrektur von AFinding; sonst False und der Grund in ASkip.</summary>
    class function SafeFixOf(const AFinding: TRuleFinding; const AOptions: TBulkFixOptions; out AFix: TRuleFix;
      out ASkip: TBulkFixSkip): Boolean; static;
    /// <summary>Korrigiert AText von AFileName (siehe Unit-Kopf). ACheck prüft je Durchgang, ASyntaxErrors zählt die
    /// Syntaxfehler vorher und nachher.</summary>
    class function Run(const AFileName, AText: string; const AOptions: TBulkFixOptions; const ACheck: TBulkFixCheck;
      const ASyntaxErrors: TBulkFixSyntaxErrors): TBulkFixFile; static;
    /// <summary>Haben sich A und B überlappt? Bereiche, die sich nur berühren, nicht; zwei Einfügungen an derselben
    /// Stelle schon (ihre Reihenfolge wäre offen).</summary>
    class function Overlaps(const A, B: TTextRange): Boolean; static;
    /// <summary>Vereinigter Diff (TTextDiff.Unified) einer Datei mit ihrem Namen ADisplayName (z. B. relativ, mit /).
    /// Leer ohne Änderung.</summary>
    class function Diff(const ADisplayName: string; const AFile: TBulkFixFile): string; static;
    /// <summary>Zusammenfassung für stderr bzw. den Bericht: Dateien, Korrekturen je Regel, übersprungene Treffer
    /// je Grund und verworfene Dateien; Zeilen mit ALineBreak.</summary>
    class function Summary(const AFiles: TArray<TBulkFixFile>; ADryRun: Boolean; const ALineBreak: string): string;
      static;
    /// <summary>Alle geänderten Dateien aus AFiles schreiben oder keine: Scheitert eine, werden die schon
    /// geschriebenen auf OldText zurückgesetzt und EBulkFixWrite ausgelöst. Liefert die Anzahl der Dateien.
    /// </summary>
    class function WriteAll(const AFiles: TArray<TBulkFixFile>; const AWrite: TBulkFixWrite): Integer; overload;
      static;
    /// <summary>Wie oben für Namen, alte und neue Texte gleicher Länge (MCP, #61).</summary>
    class function WriteAll(const ANames, AOldTexts, ANewTexts: TArray<string>; const AWrite: TBulkFixWrite): Integer;
      overload; static;
    /// <summary>Kennungen (klein) der Regeln mit "safeFix" in ACatalog.</summary>
    class function SafeRulesOf(const ACatalog: TArray<TRuleCatalogEntry>): TArray<string>; static;
    /// <summary>Text der Konfidenz für Meldungen: "hoch", "mittel", "niedrig".</summary>
    class function ConfidenceText(AConfidence: TRuleConfidence): string; static;
    /// <summary>Untergrenze eines Aufrufs (fix_findings, Befehl des Plugins): ARequested ("medium", "high"; ''
    /// = Einstellung) darf ASetting (fix.minConfidence) nur anheben. False mit Grund in AError.</summary>
    class function MinConfidenceOf(ASetting: TRuleConfidence; const ARequested: string;
      out AConfidence: TRuleConfidence; out AError: string): Boolean; static;
    /// <summary>Regeln für die Durchgänge: nur die aus AFixRules, damit jeder Durchgang schnell bleibt. Mit "all"
    /// oder einer Kennung, die keine Regel aus AAll ist (syntax, unused-suppression, unknown-rule-id entstehen in
    /// Checker bzw. Engine und brauchen die übrigen Regeln), alle.</summary>
    class function RulesFor(const AAll: TArray<IRule>; const AFixRules: TArray<string>): TArray<IRule>; static;
    /// <summary>Prüfung je Durchgang ohne weitere Filter (MCP, Plugin): Regeln, Einstellungen, Projekt und Symbole
    /// wie TFileChecker.CheckText.</summary>
    class function CheckWith(const ARules: TArray<IRule>; const ASettings: TServerSettings;
      const ARelativePath: string; const AProject: TCheckProject; const ASource: TCheckSource): TBulkFixCheck;
      overload; static;
    /// <summary>Wie oben ohne die Treffer aus ABaseline (#97): Was festgehalten ist, bleibt unverändert.</summary>
    class function CheckWith(const ARules: TArray<IRule>; const ASettings: TServerSettings;
      const ARelativePath: string; const AProject: TCheckProject; const ASource: TCheckSource;
      const ABaseline: IRuleBaseline): TBulkFixCheck; overload; static;
    /// <summary>Syntaxfehler eines Texts mit den Symbolen und Include-Dateien aus ASource.</summary>
    class function SyntaxErrorsWith(const ASource: TCheckSource): TBulkFixSyntaxErrors; static;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Text.Lines,
  Atlas.Text.Diff,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Editing.TextChanges;

const
  cAllRules = 'all';

type
  /// <summary>Korrektur eines Treffers für einen Durchgang.</summary>
  TCandidate = record
    RuleId: string;
    Fix: TRuleFix;
    /// <summary>Früheste Stelle der Edits.</summary>
    Start: TTextPosition;
  end;

function ComparePosition(const A, B: TTextPosition): Integer;
begin
  if A.Line <> B.Line then
    Result := CompareValue(A.Line, B.Line)
  else
    Result := CompareValue(A.Character, B.Character);
end;

function LineBreaksIn(const AText: string): Integer;
begin
  Result := Length(TTextLines.SplitLines(AText)) - 1;
end;

{ TBulkFixOptions }

class function TBulkFixOptions.Create(const ARules: TArray<string>; AMinConfidence: TRuleConfidence;
  const ACatalog: TArray<TRuleCatalogEntry>): TBulkFixOptions;
var
  mRule: string;
begin
  Result := Default(TBulkFixOptions);
  Result.MinConfidence := AMinConfidence;
  Result.SafeRules := TBulkFix.SafeRulesOf(ACatalog);
  for mRule in ARules do
    if SameText(Trim(mRule), cAllRules) then
      Result.All := True
    else if Trim(mRule) <> '' then
      Result.Rules := Result.Rules + [LowerCase(Trim(mRule))];
end;

function TBulkFixOptions.Wants(const ARuleId: string): Boolean;
begin
  Result := All or (IndexText(ARuleId, Rules) >= 0);
end;

{ TBulkFixLineMap }

class function TBulkFixLineMap.Identity: TBulkFixLineMap;
begin
  Result.FLines := nil;
end;

function TBulkFixLineMap.Original(ALine: Integer): Integer;
begin
  if (FLines = nil) or (ALine < 0) or (ALine > High(FLines)) then
    Result := ALine
  else
    Result := FLines[ALine];
end;

function TBulkFixLineMap.After(ALineCount: Integer; const AEdits: TArray<TTextEdit>): TBulkFixLineMap;
var
  mSorted: TArray<TTextEdit>;
  mEdit: TTextEdit;
  mList: TList<Integer>;
  mCursor, mLine, mBreaks, mBreak, mStart, mEnd: Integer;
begin
  mSorted := Copy(AEdits);
  TArray.Sort<TTextEdit>(mSorted, TComparer<TTextEdit>.Construct(
    function(const A, B: TTextEdit): Integer
    begin
      Result := ComparePosition(A.Range.StartPos, B.Range.StartPos);
      if Result = 0 then
        Result := ComparePosition(A.Range.EndPos, B.Range.EndPos);
    end));
  mList := TList<Integer>.Create;
  try
    mCursor := 0;
    for mEdit in mSorted do
    begin
      mStart := mEdit.Range.StartPos.Line;
      mEnd := Max(mStart, mEdit.Range.EndPos.Line);
      mBreaks := LineBreaksIn(mEdit.NewText);
      // Liegt der Anfang in der Zeile, in der die vorige Korrektur endet, steht diese Zeile schon in der Tabelle.
      if mStart >= mCursor then
      begin
        for mLine := mCursor to mStart - 1 do
          mList.Add(Original(mLine));
        // Ganze Zeilen gelöscht: Die Zeile beginnt mit dem Rest der letzten Zeile der Korrektur.
        if (mBreaks = 0) and (mEdit.Range.StartPos.Character = 0) and (mEdit.NewText = '') then
          mList.Add(Original(mEnd))
        else
          mList.Add(Original(mStart));
      end;
      for mBreak := 1 to mBreaks do
        if mBreak = mBreaks then
          mList.Add(Original(mEnd))
        else
          mList.Add(Original(mStart));
      mCursor := Max(mCursor, mEnd + 1);
    end;
    for mLine := mCursor to ALineCount - 1 do
      mList.Add(Original(mLine));
    Result.FLines := mList.ToArray;
  finally
    mList.Free;
  end;
end;

{ TBulkFixFile }

function TBulkFixFile.Changed: Boolean;
begin
  Result := not Rejected and (NewText <> OldText);
end;

function TBulkFixFile.FixCount: Integer;
var
  mCount: TBulkFixRuleCount;
begin
  Result := 0;
  for mCount in Applied do
    Inc(Result, mCount.Count);
end;

{ TBulkFix }

class function TBulkFix.SafeRulesOf(const ACatalog: TArray<TRuleCatalogEntry>): TArray<string>;
var
  mEntry: TRuleCatalogEntry;
begin
  Result := nil;
  for mEntry in ACatalog do
    if mEntry.SafeFix then
      Result := Result + [LowerCase(mEntry.Id)];
end;

class function TBulkFix.ConfidenceText(AConfidence: TRuleConfidence): string;
begin
  case AConfidence of
    TRuleConfidence.Low:
      Result := 'niedrig';
    TRuleConfidence.Medium:
      Result := 'mittel';
  else
    Result := 'hoch';
  end;
end;

class function TBulkFix.MinConfidenceOf(ASetting: TRuleConfidence; const ARequested: string;
  out AConfidence: TRuleConfidence; out AError: string): Boolean;
begin
  AError := '';
  AConfidence := ASetting;
  if Trim(ARequested) = '' then
    Exit(True);
  Result := TConfigurationParser.TryParseConfidence(Trim(ARequested), AConfidence) and
    (AConfidence <> TRuleConfidence.Low);
  if not Result then
  begin
    AError := 'minConfidence ist "medium" oder "high"';
    Exit;
  end;
  if Ord(AConfidence) < Ord(ASetting) then
  begin
    AError := Format('minConfidence "%s" liegt unter fix.minConfidence (%s)', [Trim(ARequested),
      ConfidenceText(ASetting)]);
    Result := False;
  end;
end;

class function TBulkFix.RulesFor(const AAll: TArray<IRule>; const AFixRules: TArray<string>): TArray<IRule>;
var
  mRule: IRule;
  mId: string;
  mFound: Boolean;
begin
  Result := nil;
  for mId in AFixRules do
  begin
    if SameText(Trim(mId), cAllRules) then
      Exit(AAll);
    mFound := False;
    for mRule in AAll do
      if SameText(mRule.Descriptor.Id, Trim(mId)) then
      begin
        Result := Result + [mRule];
        mFound := True;
      end;
    if not mFound then
      Exit(AAll);
  end;
end;

class function TBulkFix.CheckWith(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const ARelativePath: string; const AProject: TCheckProject; const ASource: TCheckSource): TBulkFixCheck;
begin
  Result :=
    function(const AText: string; const ALines: TBulkFixLineMap): TArray<TRuleFinding>
    var
      mScopes: TFindingScopes;
    begin
      Result := TFileChecker.CheckText(ARules, ASettings, ARelativePath, AText, AProject, ASource, mScopes);
    end;
end;

class function TBulkFix.CheckWith(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const ARelativePath: string; const AProject: TCheckProject; const ASource: TCheckSource;
  const ABaseline: IRuleBaseline): TBulkFixCheck;
begin
  if ABaseline = nil then
    Exit(CheckWith(ARules, ASettings, ARelativePath, AProject, ASource));
  Result :=
    function(const AText: string; const ALines: TBulkFixLineMap): TArray<TRuleFinding>
    var
      mScopes: TFindingScopes;
    begin
      Result := TFileChecker.CheckText(ARules, ASettings, ARelativePath, AText, AProject, ASource, mScopes);
      Result := ABaseline.Filter(ARelativePath, AText, mScopes, Result);
    end;
end;

class function TBulkFix.SyntaxErrorsWith(const ASource: TCheckSource): TBulkFixSyntaxErrors;
begin
  Result :=
    function(const AText: string): Integer
    var
      mProcessed: TPreprocessorResult;
      mTree: TSyntaxTree;
    begin
      mTree := TSyntaxTreeCache.ParseActive(AText, ASource.Options, nil, mProcessed);
      try
        Result := Length(mTree.Diagnostics);
      finally
        mTree.Free;
      end;
    end;
end;

class function TBulkFix.Overlaps(const A, B: TTextRange): Boolean;
begin
  if A.StartPos = B.StartPos then
    Exit(True);
  Result := (ComparePosition(A.StartPos, B.EndPos) < 0) and (ComparePosition(B.StartPos, A.EndPos) < 0);
end;

class function TBulkFix.SafeFixOf(const AFinding: TRuleFinding; const AOptions: TBulkFixOptions; out AFix: TRuleFix;
  out ASkip: TBulkFixSkip): Boolean;
var
  mFix: TRuleFix;
  mCount: Integer;
begin
  Result := False;
  AFix := Default(TRuleFix);
  if Ord(AFinding.Confidence) < Ord(AOptions.MinConfidence) then
  begin
    ASkip := TBulkFixSkip.Confidence;
    Exit;
  end;
  // Nur Korrekturen, die Text ändern: Sprünge und „Graph zeigen“ zählen nicht.
  mCount := 0;
  for mFix in AFinding.Fixes do
    if (mFix.Edits <> nil) or (mFix.OtherFiles <> nil) then
    begin
      Inc(mCount);
      AFix := mFix;
    end;
  if mCount = 0 then
  begin
    ASkip := TBulkFixSkip.NoFix;
    Exit;
  end;
  ASkip := TBulkFixSkip.Unsafe;
  if (mCount > 1) or (IndexText(AFinding.RuleId, AOptions.SafeRules) < 0) or not AFix.Safe or AFix.Alternative or
    (AFix.OtherFiles <> nil) or (AFix.FileName <> '') or (AFix.Edits = nil) then
    Exit;
  Result := True;
end;

class function TBulkFix.Run(const AFileName, AText: string; const AOptions: TBulkFixOptions;
  const ACheck: TBulkFixCheck; const ASyntaxErrors: TBulkFixSyntaxErrors): TBulkFixFile;
var
  mText: string;
  mLines: TBulkFixLineMap;
  mPass, mIndex, mDeferred: Integer;
  mFinding: TRuleFinding;
  mCandidate: TCandidate;
  mCandidates: TList<TCandidate>;
  mTaken: TList<TTextEdit>;
  mEdit, mOther: TTextEdit;
  mSkip: TBulkFixSkip;
  mFits: Boolean;

  procedure Count(const ARuleId: string);
  var
    mPosition: Integer;
  begin
    for mPosition := 0 to High(Result.Applied) do
      if SameText(Result.Applied[mPosition].RuleId, ARuleId) then
      begin
        Inc(Result.Applied[mPosition].Count);
        Exit;
      end;
    SetLength(Result.Applied, Length(Result.Applied) + 1);
    Result.Applied[High(Result.Applied)].RuleId := ARuleId;
    Result.Applied[High(Result.Applied)].Count := 1;
  end;

begin
  Result := Default(TBulkFixFile);
  Result.FileName := AFileName;
  Result.OldText := AText;
  Result.NewText := AText;
  Result.Lines := TBulkFixLineMap.Identity;
  mText := AText;
  mLines := TBulkFixLineMap.Identity;
  mDeferred := 0;
  mCandidates := TList<TCandidate>.Create;
  mTaken := TList<TTextEdit>.Create;
  try
    for mPass := 1 to MaxPasses do
    begin
      mCandidates.Clear;
      for mFinding in ACheck(mText, mLines) do
      begin
        if not AOptions.Wants(mFinding.RuleId) then
          Continue;
        if TBulkFix.SafeFixOf(mFinding, AOptions, mCandidate.Fix, mSkip) then
        begin
          mCandidate.RuleId := mFinding.RuleId;
          mCandidate.Start := mCandidate.Fix.Edits[0].Range.StartPos;
          for mEdit in mCandidate.Fix.Edits do
            if ComparePosition(mEdit.Range.StartPos, mCandidate.Start) < 0 then
              mCandidate.Start := mEdit.Range.StartPos;
          mCandidates.Add(mCandidate);
        end
        // Übersprungen wird nach dem Ausgangstext gezählt; spätere Durchgänge sehen dieselben Treffer noch einmal.
        else if mPass = 1 then
          Inc(Result.Skipped[mSkip]);
      end;
      if mCandidates.Count = 0 then
        Break;
      // Von hinten nach vorn; bei gleicher Stelle nach Regel, damit die Reihenfolge feststeht (Sort ist nicht stabil).
      mCandidates.Sort(TComparer<TCandidate>.Construct(
        function(const A, B: TCandidate): Integer
        begin
          Result := ComparePosition(B.Start, A.Start);
          if Result = 0 then
            Result := CompareText(A.RuleId, B.RuleId);
          if Result = 0 then
            Result := CompareText(A.Fix.Title, B.Fix.Title);
        end));
      mTaken.Clear;
      mDeferred := 0;
      for mIndex := 0 to mCandidates.Count - 1 do
      begin
        mCandidate := mCandidates[mIndex];
        mFits := True;
        for mEdit in mCandidate.Fix.Edits do
          for mOther in mTaken do
            if Overlaps(mEdit.Range, mOther.Range) then
              mFits := False;
        // Eine Korrektur ganz oder gar nicht; die überlappende kommt im nächsten Durchgang dran.
        if not mFits then
        begin
          Inc(mDeferred);
          Continue;
        end;
        mTaken.AddRange(mCandidate.Fix.Edits);
        Count(mCandidate.RuleId);
      end;
      mLines := mLines.After(TLineTable.Build(mText).LineCount, mTaken.ToArray);
      mText := TTextChanges.Apply(mText, mTaken.ToArray);
      Result.Passes := mPass;
      if mDeferred = 0 then
        Break;
      if mPass = MaxPasses then
        Inc(Result.Skipped[TBulkFixSkip.Conflict], mDeferred);
    end;
  finally
    mTaken.Free;
    mCandidates.Free;
  end;
  if mText = AText then
    Exit;
  // Keine neuen Syntaxfehler: sonst bleibt die Datei, wie sie ist.
  if ASyntaxErrors(mText) > ASyntaxErrors(AText) then
  begin
    Result.Rejected := True;
    Exit;
  end;
  Result.NewText := mText;
  Result.Lines := mLines;
end;

class function TBulkFix.Diff(const ADisplayName: string; const AFile: TBulkFixFile): string;
begin
  if not AFile.Changed then
    Exit('');
  Result := string.Join(sLineBreak, TTextDiff.Unified('a/' + ADisplayName, 'b/' + ADisplayName,
    TTextLines.SplitLines(AFile.OldText), TTextLines.SplitLines(AFile.NewText), DiffContext)) + sLineBreak;
end;

class function TBulkFix.Summary(const AFiles: TArray<TBulkFixFile>; ADryRun: Boolean; const ALineBreak: string):
  string;
var
  mFile: TBulkFixFile;
  mCount: TBulkFixRuleCount;
  mTotals: TList<TBulkFixRuleCount>;
  mSkipped: TBulkFixSkipCounts;
  mSkip: TBulkFixSkip;
  mChanged, mFixes, mIndex: Integer;
  mFound: Boolean;
  mLines: TArray<string>;
  mTotal: TBulkFixRuleCount;
begin
  mSkipped := Default(TBulkFixSkipCounts);
  mChanged := 0;
  mFixes := 0;
  mLines := nil;
  mTotals := TList<TBulkFixRuleCount>.Create;
  try
    for mFile in AFiles do
    begin
      for mSkip := Low(TBulkFixSkip) to High(TBulkFixSkip) do
        Inc(mSkipped[mSkip], mFile.Skipped[mSkip]);
      if not mFile.Changed then
        Continue;
      Inc(mChanged);
      for mCount in mFile.Applied do
      begin
        Inc(mFixes, mCount.Count);
        mFound := False;
        for mIndex := 0 to mTotals.Count - 1 do
          if SameText(mTotals[mIndex].RuleId, mCount.RuleId) then
          begin
            mTotal := mTotals[mIndex];
            Inc(mTotal.Count, mCount.Count);
            mTotals[mIndex] := mTotal;
            mFound := True;
          end;
        if not mFound then
          mTotals.Add(mCount);
      end;
    end;
    if ADryRun then
      mLines := mLines + [Format('Vorschau: %d Korrekturen in %d Dateien, nichts geschrieben', [mFixes, mChanged])]
    else
      mLines := mLines + [Format('%d Korrekturen in %d Dateien geschrieben', [mFixes, mChanged])];
    mTotals.Sort(TComparer<TBulkFixRuleCount>.Construct(
      function(const A, B: TBulkFixRuleCount): Integer
      begin
        Result := CompareText(A.RuleId, B.RuleId);
      end));
    for mTotal in mTotals do
      mLines := mLines + [Format('  %s: %d', [mTotal.RuleId, mTotal.Count])];
    if mSkipped[TBulkFixSkip.Confidence] + mSkipped[TBulkFixSkip.Unsafe] + mSkipped[TBulkFixSkip.Conflict] +
      mSkipped[TBulkFixSkip.NoFix] > 0 then
      mLines := mLines + [Format('Übersprungen: %d mit zu niedriger Konfidenz, %d unsicher, %d Konflikt, %d ohne ' +
        'Korrektur', [mSkipped[TBulkFixSkip.Confidence], mSkipped[TBulkFixSkip.Unsafe],
        mSkipped[TBulkFixSkip.Conflict], mSkipped[TBulkFixSkip.NoFix]])];
    for mFile in AFiles do
      if mFile.Rejected then
        mLines := mLines + [Format('Verworfen (die Korrekturen hätten Syntaxfehler erzeugt): %s', [mFile.FileName])];
  finally
    mTotals.Free;
  end;
  Result := string.Join(ALineBreak, mLines);
end;

class function TBulkFix.WriteAll(const AFiles: TArray<TBulkFixFile>; const AWrite: TBulkFixWrite): Integer;
var
  mFile: TBulkFixFile;
  mNames, mOld, mNew: TArray<string>;
begin
  mNames := nil;
  mOld := nil;
  mNew := nil;
  for mFile in AFiles do
    if mFile.Changed then
    begin
      mNames := mNames + [mFile.FileName];
      mOld := mOld + [mFile.OldText];
      mNew := mNew + [mFile.NewText];
    end;
  Result := WriteAll(mNames, mOld, mNew, AWrite);
end;

class function TBulkFix.WriteAll(const ANames, AOldTexts, ANewTexts: TArray<string>;
  const AWrite: TBulkFixWrite): Integer;
var
  mIndex, mWritten: Integer;
begin
  mWritten := 0;
  try
    for mIndex := 0 to High(ANames) do
    begin
      AWrite(ANames[mIndex], ANewTexts[mIndex]);
      Inc(mWritten);
    end;
  except
    on E: Exception do
    begin
      // Alles oder nichts: schon geschriebene Dateien zurücksetzen.
      for mIndex := mWritten - 1 downto 0 do
        try
          AWrite(ANames[mIndex], AOldTexts[mIndex]);
        except
          // Zurücksetzen nach Kräften; gemeldet wird der erste Fehler, der die übrigen Dateien verhindert hat.
          on Exception do
            Continue;
        end;
      raise EBulkFixWrite.CreateFmt('Schreiben fehlgeschlagen (%s); alle Dateien zurückgesetzt.', [E.Message]);
    end;
  end;
  Result := mWritten;
end;

end.
