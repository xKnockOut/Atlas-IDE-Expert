unit Atlas.Common.Rules.Builtin.TypeRestrictions;

// Feste Sprachregeln für Typdeklarationen (#909, Gruppe Compiler vorab), die
// der Parser allein erkennt:
//   operator-declaration-invalid  class operator mit unbekanntem Namen
//                                 (#1030, E2393), falscher Parameterzahl
//                                 (E2517), ohne den eigenen Typ in den
//                                 Parametern (E2518) bzw. in Parameter oder
//                                 Ergebnis (E2521), Inc/Dec mit anderem
//                                 Ergebnis als dem ersten Parameter (E2519)
//                                 oder Assign ohne var vor dem ersten
//                                 Parameter (Delphi 13 meldet E2617 statt
//                                 E2464, Cm.E2464, #1380). Geprüft werden nur
//                                 Records: Einen class operator in einer
//                                 Klasse meldet Delphi 13 als E2123 (Regel
//                                 syntax, #1382), damit entfällt E2522
//                                 (Umwandlung in einen Vorfahren). Zum Rumpf
//                                 eines unbekannten Operators bzw. eines class
//                                 operator in einer Klasse gibt es keine
//                                 gültige Deklaration (wie E2037, Cm.E2393,
//                                 Cm.E2522, #1380).
//   generic-declaration-invalid   Generics, die Delphi ablehnt (#1029):
//                                 Einschränkungen class und record zugleich
//                                 (E2507), doppelt (E2603), widersprüchlich
//                                 (record und constructor, E2516), Klasse
//                                 neben class/record (E2552), zwei Klassen
//                                 (E2553), ungültiger Typ (E2510);
//                                 Typparameter an Aufzählung, Menge, Zeiger,
//                                 Alias, Helfer (E2508), Destruktor oder
//                                 Klassenkonstruktor (E2528), Operator
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
//                                 außerhalb von Datei und Index und in with).
//                                 E2570 (lokale Prozedur in generischer
//                                 Methode) bleibt aus, bis der Abgleich mit
//                                 Delphi 12/13 zeigt, dass es noch kommt.
//   type-restriction-violated     feste Sprachregeln für Records, Helfer,
//                                 Klassenkonstruktoren, inline und threadvar
//                                 (#994): virtuelle und andere verbotene
//                                 Direktiven in Records (E2379, E2463) und
//                                 Record-Helfern (E2598, E2475),
//                                 parameterlose Konstruktoren (E2394, E2471)
//                                 und Destruktoren (E2465) in Records, class-
//                                 Methoden ohne static (E2398); Felder in
//                                 Helfern (E2599), Destruktor (E2295) im
//                                 Class-Helfer, Vorfahr-Helfer für
//                                 fremde Typen (E2294), Helfer als Typ
//                                 (E2527) oder in generischem Kontext
//                                 (E2589); mehrere oder parametrisierte bzw.
//                                 virtuelle Klassenkonstruktoren (E2359,
//                                 E2360, E2534); Methoden, Properties,
//                                 Klassenmitglieder, Typen und Konstanten in
//                                 lokalen oder anonymen Records (E2433 bis
//                                 E2437); inline an virtuellen Methoden
//                                 (E2425), mit asm (E2426), an Konstruktoren
//                                 (E2442), mit offenen Arrays (E2439), mit
//                                 Variablen oder typisierten Konstanten des
//                                 implementation-Teils (E2441; echte
//                                 Konstanten, Typen und Routinen übersetzt
//                                 dcc, #1328),
//                                 mit Zugriff auf die umgebende Routine
//                                 (E2449) oder Aufruf eigener lokaler
//                                 Routinen (E2501); lokale, absolute oder
//                                 initialisierte threadvar (E2189, E2190,
//                                 E2194). Option disabledChecks nimmt Codes
//                                 aus. Korrekturen: Direktive entfernen bzw.
//                                 static ergänzen.
//   attribute-usage-invalid       Attribute des Compilers am falschen Ziel
//                                 (#1033): [Weak] an Feldern und Variablen,
//                                 deren Typ sicher weder Klasse noch
//                                 Interface ist (E2584), [Volatile] an Typ,
//                                 Routine oder Property (E2325), Weak,
//                                 Unsafe, Volatile oder Ref doppelt am
//                                 selben Ziel (E2326, nicht in sich
//                                 ausschließenden Zweigen); Argument eines
//                                 Attributs, das sicher eine Variable oder
//                                 Routine der Datei ist (E2448). Eigene
//                                 Attribute dürfen mehrfach stehen; ein Typ
//                                 Weak bzw. WeakAttribute in der Datei macht
//                                 die Regel für diesen Namen still.
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
//
// Typen gelten als gleich, wenn ihr Name ohne Unit-Präfix und Typargumente
// übereinstimmt. Steht in der Datei ein Alias auf den eigenen Typ, bleibt die
// Regel bei E2518, E2519, E2521 still. Operatoren, deren Namen Delphi nicht
// sicher ablehnt (True, False, OnesComplement), gelten als bekannt.
//
// Korrekturen: Name des nächstliegenden Operators (E2393), Ergebnis wie der
// erste Parameter (E2519), var vor dem ersten Parameter (E2617),
// Parameterliste nach Vorlage (E2517); jeweils in Deklaration und Rumpf.

interface

uses
  System.SysUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  /// <summary>Kopf einer Routine aus Syntaxbaum und Token: Schlüsselwort, class, Parameter, Ergebnis.</summary>
  TRoutineHead = record
    Header: TSyntaxNode;
    /// <summary>procedure, function, constructor, destructor oder operator in Kleinbuchstaben.</summary>
    Keyword: string;
    /// <summary>Steht class davor (class procedure, class operator, class constructor)?</summary>
    IsClass: Boolean;
    /// <summary>Parameter-Knoten in Reihenfolge (ein Knoten kann mehrere Namen tragen).</summary>
    Parameters: TArray<TSyntaxNode>;
    /// <summary>Ergebnistyp oder nil.</summary>
    ResultType: TSyntaxNode;
    /// <summary>Typparameter der Routine oder nil.</summary>
    GenericParams: TSyntaxNode;
    /// <summary>Kopf aus dem Knoten AHeader (RoutineHeader) mit den Token der Datei.</summary>
    class function Read(const ATokens: TArray<TPascalToken>; AHeader: TSyntaxNode): TRoutineHead; static;
    /// <summary>Zahl der Parameternamen ("A, B: T" zählt zwei).</summary>
    function ParameterCount: Integer;
    /// <summary>Trägt der Kopf die Direktive (virtual, static, inline …)?</summary>
    function HasDirective(const AName: string): Boolean;
    /// <summary>Knoten der Direktive oder nil.</summary>
    function Directive(const AName: string): TSyntaxNode;
  end;

  TOperatorDeclarationInvalidRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TGenericDeclarationInvalidRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TTypeRestrictionViolatedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TAttributeUsageInvalidRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TTypeInfoInvalidRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

const
  OperatorDeclarationInvalidRuleId = 'operator-declaration-invalid';
  TypeRestrictionViolatedRuleId = 'type-restriction-violated';
  GenericDeclarationInvalidRuleId = 'generic-declaration-invalid';
  AttributeUsageInvalidRuleId = 'attribute-usage-invalid';
  TypeInfoInvalidRuleId = 'typeinfo-invalid';

/// <summary>Name ohne Unit-Präfix und ohne Typargumente: "System.TList&lt;T&gt;" ergibt "TList".</summary>
function BareTypeName(const AName: string): string;

procedure RegisterTypeRestrictionRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Builtin.Inheritance,
  Atlas.Text.Fuzzy;

function BareTypeName(const AName: string): string;
var
  Index: Integer;
begin
  Result := Trim(AName);
  Index := Pos('<', Result);
  if Index > 0 then
    Result := Copy(Result, 1, Index - 1);
  Index := LastDelimiter('.', Result);
  if Index > 0 then
    Result := Copy(Result, Index + 1, MaxInt);
  Result := Trim(Result);
end;

{ TRoutineHead }

class function TRoutineHead.Read(const ATokens: TArray<TPascalToken>; AHeader: TSyntaxNode): TRoutineHead;
var
  Index, Inner: Integer;
  Child: TSyntaxNode;
begin
  Result := Default(TRoutineHead);
  Result.Header := AHeader;
  Index := TRoutineBody.TokenAt(ATokens, AHeader.StartOffset);
  while (Index < Length(ATokens)) and (ATokens[Index].Kind in [TPascalTokenKind.Comment,
    TPascalTokenKind.Directive]) do
    Inc(Index);
  if (Index < Length(ATokens)) and SameText(ATokens[Index].Text, 'class') then
  begin
    Result.IsClass := True;
    Index := TRoutineBody.NextToken(ATokens, Index);
  end;
  if (Index >= 0) and (Index < Length(ATokens)) then
    Result.Keyword := LowerCase(ATokens[Index].Text);
  for Index := 0 to AHeader.ChildCount - 1 do
  begin
    Child := AHeader[Index];
    case Child.Kind of
      TSyntaxKind.Parameters:
        for Inner := 0 to Child.ChildCount - 1 do
          if Child[Inner].Kind = TSyntaxKind.Parameter then
            Result.Parameters := Result.Parameters + [Child[Inner]];
      TSyntaxKind.TypeReference:
        Result.ResultType := Child;
      TSyntaxKind.GenericParams:
        if Result.GenericParams = nil then
          Result.GenericParams := Child;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;
end;

function TRoutineHead.ParameterCount: Integer;
var
  Parameter: TSyntaxNode;
begin
  Result := 0;
  for Parameter in Parameters do
    Inc(Result, Length(SplitString(Parameter.Name, ',')));
end;

function TRoutineHead.Directive(const AName: string): TSyntaxNode;
var
  Index: Integer;
begin
  for Index := 0 to Header.ChildCount - 1 do
    if (Header[Index].Kind = TSyntaxKind.Directive) and SameText(Header[Index].Name, AName) then
      Exit(Header[Index]);
  Result := nil;
end;

function TRoutineHead.HasDirective(const AName: string): Boolean;
begin
  Result := Directive(AName) <> nil;
end;
{ Gemeinsame Hilfen }

const
  // Eingebaute Typen, die sicher für sich stehen (kein Alias eines Typs der Datei).
  BuiltinTypeNames: array[0..33] of string = ('Integer', 'Cardinal', 'Int64', 'UInt64', 'NativeInt', 'NativeUInt',
    'ShortInt', 'SmallInt', 'LongInt', 'Byte', 'Word', 'LongWord', 'Int8', 'Int16', 'Int32', 'UInt8', 'UInt16',
    'UInt32', 'string', 'AnsiString', 'UnicodeString', 'WideString', 'ShortString', 'Char', 'AnsiChar', 'WideChar',
    'Single', 'Double', 'Extended', 'Currency', 'Real', 'Variant', 'Pointer', 'TDateTime');
  BooleanTypeNames: array[0..3] of string = ('Boolean', 'ByteBool', 'WordBool', 'LongBool');

type
  /// <summary>Typdeklarationen der Datei: Name, Knoten des Typs und Alias-Ziel.</summary>
  TFileTypes = record
    Names: TArray<string>;
    Types: TArray<TSyntaxNode>;
    /// <summary>Ziel bei type A = B (ohne type), sonst ''.</summary>
    AliasOf: TArray<string>;
    class function Collect(ARoot: TSyntaxNode): TFileTypes; static;
    /// <summary>Eintrag zu AName; eine vollständige Deklaration vor einer Vorwärtsdeklaration, -1 ohne.</summary>
    function IndexOf(const AName: string): Integer;
    /// <summary>Art der Deklaration AName in der Datei (ClassType, RecordType …); Error, wenn AName fehlt, ein
    /// Alias ist oder mehrdeutig deklariert ist.</summary>
    function DeclaredKind(const AName: string): TSyntaxKind;
    /// <summary>Namen, die denselben Typ meinen wie AName: AName und seine Aliase in der Datei.</summary>
    function SameNames(const AName: string): TArray<string>;
    /// <summary>Steht AName sicher für einen anderen Typ als die Namen in AOwn? Eingebaut oder in der Datei als
    /// eigener Typ (kein Alias) deklariert.</summary>
    function CertainlyOther(const AName: string; const AOwn: array of string): Boolean;
    /// <summary>Direkter Vorfahr der Klasse AName aus der Datei, '' ohne.</summary>
    function ParentOf(const AName: string): string;
  end;

class function TFileTypes.Collect(ARoot: TSyntaxNode): TFileTypes;
var
  Types: TFileTypes;
begin
  Types := Default(TFileTypes);
  ARoot.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      Index: Integer;
      Target: string;
    begin
      Result := True;
      if (ANode.Kind <> TSyntaxKind.TypeDecl) or (ANode.Name = '') then
        Exit;
      Target := '';
      for Index := 0 to ANode.ChildCount - 1 do
        if ANode[Index].Kind <> TSyntaxKind.GenericParams then
        begin
          if ANode[Index].Kind = TSyntaxKind.TypeReference then
            Target := ANode[Index].Name;
          Types.Names := Types.Names + [ANode.Name];
          Types.Types := Types.Types + [ANode[Index]];
          Types.AliasOf := Types.AliasOf + [Target];
          Break;
        end;
    end);
  Result := Types;
end;

function TFileTypes.IndexOf(const AName: string): Integer;
var
  Index: Integer;
begin
  Result := -1;
  for Index := 0 to High(Names) do
    if SameText(Names[Index], AName) then
    begin
      if Types[Index].Kind <> TSyntaxKind.ForwardType then
        Exit(Index);
      if Result < 0 then
        Result := Index;
    end;
end;

function TFileTypes.DeclaredKind(const AName: string): TSyntaxKind;
var
  Index: Integer;
  Found: Boolean;
begin
  Result := TSyntaxKind.Error;
  Found := False;
  for Index := 0 to High(Names) do
    if SameText(Names[Index], AName) and (Types[Index].Kind <> TSyntaxKind.ForwardType) then
    begin
      if (AliasOf[Index] <> '') or (Found and (Types[Index].Kind <> Result)) then
        Exit(TSyntaxKind.Error);
      Result := Types[Index].Kind;
      Found := True;
    end;
end;

function TFileTypes.SameNames(const AName: string): TArray<string>;
var
  Index: Integer;
  Changed: Boolean;
begin
  Result := [BareTypeName(AName)];
  repeat
    Changed := False;
    for Index := 0 to High(Names) do
      if (AliasOf[Index] <> '') and MatchText(BareTypeName(AliasOf[Index]), Result) and
        not MatchText(Names[Index], Result) then
      begin
        Result := Result + [Names[Index]];
        Changed := True;
      end;
  until not Changed;
end;

function TFileTypes.CertainlyOther(const AName: string; const AOwn: array of string): Boolean;
var
  Bare: string;
  Index: Integer;
begin
  Bare := BareTypeName(AName);
  if (Bare = '') or MatchText(Bare, AOwn) then
    Exit(False);
  Index := IndexOf(Bare);
  if Index >= 0 then
    Exit(AliasOf[Index] = '');
  Result := MatchText(Bare, BuiltinTypeNames) or MatchText(Bare, BooleanTypeNames);
end;

function TFileTypes.ParentOf(const AName: string): string;
var
  Index: Integer;
begin
  Result := '';
  Index := IndexOf(AName);
  if (Index >= 0) and (Types[Index].Kind = TSyntaxKind.ClassType) and (Types[Index].ChildCount > 0) and
    (Types[Index][0].Kind = TSyntaxKind.TypeReference) then
    Result := BareTypeName(Types[Index][0].Name);
end;

