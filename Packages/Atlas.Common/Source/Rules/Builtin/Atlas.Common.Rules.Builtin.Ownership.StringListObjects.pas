unit Atlas.Common.Rules.Builtin.Ownership.StringListObjects;

// Regel aus Atlas.Common.Rules.Builtin.Ownership ausgelagert (Länge der Unit):
//   stringlist-objects-leak  AddObject/InsertObject mit einem neu erzeugten Objekt (T.Create(…) direkt oder über
//                     eine lokale Variable, die sonst nur gelesen wird) in eine TStringList der Unit ohne
//                     OwnsObjects bzw. in Items einer ListBox oder ComboBox (#1048). Still, wenn eine Routine
//                     Liste.Objects[…] liest und etwas freigibt, die Liste weitergegeben wird oder das Objekt
//                     einen Owner hat. Korrektur: TStringList.Create(True) bzw. OwnsObjects := True.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TStringListObjectsLeakRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Vergleichsschlüssel eines Ausdrucks: Kleinschreibung, ohne Leerraum und führendes Self.
    /// </summary>
    class function KeyOf(const AText: string): string; static;
  end;

/// <summary>Registriert die Regel stringlist-objects-leak.</summary>
procedure RegisterOwnershipStringListObjectsRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.RegularExpressions,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.DeclaredTypes,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Options,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Rules.Builtin.Inheritance,
  Atlas.Common.Rules.Builtin.Ownership;

const
  StringListObjectsLeakRuleId = 'stringlist-objects-leak';

{ TStringListObjectsLeakRule }

type
  /// <summary>Eine TStringList der Unit bzw. die Items einer ListBox oder ComboBox (#1048).</summary>
  TObjectsHost = record
    /// <summary>Ausdruck in Kleinschreibung ohne Self. und Leerraum, z. B. fkunden bzw. lbkunden.items.</summary>
    Key: string;
    /// <summary>Wie im Quelltext, für die Meldung.</summary>
    Text: string;
    /// <summary>Erzeugung X := TStringList.Create(…); nil bei Items eines Steuerelements.</summary>
    Creation: TSyntaxNode;
    Owning: Boolean;
    /// <summary>Gibt die Unit Objects frei oder gibt sie die Liste weiter? Dann schweigt die Regel.</summary>
    Handled: Boolean;
  end;

const
  // Klassen, deren OwnsObjects die Objekte freigibt.
  StringListClasses: array[0..1] of string = ('TStringList', 'THashedStringList');
  // Steuerelemente, deren Items Objekte halten, aber nie freigeben.
  ObjectItemControls: array[0..4] of string = ('TListBox', 'TComboBox', 'TCheckListBox', 'TComboBoxEx',
    'TColorListBox');
  FreeWords: array[0..3] of string = ('Free', 'FreeAndNil', 'DisposeOf', 'Destroy');

function TStringListObjectsLeakRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(StringListObjectsLeakRuleId, TRuleSeverity.Warning,
    'Objekte in einer TStringList ohne Besitz');
end;

