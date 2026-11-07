unit Atlas.Common.Lsp.StepFilter;

// Schrittfilter beim Hineinspringen (#850), Teil des Servers: Welche Routine
// steht an einer Zeile, wie heißt sie voll (Unit.Klasse.Methode) und welche
// filterbaren Arten hat sie. Das Plugin fragt nach jedem F7, dessen Halt in
// eine neue eigene Routine führt, und entscheidet mit debug.stepFilters.kinds
// und debug.stepFilters.patterns selbst (Atlas.Text.StepFilter).
// Befehle:
//   atlas.server.stepFilter, Argumente [uri, line] (Zeile ab 0). Antwort:
//     {"format": 1, "found": true, "name": "Kunden.TKunde.GetName",
//      "container": "TKunde", "routine": "GetName", "startLine": 30,
//      "endLine": 33, "kinds": ["getters", "trivial"]}
//     Die Zeile darf im Rumpf oder im Kopf der Implementierung stehen oder auf
//     der Deklaration im Klassenkopf (Kontextmenü); dann gelten die Arten der
//     Implementierung in derselben Datei. Ist die Datei nicht geöffnet, liest
//     der Server sie selbst.
//   atlas.server.stepFilterCounts, Argumente [[Muster …]]. Antwort:
//     {"format": 1, "files": 12, "routines": 340, "truncated": false,
//      "kinds": {"getters": 41, …}, "patterns": [3, 0]}
//     Treffer über alle Projekt-Units des Index (ohne Bibliotheken) für das
//     Fenster „Schrittfilter“.
// Arten (so eng, dass F7 nichts überspringt, worin es um etwas geht):
//   - getters/setters: read- bzw. write-Methode einer Eigenschaft derselben
//     Klasse, deren Rumpf aus genau einer einfachen Anweisung besteht
//     (Zuweisung, Aufruf, Exit); Getter mit mehr Anweisungen oder mit if,
//     Schleifen, try … bleiben stehen.
//   - trivial: Rumpf ist genau eine Zuweisung an Result, den Funktionsnamen
//     oder ein Feld (Bezeichner, der weder Parameter noch lokale Variable ist,
//     auch Self.X), bzw. Exit(Wert); im Wert steht kein Aufruf mit Klammern
//     und keine anonyme Methode. Ein Bezeichner ohne Klammern gilt als Wert.
//   - operators: class operator.
//   - emptyConstructors: Konstruktor oder Destruktor, dessen Rumpf leer ist
//     oder nur inherited aufruft (Argumente ohne weitere Aufrufe).
// Routinen in asm haben nur die Art operators, wenn sie eine sind.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Text.StepFilter,
  Atlas.Common.Pascal.SyntaxTree;

