unit Atlas.Common.Editing.CodeActions.Tests;

// Tests für Code-Aktionen ohne Protokoll (#147): uses aufräumen, Zuweisungen umkehren.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCodeActionTests = class
  public
    [Test]
    procedure OrganizeImportsAsSourceAction;
    [Test]
    procedure SwapAssignmentsIsRewrite;
  end;

implementation

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.CodeActions.Contract,
  Atlas.Common.Editing.CodeActions;

const
  cLB = #13#10;

{ TCodeActionTests }

procedure TCodeActionTests.OrganizeImportsAsSourceAction;
var
  mAction: TCodeAction;
begin
  Assert.IsTrue(TCodeActions.OrganizeImports('unit A;' + cLB + 'interface' + cLB + 'uses B, B;' + cLB +
    'implementation' + cLB + 'end.', False, mAction));
  Assert.AreEqual(cOrganizeImportsKind, mAction.Kind);
  Assert.AreEqual('B', mAction.Edits[0].NewText);
  Assert.IsFalse(TCodeActions.OrganizeImports('unit A;' + cLB + 'interface' + cLB + 'uses B, C;' + cLB +
    'implementation' + cLB + 'end.', True, mAction));
end;

procedure TCodeActionTests.SwapAssignmentsIsRewrite;
var
  mAction: TCodeAction;
begin
  Assert.IsTrue(TCodeActions.SwapAssignments('  A := B;', TTextRange.Create(0, 0, 0, 0), nil, mAction));
  Assert.AreEqual(cRewriteKind, mAction.Kind);
  Assert.AreEqual('  B := A;', mAction.Edits[0].NewText);
  Assert.IsFalse(TCodeActions.SwapAssignments('  A := F(B);', TTextRange.Create(0, 0, 0, 0), nil, mAction));
end;

initialization
  TDUnitX.RegisterTestFixture(TCodeActionTests);

end.