class function TStringListObjectsLeakRule.KeyOf(const AText: string): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := 1 to Length(AText) do
  begin
    if not CharInSet(AText[Index], [' ', #9, #10, #13]) then
    begin
      Result := Result + AText[Index];
    end;
  end;
  Result := LowerCase(Result);
  if StartsStr('self.', Result) then
  begin
    Result := Copy(Result, 6, MaxInt);
  end;
end;

type
  /// <summary>Ein Lauf der Regel über eine Unit.</summary>
  TStringListObjectsScan = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FHosts: TArray<TObjectsHost>;
    FAncestry: TAncestry;
    FLines: TArray<string>;
    FLineBreak: string;
    function TextOf(ANode: TSyntaxNode): string;
    function HostIndex(const AKey: string): Integer;
    function StringListCreate(ANode: TSyntaxNode; const AClasses: array of string): TSyntaxNode;
    function CreatedClass(ANode: TSyntaxNode): string;
    procedure AddHost(const AText: string; ACreation: TSyntaxNode);
    procedure CollectHosts(ANode: TSyntaxNode);
    procedure CollectOwning(ANode: TSyntaxNode);
    function ContainsFree(ANode: TSyntaxNode): Boolean;
    procedure MarkReleases(ARoutine, ANode: TSyntaxNode);
    procedure MarkHandled(ANode: TSyntaxNode);
    procedure VisitRoutines(ANode: TSyntaxNode);
    function EnclosingRoutine(ANode: TSyntaxNode): TSyntaxNode;
    function LocalCreatedClass(ARoutine: TSyntaxNode; const AName: string; AAdd: TSyntaxNode): string;
    function ScanLocal(ARoutine: TSyntaxNode; const AName: string; AAdd: TSyntaxNode; out AFound: string): Boolean;
    function ConsiderLocalUse(ANode, AAdd: TSyntaxNode; var AFound: string): Boolean;
    function OwnsFix(const AHost: TObjectsHost; out AFix: TRuleFix): Boolean;
    function OwnsObjectsFix(AStatement: TSyntaxNode; out AFix: TRuleFix): Boolean;
    procedure CheckAdd(ANode: TSyntaxNode);
    function AddedObjectHost(ANode: TSyntaxNode; out AHost: Integer): Boolean;
    function AddedClass(AAdd, AArgument: TSyntaxNode): string;
    procedure CheckAdds(ANode: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    procedure Run;
  end;

/// <summary>X.Create mit einem Typnamen X (auch mit Unit-Präfix).</summary>
function IsCreateAccess(AAccess: TSyntaxNode): Boolean;
begin
  Result := (AAccess.Kind = TSyntaxKind.MemberAccess) and SameText(AAccess.Name, 'Create') and
    (AAccess.ChildCount = 1) and (AAccess[0].Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]);
end;

/// <summary>Die Liste ANode als Argument (FreeObjects(Liste)), auf der rechten Seite einer Zuweisung oder mit @.</summary>
function IsPassedOn(ANode: TSyntaxNode): Boolean;
var
  mParent: TSyntaxNode;
begin
  mParent := ANode.Parent;
  if mParent = nil then
  begin
    Exit(False);
  end;
  case mParent.Kind of
    TSyntaxKind.Call:
      Result := (mParent[0] <> ANode) and not MatchText(mParent.Name, ['FreeAndNil', 'Assigned']);
    TSyntaxKind.AssignStatement:
      Result := mParent[0] <> ANode;
    TSyntaxKind.AddressOf:
      Result := True;
  else
    Result := False;
  end;
end;

/// <summary>Ist AName im var-Abschnitt von ARoutine deklariert?</summary>
function IsLocalVariable(ARoutine: TSyntaxNode; const AName: string): Boolean;
var
  mIndex, mInner: Integer;
  mName: string;
begin
  for mIndex := 0 to ARoutine.ChildCount - 1 do
  begin
    if ARoutine[mIndex].Kind <> TSyntaxKind.VarSection then
    begin
      Continue;
    end;
    for mInner := 0 to ARoutine[mIndex].ChildCount - 1 do
    begin
      for mName in ARoutine[mIndex][mInner].Name.Split([',']) do
      begin
        if SameText(Trim(mName), AName) then
        begin
          Exit(True);
        end;
      end;
    end;
  end;
  Result := False;
end;

/// <summary>Position des Objekt-Arguments: 2 bei AddObject, 3 bei InsertObject, sonst 0.</summary>
// Zuweisung der Form <Liste>.OwnsObjects := <Wert>.
function IsOwnsObjectsAssign(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.AssignStatement) and (ANode.ChildCount = 2) and
    (ANode[0].Kind = TSyntaxKind.MemberAccess) and SameText(ANode[0].Name, 'OwnsObjects') and
    (ANode[0].ChildCount = 1);
end;

function ObjectArgument(ANode: TSyntaxNode): Integer;
begin
  Result := 0;
  if (ANode.Kind <> TSyntaxKind.Call) or (ANode.ChildCount < 1) or (ANode[0].Kind <> TSyntaxKind.MemberAccess) then
  begin
    Exit;
  end;
  if SameText(ANode.Name, 'AddObject') then
  begin
    Result := 2;
  end
  else if SameText(ANode.Name, 'InsertObject') then
  begin
    Result := 3;
  end;
end;

{ TStringListObjectsScan }

constructor TStringListObjectsScan.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
end;

function TStringListObjectsScan.TextOf(ANode: TSyntaxNode): string;
begin
  Result := TRoutineBody.TextOf(FContext.Text, ANode);
end;

function TStringListObjectsScan.HostIndex(const AKey: string): Integer;
begin
  for Result := 0 to High(FHosts) do
  begin
    if FHosts[Result].Key = AKey then
    begin
      Exit;
    end;
  end;
  Result := -1;
end;

// TStringList.Create bzw. TStringList.Create(…) (auch mit Unit-Präfix): der Create-Knoten, sonst nil.
// TStringList.Create bzw. TStringList.Create(…) (auch mit Unit-Präfix): der Create-Knoten, sonst nil.
function TStringListObjectsScan.StringListCreate(ANode: TSyntaxNode; const AClasses: array of string): TSyntaxNode;
var
  mAccess: TSyntaxNode;
begin
  Result := nil;
  mAccess := ANode;
  if (mAccess.Kind = TSyntaxKind.Call) and (mAccess.ChildCount > 0) then
  begin
    mAccess := mAccess[0];
  end;
  if IsCreateAccess(mAccess) and MatchText(mAccess[0].Name, AClasses) then
  begin
    Result := ANode;
  end;
end;

// Erzeugtes Objekt T.Create(…) ohne Owner: Name der Klasse, sonst ''.
// Erzeugtes Objekt T.Create(…) ohne Owner: Name der Klasse, sonst ''.
function TStringListObjectsScan.CreatedClass(ANode: TSyntaxNode): string;
var
  mAccess: TSyntaxNode;
  mName, mFirst: string;
begin
  Result := '';
  mAccess := ANode;
  mFirst := '';
  if (mAccess.Kind = TSyntaxKind.Call) and (mAccess.ChildCount > 0) then
  begin
    if mAccess.ChildCount > 1 then
    begin
      mFirst := TextOf(mAccess[1]);
    end;
    mAccess := mAccess[0];
  end;
  if not IsCreateAccess(mAccess) then
  begin
    Exit;
  end;
  mName := mAccess[0].Name;
  // Komponenten mit Owner gibt der Owner frei (wie create-without-assignment).
  if (mFirst <> '') and not SameText(mFirst, 'nil') and (MatchText(mFirst, ['Self', 'Owner', 'AOwner',
    'Application']) or FAncestry.DescendsFrom(mName, 'TComponent')) then
  begin
    Exit;
  end;
  if TCreateWithoutAssignmentRule.LooksLikeType(mName) then
  begin
    Result := mName;
  end;
end;

procedure TStringListObjectsScan.AddHost(const AText: string; ACreation: TSyntaxNode);
var
  Host: TObjectsHost;
  Index: Integer;
begin
  Host.Key := TStringListObjectsLeakRule.KeyOf(AText);
  Host.Text := AText;
  Host.Creation := ACreation;
  Host.Owning := False;
  Host.Handled := False;
  if ACreation <> nil then
  begin
    // Create(True) besitzt; andere Konstruktoren (QuoteChar, Duplicates) nicht.
    Host.Owning := (ACreation.Kind = TSyntaxKind.Call) and (ACreation.ChildCount = 2) and
      SameText(TextOf(ACreation[1]), 'True');
  end;
  Index := HostIndex(Host.Key);
  if Index < 0 then
  begin
    FHosts := FHosts + [Host];
  end
  else if ACreation <> nil then
  begin
    // Mehrfach erzeugt: besitzend, sobald eine Erzeugung besitzt; die erste bleibt Ziel der Korrektur.
    FHosts[Index].Owning := FHosts[Index].Owning or Host.Owning;
    if FHosts[Index].Creation = nil then
    begin
      FHosts[Index].Creation := ACreation;
    end;
  end;
end;

// Erzeugungen, OwnsObjects := True und Felder vom Typ eines Steuerelements.
procedure TStringListObjectsScan.CollectHosts(ANode: TSyntaxNode);
var
  Pending: TStack<TSyntaxNode>;
  Node: TSyntaxNode;
  Index: Integer;
  Name: string;
begin
  // Iterativ (Bericht M1), Reihenfolge wie die frühere Rekursion.
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ANode);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      if (Node.Kind = TSyntaxKind.AssignStatement) and (Node.ChildCount = 2) and
        (StringListCreate(Node[1], StringListClasses) <> nil) then
      begin
        AddHost(TextOf(Node[0]), Node[1]);
      end;
      if (Node.Kind = TSyntaxKind.Field) and (Node.ChildCount > 0) and
        (Node[0].Kind = TSyntaxKind.TypeReference) and MatchText(Node[0].Name, ObjectItemControls) then
      begin
        for Name in Node.Name.Split([',']) do
        begin
          AddHost(Trim(Name) + '.Items', nil);
        end;
      end;
      for Index := Node.ChildCount - 1 downto 0 do
      begin
        Pending.Push(Node[Index]);
      end;
    end;
  finally
    Pending.Free;
  end;
end;

procedure TStringListObjectsScan.CollectOwning(ANode: TSyntaxNode);
var
  Pending: TStack<TSyntaxNode>;
  Node: TSyntaxNode;
  Index, Host: Integer;
begin
  // Iterativ (Bericht M1).
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ANode);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      if IsOwnsObjectsAssign(Node) and SameText(TextOf(Node[1]), 'True') then
      begin
        Host := HostIndex(TStringListObjectsLeakRule.KeyOf(TextOf(Node[0][0])));
        if Host >= 0 then
        begin
          FHosts[Host].Owning := True;
        end;
      end;
      for Index := Node.ChildCount - 1 downto 0 do
      begin
        Pending.Push(Node[Index]);
      end;
    end;
  finally
    Pending.Free;
  end;
