unit Atlas.Common.Rules.Builtin.TypeRestrictions;

// Feste Sprachregeln für Typdeklarationen (#909, Gruppe Compiler vorab), die
// der Parser allein erkennt:
//   operator-declaration-invalid  class operator mit unbekanntem Namen
//                                 (#1030, E2393), falscher Parameterzahl
//                                 (E2517), ohne den eigenen Typ in den
//                                 Parametern (E2518) bzw. in Parameter oder
//                                 Ergebnis (E2521), Inc/Dec mit anderem
//                                 Ergebnis als dem ersten Parameter (E2519),
//                                 Vergleich ohne Boolean-Ergebnis (E2520),
//                                 Umwandlung in einen Vorfahren (E2522) oder
//                                 Assign ohne var vor dem ersten Parameter
//                                 (E2464).
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
//
// Typen gelten als gleich, wenn ihr Name ohne Unit-Präfix und Typargumente
// übereinstimmt. Steht in der Datei ein Alias auf den eigenen Typ, bleibt die
// Regel bei E2518, E2519, E2521 still. Operatoren, deren Namen Delphi nicht
// sicher ablehnt (True, False, OnesComplement), gelten als bekannt.
//
// Korrekturen: Name des nächstliegenden Operators (E2393), Boolean als
// Ergebnis (E2520), Ergebnis wie der erste Parameter (E2519), var vor dem
// ersten Parameter (E2464), Parameterliste nach Vorlage (E2517); jeweils in
// Deklaration und Rumpf.

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

const
  OperatorDeclarationInvalidRuleId = 'operator-declaration-invalid';
  GenericDeclarationInvalidRuleId = 'generic-declaration-invalid';

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
  Atlas.Common.Rules.Derived,
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
  Result := -1;
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

/// <summary>Text eines Knotens ohne Zeilenumbrüche und doppelte Leerzeichen, für Vergleiche.</summary>
function Squeezed(const AText: string; ANode: TSyntaxNode): string;
var
  Text: string;
