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
  Atlas.Common.Rules.Builtin.TypeRestrictions.Symbols,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TTypeRestrictionsGenericsText = (ClassRecord, ClassWithClass, RecordWithClass, RecordCtor, CtorRecord, OneClass,
    ClassAndKeyword, InvalidConstraint, Operators, Destructors, ClassConstructors, Constructors, Title,
    DuplicateConstraint, InstantiatedType, RemoveType, LocalRoutine, AttributeClass, HidesTypeParam, TypeNoParams,
    VirtualMethods, InterfaceMethods, GlobalRoutines, NoVariant, ImplementationUse, ClassOf, AsAttribute);

const
  cTexts: array[TTypeRestrictionsGenericsText] of TAtlasText = (
    (De: 'class und record lassen sich nicht zusammen fordern (wie E2507).';
     En: 'class and record cannot be required together (like E2507).'),
    (De: 'class lässt sich nicht zusammen mit einer Klasse als Einschränkung fordern (wie E2552).';
     En: 'class cannot be required together with a class as constraint (like E2552).'),
    (De: 'record lässt sich nicht zusammen mit einer Klasse als Einschränkung fordern (wie E2552).';
     En: 'record cannot be required together with a class as constraint (like E2552).'),
    (De: 'record widerspricht der Einschränkung constructor (wie E2516).';
     En: 'record contradicts the constraint constructor (like E2516).'),
    (De: 'constructor widerspricht der Einschränkung record (wie E2516).';
     En: 'constructor contradicts the constraint record (like E2516).'),
    (De: 'Nur eine Klasse ist als Einschränkung erlaubt; %s ist die zweite (wie E2553).';
     En: 'Only one class is allowed as constraint; %s is the second (like E2553).'),
    (De: 'Die Klasse %s lässt sich nicht zusammen mit class bzw. record fordern (wie E2552).';
     En: 'The class %s cannot be required together with class or record (like E2552).'),
    (De: '%s ist keine gültige Einschränkung; erlaubt sind Klassen, Interfaces, class, record und constructor (wie ' +
      'E2510).';
     En: '%s is not a valid constraint; allowed are classes, interfaces, class, record and constructor (like E2510).'),
    (De: 'Operatoren dürfen keine Typparameter haben (wie E2529).';
     En: 'Operators must not have type parameters (like E2529).'),
    (De: 'Destruktoren dürfen keine Typparameter haben (wie E2528).';
     En: 'Destructors must not have type parameters (like E2528).'),
    (De: 'Klassenkonstruktoren dürfen keine Typparameter haben (wie E2528).';
     En: 'Class constructors must not have type parameters (like E2528).'),
    (De: 'Konstruktoren dürfen keine Typparameter haben (wie E2528).';
     En: 'Constructors must not have type parameters (like E2528).'),
    (De: 'Generische Deklaration unzulässig'; En: 'Generic declaration invalid'),
    (De: 'Die Einschränkung %s steht doppelt (wie E2603).'; En: 'The constraint %s occurs twice (like E2603).'),
    (De: 'Der instanziierte Typ %s lässt sich nicht mit type als eigener Typ deklarieren (wie E2574).';
     En: 'The instantiated type %s cannot be declared as a type of its own with type (like E2574).'),
    (De: 'type entfernen (Alias)'; En: 'Remove type (alias)'),
    (De: 'Die lokale Routine %s ist in %s nicht erlaubt: Methoden generischer Typen und generische Methoden haben ' +
      'keine lokalen Routinen; als private Methode oder anonyme Methode schreiben (wie E2570).';
     En: 'The local routine %s is not allowed in %s: methods of generic types and generic methods have no local ' +
      'routines; write it as a private method or an anonymous method (like E2570).'),
    (De: 'Die Attributklasse %s darf keine Typparameter haben (wie E2549).';
     En: 'The attribute class %s must not have type parameters (like E2549).'),
    (De: 'Der Typparameter %s verdeckt den gleichnamigen Typparameter von %s (wie H2509).';
     En: 'The type parameter %s hides the type parameter of the same name of %s (like H2509).'),
    (De: 'Der Typ %s darf keine Typparameter haben; erlaubt sind sie an Klassen, Records, Interfaces, Arrays und ' +
      'Prozedurtypen (wie E2508).';
     En: 'The type %s must not have type parameters; they are allowed on classes, records, interfaces, arrays and ' +
      'procedural types (like E2508).'),
    (De: 'Virtuelle, dynamische und message-Methoden dürfen keine Typparameter haben (wie E2533).';
     En: 'Virtual, dynamic and message methods must not have type parameters (like E2533).'),
    (De: 'Interface-Methoden dürfen keine Typparameter haben (wie E2535).';
     En: 'Interface methods must not have type parameters (like E2535).'),
    (De: 'Globale Routinen dürfen keine Typparameter haben; als class-Methode eines Records deklarieren (wie E2530).';
     En: 'Global routines must not have type parameters; declare them as a class method of a record (like E2530).'),
    (De: '%s hat keine Variante mit %d Typparametern; deklariert: %s (wie E2551).';
     En: '%s has no variant with %d type parameters; declared: %s (like E2551).'),
    (De: '%s gehört zu einem generischen Typ bzw. ist generisch, steht im interface-Teil und darf %s aus dem ' +
      'implementation-Teil nicht verwenden (wie E2506).';
     En: '%s belongs to a generic type or is generic, is in the interface section and must not use %s from the ' +
      'implementation section (like E2506).'),
    (De: 'class of ist für parametrisierte Typen nicht erlaubt (wie E2548).';
     En: 'class of is not allowed for parameterized types (like E2548).'),
    (De: 'Parametrisierte Typen können nicht als Attribut stehen (wie E2565).';
     En: 'Parameterized types cannot be used as attribute (like E2565).'));

