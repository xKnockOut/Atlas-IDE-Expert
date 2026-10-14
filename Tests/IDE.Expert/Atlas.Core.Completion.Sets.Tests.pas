unit Atlas.Core.Completion.Sets.Tests;

// Tests für Aufzählungen und Mengen in der Vervollständigung (#448): Rangfolge, Mengenmodus im Controller,
// neuer Klammerinhalt und die Felder aus der Antwort des Servers.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasCompletionSetsTests = class
  public
    [Test]
    procedure EnumValuesComeFirstInDeclarationOrder;
    [Test]
    procedure ComposesBracketInDeclarationOrder;
    [Test]
    procedure SpaceTogglesAndEnterReplacesBracket;
    [Test]
    procedure EnterWithoutToggleAddsSelectedValue;
    [Test]
    procedure BracketTriggerWithoutSetClosesQuietly;
    [Test]
    procedure ReadsSetFieldsFromServer;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.Controller,
  Atlas.Core.Completion.Ranking,
  Atlas.Core.Completion.Sets,
  Atlas.Core.Completion.Providers.Fixed,
  Atlas.Core.Completion.Providers.Server;

type
  TSetView = class(TInterfacedObject, IAtlasCompletionView)
  public
    Shown: Boolean;
    Empty: Boolean;
    Checked: string;
    procedure ShowList(const AItems: TAtlasCompletionItems; const AOrder: TArray<Integer>; ASelected: Integer;
      const APattern: string);
    procedure HideList;
    procedure ShowEmpty(const APrefix: string; ATotal: Integer);
    function PageSize: Integer;
    procedure ShowChips(const ACounts: TAtlasChipCounts; AActive: TAtlasChip; AVisible: Boolean);
  end;

procedure TSetView.ShowList(const AItems: TAtlasCompletionItems; const AOrder: TArray<Integer>; ASelected: Integer;
  const APattern: string);
var
  Index: Integer;
begin
  Shown := True;
  Empty := False;
  Checked := '';
  for Index in AOrder do
    if not TAtlasRanking.IsHeader(Index) and AItems[Index].Checked then
      Checked := Checked + AItems[Index].Name + ' ';
  Checked := Checked.Trim;
end;

procedure TSetView.HideList;
begin
  Shown := False;
end;

procedure TSetView.ShowEmpty(const APrefix: string; ATotal: Integer);
begin
  Shown := False;
  Empty := True;
end;

function TSetView.PageSize: Integer;
begin
  Result := 5;
end;

procedure TSetView.ShowChips(const ACounts: TAtlasChipCounts; AActive: TAtlasChip; AVisible: Boolean);
begin
end;

function Value(const AName: string; AOrdinal: Integer; AChecked: Boolean = False): TAtlasCompletionItem;
begin
  Result := Default(TAtlasCompletionItem);
  Result.Name := AName;
  Result.Kind := TAtlasItemKind.EnumMember;
  Result.Ordinal := AOrdinal;
  Result.ExpectedType := 'TAnchors';
  Result.Fits := True;
  Result.SetOf := 'TAnchorKind';
  Result.Checked := AChecked;
  Result.SetRange.StartLine := 4;
  Result.SetRange.StartCharacter := 13;
  Result.SetRange.EndLine := 4;
  Result.SetRange.EndCharacter := 23;
end;

/// <summary>akLeft angehakt, die Liste absichtlich nicht in Deklarationsreihenfolge.</summary>
function Anchors: TAtlasCompletionItems;
begin
  Result := [Value('akRight', 3), Value('akLeft', 1, True), Value('akTop', 2), Value('akBottom', 4)];
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

function Names(const AItems: TAtlasCompletionItems; const AOrder: TArray<Integer>): string;
var
  Index: Integer;
begin
  Result := '';
  for Index in AOrder do
    if TAtlasRanking.IsHeader(Index) then
      Result := Result + '# '
    else
      Result := Result + AItems[Index].Name + ' ';
  Result := Result.Trim;
end;

{ TAtlasCompletionSetsTests }

procedure TAtlasCompletionSetsTests.EnumValuesComeFirstInDeclarationOrder;
var
  Items: TAtlasCompletionItems;
  Options: TAtlasRankOptions;
  Local: TAtlasCompletionItem;
begin
  // Eine passende lokale Variable stünde sonst vor den Werten (Bereich 1).
  Local := Default(TAtlasCompletionItem);
  Local.Name := 'Ausrichtung';
  Local.ExpectedType := 'TAlign';
  Local.Fits := True;
  Local.Scope := 1;
  Items := [Local, Value('alClient', 3), Value('alNone', 1), Value('alTop', 2)];
  Options := TAtlasRankOptions.Defaults;
  Options.GroupInherited := True;
  Assert.AreEqual('# alNone alTop alClient Ausrichtung', Names(Items, TAtlasRanking.Order(Items, '', Options)));
  // Mit Getipptem entscheidet die Güte, bei Gleichstand die Deklaration.
  Assert.AreEqual('# alTop', Names(Items, TAtlasRanking.Order(Items, 'alTo', Options)));
end;

procedure TAtlasCompletionSetsTests.ComposesBracketInDeclarationOrder;
var
  Items: TAtlasCompletionItems;
  Commit: TAtlasCompletionItem;
