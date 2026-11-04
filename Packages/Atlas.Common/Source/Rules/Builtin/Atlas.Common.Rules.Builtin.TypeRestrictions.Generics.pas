unit Atlas.Common.Rules.Builtin.TypeRestrictions.Generics;

// Regel aus TypeRestrictions, registriert mit RegisterTypeRestrictionRules:
//   generic-declaration-invalid   Generics, die Delphi ablehnt (#1029):
//                                 Einschränkungen class und record zugleich
//                                 (E2507), doppelt (E2603), widersprüchlich
//                                 (record und constructor, E2516), Klasse
//                                 neben class/record (E2552), zwei Klassen
//                                 (E2553), ungültiger Typ (E2510);
//                                 Typparameter an Aufzählung, Menge, Zeiger,
//                                 Alias, Helfer (E2508), Konstruktor,
//                                 Destruktor oder Klassenkonstruktor
//                                 (E2528, Konstruktoren nur in Klassen),
//                                 Operator
//                                 (E2529), globaler Routine (E2530),
//                                 virtueller Methode (E2533), Interface-
//                                 Methode (E2535); class of eines
//                                 parametrisierten Typs (E2548), generische
//                                 Attributklasse (E2549) und parametrisierter
//                                 Typ als Attribut (E2565); Typparameter, der
//                                 einen des umgebenden Typs verdeckt (H2509);
//                                 Aufruf mit einer Zahl Typargumente, die
//                                 keine Variante hat (E2551); Methoden
//                                 generischer Typen aus dem interface-Teil,
//                                 die Symbole des implementation-Teils
//                                 verwenden (E2506, still bei Vorfahren
//                                 außerhalb von Datei und Index und in with);
//                                 lokale Routinen in generischen Methoden und
//                                 Methoden generischer Typen (E2570, #1376);
//                                 type vor einem instanziierten Typ (type
//                                 TListe<Integer>, E2574, Korrektur: type
//                                 entfernen). Klassen als Einschränkung
//                                 (E2552, E2553) erkennt die Regel in der
//                                 Datei, eingebaut (TObject) und über den
//                                 Index (TStream aus System.Classes, #1376).

interface

uses
  Atlas.Common.Rules.Contract;

const
  GenericDeclarationInvalidRuleId = 'generic-declaration-invalid';

type
  TGenericDeclarationInvalidRule = class(TInterfacedObject, IRule)
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
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Builtin.Inheritance,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Rules.Builtin.TypeRestrictions.Heads,
  Atlas.Common.Rules.Builtin.TypeRestrictions.Symbols;

{ TGenericDeclarationInvalidRule }

type
  /// <summary>Eine Einschränkung aus einer Typparameterliste (generic-declaration-invalid, #1029).</summary>
  TGenericConstraint = record
    Text: string;
    Range: TTextRange;
  end;

{$SCOPEDENUMS ON}
  /// <summary>Art einer Einschränkung; Unknown, wenn der Typ nicht sicher bekannt ist.</summary>
  TConstraintKind = (Unknown, ClassKeyword, RecordKeyword, ConstructorKeyword, ClassType, InterfaceType, Invalid);
{$SCOPEDENUMS OFF}

const
  // Typarten, die als Typ mit Typparametern nicht erlaubt sind (E2508).
  NonGenericTypeKinds = [TSyntaxKind.EnumType, TSyntaxKind.SetType, TSyntaxKind.SubrangeType,
    TSyntaxKind.PointerType, TSyntaxKind.ClassOfType, TSyntaxKind.FileType, TSyntaxKind.TypeReference,
    TSyntaxKind.HelperType];
  // Typarten, die keine gültige Einschränkung sind (E2510).
  InvalidConstraintKinds = [TSyntaxKind.RecordType, TSyntaxKind.EnumType, TSyntaxKind.SetType,
    TSyntaxKind.ArrayType, TSyntaxKind.PointerType, TSyntaxKind.ProcedureType, TSyntaxKind.SubrangeType,
    TSyntaxKind.FileType, TSyntaxKind.ClassOfType, TSyntaxKind.HelperType];
  // Direktiven, die eine Methode virtuell machen (E2533).
  VirtualDirectives: array[0..3] of string = ('virtual', 'dynamic', 'message', 'override');
/// <summary>Namen der Typparameter (Identifier-Kinder) von AParams.</summary>
function TypeParamNames(AParams: TSyntaxNode): TArray<string>;
var
  Index: Integer;
begin
  Result := nil;
  if AParams = nil then
  begin
    Exit;
  end;
  for Index := 0 to AParams.ChildCount - 1 do
  begin
    if AParams[Index].Kind = TSyntaxKind.Identifier then
    begin
      Result := Result + [AParams[Index].Name];
    end;
  end;
