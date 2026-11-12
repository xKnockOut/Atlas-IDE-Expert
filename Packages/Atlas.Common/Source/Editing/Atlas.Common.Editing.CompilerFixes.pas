unit Atlas.Common.Editing.CompilerFixes;

// Schnellkorrekturen für Compilermeldungen, Teil 2 (#549), ohne Protokoll-
// bezug. Grundlage sind Nummer, Zeile und Text der Meldung (deutsche oder
// englische Ausgabe); Namen stehen in Hochkommas.
//   - H2443 (Inline-Funktion nicht erweitert): die Unit aus dem Text (letzter
//     Name in Hochkommas) ins uses des Abschnitts der Zeile eintragen.
//   - E2003 (Unbekannter Bezeichner): Units anbieten, die den Bezeichner
//     deklarieren (wie #284); RTL- und VCL-Units zuerst, dann kürzere Namen.
//   - H2077 (Wert wird nie verwendet): Zuweisung an die genannte Variable
//     entfernen, wenn die rechte Seite sicher keine Nebenwirkung hat
//     (Literale, Operatoren, lokale Variablen, Parameter, Konstanten); ist sie
//     ein Aufruf mit Klammern, bleibt nur der Aufruf. Sonst keine Korrektur:
//     Ohne Namensauflösung kann ein Name ohne Klammern eine Funktion sein.
//   - W1035 (Rückgabewert möglicherweise undefiniert): Result :=
//     Default(<Typ>); direkt hinter das begin der Funktion, Typ aus dem Kopf.
//   - W1057/W1058 (implizite String-Umwandlung): rechte Seite der Zuweisung
//     bzw. das Argument an der Spalte der Meldung in <Zieltyp>(…) setzen; der
//     Zieltyp ist der letzte Name in Hochkommas.
// FixAll fasst alle Meldungen einer Nummer in der Datei zu einer Änderung
// zusammen (überlappende Einfügungen entfallen).

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.Contract;

type
  /// <summary>Eine Compilermeldung; Line und Column ab 0, Column -1 ohne Spalte.</summary>
  TFixMessage = record
    Code: string;
    Line: Integer;
    Column: Integer;
    Text: string;
    class function Create(const ACode: string; ALine, AColumn: Integer; const AText: string): TFixMessage; static;
  end;

  TCompilerFix = record
    Code: string;
    Title: string;
    Edits: TArray<TTextEdit>;
    Preferred: Boolean;
  end;

  TCompilerFixContext = record
    /// <summary>Units, die einen Bezeichner deklarieren; nil = keine E2003-Korrektur.</summary>
    Declaring: TUnitsDeclaringFunc;
    Namespaces: TArray<string>;
  end;

  TCompilerFixes = class
  public
    /// <summary>Nummern mit Korrektur.</summary>
    class function Codes: TArray<string>; static;
    /// <summary>Hat ACode eine Korrektur, die FixAll für die ganze Datei anwenden kann?</summary>
    class function CanFixAll(const ACode: string): Boolean; static;
    /// <summary>Namen in Hochkommas aus dem Meldungstext, in Reihenfolge.</summary>
    class function QuotedNames(const AText: string): TArray<string>; static;
    /// <summary>Units in der Reihenfolge, in der E2003 sie anbietet.</summary>
    class function RankUnits(const AUnits: TArray<string>): TArray<string>; static;
    /// <summary>Korrekturen für AMessage im Text AText (Baum ATree).</summary>
    class function Fixes(const AText: string; ATree: TSyntaxTree; const AMessage: TFixMessage;
      const AContext: TCompilerFixContext): TArray<TCompilerFix>; static;
    /// <summary>Alle Meldungen mit ACode in einer Änderung; False, wenn es weniger als zwei Korrekturen gibt.
    /// </summary>
    class function FixAll(const AText: string; ATree: TSyntaxTree; const AMessages: TArray<TFixMessage>;
      const ACode: string; const AContext: TCompilerFixContext; out AFix: TCompilerFix): Boolean; static;
  end;

