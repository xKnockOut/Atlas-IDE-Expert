unit Atlas.Common.Rules.Builtin.TypeDeclarations;

// Regeln zur Deklaration von Klassen- und Interface-Mitgliedern (#909, Gruppe
// Compiler vorab):
//   message-method-invalid
//                        message-Methode einer Klasse (#1070): nicht genau ein
//                        var-Parameter (wie E2138), Nachrichtennummer kleiner
//                        als 1 (wie E2139) oder dieselbe Nummer wie eine
//                        frühere message-Methode derselben Klasse (wie E2140).
//                        Gleich heißt: gleicher Wert über die Konstantenwerte
//                        (Semantics.ConstantValues) oder gleicher Ausdruck.
//                        Methoden in sich ausschließenden {$IF}-Zweigen
//                        (Pascal.ConditionalBranches) gelten nicht als doppelt.
//                        Korrektur für E2138: einen einzelnen Parameter zu
//                        var machen, sonst die Liste durch (var Msg: TMessage)
//                        ersetzen; der Rumpf in derselben Datei wird mit
//                        angepasst.
//   interface-declaration-invalid
//                        unzulässige Deklarationen in Interfaces (#1075):
//                        Felder (wie E2209), Sichtbarkeitsabschnitte und
//                        Direktiven wie virtual (wie E2210), Klauseln stored,
//                        default mit Wert und nodefault an Properties (wie
//                        E2207), Properties, die ein Vorfahr-Interface schon
//                        deklariert (wie E2206), Accessoren, die nur im
//                        Vorfahr-Interface stehen (wie E2370), Klassen,
//                        Records und Aufzählungen als Vorfahr eines Interfaces
//                        oder in der Interface-Liste einer Klasse (wie E2205)
//                        und doppelte Einträge dieser Liste (wie E2208).
//                        Typen löst TNameResolver über die uses-Klauseln auf;
//                        Aliase, unbekannte Typen, dispinterface und
//                        Deklarationen in bedingten Zweigen bleiben still.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  MessageMethodInvalidRuleId = 'message-method-invalid';
  InterfaceDeclarationInvalidRuleId = 'interface-declaration-invalid';

type
  TMessageMethodInvalidRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TInterfaceDeclarationInvalidRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterTypeDeclarationRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.ConstantValues;

const
  // Knoten, unter denen Klassendeklarationen stehen können (Anweisungen bleiben außen vor).
  DeclarationKinds = [TSyntaxKind.UnitFile, TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile,
    TSyntaxKind.PackageFile, TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection,
    TSyntaxKind.TypeSection, TSyntaxKind.TypeDecl, TSyntaxKind.ClassType, TSyntaxKind.Visibility];
  DefaultMessageParameter = '(var Msg: TMessage)';
  // Direktiven, die an Methoden eines Interfaces nicht erlaubt sind (E2210).
  InterfaceForbiddenDirectives: array[0..5] of string = ('virtual', 'dynamic', 'abstract', 'override', 'message',
    'reintroduce');
  // Typen, die sicher kein Interface sind (E2205); Aliase können auf ein Interface zeigen.
  NonInterfaceKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.EnumType];

type
  /// <summary>Eine message-Methode einer Klasse.</summary>
  TMessageMethod = record
    ClassName: string;
    Header: TSyntaxNode;
    Directive: TSyntaxNode;
    /// <summary>Token des Ausdrucks hinter "message"; First > Last ohne Ausdruck.</summary>
    First: Integer;
    Last: Integer;
  end;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

{ TMessageMethodInvalidRule }

function TMessageMethodInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(MessageMethodInvalidRuleId, TRuleSeverity.Error,
    'message-Methode falsch deklariert');
end;

