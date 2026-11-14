unit Atlas.Common.Editing.LearnedSuggestions;

// Gelernte Vorschläge aus dem eigenen Code (#1890, ohne KI): Steht die
// Schreibmarke in einer leeren Zeile nach einem Auslöser (Konstruktor,
// BeginUpdate, Enter …, siehe Atlas.Common.Index.Extractor.Patterns), sucht
// Suggest in den Folgemustern der Projekt-Units, was dort meist folgt, und
// schreibt es mit Subjekt und Argument des Auslösers als fertige Zeilen.
// - Ein Muster gilt ab MinCount Stellen und einem Anteil von MinShare Prozent
//   an allen Stellen seines Auslösers. Adjust verschiebt den Anteil je Muster
//   (Lernen aus der Nutzung im Plugin: oft verworfen sinkt, oft übernommen
//   steigt); Muster aus atlas.json ("suggestions.patterns") zählen als 100 %.
// - Der genaueste Schlüssel zuerst: "$S := TFoo.Create" vor "$S := $T.Create".
// - Vor dem Liefern läuft der Vorschlag durch den Parser (keine neuen
//   Syntaxfehler) und die Namensprüfung (jeder Bezeichner steht in der Datei
//   oder im Index); sonst kein Vorschlag.
// - Folgt auf den Auslöser schon ein try oder while, schlägt Atlas nichts vor.
// Reine Funktionen über Syntaxbaum und Index-Einträgen, threadsicher.

interface

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Extractor.Patterns,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Configuration.Contract;

