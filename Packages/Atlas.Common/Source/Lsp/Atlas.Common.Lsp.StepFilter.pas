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
    Command = 'atlas.server.stepFilter';
    CountsCommand = 'atlas.server.stepFilterCounts';
    /// <summary>Höchstens so viele Dateien zählt CountsCommand.</summary>
    MaxFiles = 5000;
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
    /// <summary>Name ohne Typargumente in jedem Teil: TList<T>.Add → TList.Add.</summary>
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
    if SameText(mItem, AName) then
      Exit(True);
  Result := False;
end;

function LastPart(const AName: string): string;
var
  mDot: Integer;
begin
  Result := AName;
  mDot := LastDelimiter('.', Result);
  if mDot > 0 then
    Result := Copy(Result, mDot + 1, MaxInt);
end;

function ContainerPart(const AName: string): string;
var
  mDot: Integer;
begin
  Result := '';
  mDot := LastDelimiter('.', AName);
  if mDot > 0 then
    Result := Copy(AName, 1, mDot - 1);
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
    if mChar = '<' then
      Inc(mDepth)
    else if mChar = '>' then
    begin
      if mDepth > 0 then
        Dec(mDepth);
    end
    else if mDepth = 0 then
      Result := Result + mChar;
end;

class function TLspStepFilter.UnitName(ATree: TSyntaxTree): string;
begin
  Result := '';
  if (ATree <> nil) and (ATree.Root <> nil) then
    Result := ATree.Root.Name;
end;

class function TLspStepFilter.Keyword(AHeader: TSyntaxNode; const AText: string): string;
var
  mWords: TArray<string>;
  mStart, mLength: Integer;
begin
  // Der Baum merkt sich das Schlüsselwort nicht: aus dem Text des Kopfs ([class] procedure|…|operator).
  Result := '';
  if AHeader = nil then
    Exit;
  mStart := AHeader.StartOffset + 1;
  mLength := AHeader.EndOffset - AHeader.StartOffset;
  if mLength > 40 then
    mLength := 40;
  mWords := LowerCase(Copy(AText, mStart, mLength)).Replace(#13, ' ').Replace(#10, ' ').Replace(#9, ' ').Split([' '],
    TStringSplitOptions.ExcludeEmpty);
  if Length(mWords) = 0 then
    Exit;
  Result := mWords[0];
  if (Result = 'class') and (Length(mWords) > 1) then
    Result := mWords[1];
end;

class function TLspStepFilter.Statements(ABlock: TSyntaxNode): TArray<TSyntaxNode>;
var
  mIndex: Integer;
begin
  Result := nil;
  if ABlock = nil then
    Exit;
  for mIndex := 0 to ABlock.ChildCount - 1 do
    if ABlock[mIndex].Kind <> TSyntaxKind.EmptyStatement then
      Result := Result + [ABlock[mIndex]];
end;

class function TLspStepFilter.HasCall(ANode: TSyntaxNode): Boolean;
var
  mFound: TSyntaxNode;