end;

function TStringListObjectsScan.ContainsFree(ANode: TSyntaxNode): Boolean;
var
  Pending: TStack<TSyntaxNode>;
  Node: TSyntaxNode;
  Index: Integer;
begin
  // Iterativ (Bericht M1).
  Result := False;
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ANode);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      if (Node.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.Call]) and
        MatchText(Node.Name, FreeWords) then
      begin
        Exit(True);
      end;
      for Index := Node.ChildCount - 1 downto 0 do
      begin
        Pending.Push(Node[Index]);
      end;
    end;
  finally
    Pending.Free;
  end;
end;

// Liest die Routine X.Objects[…] und gibt sie etwas frei, gilt die Freigabe als erledigt.
// Liest die Routine X.Objects[…] und gibt sie etwas frei, gilt die Freigabe als erledigt.
procedure TStringListObjectsScan.MarkReleases(ARoutine, ANode: TSyntaxNode);
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  // Iterativ (Bericht M1).
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ANode);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if (mNode.Kind = TSyntaxKind.MemberAccess) and SameText(mNode.Name, 'Objects') and (mNode.ChildCount = 1) and
        ContainsFree(ARoutine) then
      begin
        MarkHandled(mNode[0]);
      end;
      // Die Liste als Argument (FreeObjects(Liste)) oder auf der rechten Seite einer Zuweisung: weitergegeben.
      if (mNode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and IsPassedOn(mNode) then
      begin
        MarkHandled(mNode);
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

procedure TStringListObjectsScan.MarkHandled(ANode: TSyntaxNode);
var
  mHost: Integer;
begin
  mHost := HostIndex(TStringListObjectsLeakRule.KeyOf(TextOf(ANode)));
  if mHost >= 0 then
  begin
    FHosts[mHost].Handled := True;
  end;
end;

procedure TStringListObjectsScan.VisitRoutines(ANode: TSyntaxNode);
var
  Pending: TStack<TSyntaxNode>;
  Node: TSyntaxNode;
  Index: Integer;
begin
  // Iterativ (Bericht M1).
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ANode);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      if Node.Kind = TSyntaxKind.RoutineDecl then
      begin
        MarkReleases(Node, Node);
      end;
      for Index := Node.ChildCount - 1 downto 0 do
      begin
        Pending.Push(Node[Index]);
      end;
    end;
  finally
    Pending.Free;
  end;