/// <summary>Name des Typs, zu dem der Mitglieds-Kopf AHeader gehört ('' ohne).</summary>
function ContainerName(AHeader: TSyntaxNode): string;
begin
  Result := '';
  if (AHeader.Parent <> nil) and (AHeader.Parent.Parent <> nil) and
    (AHeader.Parent.Parent.Kind = TSyntaxKind.TypeDecl) then
    Result := AHeader.Parent.Parent.Name;
end;

/// <summary>Token des Namens im Kopf (bei TFoo.Bar das von Bar); -1 ohne.</summary>
function NameToken(const ATokens: TArray<TPascalToken>; AHeader: TSyntaxNode): Integer;
var
  Index, Last: Integer;
  Name: string;
begin
  Name := AHeader.Name;
  if LastDelimiter('.', Name) > 0 then
    Name := Copy(Name, LastDelimiter('.', Name) + 1, MaxInt);
  Last := -1;
  Index := TRoutineBody.TokenAt(ATokens, AHeader.StartOffset);
  while (Index < Length(ATokens)) and (ATokens[Index].Offset < AHeader.EndOffset) do
  begin
    if ATokens[Index].IsSymbol('(') or ATokens[Index].IsSymbol(':') or ATokens[Index].IsSymbol(';') or
      ATokens[Index].IsSymbol('<') then
      Break;
    if SameText(ATokens[Index].Text, Name) then
      Last := Index;
    Inc(Index);
  end;
  Result := Last;
end;

function TokenRange(const AToken: TPascalToken): TTextRange;
begin
  Result := TTextRange.Create(AToken.StartPos, AToken.EndPos);
end;

function NodeRange(ANode: TSyntaxNode): TTextRange;
begin
  Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
end;

/// <summary>Text eines Knotens in einer Zeile, ohne doppelte Leerzeichen, für Meldungen.</summary>
function OneLine(const AText: string; ANode: TSyntaxNode): string;
var
  Text: string;
begin
  if ANode = nil then
    Exit('');
  Text := TRoutineBody.TextOf(AText, ANode);
  Text := StringReplace(StringReplace(Text, #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]);
  while Pos('  ', Text) > 0 do
    Text := StringReplace(Text, '  ', ' ', [rfReplaceAll]);
  Result := Trim(Text);
end;

/// <summary>Text eines Knotens ohne Zeilenumbrüche und doppelte Leerzeichen, für Vergleiche.</summary>
function Squeezed(const AText: string; ANode: TSyntaxNode): string;
begin
  Result := LowerCase(OneLine(AText, ANode));
end;

/// <summary>Rümpfe AQualified (TFoo.Bar, auch TAussen.TFoo.Bar) mit gleicher Parameterliste und gleichem
/// Ergebnis wie AHead.</summary>
function ImplementationHeads(const AText: string; const ATokens: TArray<TPascalToken>; ARoot: TSyntaxNode;
  const AQualified: string; const AHead: TRoutineHead): TArray<TRoutineHead>;
var
  Found: TArray<TRoutineHead>;
  Params, ResultText: string;
begin
  Found := nil;
  Params := Squeezed(AText, AHead.Header.FindChild(TSyntaxKind.Parameters));
  ResultText := Squeezed(AText, AHead.ResultType);
  ARoot.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      Head: TRoutineHead;
    begin
      Result := ANode.Kind <> TSyntaxKind.RoutineHeader;
      if (ANode.Kind = TSyntaxKind.RoutineHeader) and (ANode.Parent <> nil) and
        (ANode.Parent.Kind = TSyntaxKind.RoutineDecl) and (SameText(ANode.Name, AQualified) or
        EndsText('.' + AQualified, ANode.Name)) then
      begin
        Head := TRoutineHead.Read(ATokens, ANode);
        if (Squeezed(AText, ANode.FindChild(TSyntaxKind.Parameters)) = Params) and
          (Squeezed(AText, Head.ResultType) = ResultText) then
          Found := Found + [Head];
      end;
    end);
  Result := Found;
end;

{ TOperatorDeclarationInvalidRule }

type
{$SCOPEDENUMS ON}
  /// <summary>Art eines Operators für operator-declaration-invalid (#1030).</summary>
  TOperatorShape = (Unknown, Tolerated, Unary, Conversion, Binary, Comparison, Managed, Assign);
{$SCOPEDENUMS OFF}

const
  UnaryOperators: array[0..6] of string = ('Negative', 'Positive', 'Inc', 'Dec', 'LogicalNot', 'Trunc', 'Round');
  ConversionOperators: array[0..1] of string = ('Implicit', 'Explicit');
  ComparisonOperators: array[0..5] of string = ('Equal', 'NotEqual', 'GreaterThan', 'GreaterThanOrEqual',
    'LessThan', 'LessThanOrEqual');
  BinaryOperators: array[0..14] of string = ('In', 'Add', 'Subtract', 'Multiply', 'Divide', 'IntDivide', 'Modulus',
    'LeftShift', 'RightShift', 'LogicalAnd', 'LogicalOr', 'LogicalXor', 'BitwiseAnd', 'BitwiseOr', 'BitwiseXor');
  ManagedOperators: array[0..1] of string = ('Initialize', 'Finalize');
  // Namen, die Delphi womöglich kennt; ohne Prüfung.
  ToleratedOperators: array[0..2] of string = ('True', 'False', 'OnesComplement');

function OperatorShape(const AName: string): TOperatorShape;
begin
  if MatchText(AName, UnaryOperators) then
    Result := TOperatorShape.Unary
  else if MatchText(AName, ConversionOperators) then
    Result := TOperatorShape.Conversion
  else if MatchText(AName, ComparisonOperators) then
    Result := TOperatorShape.Comparison
  else if MatchText(AName, BinaryOperators) then
    Result := TOperatorShape.Binary
  else if MatchText(AName, ManagedOperators) then
    Result := TOperatorShape.Managed
  else if SameText(AName, 'Assign') then
    Result := TOperatorShape.Assign
  else if MatchText(AName, ToleratedOperators) then
    Result := TOperatorShape.Tolerated
  else
    Result := TOperatorShape.Unknown;
end;

function KnownOperators: TArray<string>;
var
  Name: string;
begin
  Result := nil;
  for Name in UnaryOperators do
    Result := Result + [Name];
  for Name in ConversionOperators do
    Result := Result + [Name];
  for Name in ComparisonOperators do
    Result := Result + [Name];
  for Name in BinaryOperators do
    Result := Result + [Name];
  for Name in ManagedOperators do
    Result := Result + [Name];
  Result := Result + ['Assign'];
end;

function TOperatorDeclarationInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(OperatorDeclarationInvalidRuleId, TRuleSeverity.Error,
    'class operator falsch deklariert');
end;

procedure TOperatorDeclarationInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Types: TFileTypes;
  Headers: TList<TSyntaxNode>;
  Header: TSyntaxNode;

  /// <summary>Edits für Deklaration und gleiche Rümpfe; AEdit liefert je Kopf die Änderung.</summary>
  function BothHeads(const AOwn: string; const AHead: TRoutineHead;
    const AEdit: TFunc<TRoutineHead, TArray<TRuleEdit>>): TArray<TRuleEdit>;
  var
    Body: TRoutineHead;
  begin
    Result := AEdit(AHead);
    for Body in ImplementationHeads(AContext.Text, Tokens, AContext.Tree.Root, AOwn + '.' +
      Copy(AHead.Header.Name, LastDelimiter('.', AHead.Header.Name) + 1, MaxInt), AHead) do
      Result := Result + AEdit(Body);
  end;

  function RenameFix(const AOwn: string; const AHead: TRoutineHead; const ANew: string): TRuleFix;
  begin
    Result := TRuleFix.Create('In ' + ANew + ' umbenennen', BothHeads(AOwn, AHead,
      function(AOne: TRoutineHead): TArray<TRuleEdit>
      var
        Index: Integer;
      begin
        Result := nil;
        Index := NameToken(Tokens, AOne.Header);
        if Index >= 0 then
          Result := [TRuleEdit.Create(TokenRange(Tokens[Index]), ANew)];
      end));
  end;

  function ResultFix(const AOwn: string; const AHead: TRoutineHead; const ANew, ATitle: string): TRuleFix;
  begin
    Result := TRuleFix.Create(ATitle, BothHeads(AOwn, AHead,
      function(AOne: TRoutineHead): TArray<TRuleEdit>
      begin
        Result := nil;
        if AOne.ResultType <> nil then
          Result := [TRuleEdit.Create(NodeRange(AOne.ResultType), ANew)];
      end));
  end;

  function VarFix(const AOwn: string; const AHead: TRoutineHead): TRuleFix;
  begin
    Result := TRuleFix.Create('var vor den ersten Parameter setzen', BothHeads(AOwn, AHead,
      function(AOne: TRoutineHead): TArray<TRuleEdit>
      var
        Param: TSyntaxNode;
        Index: Integer;
        Depth: Integer;
      begin
        Result := nil;
        if AOne.Parameters = nil then
          Exit;
        Param := AOne.Parameters[0];
        Index := TRoutineBody.TokenAt(Tokens, Param.StartOffset);
        Depth := 0;
        while (Index < Length(Tokens)) and (Tokens[Index].Offset < Param.EndOffset) do
        begin
          if Tokens[Index].IsSymbol('[') then
            Inc(Depth)
          else if Tokens[Index].IsSymbol(']') then
            Dec(Depth)
          else if (Depth = 0) and (Tokens[Index].IsKeyword('const') or SameText(Tokens[Index].Text, 'out') or
            SameText(Tokens[Index].Text, 'constref')) then
          begin
            Result := [TRuleEdit.Create(TokenRange(Tokens[Index]), 'var')];
            Exit;
          end
          else if (Depth = 0) and (Tokens[Index].Kind = TPascalTokenKind.Identifier) then
          begin
            Result := [TRuleEdit.Create(TTextRange.Create(Tokens[Index].StartPos, Tokens[Index].StartPos), 'var ')];
            Exit;
          end;
          Inc(Index);
        end;
      end));
  end;

  function ParametersFix(const AOwn: string; const AHead: TRoutineHead; const ATemplate: string): TRuleFix;
  begin
    Result := TRuleFix.Create('Parameter nach Vorlage: ' + ATemplate, BothHeads(AOwn, AHead,
      function(AOne: TRoutineHead): TArray<TRuleEdit>
      var
        Parameters: TSyntaxNode;
        Index: Integer;
      begin
        Result := nil;
        Parameters := AOne.Header.FindChild(TSyntaxKind.Parameters);
        if Parameters <> nil then
        begin
          Result := [TRuleEdit.Create(NodeRange(Parameters), ATemplate)];
          Exit;
        end;
        Index := NameToken(Tokens, AOne.Header);
        if Index >= 0 then
          Result := [TRuleEdit.Create(TTextRange.Create(Tokens[Index].EndPos, Tokens[Index].EndPos), ATemplate)];
      end));
  end;

  procedure Report(const ARange: TTextRange; const AMessage: string; const AFixes: TArray<TRuleFix>);
  begin
    AReport.Add(ARange, AMessage, TRuleConfidence.High, AFixes);
  end;

  /// <summary>E2037 (#1380): Die Deklaration lehnt dcc ab, ihre Rümpfe passen deshalb zu nichts.</summary>
  procedure ReportBodies(const AOwn: string; const AHead: TRoutineHead);
  var
    mBody: TRoutineHead;
    mName: Integer;
  begin
    for mBody in ImplementationHeads(AContext.Text, Tokens, AContext.Tree.Root, AOwn + '.' + AHead.Header.Name,
      AHead) do
    begin
      mName := NameToken(Tokens, mBody.Header);
      if mName >= 0 then
        Report(TokenRange(Tokens[mName]), Format('Zu %s.%s gibt es keine gültige Deklaration; der Rumpf passt zu ' +
          'nichts (wie E2037).', [AOwn, AHead.Header.Name]), nil);
    end;
  end;

  procedure CheckOperator(AHeader: TSyntaxNode);
  var
    Head: TRoutineHead;
    Own, Name, Closest, Other, Template: string;
    OwnNames, ParamTypes: TArray<string>;
    Shape: TOperatorShape;
    Range: TTextRange;
    Index, Count, Expected: Integer;
    Param: TSyntaxNode;
    HasOwn, Certain: Boolean;
  begin
    Head := TRoutineHead.Read(Tokens, AHeader);
    if not Head.IsClass or (Head.Keyword <> 'operator') then
      Exit;
    Own := ContainerName(AHeader);
    Name := AHeader.Name;
    Index := NameToken(Tokens, AHeader);
    if (Own = '') or (Name = '') or (Index < 0) or not IsValidIdent(Name) then
      Exit;
    // Klassenoperatoren gibt es unter Win32 und Win64 nur in Records: In einer Klasse meldet syntax die
    // Deklaration (E2123, #1382), hier bleibt nur der Rumpf, der zu nichts passt (Cm.E2522, #1380).
    if AHeader.Parent.Kind = TSyntaxKind.ClassType then
    begin
      ReportBodies(Own, Head);
      Exit;
    end;
    Range := TokenRange(Tokens[Index]);
    Shape := OperatorShape(Name);
    if Shape = TOperatorShape.Unknown then
    begin
      Closest := TTextFuzzy.Closest(Name, KnownOperators);
      if Closest <> '' then
        Report(Range, Format('Unbekannter Operator %s; gemeint ist wohl %s (wie E2393).', [Name, Closest]),
          [RenameFix(Own, Head, Closest)])
      else
        Report(Range, Format('Unbekannter Operator %s (wie E2393).', [Name]), nil);
      ReportBodies(Own, Head);
      Exit;
    end;
    if Shape = TOperatorShape.Tolerated then
      Exit;
    OwnNames := Types.SameNames(Own);
    ParamTypes := nil;
    for Param in Head.Parameters do
      for Count := 1 to Length(SplitString(Param.Name, ',')) do
        if (Param.ChildCount > 0) and (Param[Param.ChildCount - 1].Kind = TSyntaxKind.TypeReference) then
          ParamTypes := ParamTypes + [Param[Param.ChildCount - 1].Name]
        else
          ParamTypes := ParamTypes + [''];
    // Parameterzahl (E2517).
    case Shape of
      TOperatorShape.Unary, TOperatorShape.Conversion, TOperatorShape.Managed:
        Expected := 1;
    else
      Expected := 2;
    end;
    Count := Head.ParameterCount;
    if Count <> Expected then
    begin
      case Shape of
        TOperatorShape.Unary:
          Template := '(const A: ' + Own + ')';
        TOperatorShape.Managed:
          Template := '(out Dest: ' + Own + ')';
        TOperatorShape.Assign:
          Template := '(var Dest: ' + Own + '; const [ref] Src: ' + Own + ')';
        TOperatorShape.Binary, TOperatorShape.Comparison:
          Template := '(const A, B: ' + Own + ')';
      else
        Template := '';
      end;
      if Template <> '' then
        Report(Range, Format('Der Operator %s muss %d Parameter haben (wie E2517).', [Name, Expected]),
          [ParametersFix(Own, Head, Template)])
      else
        Report(Range, Format('Der Operator %s muss %d Parameter haben (wie E2517).', [Name, Expected]), nil);
      Exit;
    end;
    // Eigener Typ in den Parametern (E2518) bzw. in Parameter oder Ergebnis (E2521).
    HasOwn := False;
    Certain := True;
    for Other in ParamTypes do
    begin
      HasOwn := HasOwn or MatchText(BareTypeName(Other), OwnNames);
      Certain := Certain and Types.CertainlyOther(Other, OwnNames);
    end;
    if Shape = TOperatorShape.Conversion then
    begin
      if Head.ResultType <> nil then
      begin
        HasOwn := HasOwn or MatchText(BareTypeName(Head.ResultType.Name), OwnNames);
        Certain := Certain and Types.CertainlyOther(Head.ResultType.Name, OwnNames);
      end;
      if not HasOwn and Certain then
      begin
        Report(Range, Format('%s muss %s als Parameter oder Ergebnis haben (wie E2521).', [Name, Own]), nil);
        Exit;
      end;
    end
    else if not HasOwn and Certain and (Shape <> TOperatorShape.Managed) then
    begin
      Report(Range, Format('Der Operator %s muss %s in mindestens einem Parameter haben (wie E2518).', [Name, Own]),
        nil);
      Exit;
    end;
    // Vergleiche mit anderem Ergebnis als Boolean übersetzt dcc (Spring4D Persistence.Criteria liefert
    // ICriterion; OP1-OP5, #1328); die Prüfung auf E2520 ist entfallen.
    // Inc und Dec liefern den Typ des Parameters (E2519).
    if MatchText(Name, ['Inc', 'Dec']) and (Head.ResultType <> nil) and (ParamTypes[0] <> '') and
      not SameText(BareTypeName(Head.ResultType.Name), BareTypeName(ParamTypes[0])) and
      Types.CertainlyOther(Head.ResultType.Name, Types.SameNames(ParamTypes[0])) and
      Types.CertainlyOther(ParamTypes[0], Types.SameNames(Head.ResultType.Name)) then
    begin
      Report(Range, Format('%s muss denselben Typ liefern wie den ersten Parameter, hier %s (wie E2519).',
        [Name, ParamTypes[0]]), [ResultFix(Own, Head, ParamTypes[0], ParamTypes[0] + ' als Ergebnis')]);
      Exit;
    end;
    // Assign eines Managed Records: erster Parameter var; Delphi 13 meldet E2617 (Cm.E2464, #1380).
    if (Shape = TOperatorShape.Assign) and (Head.Parameters <> nil) and
      (Head.Parameters[0].Modifier <> TParameterModifier.VarParam) then
      Report(Range, 'Der erste Parameter von Assign muss ein var-Parameter des eigenen Typs sein (wie E2617).',
        [VarFix(Own, Head)]);
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'operator') then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Types := TFileTypes.Collect(AContext.Tree.Root);
  Headers := TList<TSyntaxNode>.Create;
  try
    AContext.Tree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := ANode.Kind <> TSyntaxKind.RoutineDecl;
        // Operatoren gibt es nur in Records; Köpfe in Klassen nur für die Rümpfe (E2037, #1380).
        if (ANode.Kind = TSyntaxKind.RoutineHeader) and (ANode.Parent <> nil) and
          (ANode.Parent.Kind in [TSyntaxKind.RecordType, TSyntaxKind.ClassType]) then
          Headers.Add(ANode);
      end);
    for Header in Headers do
      CheckOperator(Header);
  finally
    Headers.Free;
  end;
