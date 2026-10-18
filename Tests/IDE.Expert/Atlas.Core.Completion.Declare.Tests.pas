unit Atlas.Core.Completion.Declare.Tests;

// Tests für die Deklaration unbekannter Namen in der Vervollständigung (#471): Gruppe am Ende mit Überschrift,
// Felder aus der Antwort des Servers und Enter ohne Auswahl.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasCompletionDeclareTests = class
  public
    [Test]
    procedure UnknownGroupComesLast;
    [Test]
    procedure ReadsDeclareFieldsFromServer;
    [Test]
    procedure EnterPassesThroughWithoutSelection;
    [Test]
    procedure ReadsLinkedEditsAndCommand;
    [Test]
    procedure PlainDropsPlaceholdersForActions;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.Snippets,
  Atlas.Core.Completion.Controller,
  Atlas.Core.Completion.Ranking,
  Atlas.Core.Completion.Providers.Fixed,
  Atlas.Core.Completion.Providers.Server;

type
  TDeclareView = class(TInterfacedObject, IAtlasCompletionView)
  public
    Selected: Integer;
    procedure ShowList(const AItems: TAtlasCompletionItems; const AOrder: TArray<Integer>; ASelected: Integer;
      const APattern: string);
    procedure HideList;
    procedure ShowEmpty(const APrefix: string; ATotal: Integer);
    function PageSize: Integer;
    procedure ShowChips(const ACounts: TAtlasChipCounts; AActive: TAtlasChip; AVisible: Boolean);
  end;

procedure TDeclareView.ShowList(const AItems: TAtlasCompletionItems; const AOrder: TArray<Integer>;
  ASelected: Integer; const APattern: string);
begin
  Selected := ASelected;
end;

procedure TDeclareView.HideList;
begin
end;

procedure TDeclareView.ShowEmpty(const APrefix: string; ATotal: Integer);
begin
end;

function TDeclareView.PageSize: Integer;
begin
  Result := 5;
end;

procedure TDeclareView.ShowChips(const ACounts: TAtlasChipCounts; AActive: TAtlasChip; AVisible: Boolean);
begin
end;

function Declare(const AName: string; ARank: Integer): TAtlasCompletionItem;
begin
  Result := Default(TAtlasCompletionItem);
  Result.Name := AName;
  Result.Kind := TAtlasItemKind.Variable;
  Result.IsAction := True;
  Result.Unknown := 'TotalCount';
  Result.Rank := ARank;
end;

function Declarations: TAtlasCompletionItems;
begin
  Result := [Declare('Lokale Variable anlegen', 1), Declare('Feld FTotalCount anlegen', 2)];
end;

function Names(const AItems: TAtlasCompletionItems; const AOrder: TArray<Integer>): string;
var
  Index: Integer;
begin
  Result := '';
  for Index in AOrder do
    if Index = TAtlasRanking.UnknownHeader then
      Result := Result + '? '
    else if TAtlasRanking.IsHeader(Index) then
      Result := Result + '# '
    else
      Result := Result + AItems[Index].Name + ' ';
  Result := Result.Trim;
end;

const
  // resourcestring auslagern (#473) mit Platzhalter im Literal und in der Deklaration.
  ResourceItem =
    '{"label":"Als resourcestring auslagern","kind":21,"insertTextFormat":2,"textEdit":{"range":{"start":' +
    '{"line":9,"character":14},"end":{"line":9,"character":21}},"newText":"${1:SFrage}"},' +
    '"additionalTextEdits":[{"range":{"start":{"line":3,"character":0},"end":{"line":3,"character":0}},' +
    '"newText":"  ${1:SFrage} = ''Frage?'';\n"}],"command":{"title":"Eintragen","command":' +
    '"atlas.server.addResourceString","arguments":["C:\\P\\Texte.pas","SFrage","''Frage?''"]},' +
    '"data":{"action":"create","pinned":true,"linkedEdits":true}}';

function ResourceFromLsp(const AJson: string): TAtlasCompletionItem;
var
  Json: TJSONObject;
begin
  Json := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
  try
    Result := TAtlasServerCompletionProvider.ItemFromLsp(Json, 0);
  finally
    Json.Free;
  end;
end;

function WaitFor(const ACondition: TFunc<Boolean>): Boolean;
var
  Start: UInt64;
begin
  Start := TThread.GetTickCount64;
  repeat
    CheckSynchronize(5);
    if ACondition() then
      Exit(True);
  until TThread.GetTickCount64 - Start > 3000;
  Result := False;
end;

{ TAtlasCompletionDeclareTests }

procedure TAtlasCompletionDeclareTests.UnknownGroupComesLast;
var
  Items: TAtlasCompletionItems;
  Regular: TAtlasCompletionItem;
begin
  Regular := Default(TAtlasCompletionItem);
  Regular.Name := 'TotalItems';
  Regular.Kind := TAtlasItemKind.Variable;
  Items := Declarations + [Regular];
  Assert.AreEqual('TotalItems ? Lokale Variable anlegen Feld FTotalCount anlegen',
    Names(Items, TAtlasRanking.Order(Items, 'Tot', TAtlasRankOptions.Defaults)));
  // Ohne andere Einträge bleibt die Gruppe mit ihrer Überschrift.
  Items := Declarations;
  Assert.AreEqual('? Lokale Variable anlegen Feld FTotalCount anlegen',
    Names(Items, TAtlasRanking.Order(Items, 'TotalCount', TAtlasRankOptions.Defaults)));
end;

