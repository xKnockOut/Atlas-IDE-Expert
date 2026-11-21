unit Atlas.Common.Rules.Builtin.Testing.TestCases;

// Regel aus Atlas.Common.Rules.Builtin.Testing (#1882); angemeldet wird sie dort:
//   dunitx-testcase-mismatch  [TestCase] passt nicht zur Methode: Die Zahl der Werte weicht von der Zahl der
//                             Parameter ab (DUnitX ruft über RTTI auf, Vorgabewerte zählen nicht), ein Wert passt
//                             nicht zum Typ seines Parameters, oder die Methode hat gar keine Parameter. DUnitX
//                             meldet das erst beim Lauf. Nur in Testunits (uses DUnitX.TestFramework …).
//
// Die Einträge liest Atlas.Common.Testing.TestCases.

interface

uses
  Atlas.Common.Rules.Contract;

const
  cDUnitXTestCaseMismatchRuleId = 'dunitx-testcase-mismatch';

type
  TDUnitXTestCaseMismatchRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

implementation

uses
  Atlas.Common.Pascal.SyntaxTree,
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Testing.Classes,
  Atlas.Common.Testing.TestCases,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TTestCaseText = (Title, CountMismatch, NoParameters, ValueMismatch, ValueMismatchEnum);

const
  cTexts: array[TTestCaseText] of TAtlasText = (
    (De: 'TestCase passt nicht zur Methode'; En: 'TestCase does not match the method'),
    (De: '%s hat %d Werte, %s erwartet %d Parameter.'; En: '%s has %d values, %s expects %d parameters.'),
    (De: '%s an %s, die keine Parameter hat: DUnitX kann die Werte nicht übergeben.';
     En: '%s on %s, which has no parameters: DUnitX cannot pass the values.'),
    (De: 'Wert ''%s'' passt nicht zu Parameter %s: %s.'; En: 'Value ''%s'' does not fit parameter %s: %s.'),
    (De: 'Wert ''%s'' passt nicht zu Parameter %s: %s (erlaubt: %s).';
     En: 'Value ''%s'' does not fit parameter %s: %s (allowed: %s).'));

{$SCOPEDENUMS OFF}

{ TDUnitXTestCaseMismatchRule }

function TDUnitXTestCaseMismatchRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cDUnitXTestCaseMismatchRuleId, TRuleSeverity.Warning,
    cTexts[TTestCaseText.Title].Text);
end;

procedure TDUnitXTestCaseMismatchRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mEnums: TArray<string>;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := '[' + Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset) + ']';
  end;

  function Range(ANode: TSyntaxNode): TTextRange;
  begin
    Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
  end;

  procedure CheckValues(const ACase: TDUnitXTestCase; const AParams: TArray<TDUnitXParameter>);
  var
    mIndex: Integer;
    mKind: TDUnitXValueKind;
    mNames: string;
  begin
    for mIndex := 0 to High(AParams) do
    begin
      mNames := TDUnitXTestCases.EnumNames(AParams[mIndex].TypeName, mEnums);
      mKind := TDUnitXTestCases.KindOf(AParams[mIndex].TypeName, mEnums);
      if TDUnitXTestCases.Fits(ACase.Values[mIndex], mKind, mNames) then
      begin
        Continue;
      end;
      if mKind = TDUnitXValueKind.Enum then
      begin
        AReport.Add(Range(ACase.Item), cTexts[TTestCaseText.ValueMismatchEnum].Fmt([ACase.Values[mIndex],
          AParams[mIndex].Name, AParams[mIndex].TypeName, StringReplace(mNames, ',', ', ', [rfReplaceAll])]),
          TRuleConfidence.High, []);
      end
      else
      begin
        AReport.Add(Range(ACase.Item), cTexts[TTestCaseText.ValueMismatch].Fmt([ACase.Values[mIndex],
          AParams[mIndex].Name, AParams[mIndex].TypeName]), TRuleConfidence.High, []);
      end;
    end;
  end;

  procedure CheckMember(const AMember: TDUnitXMember);
  var
    mItem: TSyntaxNode;
    mCase: TDUnitXTestCase;
    mParams: TArray<TDUnitXParameter>;
  begin
    mParams := TDUnitXTestCases.Parameters(AMember.Node);
    for mItem in AMember.Attributes do
    begin
      if not TDUnitXTestCases.Read(mItem, mCase) then
      begin
        Continue;
      end;
      // Mehrdeutige zwei Argumente: Welche DUnitX-Fassung gilt, ist unbekannt; die passende Lesart zählt.
      if mCase.HasOldReading and (Length(mCase.Values) <> Length(mParams)) and
        (Length(mCase.OldValues) = Length(mParams)) then
      begin
        mCase.Values := mCase.OldValues;
      end;
      if mParams = nil then
      begin
        AReport.Add(Range(mItem), cTexts[TTestCaseText.NoParameters].Fmt([NodeText(mItem), AMember.Node.Name]),
          TRuleConfidence.High, []);
      end
      else if Length(mCase.Values) <> Length(mParams) then
      begin
        AReport.Add(Range(mItem), cTexts[TTestCaseText.CountMismatch].Fmt([NodeText(mItem), Length(mCase.Values),
          AMember.Node.Name, Length(mParams)]), TRuleConfidence.High, []);
      end
      else
      begin
        CheckValues(mCase, mParams);
      end;
    end;
  end;

var
  mClass: TDUnitXClass;
  mMember: TDUnitXMember;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'TestCase') or
    not TUsesClauses.IsTestUnit(AContext.Tree.Tokens) then
  begin
    Exit;
  end;
  mEnums := TDUnitXTestCases.Enums(AContext.Tree.Root);
  for mClass in TDUnitXClasses.Collect(AContext.Tree.Root) do
  begin
    for mMember in mClass.Members do
    begin
      if mMember.Node.Kind = TSyntaxKind.RoutineHeader then
      begin
        CheckMember(mMember);
      end;
    end;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Testing.TestCases', cTexts);

end.