end;

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
  // Mitglieder von TObject, die im Rumpf einer Methode ohne Self sichtbar sind (E2506).
  ObjectMemberNames: array[0..33] of string = ('Create', 'Destroy', 'Free', 'DisposeOf', 'Disposed', 'ClassName',
    'ClassNameIs', 'ClassType', 'ClassParent', 'ClassInfo', 'InstanceSize', 'InheritsFrom', 'MethodAddress',
    'MethodName', 'FieldAddress', 'GetInterface', 'GetInterfaceEntry', 'GetInterfaceTable', 'Dispatch',
    'DefaultHandler', 'NewInstance', 'FreeInstance', 'InitInstance', 'CleanupInstance', 'AfterConstruction',
    'BeforeDestruction', 'SafeCallException', 'Equals', 'GetHashCode', 'ToString', 'UnitName', 'UnitScope',
    'QualifiedClassName', 'CheckDisposed');

/// <summary>Namen der Typparameter (Identifier-Kinder) von AParams.</summary>
function TypeParamNames(AParams: TSyntaxNode): TArray<string>;
var
  Index: Integer;
begin
  Result := nil;
  if AParams = nil then
    Exit;
  for Index := 0 to AParams.ChildCount - 1 do
    if AParams[Index].Kind = TSyntaxKind.Identifier then
      Result := Result + [AParams[Index].Name];
end;

/// <summary>Eigene Typparameter des Kopfs: bei TFoo&lt;T&gt;.Bar&lt;U&gt; die von Bar, nil ohne.</summary>
function OwnGenericParams(const ATokens: TArray<TPascalToken>; AHeader: TSyntaxNode): TSyntaxNode;
var
  Dots, Component, Depth, Index, Seen, Own, Child: Integer;
begin
  Result := nil;
  if (AHeader.Parent = nil) or (AHeader.Parent.Kind <> TSyntaxKind.RoutineDecl) or (Pos('.', AHeader.Name) = 0) then
    Exit(AHeader.FindChild(TSyntaxKind.GenericParams));
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
        Break;
      if ATokens[Index].IsSymbol('<') then
      begin
        if Depth = 0 then
        begin
          Inc(Seen);
          if Component = Dots then
            Own := Seen;
        end;
        Inc(Depth);
      end
      else if ATokens[Index].IsSymbol('>') then
        Dec(Depth)
      else if ATokens[Index].IsSymbol('>>') then
        Dec(Depth, 2)
      else if (Depth = 0) and ATokens[Index].IsSymbol('.') then
        Inc(Component);
    end;
    Inc(Index);
  end;
  if Own < 0 then
    Exit;
  Seen := -1;
  for Child := 0 to AHeader.ChildCount - 1 do
    if AHeader[Child].Kind = TSyntaxKind.GenericParams then
    begin
      Inc(Seen);
      if Seen = Own then
        Exit(AHeader[Child]);
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
      Group := Group + [Current];
    Current := Default(TGenericConstraint);
  end;

  procedure CloseGroup;
  begin
    Flush;
    if Group <> nil then
      Groups := Groups + [Group];
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
      Continue;
    if Token.IsSymbol('<') then
    begin
      Inc(Depth);
      if Depth = 1 then
        Continue;
    end
    else if Token.IsSymbol('>') or Token.IsSymbol('>=') or Token.IsSymbol('>>') then
    begin
      if Token.IsSymbol('>>') then
        Dec(Depth, 2)
      else
        Dec(Depth);
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
          Flush;
        Continue;
      end;
      if Token.IsSymbol(';') then
      begin
        CloseGroup;
        Continue;
      end;
    end;
    if not InConstraints then
      Continue;
    if Current.Text = '' then
      Current.Range.StartPos := Token.StartPos;
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
    Exit(TConstraintKind.ClassKeyword);
  if SameText(AText, 'record') then
    Exit(TConstraintKind.RecordKeyword);
  if SameText(AText, 'constructor') then
    Exit(TConstraintKind.ConstructorKeyword);
  Result := TConstraintKind.Unknown;
  Bare := BareTypeName(AText);
  if (Bare = '') or MatchText(Bare, AScope) then
    Exit;
  Qualified := Pos('.', Copy(AText, 1, Pos('<', AText + '<') - 1)) > 0;
  if Qualified then
  begin
    if StartsText('System.', AText) and (MatchText(Bare, BuiltinTypeNames) or MatchText(Bare, BooleanTypeNames)) then
      Result := TConstraintKind.Invalid;
    Exit;
  end;
  if ATypes.IndexOf(Bare) >= 0 then
  begin
    Kind := ATypes.DeclaredKind(Bare);
    if Kind = TSyntaxKind.ClassType then
      Result := TConstraintKind.ClassType
    else if Kind = TSyntaxKind.InterfaceType then
      Result := TConstraintKind.InterfaceType
    else if Kind in InvalidConstraintKinds then
      Result := TConstraintKind.Invalid;
    Exit;
  end;
  if SameText(Bare, 'TObject') then
    Result := TConstraintKind.ClassType
  else if MatchText(Bare, BuiltinTypeNames) or MatchText(Bare, BooleanTypeNames) then
    Result := TConstraintKind.Invalid;
end;

/// <summary>Typparameter der umgebenden generischen Typen von ANode und von ANode selbst.</summary>
function ScopeTypeParams(ANode: TSyntaxNode): TArray<string>;
var
  Node: TSyntaxNode;
begin
  Result := nil;
  if ANode.Kind = TSyntaxKind.GenericParams then
    Result := TypeParamNames(ANode);
  Node := ANode.Parent;
  while Node <> nil do
  begin
    if Node.Kind = TSyntaxKind.TypeDecl then
      Result := Result + TypeParamNames(Node.FindChild(TSyntaxKind.GenericParams));
    Node := Node.Parent;
  end;
end;

/// <summary>Typknoten einer Typdeklaration (das erste Kind außer den Typparametern), nil ohne.</summary>
function TypeOfDecl(ADecl: TSyntaxNode): TSyntaxNode;
var
  Index: Integer;
begin
  for Index := 0 to ADecl.ChildCount - 1 do
    if ADecl[Index].Kind <> TSyntaxKind.GenericParams then
      Exit(ADecl[Index]);
  Result := nil;
end;

/// <summary>Namen, die ein Knoten deklariert ("A,B" ergibt beide); leer bei Knoten ohne Deklaration.</summary>
function DeclaredNames(ANode: TSyntaxNode): TArray<string>;
var
  Name: string;
begin
  Result := nil;
  case ANode.Kind of
    TSyntaxKind.Parameter, TSyntaxKind.VarDecl, TSyntaxKind.ConstDecl, TSyntaxKind.TypeDecl, TSyntaxKind.Field,
    TSyntaxKind.PropertyDecl, TSyntaxKind.InlineVar, TSyntaxKind.InlineConst, TSyntaxKind.ForStatement,
    TSyntaxKind.ForInStatement, TSyntaxKind.ExceptionHandler, TSyntaxKind.RoutineHeader:
      for Name in SplitString(ANode.Name, ',') do
        if Trim(Name) <> '' then
          Result := Result + [Trim(Name)];
    TSyntaxKind.Identifier:
      if (ANode.Parent <> nil) and (ANode.Parent.Kind in [TSyntaxKind.GenericParams, TSyntaxKind.EnumType]) then
        Result := [ANode.Name];
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

/// <summary>Alle Namen, die unterhalb von ANode deklariert sind.</summary>
function NamesBelow(ANode: TSyntaxNode): TArray<string>;
var
  Names: TArray<string>;
begin
  Names := nil;
  ANode.Walk(
    function(AChild: TSyntaxNode): Boolean
    begin
      Result := True;
      Names := Names + DeclaredNames(AChild);
    end);
  Result := Names;
end;

/// <summary>Namen, die der Abschnitt ASection auf oberster Ebene deklariert (Typen, Werte der Aufzählungen,
/// Konstanten, Variablen, Routinen ohne Punkt).</summary>
function SectionNames(ASection: TSyntaxNode): TArray<string>;
var
  Index, Inner: Integer;
  Child, Decl: TSyntaxNode;
begin
  Result := nil;
  if ASection = nil then
    Exit;
  for Index := 0 to ASection.ChildCount - 1 do
  begin
    Child := ASection[Index];
    case Child.Kind of
      TSyntaxKind.TypeSection, TSyntaxKind.ConstSection, TSyntaxKind.VarSection:
        for Inner := 0 to Child.ChildCount - 1 do
        begin
          Decl := Child[Inner];
          Result := Result + DeclaredNames(Decl);
          if (Decl.Kind = TSyntaxKind.TypeDecl) and (TypeOfDecl(Decl) <> nil) and
            (TypeOfDecl(Decl).Kind = TSyntaxKind.EnumType) then
            Result := Result + NamesBelow(TypeOfDecl(Decl));
        end;
      TSyntaxKind.RoutineDecl:
        if Pos('.', Child.Name) = 0 then
          Result := Result + [Child.Name];
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;
end;

/// <summary>Namen des implementation-Teils, die eine Inline-Routine aus dem interface-Teil verwenden darf: echte
/// Konstanten, Typen samt Aufzählungswerten und Routinen. dcc übersetzt das (mORMot2, Clipper2 in Graphics32; TR1,
/// TR2, TR4, TR8; dcc-Lauf vom 29.10.2026, #1328); E2441 bleibt für Variablen und typisierte Konstanten (TG1,
/// TG4).</summary>
function InlineUsableNames(ASection: TSyntaxNode): TArray<string>;
var
  mIndex, mInner: Integer;
  mChild, mDecl: TSyntaxNode;
begin
  Result := nil;
  if ASection = nil then
    Exit;
  for mIndex := 0 to ASection.ChildCount - 1 do
  begin
    mChild := ASection[mIndex];
    case mChild.Kind of
      TSyntaxKind.ConstSection:
        for mInner := 0 to mChild.ChildCount - 1 do
        begin
          mDecl := mChild[mInner];
          // Typisierte Konstanten haben Typ und Wert als Kinder.
          if (mDecl.Kind = TSyntaxKind.ConstDecl) and (mDecl.ChildCount < 2) then
            Result := Result + DeclaredNames(mDecl);
        end;
      TSyntaxKind.TypeSection:
        for mInner := 0 to mChild.ChildCount - 1 do
        begin
          mDecl := mChild[mInner];
          if mDecl.Kind = TSyntaxKind.TypeDecl then
            Result := Result + DeclaredNames(mDecl);
          if (mDecl.Kind = TSyntaxKind.TypeDecl) and (TypeOfDecl(mDecl) <> nil) and
            (TypeOfDecl(mDecl).Kind = TSyntaxKind.EnumType) then
            Result := Result + NamesBelow(TypeOfDecl(mDecl));
        end;
      TSyntaxKind.RoutineDecl:
        if Pos('.', mChild.Name) = 0 then
          Result := Result + [mChild.Name];
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;
end;

/// <summary>Erste Typdeklaration AName (Klasse, Record, object) unterhalb von ASection, nil ohne.</summary>
function FindStructDecl(ASection: TSyntaxNode; const AName: string): TSyntaxNode;
var
  Found: TSyntaxNode;
begin
  Found := nil;
  if ASection <> nil then
    ASection.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := Found = nil;
        if Result and (ANode.Kind = TSyntaxKind.TypeDecl) and SameText(ANode.Name, AName) and
          (TypeOfDecl(ANode) <> nil) and (TypeOfDecl(ANode).Kind in [TSyntaxKind.ClassType,
          TSyntaxKind.RecordType, TSyntaxKind.ObjectType]) then
          Found := ANode;
      end);
  Result := Found;
end;

/// <summary>Letzter Teil eines Namens mit Punkten: "TAussen.TInnen" ergibt "TInnen".</summary>
function LastPart(const AName: string): string;
begin
  Result := Copy(AName, LastDelimiter('.', AName) + 1, MaxInt);
end;

type
  /// <summary>Symbole des implementation-Teils, die Routinen aus dem interface-Teil nicht verwenden dürfen
  /// (E2506, E2441): Typen, Aufzählungswerte, Konstanten, Variablen und Routinen, die dort und nicht im
  /// interface-Teil deklariert sind.</summary>
  TImplementationSymbols = class
  private
    FContext: TRuleContext;
    FInterface: TSyntaxNode;
    FImplementation: TSyntaxNode;
    FLocal: TArray<string>;
    FAncestry: TAncestry;
    function VisibleMembers(ADecl: TSyntaxNode; out ANames: TArray<string>): Boolean;
  public
    constructor Create(const AContext: TRuleContext);
    destructor Destroy; override;
    /// <summary>Rümpfe auf oberster Ebene des implementation-Teils; leer ohne Symbole des Teils.</summary>
    function Routines: TArray<TSyntaxNode>;
    /// <summary>Klasse, Record oder object aus dem interface-Teil, zu dem der Rumpf ARoutine gehört; nil ohne.</summary>
    function OwnerType(ARoutine: TSyntaxNode): TSyntaxNode;
    /// <summary>Erste Verwendung je Symbol des implementation-Teils im Rumpf ARoutine (ohne eigenen Kopf, with
    /// und Typparameter). ADecl ist der Typ der Methode oder nil; leer, wenn dessen Mitglieder samt Vorfahren
    /// nicht sicher bekannt sind.</summary>
    function UsesIn(ARoutine, ADecl: TSyntaxNode): TArray<TSyntaxNode>;
    property InterfacePart: TSyntaxNode read FInterface;
  end;