implementation

uses
  Atlas.Common.Editing.UsesActions,
  System.StrUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Text.Lines,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.DisableWarning,
  Atlas.Common.Localization.Texts;

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TCompilerFixesText = (AddToUses, AddToUses2, InsertResultDefaultAtThe, FixAllInTheFile,
    RemoveIneffectiveAssignmentTo, RemoveAssignmentToOnlyCall, CastExplicitly);

const
  cTexts: array[TCompilerFixesText] of TAtlasText = (
    (De: 'uses %s ergänzen (%s)'; En: 'Add %s to uses (%s)'),
    (De: 'uses %s ergänzen (%s: %s)'; En: 'Add %s to uses (%s: %s)'),
    (De: 'Result := Default(%s); am Anfang einfügen (%s)'; En: 'Insert Result := Default(%s); at the start (%s)'),
    (De: 'Alle %s in der Datei beheben (%d)'; En: 'Fix all %s in the file (%d)'),
    (De: 'Wirkungslose Zuweisung an %s entfernen (%s)'; En: 'Remove ineffective assignment to %s (%s)'),
    (De: 'Zuweisung an %s entfernen, nur %s aufrufen (%s)'; En: 'Remove assignment to %s, only call %s (%s)'),
    (De: 'Explizit umwandeln: %s(…) (%s)'; En: 'Cast explicitly: %s(…) (%s)'));

const
  cFixCodes: array[0..5] of string = ('H2443', 'E2003', 'H2077', 'W1035', 'W1057', 'W1058');
  cFixAllCodes: array[0..4] of string = ('H2443', 'H2077', 'W1035', 'W1057', 'W1058');
  // Namespaces der RTL und der Bibliotheken von Delphi: bei E2003 zuerst.
  cLibraryNamespaces: array[0..12] of string = ('System', 'Winapi', 'Vcl', 'FMX', 'Data', 'Xml', 'Web', 'Soap',
    'REST', 'Datasnap', 'FireDAC', 'IBX', 'Posix');

{ TFixMessage }

class function TFixMessage.Create(const ACode: string; ALine, AColumn: Integer; const AText: string): TFixMessage;
begin
  Result.Code := UpperCase(Trim(ACode));
  Result.Line := ALine;
  Result.Column := AColumn;
  Result.Text := AText;
end;

{ Hilfen }

function OffsetOf(const AText: string; ALine: Integer): Integer;
var
  mIndex, mLine: Integer;
begin
  // Offset ab 0 des Zeilenanfangs; -1 hinter dem Text.
  mLine := 0;
  mIndex := 1;
  while (mLine < ALine) and (mIndex <= Length(AText)) do
  begin
    if AText[mIndex] = #10 then
    begin
      Inc(mLine);
    end;
    Inc(mIndex);
  end;
  Result := mIndex - 1;
  if mLine < ALine then
  begin
    Result := -1;
  end;
end;

/// <summary>Alle Knoten der Art AKind, die in Zeile ALine beginnen, in Baumreihenfolge.</summary>
function NodesOnLine(ARoot: TSyntaxNode; ALine: Integer; AKind: TSyntaxKind): TArray<TSyntaxNode>;
var
  mFound: TArray<TSyntaxNode>;
begin
  mFound := nil;
  if ARoot <> nil then
  begin
    ARoot.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := (ANode.StartPos.Line <= ALine) and (ANode.EndPos.Line >= ALine);
        if Result and (ANode.Kind = AKind) and (ANode.StartPos.Line = ALine) then
        begin
          mFound := mFound + [ANode];
        end;
      end);
  end;
  Result := mFound;
end;

function Insertion(const APosition: TTextPosition; const AText: string): TTextEdit;
begin
  Result := TTextEdit.Create(TTextRange.Create(APosition, APosition), AText);
end;

function Fix(const ACode, ATitle: string; const AEdits: TArray<TTextEdit>; APreferred: Boolean): TCompilerFix;
begin
  Result.Code := ACode;
  Result.Title := ATitle;
  Result.Edits := AEdits;
  Result.Preferred := APreferred;
