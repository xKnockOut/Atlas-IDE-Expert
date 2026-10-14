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
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  Atlas.Core.Completion.Contract,
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