type
  /// <summary>Fundstelle eines Musters.</summary>
  TLearnedEvidence = record
    FileName: string;
    /// <summary>0-basiert.</summary>
    Line: Integer;
  end;

  /// <summary>Ein Folgemuster über alle Projekt-Units bzw. aus atlas.json.</summary>
  TLearnedPattern = record
    /// <summary>Kennung für die Lernzähler im Plugin: Trigger und Folge in Kleinbuchstaben.</summary>
    Id: string;
    Trigger: string;
    Follow: string;
    /// <summary>Stellen mit dieser Folge.</summary>
    Count: Integer;
    /// <summary>Alle Stellen des Auslösers, mit und ohne diese Folge.</summary>
    Total: Integer;
    /// <summary>Aus atlas.json ("suggestions.patterns").</summary>
    Team: Boolean;
    Evidence: TArray<TLearnedEvidence>;
    /// <summary>Anteil in Prozent; 100 bei Mustern aus atlas.json.</summary>
    function Share: Integer;
  end;

  TLearnedOptions = record
    MinCount: Integer;
    /// <summary>Prozent.</summary>
    MinShare: Integer;
    IndentSize: Integer;
    UseTabs: Boolean;
    /// <summary>Verschiebung des Anteils je Kennung (Lernen aus der Nutzung), parallel zu AdjustBy.</summary>
    AdjustIds: TArray<string>;
    AdjustBy: TArray<Integer>;
    /// <summary>Eigene Muster aus atlas.json.</summary>
    Team: TArray<TSuggestionPattern>;
    class function Default: TLearnedOptions; static;
    /// <summary>Verschiebung für AId; 0 ohne Eintrag.</summary>
    function AdjustOf(const AId: string): Integer;
  end;

  /// <summary>Fertiger Vorschlag: Lines ersetzen die leere Zeile der Schreibmarke.</summary>
  TLearnedSuggestion = record
    Pattern: TLearnedPattern;
    Lines: TArray<string>;
    /// <summary>Schreibmarke nach dem Übernehmen, relativ zur ersten Zeile von Lines.</summary>
    CursorLine: Integer;
    CursorCharacter: Integer;
  end;

  /// <summary>Kennt der Index einen Bezeichner dieses Namens?</summary>
  TLearnedNameCheck = reference to function(const AName: string): Boolean;

  /// <summary>Was das Projekt für Vorschläge beiträgt: die Units des Index, aus denen Muster gelernt werden, und
  /// die Prüfung, ob ein Bezeichner außerhalb der Datei bekannt ist.</summary>
  TLearnedProject = record
    Units: TArray<TUnitIndex>;
    Known: TLearnedNameCheck;
    class function Create(const AUnits: TArray<TUnitIndex>; const AKnown: TLearnedNameCheck): TLearnedProject;
      static;
  end;

  TLearnedSuggestions = class
  public const
    /// <summary>Muster mit weniger Stellen zeigt die Liste der gelernten Vorschläge nicht.</summary>
    cMinListed = 2;
  public
    class function IdOf(const ATrigger, AFollow: string): string; static;
    /// <summary>Vorlage AFollow in einer Zeile für Listen: Einrückung weg, Rumpf als "…".</summary>
    class function Display(const AFollow: string): string; static;
    /// <summary>Muster aller Projekt-Units in AUnits mit einer Folge, je Trigger und Folge zusammengezählt, nach
    /// Stellen absteigend; mit AKeys nur Trigger aus dieser Liste.</summary>
    class function Gather(const AUnits: TArray<TUnitIndex>; const AKeys: TArray<string>): TArray<TLearnedPattern>;
      static;
    /// <summary>Bestes Muster unter APatterns für den Trigger AKey, das die Schwellen aus AOptions erreicht.
    /// </summary>
    class function Best(const APatterns: TArray<TLearnedPattern>; const AKey: string; const AOptions: TLearnedOptions;
      out APattern: TLearnedPattern): Boolean; static;
    /// <summary>Muster aus atlas.json für ATrigger, das nicht abgewählt ist.</summary>
    class function TeamPattern(const ATrigger: TFollowTrigger; const AOptions: TLearnedOptions;
      out APattern: TLearnedPattern): Boolean; static;
    /// <summary>Vorlage eines Musters aus atlas.json (zwei Leerzeichen je Ebene).</summary>
    class function TeamFollow(const AInsert: TArray<string>): string; static;
    /// <summary>Zeilen der Vorlage AFollow für ATrigger mit der Einrückung AIndent der Auslöserzeile; False, wenn
    /// die Vorlage ein Subjekt oder Argument braucht, das der Auslöser nicht hat.</summary>
    class function Render(const AFollow: string; const ATrigger: TFollowTrigger; const AIndent: string;
      const AOptions: TLearnedOptions; out ASuggestion: TLearnedSuggestion): Boolean; static;
    /// <summary>Auslöser vor der leeren Zeile ALine (0-basiert) von AText mit Baum ATree.</summary>
    class function TriggerAt(ATree: TSyntaxTree; const AText: string; ALine: Integer; out AStatement: TSyntaxNode;
      out ATrigger: TFollowTrigger): Boolean; static;
    /// <summary>Vorschlag für die leere Zeile ALine aus den Mustern von AProject; dessen Known prüft Bezeichner,
    /// die nicht in der Datei stehen.</summary>
    class function Suggest(ATree: TSyntaxTree; const AText: string; ALine: Integer; const AProject: TLearnedProject;
      const AOptions: TLearnedOptions; out ASuggestion: TLearnedSuggestion): Boolean; static;
    /// <summary>Bringt ASuggestion keinen neuen Syntaxfehler und keinen unbekannten Bezeichner in AText?</summary>
    class function Valid(ATree: TSyntaxTree; const AText: string; ALine: Integer;
      const ASuggestion: TLearnedSuggestion; const AKnown: TLearnedNameCheck): Boolean; static;
    /// <summary>Alle Muster für die Liste der gelernten Vorschläge: aus atlas.json und aus dem Projekt ab
    /// cMinListed Stellen, nach Stellen absteigend.</summary>
    class function List(const AUnits: TArray<TUnitIndex>; const AOptions: TLearnedOptions): TArray<TLearnedPattern>;
      static;
  end;

implementation

uses
  System.StrUtils,
  System.Math,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.TreeCache;

{ TLearnedPattern }

function TLearnedPattern.Share: Integer;
begin
  Result := 100;
  if not Team and (Total > 0) then
  begin
    Result := (Count * 100) div Total;
  end;
end;

{ TLearnedOptions }

class function TLearnedOptions.Default: TLearnedOptions;
begin
  Result.MinCount := 5;
  Result.MinShare := 70;
  Result.IndentSize := 2;
  Result.UseTabs := False;
  Result.AdjustIds := nil;
  Result.AdjustBy := nil;
  Result.Team := nil;