end;

/// <summary>Eigene Typparameter des Kopfs: bei TFoo&lt;T&gt;.Bar&lt;U&gt; die von Bar, nil ohne.</summary>
function OwnGenericParams(const ATokens: TArray<TPascalToken>; AHeader: TSyntaxNode): TSyntaxNode;
var
  Dots, Component, Depth, Index, Seen, Own, Child: Integer;
begin
  Result := nil;
  if (AHeader.Parent = nil) or (AHeader.Parent.Kind <> TSyntaxKind.RoutineDecl) or (Pos('.', AHeader.Name) = 0) then
  begin
    Exit(AHeader.FindChild(TSyntaxKind.GenericParams));
  end;
  Dots := Length(AHeader.Name) - Length(StringReplace(AHeader.Name, '.', '', [rfReplaceAll]));
  Component := 0;
  Depth := 0;
  Seen := -1;
  Own := -1;
  Index := TRoutineBody.TokenAt(ATokens, AHeader.StartOffset);
  while (Index >= 0) and (Index < Length(ATokens)) and (ATokens[Index].Offset < AHeader.EndOffset) do
  begin
    if not (ATokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
    begin
      if (Depth = 0) and (ATokens[Index].IsSymbol('(') or ATokens[Index].IsSymbol(':') or
        ATokens[Index].IsSymbol(';')) then
      begin
        Break;
      end;
      if ATokens[Index].IsSymbol('<') then
      begin
        if Depth = 0 then
        begin
          Inc(Seen);
          if Component = Dots then
          begin
            Own := Seen;
          end;
        end;
        Inc(Depth);
      end
      else if ATokens[Index].IsSymbol('>') then
      begin
        Dec(Depth);
      end
      else if ATokens[Index].IsSymbol('>>') then
      begin
        Dec(Depth, 2);
      end
      else if (Depth = 0) and ATokens[Index].IsSymbol('.') then
      begin
        Inc(Component);
      end;
    end;
    Inc(Index);
  end;
  if Own < 0 then
  begin
    Exit;
  end;
  Seen := -1;
  for Child := 0 to AHeader.ChildCount - 1 do
  begin
    if AHeader[Child].Kind = TSyntaxKind.GenericParams then
    begin
      Inc(Seen);
      if Seen = Own then
      begin
        Exit(AHeader[Child]);
      end;
    end;
  end;
end;

/// <summary>Gruppen "A, B: Einschränkungen" der Liste AParams; je Gruppe die Einschränkungen in Reihenfolge.</summary>
function ConstraintGroups(const ATokens: TArray<TPascalToken>; AParams: TSyntaxNode):
  TArray<TArray<TGenericConstraint>>;
var
  Groups: TArray<TArray<TGenericConstraint>>;
  Group: TArray<TGenericConstraint>;
  Current: TGenericConstraint;
  Index, Depth: Integer;
  InConstraints: Boolean;
  Token: TPascalToken;

  procedure Flush;
  begin
    if Current.Text <> '' then
    begin
      Group := Group + [Current];
    end;
    Current := Default(TGenericConstraint);
  end;

  procedure CloseGroup;
  begin
    Flush;
    if Group <> nil then
    begin
      Groups := Groups + [Group];
    end;
    Group := nil;
    InConstraints := False;
  end;

begin
  Groups := nil;
  Group := nil;
  Current := Default(TGenericConstraint);
  InConstraints := False;
  Depth := 0;
  Index := TRoutineBody.TokenAt(ATokens, AParams.StartOffset);
  while (Index >= 0) and (Index < Length(ATokens)) and (ATokens[Index].Offset < AParams.EndOffset) do
  begin
    Token := ATokens[Index];
    Inc(Index);
    if Token.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive] then
    begin
      Continue;
    end;
    if Token.IsSymbol('<') then
    begin
      Inc(Depth);
      if Depth = 1 then
      begin
        Continue;
      end;
    end
    else if Token.IsSymbol('>') or Token.IsSymbol('>=') or Token.IsSymbol('>>') then
    begin
      if Token.IsSymbol('>>') then
      begin
        Dec(Depth, 2);
      end
      else
      begin
        Dec(Depth);
      end;
      if Depth <= 0 then
      begin
        if Token.IsSymbol('>>') and InConstraints then
        begin
          Current.Text := Current.Text + '>';
          Current.Range.EndPos := Token.EndPos;
        end;
        CloseGroup;
        Break;
      end;
    end
    else if Depth = 1 then
    begin
      if Token.IsSymbol(':') then
      begin
        InConstraints := True;
        Continue;
      end;
      if Token.IsSymbol(',') then
      begin
        if InConstraints then
        begin
          Flush;
        end;
        Continue;
      end;
      if Token.IsSymbol(';') then
      begin
        CloseGroup;
        Continue;
      end;
    end;
    if not InConstraints then
    begin
      Continue;
    end;
    if Current.Text = '' then
    begin
      Current.Range.StartPos := Token.StartPos;
    end;
    Current.Text := Current.Text + Token.Text;
    Current.Range.EndPos := Token.EndPos;
  end;
  CloseGroup;
  Result := Groups;
