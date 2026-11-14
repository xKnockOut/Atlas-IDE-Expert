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
  mIndex: Integer;
begin
  Result := '';
  for mIndex in AOrder do
  begin
    if mIndex = TAtlasRanking.cUnknownHeader then
    begin
      Result := Result + '? ';
    end
    else if TAtlasRanking.IsHeader(mIndex) then
    begin
      Result := Result + '# ';
    end
    else
    begin
      Result := Result + AItems[mIndex].Name + ' ';
    end;
  end;
  Result := Result.Trim;
end;

const
  // resourcestring auslagern (#473) mit Platzhalter im Literal und in der Deklaration.
  cResourceItem =
    '{"label":"Als resourcestring auslagern","kind":21,"insertTextFormat":2,"textEdit":{"range":{"start":' +
    '{"line":9,"character":14},"end":{"line":9,"character":21}},"newText":"${1:SFrage}"},' +
    '"additionalTextEdits":[{"range":{"start":{"line":3,"character":0},"end":{"line":3,"character":0}},' +
    '"newText":"  ${1:SFrage} = ''Frage?'';\n"}],"command":{"title":"Eintragen","command":' +
    '"atlas.server.addResourceString","arguments":["C:\\P\\Texte.pas","SFrage","''Frage?''"]},' +
    '"data":{"action":"create","pinned":true,"linkedEdits":true}}';

function ResourceFromLsp(const AJson: string): TAtlasCompletionItem;
var
  mJson: TJSONObject;
begin
  mJson := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
  try
    Result := TAtlasServerCompletionProvider.ItemFromLsp(mJson, 0);
  finally
    mJson.Free;
  end;
end;

function WaitFor(const ACondition: TFunc<Boolean>): Boolean;
var
  mStart: UInt64;
begin
  mStart := TThread.GetTickCount64;
  repeat
    CheckSynchronize(5);
    if ACondition() then
    begin
      Exit(True);
    end;
  until TThread.GetTickCount64 - mStart > 3000;
  Result := False;
end;

{ TAtlasCompletionDeclareTests }

procedure TAtlasCompletionDeclareTests.UnknownGroupComesLast;
var
  mItems: TAtlasCompletionItems;
  mRegular: TAtlasCompletionItem;
begin
  mRegular := Default(TAtlasCompletionItem);
  mRegular.Name := 'TotalItems';
  mRegular.Kind := TAtlasItemKind.Variable;
  mItems := Declarations + [mRegular];
  Assert.AreEqual('TotalItems ? Lokale Variable anlegen Feld FTotalCount anlegen',
    Names(mItems, TAtlasRanking.Order(mItems, 'Tot', TAtlasRankOptions.Defaults)));
  // Ohne andere Einträge bleibt die Gruppe mit ihrer Überschrift.
  mItems := Declarations;
  Assert.AreEqual('? Lokale Variable anlegen Feld FTotalCount anlegen',
    Names(mItems, TAtlasRanking.Order(mItems, 'TotalCount', TAtlasRankOptions.Defaults)));
end;

procedure TAtlasCompletionDeclareTests.ReadsDeclareFieldsFromServer;
var
  mJson: TJSONObject;
  mItem: TAtlasCompletionItem;
begin
  mJson := TJSONObject.ParseJSONValue('{"label":"Lokale Variable anlegen","kind":6,"textEdit":{"range":{"start":' +
    '{"line":9,"character":2},"end":{"line":9,"character":12}},"newText":"TotalCount$0"},"additionalTextEdits":' +
    '[{"range":{"start":{"line":8,"character":0},"end":{"line":8,"character":0}},"newText":"var"}],' +
    '"data":{"action":"declare","unknown":"TotalCount"}}') as TJSONObject;
  try
    mItem := TAtlasServerCompletionProvider.ItemFromLsp(mJson, 0);
  finally
    mJson.Free;
  end;
  Assert.IsTrue(mItem.IsAction);
  Assert.AreEqual('TotalCount', mItem.Unknown);
  Assert.IsTrue(mItem.UnitUsed, 'die Zusatzänderung ist keine uses-Ergänzung');
  Assert.AreEqual('TotalCount$0', mItem.TextEdit.NewText);
end;

procedure TAtlasCompletionDeclareTests.ReadsLinkedEditsAndCommand;
var
  mItem: TAtlasCompletionItem;
