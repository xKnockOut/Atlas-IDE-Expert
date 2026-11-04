unit Atlas.Common.Rules.BulkFix;

// Sammelkorrektur (#1352): wendet die sicheren Korrekturen ausgewählter Regeln
// auf ganze Dateien an, für die Kommandozeile (--fix), MCP (fix_findings) und
// den Befehl „Alle sicheren Treffer korrigieren …“ des Plugins.
//
// - Ein Treffer zählt nur mit Konfidenz ab MinConfidence (fix.minConfidence,
//   Vorgabe hoch) und nur mit genau einer Korrektur, die Text der geprüften
//   Datei ändert, als sicher markiert ist (TRuleFix.Safe) und zu einer Regel
//   gehört, die der Katalog mit "safeFix" kennzeichnet. Weitere, nicht sichere
//   Korrekturen daneben (begin … end in der ganzen Methode) stören nicht, wie
//   bei source.fixAll. Korrekturen mit Auswahl (mehrere sichere, Alternative),
//   in anderen Dateien oder in der Formulardatei sind nie sicher.
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
  begin
    Result := CompareValue(A.Line, B.Line);
  end
  else
  begin
    Result := CompareValue(A.Character, B.Character);
  end;
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
  begin
    if SameText(Trim(mRule), cAllRules) then
    begin
      Result.All := True;
    end
    else if Trim(mRule) <> '' then
    begin
      Result.Rules := Result.Rules + [LowerCase(Trim(mRule))];
    end;
  end;
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
  begin
    Result := ALine;
  end
  else
  begin
    Result := FLines[ALine];
  end;
end;

/// <summary>AEdits nach Anfang, bei gleichem Anfang nach Ende.</summary>
function SortedEdits(const AEdits: TArray<TTextEdit>): TArray<TTextEdit>;
begin
  Result := Copy(AEdits);
  TArray.Sort<TTextEdit>(Result, TComparer<TTextEdit>.Construct(
    function(const A, B: TTextEdit): Integer
    begin
      Result := ComparePosition(A.Range.StartPos, B.Range.StartPos);
      if Result = 0 then
      begin
        Result := ComparePosition(A.Range.EndPos, B.Range.EndPos);
      end;
    end));
end;

/// <summary>Zeilen bis einschließlich der Korrektur AEdit in AList; ACursor ist die erste noch nicht
/// eingetragene Zeile des Ausgangstexts.</summary>
procedure AddEditLines(const AMap: TBulkFixLineMap; AList: TList<Integer>; const AEdit: TTextEdit;
  var ACursor: Integer);
var
  mLine, mBreaks, mBreak, mStart, mEnd: Integer;
begin
  mStart := AEdit.Range.StartPos.Line;
  mEnd := Max(mStart, AEdit.Range.EndPos.Line);
  mBreaks := LineBreaksIn(AEdit.NewText);
  // Liegt der Anfang in der Zeile, in der die vorige Korrektur endet, steht diese Zeile schon in der Tabelle.
  if mStart >= ACursor then
  begin
    for mLine := ACursor to mStart - 1 do
    begin
      AList.Add(AMap.Original(mLine));
    end;
    // Ganze Zeilen gelöscht: Die Zeile beginnt mit dem Rest der letzten Zeile der Korrektur.
    if (mBreaks = 0) and (AEdit.Range.StartPos.Character = 0) and (AEdit.NewText = '') then
    begin
      AList.Add(AMap.Original(mEnd));
    end
    else
    begin
      AList.Add(AMap.Original(mStart));
    end;
  end;
  for mBreak := 1 to mBreaks - 1 do
  begin
    AList.Add(AMap.Original(mStart));
  end;
  if mBreaks > 0 then
  begin
    AList.Add(AMap.Original(mEnd));
  end;
  ACursor := Max(ACursor, mEnd + 1);
end;

function TBulkFixLineMap.After(ALineCount: Integer; const AEdits: TArray<TTextEdit>): TBulkFixLineMap;
var
  mEdit: TTextEdit;
  mList: TList<Integer>;
  mCursor, mLine: Integer;
begin
  mList := TList<Integer>.Create;
  try
    mCursor := 0;
    for mEdit in SortedEdits(AEdits) do
    begin
      AddEditLines(Self, mList, mEdit, mCursor);
    end;
    for mLine := mCursor to ALineCount - 1 do
    begin
      mList.Add(Original(mLine));
    end;
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
  begin
    Inc(Result, mCount.Count);
  end;
end;

{ TBulkFix }

class function TBulkFix.SafeRulesOf(const ACatalog: TArray<TRuleCatalogEntry>): TArray<string>;
var
  mEntry: TRuleCatalogEntry;
