unit Atlas.Common.Lsp.CodeActions.Tests;

// textDocument/codeAction über den Dispatcher (#42): try/finally und die
// Klassen-Aktionen kommen mit, refactoring.tryFinally und
// refactoring.classActions schalten sie ab.

interface

uses
  DUnitX.TestFramework,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Lsp.CodeActions;

type
  [TestFixture]
  TLspCodeActionsTests = class
  private
    FStore: IDocumentStore;
    FActions: TLspCodeActions;
    FDispatcher: TJsonRpcDispatcher;
    FSettings: TRefactoringSettings;
    FId: Integer;
    /// <summary>Titel aller Aktionen in Zeile ALine, mit "|" getrennt.</summary>
    function Titles(const AText: string; ALine: Integer): string;
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure OffersTryFinallyAndClassActions;
    [Test]
    procedure SettingsSwitchThemOff;
    [Test]
    procedure TryFinallyFollowsFormatStyle;
    /// <summary>#621: „X entfernen“ am uses-Eintrag mit data.tag; inaktive Zweige über DefinesFor.</summary>
    [Test]
    procedure UsesEntryActionsCarryTag;
    /// <summary>#663: Vorschau als data.preview, Hinweis statt Aktion als disabled.reason.</summary>
    [Test]
    procedure ActionJsonCarriesPreviewAndDisabled;
    /// <summary>#2054: abwählbare Teile als data.choices, je Edit die nötigen Teile in data.editChoices.</summary>
    [Test]
    procedure ActionJsonCarriesChoices;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Editing.CodeActions;

const
  cLB = #13#10;
  cFileName = 'C:\P\Haupt.pas';
  cText =
    'unit Haupt;' + cLB +
    'interface' + cLB +
    'type' + cLB +
    '  TKunde = class' + cLB +
    '  public' + cLB +
    '    property Name: string;' + cLB +           // 5
    '  end;' + cLB +
    'implementation' + cLB +
    'procedure P;' + cLB +
    'var' + cLB +
    '  L: TList;' + cLB +
    'begin' + cLB +
    '  L := TList.Create;' + cLB +                 // 12
    '  L.Add(nil);' + cLB +
    'end;' + cLB +
    'end.';

procedure TLspCodeActionsTests.WarmUpFirstUse;
begin
  Setup;
  try
    OffersTryFinallyAndClassActions;
  finally
    TearDown;
  end;
end;

procedure TLspCodeActionsTests.Setup;
begin
  FStore := TDocumentStore.Create;
  FSettings := TRefactoringSettings.Default;
  FId := 0;
  FActions := TLspCodeActions.Create(FStore, nil);
  FActions.RefactoringFor :=
    function(const AUri: string): TRefactoringSettings
    begin
      Result := FSettings;
    end;
  FDispatcher := TJsonRpcDispatcher.Create;
  FActions.Attach(FDispatcher);
end;

procedure TLspCodeActionsTests.TearDown;
begin
  FDispatcher.Free;
  FActions.Free;
  FStore := nil;
end;

function TLspCodeActionsTests.Titles(const AText: string; ALine: Integer): string;
var
  mUri: string;
  mRequest, mResponse: TJSONObject;
  mItem: TJSONValue;
begin
  mUri := TDocumentUris.FromPath(cFileName);
  FStore.Close(mUri);
  FStore.Open(mUri, 'delphi', 1, AText);
  Inc(FId);
  mRequest := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":' + IntToStr(FId) +
    ',"method":"textDocument/codeAction","params":{"textDocument":{"uri":"' + mUri.Replace('\', '\\') +
    '"},"range":{"start":{"line":' + IntToStr(ALine) + ',"character":0},"end":{"line":' + IntToStr(ALine) +
    ',"character":0}},"context":{"diagnostics":[]}}}') as TJSONObject;
  try
    mResponse := FDispatcher.DispatchMessage(mRequest);
  finally
    mRequest.Free;
  end;
  Assert.IsNotNull(mResponse);
  try
    Assert.IsTrue(mResponse.GetValue('result') is TJSONArray, mResponse.ToJSON);
    Result := '';
    for mItem in TJSONArray(mResponse.GetValue('result')) do
    begin
      Result := Result + TJSONObject(mItem).GetValue<string>('title') + '|';
    end;
  finally
    mResponse.Free;
  end;
end;

procedure TLspCodeActionsTests.OffersTryFinallyAndClassActions;
var
  mFound: string;
begin
  mFound := Titles(cText, 12);
  Assert.IsTrue(Pos('try/finally mit L.Free ergänzen|', mFound) > 0, mFound);
  mFound := Titles(cText, 5);
  Assert.IsTrue(Pos('Getter, Setter und Feld für Name erzeugen|', mFound) > 0, mFound);
end;

procedure TLspCodeActionsTests.SettingsSwitchThemOff;
var
  mFound: string;
begin
  FSettings.TryFinally := False;
  FSettings.ClassActions := False;
  mFound := Titles(cText, 12);
  Assert.AreEqual(0, Pos('try/finally', mFound), mFound);
  mFound := Titles(cText, 5);
  Assert.AreEqual(0, Pos('Getter, Setter', mFound), mFound);
end;

procedure TLspCodeActionsTests.TryFinallyFollowsFormatStyle;
var
  mUri, mNewText: string;
  mRequest, mResponse: TJSONObject;
  mItem: TJSONValue;
  mEdits: TJSONArray;
