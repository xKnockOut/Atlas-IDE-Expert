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
  cOperatorDeclarationInvalidRuleId = 'operator-declaration-invalid';

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
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TTypeRestrictionsOperatorsText = (Title, VarFirst, ParamsFromTemplate, NoDeclaration, UnknownMeant, Unknown,
    ParamCount, ParamOrResult, InOneParam, SameType, AsResult, AssignVar, RenameTo);

const
  cTexts: array[TTypeRestrictionsOperatorsText] of TAtlasText = (
    (De: 'class operator falsch deklariert'; En: 'class operator declared incorrectly'),
    (De: 'var vor den ersten Parameter setzen'; En: 'Put var before the first parameter'),
    (De: 'Parameter nach Vorlage: '; En: 'Parameters from template: '),
    (De: 'Zu %s.%s gibt es keine gültige Deklaration; der Rumpf passt zu nichts (wie E2037).';
     En: 'There is no valid declaration for %s.%s; the body matches nothing (like E2037).'),
    (De: 'Unbekannter Operator %s; gemeint ist wohl %s (wie E2393).';
     En: 'Unknown operator %s; %s is probably meant (like E2393).'),
    (De: 'Unbekannter Operator %s (wie E2393).'; En: 'Unknown operator %s (like E2393).'),
    (De: 'Der Operator %s muss %d Parameter haben (wie E2517).';
     En: 'The operator %s must have %d parameters (like E2517).'),
    (De: '%s muss %s als Parameter oder Ergebnis haben (wie E2521).';
     En: '%s must have %s as parameter or result (like E2521).'),
    (De: 'Der Operator %s muss %s in mindestens einem Parameter haben (wie E2518).';
     En: 'The operator %s must have %s in at least one parameter (like E2518).'),
    (De: '%s muss denselben Typ liefern wie den ersten Parameter, hier %s (wie E2519).';
     En: '%s must return the same type as the first parameter, here %s (like E2519).'),
    (De: ' als Ergebnis'; En: ' as result'),
    (De: 'Der erste Parameter von Assign muss ein var-Parameter des eigenen Typs sein (wie E2617).';
     En: 'The first parameter of Assign must be a var parameter of the own type (like E2617).'),
    (De: 'In %s umbenennen'; En: 'Rename to %s'));

{$SCOPEDENUMS OFF}

{ TOperatorDeclarationInvalidRule }

type
{$SCOPEDENUMS ON}
  /// <summary>Art eines Operators für operator-declaration-invalid (#1030).</summary>
  TOperatorShape = (Unknown, Tolerated, Unary, Conversion, Binary, Comparison, Managed, Assign);
{$SCOPEDENUMS OFF}

const
  cUnaryOperators: array[0..6] of string = ('Negative', 'Positive', 'Inc', 'Dec', 'LogicalNot', 'Trunc', 'Round');
  cConversionOperators: array[0..1] of string = ('Implicit', 'Explicit');
  cComparisonOperators: array[0..5] of string = ('Equal', 'NotEqual', 'GreaterThan', 'GreaterThanOrEqual',
    'LessThan', 'LessThanOrEqual');
  cBinaryOperators: array[0..14] of string = ('In', 'Add', 'Subtract', 'Multiply', 'Divide', 'IntDivide', 'Modulus',
    'LeftShift', 'RightShift', 'LogicalAnd', 'LogicalOr', 'LogicalXor', 'BitwiseAnd', 'BitwiseOr', 'BitwiseXor');
  cManagedOperators: array[0..1] of string = ('Initialize', 'Finalize');
  // Namen, die Delphi womöglich kennt; ohne Prüfung.
  cToleratedOperators: array[0..2] of string = ('True', 'False', 'OnesComplement');