end;

function TStringListObjectsScan.EnclosingRoutine(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode.Parent;
  while (Result <> nil) and (Result.Kind <> TSyntaxKind.RoutineDecl) do
  begin
    Result := Result.Parent;
  end;
end;

// Lokale Variable AName, in der Routine aus T.Create(…) erzeugt und sonst nur gelesen (V.Name) oder an
// AddObject übergeben: Name der Klasse, sonst ''.
// Lokale Variable AName, in der Routine aus T.Create(…) erzeugt und sonst nur gelesen (V.Name) oder an
// AddObject übergeben: Name der Klasse, sonst ''.
function TStringListObjectsScan.LocalCreatedClass(ARoutine: TSyntaxNode; const AName: string;
  AAdd: TSyntaxNode): string;
var
  mFound: string;
begin
  Result := '';
  if IsLocalVariable(ARoutine, AName) and ScanLocal(ARoutine, AName, AAdd, mFound) then
  begin
    Result := mFound;
  end;
end;

/// <summary>Erste Erzeugung der Variablen AName in AFound; False, wenn sie außer V.Name und dem AddObject-Argument
/// AAdd anders vorkommt (weitergegeben oder freigegeben).</summary>
function TStringListObjectsScan.ScanLocal(ARoutine: TSyntaxNode; const AName: string; AAdd: TSyntaxNode;
  out AFound: string): Boolean;
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  // Iterativ (Bericht M1), Reihenfolge wie die frühere Rekursion (die erste Erzeugung zählt).
  Result := True;
  AFound := '';
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ARoutine);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if (mNode.Kind = TSyntaxKind.Identifier) and SameText(mNode.Name, AName) and (mNode.Parent <> nil) then
      begin
        Result := Result and ConsiderLocalUse(mNode, AAdd, AFound);
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