end;

{ TCompilerFixes }

class function TCompilerFixes.Codes: TArray<string>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(cFixCodes));
  for mIndex := 0 to High(cFixCodes) do
  begin
    Result[mIndex] := cFixCodes[mIndex];
  end;
end;

class function TCompilerFixes.CanFixAll(const ACode: string): Boolean;
begin
  Result := MatchText(Trim(ACode), cFixAllCodes);
end;

class function TCompilerFixes.QuotedNames(const AText: string): TArray<string>;
var
  mIndex, mStart: Integer;
begin
  Result := nil;
  mIndex := 1;
  while mIndex <= Length(AText) do
  begin
    if AText[mIndex] = '''' then
    begin
      mStart := mIndex + 1;
      mIndex := mStart;
      while (mIndex <= Length(AText)) and (AText[mIndex] <> '''') do
      begin
        Inc(mIndex);
      end;
      if mIndex > Length(AText) then
      begin
        Break;
      end;
      Result := Result + [Copy(AText, mStart, mIndex - mStart)];
    end;
    Inc(mIndex);
  end;
end;

function LibraryRank(const AUnit: string): Integer;
var
  mDot: Integer;
begin
  mDot := Pos('.', AUnit);
  Result := 1;
  if (mDot > 0) and MatchText(Copy(AUnit, 1, mDot - 1), cLibraryNamespaces) then
  begin
    Result := 0;
  end;
end;

class function TCompilerFixes.RankUnits(const AUnits: TArray<string>): TArray<string>;
begin
  Result := Copy(AUnits);
  // Eindeutig weitersortieren: TArray.Sort ist nicht stabil.
  TArray.Sort<string>(Result, TComparer<string>.Construct(
    function(const ALeft, ARight: string): Integer
    begin
      Result := LibraryRank(ALeft) - LibraryRank(ARight);
      if Result = 0 then
      begin
        Result := Length(ALeft) - Length(ARight);
      end;
      if Result = 0 then
      begin
        Result := CompareText(ALeft, ARight);
      end;
      if Result = 0 then
      begin
        Result := CompareStr(ALeft, ARight);
      end;
    end));
end;

/// <summary>Korrektur "uses AUnit ergänzen" an AFixes anhängen; die erste in AFixes ist die bevorzugte.
/// </summary>
procedure AddUnitFix(const AText: string; const ATokens: TArray<TPascalToken>; const AMessage: TFixMessage;
  const AUnit, ATitle: string; var AFixes: TArray<TCompilerFix>);
var
  mEdit: TTextEdit;
  mOffset: Integer;
begin
  mOffset := OffsetOf(AText, AMessage.Line);
  if (mOffset >= 0) and TUsesClauses.AddUnit(ATokens, mOffset, AUnit, TTextLines.LineBreakOf(AText), mEdit) then
  begin
    AFixes := AFixes + [Fix(AMessage.Code, ATitle, [mEdit], Length(AFixes) = 0)];
  end;
end;

function IsUsed(const ATokens: TArray<TPascalToken>; const AUnit: string; const ANamespaces: TArray<string>): Boolean;
begin
  Result := TUsesClauses.IsUsed(TUsesClauses.UsedUnits(ATokens), AUnit, ANamespaces);
end;

function H2443Fixes(const AText: string; const ATokens: TArray<TPascalToken>; const AMessage: TFixMessage;
  const AContext: TCompilerFixContext): TArray<TCompilerFix>;
var
  mNames: TArray<string>;
  mUnitName: string;
begin
  Result := nil;
  mNames := TCompilerFixes.QuotedNames(AMessage.Text);
  if Length(mNames) < 2 then
  begin
    Exit;
  end;
  mUnitName := mNames[High(mNames)];
  if IsUsed(ATokens, mUnitName, AContext.Namespaces) then
  begin
    Exit;
  end;
  AddUnitFix(AText, ATokens, AMessage, mUnitName, cTexts[TCompilerFixesText.AddToUses].Fmt([mUnitName, AMessage.Code]),
    Result);
