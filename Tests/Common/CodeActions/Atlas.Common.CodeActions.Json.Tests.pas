unit Atlas.Common.CodeActions.Json.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCodeActionsJsonTests = class
  public
    /// <summary>#663: Vorschau als data.preview, Hinweis statt Aktion als disabled.reason.</summary>
    [Test]
    procedure ActionJsonCarriesPreviewAndDisabled;
    /// <summary>#2054: abwählbare Teile als data.choices, je Edit die nötigen Teile in data.editChoices.</summary>
    [Test]
    procedure ActionJsonCarriesChoices;
    /// <summary>WorkspaceEdit mit den Änderungen einer Datei unter changes.</summary>
    [Test]
    procedure WorkspaceEditListsChanges;
  end;

implementation

uses
  System.Generics.Collections, // Inline TJSONArray.GetValue (H2443)
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.CodeActions.Contract,
  Atlas.Common.CodeActions.Json;

const
  cFileName = 'C:\P\Haupt.pas';

{ TCodeActionsJsonTests }

procedure TCodeActionsJsonTests.ActionJsonCarriesPreviewAndDisabled;
var
  mAction: TCodeAction;
  mJson: TJSONObject;
begin
  mAction := Default(TCodeAction);
  mAction.Title := 'Umwandeln';
  mAction.Kind := cRewriteKind;
  mAction.Preview := 'Neue Signatur: procedure A;';
  mJson := TCodeActionsJson.ActionToJson(TDocumentUris.FromPath(cFileName), mAction);
  try
    Assert.AreEqual('Neue Signatur: procedure A;', mJson.GetValue<string>('data.preview'));
    Assert.IsNull(mJson.GetValue('disabled'));
    Assert.IsNull(TJSONObject(mJson.GetValue('data')).GetValue('tag'));
  finally
    mJson.Free;
  end;
  mAction.Preview := '';
  mAction.Disabled := 'erst die andere umwandeln';
  mJson := TCodeActionsJson.ActionToJson(TDocumentUris.FromPath(cFileName), mAction);
  try
    Assert.AreEqual('erst die andere umwandeln', mJson.GetValue<string>('disabled.reason'));
    Assert.IsNull(mJson.GetValue('data'));
  finally
    mJson.Free;
  end;
end;

procedure TCodeActionsJsonTests.ActionJsonCarriesChoices;
var
  mAction: TCodeAction;
  mJson: TJSONObject;
  mChoices, mEditChoices: TJSONArray;
begin
  mAction := Default(TCodeAction);
  mAction.Title := 'Methode extrahieren und gleiche Stelle ersetzen';
  mAction.Kind := 'refactor.extract';
  mAction.Edits := [TTextEdit.Create(TTextRange.Create(1, 0, 1, 5), 'A;'),
    TTextEdit.Create(TTextRange.Create(3, 2, 4, 0), 'B;')];
  mAction.Choices := [TCodeActionChoice.Create('Zeile 4 in TFoo.Bar', TTextRange.Create(3, 2, 4, 0))];
  SetLength(mAction.EditChoices, 2);
  mAction.EditChoices[1] := [0];
  mJson := TCodeActionsJson.ActionToJson(TDocumentUris.FromPath(cFileName), mAction);
  try
    mChoices := mJson.GetValue<TJSONArray>('data.choices');
    Assert.AreEqual(1, Integer(mChoices.Count));
    Assert.AreEqual('Zeile 4 in TFoo.Bar', mChoices.Items[0].GetValue<string>('title'));
    Assert.AreEqual(3, mChoices.Items[0].GetValue<Integer>('range.start.line'));
    mEditChoices := mJson.GetValue<TJSONArray>('data.editChoices');
    Assert.AreEqual(2, Integer(mEditChoices.Count));
    Assert.AreEqual(0, Integer(TJSONArray(mEditChoices.Items[0]).Count));
    Assert.AreEqual('[0]', mEditChoices.Items[1].ToJSON);
  finally
    mJson.Free;
  end;
end;

procedure TCodeActionsJsonTests.WorkspaceEditListsChanges;
var
  mUri: string;
  mJson: TJSONObject;
  mEdits: TJSONArray;
begin
  mUri := TDocumentUris.FromPath(cFileName);
  mJson := TCodeActionsJson.WorkspaceEditJson(mUri, [TTextEdit.Create(TTextRange.Create(2, 0, 2, 3), 'Neu')]);
  try
    mEdits := TJSONObject(mJson.GetValue('changes')).GetValue(mUri) as TJSONArray;
    Assert.AreEqual(1, Integer(mEdits.Count));
    Assert.AreEqual('Neu', mEdits.Items[0].GetValue<string>('newText'));
    Assert.AreEqual(2, mEdits.Items[0].GetValue<Integer>('range.start.line'));
  finally
    mJson.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TCodeActionsJsonTests);

end.
