unit Atlas.Common.Rules.Builtin.TypeRestrictions.TypeInfo;

// Regel aus TypeRestrictions, registriert mit RegisterTypeRestrictionRules:
//   typeinfo-invalid              TypeInfo bzw. Default mit einer Variablen
//                                 statt eines Typs (#1084, E2133, E2537;
//                                 Parameter, lokale, Inline- und Unit-
//                                 Variablen, Felder, Properties, Result;
//                                 Korrektur: Typ der Variablen einsetzen),
//                                 TypeInfo eines Typs ohne RTTI (Aufzählung
//                                 mit festen Werten, Dateityp, Text; E2134)
//                                 und Default eines Dateityps (E2538). Namen
//                                 werden von innen nach außen aufgelöst; in
//                                 with, in Helfern, in Methoden fremder Typen
//                                 und bei eigenen Routinen TypeInfo bzw.
//                                 Default bleibt die Regel still.

interface

uses
  Atlas.Common.Rules.Contract;

const
  TypeInfoInvalidRuleId = 'typeinfo-invalid';

type
  TTypeInfoInvalidRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Rules.Builtin.Inheritance,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Rules.Builtin.TypeRestrictions.Heads,
  Atlas.Common.Rules.Builtin.TypeRestrictions.Symbols;

{ TTypeInfoInvalidRule }

type
  /// <summary>Was ein Name an einer Stelle sicher ist: nichts in der Datei gefunden, Variable (auch Parameter,
  /// Feld, Property, Result), Typ, etwas anderes oder unsicher (with, Helfer, fremde Klasse, bedingte Zweige).</summary>
  TNameMeaning = (NotFound, Variable, TypeName, Other, Uncertain);

  /// <summary>Ergebnis der Auflösung: Bedeutung, Deklaration und – bei Variablen – der Typknoten oder nil.</summary>
  TNameResolution = record
    Meaning: TNameMeaning;
    Decl: TSyntaxNode;
    TypeNode: TSyntaxNode;
    class function Create(AMeaning: TNameMeaning; ADecl, ATypeNode: TSyntaxNode): TNameResolution; static;
  end;

class function TNameResolution.Create(AMeaning: TNameMeaning; ADecl, ATypeNode: TSyntaxNode): TNameResolution;
begin
  Result.Meaning := AMeaning;
  Result.Decl := ADecl;
  Result.TypeNode := ATypeNode;
end;

/// <summary>Kommt AName in der Namensliste ANames ("A,B") vor?</summary>
function InNameList(const ANames, AName: string): Boolean;
var
  Name: string;
