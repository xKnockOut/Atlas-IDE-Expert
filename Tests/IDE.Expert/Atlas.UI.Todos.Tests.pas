unit Atlas.UI.Todos.Tests;

// TODO-Liste (#68), Oberfläche: Filterdialog mit Vorschlägen aus der letzten
// Liste, freiem Text, „Erledigte zeigen“, Zurücksetzen, Enter und Esc.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  TAtlasTodoFilterDialogTests = class
  private
    FLanguage: TAtlasLanguage;
  public
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
  Dialog: TAtlasTodoFilterDialog;
  Filter: TAtlasTodoFilter;
begin
  Filter := Default(TAtlasTodoFilter);
  Filter.Owner := 'Marco';
  Filter.IncludeDone := True;
  Dialog := TAtlasTodoFilterDialog.CreateDialog(nil, SampleChoices, Filter);
  try
    Assert.AreEqual('TODOs filtern', Dialog.Caption);
    Assert.AreEqual(2, Dialog.CategoryBox.Items.Count);
    Assert.AreEqual('GUI', Dialog.CategoryBox.Items[1]);
    Assert.AreEqual('Rechnung', Dialog.UnitBox.Items[1]);
    Assert.AreEqual('FIXME', Dialog.KeywordBox.Items[0]);
    Assert.AreEqual('', Dialog.CategoryBox.Text);
    Assert.AreEqual('Marco', Dialog.OwnerBox.Text, 'letzter Filter');
    Assert.IsTrue(Dialog.IncludeDoneCheck.Checked);
    Assert.IsTrue(Dialog.OkButton.Default, 'Enter zeigt an');
    Assert.IsTrue(Dialog.CancelButton.Cancel, 'Esc bricht ab');
    Assert.AreEqual('Anzeigen', Dialog.OkButton.Caption);
    Dialog.OkButton.Click;
    Assert.AreEqual(Integer(mrOk), Integer(Dialog.ModalResult));
  finally
    Dialog.Free;
  end;
end;

procedure TAtlasTodoFilterDialogTests.FilterFromFieldsTrimmed;
var
  Dialog: TAtlasTodoFilterDialog;
  Filter: TAtlasTodoFilter;
begin
  Dialog := TAtlasTodoFilterDialog.CreateDialog(nil, SampleChoices, Default(TAtlasTodoFilter));
  try
    Dialog.CategoryBox.Text := ' GUI ';
    // Freier Text: auch Werte, die nicht in den Vorschlägen stehen.
    Dialog.UnitBox.Text := 'Lager';
    Dialog.KeywordBox.Text := 'HACK';
    Filter := Dialog.Filter;
    Assert.AreEqual('GUI', Filter.Category);
    Assert.AreEqual('', Filter.Owner);
    Assert.AreEqual('Lager', Filter.UnitName);
    Assert.AreEqual('HACK', Filter.Keyword);
    Assert.IsFalse(Filter.IncludeDone);
    Dialog.CancelButton.Click;
    Assert.AreEqual(Integer(mrCancel), Integer(Dialog.ModalResult));
  finally
    Dialog.Free;
  end;
end;

procedure TAtlasTodoFilterDialogTests.ResetClearsAllFields;
var
  Dialog: TAtlasTodoFilterDialog;
  Filter: TAtlasTodoFilter;
begin
  Filter := Default(TAtlasTodoFilter);
  Filter.Category := 'GUI';
  Filter.Owner := 'Anna';
  Filter.UnitName := 'Kasse';
  Filter.Keyword := 'TODO';
  Filter.IncludeDone := True;
  Dialog := TAtlasTodoFilterDialog.CreateDialog(nil, SampleChoices, Filter);
  try
    Dialog.ResetButton.Click;
    Assert.IsTrue(Dialog.Filter.IsEmpty);
    Assert.AreEqual(Integer(mrNone), Integer(Dialog.ModalResult), 'Zurücksetzen schließt nicht');
  finally
    Dialog.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTodoFilterDialogTests);

end.