end;

/// <summary>Art der Einschränkung AText; Typparameter aus AScope und unbekannte Typen ergeben Unknown.</summary>
function ConstraintKind(const ATypes: TFileTypes; const AText: string; const AScope: TArray<string>):
  TConstraintKind;
var
  Bare: string;
  Kind: TSyntaxKind;
  Qualified: Boolean;
begin
  if SameText(AText, 'class') then
  begin
    Exit(TConstraintKind.ClassKeyword);
  end;
  if SameText(AText, 'record') then
  begin
    Exit(TConstraintKind.RecordKeyword);
  end;
  if SameText(AText, 'constructor') then
  begin
    Exit(TConstraintKind.ConstructorKeyword);
  end;
  Result := TConstraintKind.Unknown;
  Bare := BareTypeName(AText);
  if (Bare = '') or MatchText(Bare, AScope) then
  begin
    Exit;
  end;
  Qualified := Pos('.', Copy(AText, 1, Pos('<', AText + '<') - 1)) > 0;
  if Qualified then
  begin
    if StartsText('System.', AText) and (MatchText(Bare, BuiltinTypeNames) or MatchText(Bare, BooleanTypeNames)) then
    begin
      Result := TConstraintKind.Invalid;
    end;
    Exit;
  end;
  if ATypes.IndexOf(Bare) >= 0 then
  begin
    Kind := ATypes.DeclaredKind(Bare);
    if Kind = TSyntaxKind.ClassType then
    begin
      Result := TConstraintKind.ClassType;
    end
    else if Kind = TSyntaxKind.InterfaceType then
    begin
      Result := TConstraintKind.InterfaceType;
    end
    else if Kind in InvalidConstraintKinds then
    begin
      Result := TConstraintKind.Invalid;
    end;
    Exit;
  end;
  if SameText(Bare, 'TObject') then
  begin
    Result := TConstraintKind.ClassType;
  end
  else if MatchText(Bare, BuiltinTypeNames) or MatchText(Bare, BooleanTypeNames) then
  begin
    Result := TConstraintKind.Invalid;
  end;
end;

/// <summary>Typparameter der umgebenden generischen Typen von ANode und von ANode selbst.</summary>
function ScopeTypeParams(ANode: TSyntaxNode): TArray<string>;
var
  Node: TSyntaxNode;
begin
  Result := nil;
  if ANode.Kind = TSyntaxKind.GenericParams then
  begin
    Result := TypeParamNames(ANode);
  end;
  Node := ANode.Parent;
  while Node <> nil do
  begin
    if Node.Kind = TSyntaxKind.TypeDecl then
    begin
      Result := Result + TypeParamNames(Node.FindChild(TSyntaxKind.GenericParams));
    end;
    Node := Node.Parent;
  end;
end;

function TGenericDeclarationInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(GenericDeclarationInvalidRuleId, TRuleSeverity.Error,
    'Generische Deklaration unzulässig');
end;

