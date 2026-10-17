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
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Editing.UsesActions;

const
  LB = #13#10;
  FileName = 'C:\P\Haupt.pas';
  Text =
    'unit Haupt;' + LB +
    'interface' + LB +
    'type' + LB +
    '  TKunde = class' + LB +
    '  public' + LB +
    '    property Name: string;' + LB +           // 5
    '  end;' + LB +
    'implementation' + LB +
    'procedure P;' + LB +
    'var' + LB +
    '  L: TList;' + LB +
    'begin' + LB +
    '  L := TList.Create;' + LB +                 // 12
    '  L.Add(nil);' + LB +
    'end;' + LB +
    'end.';

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
  Uri: string;
  Request, Response: TJSONObject;
  Item: TJSONValue;
begin
  Uri := TDocumentUris.FromPath(FileName);
  FStore.Close(Uri);
  FStore.Open(Uri, 'delphi', 1, AText);
  Inc(FId);
  Request := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":' + IntToStr(FId) +
    ',"method":"textDocument/codeAction","params":{"textDocument":{"uri":"' + Uri.Replace('\', '\\') +
    '"},"range":{"start":{"line":' + IntToStr(ALine) + ',"character":0},"end":{"line":' + IntToStr(ALine) +
    ',"character":0}},"context":{"diagnostics":[]}}}') as TJSONObject;
  try
    Response := FDispatcher.DispatchMessage(Request);
  finally
    Request.Free;
  end;
  Assert.IsNotNull(Response);
  try
    Assert.IsTrue(Response.GetValue('result') is TJSONArray, Response.ToJSON);
    Result := '';
    for Item in TJSONArray(Response.GetValue('result')) do
      Result := Result + TJSONObject(Item).GetValue<string>('title') + '|';
  finally
    Response.Free;
  end;
end;

procedure TLspCodeActionsTests.OffersTryFinallyAndClassActions;
var
  Found: string;
begin
  Found := Titles(Text, 12);
  Assert.IsTrue(Pos('try/finally mit L.Free ergänzen|', Found) > 0, Found);
  Found := Titles(Text, 5);
  Assert.IsTrue(Pos('Getter, Setter und Feld für Name erzeugen|', Found) > 0, Found);
end;

procedure TLspCodeActionsTests.SettingsSwitchThemOff;
var
  Found: string;
begin
  FSettings.TryFinally := False;
  FSettings.ClassActions := False;
  Found := Titles(Text, 12);
  Assert.AreEqual(0, Pos('try/finally', Found), Found);
  Found := Titles(Text, 5);
  Assert.AreEqual(0, Pos('Getter, Setter', Found), Found);
end;

procedure TLspCodeActionsTests.TryFinallyFollowsFormatStyle;
var
  Uri, NewText: string;
  Request, Response: TJSONObject;
  Item: TJSONValue;
  Edits: TJSONArray;
begin
  FActions.FormatStyleFor :=
    function(const AUri: string): TFormatStyle
    begin
      Result := TFormatStyle.Default;
      Result.UseTabs := True;
    end;
  Uri := TDocumentUris.FromPath(FileName);
  FStore.Open(Uri, 'delphi', 1, Text);
  Request := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":99,"method":"textDocument/codeAction","params":' +
    '{"textDocument":{"uri":"' + Uri.Replace('\', '\\') + '"},"range":{"start":{"line":12,"character":0},' +
    '"end":{"line":12,"character":0}},"context":{"diagnostics":[]}}}') as TJSONObject;
  try
    Response := FDispatcher.DispatchMessage(Request);
  finally
    Request.Free;
  end;
  try
    NewText := '';
    for Item in Response.GetValue<TJSONArray>('result') do
      if StartsText('try/finally', TJSONObject(Item).GetValue<string>('title')) then
        // Der Schlüssel ist die URI mit Punkten; deshalb über das erste Paar statt über einen Pfad.
      begin
        Edits := TJSONObject(Item).GetValue<TJSONObject>('edit.changes').Pairs[0].JsonValue as TJSONArray;
        NewText := TJSONObject(Edits.Items[0]).GetValue<string>('newText');
      end;
    Assert.IsTrue(Pos('try' + LB + #9'  L.Add(nil);', NewText) > 0, NewText);
  finally
    Response.Free;
  end;
end;

procedure TLspCodeActionsTests.UsesEntryActionsCarryTag;
const
  UsesText = 'unit Haupt;' + LB + 'interface' + LB + 'uses' + LB + '  Vcl.Grids, Vcl.Menus, {$IFDEF X}Vcl.Forms, {$ENDIF}Vcl.Dialogs;' +
    LB + 'implementation' + LB + 'end.';
var
  Uri, Tags: string;
  Request, Response: TJSONObject;
  Item, Data: TJSONValue;
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
  Uri := TDocumentUris.FromPath(FileName);
  FStore.Open(Uri, 'delphi', 1, UsesText);
  Request := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":7,"method":"textDocument/codeAction","params":' +
    '{"textDocument":{"uri":"' + Uri.Replace('\', '\\') + '"},"range":{"start":{"line":3,"character":4},' +
    '"end":{"line":3,"character":4}},"context":{"diagnostics":[]}}}') as TJSONObject;
  try
    Response := FDispatcher.DispatchMessage(Request);
  finally
    Request.Free;
  end;
  try
    Tags := '';
    for Item in Response.GetValue<TJSONArray>('result') do
    begin
      Data := TJSONObject(Item).GetValue('data');
      if Data is TJSONObject then
        Tags := Tags + TJSONObject(Item).GetValue<string>('title') + '=' + TJSONObject(Data).GetValue<string>('tag') +
          '|';
    end;
    // X fehlt: Vcl.Forms zählt nicht, also zwei ungenutzte (Vcl.Grids, Vcl.Menus).
    Assert.AreEqual('Vcl.Grids entfernen=uses.remove|Alle ungenutzten uses entfernen (2)=uses.removeAll|', Tags);
  finally
    Response.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspCodeActionsTests);

end.
