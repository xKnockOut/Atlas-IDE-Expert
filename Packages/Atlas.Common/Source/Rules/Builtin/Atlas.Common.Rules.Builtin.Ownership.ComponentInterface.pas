unit Atlas.Common.Rules.Builtin.Ownership.ComponentInterface;

// Regel aus Atlas.Common.Rules.Builtin.Ownership ausgelagert (Länge der Unit):
//   component-interface-dangling  Ein Nachfahr von TComponent (Option componentClasses) wird als Interface in
//                     einem Feld, einer globalen Variablen oder einer Liste gespeichert (#1090): FAnsicht as IFoo als
//                     Argument von Bus.Anmelden, FListe.Add …, die Zuweisung an ein Ziel außerhalb der Routine bzw.
//                     an ein Interface-Feld, Add/Insert in TList<IFoo>/TInterfaceList. TComponent zählt keine
//                     Referenzen; gibt die Datei dasselbe Objekt frei (Free, Release, DisposeOf, FreeAndNil), zeigt
//                     das Interface danach ins Leere. Still bei einer Abmeldung irgendwo in der Datei
//                     (FreeNotification, anderer Aufruf am selben Empfänger mit dem Objekt, Clear, weitere Zuweisung
//                     an dasselbe Ziel), bei Klassen mit eigenem _Release und wenn die Kette der Vorfahren abbricht.
//                     Korrektur: Empfänger.Abmelden(…) bzw. Ziel := nil vor der ersten Freigabe; Abmelden nur, wenn
//                     der Typ des Empfängers das Gegenstück hat. Ebenso gemeldet (ohne Korrektur): Nachfahren von
//                     TInterfacedObject, die so gespeichert und zusätzlich mit Free freigegeben werden.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TComponentInterfaceDanglingRule = class(TInterfacedObject, IRule)
  public const
    /// <summary>Aufrufe, die ein Interface am Empfänger speichern, und ihr Gegenstück ('' = keins).</summary>
    StoreMethods: array[0..14] of string = ('Add', 'Insert', 'AddOrSetValue', 'Push', 'Enqueue', 'Attach',
      'Subscribe', 'Register', 'RegisterObserver', 'AddObserver', 'AddListener', 'Anmelden', 'Registrieren',
      'Hinzufuegen', 'AddHandler');
    RemoveCounterparts: array[0..14] of string = ('Remove', 'Remove', '', '', '', 'Detach', 'Unsubscribe',
      'Unregister', 'UnregisterObserver', 'RemoveObserver', 'RemoveListener', 'Abmelden', 'Abmelden', 'Entfernen',
      'RemoveHandler');
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Gegenstück zum speichernden Aufruf AMethod (Anmelden → Abmelden); '' ohne.</summary>
    class function Counterpart(const AMethod: string): string; static;
  end;

/// <summary>Registriert die Regel component-interface-dangling.</summary>
procedure RegisterOwnershipComponentInterfaceRules(const ARegistry: TRuleRegistry);

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
  ComponentInterfaceDanglingRuleId = 'component-interface-dangling';

{ TComponentInterfaceDanglingRule }

function TComponentInterfaceDanglingRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(ComponentInterfaceDanglingRuleId, TRuleSeverity.Warning,
    'Interface auf eine Komponente ohne Referenzzählung bleibt nach der Freigabe gespeichert');
end;

class function TComponentInterfaceDanglingRule.Counterpart(const AMethod: string): string;
var
  Index: Integer;
begin
  for Index := 0 to High(StoreMethods) do
  begin
    if SameText(StoreMethods[Index], AMethod) then
    begin
      Exit(RemoveCounterparts[Index]);
    end;
  end;
  Result := '';
end;

procedure TComponentInterfaceDanglingRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
const
  // VCL- und FMX-Klassen, die von TComponent erben: Ohne Index endet die Kette der Vorfahren oft bei ihnen.
  KnownComponents: array[0..16] of string = ('TComponent', 'TControl', 'TWinControl', 'TCustomControl',
    'TGraphicControl', 'TScrollingWinControl', 'TCustomForm', 'TForm', 'TCustomFrame', 'TFrame', 'TDataModule',
    'TCommonCustomForm', 'TCustomPanel', 'TPanel', 'TStyledControl', 'TFmxObject', 'TCustomDataModule');
  FreeMethods: array[0..3] of string = ('Free', 'Release', 'DisposeOf', 'Destroy');
type
  /// <summary>Eine Freigabe in der Datei: Anweisung und freigegebener Ausdruck.</summary>
  TRelease = record
    Statement: TSyntaxNode;
    Target: TSyntaxNode;
  end;