procedure TMessageMethodInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Methods: TList<TMessageMethod>;
  Paths: TArray<string>;
  FileName: string;

  function FirstToken(ANode: TSyntaxNode): Integer;
  begin
    Result := TConstantValues.TokenFrom(Tokens, ANode.StartOffset);
  end;

  function NextCode(AIndex, AStop: Integer): Integer;
  begin
    Result := AIndex;
    while (Result < AStop) and IsTrivia(Tokens[Result]) do
      Inc(Result);
  end;

  procedure Collect(ANode: TSyntaxNode; const AOwner: string);
  var
    Index, Inner, Stop: Integer;
    Name: string;
    Header, Directive: TSyntaxNode;
    Method: TMessageMethod;
  begin
    Name := AOwner;
    if ANode.Kind = TSyntaxKind.TypeDecl then
    begin
      if AOwner = '' then
        Name := ANode.Name
      else
        Name := AOwner + '.' + ANode.Name;
    end;
    if ANode.Kind = TSyntaxKind.ClassType then
      for Index := 0 to ANode.ChildCount - 1 do
      begin
        Header := ANode[Index];
        if Header.Kind <> TSyntaxKind.RoutineHeader then
          Continue;
        Directive := nil;
        for Inner := 0 to Header.ChildCount - 1 do
          if (Header[Inner].Kind = TSyntaxKind.Directive) and (Header[Inner].Name = 'message') then
            Directive := Header[Inner];
        if Directive = nil then
          Continue;
        Method := Default(TMessageMethod);
        Method.ClassName := Name;
        Method.Header := Header;
        Method.Directive := Directive;
        Stop := TConstantValues.TokenFrom(Tokens, Directive.EndOffset);
        Method.First := NextCode(FirstToken(Directive) + 1, Stop);
        Method.Last := Stop - 1;
        while (Method.Last >= Method.First) and IsTrivia(Tokens[Method.Last]) do
          Dec(Method.Last);
        Methods.Add(Method);
      end;
    for Index := 0 to ANode.ChildCount - 1 do
      if ANode[Index].Kind in DeclarationKinds then
        Collect(ANode[Index], Name);
  end;

  /// <summary>Name der Methode im Kopf (Token hinter procedure/function).</summary>
  function NameRange(AHeader: TSyntaxNode): TTextRange;
  var
    Index, Stop: Integer;
  begin
    Result := TTextRange.Create(AHeader.StartPos, AHeader.EndPos);
    Stop := TConstantValues.TokenFrom(Tokens, AHeader.EndOffset);
    for Index := FirstToken(AHeader) to Stop - 1 do
      if Tokens[Index].Kind = TPascalTokenKind.Identifier then
        Exit(TTextRange.Create(Tokens[Index].StartPos, Tokens[Index].EndPos));
  end;

  function ExpressionText(const AMethod: TMessageMethod): string;
  var
    Index: Integer;
  begin
    Result := '';
    for Index := AMethod.First to AMethod.Last do
      if not IsTrivia(Tokens[Index]) then
      begin
        if (Result <> '') and (Tokens[Index - 1].Offset + Length(Tokens[Index - 1].Text) <> Tokens[Index].Offset) then
          Result := Result + ' ';
        Result := Result + Tokens[Index].Text;
      end;
  end;

  function MethodName(AHeader: TSyntaxNode): string;
  var
    Dot: Integer;
  begin
    Result := AHeader.Name;
    Dot := LastDelimiter('.', Result);
    if Dot > 0 then
      Result := Copy(Result, Dot + 1, MaxInt);
  end;

  /// <summary>Einziger Parameter ohne var: nur den Modifizierer ändern.</summary>
  function SingleParameter(AHeader: TSyntaxNode; out AParam: TSyntaxNode): Boolean;
  var
    Params: TSyntaxNode;
  begin
    AParam := nil;
    Params := AHeader.FindChild(TSyntaxKind.Parameters);
    Result := (Params <> nil) and (Params.ChildCount = 1) and (Pos(',', Params[0].Name) = 0) and
      (Params[0].FindChild(TSyntaxKind.Attribute) = nil);
    if Result then
      AParam := Params[0];
  end;

  function ParameterEdits(AHeader: TSyntaxNode; out AEdits: TArray<TTextEdit>): Boolean;
  var
    Param, Params: TSyntaxNode;
    Index: Integer;
    Position: TTextPosition;
  begin
    AEdits := nil;
    Result := True;
    if SingleParameter(AHeader, Param) then
    begin
      Index := FirstToken(Param);
      if Param.Modifier = TParameterModifier.None then
        AEdits := [TTextEdit.Create(TTextRange.Create(Tokens[Index].StartPos, Tokens[Index].StartPos), 'var ')]
      else
        AEdits := [TTextEdit.Create(TTextRange.Create(Tokens[Index].StartPos, Tokens[Index].EndPos), 'var')];
      Exit;
    end;
    Params := AHeader.FindChild(TSyntaxKind.Parameters);
    if Params <> nil then
      AEdits := [TTextEdit.Create(TTextRange.Create(Params.StartPos, Params.EndPos), DefaultMessageParameter)]
    else
    begin
      // Ohne Klammern: direkt hinter dem Namen einfügen.
      Position := NameRange(AHeader).EndPos;
      AEdits := [TTextEdit.Create(TTextRange.Create(Position, Position), DefaultMessageParameter)];
    end;
  end;

  /// <summary>Rumpf ClassName.Methode in der Datei; nil ohne oder bei mehreren.</summary>
  function Body(const AMethod: TMessageMethod): TSyntaxNode;
  var
    Section: TSyntaxNode;
    Index: Integer;
    Wanted: string;
    Many: Boolean;
  begin
    Result := nil;
    Many := False;
    Wanted := AMethod.ClassName + '.' + MethodName(AMethod.Header);
    Section := AContext.Tree.Root.FindChild(TSyntaxKind.ImplementationSection);
    if Section = nil then
      Section := AContext.Tree.Root;
    for Index := 0 to Section.ChildCount - 1 do
      if (Section[Index].Kind = TSyntaxKind.RoutineDecl) and SameText(Section[Index].Name, Wanted) then
      begin
        Many := Result <> nil;
        Result := Section[Index];
      end;
    if Many then
      Result := nil;
  end;

  function SignatureFix(const AMethod: TMessageMethod): TArray<TRuleFix>;
  var
    Edits, BodyEdits: TArray<TTextEdit>;
    Decl, Header: TSyntaxNode;
    Param: TSyntaxNode;
  begin
    Result := nil;
    if not ParameterEdits(AMethod.Header, Edits) then
      Exit;
    Decl := Body(AMethod);
    if Decl <> nil then
    begin
      Header := Decl.FindChild(TSyntaxKind.RoutineHeader);
      // Rumpf ohne Parameterliste darf so bleiben; sonst gleich anpassen.
      if (Header <> nil) and (Header.FindChild(TSyntaxKind.Parameters) <> nil) then
      begin
        if SingleParameter(AMethod.Header, Param) <> SingleParameter(Header, Param) then
          Exit;
        if ParameterEdits(Header, BodyEdits) then
          Edits := Edits + BodyEdits;
      end;
    end;
    if SingleParameter(AMethod.Header, Param) then
      Result := [TRuleFix.Create(Format('Parameter %s als var übergeben', [Param.Name]), Edits)]
    else
      Result := [TRuleFix.Create(Format('Signatur %s einsetzen', [DefaultMessageParameter]), Edits)];
  end;

  procedure CheckParameters(const AMethod: TMessageMethod);
  var
    Params: TSyntaxNode;
    Keyword: string;
    Index: Integer;
  begin
    // Nur Prozeduren: message an Funktionen ist ein anderer Fall.
    Index := NextCode(FirstToken(AMethod.Header), Length(Tokens));
    if (Index < Length(Tokens)) and Tokens[Index].IsKeyword('class') then
      Exit;
    if Index >= Length(Tokens) then
      Exit;
    Keyword := LowerCase(Tokens[Index].Text);
    if Keyword <> 'procedure' then
      Exit;
    Params := AMethod.Header.FindChild(TSyntaxKind.Parameters);
    if (Params <> nil) and (Params.ChildCount = 1) and (Pos(',', Params[0].Name) = 0) and
      (Params[0].Modifier = TParameterModifier.VarParam) then
      Exit;
    AReport.Add(NameRange(AMethod.Header), Format('Die message-Methode %s braucht genau einen var-Parameter ' +
      '(wie E2138).', [MethodName(AMethod.Header)]), TRuleConfidence.High, SignatureFix(AMethod));
  end;

  function PathOf(const AMethod: TMessageMethod): string;
  begin
    Result := TConditionalBranches.PathAt(Paths, FirstToken(AMethod.Header));
  end;

  procedure CheckNumbers;
  var
    Resolver: TNameResolver;
    Values: TConstantValues;
    Keys: TArray<string>;
    Known: TArray<Boolean>;
    Index, Earlier: Integer;
    Value: Int64;
    Method: TMessageMethod;
    Range: TTextRange;
  begin
    SetLength(Keys, Methods.Count);
    SetLength(Known, Methods.Count);
    Resolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit);
    try
      Resolver.Namespaces := AContext.Namespaces;
      Resolver.PinTree(AContext.Tree, FileName);
      Values := TConstantValues.Create(AContext.Tree, FileName, AContext.Index, Resolver);
      try
        for Index := 0 to Methods.Count - 1 do
        begin
          Method := Methods[Index];
          if Method.First > Method.Last then
            Continue;
          Range := TTextRange.Create(Tokens[Method.First].StartPos, Tokens[Method.Last].EndPos);
          if Values.Evaluate(Method.First, Method.Last, Value) then
          begin
            Keys[Index] := 'v' + IntToStr(Value);
            if Value < 1 then
            begin
              AReport.Add(Range, Format('Die Nachrichtennummer %s von %s muss mindestens 1 sein (wie E2139).',
                [ExpressionText(Method), MethodName(Method.Header)]), TRuleConfidence.High);
              Continue;
            end;
          end
          else
            Keys[Index] := 't' + UpperCase(ExpressionText(Method).Replace(' ', ''));
          Known[Index] := True;
          for Earlier := 0 to Index - 1 do
            if Known[Earlier] and SameText(Methods[Earlier].ClassName, Method.ClassName) and
              (Keys[Earlier] = Keys[Index]) and
              not TConditionalBranches.Exclusive(PathOf(Methods[Earlier]), PathOf(Method)) then
            begin
              AReport.Add(Range, Format('%s wird schon von %s behandelt (wie E2140).', [ExpressionText(Method),
                MethodName(Methods[Earlier].Header)]), TRuleConfidence.High);
              Break;
            end;
        end;
      finally
        Values.Free;
      end;
    finally
      Resolver.UnpinTree;
      Resolver.Free;
    end;
  end;

