unit Adapters.Rules.Refactorings.Tests;

// Tests für den Host-Adapter, der den Prüfregeln die Klassen-Aktionen von Editing als Korrektur gibt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRuleRefactoringsAdapterTests = class
  public
    [Test]
    procedure WithoutClassActionsNoEntry;
    [Test]
    procedure WithoutExtractNoEntry;
    [Test]
    procedure ConstantGoesToEditing;
    [Test]
    procedure MethodWithoutSelfGoesToEditing;
    [Test]
    procedure OverrideGoesToEditing;
    [Test]
    procedure CreateAccessorGoesToEditing;
    [Test]
    procedure NothingToDoGivesFalse;
  end;

implementation

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.CodeActions.Contract,
  Atlas.Common.CodeActions.Contract.Classes,
  Atlas.Common.Rules.Contract.Refactorings,
  Atlas.Common.Editing.Composition,
  Atlas.Tests.TextEdits,
  Adapters.Rules.Refactorings;

const
  // Zeile 8: Kopf von TKind, Zeile 10: Eigenschaft ohne Feld.
  cSource =
    'unit Klassen;'#13#10 +
    ''#13#10 +
    'interface'#13#10 +
    ''#13#10 +
    'type'#13#10 +
    '  TBasis = class'#13#10 +
    '    procedure Zeichne; virtual;'#13#10 +
    '  end;'#13#10 +
    '  TKind = class(TBasis)'#13#10 +
    '  public'#13#10 +
    '    property Name: string read FName;'#13#10 +
    '  end;'#13#10 +
    ''#13#10 +
    'implementation'#13#10 +
    ''#13#10 +
    'procedure TBasis.Zeichne;'#13#10 +
    'begin'#13#10 +
    'end;'#13#10 +
    ''#13#10 +
    'end.'#13#10;

  // Zeile 4: Literal 42 ab Spalte 10.
  cCall =
    'unit U;'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'begin'#13#10 +
    '  Writeln(42);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;

  // Zeile 7: Kopf von THilfe.Doppelt, braucht Self nicht.
  cHelper =
    'unit U;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  THilfe = class'#13#10 +
    '    function Doppelt(A: Integer): Integer;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'function THilfe.Doppelt(A: Integer): Integer;'#13#10 +
    'begin'#13#10 +
    '  Result := A * 2;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;

function Refactorings: TRuleRefactorings;
begin
  Result := TRuleRefactoringsAdapters.Create(TEditingComposition.ClassActions, TEditingComposition.ExtractFixes,
    TEditingComposition.MethodsWithoutSelf);
end;

{ TRuleRefactoringsAdapterTests }

procedure TRuleRefactoringsAdapterTests.WithoutClassActionsNoEntry;
begin
  Assert.IsNull(TRuleRefactoringsAdapters.Create(nil, TEditingComposition.ExtractFixes, nil).Classes);
end;

procedure TRuleRefactoringsAdapterTests.WithoutExtractNoEntry;
begin
  Assert.IsNull(TRuleRefactoringsAdapters.Create(TEditingComposition.ClassActions, nil, nil).Extract);
end;

procedure TRuleRefactoringsAdapterTests.ConstantGoesToEditing;
var
  mAction: TCodeAction;
begin
  Assert.IsTrue(Refactorings.Extract.ConstantExtraction(cCall, Default(TPascalNamePrefixes)).Run(
    TTextRange.Create(4, 10, 4, 12), mAction));
  Assert.IsTrue(Pos('= 42;', TTestEdits.Apply(cCall, mAction.Edits)) > 0);
end;

procedure TRuleRefactoringsAdapterTests.MethodWithoutSelfGoesToEditing;
var
  mScan: TRuleMethodScan;
  mFound: TArray<TRuleMethodWithoutSelf>;
begin
  Assert.IsNull(TRuleRefactoringsAdapters.Create(nil, nil, nil).Methods);
  mScan := Default(TRuleMethodScan);
  mScan.FileName := 'U.pas';
  mScan.Text := cHelper;
  mScan.WithStatic := True;
  mScan.Style := TFormatStyle.Default;
  mFound := Refactorings.Methods.WithoutSelf(mScan);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('THilfe', mFound[0].ClassName);
  Assert.AreEqual('Doppelt', mFound[0].Name);
  Assert.AreEqual(7, mFound[0].NamePosition.Line);
  Assert.IsTrue(mFound[0].HasFix);
  Assert.IsTrue(Length(mFound[0].Fix.Edits) > 0);
end;

procedure TRuleRefactoringsAdapterTests.OverrideGoesToEditing;
var
  mAction: TCodeAction;
  mText: string;
begin
  Assert.IsTrue(Refactorings.Classes.OverrideMethod(TClassEditRequest.Create(cSource, 8), 'Zeichne', mAction));
  mText := TTestEdits.Apply(cSource, mAction.Edits);
  Assert.IsTrue(Pos('procedure Zeichne; override;', mText) > 0, mText);
  Assert.IsTrue(Pos('procedure TKind.Zeichne;', mText) > 0, mText);
end;

procedure TRuleRefactoringsAdapterTests.CreateAccessorGoesToEditing;
var
  mPlan: TAccessorPlan;
  mAction: TCodeAction;
  mText: string;
begin
  mPlan := Default(TAccessorPlan);
  mPlan.Kind := TAccessorKind.Field;
  mPlan.PropertyName := 'Name';
  mPlan.PropertyType := 'string';
  mPlan.MethodSection := 'private';
  Assert.IsTrue(Refactorings.Classes.CreateAccessor(TClassEditRequest.Create(cSource, 10), mPlan, mAction));
  mText := TTestEdits.Apply(cSource, mAction.Edits);
  Assert.IsTrue(Pos('FName: string;', mText) > 0, mText);
end;

procedure TRuleRefactoringsAdapterTests.NothingToDoGivesFalse;
var
  mAction: TCodeAction;
begin
  // Zeile 1 liegt in keiner Klasse.
  Assert.IsFalse(Refactorings.Classes.OverrideMethod(TClassEditRequest.Create(cSource, 1), 'Zeichne', mAction));
  Assert.IsFalse(Refactorings.Classes.ImplementInterface(TClassEditRequest.Create(cSource, 8), 'IUnbekannt',
    mAction));
end;

initialization
  TDUnitX.RegisterTestFixture(TRuleRefactoringsAdapterTests);

end.