type
  TLspStepRoutine = record
    /// <summary>Unit.TKlasse.Methode, bei lokalen Routinen Unit.TKlasse.Methode.Lokal.</summary>
    Name: string;
    /// <summary>TKlasse (TAussen.TInnen); '' bei freien Routinen.</summary>
    Container: string;
    Routine: string;
    /// <summary>Kopf bis end; (ab 0).</summary>
    StartLine: Integer;
    EndLine: Integer;
    Kinds: TStepFilterKinds;
  end;

  TLspStepFilterCounts = record
    Files: Integer;
    Routines: Integer;
    Kinds: array[TStepFilterKind] of Integer;
    Patterns: TArray<Integer>;
    Truncated: Boolean;
  end;

  TLspStepFilter = class
  public const
    cCommand = 'atlas.server.stepFilter';
    cCountsCommand = 'atlas.server.stepFilterCounts';
    /// <summary>Höchstens so viele Dateien zählt CountsCommand.</summary>
    cMaxFiles = 5000;
  private
    class function Keyword(AHeader: TSyntaxNode; const AText: string): string; static;
    class function Statements(ABlock: TSyntaxNode): TArray<TSyntaxNode>; static;
    class function HasCall(ANode: TSyntaxNode): Boolean; static;
    class function IsInherited(AStatement: TSyntaxNode): Boolean; static;
    class function IsSimple(AStatement: TSyntaxNode): Boolean; static;
    class function IsFieldTarget(ATarget: TSyntaxNode; const ALocals: TArray<string>): Boolean; static;
    class function IsTrivial(ARoutine: TSyntaxNode; const AShortName: string): Boolean; static;
    class function LocalNames(ARoutine: TSyntaxNode): TArray<string>; static;
    class function FindType(ARoot: TSyntaxNode; const AContainer: string): TSyntaxNode; static;
    class function IsAccessor(ATree: TSyntaxTree; const AText, AContainer, ARoutine: string;
      AWrite: Boolean): Boolean; static;
    class function RoutineOf(ATree: TSyntaxTree; const AText: string; ANode: TSyntaxNode): TLspStepRoutine; static;
    class function FindImplementation(ATree: TSyntaxTree; const AQualified: string): TSyntaxNode; static;
  public
    /// <summary>Name der Unit bzw. des Programms; '' ohne.</summary>
    class function UnitName(ATree: TSyntaxTree): string; static;
    /// <summary>Name ohne Typargumente in jedem Teil: TList&lt;T&gt;.Add → TList.Add.</summary>
    class function PlainName(const AName: string): string; static;
    /// <summary>Filterbare Arten der Routine ARoutine (RoutineDecl mit Rumpf).</summary>
    class function Classify(ATree: TSyntaxTree; const AText: string; ARoutine: TSyntaxNode): TStepFilterKinds;
      static;
    /// <summary>Innerste Routine mit Rumpf an ALine, sonst die Deklaration im Klassenkopf an ALine; False ohne.
    /// </summary>
    class function RoutineAt(ATree: TSyntaxTree; const AText: string; ALine: Integer;
      out ARoutine: TLspStepRoutine): Boolean; static;
    /// <summary>Alle Routinen mit Rumpf der Datei (auch lokale), in Dateireihenfolge.</summary>
    class function Routines(ATree: TSyntaxTree; const AText: string): TArray<TLspStepRoutine>; static;
    /// <summary>Zählt die Routinen der Datei zu ACounts (Arten und je Muster aus APatterns).</summary>
    class procedure AddCounts(ATree: TSyntaxTree; const AText: string; const APatterns: TArray<string>;
      var ACounts: TLspStepFilterCounts); static;
    class function NewCounts(const APatterns: TArray<string>): TLspStepFilterCounts; static;
    class function ToJson(AFound: Boolean; const ARoutine: TLspStepRoutine): TJSONObject; static;
    class function CountsToJson(const ACounts: TLspStepFilterCounts): TJSONObject; static;
    /// <summary>Der Befehl Command für eine Datei: Antwort als JSON (format 1).</summary>
    class function Execute(ATree: TSyntaxTree; const AText: string; ALine: Integer): TJSONObject; static;
    /// <summary>Muster aus dem ersten Argument von CountsCommand (Array von Strings); ungültige fallen weg.</summary>
    class function ReadPatterns(AArguments: TJSONArray): TArray<string>; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.StrUtils,
  Atlas.Common.Lsp.StepTargets;

function Contains(const AList: TArray<string>; const AName: string): Boolean;
var
  mItem: string;