constructor TImplementationSymbols.Create(const AContext: TRuleContext);
var
  Known: TArray<string>;
  Name: string;
begin
  inherited Create;
  FContext := AContext;
  FInterface := AContext.Tree.Root.FindChild(TSyntaxKind.InterfaceSection);
  FImplementation := AContext.Tree.Root.FindChild(TSyntaxKind.ImplementationSection);
  FLocal := nil;
  if (FInterface = nil) or (FImplementation = nil) then
    Exit;
  Known := SectionNames(FInterface);
  for Name in SectionNames(FImplementation) do
    if not MatchText(Name, Known) then
      FLocal := FLocal + [Name];
end;

destructor TImplementationSymbols.Destroy;
begin
  FAncestry.Free;
  inherited;
end;

function TImplementationSymbols.Routines: TArray<TSyntaxNode>;
var
  Index: Integer;
begin
  Result := nil;
  if FLocal = nil then
    Exit;
  for Index := 0 to FImplementation.ChildCount - 1 do
    if (FImplementation[Index].Kind = TSyntaxKind.RoutineDecl) and
      (FImplementation[Index].FindChild(TSyntaxKind.RoutineHeader) <> nil) then
      Result := Result + [FImplementation[Index]];
end;

function TImplementationSymbols.OwnerType(ARoutine: TSyntaxNode): TSyntaxNode;
begin
  if Pos('.', ARoutine.Name) = 0 then
    Exit(nil);
  Result := FindStructDecl(FInterface, LastPart(Copy(ARoutine.Name, 1, LastDelimiter('.', ARoutine.Name) - 1)));
end;

function TImplementationSymbols.VisibleMembers(ADecl: TSyntaxNode; out ANames: TArray<string>): Boolean;
var
  Outer: TSyntaxNode;
  Location: TSymbolLocation;
  Chain: TArray<TSymbolLocation>;
  Member: TIndexSymbol;
  Complete, ObjectMissing: Boolean;
  Name: string;
begin
  ANames := nil;
  Outer := ADecl;
  while Outer <> nil do
  begin
    if Outer.Kind = TSyntaxKind.TypeDecl then
      ANames := ANames + NamesBelow(Outer);
    Outer := Outer.Parent;
  end;
  if TypeOfDecl(ADecl).Kind <> TSyntaxKind.ClassType then
    Exit(True);
  Result := False;
  if FAncestry = nil then
    FAncestry := TAncestry.Create(FContext.Index, TRuleDerived.UnitIndex(TRuleDerived.Open(FContext), FContext));
  Chain := FAncestry.Ancestors(ADecl.Name, Complete, ObjectMissing);
  if not Complete then
    Exit;
  for Location in Chain do
    for Member in FAncestry.Members(Location) do
      ANames := ANames + [Member.Name];
  for Name in ObjectMemberNames do
    ANames := ANames + [Name];
  Result := True;
end;

function TImplementationSymbols.UsesIn(ARoutine, ADecl: TSyntaxNode): TArray<TSyntaxNode>;
var
  Known, Used: TArray<string>;
  Header: TSyntaxNode;
  Candidates: TList<TSyntaxNode>;
  Candidate: TSyntaxNode;
begin
  Result := nil;
  Known := nil;
  if (FLocal = nil) or ((ADecl <> nil) and not VisibleMembers(ADecl, Known)) then
    Exit;
  Known := Known + NamesBelow(ARoutine);
  Header := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  Candidates := TList<TSyntaxNode>.Create;
  try
    ARoutine.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := not (ANode.Kind in [TSyntaxKind.WithStatement, TSyntaxKind.GenericParams]) and (ANode <> Header);
        if Result and (ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.TypeReference]) and
          (Pos('.', ANode.Name) = 0) then
          Candidates.Add(ANode);
      end);
    Used := nil;
    for Candidate in Candidates do
      if MatchText(Candidate.Name, FLocal) and not MatchText(Candidate.Name, Known) and
        not MatchText(Candidate.Name, Used) then
      begin
        Used := Used + [Candidate.Name];
        Result := Result + [Candidate];
      end;
  finally
    Candidates.Free;
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
      Result := TokenRange(Tokens[At])
    else
      Result := TTextRange.Create(Node.StartPos, Node.StartPos);
  end;

  function HeaderNameRange(AHeader: TSyntaxNode): TTextRange;
  var
    At: Integer;
  begin
    At := NameToken(Tokens, AHeader);
    if At >= 0 then
      Result := TokenRange(Tokens[At])
    else
      Result := NodeRange(AHeader);
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
                Report(Constraint.Range, 'class und record lassen sich nicht zusammen fordern (wie E2507).')
              else if ClassTypes > 0 then
                Report(Constraint.Range,
                  'class lässt sich nicht zusammen mit einer Klasse als Einschränkung fordern (wie E2552).');
              HasClass := True;
            end;
          TConstraintKind.RecordKeyword:
            begin
              if HasClass then
                Report(Constraint.Range, 'class und record lassen sich nicht zusammen fordern (wie E2507).')
              else if ClassTypes > 0 then
                Report(Constraint.Range,
                  'record lässt sich nicht zusammen mit einer Klasse als Einschränkung fordern (wie E2552).')
              else if HasConstructor then
                Report(Constraint.Range, 'record widerspricht der Einschränkung constructor (wie E2516).');
              HasRecord := True;
            end;
          TConstraintKind.ConstructorKeyword:
            begin
              if HasRecord then
                Report(Constraint.Range, 'constructor widerspricht der Einschränkung record (wie E2516).');
              HasConstructor := True;
            end;
          TConstraintKind.ClassType:
            begin
              if ClassTypes > 0 then
                Report(Constraint.Range, Format('Nur eine Klasse ist als Einschränkung erlaubt; %s ist die zweite ' +
                  '(wie E2553).', [Constraint.Text]))
              else if HasClass or HasRecord then
                Report(Constraint.Range, Format('Die Klasse %s lässt sich nicht zusammen mit class bzw. record ' +
                  'fordern (wie E2552).', [Constraint.Text]));
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
    if (Params = nil) or (TypeNode = nil) then
      Exit;
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
            Exit(False);
          if ANode.Kind = TSyntaxKind.GenericParams then
            Shadowing.Add(ANode);
        end);
      for Inner in Shadowing do
        for Child := 0 to Inner.ChildCount - 1 do
          if (Inner[Child].Kind = TSyntaxKind.Identifier) and MatchText(Inner[Child].Name, Names) then
            Report(NodeRange(Inner[Child]), Format('Der Typparameter %s verdeckt den gleichnamigen Typparameter ' +
              'von %s (wie H2509).', [Inner[Child].Name, ADecl.Name]));
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
      Exit;
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
      Exit;
    // Rumpf einer Routine aus dem interface-Teil: dort schon gemeldet.
    Declared := False;
    if (Holder.Parent.Kind = TSyntaxKind.ImplementationSection) and (InterfacePart <> nil) then
      for Child := 0 to InterfacePart.ChildCount - 1 do
      begin
        Other := InterfacePart[Child];
        if (Other.Kind = TSyntaxKind.RoutineDecl) and SameText(Other.Name, AHeader.Name) and
          (Other.FindChild(TSyntaxKind.RoutineHeader) <> nil) and
          (Other.FindChild(TSyntaxKind.RoutineHeader).FindChild(TSyntaxKind.GenericParams) <> nil) then
          Declared := True;
      end;
    if not Declared then
      Report(TTextRange.Create(HeaderNameRange(AHeader).StartPos, Own.EndPos), 'Globale Routinen dürfen keine ' +
        'Typparameter haben; als class-Methode eines Records deklarieren (wie E2530).');
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
        Exit('');
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
        Exit;
      TypeNode := TypeOfDecl(Decl);
      for Child := 0 to TypeNode.ChildCount - 1 do
        if (TypeNode[Child].Kind = TSyntaxKind.RoutineHeader) and SameText(TypeNode[Child].Name, AMethod) then
          AHeads := AHeads + [TypeNode[Child]];
      if (TypeNode.Kind <> TSyntaxKind.ClassType) or (TypeNode.ChildCount = 0) or
        (TypeNode[0].Kind <> TSyntaxKind.TypeReference) then
        Exit(True);
      Current := BareTypeName(TypeNode[0].Name);
      if SameText(Current, 'TObject') then
        Exit(True);
      if Types.DeclaredKind(Current) = TSyntaxKind.InterfaceType then
        Exit(True);
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
      Exit;
    Target := AAccess[0];
    TypeName := '';
    if (Target.Kind = TSyntaxKind.Identifier) and SameText(Target.Name, AAccess.Name) then
      TypeName := EnclosingClass(AAccess, True)
    else if (Target.Kind = TSyntaxKind.MemberAccess) and SameText(Target.Name, AAccess.Name) and
      (Target.ChildCount = 1) and (Target[0].Kind = TSyntaxKind.Identifier) then
    begin
      if SameText(Target[0].Name, 'Self') then
        TypeName := EnclosingClass(AAccess, False)
      else if (EnclosingClass(AAccess, True) <> '') or (Pos('.', Target[0].Name) = 0) then
        if Types.DeclaredKind(Target[0].Name) in [TSyntaxKind.ClassType, TSyntaxKind.RecordType] then
          TypeName := Target[0].Name;
    end;
    if (TypeName = '') or not MethodHeads(TypeName, AAccess.Name, Heads) or (Heads = nil) then
      Exit;
    Count := AAccess[1].ChildCount;
    Fits := False;
    Variants := '';
    for Head in Heads do
    begin
      if Head.FindChild(TSyntaxKind.GenericParams) = nil then
        Exit;
      if Length(TypeParamNames(Head.FindChild(TSyntaxKind.GenericParams))) = Count then
        Fits := True;
      if Variants <> '' then
        Variants := Variants + ', ';
      Variants := Variants + Head.Name + '<' + string.Join(', ',
        TypeParamNames(Head.FindChild(TSyntaxKind.GenericParams))) + '>';
    end;
    if not Fits then
      Report(NodeRange(AAccess), Format('%s hat keine Variante mit %d Typparametern; deklariert: %s (wie E2551).',
        [AAccess.Name, Count, Variants]));
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
          Continue;
        Generic := OwnGenericParams(Tokens, Routine.FindChild(TSyntaxKind.RoutineHeader)) <> nil;
        Outer := Decl;
        while Outer <> nil do
        begin
          if (Outer.Kind = TSyntaxKind.TypeDecl) and (Outer.FindChild(TSyntaxKind.GenericParams) <> nil) then
            Generic := True;
          Outer := Outer.Parent;
        end;
        if not Generic then
          Continue;
        for Use in Symbols.UsesIn(Routine, Decl) do
          Report(NodeRange(Use), Format('%s gehört zu einem generischen Typ bzw. ist generisch, steht im ' +
            'interface-Teil und darf %s aus dem implementation-Teil nicht verwenden (wie E2506).',
            [Routine.Name, Use.Name]));
      end;
    finally
      Symbols.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or (Pos('<', AContext.Text) = 0) then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Root := AContext.Tree.Root;
  Types := TFileTypes.Collect(Root);
  InterfacePart := Root.FindChild(TSyntaxKind.InterfaceSection);
  Nodes := TList<TSyntaxNode>.Create;
  try
    Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        // Methodenzuordnungen (function IFoo<T>.Bar = Baz;) deklarieren nichts Generisches (#1325).
        Result := not ((ANode.Kind = TSyntaxKind.RoutineHeader) and ANode.IsMethodResolution);
        if Result and (ANode.Kind in [TSyntaxKind.GenericParams, TSyntaxKind.TypeDecl, TSyntaxKind.ClassOfType,
          TSyntaxKind.Attribute, TSyntaxKind.RoutineHeader, TSyntaxKind.MemberAccess]) then
          Nodes.Add(ANode);
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
            Report(NodeRange(Node[0]), 'class of ist für parametrisierte Typen nicht erlaubt (wie E2548).');
        TSyntaxKind.Attribute:
          if (Node.ChildCount > 0) and ((Node[0].FindChild(TSyntaxKind.GenericArgs) <> nil) or
            ((Node[0].Kind = TSyntaxKind.Call) and (Node[0].ChildCount > 0) and
            (Node[0][0].FindChild(TSyntaxKind.GenericArgs) <> nil))) then
            Report(NodeRange(Node), 'Parametrisierte Typen können nicht als Attribut stehen (wie E2565).');
        TSyntaxKind.RoutineHeader:
          CheckHeader(Node);
        TSyntaxKind.MemberAccess:
          CheckCall(Node);
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
    end;
    CheckLocalSymbols;
  finally
    Nodes.Free;
  end;
end;

{ TTypeRestrictionViolatedRule }

const
  // Direktiven, die Records und Record-Helfer nicht kennen (E2379, E2463, E2598, E2475).
  RecordForbiddenDirectives: array[0..6] of string = ('virtual', 'dynamic', 'override', 'abstract', 'reintroduce',
    'message', 'final');
  // Davon die, die eine Methode virtuell machen (E2379, E2598).
  RecordVirtualDirectives: array[0..1] of string = ('virtual', 'dynamic');
  // Direktiven, die ein Klassenkonstruktor nicht tragen darf (E2534).
  ClassConstructorDirectives: array[0..2] of string = ('virtual', 'dynamic', 'message');
  // Elterntypen eines Typverweises, die eine Deklaration mit diesem Typ sind (E2527).
  DeclarationParents = [TSyntaxKind.Field, TSyntaxKind.VarDecl, TSyntaxKind.Parameter, TSyntaxKind.RoutineHeader,
    TSyntaxKind.PropertyDecl, TSyntaxKind.ConstDecl, TSyntaxKind.InlineVar, TSyntaxKind.ArrayType,
    TSyntaxKind.PointerType];

/// <summary>Steht vor ANode das Wort class (class var, class property)?</summary>
function PrecededByClass(const ATokens: TArray<TPascalToken>; ANode: TSyntaxNode): Boolean;
var
  Index: Integer;
begin
  Index := TRoutineBody.PreviousToken(ATokens, TRoutineBody.TokenAt(ATokens, ANode.StartOffset));
  Result := (Index >= 0) and (Index < Length(ATokens)) and SameText(ATokens[Index].Text, 'class');
end;

/// <summary>Gibt es zwischen AFrom und ATo (Offsets) auf oberster Klammerebene das Token AText?</summary>
function HasTopLevelToken(const ATokens: TArray<TPascalToken>; AFrom, ATo: Integer; const AText: string): Boolean;
var
  Index, Depth: Integer;
begin
  Result := False;
  Depth := 0;
  Index := TRoutineBody.TokenAt(ATokens, AFrom);
  while (Index >= 0) and (Index < Length(ATokens)) and (ATokens[Index].Offset < ATo) do
  begin
    if ATokens[Index].IsSymbol('(') or ATokens[Index].IsSymbol('[') then
      Inc(Depth)
    else if ATokens[Index].IsSymbol(')') or ATokens[Index].IsSymbol(']') then
      Dec(Depth)
    else if (Depth = 0) and not (ATokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) and
      SameText(ATokens[Index].Text, AText) then
      Exit(True);
    Inc(Index);
  end;
end;

