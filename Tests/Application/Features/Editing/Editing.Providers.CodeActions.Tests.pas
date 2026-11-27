unit Editing.Providers.CodeActions.Tests;

// Tests für die Code-Aktionen, die Editing dem Sprachserver anbietet: Schalter aus refactoring, uses-Aktionen nur
// mit Umfeld, uses aufräumen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TEditingCodeActionsProviderTests = class
  public
    [Test]
    procedure StructureFollowsClassActionsSwitch;
    [Test]
    procedure UsesActionsNeedContext;
    [Test]
    procedure OrganizeImportsRemovesDuplicates;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.CodeActions.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Semantics.Contract,
  Editing.Contract.CodeActions,
  Editing.Composition;

const
  cLB = #13#10;
  cClassText =
    'unit Haupt;' + cLB +
    'interface' + cLB +
    'type' + cLB +
    '  TKunde = class' + cLB +
    '  public' + cLB +
    '    property Name: string;' + cLB +
    '  end;' + cLB +
    'implementation' + cLB +
    'end.';
  cUsesText =
    'unit Haupt;' + cLB +
    'interface' + cLB +
    'uses' + cLB +
    '  Vcl.Grids, Vcl.Dialogs;' + cLB +
    'implementation' + cLB +
    'end.';
  cDuplicateText =
    'unit Haupt;' + cLB +
    'interface' + cLB +
    'uses' + cLB +
    '  System.SysUtils, System.SysUtils;' + cLB +
    'implementation' + cLB +
    'end.';

function Titles(const AActions: TArray<TCodeAction>): string;
var
  mAction: TCodeAction;
begin
  Result := '';
  for mAction in AActions do
  begin
    Result := Result + mAction.Title + '|';
  end;
end;

function SiteAt(const AText: string; ATree: TSyntaxTree; ALine: Integer): TCodeActionSite;
begin
  Result := Default(TCodeActionSite);
  Result.Uri := 'file:///C:/P/Haupt.pas';
  Result.Text := AText;
  Result.Tree := TSyntaxTree.HandleOf(ATree);
  Result.Range := TTextRange.Create(TTextPosition.Create(ALine, 0), TTextPosition.Create(ALine, 0));
  Result.Style := TFormatStyle.Default;
  Result.Refactoring := TRefactoringSettings.Default;
  Result.WantsEditing := True;
end;

{ TEditingCodeActionsProviderTests }

procedure TEditingCodeActionsProviderTests.StructureFollowsClassActionsSwitch;
var
  mActions: IEditingCodeActions;
  mTree: TSyntaxTree;
  mSite: TCodeActionSite;
begin
  mActions := TEditingComposition.CodeActions(Default(TEditingCodeActionSettings));
  mTree := TSyntaxTreeCache.Parse(cClassText);
  try
    mSite := SiteAt(cClassText, mTree, 5);
    Assert.IsTrue(Pos('Getter, Setter und Feld für Name erzeugen|', Titles(mActions.Structure(mSite))) > 0);
    mSite.Refactoring.ClassActions := False;
    Assert.AreEqual(0, Pos('Getter, Setter', Titles(mActions.Structure(mSite))));
    mSite := Default(TCodeActionSite);
  finally
    mTree.Free;
  end;
end;

procedure TEditingCodeActionsProviderTests.UsesActionsNeedContext;
var
  mSettings: TEditingCodeActionSettings;
  mTree: TSyntaxTree;
  mSite: TCodeActionSite;
begin
  mTree := TSyntaxTreeCache.Parse(cUsesText);
  try
    mSite := SiteAt(cUsesText, mTree, 3);
    // Cursor auf Vcl.Grids.
    mSite.Range := TTextRange.Create(TTextPosition.Create(3, 4), TTextPosition.Create(3, 4));
    Assert.AreEqual(0, Integer(Length(TEditingComposition.CodeActions(Default(TEditingCodeActionSettings))
      .UsesActions(mSite))), 'ohne Umfeld');
    mSettings := Default(TEditingCodeActionSettings);
    mSettings.UsesContextFor :=
      function(const AUri: string; out AContext: TUsesContext): Boolean
      begin
        AContext := Default(TUsesContext);
        AContext.Info :=
          function(const AUnitName: string): TUsesUnitInfo
          begin
            Result := Default(TUsesUnitInfo);
            // Vcl.Dialogs kennt der Index nicht.
            Result.Known := not SameText(AUnitName, 'Vcl.Dialogs');
          end;
        Result := True;
      end;
    Assert.IsTrue(Pos('Vcl.Grids entfernen|', Titles(TEditingComposition.CodeActions(mSettings)
      .UsesActions(mSite))) > 0);
    mSite := Default(TCodeActionSite);
  finally
    mTree.Free;
  end;
end;

procedure TEditingCodeActionsProviderTests.OrganizeImportsRemovesDuplicates;
var
  mActions: IEditingCodeActions;
  mTree: TSyntaxTree;
  mSite: TCodeActionSite;
  mAction: TCodeAction;
begin
  mActions := TEditingComposition.CodeActions(Default(TEditingCodeActionSettings));
  mTree := TSyntaxTreeCache.Parse(cDuplicateText);
  try
    mSite := SiteAt(cDuplicateText, mTree, 0);
    Assert.IsTrue(mActions.OrganizeImports(mSite, mAction));
    Assert.AreEqual(cOrganizeImportsKind, mAction.Kind);
    Assert.IsTrue(Length(mAction.Edits) > 0);
    mSite := Default(TCodeActionSite);
    mAction := Default(TCodeAction);
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TEditingCodeActionsProviderTests);

end.