begin
  for Name in SplitString(ANames, ',') do
  begin
    if SameText(Trim(Name), AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Erster Kindknoten, der einen Typ beschreibt (TypeReference, ArrayType …), nil ohne.</summary>
function TypeChild(ANode: TSyntaxNode): TSyntaxNode;
var
  Index: Integer;
begin
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    if ANode[Index].Kind in [TSyntaxKind.TypeReference, TSyntaxKind.ArrayType, TSyntaxKind.RecordType,
      TSyntaxKind.SetType, TSyntaxKind.EnumType, TSyntaxKind.PointerType, TSyntaxKind.FileType,
      TSyntaxKind.ProcedureType, TSyntaxKind.SubrangeType, TSyntaxKind.ClassOfType] then
    begin
      Exit(ANode[Index]);
    end;
  end;
  Result := nil;
end;

/// <summary>Sucht AName in den Deklarationsabschnitten unter AHolder (Routine, anonyme Methode, Klasse, Unit-
/// Abschnitt), nur vor ABefore (-1: alle). Variablen und Felder: Variable, Typen: TypeName, sonst Other.</summary>
function FindInSections(AHolder: TSyntaxNode; const AName: string; ABefore: Integer;
  out AResolution: TNameResolution): Boolean;
var
  Index, Inner: Integer;
  Section, Decl: TSyntaxNode;
begin
  AResolution := TNameResolution.Create(TNameMeaning.NotFound, nil, nil);
  for Index := 0 to AHolder.ChildCount - 1 do
  begin
    Section := AHolder[Index];
    if (ABefore >= 0) and (Section.StartOffset >= ABefore) then
    begin
      Break;
    end;
    case Section.Kind of
      TSyntaxKind.VarSection, TSyntaxKind.ConstSection, TSyntaxKind.TypeSection:
        for Inner := 0 to Section.ChildCount - 1 do
        begin
          Decl := Section[Inner];
          if not (Decl.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.ConstDecl, TSyntaxKind.TypeDecl]) or
            not InNameList(Decl.Name, AName) then
          begin
            Continue;
          end;
          case Decl.Kind of
            TSyntaxKind.VarDecl:
              AResolution := TNameResolution.Create(TNameMeaning.Variable, Decl, TypeChild(Decl));
            TSyntaxKind.TypeDecl:
              AResolution := TNameResolution.Create(TNameMeaning.TypeName, Decl, nil);
          else
            AResolution := TNameResolution.Create(TNameMeaning.Other, Decl, nil);
          end;
        end;
      TSyntaxKind.Field:
        if InNameList(Section.Name, AName) then
        begin
          AResolution := TNameResolution.Create(TNameMeaning.Variable, Section, TypeChild(Section));
        end;
      TSyntaxKind.PropertyDecl:
        if SameText(Section.Name, AName) then
        begin
          AResolution := TNameResolution.Create(TNameMeaning.Variable, Section, TypeChild(Section));
        end;
      TSyntaxKind.RoutineDecl, TSyntaxKind.RoutineHeader:
        if SameText(LastPart(Section.Name), AName) and (Pos('.', Section.Name) = 0) then
        begin
          AResolution := TNameResolution.Create(TNameMeaning.Other, Section, nil);
        end;
      TSyntaxKind.UsesClause:
        for Inner := 0 to Section.ChildCount - 1 do
        begin
          if SameText(LastPart(Section[Inner].Name), AName) then
          begin
            AResolution := TNameResolution.Create(TNameMeaning.Other, Section[Inner], nil);
          end;
        end;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;
  Result := AResolution.Meaning <> TNameMeaning.NotFound;
end;

/// <summary>Parameter, Typparameter und Result eines Routinenkopfs.</summary>
function FindInHeader(AHeader: TSyntaxNode; const AName: string; out AResolution: TNameResolution): Boolean;
var
  Index, Inner: Integer;
  Child: TSyntaxNode;
begin
  AResolution := TNameResolution.Create(TNameMeaning.NotFound, nil, nil);
  for Index := 0 to AHeader.ChildCount - 1 do
  begin
    Child := AHeader[Index];
    case Child.Kind of
      TSyntaxKind.Parameters:
        for Inner := 0 to Child.ChildCount - 1 do
        begin
          if (Child[Inner].Kind = TSyntaxKind.Parameter) and InNameList(Child[Inner].Name, AName) then
          begin
            AResolution := TNameResolution.Create(TNameMeaning.Variable, Child[Inner], TypeChild(Child[Inner]));
          end;
        end;
      TSyntaxKind.GenericParams:
        for Inner := 0 to Child.ChildCount - 1 do
        begin
          if SameText(Child[Inner].Name, AName) then
          begin
            AResolution := TNameResolution.Create(TNameMeaning.TypeName, Child[Inner], nil);
          end;
        end;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;
  if (AResolution.Meaning = TNameMeaning.NotFound) and SameText(AName, 'Result') and
    (AHeader.FindChild(TSyntaxKind.TypeReference) <> nil) then
  begin
    AResolution := TNameResolution.Create(TNameMeaning.Variable, AHeader, AHeader.FindChild(TSyntaxKind.TypeReference));
  end;
  Result := AResolution.Meaning <> TNameMeaning.NotFound;
end;

function TTypeInfoInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(TypeInfoInvalidRuleId, TRuleSeverity.Error,
    'TypeInfo oder Default mit unzulässigem Argument');
end;

