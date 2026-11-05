unit Atlas.Common.Semantics.ControlFlow.Statements;

// Was der Kontrollfluss (Semantics.ControlFlow) an den Knoten einer Anweisung abliest: ob ein Knoten eine
// Anweisung ist, ob eine Schleife eine konstante Bedingung hat (while True, until False, #1109) und ob eine
// for-Schleife sicher einmal läuft (for I := 0 to 64), wie Delphi es für W1035 wertet.

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
    /// <summary>Grenzen der for-Schleife AFor als ganze Zahlen, wenn beide Zahlenliterale sind (auch $, %, &amp;).
    /// </summary>
    class function LiteralBounds(AFor: TSyntaxNode; out AFrom, ATo: Int64): Boolean; static;
    /// <summary>Läuft die for-Schleife AFor sicher mindestens einmal? Nur bei Zahlenliteralen als Grenzen;
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
      Result := (mChild.Kind = TSyntaxKind.Literal) and TOrdinalConstants.TryNumber(mChild.Name, mBounds[mFound]);
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