begin
  FActions.FormatStyleFor :=
    function(const AUri: string): TFormatStyle
    begin
      Result := TFormatStyle.Default;
      Result.UseTabs := True;
    end;
  mUri := TDocumentUris.FromPath(cFileName);
  FStore.Open(mUri, 'delphi', 1, cText);
  mRequest := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":99,"method":"textDocument/codeAction","params":' +
    '{"textDocument":{"uri":"' + mUri.Replace('\', '\\') + '"},"range":{"start":{"line":12,"character":0},' +
    '"end":{"line":12,"character":0}},"context":{"diagnostics":[]}}}') as TJSONObject;
  try
    mResponse := FDispatcher.DispatchMessage(mRequest);
  finally
    mRequest.Free;
  end;
  try
    mNewText := '';
    for mItem in mResponse.GetValue<TJSONArray>('result') do
    begin
      if StartsText('try/finally', TJSONObject(mItem).GetValue<string>('title')) then
        // Der Schlüssel ist die URI mit Punkten; deshalb über das erste Paar statt über einen Pfad.
      begin
        mEdits := TJSONObject(mItem).GetValue<TJSONObject>('edit.changes').Pairs[0].JsonValue as TJSONArray;
        mNewText := TJSONObject(mEdits.Items[0]).GetValue<string>('newText');
      end;
    end;
    Assert.IsTrue(Pos('try' + cLB + #9'  L.Add(nil);', mNewText) > 0, mNewText);
  finally
    mResponse.Free;
  end;
end;

procedure TLspCodeActionsTests.ActionJsonCarriesPreviewAndDisabled;
var
  mAction: TCodeAction;
  mJson: TJSONObject;
begin
  mAction := Default(TCodeAction);
  mAction.Title := 'Umwandeln';
  mAction.Kind := cRewriteKind;
  mAction.Preview := 'Neue Signatur: procedure A;';
  mJson := TLspCodeActions.ActionToJson(TDocumentUris.FromPath(cFileName), mAction);
  try
    Assert.AreEqual('Neue Signatur: procedure A;', mJson.GetValue<string>('data.preview'));
    Assert.IsNull(mJson.GetValue('disabled'));
    Assert.IsNull(TJSONObject(mJson.GetValue('data')).GetValue('tag'));
  finally
    mJson.Free;
  end;
  mAction.Preview := '';
  mAction.Disabled := 'erst die andere umwandeln';
  mJson := TLspCodeActions.ActionToJson(TDocumentUris.FromPath(cFileName), mAction);
  try
    Assert.AreEqual('erst die andere umwandeln', mJson.GetValue<string>('disabled.reason'));
    Assert.IsNull(mJson.GetValue('data'));
  finally
    mJson.Free;
  end;
end;

procedure TLspCodeActionsTests.ActionJsonCarriesChoices;
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
  mJson := TLspCodeActions.ActionToJson(TDocumentUris.FromPath(cFileName), mAction);
  try
    mChoices := mJson.GetValue<TJSONArray>('data.choices');
    Assert.AreEqual(1, mChoices.Count);
    Assert.AreEqual('Zeile 4 in TFoo.Bar', mChoices.Items[0].GetValue<string>('title'));
    Assert.AreEqual(3, mChoices.Items[0].GetValue<Integer>('range.start.line'));
    mEditChoices := mJson.GetValue<TJSONArray>('data.editChoices');
    Assert.AreEqual(2, mEditChoices.Count);
    Assert.AreEqual(0, TJSONArray(mEditChoices.Items[0]).Count);
    Assert.AreEqual('[0]', mEditChoices.Items[1].ToJSON);
  finally
    mJson.Free;
  end;
end;

procedure TLspCodeActionsTests.UsesEntryActionsCarryTag;
const
  cUsesText = 'unit Haupt;' + cLB + 'interface' + cLB + 'uses' + cLB + '  Vcl.Grids, Vcl.Menus, {$IFDEF X}Vcl.Forms, {$ENDIF}Vcl.Dialogs;' +
    cLB + 'implementation' + cLB + 'end.';
var
  mUri, mTags: string;
  mRequest, mResponse: TJSONObject;
  mItem, mData: TJSONValue;
begin
  FActions.UsesContextFor :=
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
  // Projekt ohne X: der Zweig mit Vcl.Forms ist inaktiv.
  FActions.DefinesFor :=
    function(const AUri: string; out ADefines: TArray<string>): Boolean
    begin
      ADefines := ['DEBUG'];
      Result := True;
    end;
  mUri := TDocumentUris.FromPath(cFileName);
  FStore.Open(mUri, 'delphi', 1, cUsesText);
  mRequest := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":7,"method":"textDocument/codeAction","params":' +
    '{"textDocument":{"uri":"' + mUri.Replace('\', '\\') + '"},"range":{"start":{"line":3,"character":4},' +
    '"end":{"line":3,"character":4}},"context":{"diagnostics":[]}}}') as TJSONObject;
  try
    mResponse := FDispatcher.DispatchMessage(mRequest);
  finally
    mRequest.Free;
  end;
  try
    mTags := '';
    for mItem in mResponse.GetValue<TJSONArray>('result') do
    begin
      mData := TJSONObject(mItem).GetValue('data');
      if mData is TJSONObject then
      begin
        mTags := mTags + TJSONObject(mItem).GetValue<string>('title') + '=' + TJSONObject(mData).GetValue<string>('tag') +
          '|';
      end;
    end;
    // X fehlt: Vcl.Forms zählt nicht, also zwei ungenutzte (Vcl.Grids, Vcl.Menus).
    Assert.AreEqual('Vcl.Grids entfernen=uses.remove|Alle ungenutzten uses entfernen (2)=uses.removeAll|', mTags);
  finally
    mResponse.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspCodeActionsTests);

end.