end;

/// <summary>AToken ist der Bezeichner AName in der Zeile der Meldung.</summary>
function IsNameOnLine(const AToken: TPascalToken; const AMessage: TFixMessage; const AName: string): Boolean;
begin
  Result := (AToken.StartPos.Line = AMessage.Line) and (AToken.Kind = TPascalTokenKind.Identifier) and
    SameText(AToken.Text, AName);
end;

function E2003Fixes(const AText: string; const ATokens: TArray<TPascalToken>; ATree: TSyntaxTree;
  const AMessage: TFixMessage; const AContext: TCompilerFixContext): TArray<TCompilerFix>;
var
  mNames, mUnits: TArray<string>;
  mName, mUnitName: string;
  mToken: TPascalToken;
  mPosition: TTextPosition;
  mFound: Boolean;
begin
  Result := nil;
  mNames := TCompilerFixes.QuotedNames(AMessage.Text);
  if (Length(mNames) = 0) or not Assigned(AContext.Declaring) then
  begin
    Exit;
  end;
  mName := mNames[0];
  // Den Bezeichner in der Zeile suchen; MissingUnits prüft, ob er schon deklariert oder eingebunden ist.
  mFound := False;
  mPosition := TTextPosition.Create(AMessage.Line, 0);
  for mToken in ATokens do
  begin
    if IsNameOnLine(mToken, AMessage, mName) and ((AMessage.Column < 0) or not mFound or
      (mToken.StartPos.Character <= AMessage.Column)) then
    begin
      mPosition := mToken.StartPos;
      mFound := True;
    end;
  end;
  if not mFound then
  begin
    Exit;
  end;
  mUnits := TCompilerFixes.RankUnits(TUsesActions.MissingUnits(ATokens, ATree, mPosition, AContext.Declaring,
    AContext.Namespaces));
  for mUnitName in mUnits do
  begin
    AddUnitFix(AText, ATokens, AMessage, mUnitName, cTexts[TCompilerFixesText.AddToUses2].Fmt([mUnitName, AMessage.Code,
      mName]), Result);
  end;
end;

function RoutineOf(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode;
  while (Result <> nil) and (Result.Kind <> TSyntaxKind.RoutineDecl) do
  begin
    Result := Result.Parent;
  end;
end;

/// <summary>Namen, die in ARoutine (und umschließenden Routinen) als Variable, Parameter oder Konstante
/// deklariert sind.</summary>
function LocalNames(ARoutine: TSyntaxNode): TArray<string>;
var
  mNames: TArray<string>;
  mRoutine: TSyntaxNode;
begin
  mNames := ['Result', 'nil', 'True', 'False'];
  mRoutine := ARoutine;
  while mRoutine <> nil do
  begin
    mRoutine.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        // Nicht in Rümpfe und verschachtelte Routinen absteigen: Dort deklariert nichts Lokales.
        Result := not (ANode.Kind in [TSyntaxKind.Block]) and
          ((ANode = mRoutine) or (ANode.Kind <> TSyntaxKind.RoutineDecl));
        if ANode.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.Parameter, TSyntaxKind.ConstDecl] then
        begin
          mNames := mNames + [ANode.Name];
        end;
      end);
    mRoutine := RoutineOf(mRoutine.Parent);
  end;
  Result := mNames;
end;

/// <summary>Ausdruck ohne mögliche Nebenwirkung: nur Literale, Operatoren und lokale Namen.</summary>
function IsPure(ANode: TSyntaxNode; const ALocals: TArray<string>): Boolean;
var
  mIndex: Integer;