begin
  Result := False;
  if ANode = nil then
    Exit;
  mFound := ANode.Search(
    function(ANext: TSyntaxNode): TSyntaxSearchStep
    begin
      if ANext.Kind in [TSyntaxKind.Call, TSyntaxKind.AnonymousMethod, TSyntaxKind.InheritedExpr] then
        Result := TSyntaxSearchStep.Found
      else
        Result := TSyntaxSearchStep.Descend;
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
    Exit;
  mExpression := AStatement[0];
  if mExpression.Kind = TSyntaxKind.InheritedExpr then
    Exit(True);
  // inherited Create(AOwner): Aufruf mit inherited vorn; die Argumente rufen nichts auf.
  if (mExpression.Kind <> TSyntaxKind.Call) or (mExpression.ChildCount = 0) or
    (mExpression[0].Kind <> TSyntaxKind.InheritedExpr) then
    Exit;
  for mIndex := 1 to mExpression.ChildCount - 1 do
  begin
    mArgument := mExpression[mIndex];
    if HasCall(mArgument) then
      Exit;
  end;
  Result := True;
end;

class function TLspStepFilter.IsSimple(AStatement: TSyntaxNode): Boolean;
begin
  Result := AStatement.Kind in [TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement];
end;

class function TLspStepFilter.LocalNames(ARoutine: TSyntaxNode): TArray<string>;
var
  mHeader, mParams, mSection: TSyntaxNode;
  mIndex, mInner: Integer;
  mName: string;
begin
  Result := nil;
  mHeader := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  if mHeader <> nil then
  begin
    mParams := mHeader.FindChild(TSyntaxKind.Parameters);
    if mParams <> nil then
      for mIndex := 0 to mParams.ChildCount - 1 do
        if mParams[mIndex].Kind = TSyntaxKind.Parameter then
          for mName in mParams[mIndex].Name.Split([',']) do
            Result := Result + [Trim(mName)];
  end;
  for mIndex := 0 to ARoutine.ChildCount - 1 do
  begin
    mSection := ARoutine[mIndex];
    if mSection.Kind in [TSyntaxKind.VarSection, TSyntaxKind.ConstSection] then
      for mInner := 0 to mSection.ChildCount - 1 do
        if mSection[mInner].Kind in [TSyntaxKind.VarDecl, TSyntaxKind.ConstDecl] then
          for mName in mSection[mInner].Name.Split([',']) do
            Result := Result + [Trim(mName)];
  end;
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
    Exit;
  mStatement := mBody[0];
  if (mStatement.Kind = TSyntaxKind.AssignStatement) and (mStatement.ChildCount = 2) then
  begin
    mTarget := mStatement[0];
    if HasCall(mStatement[1]) then
      Exit;
    if (mTarget.Kind = TSyntaxKind.Identifier) and
      (SameText(mTarget.Name, 'Result') or SameText(mTarget.Name, AShortName)) then
      Exit(True);
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
    Exit;
  Result := ARoot.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      // In Rümpfen stehen keine Klassen mit Eigenschaften, die eine Methode der Unit bedienen.
      if ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.InitializationSection,
        TSyntaxKind.FinalizationSection] then
        Exit(TSyntaxSearchStep.Skip);
      if (ANode.Kind = TSyntaxKind.TypeDecl) and SameText(PlainName(ANode.EnclosingTypeName), AContainer) then
        Result := TSyntaxSearchStep.Found;
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
    Exit;
  for mIndex := 0 to mType.ChildCount - 1 do
  begin
    mBody := mType[mIndex];
    if not (mBody.Kind in [TSyntaxKind.ClassType, TSyntaxKind.RecordType, TSyntaxKind.ObjectType,
      TSyntaxKind.HelperType]) then
      Continue;
    for mInner := 0 to mBody.ChildCount - 1 do
    begin
      mMember := mBody[mInner];
      if mMember.Kind <> TSyntaxKind.PropertyDecl then
        Continue;
      mDeclaration := Copy(AText, mMember.StartOffset + 1, mMember.EndOffset - mMember.StartOffset);
      if SameText(TLspStepTargets.Accessor(mDeclaration, AWrite), ARoutine) then
        Exit(True);
    end;
  end;
end;

class function TLspStepFilter.Classify(ATree: TSyntaxTree; const AText: string;
  ARoutine: TSyntaxNode): TStepFilterKinds;
var
  mHeader, mBlock: TSyntaxNode;
  mWord, mName, mShort, mContainer: string;
  mBody: TArray<TSyntaxNode>;
  mStatement: TSyntaxNode;
  mOnlyInherited: Boolean;
begin
  Result := [];
  if (ARoutine = nil) or (ARoutine.Kind <> TSyntaxKind.RoutineDecl) then
    Exit;
  mHeader := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  mWord := Keyword(mHeader, AText);
  if mWord = 'operator' then
    Include(Result, TStepFilterKind.Operators);
  mBlock := ARoutine.FindChild(TSyntaxKind.Block);
  if mBlock = nil then
    Exit;
  mName := PlainName(ARoutine.Name);
  mShort := LastPart(mName);
  mBody := Statements(mBlock);
  if (mWord = 'constructor') or (mWord = 'destructor') then
  begin
    mOnlyInherited := Length(mBody) <= 1;
    for mStatement in mBody do
      if not IsInherited(mStatement) then
        mOnlyInherited := False;
    if mOnlyInherited then
      Include(Result, TStepFilterKind.EmptyConstructors);
  end;
  if IsTrivial(ARoutine, mShort) then
    Include(Result, TStepFilterKind.Trivial);
  // Methode einer Klasse: Name mit Punkt, Kopf außerhalb eines Typs (sonst Deklaration).
  mContainer := ContainerPart(mName);
  if (mContainer <> '') and (Length(mBody) = 1) and IsSimple(mBody[0]) then
  begin
    if (mWord = 'function') and IsAccessor(ATree, AText, mContainer, mShort, False) then
      Include(Result, TStepFilterKind.Getters);
    if (mWord = 'procedure') and IsAccessor(ATree, AText, mContainer, mShort, True) then
      Include(Result, TStepFilterKind.Setters);
  end;
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
      mName := PlainName(mOuter.Name) + '.' + mName;
    mOuter := mOuter.Parent;
  end;
  if ANode.Kind = TSyntaxKind.RoutineHeader then
  begin
    // Deklaration im Klassenkopf: Typ davor.
    mPrefix := PlainName(ANode.EnclosingTypeName);
    if mPrefix <> '' then
      mName := mPrefix + '.' + mName;
  end;
  Result.Container := ContainerPart(mName);
  Result.Routine := LastPart(mName);
  if UnitName(ATree) <> '' then
    Result.Name := UnitName(ATree) + '.' + mName
  else
    Result.Name := mName;
  Result.StartLine := ANode.StartPos.Line;
  Result.EndLine := ANode.EndPos.Line;
  if ANode.Kind = TSyntaxKind.RoutineDecl then
    Result.Kinds := Classify(ATree, AText, ANode);
