unit Atlas.Core.Completion.Sets.Tests;

// Tests für Aufzählungen und Mengen in der Vervollständigung (#448): Rangfolge, Mengenmodus im Controller,
// neuer Klammerinhalt und die Felder aus der Antwort des Servers. Dazu „Alle Werte einfügen“ für case (#449) und
// „Interface implementieren“ (#466) mit Kontrollkästchen und Hinweis, „Alle Felder zuweisen“ (#491) mit Liste.

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
    [Test]
    procedure PinnedCaseItemComesFirst;
    [Test]
    procedure BatchCommitsCheckedMethods;
    [Test]
    procedure HintStaysOnTopWithoutSelection;
    /// <summary>Alle Felder zuweisen (#491) mit Liste.</summary>
    [Test]
    procedure AssignListCommitsCheckedLines;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.Controller,
  Atlas.Core.Completion.Ranking,
  Atlas.Core.Completion.Sets,
  Atlas.Core.Completion.Presentation,
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
  // alNone ist ein Tippfehler-Kandidat (ein Zeichen anders, #485) und steht in eigener Gruppe dahinter.
  Assert.AreEqual('# alTop # alNone', Names(Items, TAtlasRanking.Order(Items, 'alTo', Options)));
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

procedure TAtlasCompletionSetsTests.PinnedCaseItemComesFirst;
var
  Json: TJSONObject;
  Pinned: TAtlasCompletionItem;
  Items: TAtlasCompletionItems;
  Options: TAtlasRankOptions;
  Tags: TAtlasTags;
begin
  Json := TJSONObject.ParseJSONValue('{"label":"Alle Werte einfügen","kind":15,"textEdit":{"range":{"start":' +
    '{"line":10,"character":20},"end":{"line":11,"character":4}},"newText":"\n    alNone: $0;"},' +
    '"data":{"expected":"TAlign","fits":true,"action":"case","pinned":true,"count":3}}') as TJSONObject;
  try
    Pinned := TAtlasServerCompletionProvider.ItemFromLsp(Json, 0);
  finally
    Json.Free;
  end;
  Assert.IsTrue(Pinned.Pinned);
  Assert.AreEqual(3, Integer(Pinned.Count));
  Assert.IsTrue(Pinned.HasTextEdit);
  Assert.IsFalse(Pinned.IsAction, 'kein „Neue Methode …“');
  Tags := TAtlasItemPresentation.Tags(Pinned);
  Assert.AreEqual('3', Tags[0].Text);
  // Ohne Getipptes ganz oben, vor den Werten; mit Getipptem hinter den Treffern, aber sichtbar.
  Items := [Value('alClient', 3), Pinned, Value('alNone', 1), Value('alTop', 2)];
  Options := TAtlasRankOptions.Defaults;
  Assert.AreEqual('# Alle Werte einfügen alNone alTop alClient', Names(Items, TAtlasRanking.Order(Items, '', Options)));
  Assert.AreEqual('# alTop Alle Werte einfügen # alNone', Names(Items, TAtlasRanking.Order(Items, 'alTo', Options)));
end;

function Insert(ALine: Integer; const AText: string): TAtlasTextEdit;
begin
  Result := Default(TAtlasTextEdit);
  Result.StartLine := ALine;
  Result.EndLine := ALine;
  Result.NewText := AText;
end;