{$SCOPEDENUMS OFF}

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

  /// <summary>Bisherige Einschränkungen einer Gruppe: class, record, constructor und Zahl der Klassen.</summary>
  TConstraintState = record
    HasClass: Boolean;
    HasRecord: Boolean;
    HasConstructor: Boolean;
    ClassTypes: Integer;
  end;

  /// <summary>Sucht im Kopf TFoo&lt;T&gt;.Bar&lt;U&gt; die Typparameterliste der letzten Namenskomponente.</summary>
  THeaderGenericScan = record
    /// <summary>Zahl der Punkte im Namen, also Index der letzten Komponente.</summary>
    Dots: Integer;
    Component: Integer;
    Depth: Integer;
    /// <summary>Index der zuletzt geöffneten Liste auf Ebene 0.</summary>
    Seen: Integer;
    /// <summary>Index der Liste der letzten Komponente, -1 ohne.</summary>
    Own: Integer;
    /// <summary>Verarbeitet AToken; False am Ende der Namen (Klammer, Doppelpunkt, Semikolon auf Ebene 0).
    /// </summary>
    function Step(const AToken: TPascalToken): Boolean;
    procedure OpenAngle;
  end;

  /// <summary>Zerlegt eine Typparameterliste in Gruppen "A, B: Einschränkungen".</summary>
  TConstraintScan = record
    Groups: TArray<TArray<TGenericConstraint>>;
    Group: TArray<TGenericConstraint>;
    Current: TGenericConstraint;
    Depth: Integer;
    InConstraints: Boolean;
    /// <summary>Verarbeitet AToken; False am Ende der Liste.</summary>
    function Step(const AToken: TPascalToken): Boolean;
    procedure Flush;
    procedure CloseGroup;
    /// <summary>Schließende spitze Klammer; True, wenn die Liste damit endet.</summary>
    function Close(const AToken: TPascalToken): Boolean;
    /// <summary>Trenner auf Ebene 1 (Doppelpunkt, Komma, Semikolon) verarbeitet?</summary>
    function Separator(const AToken: TPascalToken): Boolean;
    procedure Append(const AToken: TPascalToken);
  end;

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

{ THeaderGenericScan }

function THeaderGenericScan.Step(const AToken: TPascalToken): Boolean;
begin
  Result := True;
  if AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive] then
  begin
    Exit;
  end;
  if (Depth = 0) and (AToken.IsSymbol('(') or AToken.IsSymbol(':') or AToken.IsSymbol(';')) then
  begin
    Exit(False);
  end;
  if AToken.IsSymbol('<') then
  begin
    OpenAngle;
  end
  else if AToken.IsSymbol('>') then
  begin
    Dec(Depth);
  end
  else if AToken.IsSymbol('>>') then
  begin
    Dec(Depth, 2);
  end
  else if (Depth = 0) and AToken.IsSymbol('.') then
  begin
    Inc(Component);
  end;
end;

procedure THeaderGenericScan.OpenAngle;
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
end;

/// <summary>Die AIndex-te Typparameterliste unter AHeader, nil ohne.</summary>
function NthGenericParams(AHeader: TSyntaxNode; AIndex: Integer): TSyntaxNode;
var
  Seen, Child: Integer;
begin
  Seen := -1;
  for Child := 0 to AHeader.ChildCount - 1 do
  begin
    if AHeader[Child].Kind <> TSyntaxKind.GenericParams then
    begin
      Continue;
    end;
    Inc(Seen);
    if Seen = AIndex then
    begin
      Exit(AHeader[Child]);
    end;
  end;
  Result := nil;
end;