begin
  case ANode.Kind of
    TSyntaxKind.Literal:
      Exit(True);
    TSyntaxKind.Identifier:
      Exit(MatchText(ANode.Name, ALocals));
    TSyntaxKind.BinaryExpr, TSyntaxKind.UnaryExpr, TSyntaxKind.ParenExpr, TSyntaxKind.SetConstructor,
      TSyntaxKind.RangeExpr:
      begin
        // Klassenoperatoren könnten Nebenwirkungen haben; is/as und Mengen sind harmlos genug, Aufrufe nicht.
        for mIndex := 0 to ANode.ChildCount - 1 do
        begin
          if not IsPure(ANode[mIndex], ALocals) then
          begin
            Exit(False);
          end;
        end;
        Exit(True);
      end;
  else
    // Übrige Arten: nichts zu tun.
  end;
  Result := False;
end;

function StatementRemoval(const AText: string; const ATokens: TArray<TPascalToken>; AStatement: TSyntaxNode): TTextEdit;
var
  mIndex, mLast: Integer;
  mLines: TArray<string>;
  mLine: string;
  mEndPos: TTextPosition;
begin
  mEndPos := AStatement.EndPos;
  if TRoutineBody.InList(AStatement) then
  begin
    // Mit dem Semikolon dahinter; steht die Anweisung allein in ihrer Zeile, verschwindet die ganze Zeile.
    mIndex := TRoutineBody.TokenAt(ATokens, AStatement.EndOffset);
    mLast := TRoutineBody.NextToken(ATokens, mIndex - 1);
    if (mLast >= 0) and (mLast < Length(ATokens)) and ATokens[mLast].IsSymbol(';') then
    begin
      mEndPos := ATokens[mLast].EndPos;
    end;
    mLines := TTextLines.SplitLines(AText);
    if (AStatement.StartPos.Line = mEndPos.Line) and (mEndPos.Line < High(mLines)) then
    begin
      mLine := mLines[mEndPos.Line];
      if (Trim(Copy(mLine, 1, AStatement.StartPos.Character)) = '') and
        (Trim(Copy(mLine, mEndPos.Character + 1, MaxInt)) = '') then
      begin
        Exit(TTextEdit.Create(TTextRange.Create(mEndPos.Line, 0, mEndPos.Line + 1, 0), ''));
      end;
    end;
  end;
  Result := TTextEdit.Create(TTextRange.Create(AStatement.StartPos, mEndPos), '');
end;

function H2077Fixes(const AText: string; const ATokens: TArray<TPascalToken>; ATree: TSyntaxTree;
  const AMessage: TFixMessage): TArray<TCompilerFix>;
var
  mNames: TArray<string>;
  mStatement, mValue: TSyntaxNode;
  mName: string;
begin
  Result := nil;
  mNames := TCompilerFixes.QuotedNames(AMessage.Text);
  if Length(mNames) = 0 then
  begin
    Exit;
  end;
  mName := mNames[0];
  for mStatement in NodesOnLine(ATree.Root, AMessage.Line, TSyntaxKind.AssignStatement) do
  begin
    if (mStatement.ChildCount < 2) or (mStatement[0].Kind <> TSyntaxKind.Identifier) or
      not SameText(mStatement[0].Name, mName) then
    begin
      Continue;
    end;
    mValue := mStatement[1];
    // Erst Result, dann Exit: Exit([...]) liest Delphi als Menge (E2001).
    if IsPure(mValue, LocalNames(RoutineOf(mStatement))) then
    begin
      Result := [Fix(AMessage.Code, cTexts[TCompilerFixesText.RemoveIneffectiveAssignmentTo].Fmt([mName,
        AMessage.Code]),
        [StatementRemoval(AText, ATokens, mStatement)], True)];
      Exit;
    end
    else if mValue.Kind = TSyntaxKind.Call then
    begin
      // Der Aufruf bleibt, nur die Zuweisung fällt weg.
      Result := [Fix(AMessage.Code, cTexts[TCompilerFixesText.RemoveAssignmentToOnlyCall].Fmt([mName, mValue.Name,
        AMessage.Code]), [TTextEdit.Create(TTextRange.Create(mStatement.StartPos, mValue.StartPos), '')], True)];
      Exit;
    end;
  end;
end;