/// <summary>Edit, das die Direktive ADirective samt Semikolon und dem Abstand davor entfernt.</summary>
function DirectiveRemoval(const ATokens: TArray<TPascalToken>; ADirective: TSyntaxNode; out AEdit: TRuleEdit):
  Boolean;
var
  Index, Before, After: Integer;
begin
  Result := False;
  Index := TRoutineBody.TokenAt(ATokens, ADirective.StartOffset);
  Before := TRoutineBody.PreviousToken(ATokens, Index);
  if (Index < 0) or (Index >= Length(ATokens)) or (Before < 0) then
    Exit;
  After := Index;
  while (After >= 0) and (After < Length(ATokens)) and not ATokens[After].IsSymbol(';') do
    After := TRoutineBody.NextToken(ATokens, After);
  if (After < 0) or (After >= Length(ATokens)) then
    Exit;
  AEdit := TRuleEdit.Create(TTextRange.Create(ATokens[Before].EndPos, ATokens[After].EndPos), '');
  Result := True;
end;

/// <summary>Zielt der Helfer AHelper (HelperType) auf diesen Typverweis; bei class helper (TBasis) for T ist es
/// der zweite.</summary>
function HelperTarget(AHelper: TSyntaxNode; out AAncestor: TSyntaxNode): TSyntaxNode;
var
  Count: Integer;
begin
  Count := 0;
  while (Count < AHelper.ChildCount) and (AHelper[Count].Kind = TSyntaxKind.TypeReference) do
    Inc(Count);
  AAncestor := nil;
  Result := nil;
  if Count >= 2 then
  begin
    AAncestor := AHelper[0];
    Result := AHelper[1];
  end
  else if Count = 1 then
    Result := AHelper[0];
end;

/// <summary>Hat jeder Parameter des Kopfs einen Vorgabewert (und gibt es mindestens einen)?</summary>
function AllParametersDefaulted(const ATokens: TArray<TPascalToken>; const AHead: TRoutineHead): Boolean;
var
  Parameter: TSyntaxNode;
begin
  Result := AHead.Parameters <> nil;
  for Parameter in AHead.Parameters do
    if not HasTopLevelToken(ATokens, Parameter.StartOffset, Parameter.EndOffset, '=') then
      Exit(False);
end;

/// <summary>Hat der Kopf einen offenen Array-Parameter (array of T, array of const)?</summary>
function HasOpenArrayParameter(const AHead: TRoutineHead): Boolean;
var
  Parameter: TSyntaxNode;
begin
  for Parameter in AHead.Parameters do
    if Parameter.FindChild(TSyntaxKind.ArrayType) <> nil then
      Exit(True);
  Result := False;
end;

/// <summary>Ist der Record ARecord lokal (in einer Routine) oder anonym (ohne eigene Typdeklaration)?</summary>
function IsLocalOrAnonymousRecord(ARecord: TSyntaxNode): Boolean;
var
  Node: TSyntaxNode;
begin
  if (ARecord.Parent = nil) or (ARecord.Parent.Kind <> TSyntaxKind.TypeDecl) then
    Exit(True);
  Node := ARecord.Parent.Parent;
  while Node <> nil do
  begin
    if Node.Kind = TSyntaxKind.RoutineDecl then
      Exit(True);
    Node := Node.Parent;
  end;
  Result := False;
end;

function TTypeRestrictionViolatedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(TypeRestrictionViolatedRuleId, TRuleSeverity.Error,
    'Sprachregel für Records, inline und Helfer verletzt');
end;

procedure TTypeRestrictionViolatedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Types: TFileTypes;
  Root: TSyntaxNode;
  Disabled, Paths: TArray<string>;
  Nodes: TList<TSyntaxNode>;
  Node: TSyntaxNode;
  Index: Integer;
  Ancestry: TAncestry;

  procedure Report(const ACode: string; const ARange: TTextRange; const AMessage: string;
    const AFixes: TArray<TRuleFix>);
  begin
    if not MatchText(ACode, Disabled) then
      AReport.Add(ARange, AMessage, TRuleConfidence.High, AFixes);
  end;

  function NameRange(AHeader: TSyntaxNode): TTextRange;
  var
    At: Integer;
  begin
    At := NameToken(Tokens, AHeader);
    if At >= 0 then
      Result := TokenRange(Tokens[At])
    else
      Result := NodeRange(AHeader);
  end;

  function KeywordRange(ANode: TSyntaxNode): TTextRange;
  var
    At: Integer;
  begin
    At := TRoutineBody.TokenAt(Tokens, ANode.StartOffset);
    if (At >= 0) and (At < Length(Tokens)) then
      Result := TokenRange(Tokens[At])
    else
      Result := NodeRange(ANode);
  end;

  /// <summary>Korrektur, die alle Direktiven aus ANames am Kopf entfernt.</summary>
  function RemoveFix(const AHead: TRoutineHead; const ANames: array of string; const ATitle: string):
    TArray<TRuleFix>;
  var
    Edits: TArray<TRuleEdit>;
    Edit: TRuleEdit;
    Child: Integer;
  begin
    Edits := nil;
    for Child := 0 to AHead.Header.ChildCount - 1 do
      if (AHead.Header[Child].Kind = TSyntaxKind.Directive) and MatchText(AHead.Header[Child].Name, ANames) and
        DirectiveRemoval(Tokens, AHead.Header[Child], Edit) then
        Edits := Edits + [Edit];
    Result := nil;
    if Edits <> nil then
      Result := [TRuleFix.Create(ATitle, Edits)];
  end;

  /// <summary>Erste Direktive des Kopfs aus ANames oder nil.</summary>
  function FirstDirective(const AHead: TRoutineHead; const ANames: array of string): TSyntaxNode;
  var
    Child: Integer;
  begin
    for Child := 0 to AHead.Header.ChildCount - 1 do
      if (AHead.Header[Child].Kind = TSyntaxKind.Directive) and MatchText(AHead.Header[Child].Name, ANames) then
        Exit(AHead.Header[Child]);
    Result := nil;
  end;

  /// <summary>Deklaration (Kopf in Typ bzw. interface-Teil) zum Rumpf ARoutine, nil ohne.</summary>
  function DeclarationOf(ARoutine: TSyntaxNode): TSyntaxNode;
  var
    Header, Decl, Holder, Candidate: TSyntaxNode;
    Params: string;
    Child, Found: Integer;
  begin
    Result := nil;
    Header := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
    if Header = nil then
      Exit;
    Params := Squeezed(AContext.Text, Header.FindChild(TSyntaxKind.Parameters));
    if Pos('.', ARoutine.Name) > 0 then
    begin
      Decl := FindStructDecl(Root, LastPart(Copy(ARoutine.Name, 1, LastDelimiter('.', ARoutine.Name) - 1)));
      if Decl = nil then
        Exit;
      Holder := TypeOfDecl(Decl);
    end
    else if (ARoutine.Parent <> nil) and (ARoutine.Parent.Kind = TSyntaxKind.ImplementationSection) then
      Holder := Root.FindChild(TSyntaxKind.InterfaceSection)
    else
      Exit;
    if Holder = nil then
      Exit;
    Found := 0;
    for Child := 0 to Holder.ChildCount - 1 do
    begin
      Candidate := Holder[Child];
      if Candidate.Kind = TSyntaxKind.RoutineDecl then
        Candidate := Candidate.FindChild(TSyntaxKind.RoutineHeader);
      if (Candidate = nil) or (Candidate.Kind <> TSyntaxKind.RoutineHeader) or
        not SameText(Candidate.Name, LastPart(ARoutine.Name)) then
        Continue;
      Inc(Found);
      if Squeezed(AContext.Text, Candidate.FindChild(TSyntaxKind.Parameters)) = Params then
        Exit(Candidate);
      if (Params = '') and (Found = 1) then
        Result := Candidate;
    end;
    if Found > 1 then
      Result := nil;
  end;

  // Records: E2379, E2463, E2394, E2471, E2465, E2398; lokale und anonyme Records: E2433–E2437.
  procedure CheckRecord(ARecord: TSyntaxNode);
  var
    Child: Integer;
    Member, Directive: TSyntaxNode;
    Head: TRoutineHead;
  begin
    if IsLocalOrAnonymousRecord(ARecord) then
    begin
      for Child := 0 to ARecord.ChildCount - 1 do
      begin
        Member := ARecord[Child];
        case Member.Kind of
          TSyntaxKind.RoutineHeader:
            Report('E2433', NameRange(Member), 'Lokale und anonyme Records dürfen keine Methoden deklarieren ' +
              '(wie E2433).', nil);
          TSyntaxKind.PropertyDecl:
            Report('E2434', KeywordRange(Member), 'Lokale und anonyme Records dürfen keine Properties ' +
              'deklarieren (wie E2434).', nil);
          TSyntaxKind.VarSection:
            if PrecededByClass(Tokens, Member) then
              Report('E2435', KeywordRange(Member), 'Lokale und anonyme Records dürfen keine Klassenmitglieder ' +
                'deklarieren (wie E2435).', nil);
          TSyntaxKind.TypeSection:
            Report('E2436', KeywordRange(Member), 'Lokale und anonyme Records dürfen keine Typen deklarieren ' +
              '(wie E2436).', nil);
          TSyntaxKind.ConstSection:
            Report('E2437', KeywordRange(Member), 'Lokale und anonyme Records dürfen keine Konstanten ' +
              'deklarieren (wie E2437).', nil);
        else
          // Übrige Werte bewusst ohne Wirkung.
        end;
      end;
      Exit;
    end;
    for Child := 0 to ARecord.ChildCount - 1 do
    begin
      Member := ARecord[Child];
      if Member.Kind <> TSyntaxKind.RoutineHeader then
        Continue;
      Head := TRoutineHead.Read(Tokens, Member);
      if (Head.Keyword = 'operator') or (Head.IsClass and MatchText(Head.Keyword, ['constructor', 'destructor'])) then
        Continue;
      Directive := FirstDirective(Head, RecordVirtualDirectives);
      if Directive <> nil then
        Report('E2379', NodeRange(Directive), 'Records erlauben keine virtuellen Methoden (wie E2379).',
          RemoveFix(Head, RecordForbiddenDirectives, Directive.Name + ' entfernen'))
      else
      begin
        Directive := FirstDirective(Head, RecordForbiddenDirectives);
        if Directive <> nil then
          Report('E2463', NodeRange(Directive), Format('Die Direktive %s ist in Records nicht erlaubt (wie E2463).',
            [Directive.Name]), RemoveFix(Head, RecordForbiddenDirectives, Directive.Name + ' entfernen'));
      end;
      if Head.Keyword = 'constructor' then
      begin
        if Head.ParameterCount = 0 then
          Report('E2394', NameRange(Member), 'Records erlauben keine parameterlosen Konstruktoren (wie E2394).', nil)
        else if AllParametersDefaulted(Tokens, Head) then
          Report('E2471', NameRange(Member), 'Records erlauben keine Konstruktoren, die ohne Argumente aufrufbar ' +
            'sind; alle Parameter haben Vorgabewerte (wie E2471).', nil);
      end
      else if Head.Keyword = 'destructor' then
        Report('E2465', NameRange(Member), 'Records dürfen keinen Destruktor einführen (wie E2465).', nil)
      else if Head.IsClass and MatchText(Head.Keyword, ['procedure', 'function']) and
        not Head.HasDirective('static') then
        Report('E2398', NameRange(Member), 'Klassenmethoden in Records müssen static sein (wie E2398).',
          [TRuleFix.Create('static ergänzen', [TRuleEdit.Create(TTextRange.Create(Member.EndPos, Member.EndPos),
          ' static;')])]);
    end;
  end;

  /// <summary>Stammt der Typ AName sicher nicht von AAncestor ab? False, wenn die Kette nicht bekannt ist.</summary>
  function CertainlyNotDescendant(const AName, AAncestor: string): Boolean;
  var
    Chain: TArray<TSymbolLocation>;
    Location: TSymbolLocation;
    Complete, ObjectMissing: Boolean;
  begin
    Result := False;
    if SameText(AName, AAncestor) then
      Exit;
    if SameText(AName, 'TObject') then
      Exit(True);
    if Ancestry = nil then
      Ancestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(TRuleDerived.Open(AContext), AContext));
    Chain := Ancestry.Ancestors(AName, Complete, ObjectMissing);
    if not Complete then
      Exit;
    for Location in Chain do
      if SameText(Location.Symbol.Name, AAncestor) then
        Exit;
    if ObjectMissing and SameText(AAncestor, 'TObject') then
      Exit;
    Result := True;
  end;

  // Helfer: E2599, E2598, E2475, E2295, E2294, E2589. Klassenkonstruktoren im Class-Helfer (E2358) und
  // Helfer-Konstruktoren ohne Konstruktoraufruf zuerst (E2296) übersetzt dcc (Skia4Delphi MobileBars,
  // TSkPixmapHelper.Create, FMX.Skia TSkBitmapHelper; TR6, TR7, #1328); die Prüfungen sind entfallen.
  procedure CheckHelper(AHelper: TSyntaxNode);
  var
    Child, Inner: Integer;
    Member, Directive, Target, AncestorRef, AncestorDecl, AncestorTarget, Dummy, Outer: TSyntaxNode;
    Head: TRoutineHead;
    IsRecordHelper: Boolean;
    Helped, Wanted: string;
    TypeIndex: Integer;
  begin
    IsRecordHelper := SameText(AHelper.Name, 'record');
    Target := HelperTarget(AHelper, AncestorRef);
    Helped := '';
    if Target <> nil then
      Helped := BareTypeName(Target.Name);
    for Child := 0 to AHelper.ChildCount - 1 do
    begin
      Member := AHelper[Child];
      case Member.Kind of
        TSyntaxKind.Field:
          Report('E2599', KeywordRange(Member), 'Helfer dürfen keine Felder deklarieren (wie E2599).', nil);
        TSyntaxKind.VarSection:
          if not PrecededByClass(Tokens, Member) then
            for Inner := 0 to Member.ChildCount - 1 do
              Report('E2599', KeywordRange(Member[Inner]), 'Helfer dürfen keine Felder deklarieren (wie E2599).',
                nil);
        TSyntaxKind.RoutineHeader:
          begin
            Head := TRoutineHead.Read(Tokens, Member);
            if IsRecordHelper then
            begin
              Directive := FirstDirective(Head, RecordVirtualDirectives);
              if Directive <> nil then
                Report('E2598', NodeRange(Directive), 'Record-Helfer erlauben keine virtuellen Methoden ' +
                  '(wie E2598).', RemoveFix(Head, RecordForbiddenDirectives, Directive.Name + ' entfernen'))
              else
              begin
                Directive := FirstDirective(Head, RecordForbiddenDirectives);
                if Directive <> nil then
                  Report('E2475', NodeRange(Directive), Format('Die Direktive %s ist in Record-Helfern nicht ' +
                    'erlaubt (wie E2475).', [Directive.Name]), RemoveFix(Head, RecordForbiddenDirectives,
                    Directive.Name + ' entfernen'));
              end;
            end
            else if (Head.Keyword = 'destructor') and not Head.IsClass then
              Report('E2295', NameRange(Member), 'Class-Helfer dürfen keinen Destruktor einführen (wie E2295).', nil);
          end;
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
    end;
    // Vorfahr-Helfer: nur Nachfahren seines Typs (E2294).
    if not IsRecordHelper and (AncestorRef <> nil) and (Helped <> '') then
    begin
      TypeIndex := Types.IndexOf(BareTypeName(AncestorRef.Name));
      if (TypeIndex >= 0) and (Types.DeclaredKind(BareTypeName(AncestorRef.Name)) = TSyntaxKind.HelperType) then
      begin
        AncestorDecl := Types.Types[TypeIndex];
        AncestorTarget := HelperTarget(AncestorDecl, Dummy);
        if AncestorTarget <> nil then
        begin
          Wanted := BareTypeName(AncestorTarget.Name);
          if CertainlyNotDescendant(Helped, Wanted) then
            Report('E2294', NodeRange(Target), Format('Ein Class-Helfer, der von %s abstammt, kann nur Nachfahren ' +
              'von %s helfen (wie E2294).', [BareTypeName(AncestorRef.Name), Wanted]), nil);
        end;
      end;
    end;
    // Helfer im Kontext eines parametrisierten Typs (E2589).
    Outer := AHelper.Parent;
    if Outer <> nil then
      Outer := Outer.Parent;
    while Outer <> nil do
    begin
      if (Outer.Kind = TSyntaxKind.TypeDecl) and (Outer.FindChild(TSyntaxKind.GenericParams) <> nil) then
      begin
        Report('E2589', KeywordRange(AHelper.Parent), 'Helfer dürfen nicht im Kontext eines parametrisierten Typs ' +
          'deklariert werden (wie E2589).', nil);
        Break;
      end;
      Outer := Outer.Parent;
    end;
  end;

  // Klassenkonstruktoren: E2360, E2534, E2359.
  procedure CheckClassConstructors(AType: TSyntaxNode);
  var
    Child: Integer;
    Head: TRoutineHead;
    Directive, First: TSyntaxNode;
  begin
    First := nil;
    for Child := 0 to AType.ChildCount - 1 do
    begin
      if AType[Child].Kind <> TSyntaxKind.RoutineHeader then
        Continue;
      Head := TRoutineHead.Read(Tokens, AType[Child]);
      if not Head.IsClass or (Head.Keyword <> 'constructor') then
        Continue;
      if Head.ParameterCount > 0 then
        Report('E2360', NameRange(Head.Header), 'Klassenkonstruktoren dürfen keine Parameter haben (wie E2360).', nil);
      Directive := FirstDirective(Head, ClassConstructorDirectives);
      if Directive <> nil then
        Report('E2534', NodeRange(Directive), 'Klassenkonstruktoren dürfen nicht virtual, dynamic oder message sein ' +
          '(wie E2534).', RemoveFix(Head, ClassConstructorDirectives, Directive.Name + ' entfernen'));
      if First = nil then
        First := Head.Header
      else if not TConditionalBranches.Exclusive(
        TConditionalBranches.PathAt(Paths, TRoutineBody.TokenAt(Tokens, First.StartOffset)),
        TConditionalBranches.PathAt(Paths, TRoutineBody.TokenAt(Tokens, Head.Header.StartOffset))) then
        Report('E2359', NameRange(Head.Header), Format('Mehrere Klassenkonstruktoren in %s: %s und %s (wie E2359).',
          [AType.Parent.Name, First.Name, Head.Header.Name]), nil);
    end;
  end;

  // inline an Köpfen: E2425, E2442, E2439.
  procedure CheckInlineHeader(AHeader: TSyntaxNode);
  var
    Head: TRoutineHead;
    InlineHead, Decl: TSyntaxNode;
  begin
    Head := TRoutineHead.Read(Tokens, AHeader);
    InlineHead := Head.Directive('inline');
    if InlineHead = nil then
      Exit;
    if (AHeader.Parent <> nil) and (AHeader.Parent.Kind = TSyntaxKind.RoutineDecl) then
    begin
      Decl := DeclarationOf(AHeader.Parent);
      if (Decl <> nil) and (Decl <> AHeader) and TRoutineHead.Read(Tokens, Decl).HasDirective('inline') then
        Exit;
    end;
    if FirstDirective(Head, RecordVirtualDirectives) <> nil then
      Report('E2425', NodeRange(InlineHead), 'Inline-Methoden dürfen nicht virtual oder dynamic sein (wie E2425).',
        RemoveFix(Head, ['inline'], 'inline entfernen'))
    else if MatchText(Head.Keyword, ['constructor', 'destructor']) then
      Report('E2442', NodeRange(InlineHead), 'inline ist an Konstruktoren und Destruktoren nicht erlaubt (wie E2442).',
        RemoveFix(Head, ['inline'], 'inline entfernen'));
    if HasOpenArrayParameter(Head) then
      Report('E2439', NodeRange(InlineHead), 'Inline-Routinen dürfen keine offenen Array-Parameter haben (wie E2439).',
        RemoveFix(Head, ['inline'], 'inline entfernen'));
  end;

  /// <summary>Kopf mit inline zum Rumpf ARoutine (eigener Kopf oder Deklaration), nil ohne.</summary>
  function InlineHeader(ARoutine: TSyntaxNode): TSyntaxNode;
  var
    Header: TSyntaxNode;
  begin
    Header := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
    if (Header <> nil) and TRoutineHead.Read(Tokens, Header).HasDirective('inline') then
      Exit(Header);
    Result := DeclarationOf(ARoutine);
    if (Result <> nil) and not TRoutineHead.Read(Tokens, Result).HasDirective('inline') then
      Result := nil;
  end;

  /// <summary>Namen, die ARoutine selbst als Parameter und Variablen deklariert (ohne verschachtelte Routinen).</summary>
  function OwnVariables(ARoutine: TSyntaxNode): TArray<string>;
  var
    Child, Inner: Integer;
    Header: TSyntaxNode;
  begin
    Result := nil;
    Header := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
    if (Header <> nil) and (Header.FindChild(TSyntaxKind.Parameters) <> nil) then
      Result := NamesBelow(Header.FindChild(TSyntaxKind.Parameters));
    for Child := 0 to ARoutine.ChildCount - 1 do
      if ARoutine[Child].Kind = TSyntaxKind.VarSection then
        for Inner := 0 to ARoutine[Child].ChildCount - 1 do
          Result := Result + DeclaredNames(ARoutine[Child][Inner]);
  end;

  /// <summary>Bezeichner im Rumpf ABody, die nicht in with stehen.</summary>
  function IdentifiersIn(ABody: TSyntaxNode; ASkipNested: Boolean): TArray<TSyntaxNode>;
  var
    Found: TArray<TSyntaxNode>;
  begin
    Found := nil;
    ABody.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := (ANode.Kind <> TSyntaxKind.WithStatement) and
          not (ASkipNested and (ANode <> ABody) and (ANode.Kind = TSyntaxKind.RoutineDecl));
        if Result and (ANode.Kind = TSyntaxKind.Identifier) then
          Found := Found + [ANode];
      end);
    Result := Found;
  end;

  // Rümpfe von inline-Routinen: E2426, E2501, E2449.
  procedure CheckInlineBody(ARoutine: TSyntaxNode);
  var
    InlineHead, Head, Body, Outer: TSyntaxNode;
    Directive: TSyntaxNode;
    Nested, Outside, Own, Used: TArray<string>;
    Child: Integer;
    Ident: TSyntaxNode;
    Fix: TArray<TRuleFix>;
  begin
    InlineHead := InlineHeader(ARoutine);
    if InlineHead = nil then
      Exit;
    Directive := TRoutineHead.Read(Tokens, InlineHead).Directive('inline');
    Fix := RemoveFix(TRoutineHead.Read(Tokens, InlineHead), ['inline'], 'inline entfernen');
    if ARoutine.FindChild(TSyntaxKind.AsmBlock) <> nil then
      Report('E2426', NodeRange(Directive), 'Inline-Routinen dürfen keinen asm-Block haben (wie E2426).', Fix);
    Body := ARoutine.FindChild(TSyntaxKind.Block);
    if Body = nil then
      Exit;
    // Aufruf eigener lokaler Routinen.
    Nested := nil;
    for Child := 0 to ARoutine.ChildCount - 1 do
      if ARoutine[Child].Kind = TSyntaxKind.RoutineDecl then
        Nested := Nested + [ARoutine[Child].Name];
    Used := nil;
    if Nested <> nil then
      for Ident in IdentifiersIn(Body, True) do
        if MatchText(Ident.Name, Nested) and not MatchText(Ident.Name, Used) then
        begin
          Used := Used + [Ident.Name];
          Report('E2501', NodeRange(Ident), Format('Die Inline-Routine %s darf die lokale Routine %s nicht ' +
            'aufrufen (wie E2501).', [ARoutine.Name, Ident.Name]), Fix);
        end;
    // Lokale inline-Routine mit Zugriff auf Variablen der umgebenden Routine.
    Outer := ARoutine.Parent;
    Head := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
    if (Outer = nil) or (Outer.Kind <> TSyntaxKind.RoutineDecl) or (Head = nil) or
      not TRoutineHead.Read(Tokens, Head).HasDirective('inline') then
      Exit;
    Outside := OwnVariables(Outer);
    Own := NamesBelow(ARoutine);
    Used := nil;
    for Ident in IdentifiersIn(Body, False) do
      if MatchText(Ident.Name, Outside) and not MatchText(Ident.Name, Own) and not MatchText(Ident.Name, Used) then
      begin
        Used := Used + [Ident.Name];
        Report('E2449', NodeRange(Ident), Format('Die eingebettete lokale Routine %s darf nicht auf %s der ' +
          'umgebenden Routine zugreifen (wie E2449).', [ARoutine.Name, Ident.Name]), Fix);
      end;
  end;

  // inline-Routinen aus dem interface-Teil mit Symbolen des implementation-Teils: E2441.
  procedure CheckInlineLocalSymbols;
  var
    Symbols: TImplementationSymbols;
    Routine, Use, mDeclaration: TSyntaxNode;
    mUsable: TArray<string>;
  begin
    Symbols := TImplementationSymbols.Create(AContext);
    try
      mUsable := InlineUsableNames(Root.FindChild(TSyntaxKind.ImplementationSection));
      for Routine in Symbols.Routines do
      begin
        // Nur inline an der Deklaration im interface-Teil zählt: steht es allein am Rumpf, können andere Units
        // die Routine ohnehin nicht einbetten (HtmlViewer, TR5).
        mDeclaration := DeclarationOf(Routine);
        if (mDeclaration = nil) or not TRoutineHead.Read(Tokens, mDeclaration).HasDirective('inline') then
          Continue;
        if Pos('.', Routine.Name) > 0 then
        begin
          if Symbols.OwnerType(Routine) = nil then
            Continue;
        end
        else if (DeclarationOf(Routine) = nil) or (DeclarationOf(Routine).Parent = nil) or
          (DeclarationOf(Routine).Parent.Parent <> Symbols.InterfacePart) then
          Continue;
        for Use in Symbols.UsesIn(Routine, Symbols.OwnerType(Routine)) do
          if not MatchText(Use.Name, mUsable) then
            Report('E2441', NodeRange(Use), Format('Die Inline-Routine %s aus dem interface-Teil darf %s aus dem ' +
              'implementation-Teil nicht verwenden (wie E2441).', [Routine.Name, Use.Name]), nil);
      end;
    finally
      Symbols.Free;
    end;
  end;

  // threadvar: E2189, E2190, E2194.
  procedure CheckThreadVars(ASection: TSyntaxNode);
  var
    Outer: TSyntaxNode;
    Child: Integer;
    Decl: TSyntaxNode;
  begin
    Outer := ASection.Parent;
    while Outer <> nil do
    begin
      if Outer.Kind = TSyntaxKind.RoutineDecl then
      begin
        Report('E2189', KeywordRange(ASection), 'threadvar ist nur auf Unit-Ebene erlaubt, nicht lokal in einer ' +
          'Routine (wie E2189).', nil);
        Break;
      end;
      Outer := Outer.Parent;
    end;
    for Child := 0 to ASection.ChildCount - 1 do
    begin
      Decl := ASection[Child];
      if Decl.Kind <> TSyntaxKind.VarDecl then
        Continue;
      if HasTopLevelToken(Tokens, Decl.StartOffset, Decl.EndOffset, 'absolute') then
        Report('E2190', KeywordRange(Decl), 'threadvar-Variablen dürfen nicht absolute sein (wie E2190).', nil)
      else if HasTopLevelToken(Tokens, Decl.StartOffset, Decl.EndOffset, '=') then
        Report('E2194', KeywordRange(Decl), 'threadvar-Variablen lassen sich nicht initialisieren (wie E2194).', nil);
    end;
  end;

  // Helfer als Typ einer Deklaration: E2527.
  procedure CheckHelperReference(AReference: TSyntaxNode);
  var
    Name: string;
  begin
    if (AReference.Parent = nil) or not (AReference.Parent.Kind in DeclarationParents) or
      (Pos('.', AReference.Name) > 0) or (AReference.FindChild(TSyntaxKind.GenericArgs) <> nil) then
      Exit;
    Name := AReference.Name;
    if Types.DeclaredKind(Name) = TSyntaxKind.HelperType then
      Report('E2527', NodeRange(AReference), Format('Der Helfer %s kann nicht als Typ in Deklarationen stehen ' +
        '(wie E2527).', [Name]), nil);
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Root := AContext.Tree.Root;
  Types := TFileTypes.Collect(Root);
  Disabled := TRuleOptions.Strings(AContext.Options, 'disabledChecks', nil);
  Paths := TConditionalBranches.Paths(Tokens);
  Ancestry := nil;
  Nodes := TList<TSyntaxNode>.Create;
  try
    Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := True;
        if ANode.Kind in [TSyntaxKind.RecordType, TSyntaxKind.ClassType, TSyntaxKind.ObjectType,
          TSyntaxKind.HelperType, TSyntaxKind.RoutineHeader, TSyntaxKind.RoutineDecl, TSyntaxKind.VarSection,
          TSyntaxKind.TypeReference] then
          Nodes.Add(ANode);
      end);
    for Index := 0 to Nodes.Count - 1 do
    begin
      Node := Nodes[Index];
      case Node.Kind of
        TSyntaxKind.RecordType:
          begin
            CheckRecord(Node);
            if not IsLocalOrAnonymousRecord(Node) then
              CheckClassConstructors(Node);
          end;
        TSyntaxKind.ClassType, TSyntaxKind.ObjectType:
          CheckClassConstructors(Node);
        TSyntaxKind.HelperType:
          CheckHelper(Node);
        TSyntaxKind.RoutineHeader:
          CheckInlineHeader(Node);
        TSyntaxKind.RoutineDecl:
          CheckInlineBody(Node);
        TSyntaxKind.VarSection:
          if SameText(Node.Name, 'threadvar') then
            CheckThreadVars(Node);
        TSyntaxKind.TypeReference:
          CheckHelperReference(Node);
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
    end;
    CheckInlineLocalSymbols;
  finally
    Nodes.Free;
    Ancestry.Free;
  end;
end;

{ TAttributeUsageInvalidRule }

const
  // Attribute des Compilers, die er selbst prüft (System.WeakAttribute …).
  CompilerCheckedAttributes: array[0..3] of string = ('Weak', 'Unsafe', 'Volatile', 'Ref');
  // Typarten, die sicher weder Klasse noch Interface sind (E2584). ProcedureType fehlt: reference to ist ein
  // Interface.
  NonReferenceTypeKinds = [TSyntaxKind.RecordType, TSyntaxKind.EnumType, TSyntaxKind.SetType, TSyntaxKind.ArrayType,
    TSyntaxKind.PointerType, TSyntaxKind.FileType, TSyntaxKind.SubrangeType];
  // Ziele, an denen Volatile nicht stehen darf (Compiler Attributes: keine Typen, Routinen, Methoden).
  VolatileForbiddenTargets = [TSyntaxKind.TypeDecl, TSyntaxKind.RoutineDecl, TSyntaxKind.RoutineHeader,
    TSyntaxKind.PropertyDecl];