var
  Resolver: TNameResolver;
  Ancestry: TAncestry;
  FileName: string;
  Bases: TArray<string>;
  Releases: TArray<TRelease>;
  Calls, Assignments, Clears: TArray<TSyntaxNode>;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  /// <summary>Text eines Ausdrucks ohne führendes "Self." und ohne Leerraum, zum Vergleichen.</summary>
  function Normalized(ANode: TSyntaxNode): string;
  begin
    Result := StringReplace(UpperCase(NodeText(ANode)), ' ', '', [rfReplaceAll]);
    if StartsStr('SELF.', Result) then
    begin
      Result := Copy(Result, 6, MaxInt);
    end;
  end;

  function Unwrapped(ANode: TSyntaxNode): TSyntaxNode;
  begin
    Result := ANode;
    while (Result.Kind = TSyntaxKind.ParenExpr) and (Result.ChildCount = 1) do
    begin
      Result := Result[0];
    end;
  end;

  /// <summary>Äußerster Knoten um ANode, der nur aus Klammern besteht.</summary>
  function Outer(ANode: TSyntaxNode): TSyntaxNode;
  begin
    Result := ANode;
    while (Result.Parent <> nil) and (Result.Parent.Kind = TSyntaxKind.ParenExpr) do
    begin
      Result := Result.Parent;
    end;
  end;

  /// <summary>Ein einfacher Name (X oder Self.X), außer Self selbst.</summary>
  function IsObjectName(ANode: TSyntaxNode): Boolean;
  begin
    case ANode.Kind of
      TSyntaxKind.Identifier:
        Result := not SameText(ANode.Name, 'Self');
      TSyntaxKind.MemberAccess:
        Result := (ANode.ChildCount = 1) and (ANode[0].Kind = TSyntaxKind.Identifier) and
          SameText(ANode[0].Name, 'Self');
    else
      Result := False;
    end;
  end;

  function Resolve(ANode: TSyntaxNode; out ASymbol, AType: TResolvedSymbol): Boolean;
  var
    TypeFound: Boolean;
  begin
    Result := Resolver.NodeType(AContext.Tree, FileName, ANode, ASymbol, AType, TypeFound) and TypeFound;
  end;

  function SameSymbol(const A, B: TResolvedSymbol): Boolean;
  begin
    Result := SameText(A.Name, B.Name) and SameText(A.FileName, B.FileName) and
      (A.Range.StartPos.Line = B.Range.StartPos.Line) and (A.Range.StartPos.Character = B.Range.StartPos.Character);
  end;

  /// <summary>Lokale Variable oder Parameter (auch als Empfänger einer Kette L.X)?</summary>
  function IsLocal(ANode: TSyntaxNode): Boolean;
  var
    First: TSyntaxNode;
  begin
    First := ANode;
    while (First.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess, TSyntaxKind.Call]) and
      (First.ChildCount > 0) do
    begin
      First := First[0];
    end;
    if First.Kind <> TSyntaxKind.Identifier then
    begin
      Exit(True);
    end;
    if SameText(First.Name, 'Self') then
    begin
      Exit(False);
    end;
    Result := Resolver.ResolveChain(AContext.Tree, FileName, [First.Name], First.StartOffset).Kind =
      TResolvedKind.Local;
  end;

  /// <summary>Basisklasse ohne Referenzzählung, von der AClass erbt (Option componentClasses), bzw.
  /// TInterfacedObject; '' wenn nichts davon oder wenn die Kette abbricht. Deklariert eine Klasse darunter _Release,
  /// zählt sie selbst und gilt nicht.</summary>
  function ComponentBase(const AClass: string): string;
  var
    Name: string;
    Depth: Integer;
    Found: TSymbolLocation;
    Method: TIndexSymbol;
  begin
    Result := '';
    Name := AClass;
    for Depth := 0 to 63 do
    begin
      if MatchText(Name, Bases) then
      begin
        Exit(Name);
      end;
      if MatchText('TComponent', Bases) and MatchText(Name, KnownComponents) then
      begin
        Exit('TComponent');
      end;
      if SameText(Name, 'TInterfacedObject') then
      begin
        Exit(Name);
      end;
      if MatchText(Name, ['TObject', 'TInterfacedPersistent']) then
      begin
        Exit;
      end;
      if Ancestry.FindClass(Name, Found) then
      begin
        for Method in Ancestry.Methods(Found) do
        begin
          if SameText(Method.Name, '_Release') then
          begin
            Exit;
          end;
        end;
      end;
      Name := Ancestry.ParentOf(Name);
      if Name = '' then
      begin
        Exit;
      end;
    end;
  end;

  /// <summary>Kommt das Objekt AObject in ANode vor (X, X as IFoo, Self.X)?</summary>
  function Mentions(ANode: TSyntaxNode; const AObject: TResolvedSymbol): Boolean;
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Child: Integer;
    Symbol, TypeInfo: TResolvedSymbol;
  begin
    // Iterativ (Bericht M1).
    Result := False;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if IsObjectName(Node) and SameText(Normalized(Node), AObject.Name) and Resolve(Node, Symbol, TypeInfo) and
          SameSymbol(Symbol, AObject) then
        begin
          Exit(True);
        end;
        for Child := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Child]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  /// <summary>Gibt es eine Abmeldung? FreeNotification auf dem Objekt, ein anderer Aufruf am selben Empfänger mit
  /// dem Objekt als Argument bzw. Clear, eine weitere Zuweisung an dieselbe Stelle.</summary>
  function Unregistered(const AObject: TResolvedSymbol; AStore, AHolder: TSyntaxNode; AIsCall: Boolean): Boolean;
  var
    Call, Callee, Assignment: TSyntaxNode;
    Symbol, TypeInfo: TResolvedSymbol;
    Holder: string;
    Argument: Integer;
  begin
    Holder := Normalized(AHolder);
    for Call in Calls do
    begin
      Callee := Call[0];
      if (Callee.Kind <> TSyntaxKind.MemberAccess) or (Callee.ChildCount = 0) then
      begin
        Continue;
      end;
      if SameText(Callee.Name, 'FreeNotification') and Resolve(Callee[0], Symbol, TypeInfo) and
        SameSymbol(Symbol, AObject) then
      begin
        Exit(True);
      end;
      if not AIsCall or (Call = AStore) or (Normalized(Callee[0]) <> Holder) then
      begin
        Continue;
      end;
      if SameText(Callee.Name, 'Clear') then
      begin
        Exit(True);
      end;
      for Argument := 1 to Call.ChildCount - 1 do
      begin
        if Mentions(Call[Argument], AObject) then
        begin
          Exit(True);
        end;
      end;
    end;
    // Clear ohne Klammern ist eine Anweisung aus MemberAccess.
    for Callee in Clears do
    begin
      if AIsCall and (Normalized(Callee[0]) = Holder) then
      begin
        Exit(True);
      end;
    end;
    if not AIsCall then
    begin
      for Assignment in Assignments do
      begin
        if (Assignment <> AStore) and (Normalized(Assignment[0]) = Holder) then
        begin
          Exit(True);
        end;
      end;
    end;
    Result := False;
  end;

  /// <summary>Abmeldung vor der Freigabe einfügen: Empfänger.Gegenstück(Argument); bzw. Ziel := nil;.</summary>
  function UnregisterFix(AStore, AHolder, AArgument: TSyntaxNode; AIsCall: Boolean; const ARelease: TRelease;
    out AFix: TRuleFix): Boolean;
  var
    Method, Line: string;
    Symbol, TypeInfo, Member: TResolvedSymbol;
  begin
    Result := False;
    if not TRoutineBody.InList(ARelease.Statement) or
      (ARelease.Statement.StartPos.Line <> ARelease.Statement.EndPos.Line) then
    begin
      Exit;
    end;
    if AIsCall then
    begin
      Method := Counterpart(AStore[0].Name);
      // Das Gegenstück muss es am Typ des Empfängers geben.
      if (Method = '') or not Resolve(AHolder, Symbol, TypeInfo) or not Resolver.FindMember(TypeInfo, Method, Member)
        then
      begin
        Exit;
      end;
      Line := NodeText(AHolder) + '.' + Method + '(' + NodeText(AArgument) + ');';
    end
    else
    begin
      Line := NodeText(AHolder) + ' := nil;';
    end;
    AFix := TRuleFix.Create('Abmeldung vor der Freigabe einfügen',
      [TRoutineBody.InsertBefore(AContext.Text, ARelease.Statement, Line)]);
    Result := True;
  end;

  /// <summary>Wird das Objekt hier als Interface gespeichert? AValue ist "X as IFoo" oder X selbst.</summary>
  procedure Inspect(AValue: TSyntaxNode);
  var
    Value, Parent, ObjectNode, Holder, Argument: TSyntaxNode;
    InterfaceName, Base, HolderText, ListType: string;
    IsCall: Boolean;
    ObjectSymbol, ObjectType, Symbol, TypeInfo: TResolvedSymbol;
    Release: TRelease;
    Fixes: TArray<TRuleFix>;
    Fix: TRuleFix;
    Found, Index: Integer;
  begin
    Value := Outer(AValue);
    Parent := Value.Parent;
    if Parent = nil then
    begin
      Exit;
    end;
    if (AValue.Kind = TSyntaxKind.BinaryExpr) then
    begin
      ObjectNode := Unwrapped(AValue[0]);
      if (AValue[1].Kind <> TSyntaxKind.Identifier) or
        not TSelfAsInterfaceInConstructorRule.IsInterfaceType(AValue[1].Name) then
      begin
        Exit;
      end;
      InterfaceName := AValue[1].Name;
    end
    else
    begin
      ObjectNode := AValue;
      InterfaceName := '';
    end;
    if not IsObjectName(ObjectNode) then
    begin
      Exit;
    end;
    // Ziel der Speicherung: Feld, globale Variable oder Liste, kein lokaler Name.
    if (Parent.Kind = TSyntaxKind.AssignStatement) and (Parent.ChildCount = 2) and (Parent[1] = Value) then
    begin
      IsCall := False;
      Holder := Parent[0];
      if InterfaceName = '' then
      begin
        if not Resolve(Holder, Symbol, TypeInfo) or (TypeInfo.SymbolKind <> TIndexSymbolKind.InterfaceType) then
        begin
          Exit;
        end;
        InterfaceName := TypeInfo.Name;
      end;
    end
    else if (Parent.Kind = TSyntaxKind.Call) and (Parent.ChildCount >= 2) and (Parent[0] <> Value) and
      (Parent[0].Kind = TSyntaxKind.MemberAccess) and (Parent[0].ChildCount = 1) and
      MatchText(Parent[0].Name, StoreMethods) then
    begin
      IsCall := True;
      Holder := Parent[0][0];
      if InterfaceName = '' then
      begin
        // Ohne "as" nur Listen von Interfaces: TList<IFoo>, TInterfaceList.
        if not MatchText(Parent[0].Name, ['Add', 'Insert']) or not IsObjectName(Holder) then
        begin
          Exit;
        end;
        // Der deklarierte Typ genügt; TList<T> selbst muss nicht im Index stehen.
        if Holder.Kind = TSyntaxKind.Identifier then
        begin
          Symbol := Resolver.ResolveChain(AContext.Tree, FileName, [Holder.Name], Holder.StartOffset);
        end
        else
        begin
          Symbol := Resolver.ResolveChain(AContext.Tree, FileName, ['Self', Holder.Name], Holder.StartOffset);
        end;
        ListType := Symbol.TypeName;
        if (Symbol.TypeArgs <> '') and (Pos('<', ListType) = 0) then
        begin
          ListType := ListType + '<' + Symbol.TypeArgs + '>';
        end;
        if MatchText(ListType, ['TInterfaceList', 'System.Classes.TInterfaceList', 'Classes.TInterfaceList']) then
        begin
          InterfaceName := 'IInterface';
        end
        else if StartsText('TList<', ListType) and EndsText('>', ListType) and
          TSelfAsInterfaceInConstructorRule.IsInterfaceType(Copy(ListType, 7, Length(ListType) - 7)) then
        begin
          InterfaceName := Copy(ListType, 7, Length(ListType) - 7);
        end
        else
        begin
          Exit;
        end;
      end;
    end
    else
    begin
      Exit;
    end;
    if IsLocal(Holder) then
    begin
      Exit;
    end;
    if not Resolve(ObjectNode, ObjectSymbol, ObjectType) or
      not (ObjectSymbol.SymbolKind in [TIndexSymbolKind.Field, TIndexSymbolKind.Variable]) or
      (ObjectType.SymbolKind <> TIndexSymbolKind.ClassType) then
    begin
      Exit;
    end;
    Base := ComponentBase(ObjectType.Name);
    if Base = '' then
    begin
      Exit;
    end;
    // Erste Freigabe desselben Objekts in der Datei.
    Found := -1;
    for Index := 0 to High(Releases) do
    begin
      if Resolve(Releases[Index].Target, Symbol, TypeInfo) and SameSymbol(Symbol, ObjectSymbol) then
      begin
        Found := Index;
        Break;
      end;
    end;
    if Found < 0 then
    begin
      Exit;
    end;
    Release := Releases[Found];
    HolderText := NodeText(Holder);
    // Referenzgezählt: Free gibt das Objekt frei, obwohl das gespeicherte Interface es noch hält; eine Abmeldung
    // davor gäbe es schon frei (Zähler 0), Free wäre dann die zweite Freigabe.
    if SameText(Base, 'TInterfacedObject') then
    begin
      AReport.Add(TTextRange.Create(Parent.StartPos, Parent.EndPos), Format('%s ist referenzgezählt ' +
        '(TInterfacedObject); %s gibt es frei, obwohl %s noch ein %s darauf hält.', [ObjectType.Name,
        NodeText(Release.Statement), HolderText, InterfaceName]), TRuleConfidence.Medium);
      Exit;
    end;
    if Unregistered(ObjectSymbol, Parent, Holder, IsCall) then
    begin
      Exit;
    end;
    Argument := Value;
    Fixes := nil;
    if UnregisterFix(Parent, Holder, Argument, IsCall, Release, Fix) then
    begin
      Fixes := [Fix];
    end;
    AReport.Add(TTextRange.Create(Parent.StartPos, Parent.EndPos), Format('%s ist ein %s ohne Referenzzählung; ' +
      'nach %s hält %s ein ungültiges %s.', [ObjectType.Name, Base, NodeText(Release.Statement), HolderText,
      InterfaceName]), TRuleConfidence.Medium, Fixes);
  end;

  procedure Collect(ANode: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Child: Integer;
    Release: TRelease;
    Expression: TSyntaxNode;
  begin
    // Iterativ (Bericht M1), Reihenfolge wie die frühere Rekursion.
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        case Node.Kind of
          TSyntaxKind.Call:
            Calls := Calls + [Node];
          TSyntaxKind.AssignStatement:
            if Node.ChildCount = 2 then
            begin
              Assignments := Assignments + [Node];
            end;
          TSyntaxKind.CallStatement:
            if Node.ChildCount > 0 then
            begin
              // X.Free, X.Release …, FreeAndNil(X)
              Expression := Node[0];
              if (Expression.Kind = TSyntaxKind.Call) and (Expression.ChildCount > 0) and
                (Expression[0].Kind = TSyntaxKind.MemberAccess) then
              begin
                Expression := Expression[0];
              end;
              Release.Statement := Node;
              Release.Target := nil;
              if (Expression.Kind = TSyntaxKind.MemberAccess) and (Expression.ChildCount = 1) and
                MatchText(Expression.Name, FreeMethods) then
              begin
                Release.Target := Expression[0];
              end
              else if (Expression.Kind = TSyntaxKind.Call) and SameText(Expression.Name, 'FreeAndNil') and
                (Expression.ChildCount = 2) then
              begin
                Release.Target := Expression[1];
              end;
              if (Release.Target <> nil) and IsObjectName(Release.Target) then
              begin
                Releases := Releases + [Release];
              end;
              if (Expression.Kind = TSyntaxKind.MemberAccess) and (Expression.ChildCount = 1) and
                SameText(Expression.Name, 'Clear') then
              begin
                Clears := Clears + [Expression];
              end;
            end;
        else
          // Übrige Werte bewusst ohne Wirkung.
        end;
        for Child := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Child]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Child: Integer;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind = TSyntaxKind.BinaryExpr) and SameText(Node.Name, 'as') and (Node.ChildCount = 2) then
        begin
          Inspect(Node);
        end
        else if IsObjectName(Node) and (Outer(Node).Parent <> nil) and
          (Outer(Node).Parent.Kind in [TSyntaxKind.AssignStatement, TSyntaxKind.Call]) then
        begin
          Inspect(Node);
        end;
        for Child := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Child]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  Bases := TRuleOptions.Strings(AContext.Options, 'componentClasses', ['TComponent']);
  FileName := AContext.FileName;
  if FileName = '' then
  begin
    FileName := AContext.RelativePath;
  end;
  if FileName = '' then
  begin
    FileName := AContext.UnitName + '.pas';
  end;
  Releases := nil;
  Calls := nil;
  Assignments := nil;
  Clears := nil;
  Collect(AContext.Tree.Root);
  if Releases = nil then
  begin
    Exit;
  end;
  Resolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit, AContext.TreeUnits);
  Ancestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(TRuleDerived.Open(AContext), AContext));
  try
    Resolver.Namespaces := AContext.Namespaces;
    Visit(AContext.Tree.Root);
  finally
    Ancestry.Free;
    Resolver.Free;
  end;
end;

procedure RegisterOwnershipComponentInterfaceRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TComponentInterfaceDanglingRule.Create);
end;

end.