function W1035Fixes(const AText: string; ATree: TSyntaxTree; const AMessage: TFixMessage): TArray<TCompilerFix>;
var
  mRoutine, mHeader, mBody, mResultType: TSyntaxNode;
  mIndex: Integer;
  mTypeText, mIndent: string;
  mLines: TArray<string>;
  mLineBreak: string;
begin
  Result := nil;
  // Die Meldung steht auf dem end der Funktion (oder ihrem Kopf): innerste Routine um die Zeile.
  mRoutine := TDisableWarning.RoutineAt(ATree, AMessage.Line);
  if mRoutine = nil then
  begin
    Exit;
  end;
  mHeader := mRoutine.FindChild(TSyntaxKind.RoutineHeader);
  mBody := TRoutineBody.BodyOf(mRoutine);
  if (mHeader = nil) or (mBody = nil) then
  begin
    Exit;
  end;
  mResultType := nil;
  for mIndex := 0 to mHeader.ChildCount - 1 do
  begin
    if mHeader[mIndex].Kind = TSyntaxKind.TypeReference then
    begin
      mResultType := mHeader[mIndex];
    end;
  end;
  if mResultType = nil then
  begin
    Exit;
  end;
  mTypeText := TRoutineBody.TextOf(AText, mResultType);
  mLines := TTextLines.SplitLines(AText, mLineBreak);
  mIndent := TTextLines.IndentOf(mLines[mBody.StartPos.Line]) + '  ';
  if (mBody.ChildCount > 0) and (mBody[0].StartPos.Line > mBody.StartPos.Line) then
  begin
    mIndent := TTextLines.IndentOf(mLines[mBody[0].StartPos.Line]);
  end;
  Result := [Fix(AMessage.Code, cTexts[TCompilerFixesText.InsertResultDefaultAtThe].Fmt([mTypeText,
    AMessage.Code]), [Insertion(TTextPosition.Create(mBody.StartPos.Line, mBody.StartPos.Character + Length('begin')),
    mLineBreak + mIndent + Format('Result := Default(%s);', [mTypeText]))], True)];
end;

/// <summary>Rechte Seiten der Zuweisungen in Zeile ALine.</summary>
function AssignmentValues(ATree: TSyntaxTree; ALine: Integer): TArray<TSyntaxNode>;
var
  mNode: TSyntaxNode;
begin
  Result := nil;
  for mNode in NodesOnLine(ATree.Root, ALine, TSyntaxKind.AssignStatement) do
  begin
    if mNode.ChildCount >= 2 then
    begin
      Result := Result + [mNode[1]];
    end;
  end;
end;

/// <summary>Argumente der Aufrufe, die in Zeile ALine beginnen.</summary>
function CallArguments(ATree: TSyntaxTree; ALine: Integer): TArray<TSyntaxNode>;
var
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  Result := nil;
  for mNode in NodesOnLine(ATree.Root, ALine, TSyntaxKind.Call) do
  begin
    for mIndex := 1 to mNode.ChildCount - 1 do
    begin
      if mNode[mIndex].StartPos.Line = ALine then
      begin
        Result := Result + [mNode[mIndex]];
      end;
    end;
  end;
end;

/// <summary>ANode reicht über die Spalte der Meldung.</summary>
function CoversColumn(ANode: TSyntaxNode; const AMessage: TFixMessage): Boolean;
begin
  Result := (ANode.StartPos.Character <= AMessage.Column) and ((ANode.EndPos.Line > AMessage.Line) or
    (AMessage.Column <= ANode.EndPos.Character));
end;

/// <summary>Kürzester Kandidat über der Spalte der Meldung; nil ohne.</summary>
function SmallestAt(const ACandidates: TArray<TSyntaxNode>; const AMessage: TFixMessage): TSyntaxNode;
var
  mNode: TSyntaxNode;
begin
  Result := nil;
  for mNode in ACandidates do
  begin
    if CoversColumn(mNode, AMessage) and ((Result = nil) or
      (mNode.EndOffset - mNode.StartOffset < Result.EndOffset - Result.StartOffset)) then
    begin
      Result := mNode;
    end;
  end;
end;