/// <summary>Knoten des Namens eines Eintrags im Attribut-Knoten ([Name] bzw. [Name(…)]).</summary>
function AttributeNameNode(AItem: TSyntaxNode): TSyntaxNode;
begin
  Result := AItem;
  if (AItem.Kind = TSyntaxKind.Call) and (AItem.ChildCount > 0) then
    Result := AItem[0];
end;

/// <summary>Punktkette eines Bezeichners bzw. MemberAccess; '' bei anderen Ausdrücken. Iterativ (Bericht M1):
/// erst die Kette hinab, dann die Namen von innen nach außen anhängen.</summary>
function DottedNameOf(ANode: TSyntaxNode): string;
var
  Chain: TStack<TSyntaxNode>;
  Node: TSyntaxNode;
begin
  Chain := TStack<TSyntaxNode>.Create;
  try
    Node := ANode;
    while (Node.Kind = TSyntaxKind.MemberAccess) and (Node.ChildCount = 1) do
    begin
      Chain.Push(Node);
      Node := Node[0];
    end;
    Result := '';
    if Node.Kind = TSyntaxKind.Identifier then
      Result := Node.Name;
    while (Chain.Count > 0) and (Result <> '') do
      Result := Result + '.' + Chain.Pop.Name;
  finally
    Chain.Free;
  end;
end;

/// <summary>Name des Compiler-Attributs (Weak, Unsafe, Volatile, Ref) für den Eintrag AItem, '' bei anderen.
/// [WeakAttribute] und [System.Weak] zählen mit; deklariert die Datei einen Typ gleichen Namens, nicht.</summary>
function CompilerAttribute(const ATypes: TFileTypes; AItem: TSyntaxNode): string;
var
  Name, Bare: string;
  Dot: Integer;
begin
  Result := '';
  Name := DottedNameOf(AttributeNameNode(AItem));
  Dot := LastDelimiter('.', Name);
  if (Dot > 0) and not SameText(Copy(Name, 1, Dot - 1), 'System') then
    Exit;
  Bare := Copy(Name, Dot + 1, MaxInt);
  if EndsText('Attribute', Bare) and (Length(Bare) > Length('Attribute')) then
    Bare := Copy(Bare, 1, Length(Bare) - Length('Attribute'));
  if not MatchText(Bare, CompilerCheckedAttributes) then
    Exit;
  if (ATypes.IndexOf(Bare) >= 0) or (ATypes.IndexOf(Bare + 'Attribute') >= 0) then
    Exit;
  Result := CompilerCheckedAttributes[IndexText(Bare, CompilerCheckedAttributes)];
end;

/// <summary>Deklaration, zu der der Attribut-Knoten AAttribute gehört: der nächste Geschwisterknoten, der kein
/// Attribut ist, bzw. der Parameter; nil ohne.</summary>
function AttributeTarget(AAttribute: TSyntaxNode): TSyntaxNode;
var
  Parent: TSyntaxNode;
  Index: Integer;
  Found: Boolean;
begin
  Result := nil;
  Parent := AAttribute.Parent;
  if Parent = nil then
    Exit;
  if Parent.Kind = TSyntaxKind.Parameter then
    Exit(Parent);
  Found := False;
  for Index := 0 to Parent.ChildCount - 1 do
    if Parent[Index] = AAttribute then
      Found := True
    else if Found and (Parent[Index].Kind <> TSyntaxKind.Attribute) then
      Exit(Parent[Index]);
end;

/// <summary>Ist der Typ des Felds bzw. der Variablen (Kind von AType) sicher weder Klasse noch Interface? Eingebaute
/// Werttypen und Records, Aufzählungen, Mengen, Arrays, Zeiger der Datei; Aliase werden verfolgt.</summary>
function CertainlyNoReference(const ATypes: TFileTypes; AType: TSyntaxNode): Boolean;
var
  Name: string;
  Index, Depth: Integer;
begin
  if AType.Kind in NonReferenceTypeKinds then
    Exit(True);
  if (AType.Kind <> TSyntaxKind.TypeReference) or (AType.FindChild(TSyntaxKind.GenericArgs) <> nil) then
    Exit(False);
  Name := AType.Name;
  for Depth := 1 to 16 do
  begin
    if (Name = '') or (Pos('.', Name) > 0) or (Pos('<', Name) > 0) then
      Exit(False);
    if ATypes.DeclaredKind(Name) in NonReferenceTypeKinds then
      Exit(True);
    Index := ATypes.IndexOf(Name);
    if Index < 0 then
      // Pointer bleibt außen vor: die Hilfe nennt nur Klassen und Interfaces, der Fall ist nicht abgeglichen.
      Exit(not SameText(Name, 'Pointer') and (MatchText(Name, BuiltinTypeNames) or
        MatchText(Name, BooleanTypeNames)));
    if ATypes.AliasOf[Index] <> '' then
      Name := ATypes.AliasOf[Index]
    else if ATypes.Types[Index].Kind = TSyntaxKind.TypeReference then
      Name := ATypes.Types[Index].Name
    else
      Exit(False);
  end;
  Result := False;
end;

type
  /// <summary>Deklarationen der Datei je Name (klein geschrieben): Variablen und Routinen, die in einem
  /// Attributargument nie konstant sind, und alle übrigen Arten (Konstanten, Typen, Werte …).</summary>
  TDeclarationNames = class
  private
    FVariables: TObjectDictionary<string, TList<TSyntaxNode>>;
    FOthers: TDictionary<string, Boolean>;
    procedure AddVariable(const AName: string; ANode: TSyntaxNode);
    procedure AddOther(const AName: string);
    procedure AddNames(const ANames: string; ANode: TSyntaxNode; AVariable: Boolean);
  public
    constructor Create(ARoot: TSyntaxNode);
    destructor Destroy; override;
    /// <summary>Variablen- bzw. Routinen-Deklarationen zu AName, die nur so in der Datei stehen; nil sonst.</summary>
    function OnlyVariables(const AName: string): TList<TSyntaxNode>;
    /// <summary>Deklariert die Datei AName in irgendeiner Art?</summary>
    function Declared(const AName: string): Boolean;
  end;

constructor TDeclarationNames.Create(ARoot: TSyntaxNode);
var
  Nodes: TList<TSyntaxNode>;
  Node: TSyntaxNode;
  Name: string;
  Index: Integer;
begin
  inherited Create;
  FVariables := TObjectDictionary<string, TList<TSyntaxNode>>.Create([doOwnsValues]);
  FOthers := TDictionary<string, Boolean>.Create;
  Nodes := TList<TSyntaxNode>.Create;
  try
    ARoot.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := True;
        Nodes.Add(ANode);
      end);
    for Node in Nodes do
      case Node.Kind of
        TSyntaxKind.VarDecl, TSyntaxKind.Field:
          AddNames(Node.Name, Node, True);
        TSyntaxKind.RoutineHeader:
          begin
            Name := Node.Name;
            if LastDelimiter('.', Name) > 0 then
              Name := Copy(Name, LastDelimiter('.', Name) + 1, MaxInt);
            // Nur Routinen der Unit selbst gelten als sicher; Methoden und lokale Routinen zählen als andere Art.
            AddNames(Name, Node, (Pos('.', Node.Name) = 0) and (Node.Parent <> nil) and
              (Node.Parent.Kind = TSyntaxKind.RoutineDecl) and (Node.Parent.Parent <> nil) and
              (Node.Parent.Parent.Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection]));
          end;
        TSyntaxKind.ConstDecl, TSyntaxKind.TypeDecl, TSyntaxKind.Parameter, TSyntaxKind.PropertyDecl,
        TSyntaxKind.InlineVar, TSyntaxKind.InlineConst, TSyntaxKind.UsedUnit, TSyntaxKind.ForStatement,
        TSyntaxKind.ForInStatement:
          AddNames(Node.Name, Node, False);
        TSyntaxKind.EnumType:
          for Index := 0 to Node.ChildCount - 1 do
            AddOther(Node[Index].Name);
        TSyntaxKind.GenericParams:
          for Index := 0 to Node.ChildCount - 1 do
            AddOther(Node[Index].Name);
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
  finally
    Nodes.Free;
  end;
end;

destructor TDeclarationNames.Destroy;
begin
  FVariables.Free;
  FOthers.Free;
  inherited;
end;

procedure TDeclarationNames.AddVariable(const AName: string; ANode: TSyntaxNode);
var
  List: TList<TSyntaxNode>;
begin
  if not FVariables.TryGetValue(LowerCase(AName), List) then
  begin
    List := TList<TSyntaxNode>.Create;
    FVariables.Add(LowerCase(AName), List);
  end;
  List.Add(ANode);
end;

procedure TDeclarationNames.AddOther(const AName: string);
begin
  if Trim(AName) <> '' then
    FOthers.AddOrSetValue(LowerCase(Trim(AName)), True);
end;

procedure TDeclarationNames.AddNames(const ANames: string; ANode: TSyntaxNode; AVariable: Boolean);
var
  Name: string;
begin
  for Name in SplitString(ANames, ',') do
    if Trim(Name) = '' then
      Continue
    else if AVariable then
      AddVariable(Trim(Name), ANode)
    else
      AddOther(Name);
end;

function TDeclarationNames.Declared(const AName: string): Boolean;
begin
  Result := FOthers.ContainsKey(LowerCase(AName)) or FVariables.ContainsKey(LowerCase(AName));
end;

function TDeclarationNames.OnlyVariables(const AName: string): TList<TSyntaxNode>;
begin
  Result := nil;
  if FOthers.ContainsKey(LowerCase(AName)) then
    Exit;
  FVariables.TryGetValue(LowerCase(AName), Result);
end;

function TAttributeUsageInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(AttributeUsageInvalidRuleId, TRuleSeverity.Error, 'Attribut falsch verwendet');
end;

procedure TAttributeUsageInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Types: TFileTypes;
  Paths: TArray<string>;
  Attributes: TList<TSyntaxNode>;
  Names: TDeclarationNames;
  Node: TSyntaxNode;

  function PathOf(ANode: TSyntaxNode): string;
  begin
    Result := TConditionalBranches.PathAt(Paths, TRoutineBody.TokenAt(Tokens, ANode.StartOffset));
  end;

  /// <summary>Liegt ANode in ARoot (ARoot selbst eingeschlossen)?</summary>
  function Inside(ANode, ARoot: TSyntaxNode): Boolean;
  begin
    while ANode <> nil do
    begin
      if ANode = ARoot then
        Exit(True);
      ANode := ANode.Parent;
    end;
    Result := False;
  end;

  /// <summary>Ist die Deklaration ADecl (VarDecl, Field oder RoutineHeader) am Attribut AAttribute sichtbar und
  /// wird mit ihm übersetzt? Unit-Ebene oder umgebende Routine, vor dem Attribut; Felder nicht.</summary>
  function VisibleAt(ADecl, AAttribute: TSyntaxNode): Boolean;
  var
    Holder: TSyntaxNode;
  begin
    Result := False;
    if (ADecl.StartOffset >= AAttribute.StartOffset) or (ADecl.Kind = TSyntaxKind.Field) then
      Exit;
    Holder := ADecl.Parent;
    if ADecl.Kind = TSyntaxKind.VarDecl then
    begin
      if (Holder = nil) or (Holder.Kind <> TSyntaxKind.VarSection) then
        Exit;
      Holder := Holder.Parent;
      if Holder = nil then
        Exit;
      if Holder.Kind = TSyntaxKind.RoutineDecl then
      begin
        if not Inside(AAttribute, Holder) then
          Exit;
      end
      else if not (Holder.Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection]) then
        Exit;
    end;
    Result := TConditionalBranches.Implies(PathOf(AAttribute), PathOf(ADecl));
  end;

  /// <summary>Steht AName am Attribut sicher für eine Variable bzw. Routine der Datei?</summary>
  function CertainVariable(const AName: string; AAttribute: TSyntaxNode): Boolean;
  var
    Decls: TList<TSyntaxNode>;
    Decl: TSyntaxNode;
  begin
    Result := False;
    Decls := Names.OnlyVariables(AName);
    if Decls = nil then
      Exit;
    for Decl in Decls do
      if VisibleAt(Decl, AAttribute) then
        Exit(True);
  end;

  // Iterativ (Bericht M1).
  procedure CheckArgument(AArgument, AAttribute: TSyntaxNode; const AAttributeName: string; var AReported: Boolean);
  var
    Pending: TStack<TSyntaxNode>;
    Node, Callee: TSyntaxNode;
    Index: Integer;
  begin
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(AArgument);
      while (Pending.Count > 0) and not AReported do
      begin
        Node := Pending.Pop;
        case Node.Kind of
          TSyntaxKind.Identifier:
            if CertainVariable(Node.Name, AAttribute) then
            begin
              AReport.Add(NodeRange(Node), Format('Das Argument %s von [%s] ist kein konstanter Ausdruck; ' +
                'Attributargumente müssen Konstanten, TypeInfo-Ausdrücke oder Array-Konstruktoren sein (wie E2448).',
                [Node.Name, AAttributeName]), TRuleConfidence.High, nil);
              AReported := True;
            end;
          TSyntaxKind.Call:
            begin
              // Nur Aufrufe eigener Routinen; SizeOf, High, TypeInfo usw. sind konstant, Typumwandlungen auch.
              if Node.ChildCount = 0 then
                Continue;
              Callee := Node[0];
              if (Callee.Kind = TSyntaxKind.Identifier) and CertainVariable(Callee.Name, AAttribute) then
              begin
                AReport.Add(NodeRange(Node), Format('Der Aufruf %s in [%s] ist kein konstanter Ausdruck; ' +
                  'Attributargumente müssen Konstanten, TypeInfo-Ausdrücke oder Array-Konstruktoren sein ' +
                  '(wie E2448).', [Callee.Name, AAttributeName]), TRuleConfidence.High, nil);
                AReported := True;
              end;
            end;
          TSyntaxKind.BinaryExpr, TSyntaxKind.UnaryExpr, TSyntaxKind.ParenExpr, TSyntaxKind.SetConstructor,
          TSyntaxKind.IndexAccess, TSyntaxKind.RangeExpr:
            for Index := Node.ChildCount - 1 downto 0 do
              Pending.Push(Node[Index]);
        else
          // Übrige Werte bewusst ohne Wirkung.
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  procedure CheckArguments(AAttribute: TSyntaxNode);
  var
    Index, Argument: Integer;
    Item: TSyntaxNode;
    Reported: Boolean;
  begin
    for Index := 0 to AAttribute.ChildCount - 1 do
    begin
      Item := AAttribute[Index];
      if Item.Kind <> TSyntaxKind.Call then
        Continue;
      Reported := False;
      for Argument := 1 to Item.ChildCount - 1 do
        CheckArgument(Item[Argument], AAttribute, DottedNameOf(Item[0]), Reported);
    end;
  end;

  /// <summary>Alle Attribut-Knoten vor dem Ziel, zu dem AAttribute gehört (ohne Parameter: nur AAttribute).</summary>
  function AttributeGroup(AAttribute: TSyntaxNode): TArray<TSyntaxNode>;
  var
    Parent: TSyntaxNode;
    Index: Integer;
  begin
    Result := [AAttribute];
    Parent := AAttribute.Parent;
    if (Parent = nil) or (Parent.Kind = TSyntaxKind.Parameter) then
    begin
      Result := nil;
      if Parent <> nil then
        for Index := 0 to Parent.ChildCount - 1 do
          if Parent[Index].Kind = TSyntaxKind.Attribute then
            Result := Result + [Parent[Index]];
      Exit;
    end;
    Index := 0;
    while (Index < Parent.ChildCount) and (Parent[Index] <> AAttribute) do
      Inc(Index);
    while (Index + 1 < Parent.ChildCount) and (Parent[Index + 1].Kind = TSyntaxKind.Attribute) do
    begin
      Inc(Index);
      Result := Result + [Parent[Index]];
    end;
  end;

  /// <summary>Ist AAttribute das erste Attribut vor seinem Ziel?</summary>
  function FirstOfGroup(AAttribute: TSyntaxNode): Boolean;
  var
    Parent: TSyntaxNode;
    Index: Integer;
  begin
    Parent := AAttribute.Parent;
    if Parent = nil then
      Exit(False);
    for Index := 0 to Parent.ChildCount - 1 do
      if Parent[Index] = AAttribute then
        Exit((Index = 0) or (Parent[Index - 1].Kind <> TSyntaxKind.Attribute));
    Result := False;
  end;

  procedure CheckWeakTarget(AItem, ATarget: TSyntaxNode);
  var
    Child: Integer;
    TypeNode: TSyntaxNode;
  begin
    if not (ATarget.Kind in [TSyntaxKind.Field, TSyntaxKind.VarDecl]) then
      Exit;
    TypeNode := nil;
    for Child := 0 to ATarget.ChildCount - 1 do
      if ATarget[Child].Kind <> TSyntaxKind.Attribute then
      begin
        TypeNode := ATarget[Child];
        Break;
      end;
    if (TypeNode = nil) or not CertainlyNoReference(Types, TypeNode) then
      Exit;
    AReport.Add(NodeRange(AItem), Format('[Weak] ist nur an Klassen- und Interface-Referenzen erlaubt; %s hat ' +
      'den Typ %s (wie E2584).', [Trim(ATarget.Name), OneLine(AContext.Text, TypeNode)]), TRuleConfidence.High,
      nil);
  end;

  procedure CheckTarget(AFirst: TSyntaxNode);
  var
    Group: TArray<TSyntaxNode>;
    Items: TArray<TSyntaxNode>;
    ItemNames: TArray<string>;
    Attribute, Target, Item: TSyntaxNode;
    Index, Other: Integer;
    Name: string;
    Duplicate: Boolean;
  begin
    Target := AttributeTarget(AFirst);
    if Target = nil then
      Exit;
    Group := AttributeGroup(AFirst);
    Items := nil;
    ItemNames := nil;
    for Attribute in Group do
      for Index := 0 to Attribute.ChildCount - 1 do
      begin
        Items := Items + [Attribute[Index]];
        ItemNames := ItemNames + [CompilerAttribute(Types, Attribute[Index])];
      end;
    for Index := 0 to High(Items) do
    begin
      Name := ItemNames[Index];
      if Name = '' then
        Continue;
      Item := Items[Index];
      Duplicate := False;
      for Other := 0 to Index - 1 do
        if SameText(ItemNames[Other], Name) and
          not TConditionalBranches.Exclusive(PathOf(Items[Other]), PathOf(Item)) then
          Duplicate := True;
      if Duplicate then
      begin
        AReport.Add(NodeRange(Item), Format('[%s] steht mehrfach an derselben Deklaration; ein Attribut des ' +
          'Compilers darf je Ziel nur einmal stehen (wie E2326).', [Name]), TRuleConfidence.High, nil);
        Continue;
      end;
      if SameText(Name, 'Volatile') and (Target.Kind in VolatileForbiddenTargets) then
        AReport.Add(NodeRange(Item), '[Volatile] gilt nur für Variablen, Parameter und Felder, nicht für Typen, ' +
          'Routinen, Methoden oder Properties (wie E2325).', TRuleConfidence.High, nil)
      else if SameText(Name, 'Weak') then
        CheckWeakTarget(Item, Target);
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or (Pos('[', AContext.Text) = 0) then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Types := TFileTypes.Collect(AContext.Tree.Root);
  Paths := TConditionalBranches.Paths(Tokens);
  Names := nil;
  Attributes := TList<TSyntaxNode>.Create;
  try
    AContext.Tree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := True;
        if ANode.Kind = TSyntaxKind.Attribute then
          Attributes.Add(ANode);
      end);
    if Attributes.Count = 0 then
      Exit;
    Names := TDeclarationNames.Create(AContext.Tree.Root);
    for Node in Attributes do
    begin
      CheckArguments(Node);
      if FirstOfGroup(Node) then
        CheckTarget(Node);
    end;
  finally
    Names.Free;
    Attributes.Free;
  end;