procedure TGenericDeclarationInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Types: TFileTypes;
  Root, InterfacePart: TSyntaxNode;
  Nodes: TList<TSyntaxNode>;
  Node: TSyntaxNode;
  Index: Integer;
  mResolver: TNameResolver;
  mCache: IRuleDerivedCache;
  mLocal: TUnitIndex;

  procedure Report(const ARange: TTextRange; const AMessage: string);
  begin
    AReport.Add(ARange, AMessage, TRuleConfidence.High, nil);
  end;

  function TokenRangeAt(AOffset: Integer): TTextRange;
  var
    At: Integer;
  begin
    At := TRoutineBody.TokenAt(Tokens, AOffset);
    if (At >= 0) and (At < Length(Tokens)) then
    begin
      Result := TokenRange(Tokens[At]);
    end
    else
    begin
      Result := TTextRange.Create(Node.StartPos, Node.StartPos);
    end;
  end;

  function HeaderNameRange(AHeader: TSyntaxNode): TTextRange;
  var
    At: Integer;
  begin
    At := NameToken(Tokens, AHeader);
    if At >= 0 then
    begin
      Result := TokenRange(Tokens[At]);
    end
    else
    begin
      Result := NodeRange(AHeader);
    end;
  end;

  /// <summary>Art einer Einschränkung, die weder eingebaut noch in der Datei deklariert ist, über den Index
  /// (TStream aus System.Classes, #1376): Klasse oder Interface, sonst Unknown. Typparameter aus AScope und
  /// Namen der Datei (Aliase) bleiben Unknown.</summary>
  function IndexConstraintKind(const AText: string; const AScope: TArray<string>): TConstraintKind;
  var
    mBare, mFileName: string;
    mSymbol: TResolvedSymbol;
  begin
    Result := TConstraintKind.Unknown;
    mBare := BareTypeName(AText);
    if (AContext.Index = nil) or (mBare = '') or MatchText(mBare, AScope) or (Types.IndexOf(mBare) >= 0) then
    begin
      Exit;
    end;
    if mResolver = nil then
    begin
      mFileName := AContext.FileName;
      if mFileName = '' then
      begin
        mFileName := AContext.RelativePath;
      end;
      if mFileName = '' then
      begin
        mFileName := AContext.UnitName + '.pas';
      end;
      // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
      mCache := TRuleDerived.Open(AContext);
      mResolver := TRuleDerived.Resolver(mCache, AContext);
      mResolver.PinTree(AContext.Tree, mFileName);
      mLocal := mResolver.ExtractedUnit(AContext.Tree, mFileName);
    end;
    if not mResolver.ResolveTypeTextFrom(mLocal, AText, mSymbol) or mSymbol.Builtin or (mSymbol.Condition <> '') then
    begin
      Exit;
    end;
    if mSymbol.SymbolKind = TIndexSymbolKind.ClassType then
    begin
      Result := TConstraintKind.ClassType;
    end
    else if mSymbol.SymbolKind = TIndexSymbolKind.InterfaceType then
    begin
      Result := TConstraintKind.InterfaceType;
    end;
  end;

  // Einschränkungen einer Typparameterliste: E2507, E2510, E2516, E2552, E2553, E2603.
  procedure CheckConstraints(AParams: TSyntaxNode);
  var
    Scope, Seen: TArray<string>;
    Group: TArray<TGenericConstraint>;
    Constraint: TGenericConstraint;
    Kind: TConstraintKind;
    HasClass, HasRecord, HasConstructor: Boolean;
    ClassTypes: Integer;
    Key: string;
  begin
    Scope := ScopeTypeParams(AParams);
    for Group in ConstraintGroups(Tokens, AParams) do
    begin
      Seen := nil;
      HasClass := False;
      HasRecord := False;
      HasConstructor := False;
      ClassTypes := 0;
      for Constraint in Group do
      begin
        Kind := ConstraintKind(Types, Constraint.Text, Scope);
        if Kind = TConstraintKind.Unknown then
        begin
          Kind := IndexConstraintKind(Constraint.Text, Scope);
        end;
        Key := LowerCase(Constraint.Text);
        if MatchText(Key, Seen) and (Kind <> TConstraintKind.ClassType) then
        begin
          Report(Constraint.Range, Format('Die Einschränkung %s steht doppelt (wie E2603).', [Constraint.Text]));
          Continue;
        end;
        Seen := Seen + [Key];
        case Kind of
          TConstraintKind.ClassKeyword:
            begin
              if HasRecord then
              begin
                Report(Constraint.Range, 'class und record lassen sich nicht zusammen fordern (wie E2507).');
              end
              else if ClassTypes > 0 then
              begin
                Report(Constraint.Range,
                  'class lässt sich nicht zusammen mit einer Klasse als Einschränkung fordern (wie E2552).');
              end;
              HasClass := True;
            end;
          TConstraintKind.RecordKeyword:
            begin
              if HasClass then
              begin
                Report(Constraint.Range, 'class und record lassen sich nicht zusammen fordern (wie E2507).');
              end
              else if ClassTypes > 0 then
              begin
                Report(Constraint.Range,
                  'record lässt sich nicht zusammen mit einer Klasse als Einschränkung fordern (wie E2552).');
              end
              else if HasConstructor then
              begin
                Report(Constraint.Range, 'record widerspricht der Einschränkung constructor (wie E2516).');
              end;
              HasRecord := True;
            end;
          TConstraintKind.ConstructorKeyword:
            begin
              if HasRecord then
              begin
                Report(Constraint.Range, 'constructor widerspricht der Einschränkung record (wie E2516).');
              end;
              HasConstructor := True;
            end;
          TConstraintKind.ClassType:
            begin
              if ClassTypes > 0 then
              begin
                Report(Constraint.Range, Format('Nur eine Klasse ist als Einschränkung erlaubt; %s ist die zweite ' +
                  '(wie E2553).', [Constraint.Text]));
              end
              else if HasClass or HasRecord then
              begin
                Report(Constraint.Range, Format('Die Klasse %s lässt sich nicht zusammen mit class bzw. record ' +
                  'fordern (wie E2552).', [Constraint.Text]));
              end;
              Inc(ClassTypes);
            end;
          TConstraintKind.Invalid:
            Report(Constraint.Range, Format('%s ist keine gültige Einschränkung; erlaubt sind Klassen, Interfaces, ' +
              'class, record und constructor (wie E2510).', [Constraint.Text]));
          TConstraintKind.Unknown: ;
          TConstraintKind.InterfaceType: ;
        end;
      end;
    end;
  end;

  // type vor einem instanziierten Typ (TEigen = type TListe<Integer>): E2574.
  procedure CheckTypedType(ADecl, ATypeNode: TSyntaxNode);
  var
    mAt, mBefore: Integer;
    mRange: TTextRange;
  begin
    if (ATypeNode.Kind <> TSyntaxKind.TypeReference) or (ATypeNode.FindChild(TSyntaxKind.GenericArgs) = nil) or
      (ScopeTypeParams(ADecl) <> nil) then
    begin
      Exit;
    end;
    mAt := TRoutineBody.TokenAt(Tokens, ATypeNode.StartOffset);
    mBefore := TRoutineBody.PreviousToken(Tokens, mAt);
    if (mBefore < 0) or (mBefore >= Length(Tokens)) or (Tokens[mBefore].Kind <> TPascalTokenKind.Keyword) or
      not SameText(Tokens[mBefore].Text, 'type') then
    begin
      Exit;
    end;
    mRange := TTextRange.Create(Tokens[mBefore].StartPos, ATypeNode.EndPos);
    AReport.Add(mRange, Format('Der instanziierte Typ %s lässt sich nicht mit type als eigener Typ deklarieren ' +
      '(wie E2574).', [OneLine(AContext.Text, ATypeNode)]), TRuleConfidence.High,
      [TRuleFix.Create('type entfernen (Alias)', [TRuleEdit.Create(TTextRange.Create(Tokens[mBefore].StartPos,
      Tokens[mAt].StartPos), '')])]);
  end;

  // Lokale Routinen in einer generischen Methode oder einer Methode eines generischen Typs: E2570.
  procedure CheckLocalRoutines(ADecl: TSyntaxNode);
  var
    mHeader, mInner: TSyntaxNode;
    mChild: Integer;
  begin
    mHeader := ADecl.FindChild(TSyntaxKind.RoutineHeader);
    if (mHeader = nil) or (Pos('.', mHeader.Name) = 0) or (mHeader.FindChild(TSyntaxKind.GenericParams) = nil) then
    begin
      Exit;
    end;
    for mChild := 0 to ADecl.ChildCount - 1 do
    begin
      if ADecl[mChild].Kind = TSyntaxKind.RoutineDecl then
      begin
        mInner := ADecl[mChild].FindChild(TSyntaxKind.RoutineHeader);
        if mInner = nil then
        begin
          mInner := ADecl[mChild];
        end;
        Report(HeaderNameRange(mInner), Format('Die lokale Routine %s ist in %s nicht erlaubt: Methoden generischer ' +
          'Typen und generische Methoden haben keine lokalen Routinen; als private Methode oder anonyme Methode ' +
          'schreiben (wie E2570).', [ADecl[mChild].Name, mHeader.Name]));
      end;
    end;
  end;

  // Typdeklaration mit Typparametern: E2508, E2549, H2509.
  procedure CheckTypeDecl(ADecl: TSyntaxNode);
  var
    Params, TypeNode, Inner: TSyntaxNode;
    Names: TArray<string>;
    Ancestor: string;
    Depth, Child: Integer;
    Shadowing: TList<TSyntaxNode>;
  begin
    Params := ADecl.FindChild(TSyntaxKind.GenericParams);
    TypeNode := TypeOfDecl(ADecl);
    if (Params = nil) and (TypeNode <> nil) then
    begin
      CheckTypedType(ADecl, TypeNode);
    end;
    if (Params = nil) or (TypeNode = nil) then
    begin
      Exit;
    end;
    if TypeNode.Kind in NonGenericTypeKinds then
    begin
      Report(TokenRangeAt(ADecl.StartOffset), Format('Der Typ %s darf keine Typparameter haben; erlaubt sind sie ' +
        'an Klassen, Records, Interfaces, Arrays und Prozedurtypen (wie E2508).', [ADecl.Name]));
      Exit;
    end;
    if TypeNode.Kind = TSyntaxKind.ClassType then
    begin
      Ancestor := Types.ParentOf(ADecl.Name);
      Depth := 0;
      while (Ancestor <> '') and (Depth < 32) do
      begin
        if SameText(Ancestor, 'TCustomAttribute') then
        begin
          Report(TokenRangeAt(ADecl.StartOffset), Format('Die Attributklasse %s darf keine Typparameter haben ' +
            '(wie E2549).', [ADecl.Name]));
          Break;
        end;
        Ancestor := Types.ParentOf(Ancestor);
        Inc(Depth);
      end;
    end;
    Names := TypeParamNames(Params);
    Shadowing := TList<TSyntaxNode>.Create;
    try
      TypeNode.Walk(
        function(ANode: TSyntaxNode): Boolean
        begin
          Result := True;
          // IEnumerator<T>.GetCurrent = GetCurrentGen nennt die Typparameter des Interfaces, deklariert keine
          // eigenen (#1325).
          if (ANode.Kind = TSyntaxKind.RoutineHeader) and ANode.IsMethodResolution then
          begin
            Exit(False);
          end;
          if ANode.Kind = TSyntaxKind.GenericParams then
          begin
            Shadowing.Add(ANode);
          end;
        end);
      for Inner in Shadowing do
      begin
        for Child := 0 to Inner.ChildCount - 1 do
        begin
          if (Inner[Child].Kind = TSyntaxKind.Identifier) and MatchText(Inner[Child].Name, Names) then
          begin
            Report(NodeRange(Inner[Child]), Format('Der Typparameter %s verdeckt den gleichnamigen Typparameter ' +
              'von %s (wie H2509).', [Inner[Child].Name, ADecl.Name]));
          end;
        end;
      end;
    finally
      Shadowing.Free;
    end;
  end;

  // Routine mit eigenen Typparametern: E2528, E2529, E2530, E2533, E2535.
  procedure CheckHeader(AHeader: TSyntaxNode);
  var
    Own, Holder, Directive, Other: TSyntaxNode;
    Head: TRoutineHead;
    Name: string;
    Declared: Boolean;
    Child: Integer;
  begin
    Own := OwnGenericParams(Tokens, AHeader);
    if (Own = nil) or (AHeader.Parent = nil) then
    begin
      Exit;
    end;
    Holder := AHeader.Parent;
    Head := TRoutineHead.Read(Tokens, AHeader);
    if Holder.Kind = TSyntaxKind.InterfaceType then
    begin
      Report(HeaderNameRange(AHeader), 'Interface-Methoden dürfen keine Typparameter haben (wie E2535).');
      Exit;
    end;
    if Holder.Kind in [TSyntaxKind.ClassType, TSyntaxKind.RecordType, TSyntaxKind.ObjectType,
      TSyntaxKind.HelperType] then
    begin
      if Head.Keyword = 'operator' then
      begin
        Report(HeaderNameRange(AHeader), 'Operatoren dürfen keine Typparameter haben (wie E2529).');
        Exit;
      end;
      if Head.Keyword = 'destructor' then
      begin
        Report(HeaderNameRange(AHeader), 'Destruktoren dürfen keine Typparameter haben (wie E2528).');
        Exit;
      end;
      if Head.IsClass and (Head.Keyword = 'constructor') then
      begin
        Report(HeaderNameRange(AHeader), 'Klassenkonstruktoren dürfen keine Typparameter haben (wie E2528).');
        Exit;
      end;
      // Mit dcc 13 belegt für Klassen (Cm.E2528); Records und object bleiben ungeprüft still.
      if (Head.Keyword = 'constructor') and (Holder.Kind = TSyntaxKind.ClassType) then
      begin
        Report(HeaderNameRange(AHeader), 'Konstruktoren dürfen keine Typparameter haben (wie E2528).');
        Exit;
      end;
      for Name in VirtualDirectives do
      begin
        Directive := Head.Directive(Name);
        if Directive <> nil then
        begin
          Report(NodeRange(Directive), 'Virtuelle, dynamische und message-Methoden dürfen keine Typparameter ' +
            'haben (wie E2533).');
          Exit;
        end;
      end;
      Exit;
    end;
    if (Holder.Kind <> TSyntaxKind.RoutineDecl) or (Pos('.', AHeader.Name) > 0) or (Holder.Parent = nil) or
      not (Holder.Parent.Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection,
      TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile, TSyntaxKind.UnitFile]) then
    begin
      Exit;
    end;
    // Rumpf einer Routine aus dem interface-Teil: dort schon gemeldet.
    Declared := False;
    if (Holder.Parent.Kind = TSyntaxKind.ImplementationSection) and (InterfacePart <> nil) then
    begin
      for Child := 0 to InterfacePart.ChildCount - 1 do
      begin
        Other := InterfacePart[Child];
        if (Other.Kind = TSyntaxKind.RoutineDecl) and SameText(Other.Name, AHeader.Name) and
          (Other.FindChild(TSyntaxKind.RoutineHeader) <> nil) and
          (Other.FindChild(TSyntaxKind.RoutineHeader).FindChild(TSyntaxKind.GenericParams) <> nil) then
        begin
          Declared := True;
        end;
      end;
    end;
    if not Declared then
    begin
      Report(TTextRange.Create(HeaderNameRange(AHeader).StartPos, Own.EndPos), 'Globale Routinen dürfen keine ' +
        'Typparameter haben; als class-Methode eines Records deklarieren (wie E2530).');
    end;
  end;

  /// <summary>Klasse der Methode, in der ANode steht ('' außerhalb oder in with).</summary>
  function EnclosingClass(ANode: TSyntaxNode; ARejectWith: Boolean): string;
  var
    Current: TSyntaxNode;
    Name: string;
  begin
    Result := '';
    Current := ANode.Parent;
    while Current <> nil do
    begin
      if ARejectWith and (Current.Kind = TSyntaxKind.WithStatement) then
      begin
        Exit('');
      end;
      if (Current.Kind = TSyntaxKind.RoutineDecl) and (Pos('.', Current.Name) > 0) then
      begin
        Name := Copy(Current.Name, 1, LastDelimiter('.', Current.Name) - 1);
        Result := LastPart(Name);
      end;
      Current := Current.Parent;
    end;
  end;

  /// <summary>Köpfe AMethod der Klasse oder des Records AType samt Vorfahren der Datei; False, wenn die Kette
  /// außerhalb der Datei weitergeht.</summary>
  function MethodHeads(const AType, AMethod: string; out AHeads: TArray<TSyntaxNode>): Boolean;
  var
    Current: string;
    Decl, TypeNode: TSyntaxNode;
    Depth, Child: Integer;
  begin
    AHeads := nil;
    Result := False;
    Current := AType;
    Depth := 0;
    while Depth < 32 do
    begin
      Decl := FindStructDecl(Root, Current);
      if Decl = nil then
      begin
        Exit;
      end;
      TypeNode := TypeOfDecl(Decl);
      for Child := 0 to TypeNode.ChildCount - 1 do
      begin
        if (TypeNode[Child].Kind = TSyntaxKind.RoutineHeader) and SameText(TypeNode[Child].Name, AMethod) then
        begin
          AHeads := AHeads + [TypeNode[Child]];
        end;
      end;
      if (TypeNode.Kind <> TSyntaxKind.ClassType) or (TypeNode.ChildCount = 0) or
        (TypeNode[0].Kind <> TSyntaxKind.TypeReference) then
      begin
        Exit(True);
      end;
      Current := BareTypeName(TypeNode[0].Name);
      if SameText(Current, 'TObject') then
      begin
        Exit(True);
      end;
      if Types.DeclaredKind(Current) = TSyntaxKind.InterfaceType then
      begin
        Exit(True);
      end;
      Inc(Depth);
    end;
  end;

  // Aufruf F<…> mit einer Zahl Typargumente, die keine Variante von F hat: E2551.
  procedure CheckCall(AAccess: TSyntaxNode);
  var
    Target: TSyntaxNode;
    TypeName, Variants: string;
    Heads: TArray<TSyntaxNode>;
    Head: TSyntaxNode;
    Count: Integer;
    Fits: Boolean;
  begin
    if (AAccess.ChildCount <> 2) or (AAccess[1].Kind <> TSyntaxKind.GenericArgs) or (AAccess.Parent = nil) or
      not (AAccess.Parent.Kind in [TSyntaxKind.Call, TSyntaxKind.CallStatement]) or
      (AAccess.Parent[0] <> AAccess) then
    begin
      Exit;
    end;
    Target := AAccess[0];
    TypeName := '';
    if (Target.Kind = TSyntaxKind.Identifier) and SameText(Target.Name, AAccess.Name) then
    begin
      TypeName := EnclosingClass(AAccess, True);
    end
    else if (Target.Kind = TSyntaxKind.MemberAccess) and SameText(Target.Name, AAccess.Name) and
      (Target.ChildCount = 1) and (Target[0].Kind = TSyntaxKind.Identifier) then
    begin
      if SameText(Target[0].Name, 'Self') then
      begin
        TypeName := EnclosingClass(AAccess, False);
      end
      else if (EnclosingClass(AAccess, True) <> '') or (Pos('.', Target[0].Name) = 0) then
      begin
        if Types.DeclaredKind(Target[0].Name) in [TSyntaxKind.ClassType, TSyntaxKind.RecordType] then
        begin
          TypeName := Target[0].Name;
        end;
      end;
    end;
    if (TypeName = '') or not MethodHeads(TypeName, AAccess.Name, Heads) or (Heads = nil) then
    begin
      Exit;
    end;
    Count := AAccess[1].ChildCount;
    Fits := False;
    Variants := '';
    for Head in Heads do
    begin
      if Head.FindChild(TSyntaxKind.GenericParams) = nil then
      begin
        Exit;
      end;
      if Length(TypeParamNames(Head.FindChild(TSyntaxKind.GenericParams))) = Count then
      begin
        Fits := True;
      end;
      if Variants <> '' then
      begin
        Variants := Variants + ', ';
      end;
      Variants := Variants + Head.Name + '<' + string.Join(', ',
        TypeParamNames(Head.FindChild(TSyntaxKind.GenericParams))) + '>';
    end;
    if not Fits then
    begin
      Report(NodeRange(AAccess), Format('%s hat keine Variante mit %d Typparametern; deklariert: %s (wie E2551).',
        [AAccess.Name, Count, Variants]));
    end;
  end;

  // Methoden generischer Typen bzw. generische Methoden aus dem interface-Teil, die Symbole des
  // implementation-Teils verwenden: E2506.
  procedure CheckLocalSymbols;
  var
    Symbols: TImplementationSymbols;
    Routine, Decl, Outer, Use: TSyntaxNode;
    Generic: Boolean;
  begin
    Symbols := TImplementationSymbols.Create(AContext);
    try
      for Routine in Symbols.Routines do
      begin
        Decl := Symbols.OwnerType(Routine);
        if Decl = nil then
        begin
          Continue;
        end;
        Generic := OwnGenericParams(Tokens, Routine.FindChild(TSyntaxKind.RoutineHeader)) <> nil;
        Outer := Decl;
        while Outer <> nil do
        begin
          if (Outer.Kind = TSyntaxKind.TypeDecl) and (Outer.FindChild(TSyntaxKind.GenericParams) <> nil) then
          begin
            Generic := True;
          end;
          Outer := Outer.Parent;
        end;
        if not Generic then
        begin
          Continue;
        end;
        for Use in Symbols.UsesIn(Routine, Decl) do
        begin
          Report(NodeRange(Use), Format('%s gehört zu einem generischen Typ bzw. ist generisch, steht im ' +
            'interface-Teil und darf %s aus dem implementation-Teil nicht verwenden (wie E2506).',
            [Routine.Name, Use.Name]));
        end;
      end;
    finally
      Symbols.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or (Pos('<', AContext.Text) = 0) then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Root := AContext.Tree.Root;
  Types := TFileTypes.Collect(Root);
  InterfacePart := Root.FindChild(TSyntaxKind.InterfaceSection);
  mResolver := nil;
  mLocal := Default(TUnitIndex);
  Nodes := TList<TSyntaxNode>.Create;
  try
    Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        // Methodenzuordnungen (function IFoo<T>.Bar = Baz;) deklarieren nichts Generisches (#1325).
        Result := not ((ANode.Kind = TSyntaxKind.RoutineHeader) and ANode.IsMethodResolution);
        if Result and (ANode.Kind in [TSyntaxKind.GenericParams, TSyntaxKind.TypeDecl, TSyntaxKind.ClassOfType,
          TSyntaxKind.Attribute, TSyntaxKind.RoutineHeader, TSyntaxKind.MemberAccess, TSyntaxKind.RoutineDecl]) then
        begin
          Nodes.Add(ANode);
        end;
      end);
    for Index := 0 to Nodes.Count - 1 do
    begin
      Node := Nodes[Index];
      case Node.Kind of
        TSyntaxKind.GenericParams:
          CheckConstraints(Node);
        TSyntaxKind.TypeDecl:
          CheckTypeDecl(Node);
        TSyntaxKind.ClassOfType:
          if (Node.ChildCount > 0) and (Node[0].FindChild(TSyntaxKind.GenericArgs) <> nil) then
          begin
            Report(NodeRange(Node[0]), 'class of ist für parametrisierte Typen nicht erlaubt (wie E2548).');
          end;
        TSyntaxKind.Attribute:
          if (Node.ChildCount > 0) and ((Node[0].FindChild(TSyntaxKind.GenericArgs) <> nil) or
            ((Node[0].Kind = TSyntaxKind.Call) and (Node[0].ChildCount > 0) and
            (Node[0][0].FindChild(TSyntaxKind.GenericArgs) <> nil))) then
          begin
            Report(NodeRange(Node), 'Parametrisierte Typen können nicht als Attribut stehen (wie E2565).');
          end;
        TSyntaxKind.RoutineHeader:
          CheckHeader(Node);
        TSyntaxKind.MemberAccess:
          CheckCall(Node);
        TSyntaxKind.RoutineDecl:
          CheckLocalRoutines(Node);
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
    end;
    CheckLocalSymbols;
  finally
    Nodes.Free;
    if mResolver <> nil then
    begin
      mResolver.UnpinTree;
    end;
  end;
end;

end.