begin
  for mItem in AList do
  begin
    if SameText(mItem, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function LastPart(const AName: string): string;
var
  mDot: Integer;
begin
  Result := AName;
  mDot := LastDelimiter('.', Result);
  if mDot > 0 then
  begin
    Result := Copy(Result, mDot + 1, MaxInt);
  end;
end;

function ContainerPart(const AName: string): string;
var
  mDot: Integer;
begin
  Result := '';
  mDot := LastDelimiter('.', AName);
  if mDot > 0 then
  begin
    Result := Copy(AName, 1, mDot - 1);
  end;
end;

{ TLspStepFilter }

class function TLspStepFilter.PlainName(const AName: string): string;
var
  mDepth: Integer;
  mChar: Char;
begin
  Result := '';
  mDepth := 0;
  for mChar in AName do
  begin
    if mChar = '<' then
    begin
      Inc(mDepth);
    end
    else if mChar = '>' then
    begin
      if mDepth > 0 then
      begin
        Dec(mDepth);
      end;
    end
    else if mDepth = 0 then
    begin
      Result := Result + mChar;
    end;
  end;
end;

class function TLspStepFilter.UnitName(ATree: TSyntaxTree): string;
begin
  Result := '';
  if (ATree <> nil) and (ATree.Root <> nil) then
  begin
    Result := ATree.Root.Name;
  end;
end;

class function TLspStepFilter.Keyword(AHeader: TSyntaxNode; const AText: string): string;
var
  mWords: TArray<string>;
  mStart, mLength: Integer;
begin
  // Der Baum merkt sich das Schlüsselwort nicht: aus dem Text des Kopfs ([class] procedure|…|operator).
  Result := '';
  if AHeader = nil then
  begin
    Exit;
  end;
  mStart := AHeader.StartOffset + 1;
  mLength := AHeader.EndOffset - AHeader.StartOffset;
  if mLength > 40 then
  begin
    mLength := 40;
  end;
  mWords := LowerCase(Copy(AText, mStart, mLength)).Replace(#13, ' ').Replace(#10, ' ').Replace(#9, ' ').Split([' '],
    TStringSplitOptions.ExcludeEmpty);
  if Length(mWords) = 0 then
  begin
    Exit;
  end;
  Result := mWords[0];
  if (Result = 'class') and (Length(mWords) > 1) then
  begin
    Result := mWords[1];
  end;
end;

class function TLspStepFilter.Statements(ABlock: TSyntaxNode): TArray<TSyntaxNode>;
var
  mIndex: Integer;
begin
  Result := nil;
  if ABlock = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to ABlock.ChildCount - 1 do
  begin
    if ABlock[mIndex].Kind <> TSyntaxKind.EmptyStatement then
    begin
      Result := Result + [ABlock[mIndex]];
    end;
  end;
end;

class function TLspStepFilter.HasCall(ANode: TSyntaxNode): Boolean;
var
  mFound: TSyntaxNode;
begin
  Result := False;
  if ANode = nil then
  begin
    Exit;
  end;
  mFound := ANode.Search(
    function(ANext: TSyntaxNode): TSyntaxSearchStep
    begin
      if ANext.Kind in [TSyntaxKind.Call, TSyntaxKind.AnonymousMethod, TSyntaxKind.InheritedExpr] then
      begin
        Result := TSyntaxSearchStep.Found;
      end
      else
      begin
        Result := TSyntaxSearchStep.Descend;
      end;
    end);
  Result := mFound <> nil;
end;

class function TLspStepFilter.IsInherited(AStatement: TSyntaxNode): Boolean;
var
  mExpression, mArgument: TSyntaxNode;
  mIndex: Integer;
begin
  Result := False;
  if (AStatement.Kind <> TSyntaxKind.CallStatement) or (AStatement.ChildCount <> 1) then
  begin
    Exit;
  end;
  mExpression := AStatement[0];
  if mExpression.Kind = TSyntaxKind.InheritedExpr then
  begin
    Exit(True);
  end;
  // inherited Create(AOwner): Aufruf mit inherited vorn; die Argumente rufen nichts auf.
  if (mExpression.Kind <> TSyntaxKind.Call) or (mExpression.ChildCount = 0) or
    (mExpression[0].Kind <> TSyntaxKind.InheritedExpr) then
  begin
    Exit;
  end;
  for mIndex := 1 to mExpression.ChildCount - 1 do
  begin
    mArgument := mExpression[mIndex];
    if HasCall(mArgument) then
    begin
      Exit;
    end;
  end;
  Result := True;
end;

class function TLspStepFilter.IsSimple(AStatement: TSyntaxNode): Boolean;
begin
  Result := AStatement.Kind in [TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement];
end;

/// <summary>Hängt die durch Komma getrennten Namen aus AText an AResult an.</summary>
procedure AddNames(var AResult: TArray<string>; const AText: string);
var
  mName: string;
begin
  for mName in AText.Split([',']) do
  begin
    AResult := AResult + [Trim(mName)];
  end;
end;

/// <summary>Namen der Parameter im Kopf von ARoutine.</summary>
function ParameterNames(ARoutine: TSyntaxNode): TArray<string>;
var
  mHeader, mParams: TSyntaxNode;
  mIndex: Integer;
begin
  Result := nil;
  mHeader := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  if mHeader = nil then
  begin
    Exit;
  end;
  mParams := mHeader.FindChild(TSyntaxKind.Parameters);
  if mParams = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mParams.ChildCount - 1 do
  begin
    if mParams[mIndex].Kind = TSyntaxKind.Parameter then
    begin
      AddNames(Result, mParams[mIndex].Name);
    end;
  end;
end;

/// <summary>Namen der Variablen und Konstanten der Abschnitte von ARoutine.</summary>
function SectionNames(ARoutine: TSyntaxNode): TArray<string>;
var
  mSection: TSyntaxNode;
  mIndex, mInner: Integer;
begin
  Result := nil;
  for mIndex := 0 to ARoutine.ChildCount - 1 do
  begin
    mSection := ARoutine[mIndex];
    if not (mSection.Kind in [TSyntaxKind.VarSection, TSyntaxKind.ConstSection]) then
    begin
      Continue;
    end;
    for mInner := 0 to mSection.ChildCount - 1 do
    begin
      if mSection[mInner].Kind in [TSyntaxKind.VarDecl, TSyntaxKind.ConstDecl] then
      begin
        AddNames(Result, mSection[mInner].Name);
      end;
    end;
  end;
end;

class function TLspStepFilter.LocalNames(ARoutine: TSyntaxNode): TArray<string>;
begin
  Result := ParameterNames(ARoutine) + SectionNames(ARoutine);
end;

class function TLspStepFilter.IsFieldTarget(ATarget: TSyntaxNode; const ALocals: TArray<string>): Boolean;
begin
  Result := False;
  case ATarget.Kind of
    TSyntaxKind.Identifier:
      Result := not Contains(ALocals, ATarget.Name);
    TSyntaxKind.MemberAccess:
      Result := (ATarget.ChildCount = 1) and (ATarget[0].Kind = TSyntaxKind.Identifier) and
        SameText(ATarget[0].Name, 'Self');
  else
    // Übrige Arten: nichts zu tun.
  end;
end;

class function TLspStepFilter.IsTrivial(ARoutine: TSyntaxNode; const AShortName: string): Boolean;
var
  mBody: TArray<TSyntaxNode>;
  mStatement, mTarget, mCallee: TSyntaxNode;
begin
  Result := False;
  mBody := Statements(ARoutine.FindChild(TSyntaxKind.Block));
  if Length(mBody) <> 1 then
  begin
    Exit;
  end;
  mStatement := mBody[0];
  if (mStatement.Kind = TSyntaxKind.AssignStatement) and (mStatement.ChildCount = 2) then
  begin
    mTarget := mStatement[0];
    if HasCall(mStatement[1]) then
    begin
      Exit;
    end;
    if (mTarget.Kind = TSyntaxKind.Identifier) and
      (SameText(mTarget.Name, 'Result') or SameText(mTarget.Name, AShortName)) then
    begin
      Exit(True);
    end;
    Exit(IsFieldTarget(mTarget, LocalNames(ARoutine)));
  end;
  // Exit(Wert)
  if (mStatement.Kind = TSyntaxKind.CallStatement) and (mStatement.ChildCount = 1) and
    (mStatement[0].Kind = TSyntaxKind.Call) and (mStatement[0].ChildCount = 2) then
  begin
    mCallee := mStatement[0][0];
    Result := (mCallee.Kind = TSyntaxKind.Identifier) and SameText(mCallee.Name, 'Exit') and
      not HasCall(mStatement[0][1]);
  end;
end;

class function TLspStepFilter.FindType(ARoot: TSyntaxNode; const AContainer: string): TSyntaxNode;
begin
  Result := nil;
  if (ARoot = nil) or (AContainer = '') then
  begin
    Exit;
  end;
  Result := ARoot.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      // In Rümpfen stehen keine Klassen mit Eigenschaften, die eine Methode der Unit bedienen.
      if ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.InitializationSection,
        TSyntaxKind.FinalizationSection] then
      begin
        Exit(TSyntaxSearchStep.Skip);
      end;
      if (ANode.Kind = TSyntaxKind.TypeDecl) and SameText(PlainName(ANode.EnclosingTypeName), AContainer) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end);