end;

class function TLspStepFilter.FindImplementation(ATree: TSyntaxTree; const AQualified: string): TSyntaxNode;
begin
  Result := ATree.Root.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if (ANode.Kind = TSyntaxKind.RoutineDecl) and SameText(PlainName(ANode.Name), AQualified) and
        (ANode.FindChild(TSyntaxKind.Block) <> nil) then
        Result := TSyntaxSearchStep.Found;
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
    Exit;
  mFound := nil;
  mHeader := nil;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := (ANode.StartPos.Line <= ALine) and (ANode.EndPos.Line >= ALine);
      if not Result then
        Exit;
      if (ANode.Kind = TSyntaxKind.RoutineDecl) and
        ((ANode.FindChild(TSyntaxKind.Block) <> nil) or (ANode.FindChild(TSyntaxKind.AsmBlock) <> nil)) then
        mFound := ANode
      else if (ANode.Kind = TSyntaxKind.RoutineHeader) and (ANode.Parent <> nil) and
        (ANode.Parent.Kind <> TSyntaxKind.RoutineDecl) and not ANode.IsMethodResolution then
        mHeader := ANode;
    end);
  if mFound <> nil then
  begin
    ARoutine := RoutineOf(ATree, AText, mFound);
    Exit(True);
  end;
  if mHeader = nil then
    Exit;
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
    ATree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := True;
        if (ANode.Kind = TSyntaxKind.RoutineDecl) and
          ((ANode.FindChild(TSyntaxKind.Block) <> nil) or (ANode.FindChild(TSyntaxKind.AsmBlock) <> nil)) then
          mList := mList + [RoutineOf(ATree, AText, ANode)];
      end);
  Result := mList;
end;

class function TLspStepFilter.NewCounts(const APatterns: TArray<string>): TLspStepFilterCounts;
var
  mIndex: Integer;
begin
  Result := Default(TLspStepFilterCounts);
  SetLength(Result.Patterns, Length(APatterns));
  for mIndex := 0 to High(Result.Patterns) do
    Result.Patterns[mIndex] := 0;
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
      if mKind in mRoutine.Kinds then
        Inc(ACounts.Kinds[mKind]);
    for mIndex := 0 to High(APatterns) do
      if (mIndex <= High(ACounts.Patterns)) and TStepFilterNames.Matches(APatterns[mIndex], mRoutine.Name) then
        Inc(ACounts.Patterns[mIndex]);
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
    Exit;
  Result.AddPair('name', ARoutine.Name);
  Result.AddPair('container', ARoutine.Container);
  Result.AddPair('routine', ARoutine.Routine);
  Result.AddPair('startLine', TJSONNumber.Create(ARoutine.StartLine));
  Result.AddPair('endLine', TJSONNumber.Create(ARoutine.EndLine));
  mKinds := TJSONArray.Create;
  Result.AddPair('kinds', mKinds);
  for mKind := Low(TStepFilterKind) to High(TStepFilterKind) do
    if mKind in ARoutine.Kinds then
      mKinds.Add(TStepFilterNames.KindNames[mKind]);
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
    mKinds.AddPair(TStepFilterNames.KindNames[mKind], TJSONNumber.Create(ACounts.Kinds[mKind]));
  mPatterns := TJSONArray.Create;
  Result.AddPair('patterns', mPatterns);
  for mCount in ACounts.Patterns do
    mPatterns.Add(mCount);
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
    Exit;
  mItems := TJSONArray(AArguments.Items[0]);
  for mIndex := 0 to mItems.Count - 1 do
    // TJSONNumber erbt von TJSONString: Zahlen sind keine Muster.
    if (mItems.Items[mIndex] is TJSONString) and not (mItems.Items[mIndex] is TJSONNumber) and
      TStepFilterNames.IsValidPattern(Trim(mItems.Items[mIndex].Value)) then
      Result := Result + [Trim(mItems.Items[mIndex].Value)];
end;

end.