begin
  Result := nil;
  for mEntry in ACatalog do
  begin
    if mEntry.SafeFix then
    begin
      Result := Result + [LowerCase(mEntry.Id)];
    end;
  end;
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
  begin
    Exit(True);
  end;
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
    begin
      Exit(AAll);
    end;
    mFound := False;
    for mRule in AAll do
    begin
      if SameText(mRule.Descriptor.Id, Trim(mId)) then
      begin
        Result := Result + [mRule];
        mFound := True;
      end;
    end;
    if not mFound then
    begin
      Exit(AAll);
    end;
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
      Result := TFileChecker.CheckText(ARules, ASettings, ARelativePath, AText,
        TCheckOrigin.Make(AProject, ASource), mScopes);
    end;
end;

class function TBulkFix.CheckWith(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const ARelativePath: string; const AProject: TCheckProject; const ASource: TCheckSource;
  const ABaseline: IRuleBaseline): TBulkFixCheck;
begin
  if ABaseline = nil then
  begin
    Exit(CheckWith(ARules, ASettings, ARelativePath, AProject, ASource));
  end;
  Result :=
    function(const AText: string; const ALines: TBulkFixLineMap): TArray<TRuleFinding>
    var
      mScopes: TFindingScopes;
    begin
      Result := TFileChecker.CheckText(ARules, ASettings, ARelativePath, AText,
        TCheckOrigin.Make(AProject, ASource), mScopes);
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
  begin
    Exit(True);
  end;
  Result := (ComparePosition(A.StartPos, B.EndPos) < 0) and (ComparePosition(B.StartPos, A.EndPos) < 0);
end;

class function TBulkFix.SafeFixOf(const AFinding: TRuleFinding; const AOptions: TBulkFixOptions; out AFix: TRuleFix;
  out ASkip: TBulkFixSkip): Boolean;
var
  mFix: TRuleFix;
  mCount, mTextFixes: Integer;
begin
  Result := False;
  AFix := Default(TRuleFix);
  if Ord(AFinding.Confidence) < Ord(AOptions.MinConfidence) then
  begin
    ASkip := TBulkFixSkip.Confidence;
    Exit;
  end;
  // Nur Korrekturen, die Text ändern: Sprünge und „Graph zeigen“ zählen nicht. Genommen wird die eine sichere
  // Korrektur wie bei source.fixAll; weitere, nicht sichere (begin … end in der ganzen Methode) bleiben eine
  // Auswahl für den Benutzer. Zwei sichere sind selbst eine Auswahl.
  mTextFixes := 0;
  mCount := 0;
  for mFix in AFinding.Fixes do
  begin
    if (mFix.Edits <> nil) or (mFix.OtherFiles <> nil) then
    begin
      Inc(mTextFixes);
      if mFix.Safe and not mFix.Alternative then
      begin
        Inc(mCount);
        AFix := mFix;
      end;
    end;
  end;
  if mTextFixes = 0 then
  begin
    ASkip := TBulkFixSkip.NoFix;
    Exit;
  end;
  ASkip := TBulkFixSkip.Unsafe;
  if (mCount <> 1) or (IndexText(AFinding.RuleId, AOptions.SafeRules) < 0) or (AFix.OtherFiles <> nil) or
    (AFix.FileName <> '') or (AFix.Edits = nil) then
  begin
    AFix := Default(TRuleFix);
    Exit;
  end;
  Result := True;
end;

/// <summary>Zählt eine angewendete Korrektur der Regel ARuleId.</summary>
procedure CountRule(var AApplied: TArray<TBulkFixRuleCount>; const ARuleId: string; ACount: Integer);
var
  mPosition: Integer;
begin
  for mPosition := 0 to High(AApplied) do
  begin
    if SameText(AApplied[mPosition].RuleId, ARuleId) then
    begin
      Inc(AApplied[mPosition].Count, ACount);
      Exit;
    end;
  end;
  SetLength(AApplied, Length(AApplied) + 1);
  AApplied[High(AApplied)].RuleId := ARuleId;
  AApplied[High(AApplied)].Count := ACount;
end;

/// <summary>Kandidat zu AFix mit der frühesten Stelle seiner Edits.</summary>
function CandidateOf(const ARuleId: string; const AFix: TRuleFix): TCandidate;
var
  mEdit: TTextEdit;
begin
  Result.RuleId := ARuleId;
  Result.Fix := AFix;
  Result.Start := AFix.Edits[0].Range.StartPos;
  for mEdit in AFix.Edits do
  begin
    if ComparePosition(mEdit.Range.StartPos, Result.Start) < 0 then
    begin
      Result.Start := mEdit.Range.StartPos;
    end;
  end;
end;