end;

class function TLspStepFilter.IsAccessor(ATree: TSyntaxTree; const AText, AContainer, ARoutine: string;
  AWrite: Boolean): Boolean;
var
  mType, mBody, mMember: TSyntaxNode;
  mIndex, mInner: Integer;
  mDeclaration: string;
begin
  Result := False;
  mType := FindType(ATree.Root, AContainer);
  if mType = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mType.ChildCount - 1 do
  begin
    mBody := mType[mIndex];
    if not (mBody.Kind in [TSyntaxKind.ClassType, TSyntaxKind.RecordType, TSyntaxKind.ObjectType,
      TSyntaxKind.HelperType]) then
    begin
      Continue;
    end;
    for mInner := 0 to mBody.ChildCount - 1 do
    begin
      mMember := mBody[mInner];
      if mMember.Kind <> TSyntaxKind.PropertyDecl then
      begin
        Continue;
      end;
      mDeclaration := Copy(AText, mMember.StartOffset + 1, mMember.EndOffset - mMember.StartOffset);
      if SameText(TLspStepTargets.Accessor(mDeclaration, AWrite), ARoutine) then
      begin
        Exit(True);
      end;
    end;
  end;
end;

/// <summary>True, wenn ABody höchstens aus einem inherited-Aufruf besteht.</summary>
function OnlyInherited(const ABody: TArray<TSyntaxNode>): Boolean;
var
  mStatement: TSyntaxNode;
