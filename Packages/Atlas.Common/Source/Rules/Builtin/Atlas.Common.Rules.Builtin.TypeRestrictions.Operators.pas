unit Atlas.Common.Rules.Builtin.TypeRestrictions.Operators;

// Regel aus TypeRestrictions, registriert mit RegisterTypeRestrictionRules:
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
  Atlas.Common.Rules.Contract;

const
  OperatorDeclarationInvalidRuleId = 'operator-declaration-invalid';

type
  TOperatorDeclarationInvalidRule = class(TInterfacedObject, IRule)
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
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Rules.Builtin.Inheritance,
  Atlas.Text.Fuzzy,
  Atlas.Common.Rules.Builtin.TypeRestrictions.Heads,
  Atlas.Common.Rules.Builtin.TypeRestrictions.Symbols;

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
  begin
    Result := TOperatorShape.Unary;
  end
  else if MatchText(AName, ConversionOperators) then
  begin
    Result := TOperatorShape.Conversion;
  end
  else if MatchText(AName, ComparisonOperators) then
  begin
    Result := TOperatorShape.Comparison;
  end
  else if MatchText(AName, BinaryOperators) then
  begin
    Result := TOperatorShape.Binary;
  end
  else if MatchText(AName, ManagedOperators) then
  begin
    Result := TOperatorShape.Managed;
  end
  else if SameText(AName, 'Assign') then
  begin
    Result := TOperatorShape.Assign;
  end
  else if MatchText(AName, ToleratedOperators) then
  begin
    Result := TOperatorShape.Tolerated;
  end
  else
  begin
    Result := TOperatorShape.Unknown;
  end;
end;

function KnownOperators: TArray<string>;
var
  Name: string;
begin
  Result := nil;
  for Name in UnaryOperators do
  begin
    Result := Result + [Name];
  end;
  for Name in ConversionOperators do
  begin
    Result := Result + [Name];
  end;
  for Name in ComparisonOperators do
  begin
    Result := Result + [Name];
  end;
  for Name in BinaryOperators do
  begin
    Result := Result + [Name];
  end;
  for Name in ManagedOperators do
  begin
    Result := Result + [Name];
  end;
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
    begin
      Result := Result + AEdit(Body);
    end;
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
        begin
          Result := [TRuleEdit.Create(TokenRange(Tokens[Index]), ANew)];
        end;
      end));
  end;

  function ResultFix(const AOwn: string; const AHead: TRoutineHead; const ANew, ATitle: string): TRuleFix;
  begin
    Result := TRuleFix.Create(ATitle, BothHeads(AOwn, AHead,
      function(AOne: TRoutineHead): TArray<TRuleEdit>
      begin
        Result := nil;
        if AOne.ResultType <> nil then
        begin
          Result := [TRuleEdit.Create(NodeRange(AOne.ResultType), ANew)];
        end;
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
        begin
          Exit;
        end;
        Param := AOne.Parameters[0];
        Index := TRoutineBody.TokenAt(Tokens, Param.StartOffset);
        Depth := 0;
        while (Index < Length(Tokens)) and (Tokens[Index].Offset < Param.EndOffset) do
        begin
          if Tokens[Index].IsSymbol('[') then
          begin
            Inc(Depth);
          end
          else if Tokens[Index].IsSymbol(']') then
          begin
            Dec(Depth);
          end
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
        begin
          Result := [TRuleEdit.Create(TTextRange.Create(Tokens[Index].EndPos, Tokens[Index].EndPos), ATemplate)];
        end;
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
      begin
        Report(TokenRange(Tokens[mName]), Format('Zu %s.%s gibt es keine gültige Deklaration; der Rumpf passt zu ' +
          'nichts (wie E2037).', [AOwn, AHead.Header.Name]), nil);
      end;
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
    begin
      Exit;
    end;
    Own := ContainerName(AHeader);
    Name := AHeader.Name;
    Index := NameToken(Tokens, AHeader);
    if (Own = '') or (Name = '') or (Index < 0) or not IsValidIdent(Name) then
    begin
      Exit;
    end;
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
      begin
        Report(Range, Format('Unbekannter Operator %s; gemeint ist wohl %s (wie E2393).', [Name, Closest]),
          [RenameFix(Own, Head, Closest)]);
      end
      else
      begin
        Report(Range, Format('Unbekannter Operator %s (wie E2393).', [Name]), nil);
      end;
      ReportBodies(Own, Head);
      Exit;
    end;
    if Shape = TOperatorShape.Tolerated then
    begin
      Exit;
    end;
    OwnNames := Types.SameNames(Own);
    ParamTypes := nil;
    for Param in Head.Parameters do
    begin
      for Count := 1 to Length(SplitString(Param.Name, ',')) do
      begin
        if (Param.ChildCount > 0) and (Param[Param.ChildCount - 1].Kind = TSyntaxKind.TypeReference) then
        begin
          ParamTypes := ParamTypes + [Param[Param.ChildCount - 1].Name];
        end
        else
        begin
          ParamTypes := ParamTypes + [''];
        end;
      end;
    end;
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
      begin
        Report(Range, Format('Der Operator %s muss %d Parameter haben (wie E2517).', [Name, Expected]),
          [ParametersFix(Own, Head, Template)]);
      end
      else
      begin
        Report(Range, Format('Der Operator %s muss %d Parameter haben (wie E2517).', [Name, Expected]), nil);
      end;
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
    begin
      Report(Range, 'Der erste Parameter von Assign muss ein var-Parameter des eigenen Typs sein (wie E2617).',
        [VarFix(Own, Head)]);
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'operator') then
  begin
    Exit;
  end;
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
        begin
          Headers.Add(ANode);
        end;
      end);
    for Header in Headers do
    begin
      CheckOperator(Header);
    end;
  finally
    Headers.Free;
  end;
end;

end.
