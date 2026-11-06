unit Atlas.Common.Semantics.ControlFlow.Statements;

// Was der Kontrollfluss (Semantics.ControlFlow) an den Knoten einer Anweisung abliest: ob ein Knoten eine
// Anweisung ist, ob eine Schleife eine konstante Bedingung hat (while True, until False, #1109) und ob eine
// for-Schleife sicher einmal läuft (for I := 0 to 64, auch for I := 1 to cVersuche mit cVersuche = 3 in
// derselben Unit), wie Delphi es für W1035 wertet.

interface

uses
  Atlas.Common.Pascal.SyntaxTree;

type
  TFlowStatements = class abstract
  public
    /// <summary>Ist ein Knoten der Art AKind eine Anweisung (und kein Ausdruck)?</summary>
    class function IsStatement(AKind: TSyntaxKind): Boolean; static;
    /// <summary>Ist die Bedingung der Schleife S die Konstante AValue (while True, until False; auch in
    /// Klammern)? Dann verlässt nur Break, Exit oder raise die Schleife (#1109).</summary>
    class function ConstantCondition(S: TSyntaxNode; const AValue: string): Boolean; static;
    /// <summary>Grenzen der for-Schleife AFor als ganze Zahlen, wenn beide Zahlenliterale (auch $, %, &amp;) oder
    /// Namen echter Konstanten der Unit mit einem Zahlenliteral als Wert sind (siehe ConstantBound).</summary>
    class function LiteralBounds(AFor: TSyntaxNode; out AFrom, ATo: Int64): Boolean; static;
    /// <summary>Wert der Grenze ABound: Zahlenliteral oder Name einer Konstanten ohne Typ (cVersuche = 3), die
    /// im Baum genau einmal deklariert ist und deren Name sonst nirgends deklariert wird (Variable, Parameter,
    /// Feld, Routine, Typ, Inline-Variable). Delphi kennt solche Werte beim Übersetzen und warnt dann nicht.
    /// </summary>
    class function ConstantBound(ABound: TSyntaxNode; out AValue: Int64): Boolean; static;
    /// <summary>Läuft die for-Schleife AFor sicher mindestens einmal? Nur bei bekannten Grenzen (LiteralBounds);
    /// to braucht AFrom &lt;= ATo, downto AFrom &gt;= ATo. False für andere Knoten.</summary>
    class function RunsAtLeastOnce(AFor: TSyntaxNode): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Semantics.OrdinalConstants;

class function TFlowStatements.IsStatement(AKind: TSyntaxKind): Boolean;
begin
  case AKind of
    TSyntaxKind.Block, TSyntaxKind.AsmBlock, TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement,
    TSyntaxKind.IfStatement, TSyntaxKind.CaseStatement, TSyntaxKind.ForStatement,
    TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement,
    TSyntaxKind.WithStatement, TSyntaxKind.TryStatement, TSyntaxKind.RaiseStatement,
    TSyntaxKind.GotoStatement, TSyntaxKind.LabeledStatement, TSyntaxKind.InlineVar,
    TSyntaxKind.InlineConst, TSyntaxKind.EmptyStatement, TSyntaxKind.Error:
      Result := True;
  else
    Result := False;
  end;
end;

class function TFlowStatements.ConstantCondition(S: TSyntaxNode; const AValue: string): Boolean;
var
  mIndex: Integer;
  mCondition: TSyntaxNode;
begin
  Result := False;
  for mIndex := 0 to S.ChildCount - 1 do
  begin
    if not IsStatement(S.Children[mIndex].Kind) then
    begin
      mCondition := S.Children[mIndex];
      while (mCondition.Kind = TSyntaxKind.ParenExpr) and (mCondition.ChildCount = 1) do
      begin
        mCondition := mCondition.Children[0];
      end;
      Exit((mCondition.Kind in [TSyntaxKind.Identifier, TSyntaxKind.Literal]) and SameText(mCondition.Name, AValue));
    end;
  end;
end;

