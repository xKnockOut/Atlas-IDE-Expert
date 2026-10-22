unit Atlas.Common.Rules.Builtin.Generics;

// Regeln für Generics (#909, Gruppe Compiler vorab):
//   generic-constraint-violated  Ein Typargument erfüllt die Einschränkung
//                                seines Typparameters nicht (#1028): class
//                                (E2511), record (E2512), constructor (E2513),
//                                Interface (E2514) oder Basisklasse (E2515);
//                                außerdem T.Create ohne constructor-Einschränkung
//                                (E2568) und Methodenaufrufe auf Werten eines
//                                Typparameters ohne jede Einschränkung (E2571).
//
// Typargumente stehen im Baum als GenericArgs unter einer TypeReference oder
// einem MemberAccess (TFabrik<Integer>.Create). Den generischen Typ löst
// TNameResolver.ResolveTypeTextFrom samt Zahl der Typparameter auf, die
// Einschränkungen liest die Regel aus seiner Signatur ("TFabrik<T: class> =
// class"). Gemeldet wird nur, was sicher feststeht: Argumente, die selbst
// Typparameter sind, Aliase und Typen mit abgebrochener Vorfahrenkette bleiben
// still. Rümpfe der Methoden generischer Typen dieser Datei prüft die Regel auf
// T.Create und V.Methode mit V vom Typ T.
//
// Korrektur bei E2568 und E2571 für Typparameter dieser Datei, die allein in
// ihrer Gruppe stehen: die Einschränkung ergänzen (T: class, constructor bzw.
// T: class).

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  GenericConstraintViolatedRuleId = 'generic-constraint-violated';

type
  /// <summary>Ein Typparameter mit seinen Einschränkungen aus "&lt;T: class, constructor; U&gt;".</summary>
  TGenericParam = record
    Name: string;
    /// <summary>class, record, constructor in Kleinschreibung oder Typnamen wie geschrieben.</summary>
    Constraints: TArray<string>;
    /// <summary>Steht allein in seiner Gruppe (nicht "K, V: class").</summary>
    Single: Boolean;
    /// <summary>Offset (ab 0, relativ zum Anfang des gelesenen Texts) hinter dem letzten Zeichen der Gruppe.
    /// </summary>
    GroupEnd: Integer;
    function Has(const AConstraint: string): Boolean;
    /// <summary>Einschränkungen, die Typen nennen (weder class noch record noch constructor).</summary>
    function TypeConstraints: TArray<string>;
  end;

  TGenericConstraintViolatedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Typparameter aus dem Text ab dem ersten "&lt;" bis zum passenden "&gt;"; leer ohne "&lt;".
    /// </summary>
    class function ParseParams(const AText: string): TArray<TGenericParam>; static;
  end;

procedure RegisterGenericRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Rules.Derived;

const
  Keywords: array[0..2] of string = ('class', 'record', 'constructor');
  ManagedBuiltins: array[0..6] of string = ('string', 'UnicodeString', 'AnsiString', 'WideString', 'RawByteString',
    'Variant', 'OleVariant');

type
  /// <summary>Art eines Typarguments, soweit sie sicher feststeht.</summary>
  TArgumentKind = (Unknown, ClassArg, ValueArg, ManagedArg, InterfaceArg);

{ TGenericParam }

function TGenericParam.Has(const AConstraint: string): Boolean;
begin
  Result := MatchText(AConstraint, Constraints);
end;

function TGenericParam.TypeConstraints: TArray<string>;
var
  Constraint: string;
begin
  Result := nil;
  for Constraint in Constraints do
    if not MatchText(Constraint, Keywords) then
      Result := Result + [Constraint];
end;

{ TGenericConstraintViolatedRule }

function TGenericConstraintViolatedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(GenericConstraintViolatedRuleId, TRuleSeverity.Error,
    'Typargument verletzt eine Einschränkung');
end;