begin
  Items := Anchors;
  Assert.IsTrue(TAtlasCompletionSets.Active(Items));
  Assert.IsFalse(TAtlasCompletionSets.Active([Default(TAtlasCompletionItem)]));
  Items[0].Checked := True;
  Assert.AreEqual(2, TAtlasCompletionSets.CheckedCount(Items));
  Assert.AreEqual('[akLeft, akRight]', TAtlasCompletionSets.Text(Items));
  // Scoped Enums: Typpräfix aus InsertText.
  Items[0].InsertText := 'TAnchorKind.akRight';
  Assert.AreEqual('[akLeft, TAnchorKind.akRight]', TAtlasCompletionSets.Text(Items));
  Items[0].Checked := False;
  Items[1].Checked := False;
  Assert.AreEqual('[]', TAtlasCompletionSets.Text(Items));
  Items[2].Checked := True;
  Commit := TAtlasCompletionSets.CommitItem(Items);
  Assert.IsTrue(Commit.HasTextEdit);
  Assert.AreEqual('[akTop]', Commit.TextEdit.NewText);
  Assert.AreEqual(13, Commit.TextEdit.StartCharacter);
  Assert.AreEqual(23, Commit.TextEdit.EndCharacter);
end;

procedure TAtlasCompletionSetsTests.SpaceTogglesAndEnterReplacesBracket;
var
  View: TSetView;
  ViewRef: IAtlasCompletionView;
  Controller: TAtlasCompletionController;
  Committed: string;
  Context: TAtlasContext;
begin
  View := TSetView.Create;
  ViewRef := View;
  Controller := TAtlasCompletionController.Create(
    TAtlasFixedCompletionProvider.Create(Anchors) as IAtlasCompletionProvider, ViewRef);
  try
    Committed := '';
    Controller.OnCommit :=
      procedure(const AItem: TAtlasCompletionItem)
      begin
        Committed := AItem.TextEdit.NewText;
      end;
    Context := Default(TAtlasContext);
    Context.FileName := 'C:\P\A.pas';
    Controller.Start(Context);
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.IsTrue(Controller.SetMode);
    Assert.AreEqual('akLeft', View.Checked);
    // Werte in Deklarationsreihenfolge: akLeft, akTop, ...; akTop anhaken.
    Assert.IsTrue(Controller.HandleKey(TAtlasNavigationKey.Down));
    Assert.IsTrue(Controller.HandleKey(TAtlasNavigationKey.Toggle));
    Assert.AreEqual('akLeft akTop', View.Checked);
    Assert.IsTrue(Controller.HandleKey(TAtlasNavigationKey.Accept));
    Assert.AreEqual('[akLeft, akTop]', Committed);
    Assert.IsFalse(Controller.Active);
  finally
    Controller.Free;
  end;
end;

procedure TAtlasCompletionSetsTests.EnterWithoutToggleAddsSelectedValue;
var
  View: TSetView;
  ViewRef: IAtlasCompletionView;
  Controller: TAtlasCompletionController;
  Committed: string;
  Context: TAtlasContext;
begin
  View := TSetView.Create;
  ViewRef := View;
  Controller := TAtlasCompletionController.Create(
    TAtlasFixedCompletionProvider.Create(Anchors) as IAtlasCompletionProvider, ViewRef);
  try
    Controller.OnCommit :=
      procedure(const AItem: TAtlasCompletionItem)
      begin
        Committed := AItem.TextEdit.NewText;
      end;
    Context := Default(TAtlasContext);
    Context.FileName := 'C:\P\A.pas';
    Context.Prefix := 'akB';
    Controller.Start(Context);
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.IsTrue(Controller.HandleKey(TAtlasNavigationKey.Accept));
    Assert.AreEqual('[akLeft, akBottom]', Committed);
  finally
    Controller.Free;
  end;
end;

procedure TAtlasCompletionSetsTests.BracketTriggerWithoutSetClosesQuietly;
var
  View: TSetView;
  ViewRef: IAtlasCompletionView;
  Controller: TAtlasCompletionController;
  Context: TAtlasContext;
begin
  View := TSetView.Create;
  ViewRef := View;
  Controller := TAtlasCompletionController.Create(
    TAtlasFixedCompletionProvider.Create(nil) as IAtlasCompletionProvider, ViewRef);
  try
    Context := Default(TAtlasContext);
    Context.FileName := 'C:\P\A.pas';
    Context.Trigger := '[';
    Controller.Start(Context);
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Active;
      end), 'Nach "[" ohne Menge schließt die Liste');
    Assert.IsFalse(View.Empty, 'kein leerer Zustand');
    Assert.IsFalse(Controller.HandleKey(TAtlasNavigationKey.Toggle), 'Leertaste gehört dem Editor');
  finally
    Controller.Free;
  end;
end;

procedure TAtlasCompletionSetsTests.ReadsSetFieldsFromServer;
var
  Json: TJSONObject;
  Item: TAtlasCompletionItem;
begin
  Json := TJSONObject.ParseJSONValue('{"label":"akTop","kind":20,"data":{"expected":"TAnchors","fits":true,' +
    '"ordinal":2,"setOf":"TAnchorKind","checked":true,"setRange":{"start":{"line":4,"character":13},' +
    '"end":{"line":4,"character":23}}}}') as TJSONObject;
  try
    Item := TAtlasServerCompletionProvider.ItemFromLsp(Json, 0);
  finally
    Json.Free;
  end;
  Assert.AreEqual(2, Item.Ordinal);
  Assert.AreEqual('TAnchorKind', Item.SetOf);
  Assert.IsTrue(Item.Checked);
  Assert.AreEqual(4, Item.SetRange.StartLine);
  Assert.AreEqual(23, Item.SetRange.EndCharacter);
  // Ohne Bereich kein Mengenmodus.
  Json := TJSONObject.ParseJSONValue('{"label":"akTop","data":{"setOf":"TAnchorKind"}}') as TJSONObject;
  try
    Item := TAtlasServerCompletionProvider.ItemFromLsp(Json, 0);
  finally
    Json.Free;
  end;
  Assert.AreEqual('', Item.SetOf);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasCompletionSetsTests);

end.