begin
  mItem := ResourceFromLsp(cResourceItem);
  Assert.IsTrue(mItem.IsAction);
  Assert.IsTrue(mItem.LinkedEdits);
  Assert.AreEqual(TAtlasSnippets.FromLsp('${1:SFrage}'), mItem.Snippet);
  Assert.AreEqual(1, Integer(Length(mItem.AdditionalEdits)));
  Assert.AreEqual(TAtlasSnippets.FromLsp('  ${1:SFrage} = ''Frage?'';'#10), mItem.AdditionalEdits[0].NewText);
  Assert.AreEqual('atlas.server.addResourceString', mItem.Command);
  Assert.AreEqual('["C:\\P\\Texte.pas","SFrage","''Frage?''"]', mItem.CommandArguments);
  // Ohne Vorlage keine verknüpften Änderungen, ohne Argumente eine leere Liste.
  mItem := ResourceFromLsp(StringReplace(StringReplace(cResourceItem, '"insertTextFormat":2,', '', []),
    ',"arguments":["C:\\P\\Texte.pas","SFrage","''Frage?''"]', '', []));
  Assert.IsFalse(mItem.LinkedEdits);
  Assert.AreEqual('  ${1:SFrage} = ''Frage?'';'#10, mItem.AdditionalEdits[0].NewText);
  Assert.AreEqual('[]', mItem.CommandArguments);
end;

procedure TAtlasCompletionDeclareTests.PlainDropsPlaceholdersForActions;
var
  mItems: TAtlasCompletionItems;
  mSnippet: TAtlasCompletionItem;
begin
  mSnippet := Default(TAtlasCompletionItem);
  mSnippet.Name := 'forin';
  mSnippet.Snippet := TAtlasSnippets.FromLsp('for ${1:Item} in ${2:List} do');
  mItems := TAtlasServerCompletionProvider.WithoutSnippets([ResourceFromLsp(cResourceItem), mSnippet]);
  // Die Vorlage fällt weg, der Eintrag, der Code erzeugt, bleibt mit dem Text der Vorgaben.
  Assert.AreEqual(1, Integer(Length(mItems)));
  Assert.AreEqual('', mItems[0].Snippet);
  Assert.IsFalse(mItems[0].LinkedEdits);
  Assert.AreEqual('SFrage', mItems[0].TextEdit.NewText);
  Assert.AreEqual('  SFrage = ''Frage?'';'#10, mItems[0].AdditionalEdits[0].NewText);
  Assert.AreEqual('atlas.server.addResourceString', mItems[0].Command);
end;

procedure TAtlasCompletionDeclareTests.EnterPassesThroughWithoutSelection;
var
  mView: TDeclareView;
  mViewRef: IAtlasCompletionView;
  mController: TAtlasCompletionController;
  mCommitted: string;
  mContext: TAtlasContext;
begin
  mView := TDeclareView.Create;
  mViewRef := mView;
  mController := TAtlasCompletionController.Create(
    TAtlasFixedCompletionProvider.Create(Declarations) as IAtlasCompletionProvider, mViewRef);
  try
    mCommitted := '';
    mController.OnCommit :=
      procedure(const AItem: TAtlasCompletionItem)
      begin
        mCommitted := AItem.Name;
      end;
    mContext := Default(TAtlasContext);
    mContext.FileName := 'C:\P\A.pas';
    mContext.Prefix := 'TotalCount';
    mController.Start(mContext);
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not mController.Loading;
      end));
    // Nur Deklarationen: sichtbar, nichts gewählt; Enter gehört dem Editor und schließt die Liste.
    Assert.IsTrue(mController.Passive);
    Assert.AreEqual(-1, mView.Selected);
    Assert.IsFalse(mController.HandleKey(TAtlasNavigationKey.Accept));
    Assert.AreEqual('', mCommitted);
    Assert.IsFalse(mController.Active);
    // Pfeiltaste wählt die erste Deklaration, Enter übernimmt sie.
    mController.Start(mContext);
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not mController.Loading;
      end));
    Assert.IsTrue(mController.HandleKey(TAtlasNavigationKey.Down));
    Assert.IsFalse(mController.Passive);
    Assert.IsTrue(mView.Selected >= 0);
    Assert.IsTrue(mController.HandleKey(TAtlasNavigationKey.Accept));
    Assert.AreEqual('Lokale Variable anlegen', mCommitted);
  finally
    mController.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasCompletionDeclareTests);

end.