begin
  Result := Length(ABody) <= 1;
  for mStatement in ABody do
  begin
    if not TLspStepFilter.IsInherited(mStatement) then
    begin
      Result := False;
    end;
  end;
end;

/// <summary>Getter bzw. Setter einer Eigenschaft: Methode mit Punkt im Namen und einer einfachen Anweisung.</summary>
function AccessorKinds(ATree: TSyntaxTree; const AText, AWord, AName: string;
  const ABody: TArray<TSyntaxNode>): TStepFilterKinds;
var
  mContainer, mShort: string;
begin
  Result := [];
  mContainer := ContainerPart(AName);
  mShort := LastPart(AName);
  if (mContainer = '') or (Length(ABody) <> 1) or not TLspStepFilter.IsSimple(ABody[0]) then
  begin
    Exit;
  end;
  if (AWord = 'function') and TLspStepFilter.IsAccessor(ATree, AText, mContainer, mShort, False) then
  begin
    Include(Result, TStepFilterKind.Getters);
  end;
  if (AWord = 'procedure') and TLspStepFilter.IsAccessor(ATree, AText, mContainer, mShort, True) then
  begin
    Include(Result, TStepFilterKind.Setters);
  end;
end;

class function TLspStepFilter.Classify(ATree: TSyntaxTree; const AText: string;
  ARoutine: TSyntaxNode): TStepFilterKinds;
var
  mBlock: TSyntaxNode;
  mWord, mName: string;
  mBody: TArray<TSyntaxNode>;
begin
  Result := [];
  if (ARoutine = nil) or (ARoutine.Kind <> TSyntaxKind.RoutineDecl) then
  begin
    Exit;
  end;
  mWord := Keyword(ARoutine.FindChild(TSyntaxKind.RoutineHeader), AText);
  if mWord = 'operator' then
  begin
    Include(Result, TStepFilterKind.Operators);
  end;
  mBlock := ARoutine.FindChild(TSyntaxKind.Block);
  if mBlock = nil then
  begin
    Exit;
  end;
  mName := PlainName(ARoutine.Name);
  mBody := Statements(mBlock);
  if ((mWord = 'constructor') or (mWord = 'destructor')) and OnlyInherited(mBody) then
  begin
    Include(Result, TStepFilterKind.EmptyConstructors);
  end;
  if IsTrivial(ARoutine, LastPart(mName)) then
  begin
    Include(Result, TStepFilterKind.Trivial);
  end;
  // Methode einer Klasse: Name mit Punkt, Kopf außerhalb eines Typs (sonst Deklaration).
  Result := Result + AccessorKinds(ATree, AText, mWord, mName, mBody);
end;

class function TLspStepFilter.RoutineOf(ATree: TSyntaxTree; const AText: string;
  ANode: TSyntaxNode): TLspStepRoutine;
var
  mOuter: TSyntaxNode;
  mName, mPrefix: string;