/// <summary>Ein Vorkommen ANode der lokalen Variablen: Erzeugung (merkt die Klasse) oder V.Name bzw. das
/// AddObject-Argument (True); sonst False.</summary>
function TStringListObjectsScan.ConsiderLocalUse(ANode, AAdd: TSyntaxNode; var AFound: string): Boolean;
var
  mParent: TSyntaxNode;
begin
  mParent := ANode.Parent;
  Result := True;
  if (mParent.Kind = TSyntaxKind.AssignStatement) and (mParent[0] = ANode) and (mParent.ChildCount = 2) and
    (CreatedClass(mParent[1]) <> '') then
  begin
    if AFound = '' then
    begin
      AFound := CreatedClass(mParent[1]);
    end;
  end
  // V.Name liest nur; alles andere außer dem AddObject-Argument gibt V weiter oder frei.
  else if not ((mParent.Kind = TSyntaxKind.MemberAccess) and (mParent[0] = ANode) and
    not MatchText(mParent.Name, FreeWords)) and (mParent <> AAdd) then
  begin
    Result := False;
  end;
end;

function TStringListObjectsScan.OwnsFix(const AHost: TObjectsHost; out AFix: TRuleFix): Boolean;
var
  mCreation, mAccess: TSyntaxNode;
  mClassText: string;
begin
  mCreation := AHost.Creation;
  if mCreation = nil then
  begin
    Exit(False);
  end;
  mAccess := mCreation;
  if mCreation.Kind = TSyntaxKind.Call then
  begin
    mAccess := mCreation[0];
  end;
  mClassText := TextOf(mAccess[0]);
  Result := True;
  if (mCreation.Kind = TSyntaxKind.MemberAccess) or (mCreation.ChildCount = 1) then
  begin
    // TStringList.Create bzw. TStringList.Create() → TStringList.Create(True)
    AFix := TRuleFix.Create(Format('%s.Create(True) setzen', [mClassText]),
      [TTextEdit.Create(TTextRange.Create(mCreation.StartPos, mCreation.EndPos), mClassText + '.Create(True)')]);
  end
  else if (mCreation.ChildCount = 2) and SameText(TextOf(mCreation[1]), 'False') then
  begin
    AFix := TRuleFix.Create(Format('%s.Create(True) setzen', [mClassText]),
      [TTextEdit.Create(TTextRange.Create(mCreation[1].StartPos, mCreation[1].EndPos), 'True')]);
  end
  else
  begin
    Result := OwnsObjectsFix(mCreation.Parent, AFix);
  end;
end;

/// <summary>Andere Konstruktoren: OwnsObjects := True in die Zeile nach der Erzeugung AStatement; die Zeile muss mit
/// der Anweisung enden.</summary>
function TStringListObjectsScan.OwnsObjectsFix(AStatement: TSyntaxNode; out AFix: TRuleFix): Boolean;
begin
  Result := (AStatement <> nil) and (AStatement.Kind = TSyntaxKind.AssignStatement) and
    (AStatement.StartPos.Line = AStatement.EndPos.Line) and (AStatement.EndPos.Line <= High(FLines));
  Result := Result and (Trim(Copy(FLines[AStatement.EndPos.Line], AStatement.EndPos.Character + 1, MaxInt)) = ';');
  if Result then
  begin
    AFix := TRuleFix.Create('OwnsObjects := True setzen',
      [TTextEdit.Create(TTextRange.Create(AStatement.EndPos.Line + 1, 0, AStatement.EndPos.Line + 1, 0),
      Copy(FLines[AStatement.StartPos.Line], 1, AStatement.StartPos.Character) + TextOf(AStatement[0]) +
      '.OwnsObjects := True;' + FLineBreak)]);
  end;
end;

procedure TStringListObjectsScan.CheckAdd(ANode: TSyntaxNode);
var
  mHost: Integer;
  mClassName: string;
  mFix: TRuleFix;
  mFixes: TArray<TRuleFix>;
