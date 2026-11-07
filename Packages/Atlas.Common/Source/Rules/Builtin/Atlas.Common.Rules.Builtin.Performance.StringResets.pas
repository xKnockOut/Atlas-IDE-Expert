unit Atlas.Common.Rules.Builtin.Performance.StringResets;

// Für string-concat-in-loop: Setzt eine frühere Anweisung im selben Durchlauf der Schleife den String sicher neu
// (auch über beide Zweige eines if)? Dann wächst er nicht über die Durchläufe.

interface

uses
  Atlas.Common.Pascal.SyntaxTree;

type
  TStringResets = class
  public
    /// <summary>Setzt eine frühere Anweisung im selben Durchlauf der innersten Schleife AName sicher neu, auch über
    /// beide Zweige eines if (mText := '> ' bzw. '  '; mText := mText + Zeile)? Dann wächst der String nicht über die
    /// Durchläufe (Gesamtlauf 07.11.).</summary>
    class function EarlierInPass(ATree: TSyntaxTree; AOffset: Integer; const AName: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils;

/// <summary>Kommt der Bezeichner AName in ANode vor?</summary>
function MentionsName(ANode: TSyntaxNode; const AName: string): Boolean;
var
  mName: string;
begin
  mName := AName;
  Result := ANode.Search(
    function(AVisited: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if (AVisited.Kind = TSyntaxKind.Identifier) and SameText(AVisited.Name, mName) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end) <> nil;
end;

/// <summary>Setzt ANode AName in jedem Fall neu, ohne den alten Wert zu lesen: AName := … ohne AName rechts, ein
/// begin … end mit einer solchen Anweisung oder ein if mit else, das es in beiden Zweigen tut.</summary>
function ResetsAlways(ANode: TSyntaxNode; const AName: string): Boolean;
var
  mIndex: Integer;
begin
  case ANode.Kind of
    TSyntaxKind.AssignStatement:
      Result := (ANode.ChildCount = 2) and (ANode[0].Kind = TSyntaxKind.Identifier) and
        SameText(ANode[0].Name, AName) and not MentionsName(ANode[1], AName);
    TSyntaxKind.Block:
      begin
        Result := False;
        for mIndex := 0 to ANode.ChildCount - 1 do
        begin
          if ResetsAlways(ANode[mIndex], AName) then
          begin
            Exit(True);
          end;
        end;
      end;
    TSyntaxKind.IfStatement:
      Result := (ANode.ChildCount >= 3) and ResetsAlways(ANode[1], AName) and ResetsAlways(ANode[2], AName);
  else
    // Schleifen, case, try und Aufrufe setzen nicht sicher neu.
    Result := False;
  end;
end;

/// <summary>Zuweisung, die an AOffset beginnt; nil ohne.</summary>
function AssignmentAt(ATree: TSyntaxTree; AOffset: Integer): TSyntaxNode;
var
  mOffset: Integer;
begin
  mOffset := AOffset;
  Result := ATree.Root.Search(
    function(AVisited: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if (AVisited.StartOffset > mOffset) or (AVisited.EndOffset < mOffset) then
      begin
        Result := TSyntaxSearchStep.Skip;
      end
      else if (AVisited.Kind = TSyntaxKind.AssignStatement) and (AVisited.StartOffset = mOffset) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end);
end;

{ TStringResets }

class function TStringResets.EarlierInPass(ATree: TSyntaxTree; AOffset: Integer; const AName: string): Boolean;
var
  mChild, mParent: TSyntaxNode;
  mIndex: Integer;
begin
  Result := False;
  mChild := AssignmentAt(ATree, AOffset);
  if mChild = nil then
  begin
    Exit;
  end;
  mParent := mChild.Parent;
  while (mParent <> nil) and not (mParent.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement,
    TSyntaxKind.WhileStatement, TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]) do
  begin
    if mParent.Kind in [TSyntaxKind.Block, TSyntaxKind.RepeatStatement] then
    begin
      mIndex := 0;
      while (mIndex < mParent.ChildCount) and (mParent[mIndex] <> mChild) do
      begin
        if ResetsAlways(mParent[mIndex], AName) then
        begin
          Exit(True);
        end;
        Inc(mIndex);
      end;
    end;
    if mParent.Kind = TSyntaxKind.RepeatStatement then
    begin
      Exit;
    end;
    mChild := mParent;
    mParent := mChild.Parent;
  end;
end;

end.