/// <summary>Fehlende Methode wie vom Server (#466): Abschnitt, Kommentar und Deklaration vor Zeile 8, Rumpf in 12.</summary>
function Method(const AName, AInterface: string; AOrdinal: Integer): TAtlasCompletionItem;
begin
  Result := Default(TAtlasCompletionItem);
  Result.Name := AName;
  Result.Kind := TAtlasItemKind.Method;
  Result.Ordinal := AOrdinal;
  Result.ExpectedType := 'IExporter, IFlush';
  Result.Fits := True;
  Result.SetOf := 'IExporter, IFlush';
  Result.Checked := True;
  Result.Batch := True;
  Result.SetRange.StartLine := 7;
  Result.SetRange.StartCharacter := 4;
  Result.SetRange.EndLine := 7;
  Result.SetRange.EndCharacter := 4;
  Result.AdditionalEdits := [Insert(8, '  public'#10), Insert(8, '    { ' + AInterface + ' }'#10),
    Insert(8, '    procedure ' + AName + ';'#10), Insert(12, AName + #10)];
end;

procedure TAtlasCompletionSetsTests.BatchCommitsCheckedMethods;
var
  View: TSetView;
  ViewRef: IAtlasCompletionView;
  Controller: TAtlasCompletionController;
  Committed: TAtlasCompletionItem;
  Context: TAtlasContext;
  Json: TJSONObject;
  Item: TAtlasCompletionItem;
begin
  View := TSetView.Create;
  ViewRef := View;
  Controller := TAtlasCompletionController.Create(TAtlasFixedCompletionProvider.Create([Method('Flush', 'IFlush', 3),
    Method('Export', 'IExporter', 1), Method('Close', 'IExporter', 2)]) as IAtlasCompletionProvider, ViewRef);
  try
    Controller.OnCommit :=
      procedure(const AItem: TAtlasCompletionItem)
      begin
        Committed := AItem;
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
    Assert.AreEqual('Export Close Flush', View.Checked);
    // Close abwählen, dann übernehmen.
    Assert.IsTrue(Controller.HandleKey(TAtlasNavigationKey.Down));
    Assert.IsTrue(Controller.HandleKey(TAtlasNavigationKey.Toggle));
    Assert.IsTrue(Controller.HandleKey(TAtlasNavigationKey.Accept));
    Assert.IsTrue(Committed.HasTextEdit);
    Assert.AreEqual('', Committed.TextEdit.NewText);
    Assert.AreEqual(4, Committed.TextEdit.StartCharacter);
    Assert.AreEqual(2, Integer(Length(Committed.AdditionalEdits)));
    Assert.AreEqual('  public'#10'    { IExporter }'#10'    procedure Export;'#10'    { IFlush }'#10'    procedure Flush;'#10,
      Committed.AdditionalEdits[0].NewText);
    Assert.AreEqual('Export'#10'Flush'#10, Committed.AdditionalEdits[1].NewText);
  finally
    Controller.Free;
  end;
  Json := TJSONObject.ParseJSONValue('{"label":"Export","kind":2,"data":{"expected":"IExporter","fits":true,' +
    '"ordinal":1,"setOf":"IExporter","checked":true,"batch":true,"action":"implement","setRange":{"start":' +
    '{"line":7,"character":4},"end":{"line":7,"character":4}}}}') as TJSONObject;
  try
    Item := TAtlasServerCompletionProvider.ItemFromLsp(Json, 0);
  finally
    Json.Free;
  end;
  Assert.IsTrue(Item.Batch);
  Assert.IsFalse(Item.IsAction);
  Assert.AreEqual('IExporter', Item.SetOf);
end;

procedure TAtlasCompletionSetsTests.AssignListCommitsCheckedLines;
var
  Json: TJSONObject;
  Item, Committed: TAtlasCompletionItem;
  Lines: TAtlasCompletionItems;
  View: TSetView;
  ViewRef: IAtlasCompletionView;
  Controller: TAtlasCompletionController;
  Context: TAtlasContext;
begin
  // Wie vom Server (#491): textEdit über "Opts." mit unverändertem Text, die Zeilen unter data.assign.
  Json := TJSONObject.ParseJSONValue('{"label":"Alle Felder zuweisen (3)","kind":15,"detail":"TOpts",' +
    '"textEdit":{"range":{"start":{"line":5,"character":2},"end":{"line":5,"character":7}},"newText":"Opts."},' +
    '"data":{"action":"assign","pinned":true,"assign":[{"name":"A","detail":"Integer","text":"Opts.A := 0;\r\n  "},' +
    '{"name":"B","detail":"string","text":"Opts.B := '''';\r\n  "},{"name":"C","detail":"Boolean",' +
    '"text":"Opts.C := False;\r\n  "}]}}') as TJSONObject;
  try
    Item := TAtlasServerCompletionProvider.ItemFromLsp(Json, 0);
  finally
    Json.Free;
  end;
  Assert.AreEqual(3, Integer(Length(Item.Assignments)));
  Assert.AreEqual('B', Item.Assignments[1].Name);
  Assert.AreEqual('Opts.C := False;'#13#10'  ', Item.Assignments[2].Text);
  Lines := TAtlasCompletionSets.AssignItems(Item);
  Assert.AreEqual(3, Integer(Length(Lines)));
  Assert.IsTrue(Lines[0].Batch and Lines[0].Assign and Lines[0].Checked);
  Assert.AreEqual('TOpts', Lines[0].SetOf);
  Assert.AreEqual(2, Lines[0].SetRange.StartCharacter);
  Assert.AreEqual(7, Lines[0].SetRange.EndCharacter);
  Assert.AreEqual(7, Lines[0].AdditionalEdits[0].StartCharacter, 'hinter dem Punkt');
  View := TSetView.Create;
  ViewRef := View;
  Controller := TAtlasCompletionController.Create(TAtlasFixedCompletionProvider.Create([Item]) as
    IAtlasCompletionProvider, ViewRef);
  try
    Controller.OnCommit :=
      procedure(const AItem: TAtlasCompletionItem)
      begin
        Committed := AItem;
      end;
    Context := Default(TAtlasContext);
    Context.FileName := 'C:\P\A.pas';
    Controller.Start(Context);
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    // Enter auf dem Eintrag öffnet erst die Liste, alle angehakt.
    Assert.IsTrue(Controller.HandleKey(TAtlasNavigationKey.Accept));
    Assert.IsTrue(Controller.SetMode);
    Assert.AreEqual('A B C', View.Checked);
    Assert.AreEqual('', Committed.Name, 'noch nichts übernommen');
    // B abwählen, dann übernehmen: der Ausdruck weg, die Zeilen von A und C an seiner Stelle.
    Assert.IsTrue(Controller.HandleKey(TAtlasNavigationKey.Down));
    Assert.IsTrue(Controller.HandleKey(TAtlasNavigationKey.Toggle));
    Assert.IsTrue(Controller.HandleKey(TAtlasNavigationKey.Accept));
    Assert.IsTrue(Committed.HasTextEdit);
    Assert.IsTrue(Committed.IsAction);
    Assert.AreEqual('', Committed.TextEdit.NewText);
    Assert.AreEqual(2, Committed.TextEdit.StartCharacter);
    Assert.AreEqual(1, Integer(Length(Committed.AdditionalEdits)));
    Assert.AreEqual('Opts.A := 0;'#13#10'  Opts.C := False;'#13#10'  ', Committed.AdditionalEdits[0].NewText);
  finally
    Controller.Free;
  end;
  Lines := nil;
end;

procedure TAtlasCompletionSetsTests.HintStaysOnTopWithoutSelection;
var
  Json: TJSONObject;
  Hint, Item: TAtlasCompletionItem;
  Items: TAtlasCompletionItems;
  View: TSetView;
  ViewRef: IAtlasCompletionView;
  Controller: TAtlasCompletionController;
  Context: TAtlasContext;
begin
  // Der Hinweis entfernt das getippte Wort: textEdit ohne Text bleibt hier erhalten.
  Json := TJSONObject.ParseJSONValue('{"label":"2 Methoden von IExporter fehlen","kind":15,"textEdit":{"range":' +
    '{"start":{"line":7,"character":4},"end":{"line":7,"character":6}},"newText":""},"data":{"action":"implement",' +
    '"hint":true,"container":"IExporter"}}') as TJSONObject;
  try
    Hint := TAtlasServerCompletionProvider.ItemFromLsp(Json, 0);
  finally
    Json.Free;
  end;
  Assert.IsTrue(Hint.Hint);
  Assert.IsTrue(Hint.HasTextEdit);
  Assert.AreEqual('', Hint.TextEdit.NewText);
  Item := Default(TAtlasCompletionItem);
  Item.Name := 'Exception';
  Item.Kind := TAtlasItemKind.Class_;
  Items := [Item, Hint];
  Assert.AreEqual('2 Methoden von IExporter fehlen Exception',
    Names(Items, TAtlasRanking.Order(Items, 'Ex', TAtlasRankOptions.Defaults)));
  // Vorgewählt ist der erste Eintrag nach dem Hinweis; steht nur der Hinweis da, nichts.
  View := TSetView.Create;
  ViewRef := View;
  Controller := TAtlasCompletionController.Create(
    TAtlasFixedCompletionProvider.Create(Items) as IAtlasCompletionProvider, ViewRef);
  try
    Context := Default(TAtlasContext);
    Context.FileName := 'C:\P\A.pas';
    Context.Prefix := 'Ex';
    Controller.Start(Context);
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.IsTrue(Controller.SelectedItem(Item));
    Assert.AreEqual('Exception', Item.Name);
  finally
    Controller.Free;
  end;
  Controller := TAtlasCompletionController.Create(
    TAtlasFixedCompletionProvider.Create([Hint]) as IAtlasCompletionProvider, ViewRef);
  try
    Context.Prefix := 'Ex';
    Controller.Start(Context);
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.IsFalse(Controller.SelectedItem(Item), 'Hinweis nicht vorgewählt');
    Assert.IsTrue(Controller.Passive);
  finally
    Controller.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasCompletionSetsTests);

end.