begin
  if not AddedObjectHost(ANode, mHost) then
  begin
    Exit;
  end;
  mClassName := AddedClass(ANode, ANode[ANode.ChildCount - 1]);
  if mClassName = '' then
  begin
    Exit;
  end;
  mFixes := nil;
  if OwnsFix(FHosts[mHost], mFix) then
  begin
    mFixes := [mFix];
  end;
  FReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos),
    Format('%s besitzt die Objekte nicht; die %s-Objekte werden nie freigegeben.',
    [TextOf(ANode[0][0]), mClassName]), TRuleConfidence.Medium, mFixes);
end;

/// <summary>X.AddObject(S, O) bzw. X.InsertObject(I, S, O) an einer Liste der Unit, die weder besitzt noch ihre
/// Objekte selbst freigibt: Index der Liste in AHost.</summary>
function TStringListObjectsScan.AddedObjectHost(ANode: TSyntaxNode; out AHost: Integer): Boolean;
var
  mObjectArg: Integer;
begin
  AHost := -1;
  mObjectArg := ObjectArgument(ANode);
  if (mObjectArg > 0) and (ANode.ChildCount = mObjectArg + 1) and (ANode[0].ChildCount = 1) then
  begin
    AHost := HostIndex(TStringListObjectsLeakRule.KeyOf(TextOf(ANode[0][0])));
  end;
  Result := (AHost >= 0) and not FHosts[AHost].Owning and not FHosts[AHost].Handled;
end;

/// <summary>Klasse des übergebenen Objekts: direkt T.Create(…) oder eine lokale Variable daraus; sonst ''.</summary>
function TStringListObjectsScan.AddedClass(AAdd, AArgument: TSyntaxNode): string;
var
  mRoutine: TSyntaxNode;
begin
  Result := CreatedClass(AArgument);
  if (Result = '') and (AArgument.Kind = TSyntaxKind.Identifier) then
  begin
    mRoutine := EnclosingRoutine(AAdd);
    if mRoutine <> nil then
    begin
      Result := LocalCreatedClass(mRoutine, AArgument.Name, AAdd);
    end;
  end;
end;

// Prüft jeden Knoten nach seinen Kindern (Nachordnung) mit CheckAdd.
procedure TStringListObjectsScan.CheckAdds(ANode: TSyntaxNode);
var
  Pending: TStack<TSyntaxPostOrderEntry>;
  Entry: TSyntaxPostOrderEntry;
  Index: Integer;
begin
  // Iterativ (Bericht M1): Done = die Kinder sind schon geprüft.
  Pending := TStack<TSyntaxPostOrderEntry>.Create;
  try
    Pending.Push(TSyntaxPostOrderEntry.Create(ANode, False));
    while Pending.Count > 0 do
    begin
      Entry := Pending.Pop;
      if Entry.Done then
      begin
        CheckAdd(Entry.Node);
        Continue;
      end;
      Pending.Push(TSyntaxPostOrderEntry.Create(Entry.Node, True));
      for Index := Entry.Node.ChildCount - 1 downto 0 do
      begin
        Pending.Push(TSyntaxPostOrderEntry.Create(Entry.Node[Index], False));
      end;
    end;
  finally
    Pending.Free;
  end;
end;

procedure TStringListObjectsScan.Run;
begin
  if (FContext.Tree = nil) or (FContext.Tree.Root = nil) or not (ContainsText(FContext.Text, 'AddObject') or
    ContainsText(FContext.Text, 'InsertObject')) then
  begin
    Exit;
  end;
  FLines := TTextLines.SplitLines(FContext.Text, FLineBreak);
  FHosts := nil;
  CollectHosts(FContext.Tree.Root);
  if FHosts = nil then
  begin
    Exit;
  end;
  CollectOwning(FContext.Tree.Root);
  VisitRoutines(FContext.Tree.Root);
  FAncestry := TAncestry.Create(FContext.Index, TRuleDerived.UnitIndex(TRuleDerived.Open(FContext), FContext));
  try
    CheckAdds(FContext.Tree.Root);
  finally
    FAncestry.Free;
  end;
end;

{ TStringListObjectsLeakRule }

procedure TStringListObjectsLeakRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mWorker: TStringListObjectsScan;
begin
  mWorker := TStringListObjectsScan.Create(AContext, AReport);
  try
    mWorker.Run;
  finally
    mWorker.Free;
  end;
end;

procedure RegisterOwnershipStringListObjectsRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TStringListObjectsLeakRule.Create);
end;

end.