function OperatorShape(const AName: string): TOperatorShape;
begin
  if MatchText(AName, cUnaryOperators) then
  begin
    Result := TOperatorShape.Unary;
  end
  else if MatchText(AName, cConversionOperators) then
  begin
    Result := TOperatorShape.Conversion;
  end
  else if MatchText(AName, cComparisonOperators) then
  begin
    Result := TOperatorShape.Comparison;
  end
  else if MatchText(AName, cBinaryOperators) then
  begin
    Result := TOperatorShape.Binary;
  end
  else if MatchText(AName, cManagedOperators) then
  begin
    Result := TOperatorShape.Managed;
  end
  else if SameText(AName, 'Assign') then
  begin
    Result := TOperatorShape.Assign;
  end
  else if MatchText(AName, cToleratedOperators) then
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
  mName: string;
begin
  Result := nil;
  for mName in cUnaryOperators do
  begin
    Result := Result + [mName];
  end;
  for mName in cConversionOperators do
  begin
    Result := Result + [mName];
  end;
  for mName in cComparisonOperators do
  begin
    Result := Result + [mName];
  end;
  for mName in cBinaryOperators do
  begin
    Result := Result + [mName];
  end;
  for mName in cManagedOperators do
  begin
    Result := Result + [mName];
  end;
  Result := Result + ['Assign'];
end;

type
  /// <summary>Ein class operator mit allem, was die Prüfungen brauchen.</summary>
  TOperatorSite = record
    Head: TRoutineHead;
    Own: string;
    Name: string;
    Range: TTextRange;
    Shape: TOperatorShape;
    OwnNames: TArray<string>;
    /// <summary>Typname je Parametername ('' ohne Typ).</summary>
    ParamTypes: TArray<string>;
  end;

/// <summary>Typname je Parametername des Kopfs ("A, B: T" ergibt zweimal T, '' ohne Typ).</summary>
function ParameterTypeNames(const AHead: TRoutineHead): TArray<string>;
var
  mParam: TSyntaxNode;
  mType: string;
  mCount: Integer;
begin
  Result := nil;
  for mParam in AHead.Parameters do
  begin
    mType := '';
    if (mParam.ChildCount > 0) and (mParam[mParam.ChildCount - 1].Kind = TSyntaxKind.TypeReference) then
    begin
      mType := mParam[mParam.ChildCount - 1].Name;
    end;
    for mCount := 1 to Length(SplitString(mParam.Name, ',')) do
    begin
      Result := Result + [mType];
    end;
  end;
end;

/// <summary>Verlangte Parameterzahl eines Operators der Art AShape.</summary>
function ExpectedParameterCount(AShape: TOperatorShape): Integer;
begin
  case AShape of
    TOperatorShape.Unary, TOperatorShape.Conversion, TOperatorShape.Managed:
      Result := 1;
  else
    Result := 2;
  end;
end;

/// <summary>Vorlage der Parameterliste für einen Operator der Art AShape im Typ AOwn; '' ohne Vorlage.</summary>
function ParameterTemplate(AShape: TOperatorShape; const AOwn: string): string;
begin
  case AShape of
    TOperatorShape.Unary:
      Result := '(const A: ' + AOwn + ')';
    TOperatorShape.Managed:
      Result := '(out Dest: ' + AOwn + ')';
    TOperatorShape.Assign:
      Result := '(var Dest: ' + AOwn + '; const [ref] Src: ' + AOwn + ')';
    TOperatorShape.Binary, TOperatorShape.Comparison:
      Result := '(const A, B: ' + AOwn + ')';
  else
    Result := '';
  end;
end;

function TOperatorDeclarationInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cOperatorDeclarationInvalidRuleId, TRuleSeverity.Error,
    cTexts[TTypeRestrictionsOperatorsText.Title].Text);
end;

