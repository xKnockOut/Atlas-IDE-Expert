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

procedure TStringListObjectsLeakRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Hosts: TArray<TObjectsHost>;
  Ancestry: TAncestry;
  Lines: TArray<string>;
  LineBreak: string;

  function TextOf(ANode: TSyntaxNode): string;
  begin
    Result := TRoutineBody.TextOf(AContext.Text, ANode);
  end;

  function HostIndex(const AKey: string): Integer;
  begin
    for Result := 0 to High(Hosts) do
    begin
      if Hosts[Result].Key = AKey then
      begin
        Exit;
      end;
    end;
    Result := -1;
  end;

  // TStringList.Create bzw. TStringList.Create(…) (auch mit Unit-Präfix): der Create-Knoten, sonst nil.
  function StringListCreate(ANode: TSyntaxNode; const AClasses: array of string): TSyntaxNode;
  var
    Access: TSyntaxNode;
  begin
    Result := nil;
    Access := ANode;
    if (Access.Kind = TSyntaxKind.Call) and (Access.ChildCount > 0) then
    begin
      Access := Access[0];
    end;
    if (Access.Kind = TSyntaxKind.MemberAccess) and SameText(Access.Name, 'Create') and (Access.ChildCount = 1) and
      (Access[0].Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and MatchText(Access[0].Name, AClasses)
      then
    begin
      Result := ANode;
    end;
  end;

  // Erzeugtes Objekt T.Create(…) ohne Owner: Name der Klasse, sonst ''.
  function CreatedClass(ANode: TSyntaxNode): string;
  var
    Access: TSyntaxNode;
    Name, First: string;
  begin
    Result := '';
    Access := ANode;
    First := '';
    if (Access.Kind = TSyntaxKind.Call) and (Access.ChildCount > 0) then
    begin
      if Access.ChildCount > 1 then
      begin
        First := TextOf(Access[1]);
      end;
      Access := Access[0];
    end;
    if (Access.Kind <> TSyntaxKind.MemberAccess) or not SameText(Access.Name, 'Create') or (Access.ChildCount <> 1) or
      not (Access[0].Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) then
    begin
      Exit;
    end;
    Name := Access[0].Name;
    // Komponenten mit Owner gibt der Owner frei (wie create-without-assignment).
    if (First <> '') and not SameText(First, 'nil') and (MatchText(First, ['Self', 'Owner', 'AOwner',
      'Application']) or Ancestry.DescendsFrom(Name, 'TComponent')) then
    begin
      Exit;
    end;
    if TCreateWithoutAssignmentRule.LooksLikeType(Name) then
    begin
      Result := Name;
    end;
  end;

  procedure AddHost(const AText: string; ACreation: TSyntaxNode);
  var
    Host: TObjectsHost;
    Index: Integer;
  begin
    Host.Key := KeyOf(AText);
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
      Hosts := Hosts + [Host];
    end
    else if ACreation <> nil then
    begin
      // Mehrfach erzeugt: besitzend, sobald eine Erzeugung besitzt; die erste bleibt Ziel der Korrektur.
      Hosts[Index].Owning := Hosts[Index].Owning or Host.Owning;
      if Hosts[Index].Creation = nil then
      begin
        Hosts[Index].Creation := ACreation;
      end;
    end;
  end;

  // Erzeugungen, OwnsObjects := True und Felder vom Typ eines Steuerelements.
  procedure CollectHosts(ANode: TSyntaxNode);
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

  procedure CollectOwning(ANode: TSyntaxNode);
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
        if (Node.Kind = TSyntaxKind.AssignStatement) and (Node.ChildCount = 2) and
          (Node[0].Kind = TSyntaxKind.MemberAccess) and SameText(Node[0].Name, 'OwnsObjects') and
          (Node[0].ChildCount = 1) and SameText(TextOf(Node[1]), 'True') then
        begin
          Host := HostIndex(KeyOf(TextOf(Node[0][0])));
          if Host >= 0 then
          begin
            Hosts[Host].Owning := True;
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

  function ContainsFree(ANode: TSyntaxNode): Boolean;
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
  procedure MarkReleases(ARoutine, ANode: TSyntaxNode);
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
        if (Node.Kind = TSyntaxKind.MemberAccess) and SameText(Node.Name, 'Objects') and (Node.ChildCount = 1) then
        begin
          Host := HostIndex(KeyOf(TextOf(Node[0])));
          if (Host >= 0) and ContainsFree(ARoutine) then
          begin
            Hosts[Host].Handled := True;
          end;
        end;
        // Die Liste als Argument (FreeObjects(Liste)) oder auf der rechten Seite einer Zuweisung: weitergegeben.
        if (Node.Parent <> nil) and (((Node.Parent.Kind = TSyntaxKind.Call) and (Node.Parent[0] <> Node) and
          not MatchText(Node.Parent.Name, ['FreeAndNil', 'Assigned'])) or
          ((Node.Parent.Kind = TSyntaxKind.AssignStatement) and (Node.Parent[0] <> Node)) or
          (Node.Parent.Kind = TSyntaxKind.AddressOf)) and
          (Node.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) then
        begin
          Host := HostIndex(KeyOf(TextOf(Node)));
          if Host >= 0 then
          begin
            Hosts[Host].Handled := True;
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

  procedure VisitRoutines(ANode: TSyntaxNode);
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

  function EnclosingRoutine(ANode: TSyntaxNode): TSyntaxNode;
  begin
    Result := ANode.Parent;
    while (Result <> nil) and (Result.Kind <> TSyntaxKind.RoutineDecl) do
    begin
      Result := Result.Parent;
    end;
  end;

  // Lokale Variable AName, in der Routine aus T.Create(…) erzeugt und sonst nur gelesen (V.Name) oder an
  // AddObject übergeben: Name der Klasse, sonst ''.
  function LocalCreatedClass(ARoutine: TSyntaxNode; const AName: string; AAdd: TSyntaxNode): string;
  var
    Found: string;
    Other: Boolean;

    procedure Scan(ANode: TSyntaxNode);
    var
      Pending: TStack<TSyntaxNode>;
      Node: TSyntaxNode;
      Index: Integer;
      Parent: TSyntaxNode;
    begin
      // Iterativ (Bericht M1), Reihenfolge wie die frühere Rekursion (die erste Erzeugung zählt).
      Pending := TStack<TSyntaxNode>.Create;
      try
        Pending.Push(ANode);
        while Pending.Count > 0 do
        begin
          Node := Pending.Pop;
          if (Node.Kind = TSyntaxKind.Identifier) and SameText(Node.Name, AName) and (Node.Parent <> nil) then
          begin
            Parent := Node.Parent;
            if (Parent.Kind = TSyntaxKind.AssignStatement) and (Parent[0] = Node) and (Parent.ChildCount = 2) and
              (CreatedClass(Parent[1]) <> '') and (Found = '') then
            begin
              Found := CreatedClass(Parent[1]);
            end
            // V.Name liest nur; alles andere außer dem AddObject-Argument gibt V weiter oder frei.
            else if not ((Parent.Kind = TSyntaxKind.MemberAccess) and (Parent[0] = Node) and
              not MatchText(Parent.Name, FreeWords)) and (Parent <> AAdd) then
            begin
              Other := True;
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

  var
    Index, Inner: Integer;
    Local: Boolean;
    Name: string;
  begin
    Result := '';
    Local := False;
    for Index := 0 to ARoutine.ChildCount - 1 do
    begin
      if ARoutine[Index].Kind = TSyntaxKind.VarSection then
      begin
        for Inner := 0 to ARoutine[Index].ChildCount - 1 do
        begin
          for Name in ARoutine[Index][Inner].Name.Split([',']) do
          begin
            if SameText(Trim(Name), AName) then
            begin
              Local := True;
            end;
          end;
        end;
      end;
    end;
    if not Local then
    begin
      Exit;
    end;
    Found := '';
    Other := False;
    Scan(ARoutine);
    if not Other then
    begin
      Result := Found;
    end;
  end;

  function OwnsFix(const AHost: TObjectsHost; out AFix: TRuleFix): Boolean;
  var
    Creation, Access: TSyntaxNode;
    Statement: TSyntaxNode;
    ClassText: string;
  begin
    Result := False;
    Creation := AHost.Creation;
    if Creation = nil then
    begin
      Exit;
    end;
    Access := Creation;
    if Creation.Kind = TSyntaxKind.Call then
    begin
      Access := Creation[0];
    end;
    ClassText := TextOf(Access[0]);
    if (Creation.Kind = TSyntaxKind.MemberAccess) or (Creation.ChildCount = 1) then
    begin
      // TStringList.Create bzw. TStringList.Create() → TStringList.Create(True)
      AFix := TRuleFix.Create(Format('%s.Create(True) setzen', [ClassText]),
        [TTextEdit.Create(TTextRange.Create(Creation.StartPos, Creation.EndPos), ClassText + '.Create(True)')]);
      Exit(True);
    end;
    if (Creation.ChildCount = 2) and SameText(TextOf(Creation[1]), 'False') then
    begin
      AFix := TRuleFix.Create(Format('%s.Create(True) setzen', [ClassText]),
        [TTextEdit.Create(TTextRange.Create(Creation[1].StartPos, Creation[1].EndPos), 'True')]);
      Exit(True);
    end;
    // Andere Konstruktoren: OwnsObjects nach der Erzeugung setzen.
    Statement := Creation.Parent;
    if (Statement = nil) or (Statement.Kind <> TSyntaxKind.AssignStatement) or
      (Statement.StartPos.Line <> Statement.EndPos.Line) or (Statement.EndPos.Line > High(Lines)) then
    begin
      Exit;
    end;
    // Die Zeile muss mit der Anweisung enden.
    if Trim(Copy(Lines[Statement.EndPos.Line], Statement.EndPos.Character + 1, MaxInt)) <> ';' then
    begin
      Exit;
    end;
    AFix := TRuleFix.Create('OwnsObjects := True setzen',
      [TTextEdit.Create(TTextRange.Create(Statement.EndPos.Line + 1, 0, Statement.EndPos.Line + 1, 0),
      Copy(Lines[Statement.StartPos.Line], 1, Statement.StartPos.Character) + TextOf(Statement[0]) +
      '.OwnsObjects := True;' + LineBreak)]);
    Result := True;
  end;

  procedure CheckAdd(ANode: TSyntaxNode);
  var
    Host, ObjectArg: Integer;
    Access, Argument, Routine: TSyntaxNode;
    ClassName: string;
    Fix: TRuleFix;
    Fixes: TArray<TRuleFix>;
  begin
    if (ANode.Kind <> TSyntaxKind.Call) or (ANode.ChildCount < 1) or (ANode[0].Kind <> TSyntaxKind.MemberAccess) then
    begin
      Exit;
    end;
    if SameText(ANode.Name, 'AddObject') then
    begin
      ObjectArg := 2;
    end
    else if SameText(ANode.Name, 'InsertObject') then
    begin
      ObjectArg := 3;
    end
    else
    begin
      Exit;
    end;
    Access := ANode[0];
    if (ANode.ChildCount <> ObjectArg + 1) or (Access.ChildCount <> 1) then
    begin
      Exit;
    end;
    Host := HostIndex(KeyOf(TextOf(Access[0])));
    if (Host < 0) or Hosts[Host].Owning or Hosts[Host].Handled then
    begin
      Exit;
    end;
    Argument := ANode[ObjectArg];
    ClassName := CreatedClass(Argument);
    if (ClassName = '') and (Argument.Kind = TSyntaxKind.Identifier) then
    begin
      Routine := EnclosingRoutine(ANode);
      if Routine <> nil then
      begin
        ClassName := LocalCreatedClass(Routine, Argument.Name, ANode);
      end;
    end;
    if ClassName = '' then
    begin
      Exit;
    end;
    Fixes := nil;
    if OwnsFix(Hosts[Host], Fix) then
    begin
      Fixes := [Fix];
    end;
    AReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos),
      Format('%s besitzt die Objekte nicht; die %s-Objekte werden nie freigegeben.',
      [TextOf(Access[0]), ClassName]), TRuleConfidence.Medium, Fixes);
  end;

  // Prüft jeden Knoten nach seinen Kindern (Nachordnung) mit CheckAdd.
  procedure CheckAdds(ANode: TSyntaxNode);
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

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not (ContainsText(AContext.Text, 'AddObject') or
    ContainsText(AContext.Text, 'InsertObject')) then
  begin
    Exit;
  end;
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  Hosts := nil;
  CollectHosts(AContext.Tree.Root);
  if Hosts = nil then
  begin
    Exit;
  end;
  CollectOwning(AContext.Tree.Root);
  VisitRoutines(AContext.Tree.Root);
  Ancestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(TRuleDerived.Open(AContext), AContext));
  try
    CheckAdds(AContext.Tree.Root);
  finally
    Ancestry.Free;
  end;
end;

procedure RegisterOwnershipStringListObjectsRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TStringListObjectsLeakRule.Create);
end;

end.