/// <summary>Eigene Typparameter des Kopfs: bei TFoo&lt;T&gt;.Bar&lt;U&gt; die von Bar, nil ohne.</summary>
function OwnGenericParams(const ATokens: TArray<TPascalToken>; AHeader: TSyntaxNode): TSyntaxNode;
var
  Index: Integer;
  Scan: THeaderGenericScan;
begin
  Result := nil;
  if (AHeader.Parent = nil) or (AHeader.Parent.Kind <> TSyntaxKind.RoutineDecl) or (Pos('.', AHeader.Name) = 0) then
  begin
    Exit(AHeader.FindChild(TSyntaxKind.GenericParams));
  end;
  Scan := Default(THeaderGenericScan);
  Scan.Dots := Length(AHeader.Name) - Length(StringReplace(AHeader.Name, '.', '', [rfReplaceAll]));
  Scan.Seen := -1;
  Scan.Own := -1;
  Index := TRoutineBody.TokenAt(ATokens, AHeader.StartOffset);
  while (Index >= 0) and (Index < Length(ATokens)) and (ATokens[Index].Offset < AHeader.EndOffset) and
    Scan.Step(ATokens[Index]) do
  begin
    Inc(Index);
  end;
  if Scan.Own >= 0 then
  begin
    Result := NthGenericParams(AHeader, Scan.Own);
  end;
end;

{ TConstraintScan }

procedure TConstraintScan.Flush;
begin
  if Current.Text <> '' then
  begin
    Group := Group + [Current];
  end;
  Current := Default(TGenericConstraint);
end;

procedure TConstraintScan.CloseGroup;
begin
  Flush;
  if Group <> nil then
  begin
    Groups := Groups + [Group];
  end;
  Group := nil;
  InConstraints := False;
end;

function TConstraintScan.Close(const AToken: TPascalToken): Boolean;
begin
  if AToken.IsSymbol('>>') then
  begin
    Dec(Depth, 2);
  end
  else
  begin
    Dec(Depth);
  end;
  Result := Depth <= 0;
  if not Result then
  begin
    Exit;
  end;
  if AToken.IsSymbol('>>') and InConstraints then
  begin
    Current.Text := Current.Text + '>';
    Current.Range.EndPos := AToken.EndPos;
  end;
  CloseGroup;
end;

function TConstraintScan.Separator(const AToken: TPascalToken): Boolean;
begin
  Result := True;
  if AToken.IsSymbol(':') then
  begin
    InConstraints := True;
  end
  else if AToken.IsSymbol(',') then
  begin
    if InConstraints then
    begin
      Flush;
    end;
  end
  else if AToken.IsSymbol(';') then
  begin
    CloseGroup;
  end
  else
  begin
    Result := False;
  end;
end;

procedure TConstraintScan.Append(const AToken: TPascalToken);
begin
  if not InConstraints then
  begin
    Exit;
  end;
  if Current.Text = '' then
  begin
    Current.Range.StartPos := AToken.StartPos;
  end;
  Current.Text := Current.Text + AToken.Text;
  Current.Range.EndPos := AToken.EndPos;
end;

function TConstraintScan.Step(const AToken: TPascalToken): Boolean;
begin
  Result := True;
  if AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive] then
  begin
    Exit;
  end;
  if AToken.IsSymbol('<') then
  begin
    Inc(Depth);
    if Depth = 1 then
    begin
      Exit;
    end;
  end
  else if AToken.IsSymbol('>') or AToken.IsSymbol('>=') or AToken.IsSymbol('>>') then
  begin
    if Close(AToken) then
    begin
      Exit(False);
    end;
  end
  else if (Depth = 1) and Separator(AToken) then
  begin
    Exit;
  end;
  Append(AToken);
end;

/// <summary>Gruppen "A, B: Einschränkungen" der Liste AParams; je Gruppe die Einschränkungen in Reihenfolge.</summary>
function ConstraintGroups(const ATokens: TArray<TPascalToken>; AParams: TSyntaxNode):
  TArray<TArray<TGenericConstraint>>;
var
  Scan: TConstraintScan;
  Index: Integer;
begin
  Scan := Default(TConstraintScan);
  Index := TRoutineBody.TokenAt(ATokens, AParams.StartOffset);
  while (Index >= 0) and (Index < Length(ATokens)) and (ATokens[Index].Offset < AParams.EndOffset) and
    Scan.Step(ATokens[Index]) do
  begin
    Inc(Index);
  end;
  Scan.CloseGroup;
  Result := Scan.Groups;
end;

/// <summary>Einschränkung class, record oder constructor?</summary>
function KeywordConstraint(const AText: string; out AKind: TConstraintKind): Boolean;
begin
  Result := True;
  if SameText(AText, 'class') then
  begin
    AKind := TConstraintKind.ClassKeyword;
  end
  else if SameText(AText, 'record') then
  begin
    AKind := TConstraintKind.RecordKeyword;
  end
  else if SameText(AText, 'constructor') then
  begin
    AKind := TConstraintKind.ConstructorKeyword;
  end
  else
  begin
    AKind := TConstraintKind.Unknown;
    Result := False;
  end;