end;

function TLearnedOptions.AdjustOf(const AId: string): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  for mIndex := 0 to Min(High(AdjustIds), High(AdjustBy)) do
  begin
    if SameText(AdjustIds[mIndex], AId) then
    begin
      Exit(AdjustBy[mIndex]);
    end;
  end;
end;

{ TLearnedProject }

class function TLearnedProject.Create(const AUnits: TArray<TUnitIndex>;
  const AKnown: TLearnedNameCheck): TLearnedProject;
begin
  Result.Units := AUnits;
  Result.Known := AKnown;
end;

{ TLearnedSuggestions }

class function TLearnedSuggestions.IdOf(const ATrigger, AFollow: string): string;
begin
  Result := LowerCase(ATrigger + ' => ' + StringReplace(AFollow, #10, ' / ', [rfReplaceAll]));
end;

class function TLearnedSuggestions.Display(const AFollow: string): string;
var
  mPart, mText: string;
begin
  Result := '';
  for mPart in AFollow.Split([#10]) do
  begin
    if Result <> '' then
    begin
      Result := Result + ' ';
    end;
    mText := mPart;
    while StartsStr(TIndexFollowPatterns.cIndentMark, mText) do
    begin
      mText := Copy(mText, 2, MaxInt);
    end;
    if mText = TIndexFollowPatterns.cBody then
    begin
      mText := '…';
    end;
    Result := Result + mText;
  end;
end;

type
  /// <summary>Sammelt Muster mehrerer Units je Trigger und Folge.</summary>
  TPatternSum = class
  private
    FTotals: TDictionary<string, Integer>;
    FPositions: TDictionary<string, Integer>;
    FItems: TList<TLearnedPattern>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const AUnit: TUnitIndex; const APattern: TIndexFollowPattern);
    function ToArray: TArray<TLearnedPattern>;
  end;

constructor TPatternSum.Create;
begin
  inherited Create;
  FTotals := TDictionary<string, Integer>.Create;
  FPositions := TDictionary<string, Integer>.Create;
  FItems := TList<TLearnedPattern>.Create;
end;

destructor TPatternSum.Destroy;
begin
  FItems.Free;
  FPositions.Free;
  FTotals.Free;
  inherited;
end;

procedure TPatternSum.Add(const AUnit: TUnitIndex; const APattern: TIndexFollowPattern);
var
  mTrigger, mId: string;
  mTotal, mPosition: Integer;
  mItem: TLearnedPattern;
  mLine: Integer;
  mEvidence: TLearnedEvidence;
begin
  mTrigger := LowerCase(APattern.Trigger);
  if not FTotals.TryGetValue(mTrigger, mTotal) then
  begin
    mTotal := 0;
  end;
  FTotals.AddOrSetValue(mTrigger, mTotal + APattern.Count);
  if APattern.Follow = '' then
  begin
    Exit;
  end;
  mId := TLearnedSuggestions.IdOf(APattern.Trigger, APattern.Follow);
  if FPositions.TryGetValue(mId, mPosition) then
  begin
    mItem := FItems[mPosition];
  end
  else
  begin
    mItem := Default(TLearnedPattern);
    mItem.Id := mId;
    mItem.Trigger := APattern.Trigger;
    mItem.Follow := APattern.Follow;
    mPosition := FItems.Add(mItem);
    FPositions.Add(mId, mPosition);
  end;
  Inc(mItem.Count, APattern.Count);
  for mLine in APattern.Lines do
  begin
    if Length(mItem.Evidence) < TIndexFollowPatterns.cMaxEvidence then
    begin
      mEvidence.FileName := AUnit.FileName;
      mEvidence.Line := mLine;
      mItem.Evidence := mItem.Evidence + [mEvidence];
    end;
  end;
  FItems[mPosition] := mItem;
end;

function TPatternSum.ToArray: TArray<TLearnedPattern>;
var
  mIndex, mTotal: Integer;
  mItem: TLearnedPattern;
begin
  for mIndex := 0 to FItems.Count - 1 do
  begin
    mItem := FItems[mIndex];
    if FTotals.TryGetValue(LowerCase(mItem.Trigger), mTotal) then
    begin
      mItem.Total := mTotal;
    end;
    FItems[mIndex] := mItem;
  end;
  Result := FItems.ToArray;
  TArray.Sort<TLearnedPattern>(Result, TComparer<TLearnedPattern>.Construct(
    function(const ALeft, ARight: TLearnedPattern): Integer
    begin
      Result := ARight.Count - ALeft.Count;
      if Result = 0 then
      begin
        Result := CompareStr(ALeft.Id, ARight.Id);
      end;
    end));
end;

class function TLearnedSuggestions.Gather(const AUnits: TArray<TUnitIndex>;
  const AKeys: TArray<string>): TArray<TLearnedPattern>;
var
  mSum: TPatternSum;
  mUnit: TUnitIndex;
  mPattern: TIndexFollowPattern;
begin
  mSum := TPatternSum.Create;
  try
    for mUnit in AUnits do
    begin
      if mUnit.Library_ then
      begin
        Continue;
      end;
      for mPattern in mUnit.Patterns do
      begin
        if (AKeys = nil) or (IndexText(mPattern.Trigger, AKeys) >= 0) then
        begin
          mSum.Add(mUnit, mPattern);
        end;
      end;
    end;
    Result := mSum.ToArray;
  finally
    mSum.Free;
  end;
end;

class function TLearnedSuggestions.Best(const APatterns: TArray<TLearnedPattern>; const AKey: string;
  const AOptions: TLearnedOptions; out APattern: TLearnedPattern): Boolean;
var
  mPattern: TLearnedPattern;
  mScore, mBest: Integer;
  mBetter: Boolean;
begin
  Result := False;
  APattern := Default(TLearnedPattern);
  mBest := Low(Integer);
  for mPattern in APatterns do
  begin
    if not SameText(mPattern.Trigger, AKey) or (mPattern.Count < AOptions.MinCount) then
    begin
      Continue;
    end;
    mScore := mPattern.Share + AOptions.AdjustOf(mPattern.Id);
    mBetter := (mScore > mBest) or ((mScore = mBest) and (mPattern.Count > APattern.Count));
    if (mScore >= AOptions.MinShare) and mBetter then
    begin
      mBest := mScore;
      APattern := mPattern;
      Result := True;
    end;
  end;
end;

class function TLearnedSuggestions.TeamFollow(const AInsert: TArray<string>): string;
var
  mLine, mText: string;
  mSpaces: Integer;
begin
  Result := '';
  for mLine in AInsert do
  begin
    mText := TrimLeft(mLine);
    mSpaces := Length(StringReplace(Copy(mLine, 1, Length(mLine) - Length(mText)), #9, '  ', [rfReplaceAll]));
    if Result <> '' then
    begin
      Result := Result + #10;
    end;
    Result := Result + StringOfChar(TIndexFollowPatterns.cIndentMark, mSpaces div 2) + TrimRight(mText);
  end;
end;

/// <summary>Auslöser AAfter aus atlas.json passt zu ATrigger: einer seiner Schlüssel oder der Aufruf selbst.</summary>
function TeamMatches(const AAfter: string; const ATrigger: TFollowTrigger): Boolean;
var
  mAfter, mKey: string;
begin
  mAfter := TIndexFollowPatterns.NormalizeText(AAfter);
  Result := SameText(mAfter, TIndexFollowPatterns.NormalizeText(ATrigger.Callee));
  for mKey in ATrigger.Keys do
  begin
    Result := Result or SameText(mAfter, TIndexFollowPatterns.NormalizeText(mKey));
  end;
end;

class function TLearnedSuggestions.TeamPattern(const ATrigger: TFollowTrigger; const AOptions: TLearnedOptions;
  out APattern: TLearnedPattern): Boolean;
var
  mTeam: TSuggestionPattern;
begin
  APattern := Default(TLearnedPattern);
  for mTeam in AOptions.Team do
  begin
    if not TeamMatches(mTeam.After, ATrigger) then
    begin
      Continue;
    end;
    APattern.Trigger := mTeam.After;
    APattern.Follow := TeamFollow(mTeam.Insert);
    APattern.Id := IdOf(APattern.Trigger, APattern.Follow);
    APattern.Team := True;
    if APattern.Share + AOptions.AdjustOf(APattern.Id) >= AOptions.MinShare then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Setzt Subjekt, Argument und Klasse in die Zeile AText einer Vorlage ein; False, wenn einer fehlt.
/// </summary>
function Filled(const AText: string; const ATrigger: TFollowTrigger; out ALine: string): Boolean;
begin
  Result := ((Pos(TIndexFollowPatterns.cSubject, AText) = 0) or (ATrigger.Subject <> '')) and
    ((Pos(TIndexFollowPatterns.cArgument, AText) = 0) or (ATrigger.Argument <> '')) and
    ((Pos(TIndexFollowPatterns.cTypeName, AText) = 0) or (ATrigger.TypeName <> ''));
  ALine := StringReplace(AText, TIndexFollowPatterns.cSubject, ATrigger.Subject, [rfReplaceAll]);
  ALine := StringReplace(ALine, TIndexFollowPatterns.cArgument, ATrigger.Argument, [rfReplaceAll]);
  ALine := StringReplace(ALine, TIndexFollowPatterns.cTypeName, ATrigger.TypeName, [rfReplaceAll]);
end;

/// <summary>Einrückung je Ebene nach AOptions: ein Tabulator oder IndentSize Leerzeichen.</summary>
function IndentUnit(const AOptions: TLearnedOptions): string;
begin
  if AOptions.UseTabs then
  begin
    Result := #9;
  end
  else
  begin
    Result := StringOfChar(' ', Max(1, AOptions.IndentSize));
  end;
end;

/// <summary>Zeile AFollowLine einer Vorlage ohne ihre Einrückungszeichen; APrefix ist AIndent und je Zeichen
/// einmal AUnit.</summary>
function WithoutIndentMarks(const AFollowLine, AIndent, AUnit: string; out APrefix: string): string;
var
  mDepth: Integer;
begin
  mDepth := 0;
  APrefix := AIndent;
  while (mDepth < Length(AFollowLine)) and (AFollowLine[mDepth + 1] = TIndexFollowPatterns.cIndentMark) do
  begin
    Inc(mDepth);
    APrefix := APrefix + AUnit;
  end;
  Result := Copy(AFollowLine, mDepth + 1, MaxInt);
end;

class function TLearnedSuggestions.Render(const AFollow: string; const ATrigger: TFollowTrigger;
  const AIndent: string; const AOptions: TLearnedOptions; out ASuggestion: TLearnedSuggestion): Boolean;
var
  mUnit, mText, mLine, mPrefix: string;
  mIndex: Integer;
  mParts: TArray<string>;
begin
  ASuggestion := Default(TLearnedSuggestion);
  mUnit := IndentUnit(AOptions);
  mParts := AFollow.Split([#10]);
  Result := Length(mParts) > 0;
  ASuggestion.CursorLine := -1;
  for mIndex := 0 to High(mParts) do
  begin
    mText := WithoutIndentMarks(mParts[mIndex], AIndent, mUnit, mPrefix);
    if mText = TIndexFollowPatterns.cBody then
    begin
      mLine := mPrefix;
      if ASuggestion.CursorLine < 0 then
      begin
        ASuggestion.CursorLine := mIndex;
        ASuggestion.CursorCharacter := Length(mLine);
      end;
    end
    else if Filled(mText, ATrigger, mLine) then
    begin
      mLine := mPrefix + mLine;
    end
    else
    begin
      Exit(False);
    end;
    ASuggestion.Lines := ASuggestion.Lines + [mLine];
  end;
  if Result and (ASuggestion.CursorLine < 0) then
  begin
    ASuggestion.CursorLine := High(ASuggestion.Lines);
    ASuggestion.CursorCharacter := Length(ASuggestion.Lines[ASuggestion.CursorLine]);
  end;
end;

/// <summary>Index des ersten Tokens ab Zeile ALine.</summary>
function FirstTokenOfLine(const ATokens: TArray<TPascalToken>; ALine: Integer): Integer;
var
  mLow, mHigh, mMiddle: Integer;
begin
  mLow := 0;
  mHigh := Length(ATokens);
  while mLow < mHigh do
  begin
    mMiddle := (mLow + mHigh) div 2;
    if ATokens[mMiddle].StartPos.Line < ALine then
    begin
      mLow := mMiddle + 1;
    end
    else
    begin
      mHigh := mMiddle;
    end;
  end;
  Result := mLow;
end;

/// <summary>Index des Code-Tokens vor AIndex; -1 ohne.</summary>
function CodeTokenBefore(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and (ATokens[Result].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
  begin
    Dec(Result);
  end;
end;

/// <summary>Endoffset der Anweisung, deren Semikolon direkt vor der Zeile ALine steht; False ohne.</summary>
function StatementEndBefore(const ATokens: TArray<TPascalToken>; ALine: Integer; out AEnd: Integer): Boolean;
var
  mSemicolon, mLast: Integer;
begin
  AEnd := -1;
  mSemicolon := CodeTokenBefore(ATokens, FirstTokenOfLine(ATokens, ALine));
  mLast := -1;
  if (mSemicolon >= 0) and ATokens[mSemicolon].IsSymbol(';') then
  begin
    mLast := CodeTokenBefore(ATokens, mSemicolon);
  end;
  Result := mLast >= 0;
  if Result then
  begin
    AEnd := ATokens[mLast].Offset + Length(ATokens[mLast].Text);
  end;
end;

/// <summary>Zuweisung oder Aufruf in einer Anweisungsliste unter ARoot, die bei AEnd endet; nil ohne.</summary>
function ListStatementEndingAt(ARoot: TSyntaxNode; AEnd: Integer): TSyntaxNode;
begin
  Result := ARoot.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      if (ANode.StartOffset > AEnd) or (ANode.EndOffset < AEnd) then
      begin
        Exit(TSyntaxSearchStep.Skip);
      end;
      if (ANode.EndOffset = AEnd) and (ANode.Kind in [TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement]) and
        (ANode.Parent <> nil) and TIndexFollowPatterns.IsList(ANode.Parent.Kind) then
      begin
        Exit(TSyntaxSearchStep.Found);
      end;
      Result := TSyntaxSearchStep.Descend;
    end);
end;

class function TLearnedSuggestions.TriggerAt(ATree: TSyntaxTree; const AText: string; ALine: Integer;
  out AStatement: TSyntaxNode; out ATrigger: TFollowTrigger): Boolean;
var
  mLines: TArray<string>;
  mEnd: Integer;
  mFound: TSyntaxNode;
begin
  AStatement := nil;
  ATrigger := Default(TFollowTrigger);
  Result := False;
  mLines := AText.Split([#13#10, #10]);
  if (ATree = nil) or (ATree.Root = nil) or (ALine < 1) or (ALine > High(mLines)) or (Trim(mLines[ALine]) <> '') then
  begin
    Exit;
  end;
  if not StatementEndBefore(ATree.Tokens, ALine, mEnd) then
  begin
    Exit;
  end;
  mFound := ListStatementEndingAt(ATree.Root, mEnd);
  if (mFound <> nil) and TIndexFollowPatterns.TriggerOf(ATree, mFound, ATrigger) then
  begin
    AStatement := mFound;
    Result := True;
  end;
end;

/// <summary>Einrückung der Zeile ALine von AText.</summary>
function IndentOfLine(const AText: string; ALine: Integer): string;
var
  mLines: TArray<string>;
  mLength: Integer;
begin
  Result := '';
  mLines := AText.Split([#13#10, #10]);
  if (ALine >= 0) and (ALine <= High(mLines)) then
  begin
    mLength := 0;
    while (mLength < Length(mLines[ALine])) and CharInSet(mLines[ALine][mLength + 1], [' ', #9]) do
    begin
      Inc(mLength);
    end;
    Result := Copy(mLines[ALine], 1, mLength);
  end;
end;

class function TLearnedSuggestions.Suggest(ATree: TSyntaxTree; const AText: string; ALine: Integer;
  const AProject: TLearnedProject; const AOptions: TLearnedOptions; out ASuggestion: TLearnedSuggestion): Boolean;
var
  mStatement, mNext: TSyntaxNode;
  mTrigger: TFollowTrigger;
  mPatterns: TArray<TLearnedPattern>;
  mPattern: TLearnedPattern;
  mKey: string;
  mFound: Boolean;
begin
  ASuggestion := Default(TLearnedSuggestion);
  Result := False;
  if not TriggerAt(ATree, AText, ALine, mStatement, mTrigger) then
  begin
    Exit;
  end;
  // Schon ein try oder while dahinter: der Rahmen steht bereits.
  mNext := TIndexFollowPatterns.NextStatement(mStatement);
  if (mNext <> nil) and (mNext.Kind in [TSyntaxKind.TryStatement, TSyntaxKind.WhileStatement]) then
  begin
    Exit;
  end;
  mFound := TeamPattern(mTrigger, AOptions, mPattern);
  if not mFound then
  begin
    mPatterns := Gather(AProject.Units, mTrigger.Keys);
    for mKey in mTrigger.Keys do
    begin
      if not mFound then
      begin
        mFound := Best(mPatterns, mKey, AOptions, mPattern);
      end;
    end;
  end;
  if not mFound or not Render(mPattern.Follow, mTrigger, IndentOfLine(AText, mStatement.StartPos.Line), AOptions,
    ASuggestion) then
  begin
    Exit;
  end;
  ASuggestion.Pattern := mPattern;
  Result := Valid(ATree, AText, ALine, ASuggestion, AProject.Known);
end;

/// <summary>Bezeichner in ATokens, kleingeschrieben.</summary>
function NamesOf(const ATokens: TArray<TPascalToken>): TDictionary<string, Boolean>;
var
  mToken: TPascalToken;
begin
  Result := TDictionary<string, Boolean>.Create;
  for mToken in ATokens do
  begin
    if mToken.Kind = TPascalTokenKind.Identifier then
    begin
      Result.AddOrSetValue(LowerCase(mToken.Text), True);
    end;
  end;
end;

class function TLearnedSuggestions.Valid(ATree: TSyntaxTree; const AText: string; ALine: Integer;
  const ASuggestion: TLearnedSuggestion; const AKnown: TLearnedNameCheck): Boolean;
var
  mLines: TArray<string>;
  mBreak, mInserted: string;
  mBefore, mAfter: TSyntaxTree;
  mNames: TDictionary<string, Boolean>;
  mToken: TPascalToken;
begin
  mBreak := #10;
  if Pos(#13#10, AText) > 0 then
  begin
    mBreak := #13#10;
  end;
  mLines := AText.Split([#13#10, #10]);
  mInserted := string.Join(mBreak, ASuggestion.Lines);
  mLines[ALine] := mInserted;
  // Beide Stände gleich gelesen, damit nur neue Fehler zählen.
  mBefore := TSyntaxTreeCache.Parse(AText);
  mAfter := TSyntaxTreeCache.Parse(string.Join(mBreak, mLines));
  try
    Result := Length(mAfter.Diagnostics) <= Length(mBefore.Diagnostics);
  finally
    mAfter.Free;
    mBefore.Free;
  end;
  if not Result then
  begin
    Exit;
  end;
  mNames := NamesOf(ATree.Tokens);
  try
    for mToken in TPascalLexer.Tokenize(mInserted) do
    begin
      if (mToken.Kind = TPascalTokenKind.Identifier) and not mNames.ContainsKey(LowerCase(mToken.Text)) and
        not (Assigned(AKnown) and AKnown(mToken.Text)) then
      begin
        Exit(False);
      end;
    end;
  finally
    mNames.Free;
  end;
end;

class function TLearnedSuggestions.List(const AUnits: TArray<TUnitIndex>;
  const AOptions: TLearnedOptions): TArray<TLearnedPattern>;
var
  mTeam: TSuggestionPattern;
  mPattern: TLearnedPattern;
begin
  Result := nil;
  for mTeam in AOptions.Team do
  begin
    mPattern := Default(TLearnedPattern);
    mPattern.Trigger := mTeam.After;
    mPattern.Follow := TeamFollow(mTeam.Insert);
    mPattern.Id := IdOf(mPattern.Trigger, mPattern.Follow);
    mPattern.Team := True;
    Result := Result + [mPattern];
  end;
  for mPattern in Gather(AUnits, nil) do
  begin
    if mPattern.Count >= cMinListed then
    begin
      Result := Result + [mPattern];
    end;
  end;
end;

end.
