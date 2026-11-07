unit Atlas.UI.Todos.Tests;

// TODO-Liste (#68), Oberfläche: Filterdialog mit Vorschlägen aus der letzten
// Liste, freiem Text, „Erledigte zeigen“, Zurücksetzen, Enter und Esc.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  [Category('Atlas.IDE.Bookmarks')]
  TAtlasTodoFilterDialogTests = class
  private
    FLanguage: TAtlasLanguage;
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ShowsChoicesAndCurrentFilter;
    [Test]
    procedure FilterFromFieldsTrimmed;
    [Test]
    procedure ResetClearsAllFields;
  end;

implementation

uses
  System.SysUtils,
  System.UITypes,
  Atlas.Core.Projects.Todos,
  Atlas.UI.Todos.Dialog;

function SampleChoices: TAtlasTodoChoices;
begin
  Result := Default(TAtlasTodoChoices);
  Result.Categories := ['Export', 'GUI'];
  Result.Owners := ['Anna', 'Marco'];
  Result.Units := ['Kasse', 'Rechnung'];
  Result.Keywords := ['FIXME', 'TODO'];
end;

{ TAtlasTodoFilterDialogTests }

procedure TAtlasTodoFilterDialogTests.WarmUpFirstUse;
begin
  Setup;
  try
    ShowsChoicesAndCurrentFilter;
  finally
    TearDown;
  end;
end;

procedure TAtlasTodoFilterDialogTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasTodoFilterDialogTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
end;

procedure TAtlasTodoFilterDialogTests.ShowsChoicesAndCurrentFilter;
var
  mDialog: TAtlasTodoFilterDialog;
  mFilter: TAtlasTodoFilter;
begin
  mFilter := Default(TAtlasTodoFilter);
  mFilter.Owner := 'Marco';
  mFilter.IncludeDone := True;
  mDialog := TAtlasTodoFilterDialog.CreateDialog(nil, SampleChoices, mFilter);
  try
    Assert.AreEqual('TODOs filtern', mDialog.Caption);
    Assert.AreEqual(2, Integer(mDialog.CategoryBox.Items.Count));
    Assert.AreEqual('GUI', mDialog.CategoryBox.Items[1]);
    Assert.AreEqual('Rechnung', mDialog.UnitBox.Items[1]);
    Assert.AreEqual('FIXME', mDialog.KeywordBox.Items[0]);
    Assert.AreEqual('', mDialog.CategoryBox.Text);
    Assert.AreEqual('Marco', mDialog.OwnerBox.Text, 'letzter Filter');
    Assert.IsTrue(mDialog.IncludeDoneCheck.Checked);
    Assert.IsTrue(mDialog.OkButton.Default, 'Enter zeigt an');
    Assert.IsTrue(mDialog.CancelButton.Cancel, 'Esc bricht ab');
    Assert.AreEqual('Anzeigen', mDialog.OkButton.Caption);
    mDialog.OkButton.Click;
    Assert.AreEqual(Integer(mrOk), Integer(mDialog.ModalResult));
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasTodoFilterDialogTests.FilterFromFieldsTrimmed;
var
  mDialog: TAtlasTodoFilterDialog;
  mFilter: TAtlasTodoFilter;
begin
  mDialog := TAtlasTodoFilterDialog.CreateDialog(nil, SampleChoices, Default(TAtlasTodoFilter));
  try
    mDialog.CategoryBox.Text := ' GUI ';
    // Freier Text: auch Werte, die nicht in den Vorschlägen stehen.
    mDialog.UnitBox.Text := 'Lager';
    mDialog.KeywordBox.Text := 'HACK';
    mFilter := mDialog.Filter;
    Assert.AreEqual('GUI', mFilter.Category);
    Assert.AreEqual('', mFilter.Owner);
    Assert.AreEqual('Lager', mFilter.UnitName);
    Assert.AreEqual('HACK', mFilter.Keyword);
    Assert.IsFalse(mFilter.IncludeDone);
    mDialog.CancelButton.Click;
    Assert.AreEqual(Integer(mrCancel), Integer(mDialog.ModalResult));
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasTodoFilterDialogTests.ResetClearsAllFields;
var
  mDialog: TAtlasTodoFilterDialog;
  mFilter: TAtlasTodoFilter;
begin
  mFilter := Default(TAtlasTodoFilter);
  mFilter.Category := 'GUI';
  mFilter.Owner := 'Anna';
  mFilter.UnitName := 'Kasse';
  mFilter.Keyword := 'TODO';
  mFilter.IncludeDone := True;
  mDialog := TAtlasTodoFilterDialog.CreateDialog(nil, SampleChoices, mFilter);
  try
    mDialog.ResetButton.Click;
    Assert.IsTrue(mDialog.Filter.IsEmpty);
    Assert.AreEqual(Integer(mrNone), Integer(mDialog.ModalResult), 'Zurücksetzen schließt nicht');
  finally
    mDialog.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTodoFilterDialogTests);

end.