begin
  Result := Default(TLspStepRoutine);
  mName := PlainName(ANode.Name);
  // Lokale Routinen tragen die Namen der umgebenden davor.
  mOuter := ANode.Parent;
  while mOuter <> nil do
  begin
    if mOuter.Kind = TSyntaxKind.RoutineDecl then
    begin
      mName := PlainName(mOuter.Name) + '.' + mName;
    end;
    mOuter := mOuter.Parent;
  end;
  if ANode.Kind = TSyntaxKind.RoutineHeader then
  begin
    // Deklaration im Klassenkopf: Typ davor.
    mPrefix := PlainName(ANode.EnclosingTypeName);
    if mPrefix <> '' then
    begin
      mName := mPrefix + '.' + mName;
    end;
  end;
  Result.Container := ContainerPart(mName);
  Result.Routine := LastPart(mName);
  if UnitName(ATree) <> '' then
  begin
    Result.Name := UnitName(ATree) + '.' + mName;
  end
  else
  begin
    Result.Name := mName;
  end;
  Result.StartLine := ANode.StartPos.Line;
  Result.EndLine := ANode.EndPos.Line;
  if ANode.Kind = TSyntaxKind.RoutineDecl then
  begin
    Result.Kinds := Classify(ATree, AText, ANode);
  end;
end;

class function TLspStepFilter.FindImplementation(ATree: TSyntaxTree; const AQualified: string): TSyntaxNode;
begin
  Result := ATree.Root.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if (ANode.Kind = TSyntaxKind.RoutineDecl) and SameText(PlainName(ANode.Name), AQualified) and
        (ANode.FindChild(TSyntaxKind.Block) <> nil) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end);
end;

class function TLspStepFilter.RoutineAt(ATree: TSyntaxTree; const AText: string; ALine: Integer;
  out ARoutine: TLspStepRoutine): Boolean;
var
  mFound, mHeader, mBody: TSyntaxNode;
  mQualified: string;
  mLine: TLspStepRoutine;
begin
  ARoutine := Default(TLspStepRoutine);
  Result := False;
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit;
  end;
  mFound := nil;
  mHeader := nil;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := (ANode.StartPos.Line <= ALine) and (ANode.EndPos.Line >= ALine);
      if not Result then
      begin
        Exit;
      end;
      if (ANode.Kind = TSyntaxKind.RoutineDecl) and
        ((ANode.FindChild(TSyntaxKind.Block) <> nil) or (ANode.FindChild(TSyntaxKind.AsmBlock) <> nil)) then
      begin
        mFound := ANode;
      end
      else if (ANode.Kind = TSyntaxKind.RoutineHeader) and (ANode.Parent <> nil) and
        (ANode.Parent.Kind <> TSyntaxKind.RoutineDecl) and not ANode.IsMethodResolution then
      begin
        mHeader := ANode;
      end;
    end);
  if mFound <> nil then
  begin
    ARoutine := RoutineOf(ATree, AText, mFound);
    Exit(True);
  end;
  if mHeader = nil then
  begin
    Exit;
  end;
  ARoutine := RoutineOf(ATree, AText, mHeader);
  // Arten der Implementierung derselben Datei.
  mQualified := ARoutine.Container + '.' + ARoutine.Routine;
  mBody := FindImplementation(ATree, mQualified);
  if mBody <> nil then
  begin
    mLine := RoutineOf(ATree, AText, mBody);
    ARoutine.Kinds := mLine.Kinds;
  end;
  Result := True;
end;

class function TLspStepFilter.Routines(ATree: TSyntaxTree; const AText: string): TArray<TLspStepRoutine>;
var
  mList: TArray<TLspStepRoutine>;
begin
  mList := nil;
  if (ATree <> nil) and (ATree.Root <> nil) then
  begin
    ATree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := True;
        if (ANode.Kind = TSyntaxKind.RoutineDecl) and
          ((ANode.FindChild(TSyntaxKind.Block) <> nil) or (ANode.FindChild(TSyntaxKind.AsmBlock) <> nil)) then
        begin
          mList := mList + [RoutineOf(ATree, AText, ANode)];
        end;
      end);
  end;
  Result := mList;
end;

class function TLspStepFilter.NewCounts(const APatterns: TArray<string>): TLspStepFilterCounts;
var
  mIndex: Integer;
begin
  Result := Default(TLspStepFilterCounts);
  SetLength(Result.Patterns, Length(APatterns));
  for mIndex := 0 to High(Result.Patterns) do
  begin
    Result.Patterns[mIndex] := 0;
  end;
end;

class procedure TLspStepFilter.AddCounts(ATree: TSyntaxTree; const AText: string; const APatterns: TArray<string>;
  var ACounts: TLspStepFilterCounts);