var
  Method: TMessageMethod;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Tokens := AContext.Tree.Tokens;
  FileName := AContext.FileName;
  if FileName = '' then
    FileName := AContext.RelativePath;
  if FileName = '' then
    FileName := AContext.UnitName + '.pas';
  Methods := TList<TMessageMethod>.Create;
  try
    Collect(AContext.Tree.Root, '');
    if Methods.Count = 0 then
      Exit;
    Paths := TConditionalBranches.Paths(Tokens);
    for Method in Methods do
      CheckParameters(Method);
    CheckNumbers;
  finally
    Methods.Free;
  end;
end;

{ TInterfaceDeclarationInvalidRule }

function TInterfaceDeclarationInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(InterfaceDeclarationInvalidRuleId, TRuleSeverity.Error,
    'Unzulässige Deklaration in einem Interface');
end;

procedure TInterfaceDeclarationInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Paths: TArray<string>;
  FileName: string;
  Resolver: TNameResolver;
  OwnUnit: TUnitIndex;

  function FirstToken(ANode: TSyntaxNode): Integer;
  begin
    Result := TConstantValues.TokenFrom(Tokens, ANode.StartOffset);
  end;

  function StopToken(ANode: TSyntaxNode): Integer;
  begin
    Result := TConstantValues.TokenFrom(Tokens, ANode.EndOffset);
  end;

  /// <summary>Steht ANode außerhalb jeder bedingten Übersetzung?</summary>
  function Unconditional(ANode: TSyntaxNode): Boolean;
  begin
    Result := TConditionalBranches.PathAt(Paths, FirstToken(ANode)) = '';
  end;

  function TokenRange(AIndex: Integer): TTextRange;
  begin
    Result := TTextRange.Create(Tokens[AIndex].StartPos, Tokens[AIndex].EndPos);
  end;

  function FirstRange(ANode: TSyntaxNode): TTextRange;
  begin
    Result := TokenRange(FirstToken(ANode));
  end;

  /// <summary>Text des Knotens ohne Leerraum, Groß-/Kleinschreibung und Unit-Präfix (E2208).</summary>
  function TypeKey(ANode: TSyntaxNode): string;
  var
    Index, Angle: Integer;
    Head: string;
  begin
    Result := '';
    for Index := FirstToken(ANode) to StopToken(ANode) - 1 do
      if not IsTrivia(Tokens[Index]) then
        Result := Result + UpperCase(Tokens[Index].Text);
    Angle := Pos('<', Result);
    if Angle = 0 then
      Angle := Length(Result) + 1;
    Head := Copy(Result, 1, Angle - 1);
    Result := Copy(Head, LastDelimiter('.', Head) + 1, MaxInt) + Copy(Result, Angle, MaxInt);
  end;

  /// <summary>Löst ANode (TypeReference) sicher zu einer Klasse, einem Record oder einer Aufzählung auf?</summary>
  function NotAnInterface(ANode: TSyntaxNode; out AKind: string): Boolean;
  var
    Resolved: TResolvedSymbol;
  begin
    AKind := '';
    Result := (ANode.Name <> '') and Resolver.ResolveTypeFrom(OwnUnit, ANode.Name, Resolved) and
      Resolved.Found and not Resolved.Builtin and (Resolved.SymbolKind in NonInterfaceKinds);
    if not Result then
      Exit;
    case Resolved.SymbolKind of
      TIndexSymbolKind.RecordType:
        AKind := 'ein Record';
      TIndexSymbolKind.EnumType:
        AKind := 'eine Aufzählung';
    else
      AKind := 'eine Klasse';
    end;
  end;

  procedure ReportNotInterface(ANode: TSyntaxNode);
  var
    Kind: string;
  begin
    if Unconditional(ANode) and NotAnInterface(ANode, Kind) then
      AReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), Format('%s ist %s und kein Interface ' +
        '(wie E2205).', [ANode.Name, Kind]), TRuleConfidence.High);
  end;

  procedure CheckClassList(AClass: TSyntaxNode);
  var
    Index, Earlier, Position: Integer;
    References: TArray<TSyntaxNode>;
  begin
    References := nil;
    for Index := 0 to AClass.ChildCount - 1 do
      if AClass[Index].Kind = TSyntaxKind.TypeReference then
        References := References + [AClass[Index]]
      else
        Break;
    for Position := 1 to High(References) do
    begin
      ReportNotInterface(References[Position]);
      for Earlier := 0 to Position - 1 do
        if (TypeKey(References[Earlier]) = TypeKey(References[Position])) and
          Unconditional(References[Position]) then
        begin
          AReport.Add(TTextRange.Create(References[Position].StartPos, References[Position].EndPos),
            Format('%s steht schon in der Liste der Interfaces (wie E2208).', [References[Position].Name]),
            TRuleConfidence.High);
          Break;
        end;
    end;
  end;

  function IsDispInterface(AType: TSyntaxNode): Boolean;
  var
    Index: Integer;
  begin
    Index := FirstToken(AType);
    while (Index < Length(Tokens)) and IsTrivia(Tokens[Index]) do
      Inc(Index);
    Result := (Index < Length(Tokens)) and SameText(Tokens[Index].Text, 'dispinterface');
  end;

  /// <summary>Klauseln stored, nodefault und default mit Wert vor dem ersten Semikolon der Property.</summary>
  procedure CheckPropertyClauses(AProperty: TSyntaxNode);
  var
    Index, Stop, Depth, Next: Integer;
    Word: string;
  begin
    Stop := StopToken(AProperty);
    Depth := 0;
    // Ab dem Namen: eine Property namens Default ist erlaubt.
    Index := FirstToken(AProperty);
    while (Index < Stop) and not ((Tokens[Index].Kind = TPascalTokenKind.Identifier) and
      SameText(Tokens[Index].Text, AProperty.Name)) do
      Inc(Index);
    Inc(Index);
    while Index < Stop do
    begin
      if Tokens[Index].IsSymbol('[') or Tokens[Index].IsSymbol('(') then
        Inc(Depth)
      else if Tokens[Index].IsSymbol(']') or Tokens[Index].IsSymbol(')') then
        Dec(Depth)
      else if (Depth = 0) and Tokens[Index].IsSymbol(';') then
        Break
      else if (Depth = 0) and (Tokens[Index].Kind = TPascalTokenKind.Identifier) then
      begin
        Word := LowerCase(Tokens[Index].Text);
        Next := Index + 1;
        while (Next < Stop) and IsTrivia(Tokens[Next]) do
          Inc(Next);
        if (Word = 'stored') or (Word = 'nodefault') or
          ((Word = 'default') and (Next < Stop) and not Tokens[Next].IsSymbol(';')) then
          AReport.Add(TokenRange(Index), Format('Die Klausel %s ist in Interfaces nicht erlaubt (wie E2207).',
            [Word]), TRuleConfidence.High);
      end;
      Inc(Index);
    end;
  end;

  /// <summary>Name der Property (erster Bezeichner nach property).</summary>
  function PropertyName(AProperty: TSyntaxNode): TTextRange;
  var
    Index, Stop: Integer;
  begin
    Result := TTextRange.Create(AProperty.StartPos, AProperty.EndPos);
    Stop := StopToken(AProperty);
    for Index := FirstToken(AProperty) to Stop - 1 do
      if (Tokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[Index].Text, AProperty.Name) then
        Exit(TokenRange(Index));
  end;

  /// <summary>read- und write-Accessor der Property (Namen vor dem ersten Semikolon).</summary>
  function Accessors(AProperty: TSyntaxNode): TArray<Integer>;
  var
    Index, Stop, Next: Integer;
  begin
    Result := nil;
    Stop := StopToken(AProperty);
    for Index := FirstToken(AProperty) to Stop - 1 do
    begin
      if Tokens[Index].IsSymbol(';') then
        Break;
      if (Tokens[Index].Kind = TPascalTokenKind.Identifier) and MatchText(Tokens[Index].Text, ['read', 'write']) then
      begin
        Next := Index + 1;
        while (Next < Stop) and IsTrivia(Tokens[Next]) do
          Inc(Next);
        if (Next < Stop) and (Tokens[Next].Kind = TPascalTokenKind.Identifier) then
          Result := Result + [Next];
      end;
    end;
  end;

  procedure CheckInheritedMembers(AType: TSyntaxNode; const AName: string);
  var
    Own, Ancestor, Member: TResolvedSymbol;
    Index, Accessor: Integer;
    Methods: TArray<string>;
    Child: TSyntaxNode;
  begin
    if not Resolver.ResolveTypeFrom(OwnUnit, AName, Own) or not Own.Found or
      (Own.SymbolKind <> TIndexSymbolKind.InterfaceType) or not Resolver.AncestorOf(Own, Ancestor) then
      Exit;
    Methods := nil;
    for Index := 0 to AType.ChildCount - 1 do
      if AType[Index].Kind = TSyntaxKind.RoutineHeader then
        Methods := Methods + [AType[Index].Name];
    for Index := 0 to AType.ChildCount - 1 do
    begin
      Child := AType[Index];
      if (Child.Kind <> TSyntaxKind.PropertyDecl) or not Unconditional(Child) then
        Continue;
      if Resolver.DeclaredMember(Ancestor, Child.Name, Member) and
        (Member.SymbolKind = TIndexSymbolKind.Property_) then
        AReport.Add(PropertyName(Child), Format('Die Property %s ist schon in %s ' +
          'deklariert; Interfaces dürfen Properties nicht überschreiben (wie E2206).', [Child.Name,
          Member.Container]), TRuleConfidence.High);
      for Accessor in Accessors(Child) do
      begin
        if MatchText(Tokens[Accessor].Text, Methods) then
          Continue;
        if Resolver.DeclaredMember(Ancestor, Tokens[Accessor].Text, Member) and
          (Member.SymbolKind = TIndexSymbolKind.Method) then
          AReport.Add(TokenRange(Accessor), Format('%s stammt aus %s; Accessoren einer Interface-Property ' +
            'müssen im Interface selbst stehen (wie E2370).', [Tokens[Accessor].Text, Member.Container]),
            TRuleConfidence.High);
      end;
    end;
  end;

  procedure CheckInterface(AType: TSyntaxNode; const AName: string);
  var
    Index, Inner: Integer;
    Child: TSyntaxNode;
    First: Boolean;
  begin
    if IsDispInterface(AType) then
      Exit;
    First := True;
    for Index := 0 to AType.ChildCount - 1 do
    begin
      Child := AType[Index];
      if (Child.Kind = TSyntaxKind.TypeReference) and First then
        ReportNotInterface(Child);
      First := False;
      if not Unconditional(Child) then
        Continue;
      case Child.Kind of
        TSyntaxKind.Field:
          AReport.Add(FirstRange(Child), 'Interfaces dürfen keine Felder haben (wie E2209).', TRuleConfidence.High);
        TSyntaxKind.VarSection:
          for Inner := 0 to Child.ChildCount - 1 do
            if Child[Inner].Kind = TSyntaxKind.VarDecl then
              AReport.Add(FirstRange(Child[Inner]), 'Interfaces dürfen keine Felder haben (wie E2209).',
                TRuleConfidence.High);
        TSyntaxKind.Visibility:
          AReport.Add(TTextRange.Create(Child.StartPos, Child.EndPos), Format('Die Direktive %s ist in ' +
            'Interfaces nicht erlaubt (wie E2210).', [Child.Name]), TRuleConfidence.High);
        TSyntaxKind.RoutineHeader:
          for Inner := 0 to Child.ChildCount - 1 do
            if (Child[Inner].Kind = TSyntaxKind.Directive) and
              MatchText(Child[Inner].Name, InterfaceForbiddenDirectives) then
              AReport.Add(FirstRange(Child[Inner]), Format('Die Direktive %s ist in Interfaces nicht erlaubt ' +
                '(wie E2210).', [Child[Inner].Name]), TRuleConfidence.High);
        TSyntaxKind.PropertyDecl:
          CheckPropertyClauses(Child);
      end;
    end;
    CheckInheritedMembers(AType, AName);
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Index: Integer;
    Body: TSyntaxNode;
  begin
    if ANode.Kind = TSyntaxKind.TypeDecl then
    begin
      Body := ANode.FindChild(TSyntaxKind.InterfaceType);
      if Body <> nil then
        CheckInterface(Body, ANode.Name);
      Body := ANode.FindChild(TSyntaxKind.ClassType);
      if Body <> nil then
        CheckClassList(Body);
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      if ANode[Index].Kind in DeclarationKinds then
        Visit(ANode[Index]);
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Tokens := AContext.Tree.Tokens;
  FileName := AContext.FileName;
  if FileName = '' then
    FileName := AContext.RelativePath;
  if FileName = '' then
    FileName := AContext.UnitName + '.pas';
  Paths := TConditionalBranches.Paths(Tokens);
  Resolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit);
  try
    Resolver.Namespaces := AContext.Namespaces;
    Resolver.PinTree(AContext.Tree, FileName);
    try
      OwnUnit := Resolver.ExtractedUnit(AContext.Tree, FileName);
      Visit(AContext.Tree.Root);
    finally
      Resolver.UnpinTree;
    end;
  finally
    Resolver.Free;
  end;
end;

procedure RegisterTypeDeclarationRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TMessageMethodInvalidRule.Create);
  ARegistry.Register(TInterfaceDeclarationInvalidRule.Create);
end;

end.