/// <summary>Ausdruck, der umgewandelt werden soll: rechte Seite einer Zuweisung oder Argument eines Aufrufs in der
/// Zeile; ohne Spalte nur eindeutig (genau eine Zuweisung in der Zeile). nil ohne.</summary>
function CastTarget(ATree: TSyntaxTree; const AMessage: TFixMessage): TSyntaxNode;
var
  mCandidates: TArray<TSyntaxNode>;
begin
  mCandidates := AssignmentValues(ATree, AMessage.Line);
  if AMessage.Column >= 0 then
  begin
    Result := SmallestAt(mCandidates + CallArguments(ATree, AMessage.Line), AMessage);
  end
  else if Length(mCandidates) = 1 then
  begin
    Result := mCandidates[0];
  end
  else
  begin
    Result := nil;
  end;
end;

function StringCastFixes(ATree: TSyntaxTree; const AMessage: TFixMessage): TArray<TCompilerFix>;
var
  mNames: TArray<string>;
  mTarget: string;
  mChosen: TSyntaxNode;
begin
  Result := nil;
  mNames := TCompilerFixes.QuotedNames(AMessage.Text);
  if Length(mNames) < 2 then
  begin
    Exit;
  end;
  mTarget := mNames[High(mNames)];
  mChosen := CastTarget(ATree, AMessage);
  if mChosen <> nil then
  begin
    Result := [Fix(AMessage.Code, cTexts[TCompilerFixesText.CastExplicitly].Fmt([mTarget, AMessage.Code]),
      [Insertion(mChosen.StartPos, mTarget + '('), Insertion(mChosen.EndPos, ')')], True)];
  end;
end;

class function TCompilerFixes.Fixes(const AText: string; ATree: TSyntaxTree; const AMessage: TFixMessage;
  const AContext: TCompilerFixContext): TArray<TCompilerFix>;
var
  mTokens: TArray<TPascalToken>;
begin
  Result := nil;
  if (ATree = nil) or (AMessage.Line < 0) then
  begin
    Exit;
  end;
  mTokens := ATree.Tokens;
  if AMessage.Code = 'H2443' then
  begin
    Result := H2443Fixes(AText, mTokens, AMessage, AContext);
  end
  else if AMessage.Code = 'E2003' then
  begin
    Result := E2003Fixes(AText, mTokens, ATree, AMessage, AContext);
  end
  else if AMessage.Code = 'H2077' then
  begin
    Result := H2077Fixes(AText, mTokens, ATree, AMessage);
  end
  else if AMessage.Code = 'W1035' then
  begin
    Result := W1035Fixes(AText, ATree, AMessage);
  end
  else if (AMessage.Code = 'W1057') or (AMessage.Code = 'W1058') then
  begin
    Result := StringCastFixes(ATree, AMessage);
  end;
end;

function Compare(const A, B: TTextPosition): Integer;
begin
  Result := A.Line - B.Line;
  if Result = 0 then
  begin
    Result := A.Character - B.Character;
  end;
end;

/// <summary>AEdit beginnt dort, wo AOther endet, und ist keine bloße Einfügung.</summary>
function StartsAtEndOf(const AEdit, AOther: TTextEdit): Boolean;
begin
  Result := (Compare(AEdit.Range.StartPos, AOther.Range.EndPos) = 0) and
    (Compare(AEdit.Range.StartPos, AEdit.Range.EndPos) <> 0);
end;

/// <summary>Überschneidet sich AEdit mit einer Änderung aus AEdits? Zwei Einfügungen an verschiedenen Stellen
/// nicht, an derselben schon (die Reihenfolge wäre offen).</summary>
function Overlaps(const AEdit: TTextEdit; const AEdits: TArray<TTextEdit>): Boolean;
var
  mOther: TTextEdit;
begin
  for mOther in AEdits do
  begin
    if (Compare(AEdit.Range.StartPos, mOther.Range.EndPos) <= 0) and
      (Compare(mOther.Range.StartPos, AEdit.Range.EndPos) <= 0) and not StartsAtEndOf(AEdit, mOther) and
      not StartsAtEndOf(mOther, AEdit) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function OverlapsAny(const AEdits, AOthers: TArray<TTextEdit>): Boolean;