end;

/// <summary>Ist ABare ein eingebauter einfacher Typ (Integer, string, Boolean …)?</summary>
function IsBuiltinType(const ABare: string): Boolean;
begin
  Result := MatchText(ABare, BuiltinTypeNames) or MatchText(ABare, BooleanTypeNames);
end;

/// <summary>Art einer Einschränkung, deren Typ in der Datei als AKind deklariert ist.</summary>
function DeclaredConstraintKind(AKind: TSyntaxKind): TConstraintKind;
begin
  if AKind = TSyntaxKind.ClassType then
  begin
    Result := TConstraintKind.ClassType;
  end
  else if AKind = TSyntaxKind.InterfaceType then
  begin
    Result := TConstraintKind.InterfaceType;
  end
  else if AKind in InvalidConstraintKinds then
  begin
    Result := TConstraintKind.Invalid;
  end
  else
  begin
    Result := TConstraintKind.Unknown;
  end;
end;

/// <summary>Art einer Einschränkung, die weder in der Datei steht noch qualifiziert ist.</summary>
function BuiltinConstraintKind(const ABare: string): TConstraintKind;
begin
  if SameText(ABare, 'TObject') then
  begin
    Result := TConstraintKind.ClassType;
  end
  else if IsBuiltinType(ABare) then
  begin
    Result := TConstraintKind.Invalid;
  end
  else
  begin
    Result := TConstraintKind.Unknown;
  end;
end;

/// <summary>Art der Einschränkung AText; Typparameter aus AScope und unbekannte Typen ergeben Unknown.</summary>
function ConstraintKind(const ATypes: TFileTypes; const AText: string; const AScope: TArray<string>):
  TConstraintKind;
var
  Bare: string;
begin
  if KeywordConstraint(AText, Result) then
  begin
    Exit;
  end;
  Bare := BareTypeName(AText);
  if (Bare = '') or MatchText(Bare, AScope) then
  begin
    Exit;
  end;
  if Pos('.', Copy(AText, 1, Pos('<', AText + '<') - 1)) > 0 then
  begin
    if StartsText('System.', AText) and IsBuiltinType(Bare) then
    begin
      Result := TConstraintKind.Invalid;
    end;
  end
  else if ATypes.IndexOf(Bare) >= 0 then
  begin
    Result := DeclaredConstraintKind(ATypes.DeclaredKind(Bare));
  end
  else
  begin
    Result := BuiltinConstraintKind(Bare);
  end;
end;

/// <summary>Widerspruch der Einschränkung class, record oder constructor zu AState, '' ohne.</summary>
function KeywordConflict(AKind: TConstraintKind; const AState: TConstraintState): string;
begin
  Result := '';
  case AKind of
    TConstraintKind.ClassKeyword:
      if AState.HasRecord then
      begin
        Result := cTexts[TTypeRestrictionsGenericsText.ClassRecord].Text;
      end
      else if AState.ClassTypes > 0 then
      begin
        Result := cTexts[TTypeRestrictionsGenericsText.ClassWithClass].Text;
      end;
    TConstraintKind.RecordKeyword:
      if AState.HasClass then
      begin
        Result := cTexts[TTypeRestrictionsGenericsText.ClassRecord].Text;
      end
      else if AState.ClassTypes > 0 then
      begin
        Result := cTexts[TTypeRestrictionsGenericsText.RecordWithClass].Text;
      end
      else if AState.HasConstructor then
      begin
        Result := cTexts[TTypeRestrictionsGenericsText.RecordCtor].Text;
      end;
    TConstraintKind.ConstructorKeyword:
      if AState.HasRecord then
      begin
        Result := cTexts[TTypeRestrictionsGenericsText.CtorRecord].Text;
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

/// <summary>Meldung zur Einschränkung AText der Art AKind nach den bisherigen AState, '' ohne.</summary>
function ConstraintConflict(AKind: TConstraintKind; const AState: TConstraintState; const AText: string): string;
begin
  Result := '';
  case AKind of
    TConstraintKind.ClassType:
      if AState.ClassTypes > 0 then
      begin
        Result := cTexts[TTypeRestrictionsGenericsText.OneClass].Fmt([AText]);
      end
      else if AState.HasClass or AState.HasRecord then
      begin
        Result := cTexts[TTypeRestrictionsGenericsText.ClassAndKeyword].Fmt([AText]);
      end;
    TConstraintKind.Invalid:
      Result := cTexts[TTypeRestrictionsGenericsText.InvalidConstraint].Fmt([AText]);
  else
    Result := KeywordConflict(AKind, AState);
  end;
