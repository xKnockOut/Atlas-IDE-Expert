unit Atlas.Common.Pascal.SyntaxNodes;

// Kleine Abfragen am Syntaxbaum, die Prüfregeln, Editierbefehle und LSP-Funktionen gemeinsam brauchen: Name einer
// Punktkette, Klammern um einen Ausdruck, umgebende Routine oder Anweisung, Kind an einem Offset, Direktiven eines
// Kopfs. Regeln bringen keine eigenen Kopien dieser Helfer mit (atlas-duplicates.json). Alle Läufe sind iterativ;
// nil als Knoten ist überall erlaubt, wo es dokumentiert ist.

interface

uses
  Atlas.Common.Pascal.SyntaxTree;

type
  TSyntaxNodes = class
  public
    /// <summary>Name einer Bezeichner- bzw. Punktkette ("A.B.C"); '' bei anderen Ausdrücken.</summary>
    class function DottedName(ANode: TSyntaxNode): string; static;
    /// <summary>Ist ANode ein Bezeichner oder eine Punktkette, die mit einem Bezeichner beginnt?</summary>
    class function IsNameChain(ANode: TSyntaxNode): Boolean; static;
    /// <summary>ANode ohne umschließende Klammern ((X) → X, auch mehrfach); nil bleibt nil.</summary>
    class function Unparen(ANode: TSyntaxNode): TSyntaxNode; static;
    /// <summary>Äußerste Klammer, in der ANode allein steht ((X) für X); ohne Klammer ANode selbst.</summary>
    class function OuterParens(ANode: TSyntaxNode): TSyntaxNode; static;
    /// <summary>Nächster Vorfahr von ANode (ANode selbst ausgeschlossen) einer der Arten AKinds; nil ohne oder wenn
    /// der Weg nach oben vorher AStop erreicht.</summary>
    class function Enclosing(ANode: TSyntaxNode; const AKinds: TSyntaxKinds;
      AStop: TSyntaxNode = nil): TSyntaxNode; static;
    /// <summary>Wie Enclosing, aber ANode selbst eingeschlossen; nil ohne ANode.</summary>
    class function Nearest(ANode: TSyntaxNode; const AKinds: TSyntaxKinds): TSyntaxNode; static;
    /// <summary>Erstes Kind von ANode, dessen Bereich AOffset enthält (Anfang und Ende eingeschlossen); nil ohne.
    /// </summary>
    class function ChildAt(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode; static;
    /// <summary>Innerster Knoten unter ANode, dessen Bereich AOffset enthält (Ende ausgeschlossen); ANode selbst,
    /// wenn kein Kind passt.</summary>
    class function DeepestAt(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode; static;
    /// <summary>Stelle von AChild unter den Kindern von AParent; -1 ohne.</summary>
    class function IndexOf(AParent, AChild: TSyntaxNode): Integer; static;
    /// <summary>Gibt es unter ANode (samt ANode) einen Knoten der Art AKind?</summary>
    class function ContainsKind(ANode: TSyntaxNode; AKind: TSyntaxKind): Boolean; static;
    /// <summary>Kommt unter ANode (samt ANode) ein Bezeichner AName vor (ohne Groß-/Kleinschreibung)?</summary>
    class function Mentions(ANode: TSyntaxNode; const AName: string): Boolean; static;
    /// <summary>Hat der Routinenkopf AHeader eine der Direktiven ANames (ohne Groß-/Kleinschreibung)? False ohne
    /// AHeader.</summary>
    class function HasDirective(AHeader: TSyntaxNode; const ANames: array of string): Boolean; static;
    /// <summary>Anfang des Zugriffs, in dem ANode links steht: bei A in A.B[1]^ der ganze Ausdruck.</summary>
    class function AccessRoot(ANode: TSyntaxNode): TSyntaxNode; static;
    /// <summary>Name bei einem Bezeichner X oder bei Self.X, sonst ''; '' ohne ANode.</summary>
    class function FieldName(ANode: TSyntaxNode): string; static;
    /// <summary>Hat ABlock nur leere Anweisungen (oder gar keine)?</summary>
    class function OnlyEmptyStatements(ABlock: TSyntaxNode): Boolean; static;
    /// <summary>Erstes Kind von ANode, das keine der Arten AKinds hat (etwa der Typ hinter GenericParams); nil ohne.
    /// </summary>
    class function FirstChildExcept(ANode: TSyntaxNode; const AKinds: TSyntaxKinds): TSyntaxNode; static;
    /// <summary>Name von ARoutine samt der Routinen, in denen sie verschachtelt ist ("Aussen.Innen").</summary>
    class function RoutinePath(ARoutine: TSyntaxNode): string; static;
    /// <summary>Alle Knoten der Art AKind unter ARoot (samt ARoot) in der Reihenfolge von TSyntaxNode.Walk.</summary>
    class function OfKind(ARoot: TSyntaxNode; AKind: TSyntaxKind): TArray<TSyntaxNode>; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils;

{ TSyntaxNodes }

class function TSyntaxNodes.DottedName(ANode: TSyntaxNode): string;
var
  mSuffix: string;
begin
  mSuffix := '';
  while (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount = 1) do
  begin
    mSuffix := '.' + ANode.Name + mSuffix;
    ANode := ANode[0];
  end;
  Result := '';
  if ANode.Kind = TSyntaxKind.Identifier then
  begin
    Result := ANode.Name + mSuffix;
  end;
end;

class function TSyntaxNodes.IsNameChain(ANode: TSyntaxNode): Boolean;
begin
  while (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount = 1) do
  begin
    ANode := ANode[0];
  end;
  Result := ANode.Kind = TSyntaxKind.Identifier;
end;

class function TSyntaxNodes.Unparen(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode;
  while (Result <> nil) and (Result.Kind = TSyntaxKind.ParenExpr) and (Result.ChildCount = 1) do
  begin
    Result := Result[0];
  end;
end;

class function TSyntaxNodes.OuterParens(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode;
  while (Result.Parent <> nil) and (Result.Parent.Kind = TSyntaxKind.ParenExpr) and
    (Result.Parent.ChildCount = 1) do
  begin
    Result := Result.Parent;
  end;
end;

class function TSyntaxNodes.Enclosing(ANode: TSyntaxNode; const AKinds: TSyntaxKinds;
  AStop: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode.Parent;
  while (Result <> nil) and (Result <> AStop) and not (Result.Kind in AKinds) do
  begin
    Result := Result.Parent;
  end;
  if Result = AStop then
  begin
    Result := nil;
  end;
end;

class function TSyntaxNodes.Nearest(ANode: TSyntaxNode; const AKinds: TSyntaxKinds): TSyntaxNode;
begin
  Result := ANode;
  while (Result <> nil) and not (Result.Kind in AKinds) do
  begin
    Result := Result.Parent;
  end;
end;

class function TSyntaxNodes.ChildAt(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode;
var
  mIndex: Integer;
begin
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    if (ANode[mIndex].StartOffset <= AOffset) and (AOffset <= ANode[mIndex].EndOffset) then
    begin
      Exit(ANode[mIndex]);
    end;
  end;
  Result := nil;
end;

class function TSyntaxNodes.DeepestAt(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode;
var
  mIndex: Integer;
  mFound: Boolean;
begin
  Result := ANode;
  repeat
    mFound := False;
    for mIndex := 0 to Result.ChildCount - 1 do
    begin
      if (AOffset >= Result[mIndex].StartOffset) and (AOffset < Result[mIndex].EndOffset) then
      begin
        Result := Result[mIndex];
        mFound := True;
        Break;
      end;
    end;
  until not mFound;
end;

class function TSyntaxNodes.IndexOf(AParent, AChild: TSyntaxNode): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to AParent.ChildCount - 1 do
  begin
    if AParent[mIndex] = AChild then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

class function TSyntaxNodes.ContainsKind(ANode: TSyntaxNode; AKind: TSyntaxKind): Boolean;
var
  mNode: TSyntaxNode;
begin
  for mNode in TSyntaxNode.PreOrder(ANode) do
  begin
    if mNode.Kind = AKind then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TSyntaxNodes.Mentions(ANode: TSyntaxNode; const AName: string): Boolean;
var
  mNode: TSyntaxNode;
begin
  for mNode in TSyntaxNode.PreOrder(ANode) do
  begin
    if (mNode.Kind = TSyntaxKind.Identifier) and SameText(mNode.Name, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TSyntaxNodes.HasDirective(AHeader: TSyntaxNode; const ANames: array of string): Boolean;
var
  mIndex: Integer;
begin
  if AHeader <> nil then
  begin
    for mIndex := 0 to AHeader.ChildCount - 1 do
    begin
      if (AHeader[mIndex].Kind = TSyntaxKind.Directive) and MatchText(AHeader[mIndex].Name, ANames) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

class function TSyntaxNodes.AccessRoot(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode;
  while (Result.Parent <> nil) and (Result.Parent.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess,
    TSyntaxKind.Dereference]) and (Result.Parent[0] = Result) do
  begin
    Result := Result.Parent;
  end;
end;

class function TSyntaxNodes.FieldName(ANode: TSyntaxNode): string;
begin
  Result := '';
  if ANode = nil then
  begin
    Exit;
  end;
  if ANode.Kind = TSyntaxKind.Identifier then
  begin
    Result := ANode.Name;
  end
  else if (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount = 1) and
    (ANode[0].Kind = TSyntaxKind.Identifier) and SameText(ANode[0].Name, 'Self') then
  begin
    Result := ANode.Name;
  end;
end;

class function TSyntaxNodes.OnlyEmptyStatements(ABlock: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := 0 to ABlock.ChildCount - 1 do
  begin
    if ABlock[mIndex].Kind <> TSyntaxKind.EmptyStatement then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

class function TSyntaxNodes.FirstChildExcept(ANode: TSyntaxNode; const AKinds: TSyntaxKinds): TSyntaxNode;
var
  mIndex: Integer;
begin
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    if not (ANode[mIndex].Kind in AKinds) then
    begin
      Exit(ANode[mIndex]);
    end;
  end;
  Result := nil;
end;

class function TSyntaxNodes.RoutinePath(ARoutine: TSyntaxNode): string;
var
  mParent: TSyntaxNode;
begin
  Result := ARoutine.Name;
  mParent := Enclosing(ARoutine, [TSyntaxKind.RoutineDecl]);
  while mParent <> nil do
  begin
    Result := mParent.Name + '.' + Result;
    mParent := Enclosing(mParent, [TSyntaxKind.RoutineDecl]);
  end;
end;

class function TSyntaxNodes.OfKind(ARoot: TSyntaxNode; AKind: TSyntaxKind): TArray<TSyntaxNode>;
var
  mNode: TSyntaxNode;
  mCount: Integer;
begin
  Result := nil;
  mCount := 0;
  for mNode in TSyntaxNode.PreOrder(ARoot) do
  begin
    if mNode.Kind = AKind then
    begin
      if mCount = Length(Result) then
      begin
        SetLength(Result, 2 * mCount + 8);
      end;
      Result[mCount] := mNode;
      Inc(mCount);
    end;
  end;
  SetLength(Result, mCount);
end;

end.
