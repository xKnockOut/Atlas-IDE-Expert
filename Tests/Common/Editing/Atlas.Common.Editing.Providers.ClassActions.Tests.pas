unit Atlas.Common.Editing.Providers.ClassActions.Tests;

// Tests für die Klassen-Aktionen, die Editing über seinen Contract anbietet: gleiche Ergebnisse wie
// TClassActions mit demselben Kontext.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TEditingClassActionsProviderTests = class
  public
    [Test]
    procedure OverrideLikeClassActions;
    [Test]
    procedure RequestLineIsUsed;
  end;

implementation

uses
  Atlas.Common.CodeActions.Contract,
  Atlas.Common.CodeActions.Contract.Classes,
  Atlas.Common.Editing.Contract.ClassActions,
  Atlas.Common.Editing.ClassActions,
  Atlas.Common.Editing.Providers.ClassActions;

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

{ TEditingClassActionsProviderTests }

procedure TEditingClassActionsProviderTests.OverrideLikeClassActions;
var
  mProvider: IEditingClassActions;
  mExpected, mAction: TCodeAction;
  mIndex: Integer;
begin
  mProvider := TEditingClassActionsProvider.New;
  Assert.IsTrue(TClassActions.OverrideMethod(cSource, 8, 'Zeichne', TClassActionContext.Default, mExpected));
  Assert.IsTrue(mProvider.OverrideMethod(TClassEditRequest.Create(cSource, 8), 'Zeichne', mAction));
  Assert.AreEqual(mExpected.Title, mAction.Title);
  Assert.AreEqual(Integer(Length(mExpected.Edits)), Integer(Length(mAction.Edits)));
  for mIndex := 0 to High(mAction.Edits) do
  begin
    Assert.AreEqual(mExpected.Edits[mIndex].NewText, mAction.Edits[mIndex].NewText);
  end;
end;

procedure TEditingClassActionsProviderTests.RequestLineIsUsed;
var
  mRequest: TClassEditRequest;
  mAction: TCodeAction;
begin
  mRequest := TClassEditRequest.Create(cSource, 1);
  Assert.IsFalse(TEditingClassActionsProvider.New.OverrideMethod(mRequest, 'Zeichne', mAction));
  Assert.IsTrue(TEditingClassActionsProvider.New.OverrideMethod(mRequest.At(8), 'Zeichne', mAction));
  Assert.AreEqual(1, mRequest.Line);
end;

initialization
  TDUnitX.RegisterTestFixture(TEditingClassActionsProviderTests);

end.