end;

/// <summary>Merkt die Einschränkung der Art AKind in AState.</summary>
procedure NoteConstraint(AKind: TConstraintKind; var AState: TConstraintState);
begin
  case AKind of
    TConstraintKind.ClassKeyword:
      AState.HasClass := True;
    TConstraintKind.RecordKeyword:
      AState.HasRecord := True;
    TConstraintKind.ConstructorKeyword:
      AState.HasConstructor := True;
    TConstraintKind.ClassType:
      Inc(AState.ClassTypes);
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

/// <summary>Varianten "F&lt;T, U&gt;" der Köpfe AHeads; AFits, wenn eine ACount Typparameter hat. False, wenn ein
/// Kopf keine Typparameter hat.</summary>
function DescribeVariants(const AHeads: TArray<TSyntaxNode>; ACount: Integer; out AVariants: string;
  out AFits: Boolean): Boolean;
var
  Head, Params: TSyntaxNode;
  Names: TArray<string>;
begin
  AFits := False;
  AVariants := '';
  Result := False;
  for Head in AHeads do
  begin
    Params := Head.FindChild(TSyntaxKind.GenericParams);
    if Params = nil then
    begin
      Exit;
    end;
    Names := TypeParamNames(Params);
    AFits := AFits or (Length(Names) = ACount);
    if AVariants <> '' then
    begin
      AVariants := AVariants + ', ';
    end;
    AVariants := AVariants + Head.Name + '<' + string.Join(', ', Names) + '>';
  end;
  Result := True;
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

/// <summary>Meldung für Typparameter an Operator, Destruktor oder Konstruktor in einem Typ der Art AHolderKind,
/// '' sonst.</summary>
function MemberGenericMessage(const AHead: TRoutineHead; AHolderKind: TSyntaxKind): string;
begin
  if AHead.Keyword = 'operator' then
  begin
    Result := cTexts[TTypeRestrictionsGenericsText.Operators].Text;
  end
  else if AHead.Keyword = 'destructor' then
  begin
    Result := cTexts[TTypeRestrictionsGenericsText.Destructors].Text;
  end
  else if AHead.IsClass and (AHead.Keyword = 'constructor') then
  begin
    Result := cTexts[TTypeRestrictionsGenericsText.ClassConstructors].Text;
  end
  // Mit dcc 13 belegt für Klassen (Cm.E2528); Records und object bleiben ungeprüft still.
  else if (AHead.Keyword = 'constructor') and (AHolderKind = TSyntaxKind.ClassType) then
  begin
    Result := cTexts[TTypeRestrictionsGenericsText.Constructors].Text;
  end
  else
  begin
    Result := '';
  end;
end;

function TGenericDeclarationInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(GenericDeclarationInvalidRuleId, TRuleSeverity.Error,
    cTexts[TTypeRestrictionsGenericsText.Title].Text);
end;