procedure TOperatorDeclarationInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TArray<TPascalToken>;
  mTypes: TFileTypes;
  mHeaders: TList<TSyntaxNode>;
  mHeader: TSyntaxNode;

  /// <summary>Edits für Deklaration und gleiche Rümpfe; AEdit liefert je Kopf die Änderung.</summary>
  function BothHeads(const AOwn: string; const AHead: TRoutineHead;
    const AEdit: TFunc<TRoutineHead, TArray<TRuleEdit>>): TArray<TRuleEdit>;
  var
    mBody: TRoutineHead;
  begin
    Result := AEdit(AHead);
    for mBody in ImplementationHeads(AContext.Text, mTokens, AContext.Tree.Root, AOwn + '.' +
      Copy(AHead.Header.Name, LastDelimiter('.', AHead.Header.Name) + 1, MaxInt), AHead) do
    begin
      Result := Result + AEdit(mBody);
    end;
  end;

  function RenameFix(const AOwn: string; const AHead: TRoutineHead; const ANew: string): TRuleFix;
  begin
    Result := TRuleFix.Create(cTexts[TTypeRestrictionsOperatorsText.RenameTo].Fmt([ANew]), BothHeads(AOwn, AHead,
      function(AOne: TRoutineHead): TArray<TRuleEdit>
      var
        Index: Integer;
      begin
        Result := nil;
        Index := NameToken(mTokens, AOne.Header);
        if Index >= 0 then
        begin
          Result := [TRuleEdit.Create(TokenRange(mTokens[Index]), ANew)];
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
    Result := TRuleFix.Create(cTexts[TTypeRestrictionsOperatorsText.VarFirst].Text, BothHeads(AOwn, AHead,
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
        Index := TRoutineBody.TokenAt(mTokens, Param.StartOffset);
        Depth := 0;
        while (Index < Length(mTokens)) and (mTokens[Index].Offset < Param.EndOffset) do
        begin
          if mTokens[Index].IsSymbol('[') then
          begin
            Inc(Depth);
          end
          else if mTokens[Index].IsSymbol(']') then
          begin
            Dec(Depth);
          end
          else if (Depth = 0) and (mTokens[Index].IsKeyword('const') or SameText(mTokens[Index].Text, 'out') or
            SameText(mTokens[Index].Text, 'constref')) then
          begin
            Result := [TRuleEdit.Create(TokenRange(mTokens[Index]), 'var')];
            Exit;
          end
          else if (Depth = 0) and (mTokens[Index].Kind = TPascalTokenKind.Identifier) then
          begin
            Result := [TRuleEdit.Create(TTextRange.Create(mTokens[Index].StartPos, mTokens[Index].StartPos), 'var ')];
            Exit;
          end;
          Inc(Index);
        end;
      end));
  end;

  function ParametersFix(const AOwn: string; const AHead: TRoutineHead; const ATemplate: string): TRuleFix;
  begin
    Result := TRuleFix.Create(cTexts[TTypeRestrictionsOperatorsText.ParamsFromTemplate].Text + ATemplate,
      BothHeads(AOwn, AHead,
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
        Index := NameToken(mTokens, AOne.Header);
        if Index >= 0 then
        begin
          Result := [TRuleEdit.Create(TTextRange.Create(mTokens[Index].EndPos, mTokens[Index].EndPos), ATemplate)];
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
    for mBody in ImplementationHeads(AContext.Text, mTokens, AContext.Tree.Root, AOwn + '.' + AHead.Header.Name,
      AHead) do
    begin
      mName := NameToken(mTokens, mBody.Header);
      if mName >= 0 then
      begin
        Report(TokenRange(mTokens[mName]), cTexts[TTypeRestrictionsOperatorsText.NoDeclaration].Fmt([AOwn,
          AHead.Header.Name]), nil);
      end;
    end;
  end;

  /// <summary>Liest den Kopf AHeader als class operator mit Namen und eigenem Typ; False bei anderen Köpfen.
  /// </summary>
  function ReadSite(AHeader: TSyntaxNode; out ASite: TOperatorSite): Boolean;
  var
    mIndex: Integer;
  begin
    ASite := Default(TOperatorSite);
    ASite.Head := TRoutineHead.Read(mTokens, AHeader);
    ASite.Own := ContainerName(AHeader);
    ASite.Name := AHeader.Name;
    mIndex := NameToken(mTokens, AHeader);
    Result := ASite.Head.IsClass and (ASite.Head.Keyword = 'operator');
    Result := Result and (ASite.Own <> '') and (ASite.Name <> '') and (mIndex >= 0) and IsValidIdent(ASite.Name);
    if Result then
    begin
      ASite.Range := TokenRange(mTokens[mIndex]);
      ASite.Shape := OperatorShape(ASite.Name);
      ASite.OwnNames := mTypes.SameNames(ASite.Own);
      ASite.ParamTypes := ParameterTypeNames(ASite.Head);
    end;
  end;

  procedure ReportUnknown(const ASite: TOperatorSite);
  var
    mClosest: string;
  begin
    mClosest := TTextFuzzy.Closest(ASite.Name, KnownOperators);
    if mClosest <> '' then
    begin
      Report(ASite.Range, cTexts[TTypeRestrictionsOperatorsText.UnknownMeant].Fmt([ASite.Name,
        mClosest]), [RenameFix(ASite.Own, ASite.Head, mClosest)]);
    end
    else
    begin
      Report(ASite.Range, cTexts[TTypeRestrictionsOperatorsText.Unknown].Fmt([ASite.Name]), nil);
    end;
    ReportBodies(ASite.Own, ASite.Head);
  end;

  /// <summary>Parameterzahl (E2517); True nach einer Meldung.</summary>
  function CheckCount(const ASite: TOperatorSite): Boolean;
  var
    mExpected: Integer;
    mTemplate: string;
    mFixes: TArray<TRuleFix>;
  begin
    mExpected := ExpectedParameterCount(ASite.Shape);
    Result := ASite.Head.ParameterCount <> mExpected;
    if not Result then
    begin
      Exit;
    end;
    mTemplate := ParameterTemplate(ASite.Shape, ASite.Own);
    mFixes := nil;
    if mTemplate <> '' then
    begin
      mFixes := [ParametersFix(ASite.Own, ASite.Head, mTemplate)];
    end;
    Report(ASite.Range, cTexts[TTypeRestrictionsOperatorsText.ParamCount].Fmt([ASite.Name, mExpected]),
      mFixes);
  end;

  /// <summary>Eigener Typ in den Parametern (E2518) bzw. in Parameter oder Ergebnis (E2521); True nach einer
  /// Meldung.</summary>
  function CheckOwnType(const ASite: TOperatorSite): Boolean;
  var
    mOther: string;
    mHasOwn, mCertain: Boolean;
  begin
    mHasOwn := False;
    mCertain := True;
    for mOther in ASite.ParamTypes do
    begin
      mHasOwn := mHasOwn or MatchText(BareTypeName(mOther), ASite.OwnNames);
      mCertain := mCertain and mTypes.CertainlyOther(mOther, ASite.OwnNames);
    end;
    if (ASite.Shape = TOperatorShape.Conversion) and (ASite.Head.ResultType <> nil) then
    begin
      mHasOwn := mHasOwn or MatchText(BareTypeName(ASite.Head.ResultType.Name), ASite.OwnNames);
      mCertain := mCertain and mTypes.CertainlyOther(ASite.Head.ResultType.Name, ASite.OwnNames);
    end;
    Result := not mHasOwn and mCertain and (ASite.Shape <> TOperatorShape.Managed);
    if not Result then
    begin
      Exit;
    end;
    if ASite.Shape = TOperatorShape.Conversion then
    begin
      Report(ASite.Range, cTexts[TTypeRestrictionsOperatorsText.ParamOrResult].Fmt([ASite.Name,
        ASite.Own]), nil);
    end
    else
    begin
      Report(ASite.Range, cTexts[TTypeRestrictionsOperatorsText.InOneParam].Fmt([ASite.Name, ASite.Own]), nil);
    end;
  end;

  /// <summary>Liefert der Kopf sicher einen anderen Typ als den des ersten Parameters?</summary>
  function ResultDiffers(const ASite: TOperatorSite): Boolean;
  var
    mResult, mFirst: string;
  begin
    Result := (ASite.Head.ResultType <> nil) and (ASite.ParamTypes[0] <> '');
    if not Result then
    begin
      Exit;
    end;
    mResult := ASite.Head.ResultType.Name;
    mFirst := ASite.ParamTypes[0];
    Result := not SameText(BareTypeName(mResult), BareTypeName(mFirst));
    Result := Result and mTypes.CertainlyOther(mResult, mTypes.SameNames(mFirst)) and
      mTypes.CertainlyOther(mFirst, mTypes.SameNames(mResult));
  end;

  /// <summary>Inc und Dec liefern den Typ des Parameters (E2519); True nach einer Meldung.</summary>
  function CheckIncDec(const ASite: TOperatorSite): Boolean;
  begin
    // Vergleiche mit anderem Ergebnis als Boolean übersetzt dcc (Spring4D Persistence.Criteria liefert
    // ICriterion; OP1-OP5, #1328); die Prüfung auf E2520 ist entfallen.
    Result := MatchText(ASite.Name, ['Inc', 'Dec']) and ResultDiffers(ASite);
    if Result then
    begin
      Report(ASite.Range, cTexts[TTypeRestrictionsOperatorsText.SameType].Fmt(
        [ASite.Name, ASite.ParamTypes[0]]), [ResultFix(ASite.Own, ASite.Head, ASite.ParamTypes[0],
        ASite.ParamTypes[0] + cTexts[TTypeRestrictionsOperatorsText.AsResult].Text)]);
    end;
  end;

  /// <summary>Assign eines Managed Records: erster Parameter var; Delphi 13 meldet E2617 (Cm.E2464, #1380).
  /// </summary>
  procedure CheckAssign(const ASite: TOperatorSite);
  begin
    if (ASite.Shape = TOperatorShape.Assign) and (ASite.Head.Parameters <> nil) and
      (ASite.Head.Parameters[0].Modifier <> TParameterModifier.VarParam) then
    begin
      Report(ASite.Range, cTexts[TTypeRestrictionsOperatorsText.AssignVar].Text, [VarFix(ASite.Own, ASite.Head)]);
    end;
  end;

  procedure CheckOperator(AHeader: TSyntaxNode);
  var
    mSite: TOperatorSite;
  begin
    if not ReadSite(AHeader, mSite) then
    begin
      Exit;
    end;
    // Klassenoperatoren gibt es unter Win32 und Win64 nur in Records: In einer Klasse meldet syntax die
    // Deklaration (E2123, #1382), hier bleibt nur der Rumpf, der zu nichts passt (Cm.E2522, #1380).
    if AHeader.Parent.Kind = TSyntaxKind.ClassType then
    begin
      ReportBodies(mSite.Own, mSite.Head);
    end
    else if mSite.Shape = TOperatorShape.Unknown then
    begin
      ReportUnknown(mSite);
    end
    else if mSite.Shape <> TOperatorShape.Tolerated then
    begin
      if CheckCount(mSite) or CheckOwnType(mSite) or CheckIncDec(mSite) then
      begin
        Exit;
      end;
      CheckAssign(mSite);
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'operator') then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mTypes := TFileTypes.Collect(AContext.Tree.Root);
  mHeaders := TList<TSyntaxNode>.Create;
  try
    AContext.Tree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := ANode.Kind <> TSyntaxKind.RoutineDecl;
        // Operatoren gibt es nur in Records; Köpfe in Klassen nur für die Rümpfe (E2037, #1380).
        if (ANode.Kind = TSyntaxKind.RoutineHeader) and (ANode.Parent <> nil) and
          (ANode.Parent.Kind in [TSyntaxKind.RecordType, TSyntaxKind.ClassType]) then
        begin
          mHeaders.Add(ANode);
        end;
      end);
    for mHeader in mHeaders do
    begin
      CheckOperator(mHeader);
    end;
  finally
    mHeaders.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.TypeRestrictions.Operators', cTexts);

end.
