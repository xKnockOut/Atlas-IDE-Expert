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
    procedure OverrideGoesToEditing;
    [Test]
    procedure CreateAccessorGoesToEditing;
    [Test]
    procedure NothingToDoGivesFalse;
  end;

implementation

uses
  Atlas.Common.CodeActions.Contract,
  Atlas.Common.CodeActions.Contract.Classes,
  Atlas.Common.Rules.Contract.Refactorings,
  Atlas.Common.Editing.Providers.ClassActions,
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

function Refactorings: TRuleRefactorings;
begin
  Result := TRuleRefactoringsAdapters.Create(TEditingClassActionsProvider.New);
end;

{ TRuleRefactoringsAdapterTests }

procedure TRuleRefactoringsAdapterTests.WithoutClassActionsNoEntry;
begin
  Assert.IsNull(TRuleRefactoringsAdapters.Create(nil).Classes);
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