end;

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
    if SameText(Trim(Name), AName) then
      Exit(True);
  Result := False;
end;

/// <summary>Erster Kindknoten, der einen Typ beschreibt (TypeReference, ArrayType …), nil ohne.</summary>
function TypeChild(ANode: TSyntaxNode): TSyntaxNode;
var
  Index: Integer;
begin
  for Index := 0 to ANode.ChildCount - 1 do
    if ANode[Index].Kind in [TSyntaxKind.TypeReference, TSyntaxKind.ArrayType, TSyntaxKind.RecordType,
      TSyntaxKind.SetType, TSyntaxKind.EnumType, TSyntaxKind.PointerType, TSyntaxKind.FileType,
      TSyntaxKind.ProcedureType, TSyntaxKind.SubrangeType, TSyntaxKind.ClassOfType] then
      Exit(ANode[Index]);
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
      Break;
    case Section.Kind of
      TSyntaxKind.VarSection, TSyntaxKind.ConstSection, TSyntaxKind.TypeSection:
        for Inner := 0 to Section.ChildCount - 1 do
        begin
          Decl := Section[Inner];
          if not (Decl.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.ConstDecl, TSyntaxKind.TypeDecl]) or
            not InNameList(Decl.Name, AName) then
            Continue;
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
          AResolution := TNameResolution.Create(TNameMeaning.Variable, Section, TypeChild(Section));
      TSyntaxKind.PropertyDecl:
        if SameText(Section.Name, AName) then
          AResolution := TNameResolution.Create(TNameMeaning.Variable, Section, TypeChild(Section));
      TSyntaxKind.RoutineDecl, TSyntaxKind.RoutineHeader:
        if SameText(LastPart(Section.Name), AName) and (Pos('.', Section.Name) = 0) then
          AResolution := TNameResolution.Create(TNameMeaning.Other, Section, nil);
      TSyntaxKind.UsesClause:
        for Inner := 0 to Section.ChildCount - 1 do
          if SameText(LastPart(Section[Inner].Name), AName) then
            AResolution := TNameResolution.Create(TNameMeaning.Other, Section[Inner], nil);
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
          if (Child[Inner].Kind = TSyntaxKind.Parameter) and InNameList(Child[Inner].Name, AName) then
            AResolution := TNameResolution.Create(TNameMeaning.Variable, Child[Inner], TypeChild(Child[Inner]));
      TSyntaxKind.GenericParams:
        for Inner := 0 to Child.ChildCount - 1 do
          if SameText(Child[Inner].Name, AName) then
            AResolution := TNameResolution.Create(TNameMeaning.TypeName, Child[Inner], nil);
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;
  if (AResolution.Meaning = TNameMeaning.NotFound) and SameText(AName, 'Result') and
    (AHeader.FindChild(TSyntaxKind.TypeReference) <> nil) then
    AResolution := TNameResolution.Create(TNameMeaning.Variable, AHeader, AHeader.FindChild(TSyntaxKind.TypeReference));
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
      Exit(True);
    Struct := Types.Types[Index];
    if not (Struct.Kind in [TSyntaxKind.ClassType, TSyntaxKind.RecordType, TSyntaxKind.ObjectType]) then
      Exit(True);
    if FindInSections(Struct, AName, -1, AResolution) then
      Exit(True);
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
            Exit(TNameResolution.Create(TNameMeaning.Uncertain, nil, nil));
        TSyntaxKind.Block:
          begin
            Position := Parent.ChildCount - 1;
            while (Position >= 0) and (Parent[Position] <> Node) do
              Dec(Position);
            for Index := Position - 1 downto 0 do
              if (Parent[Index].Kind in [TSyntaxKind.InlineVar, TSyntaxKind.InlineConst]) and
                InNameList(Parent[Index].Name, AName) then
              begin
                if Parent[Index].Kind = TSyntaxKind.InlineVar then
                  Exit(TNameResolution.Create(TNameMeaning.Variable, Parent[Index], TypeChild(Parent[Index])));
                Exit(TNameResolution.Create(TNameMeaning.Other, Parent[Index], nil));
              end;
          end;
        TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.ExceptionHandler:
          if SameText(Parent.Name, AName) then
            Exit(TNameResolution.Create(TNameMeaning.Variable, Parent, TypeChild(Parent)));
        TSyntaxKind.AnonymousMethod:
          begin
            if FindInHeader(Parent, AName, Result) or FindInSections(Parent, AName, -1, Result) then
              Exit;
          end;
        TSyntaxKind.RoutineDecl:
          begin
            Header := Parent.FindChild(TSyntaxKind.RoutineHeader);
            if (Header <> nil) and FindInHeader(Header, AName, Result) then
              Exit;
            if FindInSections(Parent, AName, -1, Result) then
              Exit;
            if SameText(LastPart(Parent.Name), AName) then
              Exit(TNameResolution.Create(TNameMeaning.Other, Parent, nil));
            if (Pos('.', Parent.Name) > 0) and FindInOwner(Parent, AName, Result) then
              Exit;
          end;
        TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection:
          begin
            // Unit-Ebene: im implementation-Teil zuerst die eigenen Deklarationen davor, dann der interface-Teil.
            if FindInSections(Parent, AName, ANode.StartOffset, Result) then
              Exit;
            if (Parent.Kind = TSyntaxKind.ImplementationSection) and (Parent.Parent <> nil) then
            begin
              Header := Parent.Parent.FindChild(TSyntaxKind.InterfaceSection);
              if (Header <> nil) and FindInSections(Header, AName, -1, Result) then
                Exit;
            end;
            Exit(TNameResolution.Create(TNameMeaning.NotFound, nil, nil));
          end;
        TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile:
          begin
            if FindInSections(Parent, AName, ANode.StartOffset, Result) then
              Exit;
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
        Exit;
      if (Pos('.', Result.Name) > 0) or (Result.FindChild(TSyntaxKind.GenericArgs) <> nil) then
        Exit(nil);
      Index := Types.IndexOf(Result.Name);
      if Index < 0 then
        Exit;
      Result := Types.Types[Index];
    end;
    Result := nil;
  end;

  function HasExplicitValues(AEnum: TSyntaxNode): Boolean;
  var
    Index: Integer;
  begin
    for Index := 0 to AEnum.ChildCount - 1 do
      if AEnum[Index].Kind <> TSyntaxKind.Identifier then
        Exit(True);
    Result := False;
  end;

  /// <summary>Deklariert eine Unit im Index AName auf oberster Ebene (eigene Routine Default o. ä.)?</summary>
  function DeclaredInIndex(const AName: string): Boolean;
  var
    Location: TSymbolLocation;
  begin
    if AContext.Index = nil then
      Exit(False);
    for Location in AContext.Index.FindSymbols(AName) do
      if Location.Symbol.Container = '' then
        Exit(True);
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
      Exit;
    Name := Argument.Name;
    Resolution := Resolve(ACall, Name);
    if (Resolution.Decl <> nil) and (Resolution.Meaning in [TNameMeaning.Variable, TNameMeaning.TypeName]) and
      not TConditionalBranches.Implies(PathOf(ACall), PathOf(Resolution.Decl)) then
      Exit;
    case Resolution.Meaning of
      TNameMeaning.Variable:
        begin
          Code := 'E2537';
          if IsTypeInfo then
            Code := 'E2133';
          Fixes := nil;
          TypeText := '';
          if (Resolution.TypeNode <> nil) and (Resolution.TypeNode.Kind = TSyntaxKind.TypeReference) then
            TypeText := OneLine(AContext.Text, Resolution.TypeNode);
          if TypeText <> '' then
          begin
            Fixes := [TRuleFix.Create(Format('%s(%s) einsetzen', [Intrinsic, TypeText]),
              [TRuleEdit.Create(NodeRange(Argument), TypeText)])];
            AReport.Add(NodeRange(Argument), Format('%s erwartet einen Typ, %s ist eine Variable; gemeint ist ' +
              '%s(%s) (wie %s).', [Intrinsic, Name, Intrinsic, TypeText, Code]), TRuleConfidence.High, Fixes);
          end
          else
            AReport.Add(NodeRange(Argument), Format('%s erwartet einen Typ, %s ist eine Variable (wie %s).',
              [Intrinsic, Name, Code]), TRuleConfidence.High, nil);
        end;
      TNameMeaning.NotFound, TNameMeaning.TypeName:
        begin
          Behind := nil;
          BuiltinFile := False;
          if Resolution.Meaning = TNameMeaning.TypeName then
          begin
            if Resolution.Decl.Kind <> TSyntaxKind.TypeDecl then
              Exit;
            Behind := TypeBehind(Resolution.Decl);
            if Behind = nil then
              Exit;
          end
          else
          begin
            // Text, TextFile und file aus System; eine gleichnamige Deklaration der Datei macht still.
            if Names.Declared(Name) or (Types.IndexOf(Name) >= 0) then
              Exit;
            BuiltinFile := MatchText(Name, ['Text', 'TextFile']) or (not IsTypeInfo and SameText(Name, 'File'));
            if not BuiltinFile then
              Exit;
          end;
          if BuiltinFile or (Behind.Kind = TSyntaxKind.FileType) then
          begin
            if IsTypeInfo then
              AReport.Add(NodeRange(Argument), Format('%s hat keine Typinformation: Dateitypen erzeugen keine ' +
                'RTTI (wie E2134).', [Name]), TRuleConfidence.High, nil)
            else if (ACall.Parent <> nil) and (ACall.Parent.Kind = TSyntaxKind.AssignStatement) and
              (ACall.Parent.ChildCount > 1) and (ACall.Parent[1] = ACall) then
              // Die Zuweisung an eine Dateivariable meldet dcc zusätzlich als E2015.
              AReport.Add(NodeRange(Argument), Format('Default ist für den Dateityp %s nicht erlaubt, und ' +
                'Dateivariablen lassen sich nicht zuweisen (wie E2538 und E2015).', [Name]),
                TRuleConfidence.High, nil)
            else
              AReport.Add(NodeRange(Argument), Format('Default ist für den Dateityp %s nicht erlaubt (wie E2538).',
                [Name]), TRuleConfidence.High, nil);
          end
          else if IsTypeInfo and (Behind.Kind = TSyntaxKind.EnumType) and HasExplicitValues(Behind) then
            AReport.Add(NodeRange(Argument), Format('%s hat keine Typinformation: Aufzählungen mit festen Werten ' +
              'erzeugen keine RTTI (wie E2134).', [Name]), TRuleConfidence.High, nil);
        end;
      TNameMeaning.Other: ;
      TNameMeaning.Uncertain: ;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or
    not (ContainsText(AContext.Text, 'TypeInfo') or ContainsText(AContext.Text, 'Default')) then
    Exit;
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
          Calls.Add(ANode);
      end);
    if Calls.Count = 0 then
      Exit;
    Names := TDeclarationNames.Create(AContext.Tree.Root);
    for Call in Calls do
      // Eine eigene Routine TypeInfo bzw. Default (Datei oder Index) verdeckt die des Compilers.
      if not Names.Declared(Call[0].Name) and not DeclaredInIndex(Call[0].Name) then
        CheckCall(Call);
  finally
    Names.Free;
    Calls.Free;
  end;
end;

procedure RegisterTypeRestrictionRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TOperatorDeclarationInvalidRule.Create);
  ARegistry.Register(TGenericDeclarationInvalidRule.Create);
  ARegistry.Register(TTypeRestrictionViolatedRule.Create);
  ARegistry.Register(TAttributeUsageInvalidRule.Create);
  ARegistry.Register(TTypeInfoInvalidRule.Create);
end;

end.