procedure TGenericDeclarationInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Types: TFileTypes;
  Root, InterfacePart: TSyntaxNode;
  Nodes: TList<TSyntaxNode>;
  Node: TSyntaxNode;
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

  /// <summary>Art der Einschränkung aus Datei und eingebauten Typen, sonst über den Index.</summary>
  function ResolvedConstraintKind(const AText: string; const AScope: TArray<string>): TConstraintKind;
  begin
    Result := ConstraintKind(Types, AText, AScope);
    if Result = TConstraintKind.Unknown then
    begin
      Result := IndexConstraintKind(AText, AScope);
    end;
  end;

  procedure CheckGroup(const AGroup: TArray<TGenericConstraint>; const AScope: TArray<string>);
  var
    Seen: TArray<string>;
    Constraint: TGenericConstraint;
    Kind: TConstraintKind;
    State: TConstraintState;
    Key, Message: string;
  begin
    Seen := nil;
    State := Default(TConstraintState);
    for Constraint in AGroup do
    begin
      Kind := ResolvedConstraintKind(Constraint.Text, AScope);
      Key := LowerCase(Constraint.Text);
      if MatchText(Key, Seen) and (Kind <> TConstraintKind.ClassType) then
      begin
        Report(Constraint.Range, cTexts[TTypeRestrictionsGenericsText.DuplicateConstraint].Fmt([Constraint.Text]));
        Continue;
      end;
      Seen := Seen + [Key];
      Message := ConstraintConflict(Kind, State, Constraint.Text);
      if Message <> '' then
      begin
        Report(Constraint.Range, Message);
      end;
      NoteConstraint(Kind, State);
    end;
  end;

  // Einschränkungen einer Typparameterliste: E2507, E2510, E2516, E2552, E2553, E2603.
  procedure CheckConstraints(AParams: TSyntaxNode);
  var
    Scope: TArray<string>;
    Group: TArray<TGenericConstraint>;
  begin
    Scope := ScopeTypeParams(AParams);
    for Group in ConstraintGroups(Tokens, AParams) do
    begin
      CheckGroup(Group, Scope);
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
    AReport.Add(mRange, cTexts[TTypeRestrictionsGenericsText.InstantiatedType].Fmt([OneLine(AContext.Text, ATypeNode)]),
      TRuleConfidence.High,
      [TRuleFix.Create(cTexts[TTypeRestrictionsGenericsText.RemoveType].Text,
        [TRuleEdit.Create(TTextRange.Create(Tokens[mBefore].StartPos,
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
        Report(HeaderNameRange(mInner), cTexts[TTypeRestrictionsGenericsText.LocalRoutine].Fmt([ADecl[mChild].Name,
          mHeader.Name]));
      end;
    end;
  end;

  // Generische Attributklasse: E2549.
  procedure CheckAttributeClass(ADecl: TSyntaxNode);
  var
    Ancestor: string;
    Depth: Integer;
  begin
    Ancestor := Types.ParentOf(ADecl.Name);
    Depth := 0;
    while (Ancestor <> '') and (Depth < 32) do
    begin
      if SameText(Ancestor, 'TCustomAttribute') then
      begin
        Report(TokenRangeAt(ADecl.StartOffset), cTexts[TTypeRestrictionsGenericsText.AttributeClass].Fmt([ADecl.Name]));
        Break;
      end;
      Ancestor := Types.ParentOf(Ancestor);
      Inc(Depth);
    end;
  end;

  /// <summary>Typparameterlisten innerhalb von ATypeNode, ohne Methodenzuordnungen.</summary>
  function InnerGenericParams(ATypeNode: TSyntaxNode): TArray<TSyntaxNode>;
  var
    Found: TArray<TSyntaxNode>;
  begin
    Found := nil;
    ATypeNode.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        // IEnumerator<T>.GetCurrent = GetCurrentGen nennt die Typparameter des Interfaces, deklariert keine
        // eigenen (#1325).
        Result := not ((ANode.Kind = TSyntaxKind.RoutineHeader) and ANode.IsMethodResolution);
        if Result and (ANode.Kind = TSyntaxKind.GenericParams) then
        begin
          Found := Found + [ANode];
        end;
      end);
    Result := Found;
  end;

  // Typparameter, die einen des umgebenden Typs verdecken: H2509.
  procedure CheckShadowing(ADecl, AParams, ATypeNode: TSyntaxNode);
  var
    Inner: TSyntaxNode;
    Names: TArray<string>;
    Child: Integer;
  begin
    Names := TypeParamNames(AParams);
    for Inner in InnerGenericParams(ATypeNode) do
    begin
      for Child := 0 to Inner.ChildCount - 1 do
      begin
        if (Inner[Child].Kind = TSyntaxKind.Identifier) and MatchText(Inner[Child].Name, Names) then
        begin
          Report(NodeRange(Inner[Child]), cTexts[TTypeRestrictionsGenericsText.HidesTypeParam].Fmt([Inner[Child].Name,
            ADecl.Name]));
        end;
      end;
    end;
  end;

  // Typdeklaration mit Typparametern: E2508, E2549, H2509.
  procedure CheckTypeDecl(ADecl: TSyntaxNode);
  var
    Params, TypeNode: TSyntaxNode;
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
      Report(TokenRangeAt(ADecl.StartOffset), cTexts[TTypeRestrictionsGenericsText.TypeNoParams].Fmt([ADecl.Name]));
      Exit;
    end;
    if TypeNode.Kind = TSyntaxKind.ClassType then
    begin
      CheckAttributeClass(ADecl);
    end;
    CheckShadowing(ADecl, Params, TypeNode);
  end;

  // Methoden mit eigenen Typparametern: E2528, E2529, E2533.
  procedure CheckMemberHeader(AHeader, AHolder: TSyntaxNode);
  var
    Head: TRoutineHead;
    Message, Name: string;
    Directive: TSyntaxNode;
  begin
    Head := TRoutineHead.Read(Tokens, AHeader);
    Message := MemberGenericMessage(Head, AHolder.Kind);
    if Message <> '' then
    begin
      Report(HeaderNameRange(AHeader), Message);
      Exit;
    end;
    for Name in VirtualDirectives do
    begin
      Directive := Head.Directive(Name);
      if Directive <> nil then
      begin
        Report(NodeRange(Directive), cTexts[TTypeRestrictionsGenericsText.VirtualMethods].Text);
        Exit;
      end;
    end;
  end;

  /// <summary>Steht im interface-Teil eine generische Routine AName?</summary>
  function DeclaredGenericInInterface(const AName: string): Boolean;
  var
    Child: Integer;
    Other, Header: TSyntaxNode;
  begin
    Result := False;
    if InterfacePart = nil then
    begin
      Exit;
    end;
    for Child := 0 to InterfacePart.ChildCount - 1 do
    begin
      Other := InterfacePart[Child];
      if (Other.Kind <> TSyntaxKind.RoutineDecl) or not SameText(Other.Name, AName) then
      begin
        Continue;
      end;
      Header := Other.FindChild(TSyntaxKind.RoutineHeader);
      if (Header <> nil) and (Header.FindChild(TSyntaxKind.GenericParams) <> nil) then
      begin
        Exit(True);
      end;
    end;
  end;

  /// <summary>Ist AHeader der Kopf einer globalen Routine (Holder ist ihre RoutineDecl)?</summary>
  function IsGlobalRoutine(AHeader, AHolder: TSyntaxNode): Boolean;
  begin
    Result := (AHolder.Kind = TSyntaxKind.RoutineDecl) and (Pos('.', AHeader.Name) = 0) and (AHolder.Parent <> nil);
    Result := Result and (AHolder.Parent.Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection,
      TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile, TSyntaxKind.UnitFile]);
  end;

  // Routine mit eigenen Typparametern: E2528, E2529, E2530, E2533, E2535.
  procedure CheckHeader(AHeader: TSyntaxNode);
  var
    Own, Holder: TSyntaxNode;
  begin
    Own := OwnGenericParams(Tokens, AHeader);
    if (Own = nil) or (AHeader.Parent = nil) then
    begin
      Exit;
    end;
    Holder := AHeader.Parent;
    if Holder.Kind = TSyntaxKind.InterfaceType then
    begin
      Report(HeaderNameRange(AHeader), cTexts[TTypeRestrictionsGenericsText.InterfaceMethods].Text);
    end
    else if Holder.Kind in [TSyntaxKind.ClassType, TSyntaxKind.RecordType, TSyntaxKind.ObjectType,
      TSyntaxKind.HelperType] then
    begin
      CheckMemberHeader(AHeader, Holder);
    end
    // Rumpf einer Routine aus dem interface-Teil: dort schon gemeldet.
    else if IsGlobalRoutine(AHeader, Holder) and not ((Holder.Parent.Kind = TSyntaxKind.ImplementationSection) and
      DeclaredGenericInInterface(AHeader.Name)) then
    begin
      Report(TTextRange.Create(HeaderNameRange(AHeader).StartPos, Own.EndPos),
        cTexts[TTypeRestrictionsGenericsText.GlobalRoutines].Text);
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

  /// <summary>Hängt die Köpfe AMethod direkt in ATypeNode an AHeads an.</summary>
  procedure AddMethodHeads(ATypeNode: TSyntaxNode; const AMethod: string; var AHeads: TArray<TSyntaxNode>);
  var
    Child: Integer;
  begin
    for Child := 0 to ATypeNode.ChildCount - 1 do
    begin
      if (ATypeNode[Child].Kind = TSyntaxKind.RoutineHeader) and SameText(ATypeNode[Child].Name, AMethod) then
      begin
        AHeads := AHeads + [ATypeNode[Child]];
      end;
    end;
  end;

  /// <summary>Köpfe AMethod der Klasse oder des Records AType samt Vorfahren der Datei; False, wenn die Kette
  /// außerhalb der Datei weitergeht.</summary>
  function MethodHeads(const AType, AMethod: string; out AHeads: TArray<TSyntaxNode>): Boolean;
  var
    Current: string;
    Decl, TypeNode: TSyntaxNode;
    Depth: Integer;
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
      AddMethodHeads(TypeNode, AMethod, AHeads);
      if (TypeNode.Kind <> TSyntaxKind.ClassType) or (TypeNode.ChildCount = 0) or
        (TypeNode[0].Kind <> TSyntaxKind.TypeReference) then
      begin
        Exit(True);
      end;
      Current := BareTypeName(TypeNode[0].Name);
      if SameText(Current, 'TObject') or (Types.DeclaredKind(Current) = TSyntaxKind.InterfaceType) then
      begin
        Exit(True);
      end;
      Inc(Depth);
    end;
  end;

  /// <summary>Ist AAccess (F&lt;…&gt;) das aufgerufene Ziel eines Aufrufs?</summary>
  function IsGenericCall(AAccess: TSyntaxNode): Boolean;
  begin
    Result := (AAccess.ChildCount = 2) and (AAccess[1].Kind = TSyntaxKind.GenericArgs) and (AAccess.Parent <> nil);
    Result := Result and (AAccess.Parent.Kind in [TSyntaxKind.Call, TSyntaxKind.CallStatement]) and
      (AAccess.Parent[0] = AAccess);
  end;

  /// <summary>Typ hinter X.F&lt;…&gt; mit dem Bezeichner AQualifier als X ('' ohne).</summary>
  function QualifiedCallType(AAccess, AQualifier: TSyntaxNode): string;
  begin
    Result := '';
    if SameText(AQualifier.Name, 'Self') then
    begin
      Result := EnclosingClass(AAccess, False);
    end
    else if ((EnclosingClass(AAccess, True) <> '') or (Pos('.', AQualifier.Name) = 0)) and
      (Types.DeclaredKind(AQualifier.Name) in [TSyntaxKind.ClassType, TSyntaxKind.RecordType]) then
    begin
      Result := AQualifier.Name;
    end;
  end;

  /// <summary>Klasse oder Record, deren Methode AAccess aufruft ('' unbekannt).</summary>
  function CallTypeName(AAccess: TSyntaxNode): string;
  var
    Target: TSyntaxNode;
  begin
    Result := '';
    Target := AAccess[0];
    if not SameText(Target.Name, AAccess.Name) then
    begin
      Exit;
    end;
    if Target.Kind = TSyntaxKind.Identifier then
    begin
      Result := EnclosingClass(AAccess, True);
    end
    else if (Target.Kind = TSyntaxKind.MemberAccess) and (Target.ChildCount = 1) and
      (Target[0].Kind = TSyntaxKind.Identifier) then
    begin
      Result := QualifiedCallType(AAccess, Target[0]);
    end;
  end;

  // Aufruf F<…> mit einer Zahl Typargumente, die keine Variante von F hat: E2551.
  procedure CheckCall(AAccess: TSyntaxNode);
  var
    TypeName, Variants: string;
    Heads: TArray<TSyntaxNode>;
    Count: Integer;
    Fits: Boolean;
  begin
    if not IsGenericCall(AAccess) then
    begin
      Exit;
    end;
    TypeName := CallTypeName(AAccess);
    if (TypeName = '') or not MethodHeads(TypeName, AAccess.Name, Heads) or (Heads = nil) then
    begin
      Exit;
    end;
    Count := AAccess[1].ChildCount;
    if DescribeVariants(Heads, Count, Variants, Fits) and not Fits then
    begin
      Report(NodeRange(AAccess), cTexts[TTypeRestrictionsGenericsText.NoVariant].Fmt([AAccess.Name, Count, Variants]));
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
          Report(NodeRange(Use), cTexts[TTypeRestrictionsGenericsText.ImplementationUse].Fmt([Routine.Name, Use.Name]));
        end;
      end;
    finally
      Symbols.Free;
    end;
  end;

  // class of eines parametrisierten Typs: E2548.
  procedure CheckClassOf(AClassOf: TSyntaxNode);
  begin
    if (AClassOf.ChildCount > 0) and (AClassOf[0].FindChild(TSyntaxKind.GenericArgs) <> nil) then
    begin
      Report(NodeRange(AClassOf[0]), cTexts[TTypeRestrictionsGenericsText.ClassOf].Text);
    end;
  end;

  // Parametrisierter Typ als Attribut: E2565.
  procedure CheckGenericAttribute(AAttribute: TSyntaxNode);
  var
    Item: TSyntaxNode;
    Generic: Boolean;
  begin
    if AAttribute.ChildCount = 0 then
    begin
      Exit;
    end;
    Item := AAttribute[0];
    Generic := Item.FindChild(TSyntaxKind.GenericArgs) <> nil;
    Generic := Generic or ((Item.Kind = TSyntaxKind.Call) and (Item.ChildCount > 0) and
      (Item[0].FindChild(TSyntaxKind.GenericArgs) <> nil));
    if Generic then
    begin
      Report(NodeRange(AAttribute), cTexts[TTypeRestrictionsGenericsText.AsAttribute].Text);
    end;
  end;

  procedure CheckNode(ANode: TSyntaxNode);
  begin
    case ANode.Kind of
      TSyntaxKind.GenericParams:
        CheckConstraints(ANode);
      TSyntaxKind.TypeDecl:
        CheckTypeDecl(ANode);
      TSyntaxKind.ClassOfType:
        CheckClassOf(ANode);
      TSyntaxKind.Attribute:
        CheckGenericAttribute(ANode);
      TSyntaxKind.RoutineHeader:
        CheckHeader(ANode);
      TSyntaxKind.MemberAccess:
        CheckCall(ANode);
      TSyntaxKind.RoutineDecl:
        CheckLocalRoutines(ANode);
    else
      // Übrige Werte bewusst ohne Wirkung.
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
    for Node in Nodes do
    begin
      CheckNode(Node);
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

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.TypeRestrictions.Generics', cTexts);

end.