var
  mRoutine: TLspStepRoutine;
  mKind: TStepFilterKind;
  mIndex: Integer;
begin
  Inc(ACounts.Files);
  for mRoutine in Routines(ATree, AText) do
  begin
    Inc(ACounts.Routines);
    for mKind := Low(TStepFilterKind) to High(TStepFilterKind) do
    begin
      if mKind in mRoutine.Kinds then
      begin
        Inc(ACounts.Kinds[mKind]);
      end;
    end;
    for mIndex := 0 to High(APatterns) do
    begin
      if (mIndex <= High(ACounts.Patterns)) and TStepFilterNames.Matches(APatterns[mIndex], mRoutine.Name) then
      begin
        Inc(ACounts.Patterns[mIndex]);
      end;
    end;
  end;
end;

class function TLspStepFilter.ToJson(AFound: Boolean; const ARoutine: TLspStepRoutine): TJSONObject;
var
  mKinds: TJSONArray;
  mKind: TStepFilterKind;
begin
  Result := TJSONObject.Create;
  Result.AddPair('format', TJSONNumber.Create(1));
  Result.AddPair('found', TJSONBool.Create(AFound));
  if not AFound then
  begin
    Exit;
  end;
  Result.AddPair('name', ARoutine.Name);
  Result.AddPair('container', ARoutine.Container);
  Result.AddPair('routine', ARoutine.Routine);
  Result.AddPair('startLine', TJSONNumber.Create(ARoutine.StartLine));
  Result.AddPair('endLine', TJSONNumber.Create(ARoutine.EndLine));
  mKinds := TJSONArray.Create;
  Result.AddPair('kinds', mKinds);
  for mKind := Low(TStepFilterKind) to High(TStepFilterKind) do
  begin
    if mKind in ARoutine.Kinds then
    begin
      mKinds.Add(TStepFilterNames.cKindNames[mKind]);
    end;
  end;
end;

class function TLspStepFilter.CountsToJson(const ACounts: TLspStepFilterCounts): TJSONObject;
var
  mKinds: TJSONObject;
  mPatterns: TJSONArray;
  mKind: TStepFilterKind;
  mCount: Integer;
begin
  Result := TJSONObject.Create;
  Result.AddPair('format', TJSONNumber.Create(1));
  Result.AddPair('files', TJSONNumber.Create(ACounts.Files));
  Result.AddPair('routines', TJSONNumber.Create(ACounts.Routines));
  Result.AddPair('truncated', TJSONBool.Create(ACounts.Truncated));
  mKinds := TJSONObject.Create;
  Result.AddPair('kinds', mKinds);
  for mKind := Low(TStepFilterKind) to High(TStepFilterKind) do
  begin
    mKinds.AddPair(TStepFilterNames.cKindNames[mKind], TJSONNumber.Create(ACounts.Kinds[mKind]));
  end;
  mPatterns := TJSONArray.Create;
  Result.AddPair('patterns', mPatterns);
  for mCount in ACounts.Patterns do
  begin
    mPatterns.Add(mCount);
  end;
end;

class function TLspStepFilter.Execute(ATree: TSyntaxTree; const AText: string; ALine: Integer): TJSONObject;
var
  mRoutine: TLspStepRoutine;
  mFound: Boolean;
begin
  mFound := RoutineAt(ATree, AText, ALine, mRoutine);
  Result := ToJson(mFound, mRoutine);
end;

class function TLspStepFilter.ReadPatterns(AArguments: TJSONArray): TArray<string>;
var
  mItems: TJSONArray;
  mIndex: Integer;
begin
  Result := nil;
  if (AArguments = nil) or (AArguments.Count = 0) or not (AArguments.Items[0] is TJSONArray) then
  begin
    Exit;
  end;
  mItems := TJSONArray(AArguments.Items[0]);
  for mIndex := 0 to mItems.Count - 1 do
  begin
    // TJSONNumber erbt von TJSONString: Zahlen sind keine Muster.
    if (mItems.Items[mIndex] is TJSONString) and not (mItems.Items[mIndex] is TJSONNumber) and
      TStepFilterNames.IsValidPattern(Trim(mItems.Items[mIndex].Value)) then
    begin
      Result := Result + [Trim(mItems.Items[mIndex].Value)];
    end;
  end;
end;

end.
