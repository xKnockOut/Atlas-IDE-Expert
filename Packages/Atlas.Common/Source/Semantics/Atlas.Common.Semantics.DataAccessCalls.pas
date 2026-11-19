unit Atlas.Common.Semantics.DataAccessCalls;

// Anhalten bei SQL oder HTTP (#870), Teil ohne Index: die Aufrufe
// Empfänger.Methode bzw. Empfänger.Methode(…) einer Unit, deren Methodenname in
// einer Liste steht (Open, ExecSQL, Post …). Ob der Empfänger zu einer
// beobachteten Klasse gehört, entscheidet erst die Namensauflösung
// (Atlas.Common.Lsp.DataAccessSites).
//
// Gezählt werden nur Aufrufe mit Empfänger vor dem Punkt: Aufrufe ohne
// Empfänger (im eigenen Nachfahren oder in with) bleiben außen vor, weil der
// Typ von Self bzw. des with-Objekts dafür nicht sicher feststeht.
// Haltezeile ist die Startzeile der innersten Anweisung um den Aufruf: Dort
// hält der Debugger, bevor die Anweisung den Aufruf ausführt.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  TDataAccessCall = record
    /// <summary>Knoten des Aufrufs: Call bzw. MemberAccess ohne Klammern.</summary>
    Node: TSyntaxNode;
    /// <summary>Ausdruck vor dem Punkt (qryKunde bei qryKunde.ExecSQL).</summary>
    Receiver: TSyntaxNode;
    /// <summary>Name der Methode wie im Quelltext.</summary>
    Method: string;
    Arguments: TArray<TSyntaxNode>;
    /// <summary>Stelle des Methodennamens.</summary>
    Position: TTextPosition;
    /// <summary>Zeile (ab 0) der innersten Anweisung um den Aufruf.</summary>
    BreakLine: Integer;
    /// <summary>Name der umgebenden Routine (TfrmKunde.Speichern); '' außerhalb.</summary>
    Routine: string;
  end;

  TDataAccessCalls = class
  private
    class function Contains(const AMethods: TArray<string>; const AName: string): Boolean; static;
    /// <summary>MemberAccess ohne Klammern, der für sich steht (kein Aufrufziel, kein Empfänger, keine Zuweisung).
    /// </summary>
    class function IsBareCall(ANode: TSyntaxNode): Boolean; static;
    class function CallOf(ANode, ACallee: TSyntaxNode; AWithArguments: Boolean;
      out ACall: TDataAccessCall): Boolean; static;
  public
    /// <summary>Alle Aufrufe in ATree, deren Methodenname in AMethods steht (ohne Groß-/Kleinschreibung), in
    /// Baumreihenfolge.</summary>
    class function Collect(ATree: TSyntaxTree; const AMethods: TArray<string>): TArray<TDataAccessCall>; static;
    /// <summary>Startzeile der innersten Anweisung über ANode; ohne Anweisung die Zeile von ANode.</summary>
    class function StatementLine(ANode: TSyntaxNode): Integer; static;
    /// <summary>Name der innersten Routine über ANode; '' ohne.</summary>
    class function RoutineOf(ANode: TSyntaxNode): string; static;
  end;

implementation

uses
  Atlas.Common.Semantics.StepCalls;

{ TDataAccessCalls }

class function TDataAccessCalls.Contains(const AMethods: TArray<string>; const AName: string): Boolean;
var
  mMethod: string;
begin
  Result := False;
  for mMethod in AMethods do
  begin
    if SameText(mMethod, AName) then
    begin
      Exit(True);
    end;
  end;
end;

class function TDataAccessCalls.IsBareCall(ANode: TSyntaxNode): Boolean;
var
  mParent: TSyntaxNode;
begin
  mParent := ANode.Parent;
  Result := True;
  if mParent = nil then
  begin
    Exit;
  end;
  // Ziel eines Aufrufs mit Klammern, Empfänger eines weiteren Punkts, Ziel einer Zuweisung, @X.Open.
  if (mParent.Kind in [TSyntaxKind.Call, TSyntaxKind.MemberAccess, TSyntaxKind.AssignStatement,
    TSyntaxKind.IndexAccess]) and (mParent.ChildCount > 0) and (mParent[0] = ANode) then
  begin
    Result := False;
  end
  else if mParent.Kind in [TSyntaxKind.AddressOf, TSyntaxKind.GenericArgs] then
  begin
    Result := False;
  end;
end;

class function TDataAccessCalls.CallOf(ANode, ACallee: TSyntaxNode; AWithArguments: Boolean;
  out ACall: TDataAccessCall): Boolean;
var
  mIndex: Integer;
begin
  ACall := Default(TDataAccessCall);
  ACall.Receiver := TStepCalls.ReceiverOf(ACallee);
  Result := (ACall.Receiver <> nil) and TStepCalls.NamePosition(ACallee, ACall.Position);
  if not Result then
  begin
    Exit;
  end;
  ACall.Node := ANode;
  ACall.Method := ACallee.Name;
  if AWithArguments then
  begin
    for mIndex := 1 to ANode.ChildCount - 1 do
    begin
      ACall.Arguments := ACall.Arguments + [ANode[mIndex]];
    end;
  end;
  ACall.BreakLine := StatementLine(ANode);
  ACall.Routine := RoutineOf(ANode);
end;

class function TDataAccessCalls.Collect(ATree: TSyntaxTree; const AMethods: TArray<string>): TArray<TDataAccessCall>;
var
  mNode, mCallee: TSyntaxNode;
  mCall: TDataAccessCall;
begin
  Result := nil;
  if ATree = nil then
  begin
    Exit;
  end;
  for mNode in TSyntaxNode.PreOrder(ATree.Root) do
  begin
    if (mNode.Kind = TSyntaxKind.Call) and (mNode.ChildCount > 0) then
    begin
      mCallee := mNode[0];
      if (mCallee.Kind = TSyntaxKind.MemberAccess) and Contains(AMethods, mCallee.Name) and
        CallOf(mNode, mCallee, True, mCall) then
      begin
        Result := Result + [mCall];
      end;
    end
    else if (mNode.Kind = TSyntaxKind.MemberAccess) and Contains(AMethods, mNode.Name) and IsBareCall(mNode) and
      CallOf(mNode, mNode, False, mCall) then
    begin
      Result := Result + [mCall];
    end;
  end;
end;

class function TDataAccessCalls.StatementLine(ANode: TSyntaxNode): Integer;
var
  mNode: TSyntaxNode;
begin
  Result := ANode.StartPos.Line;
  mNode := ANode;
  while mNode <> nil do
  begin
    if mNode.Kind in TStepCalls.cStatementKinds then
    begin
      Exit(mNode.StartPos.Line);
    end;
    mNode := mNode.Parent;
  end;
end;

class function TDataAccessCalls.RoutineOf(ANode: TSyntaxNode): string;
var
  mNode: TSyntaxNode;
begin
  Result := '';
  mNode := ANode;
  while mNode <> nil do
  begin
    if mNode.Kind = TSyntaxKind.RoutineDecl then
    begin
      Exit(mNode.Name);
    end;
    mNode := mNode.Parent;
  end;
end;

end.