procedure TTypeInfoInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Types: TFileTypes;
  Paths: TArray<string>;
  Calls: TList<TSyntaxNode>;
  Names: TDeclarationNames;
  Call: TSyntaxNode;

  function PathOf(ANode: TSyntaxNode): string;
  begin
    Result := TConditionalBranches.PathAt(Paths, TRoutineBody.TokenAt(Tokens, ANode.StartOffset));
  end;

  /// <summary>Mitglieder des Typs, zu dem die Methode ARoutine gehört; Uncertain, wenn der Typ nicht in der Datei
  /// steht oder ein Helfer ist. Vorfahren außerhalb der Datei bleiben unbeachtet.</summary>
  function FindInOwner(ARoutine: TSyntaxNode; const AName: string; out AResolution: TNameResolution): Boolean;
  var
    Qualifier: string;
    Index: Integer;
    Decl, Struct: TSyntaxNode;
  begin
    AResolution := TNameResolution.Create(TNameMeaning.Uncertain, nil, nil);
    Qualifier := Copy(ARoutine.Name, 1, LastDelimiter('.', ARoutine.Name) - 1);
    Index := Types.IndexOf(BareTypeName(Qualifier));
    if Index < 0 then
    begin
      Exit(True);
    end;
    Struct := Types.Types[Index];
    if not (Struct.Kind in [TSyntaxKind.ClassType, TSyntaxKind.RecordType, TSyntaxKind.ObjectType]) then
    begin
      Exit(True);
    end;
    if FindInSections(Struct, AName, -1, AResolution) then
    begin
      Exit(True);
    end;
    Decl := Struct.Parent;
    Result := (Decl <> nil) and FindInHeader(Decl, AName, AResolution);
  end;

  /// <summary>Bedeutung von AName an der Stelle ANode, von innen nach außen.</summary>
  function Resolve(ANode: TSyntaxNode; const AName: string): TNameResolution;
  var
    Node, Parent, Header: TSyntaxNode;
    Index, Position: Integer;
  begin
    Node := ANode;
    while Node.Parent <> nil do
    begin
      Parent := Node.Parent;
      case Parent.Kind of
        TSyntaxKind.WithStatement:
          if Node = Parent[Parent.ChildCount - 1] then
          begin
            Exit(TNameResolution.Create(TNameMeaning.Uncertain, nil, nil));
          end;
        TSyntaxKind.Block:
          begin
            Position := Parent.ChildCount - 1;
            while (Position >= 0) and (Parent[Position] <> Node) do
            begin
              Dec(Position);
            end;
            for Index := Position - 1 downto 0 do
            begin
              if (Parent[Index].Kind in [TSyntaxKind.InlineVar, TSyntaxKind.InlineConst]) and
                InNameList(Parent[Index].Name, AName) then
              begin
                if Parent[Index].Kind = TSyntaxKind.InlineVar then
                begin
                  Exit(TNameResolution.Create(TNameMeaning.Variable, Parent[Index], TypeChild(Parent[Index])));
                end;
                Exit(TNameResolution.Create(TNameMeaning.Other, Parent[Index], nil));
              end;
            end;
          end;
        TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.ExceptionHandler:
          if SameText(Parent.Name, AName) then
          begin
            Exit(TNameResolution.Create(TNameMeaning.Variable, Parent, TypeChild(Parent)));
          end;
        TSyntaxKind.AnonymousMethod:
          begin
            if FindInHeader(Parent, AName, Result) or FindInSections(Parent, AName, -1, Result) then
            begin
              Exit;
            end;
          end;
        TSyntaxKind.RoutineDecl:
          begin
            Header := Parent.FindChild(TSyntaxKind.RoutineHeader);
            if (Header <> nil) and FindInHeader(Header, AName, Result) then
            begin
              Exit;
            end;
            if FindInSections(Parent, AName, -1, Result) then
            begin
              Exit;
            end;
            if SameText(LastPart(Parent.Name), AName) then
            begin
              Exit(TNameResolution.Create(TNameMeaning.Other, Parent, nil));
            end;
            if (Pos('.', Parent.Name) > 0) and FindInOwner(Parent, AName, Result) then
            begin
              Exit;
            end;
          end;
        TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection:
          begin
            // Unit-Ebene: im implementation-Teil zuerst die eigenen Deklarationen davor, dann der interface-Teil.
            if FindInSections(Parent, AName, ANode.StartOffset, Result) then
            begin
              Exit;
            end;
            if (Parent.Kind = TSyntaxKind.ImplementationSection) and (Parent.Parent <> nil) then
            begin
              Header := Parent.Parent.FindChild(TSyntaxKind.InterfaceSection);
              if (Header <> nil) and FindInSections(Header, AName, -1, Result) then
              begin
                Exit;
              end;
            end;
            Exit(TNameResolution.Create(TNameMeaning.NotFound, nil, nil));
          end;
        TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile:
          begin
            if FindInSections(Parent, AName, ANode.StartOffset, Result) then
            begin
              Exit;
            end;
            Exit(TNameResolution.Create(TNameMeaning.NotFound, nil, nil));
          end;
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
      Node := Parent;
    end;
    Result := TNameResolution.Create(TNameMeaning.NotFound, nil, nil);
  end;

  /// <summary>Typknoten hinter dem Typnamen ADecl (TypeDecl), Aliase in der Datei verfolgt; nil bei unsicheren.
  /// </summary>
  function TypeBehind(ADecl: TSyntaxNode): TSyntaxNode;
  var
    Depth, Index: Integer;
  begin
    Result := TypeChild(ADecl);
    for Depth := 1 to 16 do
    begin
      if (Result = nil) or (Result.Kind <> TSyntaxKind.TypeReference) then
      begin
        Exit;
      end;
      if (Pos('.', Result.Name) > 0) or (Result.FindChild(TSyntaxKind.GenericArgs) <> nil) then
      begin
        Exit(nil);
      end;
      Index := Types.IndexOf(Result.Name);
      if Index < 0 then
      begin
        Exit;
      end;
      Result := Types.Types[Index];
    end;
    Result := nil;
  end;

  function HasExplicitValues(AEnum: TSyntaxNode): Boolean;
  var
    Index: Integer;
  begin
    for Index := 0 to AEnum.ChildCount - 1 do
    begin
      if AEnum[Index].Kind <> TSyntaxKind.Identifier then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  /// <summary>Deklariert eine Unit im Index AName auf oberster Ebene (eigene Routine Default o. ä.)?</summary>
  function DeclaredInIndex(const AName: string): Boolean;
  var
    Location: TSymbolLocation;
  begin
    if AContext.Index = nil then
    begin
      Exit(False);
    end;
    for Location in AContext.Index.FindSymbols(AName) do
    begin
      if Location.Symbol.Container = '' then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  procedure CheckCall(ACall: TSyntaxNode);
  var
    Intrinsic, Name, TypeText, Code: string;
    Argument, Behind: TSyntaxNode;
    Resolution: TNameResolution;
    Fixes: TArray<TRuleFix>;
    BuiltinFile, IsTypeInfo: Boolean;
  begin
    Intrinsic := ACall[0].Name;
    IsTypeInfo := SameText(Intrinsic, 'TypeInfo');
    Argument := ACall[1];
    if Argument.Kind <> TSyntaxKind.Identifier then
    begin
      Exit;
    end;
    Name := Argument.Name;
    Resolution := Resolve(ACall, Name);
    if (Resolution.Decl <> nil) and (Resolution.Meaning in [TNameMeaning.Variable, TNameMeaning.TypeName]) and
      not TConditionalBranches.Implies(PathOf(ACall), PathOf(Resolution.Decl)) then
    begin
      Exit;
    end;
    case Resolution.Meaning of
      TNameMeaning.Variable:
        begin
          Code := 'E2537';
          if IsTypeInfo then
          begin
            Code := 'E2133';
          end;
          Fixes := nil;
          TypeText := '';
          if (Resolution.TypeNode <> nil) and (Resolution.TypeNode.Kind = TSyntaxKind.TypeReference) then
          begin
            TypeText := OneLine(AContext.Text, Resolution.TypeNode);
          end;
          if TypeText <> '' then
          begin
            Fixes := [TRuleFix.Create(Format('%s(%s) einsetzen', [Intrinsic, TypeText]),
              [TRuleEdit.Create(NodeRange(Argument), TypeText)])];
            AReport.Add(NodeRange(Argument), Format('%s erwartet einen Typ, %s ist eine Variable; gemeint ist ' +
              '%s(%s) (wie %s).', [Intrinsic, Name, Intrinsic, TypeText, Code]), TRuleConfidence.High, Fixes);
          end
          else
          begin
            AReport.Add(NodeRange(Argument), Format('%s erwartet einen Typ, %s ist eine Variable (wie %s).',
              [Intrinsic, Name, Code]), TRuleConfidence.High, nil);
          end;
        end;
      TNameMeaning.NotFound, TNameMeaning.TypeName:
        begin
          Behind := nil;
          BuiltinFile := False;
          if Resolution.Meaning = TNameMeaning.TypeName then
          begin
            if Resolution.Decl.Kind <> TSyntaxKind.TypeDecl then
            begin
              Exit;
            end;
            Behind := TypeBehind(Resolution.Decl);
            if Behind = nil then
            begin
              Exit;
            end;
          end
          else
          begin
            // Text, TextFile und file aus System; eine gleichnamige Deklaration der Datei macht still.
            if Names.Declared(Name) or (Types.IndexOf(Name) >= 0) then
            begin
              Exit;
            end;
            BuiltinFile := MatchText(Name, ['Text', 'TextFile']) or (not IsTypeInfo and SameText(Name, 'File'));
            if not BuiltinFile then
            begin
              Exit;
            end;
          end;
          if BuiltinFile or (Behind.Kind = TSyntaxKind.FileType) then
          begin
            if IsTypeInfo then
            begin
              AReport.Add(NodeRange(Argument), Format('%s hat keine Typinformation: Dateitypen erzeugen keine ' +
                'RTTI (wie E2134).', [Name]), TRuleConfidence.High, nil);
            end
            else if (ACall.Parent <> nil) and (ACall.Parent.Kind = TSyntaxKind.AssignStatement) and
              (ACall.Parent.ChildCount > 1) and (ACall.Parent[1] = ACall) then
            begin
              // Die Zuweisung an eine Dateivariable meldet dcc zusätzlich als E2015.
              AReport.Add(NodeRange(Argument), Format('Default ist für den Dateityp %s nicht erlaubt, und ' +
                'Dateivariablen lassen sich nicht zuweisen (wie E2538 und E2015).', [Name]),
                TRuleConfidence.High, nil);
            end
            else
            begin
              AReport.Add(NodeRange(Argument), Format('Default ist für den Dateityp %s nicht erlaubt (wie E2538).',
                [Name]), TRuleConfidence.High, nil);
            end;
          end
          else if IsTypeInfo and (Behind.Kind = TSyntaxKind.EnumType) and HasExplicitValues(Behind) then
          begin
            AReport.Add(NodeRange(Argument), Format('%s hat keine Typinformation: Aufzählungen mit festen Werten ' +
              'erzeugen keine RTTI (wie E2134).', [Name]), TRuleConfidence.High, nil);
          end;
        end;
      TNameMeaning.Other: ;
      TNameMeaning.Uncertain: ;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or
    not (ContainsText(AContext.Text, 'TypeInfo') or ContainsText(AContext.Text, 'Default')) then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Types := TFileTypes.Collect(AContext.Tree.Root);
  Paths := TConditionalBranches.Paths(Tokens);
  Names := nil;
  Calls := TList<TSyntaxNode>.Create;
  try
    AContext.Tree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := True;
        if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount = 2) and
          (ANode[0].Kind = TSyntaxKind.Identifier) and MatchText(ANode[0].Name, ['TypeInfo', 'Default']) then
        begin
          Calls.Add(ANode);
        end;
      end);
    if Calls.Count = 0 then
    begin
      Exit;
    end;
    Names := TDeclarationNames.Create(AContext.Tree.Root);
    for Call in Calls do
    begin
      // Eine eigene Routine TypeInfo bzw. Default (Datei oder Index) verdeckt die des Compilers.
      if not Names.Declared(Call[0].Name) and not DeclaredInIndex(Call[0].Name) then
      begin
        CheckCall(Call);
      end;
    end;
  finally
    Names.Free;
    Calls.Free;
  end;
end;

end.