class function TFlowStatements.LiteralBounds(AFor: TSyntaxNode; out AFrom, ATo: Int64): Boolean;
var
  mIndex, mFound: Integer;
  mBounds: array[0..1] of Int64;
  mChild: TSyntaxNode;
begin
  mFound := 0;
  mIndex := 0;
  Result := True;
  // Kinder: optional der Typ (for var I: Integer), dann Anfang, Ende und der Rumpf.
  while Result and (mFound < 2) and (mIndex < AFor.ChildCount) do
  begin
    mChild := AFor.Children[mIndex];
    if mChild.Kind <> TSyntaxKind.TypeReference then
    begin
      Result := ConstantBound(mChild, mBounds[mFound]);
      Inc(mFound);
    end;
    Inc(mIndex);
  end;
  Result := Result and (mFound = 2);
  AFrom := 0;
  ATo := 0;
  if Result then
  begin
    AFrom := mBounds[0];
    ATo := mBounds[1];
  end;
end;

/// <summary>Oberster Knoten über ANode.</summary>
function RootOf(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode;
  while Result.Parent <> nil do
  begin
    Result := Result.Parent;
  end;
end;

/// <summary>Deklariert ANode den Namen AName (auch in Listen "A,B" von Variablen und Parametern)?</summary>
function DeclaresName(ANode: TSyntaxNode; const AName: string): Boolean;
var
  mName: string;
begin
  Result := False;
  if not (ANode.Kind in [TSyntaxKind.ConstDecl, TSyntaxKind.VarDecl, TSyntaxKind.Parameter, TSyntaxKind.Field,
    TSyntaxKind.TypeDecl, TSyntaxKind.RoutineDecl, TSyntaxKind.RoutineHeader, TSyntaxKind.PropertyDecl,
    TSyntaxKind.InlineVar, TSyntaxKind.InlineConst, TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement]) then
  begin
    Exit;
  end;
  for mName in ANode.Name.Split([',']) do
  begin
    if SameText(Trim(mName), AName) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Die einzige Deklaration von AName im Baum unter ARoot, wenn sie eine Konstante ist; sonst nil.
/// </summary>
function SoleConstant(ARoot: TSyntaxNode; const AName: string): TSyntaxNode;
var
  mFound: TSyntaxNode;
  mCount: Integer;
begin
  mFound := nil;
  mCount := 0;
  ARoot.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if DeclaresName(ANode, AName) then
      begin
        Inc(mCount);
        mFound := ANode;
      end;
      Result := mCount < 2;
    end);
  Result := nil;
  if (mCount = 1) and (mFound.Kind = TSyntaxKind.ConstDecl) then
  begin
    Result := mFound;
  end;
end;

class function TFlowStatements.ConstantBound(ABound: TSyntaxNode; out AValue: Int64): Boolean;
var
  mDeclaration: TSyntaxNode;
begin
  AValue := 0;
  if ABound.Kind = TSyntaxKind.Literal then
  begin
    Exit(TOrdinalConstants.TryNumber(ABound.Name, AValue));
  end;
  if ABound.Kind <> TSyntaxKind.Identifier then
  begin
    Exit(False);
  end;
  mDeclaration := SoleConstant(RootOf(ABound), ABound.Name);
  // Nur "Name = Zahl": Typisierte Konstanten (Name: Integer = 3) sind für Delphi Variablen.
  Result := (mDeclaration <> nil) and (mDeclaration.ChildCount = 1) and
    (mDeclaration.Children[0].Kind = TSyntaxKind.Literal) and
    TOrdinalConstants.TryNumber(mDeclaration.Children[0].Name, AValue);
end;

class function TFlowStatements.RunsAtLeastOnce(AFor: TSyntaxNode): Boolean;
var
  mFrom, mTo: Int64;
begin
  Result := (AFor.Kind = TSyntaxKind.ForStatement) and LiteralBounds(AFor, mFrom, mTo);
  if Result then
  begin
    if AFor.Descending then
    begin
      Result := mFrom >= mTo;
    end
    else
    begin
      Result := mFrom <= mTo;
    end;
  end;
end;

end.