begin
  if ANode = nil then
    Exit('');
  Text := TRoutineBody.TextOf(AText, ANode);
  Text := StringReplace(StringReplace(Text, #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]);
  while Pos('  ', Text) > 0 do
    Text := StringReplace(Text, '  ', ' ', [rfReplaceAll]);
  Result := LowerCase(Trim(Text));
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

  procedure CheckOperator(AHeader: TSyntaxNode);
  var
    Head: TRoutineHead;
    Own, Name, Closest, Other, Template, Ancestor: string;
    OwnNames, ParamTypes: TArray<string>;
    Shape: TOperatorShape;
    Range: TTextRange;
    Index, Count, Expected, Depth: Integer;
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
      // Umwandlung in bzw. aus einem Vorfahren (E2522), Kette aus der Datei.
      if HasOwn then
      begin
        Ancestor := Types.ParentOf(Own);
        Depth := 0;
        while (Ancestor <> '') and (Depth < 32) do
        begin
          if MatchText(Ancestor, ParamTypes) or ((Head.ResultType <> nil) and
            SameText(BareTypeName(Head.ResultType.Name), Ancestor)) then
          begin
            Report(Range, Format('%s darf nicht in den Vorfahren %s oder aus ihm umwandeln (wie E2522).',
              [Name, Ancestor]), nil);
            Exit;
          end;
          Ancestor := Types.ParentOf(Ancestor);
          Inc(Depth);
        end;
      end;
    end
    else if not HasOwn and Certain and (Shape <> TOperatorShape.Managed) then
    begin
      Report(Range, Format('Der Operator %s muss %s in mindestens einem Parameter haben (wie E2518).', [Name, Own]),
        nil);
      Exit;
    end;
    // Vergleich ohne Boolean (E2520).
    if (Shape = TOperatorShape.Comparison) and (Head.ResultType <> nil) and
      not MatchText(BareTypeName(Head.ResultType.Name), BooleanTypeNames) and
      Types.CertainlyOther(Head.ResultType.Name, BooleanTypeNames) then
    begin
      Report(Range, Format('%s muss Boolean liefern (wie E2520).', [Name]),
        [ResultFix(Own, Head, 'Boolean', 'Boolean als Ergebnis')]);
      Exit;
    end;
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
    // Assign eines Managed Records: erster Parameter var (E2464).
    if (Shape = TOperatorShape.Assign) and (Head.Parameters <> nil) and
      (Head.Parameters[0].Modifier <> TParameterModifier.VarParam) then
      Report(Range, 'Der erste Parameter von Assign muss ein var-Parameter sein (wie E2464).',
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

function TGenericDeclarationInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(GenericDeclarationInvalidRuleId, TRuleSeverity.Error,
    'Generische Deklaration unzulässig');
end;

procedure TGenericDeclarationInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Types: TFileTypes;
  Root, InterfacePart, ImplementationPart: TSyntaxNode;
  Nodes: TList<TSyntaxNode>;
  Node: TSyntaxNode;
  Index: Integer;
  Ancestry: TAncestry;

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

  /// <summary>Mitglieder von ADecl und seinen Vorfahren; False, wenn die Kette nicht sicher bekannt ist.</summary>
  function VisibleMembers(ADecl: TSyntaxNode; out ANames: TArray<string>): Boolean;
  var
    TypeNode, Outer: TSyntaxNode;
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
    TypeNode := TypeOfDecl(ADecl);
    if TypeNode.Kind <> TSyntaxKind.ClassType then
      Exit(True);
    Result := False;
    if Ancestry = nil then
      Ancestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(TRuleDerived.Open(AContext), AContext));
    Chain := Ancestry.Ancestors(ADecl.Name, Complete, ObjectMissing);
    if not Complete then
      Exit;
    for Location in Chain do
      for Member in Ancestry.Members(Location) do
        ANames := ANames + [Member.Name];
    for Name in ObjectMemberNames do
      ANames := ANames + [Name];
    Result := True;
  end;

  // Methoden generischer Typen bzw. generische Methoden aus dem interface-Teil, die Symbole des
  // implementation-Teils verwenden: E2506.
  procedure CheckLocalSymbols;
  var
    Local, Known, Used: TArray<string>;
    Child: Integer;
    Routine, Header, Decl, Outer: TSyntaxNode;
    Generic: Boolean;
    Usages: TList<TSyntaxNode>;
    Use: TSyntaxNode;
    Name, Symbol: string;
  begin
    if (InterfacePart = nil) or (ImplementationPart = nil) then
      Exit;
    Local := nil;
    Known := SectionNames(InterfacePart);
    for Name in SectionNames(ImplementationPart) do
      if not MatchText(Name, Known) then
        Local := Local + [Name];
    if Local = nil then
      Exit;
    Usages := TList<TSyntaxNode>.Create;
    try
      for Child := 0 to ImplementationPart.ChildCount - 1 do
      begin
        Routine := ImplementationPart[Child];
        Header := Routine.FindChild(TSyntaxKind.RoutineHeader);
        if (Routine.Kind <> TSyntaxKind.RoutineDecl) or (Header = nil) or (Pos('.', Routine.Name) = 0) then
          Continue;
        Decl := FindStructDecl(InterfacePart, LastPart(Copy(Routine.Name, 1, LastDelimiter('.', Routine.Name) - 1)));
        if Decl = nil then
          Continue;
        Generic := OwnGenericParams(Tokens, Header) <> nil;
        Outer := Decl;
        while Outer <> nil do
        begin
          if (Outer.Kind = TSyntaxKind.TypeDecl) and (Outer.FindChild(TSyntaxKind.GenericParams) <> nil) then
            Generic := True;
          Outer := Outer.Parent;
        end;
        if not Generic or not VisibleMembers(Decl, Known) then
          Continue;
        Known := Known + NamesBelow(Routine);
        Usages.Clear;
        Routine.Walk(
          function(ANode: TSyntaxNode): Boolean
          begin
            Result := not (ANode.Kind in [TSyntaxKind.WithStatement, TSyntaxKind.GenericParams]) and
              (ANode <> Header);
            if Result and (ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.TypeReference]) and
              (Pos('.', ANode.Name) = 0) then
              Usages.Add(ANode);
          end);
        Used := nil;
        for Use in Usages do
        begin
          Symbol := Use.Name;
          if MatchText(Symbol, Local) and not MatchText(Symbol, Known) and not MatchText(Symbol, Used) then
          begin
            Used := Used + [Symbol];
            Report(NodeRange(Use), Format('%s gehört zu einem generischen Typ bzw. ist generisch, steht im ' +
              'interface-Teil und darf %s aus dem implementation-Teil nicht verwenden (wie E2506).',
              [Routine.Name, Symbol]));
          end;
        end;
      end;
    finally
      Usages.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or (Pos('<', AContext.Text) = 0) then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Root := AContext.Tree.Root;
  Types := TFileTypes.Collect(Root);
  InterfacePart := Root.FindChild(TSyntaxKind.InterfaceSection);
  ImplementationPart := Root.FindChild(TSyntaxKind.ImplementationSection);
  Ancestry := nil;
  Nodes := TList<TSyntaxNode>.Create;
  try
    Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := True;
        if ANode.Kind in [TSyntaxKind.GenericParams, TSyntaxKind.TypeDecl, TSyntaxKind.ClassOfType,
          TSyntaxKind.Attribute, TSyntaxKind.RoutineHeader, TSyntaxKind.MemberAccess] then
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
      end;
    end;
    CheckLocalSymbols;
  finally
    Nodes.Free;
    Ancestry.Free;
  end;
end;

procedure RegisterTypeRestrictionRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TOperatorDeclarationInvalidRule.Create);
  ARegistry.Register(TGenericDeclarationInvalidRule.Create);
end;

end.