procedure TAtlasCompletionDeclareTests.ReadsDeclareFieldsFromServer;
var
  Json: TJSONObject;
  Item: TAtlasCompletionItem;
begin
  Json := TJSONObject.ParseJSONValue('{"label":"Lokale Variable anlegen","kind":6,"textEdit":{"range":{"start":' +
    '{"line":9,"character":2},"end":{"line":9,"character":12}},"newText":"TotalCount$0"},"additionalTextEdits":' +
    '[{"range":{"start":{"line":8,"character":0},"end":{"line":8,"character":0}},"newText":"var"}],' +
    '"data":{"action":"declare","unknown":"TotalCount"}}') as TJSONObject;
  try
    Item := TAtlasServerCompletionProvider.ItemFromLsp(Json, 0);
  finally
    Json.Free;
  end;
  Assert.IsTrue(Item.IsAction);
  Assert.AreEqual('TotalCount', Item.Unknown);
  Assert.IsTrue(Item.UnitUsed, 'die Zusatzänderung ist keine uses-Ergänzung');
  Assert.AreEqual('TotalCount$0', Item.TextEdit.NewText);
end;

procedure TAtlasCompletionDeclareTests.ReadsLinkedEditsAndCommand;
var
  Item: TAtlasCompletionItem;
begin
  Item := ResourceFromLsp(ResourceItem);
  Assert.IsTrue(Item.IsAction);
  Assert.IsTrue(Item.LinkedEdits);
  Assert.AreEqual(TAtlasSnippets.FromLsp('${1:SFrage}'), Item.Snippet);
  Assert.AreEqual(1, Integer(Length(Item.AdditionalEdits)));
  Assert.AreEqual(TAtlasSnippets.FromLsp('  ${1:SFrage} = ''Frage?'';'#10), Item.AdditionalEdits[0].NewText);
  Assert.AreEqual('atlas.server.addResourceString', Item.Command);
  Assert.AreEqual('["C:\\P\\Texte.pas","SFrage","''Frage?''"]', Item.CommandArguments);
  // Ohne Vorlage keine verknüpften Änderungen, ohne Argumente eine leere Liste.
  Item := ResourceFromLsp(StringReplace(StringReplace(ResourceItem, '"insertTextFormat":2,', '', []),
    ',"arguments":["C:\\P\\Texte.pas","SFrage","''Frage?''"]', '', []));
  Assert.IsFalse(Item.LinkedEdits);
  Assert.AreEqual('  ${1:SFrage} = ''Frage?'';'#10, Item.AdditionalEdits[0].NewText);
  Assert.AreEqual('[]', Item.CommandArguments);
end;

procedure TAtlasCompletionDeclareTests.PlainDropsPlaceholdersForActions;
var
  Items: TAtlasCompletionItems;
  Snippet: TAtlasCompletionItem;
begin
  Snippet := Default(TAtlasCompletionItem);
  Snippet.Name := 'forin';
  Snippet.Snippet := TAtlasSnippets.FromLsp('for ${1:Item} in ${2:List} do');
  Items := TAtlasServerCompletionProvider.WithoutSnippets([ResourceFromLsp(ResourceItem), Snippet]);
  // Die Vorlage fällt weg, der Eintrag, der Code erzeugt, bleibt mit dem Text der Vorgaben.
  Assert.AreEqual(1, Integer(Length(Items)));
  Assert.AreEqual('', Items[0].Snippet);
  Assert.IsFalse(Items[0].LinkedEdits);
  Assert.AreEqual('SFrage', Items[0].TextEdit.NewText);
  Assert.AreEqual('  SFrage = ''Frage?'';'#10, Items[0].AdditionalEdits[0].NewText);
  Assert.AreEqual('atlas.server.addResourceString', Items[0].Command);
end;

procedure TAtlasCompletionDeclareTests.EnterPassesThroughWithoutSelection;
var
  View: TDeclareView;
  ViewRef: IAtlasCompletionView;
  Controller: TAtlasCompletionController;
  Committed: string;
  Context: TAtlasContext;
begin
  View := TDeclareView.Create;
  ViewRef := View;
  Controller := TAtlasCompletionController.Create(
    TAtlasFixedCompletionProvider.Create(Declarations) as IAtlasCompletionProvider, ViewRef);
  try
    Committed := '';
    Controller.OnCommit :=
      procedure(const AItem: TAtlasCompletionItem)
      begin
        Committed := AItem.Name;
      end;
    Context := Default(TAtlasContext);
    Context.FileName := 'C:\P\A.pas';
    Context.Prefix := 'TotalCount';
    Controller.Start(Context);
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    // Nur Deklarationen: sichtbar, nichts gewählt; Enter gehört dem Editor und schließt die Liste.
    Assert.IsTrue(Controller.Passive);
    Assert.AreEqual(-1, View.Selected);
    Assert.IsFalse(Controller.HandleKey(TAtlasNavigationKey.Accept));
    Assert.AreEqual('', Committed);
    Assert.IsFalse(Controller.Active);
    // Pfeiltaste wählt die erste Deklaration, Enter übernimmt sie.
    Controller.Start(Context);
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.IsTrue(Controller.HandleKey(TAtlasNavigationKey.Down));
    Assert.IsFalse(Controller.Passive);
    Assert.IsTrue(View.Selected >= 0);
    Assert.IsTrue(Controller.HandleKey(TAtlasNavigationKey.Accept));
    Assert.AreEqual('Lokale Variable anlegen', Committed);
  finally
    Controller.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasCompletionDeclareTests);

end.