/// <summary>Sichere Korrekturen aus AFindings von hinten nach vorn; bei gleicher Stelle nach Regel und Titel,
/// damit die Reihenfolge feststeht (Sort ist nicht stabil). Übersprungene zählen nur mit ACountSkipped, also nach
/// dem Ausgangstext; spätere Durchgänge sehen dieselben Treffer noch einmal.</summary>
function CandidatesOf(const AFindings: TArray<TRuleFinding>; const AOptions: TBulkFixOptions;
  ACountSkipped: Boolean; var ASkipped: TBulkFixSkipCounts): TArray<TCandidate>;
var
  mFinding: TRuleFinding;
  mFix: TRuleFix;
  mSkip: TBulkFixSkip;
begin
  Result := nil;
  for mFinding in AFindings do
  begin
    if not AOptions.Wants(mFinding.RuleId) then
    begin
      Continue;
    end;
    if TBulkFix.SafeFixOf(mFinding, AOptions, mFix, mSkip) then
    begin
      Result := Result + [CandidateOf(mFinding.RuleId, mFix)];
    end
    else if ACountSkipped then
    begin
      Inc(ASkipped[mSkip]);
    end;
  end;
  TArray.Sort<TCandidate>(Result, TComparer<TCandidate>.Construct(
    function(const A, B: TCandidate): Integer
    begin
      Result := ComparePosition(B.Start, A.Start);
      if Result = 0 then
      begin
        Result := CompareText(A.RuleId, B.RuleId);
      end;
      if Result = 0 then
      begin
        Result := CompareText(A.Fix.Title, B.Fix.Title);
      end;
    end));
end;

/// <summary>Überlappt keine Änderung aus AEdits eine aus ATaken?</summary>
function FitsBeside(const AEdits: TArray<TTextEdit>; ATaken: TList<TTextEdit>): Boolean;
var
  mEdit, mOther: TTextEdit;
begin
  for mEdit in AEdits do
  begin
    for mOther in ATaken do
    begin
      if TBulkFix.Overlaps(mEdit.Range, mOther.Range) then
      begin
        Exit(False);
      end;
    end;
  end;
  Result := True;
end;

/// <summary>Die Edits der Kandidaten, die sich nicht überlappen: eine Korrektur ganz oder gar nicht, die
/// überlappende kommt im nächsten Durchgang dran (ADeferred).</summary>
function TakeFitting(const ACandidates: TArray<TCandidate>; var AApplied: TArray<TBulkFixRuleCount>;
  out ADeferred: Integer): TArray<TTextEdit>;
var
  mCandidate: TCandidate;
  mTaken: TList<TTextEdit>;
begin
  ADeferred := 0;
  mTaken := TList<TTextEdit>.Create;
  try
    for mCandidate in ACandidates do
    begin
      if FitsBeside(mCandidate.Fix.Edits, mTaken) then
      begin
        mTaken.AddRange(mCandidate.Fix.Edits);
        CountRule(AApplied, mCandidate.RuleId, 1);
      end
      else
      begin
        Inc(ADeferred);
      end;
    end;
    Result := mTaken.ToArray;
  finally
    mTaken.Free;
  end;
end;

class function TBulkFix.Run(const AFileName, AText: string; const AOptions: TBulkFixOptions;
  const ACheck: TBulkFixCheck; const ASyntaxErrors: TBulkFixSyntaxErrors): TBulkFixFile;
var
  mText: string;
  mLines: TBulkFixLineMap;
  mPass, mDeferred: Integer;
  mCandidates: TArray<TCandidate>;
  mTaken: TArray<TTextEdit>;
begin
  Result := Default(TBulkFixFile);
  Result.FileName := AFileName;
  Result.OldText := AText;
  Result.NewText := AText;
  Result.Lines := TBulkFixLineMap.Identity;
  mText := AText;
  mLines := TBulkFixLineMap.Identity;
  for mPass := 1 to MaxPasses do
  begin
    mCandidates := CandidatesOf(ACheck(mText, mLines), AOptions, mPass = 1, Result.Skipped);
    if mCandidates = nil then
    begin
      Break;
    end;
    mTaken := TakeFitting(mCandidates, Result.Applied, mDeferred);
    mLines := mLines.After(TLineTable.Build(mText).LineCount, mTaken);
    mText := TTextChanges.Apply(mText, mTaken);
    Result.Passes := mPass;
    if (mDeferred > 0) and (mPass = MaxPasses) then
    begin
      Inc(Result.Skipped[TBulkFixSkip.Conflict], mDeferred);
    end;
    if mDeferred = 0 then
    begin
      Break;
    end;
  end;
  // Keine neuen Syntaxfehler: sonst bleibt die Datei, wie sie ist.
  if (mText <> AText) and (ASyntaxErrors(mText) > ASyntaxErrors(AText)) then
  begin
    Result.Rejected := True;
  end
  else if mText <> AText then
  begin
    Result.NewText := mText;
    Result.Lines := mLines;
  end;