var
  mEdit: TTextEdit;
begin
  for mEdit in AEdits do
  begin
    if Overlaps(mEdit, AOthers) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Units aus den Meldungen mit ACode, jede einmal.</summary>
function MessageUnits(const AMessages: TArray<TFixMessage>; const ACode: string): TArray<string>;
var
  mMessage: TFixMessage;
  mNames: TArray<string>;
begin
  Result := nil;
  for mMessage in AMessages do
  begin
    if mMessage.Code <> ACode then
    begin
      Continue;
    end;
    mNames := TCompilerFixes.QuotedNames(mMessage.Text);
    if (Length(mNames) >= 2) and (IndexText(mNames[High(mNames)], Result) < 0) then
    begin
      Result := Result + [mNames[High(mNames)]];
    end;
  end;
end;

/// <summary>H2443: Alle Units in einem Schritt, jede einmal; AddUnits verteilt sie auf interface und
/// implementation. Liefert die Zahl der ergänzten Units, 0 ohne.</summary>
function FixAllUnits(const AText: string; ATree: TSyntaxTree; const AMessages: TArray<TFixMessage>;
  const AContext: TCompilerFixContext; out AEdits: TArray<TTextEdit>): Integer;
var
  mUnits, mAdded: TArray<string>;
begin
  Result := 0;
  AEdits := nil;
  mUnits := MessageUnits(AMessages, 'H2443');
  if (Length(mUnits) >= 2) and TUsesActions.AddUnits(ATree.Tokens, TUsesAddRequest.Create(mUnits,
    AContext.Declaring, AContext.Namespaces, TTextLines.LineBreakOf(AText)), AEdits, mAdded) then
  begin
    Result := Length(mAdded);
  end;
end;

/// <summary>Je Meldung mit ACode nur die erste (bevorzugte) Korrektur, ohne Überschneidung mit schon gesammelten.
/// Liefert die Zahl der übernommenen Korrekturen.</summary>
function FixAllMessages(const AText: string; ATree: TSyntaxTree; const AMessages: TArray<TFixMessage>;
  const ACode: string; const AContext: TCompilerFixContext; out AEdits: TArray<TTextEdit>): Integer;
var
  mMessage: TFixMessage;
  mFixes: TArray<TCompilerFix>;
begin
  Result := 0;
  AEdits := nil;
  for mMessage in AMessages do
  begin
    if mMessage.Code <> ACode then
    begin
      Continue;
    end;
    mFixes := TCompilerFixes.Fixes(AText, ATree, mMessage, AContext);
    if (mFixes <> nil) and not OverlapsAny(mFixes[0].Edits, AEdits) then
    begin
      AEdits := AEdits + mFixes[0].Edits;
      Inc(Result);
    end;
  end;
end;

class function TCompilerFixes.FixAll(const AText: string; ATree: TSyntaxTree;
  const AMessages: TArray<TFixMessage>; const ACode: string; const AContext: TCompilerFixContext;
  out AFix: TCompilerFix): Boolean;
var
  mEdits: TArray<TTextEdit>;
  mCount: Integer;
  mCode: string;
begin
  AFix := Default(TCompilerFix);
  mCode := UpperCase(Trim(ACode));
  if (ATree = nil) or not CanFixAll(mCode) then
  begin
    Exit(False);
  end;
  if mCode = 'H2443' then
  begin
    mCount := FixAllUnits(AText, ATree, AMessages, AContext, mEdits);
  end
  else
  begin
    mCount := FixAllMessages(AText, ATree, AMessages, mCode, AContext, mEdits);
  end;
  Result := mCount >= 2;
  if Result then
  begin
    AFix := Fix(mCode, cTexts[TCompilerFixesText.FixAllInTheFile].Fmt([mCode, mCount]), mEdits, False);
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.CompilerFixes', cTexts);

end.
