unit Lsp.CodeActions.Tests;

// textDocument/codeAction über den Dispatcher (#42): try/finally und die
// Klassen-Aktionen kommen mit, refactoring.tryFinally und
// refactoring.classActions schalten sie ab. Die Aktionen aus Editing kommen wie in der Shell über
// TLspSourceActionsAdapter.

interface

uses
  DUnitX.TestFramework,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Editing.Contract.CodeActions,
  Lsp.CodeActions;

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
    /// <summary>Aktionen aus Editing mit ASettings, wie die Shell sie anmeldet.</summary>
    procedure UseSources(const ASettings: TEditingCodeActionSettings);
  public
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
    [Test]
    procedure MatchesRequestedKinds;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.CodeActions.Contract,
  Atlas.Tests.LspRules,
  Atlas.Common.Semantics.Contract,
  Editing.Composition,
  Adapters.Lsp.SourceActions;

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

{ TLspCodeActionsTests }

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

procedure TLspCodeActionsTests.UseSources(const ASettings: TEditingCodeActionSettings);
begin
  FActions.SourceActions := TLspSourceActionsAdapter.Wrap(TEditingComposition.CodeActions(ASettings));
end;

procedure TLspCodeActionsTests.Setup;
begin
  FStore := TDocumentStore.Create;
  FSettings := TRefactoringSettings.Default;
  FId := 0;
  FActions := TLspCodeActions.Create(FStore, TTestLspRules.PlainActions);
  FActions.RefactoringFor :=
    function(const AUri: string): TRefactoringSettings
    begin
      Result := FSettings;
    end;
  UseSources(Default(TEditingCodeActionSettings));
  FDispatcher := TJsonRpcDispatcher.Create;
  FActions.Attach(FDispatcher);
end;

procedure TLspCodeActionsTests.TearDown;
begin
  FDispatcher.Free;
  FActions.Free;
  FStore := nil;
  // Die Standardwerte enthalten Arrays und Texte (TRefactoringSettings.Default); blieben sie bis zum nächsten Setup
  // stehen, zählte der Leckmonitor sie dem ersten Test als Leck.
  FSettings := Default(TRefactoringSettings);
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

procedure TLspCodeActionsTests.UsesEntryActionsCarryTag;
const
  cUsesText = 'unit Haupt;' + cLB + 'interface' + cLB + 'uses' + cLB + '  Vcl.Grids, Vcl.Menus, {$IFDEF X}Vcl.Forms, {$ENDIF}Vcl.Dialogs;' +
    cLB + 'implementation' + cLB + 'end.';
var
  mSettings: TEditingCodeActionSettings;
  mUri, mTags: string;
  mRequest, mResponse: TJSONObject;
  mItem, mData: TJSONValue;
begin
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
  // Projekt ohne X: der Zweig mit Vcl.Forms ist inaktiv.
  mSettings.DefinesFor :=
    function(const AUri: string; out ADefines: TArray<string>): Boolean
    begin
      ADefines := ['DEBUG'];
      Result := True;
    end;
  UseSources(mSettings);
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

procedure TLspCodeActionsTests.MatchesRequestedKinds;
begin
  Assert.IsTrue(TLspCodeActions.KindRequested(cFixAllKind, nil));
  Assert.IsTrue(TLspCodeActions.KindRequested(cFixAllKind, ['source']));
  Assert.IsTrue(TLspCodeActions.KindRequested(cOrganizeImportsKind, ['source.organizeImports']));
  Assert.IsFalse(TLspCodeActions.KindRequested(cFixAllKind, ['source.organizeImports']));
  Assert.IsFalse(TLspCodeActions.KindRequested(cQuickFixKind, ['source']));
  Assert.IsFalse(TLspCodeActions.KindRequested('sourceX', ['source']));
end;

initialization
  TDUnitX.RegisterTestFixture(TLspCodeActionsTests);

end.