class function TGenericConstraintViolatedRule.ParseParams(const AText: string): TArray<TGenericParam>;
var
  Position, Depth, GroupStart: Integer;

  procedure AddGroup(AEnd: Integer);
  var
    Group, NamesText, ConstraintText, Part: string;
    Colon, Inner, PartDepth, PartStart: Integer;
    Names, Constraints: TArray<string>;
    Param: TGenericParam;
    Name: string;
  begin
    Group := Copy(AText, GroupStart, AEnd - GroupStart);
    Colon := Pos(':', Group);
    if Colon > 0 then
    begin
      NamesText := Copy(Group, 1, Colon - 1);
      ConstraintText := Copy(Group, Colon + 1, MaxInt);
    end
    else
    begin
      NamesText := Group;
      ConstraintText := '';
    end;
    Names := nil;
    for Part in NamesText.Split([',']) do
      if Trim(Part) <> '' then
        Names := Names + [Trim(Part)];
    // Einschränkungen an Kommas auf oberster Ebene trennen (IComparer<T, U> bleibt ganz).
    Constraints := nil;
    PartDepth := 0;
    PartStart := 1;
    for Inner := 1 to Length(ConstraintText) + 1 do
      if (Inner > Length(ConstraintText)) or ((ConstraintText[Inner] = ',') and (PartDepth = 0)) then
      begin
        Part := Trim(Copy(ConstraintText, PartStart, Inner - PartStart));
        if Part <> '' then
        begin
          if MatchText(Part, Keywords) then
            Part := LowerCase(Part);
          Constraints := Constraints + [Part];
        end;
        PartStart := Inner + 1;
      end
      else if ConstraintText[Inner] = '<' then
        Inc(PartDepth)
      else if ConstraintText[Inner] = '>' then
        Dec(PartDepth);
    // Hinter dem letzten Zeichen der Gruppe, ohne folgende Leerzeichen.
    Inner := AEnd - 1;
    while (Inner > GroupStart) and CharInSet(AText[Inner], [' ', #9, #10, #13]) do
      Dec(Inner);
    for Name in Names do
    begin
      Param := Default(TGenericParam);
      Param.Name := Name;
      Param.Constraints := Constraints;
      Param.Single := Length(Names) = 1;
      Param.GroupEnd := Inner;
      Result := Result + [Param];
    end;
  end;

begin
  Result := nil;
  Position := Pos('<', AText);
  if Position = 0 then
    Exit;
  Depth := 0;
  GroupStart := Position + 1;
  while Position <= Length(AText) do
  begin
    case AText[Position] of
      '<':
        Inc(Depth);
      '>':
        begin
          Dec(Depth);
          if Depth = 0 then
          begin
            AddGroup(Position);
            Exit;
          end;
        end;
      ';':
        if Depth = 1 then
        begin
          AddGroup(Position);
          GroupStart := Position + 1;
        end;
    end;
    Inc(Position);
  end;
end;

procedure TGenericConstraintViolatedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Cache: IRuleDerivedCache;
  Resolver: TNameResolver;
  FileName: string;
  Local: TUnitIndex;
  // Namen aller Typparameter der Datei: solche Argumente bleiben ungeprüft.
  ParamNames: TDictionary<string, Boolean>;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  function RangeOf(ANode: TSyntaxNode): TTextRange;
  begin
    Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
  end;

  function BareName(const AName: string): string;
  begin
    Result := AName;
    if Pos('<', Result) > 0 then
      Result := Copy(Result, 1, Pos('<', Result) - 1);
    Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
  end;

  function SameType(const A, B: TResolvedSymbol): Boolean;
  begin
    Result := SameText(A.Name, B.Name) and SameText(A.Container, B.Container) and SameText(A.UnitName, B.UnitName);
  end;

  function KindOf(const AType: TResolvedSymbol): TArgumentKind;
  begin
    Result := TArgumentKind.Unknown;
    if AType.Builtin then
    begin
      if MatchText(AType.Name, ManagedBuiltins) then
        Result := TArgumentKind.ManagedArg
      else
        Result := TArgumentKind.ValueArg;
      Exit;
    end;
    case AType.SymbolKind of
      TIndexSymbolKind.ClassType:
        Result := TArgumentKind.ClassArg;
      TIndexSymbolKind.RecordType, TIndexSymbolKind.EnumType:
        Result := TArgumentKind.ValueArg;
      TIndexSymbolKind.InterfaceType:
        Result := TArgumentKind.InterfaceArg;
    end;
  end;

  /// <summary>Erbt die Klasse bzw. das Interface AType von ATarget (oder ist es)? False mit AKnown = False, wenn
  /// die Kette abbricht.</summary>
  function Descends(const AType, ATarget: TResolvedSymbol; out AKnown: Boolean): Boolean;
  var
    Current, Next: TResolvedSymbol;
    Depth: Integer;
  begin
    AKnown := True;
    Current := AType;
    for Depth := 0 to 64 do
    begin
      if SameType(Current, ATarget) then
        Exit(True);
      if (Length(Current.Ancestors) = 0) or SameText(BareName(Current.Ancestors[0]), 'TObject') or
        SameText(BareName(Current.Ancestors[0]), 'IInterface') then
        Exit(SameText(ATarget.Name, 'TObject') or SameText(ATarget.Name, 'IInterface') or
          SameText(ATarget.Name, 'IUnknown'));
      if not Resolver.AncestorOf(Current, Next) then
        Break;
      Current := Next;
    end;
    AKnown := False;
    Result := False;
  end;

  /// <summary>Unterstützt die Klasse AType das Interface ATarget (über die Interface-Listen der ganzen Kette und
  /// deren Vorfahren)? AKnown = False, wenn eine Kette abbricht.</summary>
  function Supports(const AType, ATarget: TResolvedSymbol; out AKnown: Boolean): Boolean;
  var
    Current, Next, Interface_: TResolvedSymbol;
    Depth, Index: Integer;
    Known: Boolean;
  begin
    AKnown := False;
    Result := False;
    Current := AType;
    for Depth := 0 to 64 do
    begin
      for Index := 1 to High(Current.Ancestors) do
      begin
        if not Resolver.ResolveTypeTextFrom(Local, Current.Ancestors[Index], Interface_) or
          (Interface_.SymbolKind <> TIndexSymbolKind.InterfaceType) then
          Exit;
        if Descends(Interface_, ATarget, Known) then
        begin
          AKnown := True;
          Exit(True);
        end;
        if not Known then
          Exit;
      end;
      if (Length(Current.Ancestors) = 0) or SameText(BareName(Current.Ancestors[0]), 'TObject') then
      begin
        AKnown := True;
        Exit;
      end;
      if not Resolver.AncestorOf(Current, Next) then
        Exit;
      Current := Next;
    end;
  end;

  /// <summary>Meldung für ein Typargument, das AParam des Typs AGeneric nicht erfüllt; '' wenn es passt oder
  /// unklar ist.</summary>
  function Violation(const AGeneric: string; const AParam: TGenericParam; const AArgText: string;
    const AArg: TResolvedSymbol): string;
  var
    Kind: TArgumentKind;
    Constraint: string;
    Target: TResolvedSymbol;
    Known, Missing: Boolean;
  begin
    Result := '';
    Kind := KindOf(AArg);
    if Kind = TArgumentKind.Unknown then
      Exit;
    if AParam.Has('class') and (Kind <> TArgumentKind.ClassArg) then
      Exit(Format('%s ist kein Klassentyp; %s von %s verlangt class (wie E2511).', [AArgText, AParam.Name,
        AGeneric]));
    if AParam.Has('record') and (Kind <> TArgumentKind.ValueArg) then
      Exit(Format('%s ist kein Werttyp; %s von %s verlangt record (wie E2512).', [AArgText, AParam.Name,
        AGeneric]));
    if AParam.Has('constructor') and not AParam.Has('record') and (Kind <> TArgumentKind.ClassArg) then
      Exit(Format('%s hat keinen parameterlosen Konstruktor; %s von %s verlangt constructor (wie E2513).',
        [AArgText, AParam.Name, AGeneric]));
    for Constraint in AParam.TypeConstraints do
    begin
      if not Resolver.ResolveTypeTextFrom(Local, Constraint, Target) then
        Continue;
      if Target.SymbolKind = TIndexSymbolKind.InterfaceType then
      begin
        Known := True;
        case Kind of
          TArgumentKind.ClassArg:
            Missing := not Supports(AArg, Target, Known);
          TArgumentKind.InterfaceArg:
            Missing := not Descends(AArg, Target, Known);
        else
          Missing := True;
        end;
        if Missing and Known then
          Exit(Format('%s unterstützt %s nicht; %s von %s verlangt %s (wie E2514).', [AArgText, Constraint,
            AParam.Name, AGeneric, Constraint]));
      end
      else if Target.SymbolKind = TIndexSymbolKind.ClassType then
      begin
        Known := True;
        Missing := True;
        if Kind = TArgumentKind.ClassArg then
          Missing := not Descends(AArg, Target, Known);
        if Missing and Known then
          Exit(Format('%s ist nicht mit %s kompatibel; %s von %s verlangt %s (wie E2515).', [AArgText,
            Constraint, AParam.Name, AGeneric, Constraint]));
      end;
    end;
  end;

  procedure CheckArguments(AArgs: TSyntaxNode);
  var
    Owner: TSyntaxNode;
    Base, ArgText: string;
    Args: TArray<string>;
    Generic, Arg: TResolvedSymbol;
    Params: TArray<TGenericParam>;
    Index: Integer;
    Message: string;
  begin
    Owner := AArgs.Parent;
    if (Owner = nil) or not (Owner.Kind in [TSyntaxKind.TypeReference, TSyntaxKind.MemberAccess]) then
      Exit;
    Base := Trim(Copy(AContext.Text, Owner.StartOffset + 1, AArgs.StartOffset - Owner.StartOffset));
    Args := nil;
    for Index := 0 to AArgs.ChildCount - 1 do
      Args := Args + [Trim(NodeText(AArgs[Index]))];
    if (Base = '') or (Args = nil) then
      Exit;
    if not Resolver.ResolveTypeTextFrom(Local, Base + '<' + string.Join(',', Args) + '>', Generic) or
      not Generic.IsType then
      Exit;
    Params := ParseParams(Generic.Signature);
    if Length(Params) <> Length(Args) then
      Exit;
    for Index := 0 to High(Args) do
    begin
      if (Params[Index].Constraints = nil) or (AArgs[Index].Kind <> TSyntaxKind.TypeReference) then
        Continue;
      ArgText := Args[Index];
      if ParamNames.ContainsKey(LowerCase(BareName(ArgText))) or
        not Resolver.ResolveTypeTextFrom(Local, ArgText, Arg) then
        Continue;
      Message := Violation(Generic.Name, Params[Index], ArgText, Arg);
      if Message <> '' then
        AReport.Add(RangeOf(AArgs[Index]), Message, TRuleConfidence.High);
    end;
  end;

  /// <summary>Korrektur, die an die Gruppe von AParam (Typparameter aus der Datei, Text ab AStart) AText hängt.
  /// </summary>
  function ConstraintFix(const AParam: TGenericParam; AStart: Integer; const AText: string;
    out AFix: TRuleFix): Boolean;
  var
    Offset: Integer;
  begin
    Result := AParam.Single;
    if not Result then
      Exit;
    Offset := AStart + AParam.GroupEnd;
    AFix := TRuleFix.Create('Einschränkung ergänzen', [TRuleEdit.Create(TRuleDerived.OffsetRange(Cache, AContext,
      Offset, Offset), AText)]);
  end;

  /// <summary>Typparameter des generischen Typs bzw. der Methode im Knoten ANode (TypeDecl oder RoutineHeader)
  /// samt Offset des Texts, aus dem sie gelesen wurden.</summary>
  function ParamsOf(ANode: TSyntaxNode; out AStart: Integer): TArray<TGenericParam>;
  var
    Node: TSyntaxNode;
  begin
    Result := nil;
    AStart := 0;
    Node := ANode.FindChild(TSyntaxKind.GenericParams);
    if Node = nil then
      Exit;
    AStart := Node.StartOffset;
    Result := ParseParams(NodeText(Node));
  end;

  procedure CheckBody(ARoutine: TSyntaxNode; const AParams: TArray<TGenericParam>; const AStarts: TArray<Integer>);

    function FindParam(const AName: string; out AIndex: Integer): Boolean;
    var
      Index: Integer;
    begin
      // Typparameter der Methode verdecken die der Klasse: sie stehen hinten.
      for Index := High(AParams) downto 0 do
        if SameText(AParams[Index].Name, AName) then
        begin
          AIndex := Index;
          Exit(True);
        end;
      Result := False;
    end;

    // Iterativ (Bericht M1).
    procedure Visit(ARoot: TSyntaxNode);
    var
      Pending: TStack<TSyntaxNode>;
      Node: TSyntaxNode;
      Index, Child: Integer;
      Receiver: TSyntaxNode;
      Symbol: TResolvedSymbol;
      Param: TGenericParam;
      Fix: TRuleFix;
      Fixes: TArray<TRuleFix>;
      Text: string;
    begin
      Pending := TStack<TSyntaxNode>.Create;
      try
        Pending.Push(ARoot);
        while Pending.Count > 0 do
        begin
          Node := Pending.Pop;
          if (Node.Kind = TSyntaxKind.MemberAccess) and (Node.ChildCount > 0) and
            (Node[0].Kind = TSyntaxKind.Identifier) then
          begin
            Receiver := Node[0];
            if FindParam(Receiver.Name, Index) then
            begin
              Param := AParams[Index];
              // T.Create ohne constructor; eine Basisklasse oder record als Einschränkung lässt die Regel aus.
              if SameText(Node.Name, 'Create') and not Param.Has('constructor') and not Param.Has('record') and
                (Param.TypeConstraints = nil) then
              begin
                Fixes := nil;
                Text := ': class, constructor';
                if Param.Constraints <> nil then
                  Text := ', constructor';
                if ConstraintFix(Param, AStarts[Index], Text, Fix) then
                  Fixes := [Fix];
                AReport.Add(RangeOf(Node), Format('%s hat keine constructor-Einschränkung; %s.Create ist nicht ' +
                  'erlaubt (wie E2568).', [Param.Name, Param.Name]), TRuleConfidence.High, Fixes);
              end;
            end
            else
            begin
              Symbol := Resolver.Resolve(AContext.Tree, FileName, Receiver.StartPos);
              if Symbol.Found and not Symbol.IsType and FindParam(Symbol.TypeName, Index) and
                (AParams[Index].Constraints = nil) then
              begin
                Fixes := nil;
                if ConstraintFix(AParams[Index], AStarts[Index], ': class', Fix) then
                  Fixes := [Fix];
                AReport.Add(RangeOf(Node), Format('%s hat keine class- oder Interface-Einschränkung; %s.%s ist nicht ' +
                  'erlaubt (wie E2571).', [AParams[Index].Name, Receiver.Name, Node.Name]), TRuleConfidence.High,
                  Fixes);
              end;
            end;
          end;
          for Child := Node.ChildCount - 1 downto 0 do
            if Node[Child].Kind <> TSyntaxKind.AnonymousMethod then
              Pending.Push(Node[Child]);
        end;
      finally
        Pending.Free;
      end;
    end;

  var
    Child: Integer;
  begin
    for Child := 0 to ARoutine.ChildCount - 1 do
      if ARoutine[Child].Kind = TSyntaxKind.Block then
        Visit(ARoutine[Child]);
  end;

  /// <summary>Methoden generischer Typen dieser Datei: Typparameter von Klasse und Methode, dann der Rumpf.
  /// </summary>
  procedure CheckMethods;
  var
    Types: TDictionary<string, TSyntaxNode>;

    // Iterativ (Bericht M1).
    procedure CollectTypes(ARoot: TSyntaxNode);
    var
      Pending: TStack<TSyntaxNode>;
      Node: TSyntaxNode;
      Child: Integer;
    begin
      Pending := TStack<TSyntaxNode>.Create;
      try
        Pending.Push(ARoot);
        while Pending.Count > 0 do
        begin
          Node := Pending.Pop;
          if (Node.Kind = TSyntaxKind.TypeDecl) and (Node.FindChild(TSyntaxKind.GenericParams) <> nil) then
            Types.AddOrSetValue(LowerCase(Node.Name), Node);
          if Node.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.Block] then
            Continue;
          for Child := Node.ChildCount - 1 downto 0 do
            Pending.Push(Node[Child]);
        end;
      finally
        Pending.Free;
      end;
    end;

    /// <summary>Kopf der Methode AName im Typ ATypeDecl, wenn es genau einen gibt.</summary>
    function MethodHeader(ATypeDecl: TSyntaxNode; const AName: string): TSyntaxNode;
    var
      Body: TSyntaxNode;
      Index: Integer;
    begin
      Result := nil;
      Body := ATypeDecl.FindChild(TSyntaxKind.ClassType);
      if Body = nil then
        Body := ATypeDecl.FindChild(TSyntaxKind.RecordType);
      if Body = nil then
        Exit;
      for Index := 0 to Body.ChildCount - 1 do
        if (Body[Index].Kind = TSyntaxKind.RoutineHeader) and SameText(Body[Index].Name, AName) then
        begin
          if Result <> nil then
            Exit(nil);
          Result := Body[Index];
        end;
    end;

    // Iterativ (Bericht M1).
    procedure Visit(ARoot: TSyntaxNode);
    var
      Pending: TStack<TSyntaxNode>;
      Node: TSyntaxNode;
      Child, Index, Start, Dot: Integer;
      TypeDecl, Header: TSyntaxNode;
      Params, Own: TArray<TGenericParam>;
      Starts: TArray<Integer>;
    begin
      Pending := TStack<TSyntaxNode>.Create;
      try
        Pending.Push(ARoot);
        while Pending.Count > 0 do
        begin
          Node := Pending.Pop;
          if Node.Kind = TSyntaxKind.RoutineDecl then
          begin
            Dot := LastDelimiter('.', Node.Name);
            if (Dot > 0) and Types.TryGetValue(LowerCase(Copy(Node.Name, 1, Dot - 1)), TypeDecl) then
            begin
              Params := ParamsOf(TypeDecl, Start);
              Starts := nil;
              for Index := 0 to High(Params) do
                Starts := Starts + [Start];
              Header := MethodHeader(TypeDecl, Copy(Node.Name, Dot + 1, MaxInt));
              if Header <> nil then
              begin
                Own := ParamsOf(Header, Start);
                for Index := 0 to High(Own) do
                  Starts := Starts + [Start];
                Params := Params + Own;
              end;
              if Params <> nil then
                CheckBody(Node, Params, Starts);
            end;
            Continue;
          end;
          for Child := Node.ChildCount - 1 downto 0 do
            Pending.Push(Node[Child]);
        end;
      finally
        Pending.Free;
      end;
    end;

  begin
    Types := TDictionary<string, TSyntaxNode>.Create;
    try
      CollectTypes(AContext.Tree.Root);
      if Types.Count > 0 then
        Visit(AContext.Tree.Root);
    finally
      Types.Free;
    end;
  end;

var
  ArgsNodes: TArray<TSyntaxNode>;
  Node: TSyntaxNode;
  HasParams: Boolean;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  ArgsNodes := nil;
  HasParams := False;
  ParamNames := TDictionary<string, Boolean>.Create;
  try
    AContext.Tree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      var
        Child: Integer;
      begin
        if ANode.Kind = TSyntaxKind.GenericArgs then
          ArgsNodes := ArgsNodes + [ANode]
        else if ANode.Kind = TSyntaxKind.GenericParams then
        begin
          HasParams := True;
          for Child := 0 to ANode.ChildCount - 1 do
            ParamNames.AddOrSetValue(LowerCase(ANode[Child].Name), True);
        end;
        Result := True;
      end);
    if (ArgsNodes = nil) and not HasParams then
      Exit;
    Cache := TRuleDerived.Open(AContext);
    FileName := AContext.FileName;
    if FileName = '' then
      FileName := AContext.RelativePath;
    if FileName = '' then
      FileName := AContext.UnitName + '.pas';
    Resolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit);
    try
      Resolver.Namespaces := AContext.Namespaces;
      Resolver.PinTree(AContext.Tree, FileName);
      try
        Local := Resolver.ExtractedUnit(AContext.Tree, FileName);
        for Node in ArgsNodes do
          CheckArguments(Node);
        if HasParams then
          CheckMethods;
      finally
        Resolver.UnpinTree;
      end;
    finally
      Resolver.Free;
    end;
  finally
    ParamNames.Free;
  end;
end;

procedure RegisterGenericRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TGenericConstraintViolatedRule.Create);
end;

end.