end;

class function TBulkFix.Diff(const ADisplayName: string; const AFile: TBulkFixFile): string;
begin
  if not AFile.Changed then
  begin
    Exit('');
  end;
  Result := string.Join(sLineBreak, TTextDiff.Unified('a/' + ADisplayName, 'b/' + ADisplayName,
    TTextLines.SplitLines(AFile.OldText), TTextLines.SplitLines(AFile.NewText), DiffContext)) + sLineBreak;
end;

/// <summary>Zeile "Übersprungen: …"; '' ohne übersprungene Treffer.</summary>
function SkippedLine(const ASkipped: TBulkFixSkipCounts): string;
begin
  Result := '';
  if ASkipped[TBulkFixSkip.Confidence] + ASkipped[TBulkFixSkip.Unsafe] + ASkipped[TBulkFixSkip.Conflict] +
    ASkipped[TBulkFixSkip.NoFix] > 0 then
  begin
    Result := Format('Übersprungen: %d mit zu niedriger Konfidenz, %d unsicher, %d Konflikt, %d ohne Korrektur',
      [ASkipped[TBulkFixSkip.Confidence], ASkipped[TBulkFixSkip.Unsafe], ASkipped[TBulkFixSkip.Conflict],
      ASkipped[TBulkFixSkip.NoFix]]);
  end;
end;

/// <summary>Summen über alle geänderten Dateien: Korrekturen je Regel (nach Kennung sortiert), Übersprungene
/// über alle Dateien.</summary>
procedure AddTotals(const AFiles: TArray<TBulkFixFile>; var ATotals: TArray<TBulkFixRuleCount>;
  var ASkipped: TBulkFixSkipCounts; out AChanged: Integer);
var
  mFile: TBulkFixFile;
  mCount: TBulkFixRuleCount;
  mSkip: TBulkFixSkip;
begin
  AChanged := 0;
  for mFile in AFiles do
  begin
    for mSkip := Low(TBulkFixSkip) to High(TBulkFixSkip) do
    begin
      Inc(ASkipped[mSkip], mFile.Skipped[mSkip]);
    end;
    if mFile.Changed then
    begin
      Inc(AChanged);
      for mCount in mFile.Applied do
      begin
        CountRule(ATotals, mCount.RuleId, mCount.Count);
      end;
    end;
  end;
  // Kennungen sind eindeutig: Die Reihenfolge steht fest, obwohl Sort nicht stabil ist.
  TArray.Sort<TBulkFixRuleCount>(ATotals, TComparer<TBulkFixRuleCount>.Construct(
    function(const A, B: TBulkFixRuleCount): Integer
    begin
      Result := CompareText(A.RuleId, B.RuleId);
    end));
end;

class function TBulkFix.Summary(const AFiles: TArray<TBulkFixFile>; ADryRun: Boolean; const ALineBreak: string):
  string;
var
  mFile: TBulkFixFile;
  mTotals: TArray<TBulkFixRuleCount>;
  mTotal: TBulkFixRuleCount;
  mSkipped: TBulkFixSkipCounts;
  mChanged, mFixes: Integer;
  mLines: TArray<string>;
begin
  mSkipped := Default(TBulkFixSkipCounts);
  mTotals := nil;
  AddTotals(AFiles, mTotals, mSkipped, mChanged);
  mFixes := 0;
  for mTotal in mTotals do
  begin
    Inc(mFixes, mTotal.Count);
  end;
  if ADryRun then
  begin
    mLines := [Format('Vorschau: %d Korrekturen in %d Dateien, nichts geschrieben', [mFixes, mChanged])];
  end
  else
  begin
    mLines := [Format('%d Korrekturen in %d Dateien geschrieben', [mFixes, mChanged])];
  end;
  for mTotal in mTotals do
  begin
    mLines := mLines + [Format('  %s: %d', [mTotal.RuleId, mTotal.Count])];
  end;
  if SkippedLine(mSkipped) <> '' then
  begin
    mLines := mLines + [SkippedLine(mSkipped)];
  end;
  for mFile in AFiles do
  begin
    if mFile.Rejected then
    begin
      mLines := mLines + [Format('Verworfen (die Korrekturen hätten Syntaxfehler erzeugt): %s', [mFile.FileName])];
    end;
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
  begin
    if mFile.Changed then
    begin
      mNames := mNames + [mFile.FileName];
      mOld := mOld + [mFile.OldText];
      mNew := mNew + [mFile.NewText];
    end;
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
