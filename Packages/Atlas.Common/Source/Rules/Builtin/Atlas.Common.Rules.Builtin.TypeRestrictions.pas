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

const
  OperatorDeclarationInvalidRuleId = 'operator-declaration-invalid';

/// <summary>Name ohne Unit-Präfix und ohne Typargumente: "System.TList&lt;T&gt;" ergibt "TList".</summary>
function BareTypeName(const AName: string): string;

procedure RegisterTypeRestrictionRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Editing.RoutineBody,
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
    function IndexOf(const AName: string): Integer;
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
  for Index := 0 to High(Names) do
    if SameText(Names[Index], AName) then
      Exit(Index);
  Result := -1;
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

procedure RegisterTypeRestrictionRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TOperatorDeclarationInvalidRule.Create);
end;

end.
