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
  mIndex: Integer;
begin
  Shown := True;
  Empty := False;
  Checked := '';
  for mIndex in AOrder do
  begin
    if not TAtlasRanking.IsHeader(mIndex) and AItems[mIndex].Checked then
    begin
      Checked := Checked + AItems[mIndex].Name + ' ';
    end;
  end;
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

function Value(const AName: string; AOrdinal: Integer; AChecked: Boolean): TAtlasCompletionItem; overload;
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

function Value(const AName: string; AOrdinal: Integer): TAtlasCompletionItem; overload;
begin
  Result := Value(AName, AOrdinal, False);
end;

/// <summary>akLeft angehakt, die Liste absichtlich nicht in Deklarationsreihenfolge.</summary>
function Anchors: TAtlasCompletionItems;
begin
  Result := [Value('akRight', 3), Value('akLeft', 1, True), Value('akTop', 2), Value('akBottom', 4)];
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

function Names(const AItems: TAtlasCompletionItems; const AOrder: TArray<Integer>): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex in AOrder do
  begin
    if TAtlasRanking.IsHeader(mIndex) then
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

{ TAtlasCompletionSetsTests }

procedure TAtlasCompletionSetsTests.EnumValuesComeFirstInDeclarationOrder;
var
  mItems: TAtlasCompletionItems;
  mOptions: TAtlasRankOptions;
  mLocal: TAtlasCompletionItem;
begin
  // Eine passende lokale Variable stünde sonst vor den Werten (Bereich 1).
  mLocal := Default(TAtlasCompletionItem);
  mLocal.Name := 'Ausrichtung';
  mLocal.ExpectedType := 'TAlign';
  mLocal.Fits := True;
  mLocal.Scope := 1;
  mItems := [mLocal, Value('alClient', 3), Value('alNone', 1), Value('alTop', 2)];
  mOptions := TAtlasRankOptions.Defaults;
  mOptions.GroupInherited := True;
  Assert.AreEqual('# alNone alTop alClient Ausrichtung', Names(mItems, TAtlasRanking.Order(mItems, '', mOptions)));
  // Mit Getipptem entscheidet die Güte, bei Gleichstand die Deklaration.
  // alNone ist ein Tippfehler-Kandidat (ein Zeichen anders, #485) und steht in eigener Gruppe dahinter.
  Assert.AreEqual('# alTop # alNone', Names(mItems, TAtlasRanking.Order(mItems, 'alTo', mOptions)));
end;

procedure TAtlasCompletionSetsTests.ComposesBracketInDeclarationOrder;
var
  mItems: TAtlasCompletionItems;
  mCommit: TAtlasCompletionItem;
begin
  mItems := Anchors;
  Assert.IsTrue(TAtlasCompletionSets.Active(mItems));
  Assert.IsFalse(TAtlasCompletionSets.Active([Default(TAtlasCompletionItem)]));
  mItems[0].Checked := True;
  Assert.AreEqual(2, TAtlasCompletionSets.CheckedCount(mItems));
  Assert.AreEqual('[akLeft, akRight]', TAtlasCompletionSets.Text(mItems));
  // Scoped Enums: Typpräfix aus InsertText.
  mItems[0].InsertText := 'TAnchorKind.akRight';
  Assert.AreEqual('[akLeft, TAnchorKind.akRight]', TAtlasCompletionSets.Text(mItems));
  mItems[0].Checked := False;
  mItems[1].Checked := False;
  Assert.AreEqual('[]', TAtlasCompletionSets.Text(mItems));
  mItems[2].Checked := True;
  mCommit := TAtlasCompletionSets.CommitItem(mItems);
  Assert.IsTrue(mCommit.HasTextEdit);
  Assert.AreEqual('[akTop]', mCommit.TextEdit.NewText);
  Assert.AreEqual(13, mCommit.TextEdit.StartCharacter);
  Assert.AreEqual(23, mCommit.TextEdit.EndCharacter);
end;

procedure TAtlasCompletionSetsTests.SpaceTogglesAndEnterReplacesBracket;
var
  mView: TSetView;
  mViewRef: IAtlasCompletionView;
  mController: TAtlasCompletionController;
  mCommitted: string;
  mContext: TAtlasContext;
begin
  mView := TSetView.Create;
  mViewRef := mView;
  mController := TAtlasCompletionController.Create(
    TAtlasFixedCompletionProvider.Create(Anchors) as IAtlasCompletionProvider, mViewRef);
  try
    mCommitted := '';
    mController.OnCommit :=
      procedure(const AItem: TAtlasCompletionItem)
      begin
        mCommitted := AItem.TextEdit.NewText;
      end;
    mContext := Default(TAtlasContext);
    mContext.FileName := 'C:\P\A.pas';
    mController.Start(mContext);
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not mController.Loading;
      end));
    Assert.IsTrue(mController.SetMode);
    Assert.AreEqual('akLeft', mView.Checked);
    // Werte in Deklarationsreihenfolge: akLeft, akTop, ...; akTop anhaken.
    Assert.IsTrue(mController.HandleKey(TAtlasNavigationKey.Down));
    Assert.IsTrue(mController.HandleKey(TAtlasNavigationKey.Toggle));
    Assert.AreEqual('akLeft akTop', mView.Checked);
    Assert.IsTrue(mController.HandleKey(TAtlasNavigationKey.Accept));
    Assert.AreEqual('[akLeft, akTop]', mCommitted);
    Assert.IsFalse(mController.Active);
  finally
    mController.Free;
  end;
end;

procedure TAtlasCompletionSetsTests.EnterWithoutToggleAddsSelectedValue;
var
  mView: TSetView;
  mViewRef: IAtlasCompletionView;
  mController: TAtlasCompletionController;
  mCommitted: string;
  mContext: TAtlasContext;
begin
  mView := TSetView.Create;
  mViewRef := mView;
  mController := TAtlasCompletionController.Create(
    TAtlasFixedCompletionProvider.Create(Anchors) as IAtlasCompletionProvider, mViewRef);
  try
    mController.OnCommit :=
      procedure(const AItem: TAtlasCompletionItem)
      begin
        mCommitted := AItem.TextEdit.NewText;
      end;
    mContext := Default(TAtlasContext);
    mContext.FileName := 'C:\P\A.pas';
    mContext.Prefix := 'akB';
    mController.Start(mContext);
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not mController.Loading;
      end));
    Assert.IsTrue(mController.HandleKey(TAtlasNavigationKey.Accept));
    Assert.AreEqual('[akLeft, akBottom]', mCommitted);
  finally
    mController.Free;
  end;
end;

procedure TAtlasCompletionSetsTests.BracketTriggerWithoutSetClosesQuietly;
var
  mView: TSetView;
  mViewRef: IAtlasCompletionView;
  mController: TAtlasCompletionController;
  mContext: TAtlasContext;
begin
  mView := TSetView.Create;
  mViewRef := mView;
  mController := TAtlasCompletionController.Create(
    TAtlasFixedCompletionProvider.Create(nil) as IAtlasCompletionProvider, mViewRef);
  try
    mContext := Default(TAtlasContext);
    mContext.FileName := 'C:\P\A.pas';
    mContext.Trigger := '[';
    mController.Start(mContext);
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not mController.Active;
      end), 'Nach "[" ohne Menge schließt die Liste');
    Assert.IsFalse(mView.Empty, 'kein leerer Zustand');
    Assert.IsFalse(mController.HandleKey(TAtlasNavigationKey.Toggle), 'Leertaste gehört dem Editor');
  finally
    mController.Free;
  end;
end;

procedure TAtlasCompletionSetsTests.ReadsSetFieldsFromServer;
var
  mJson: TJSONObject;
  mItem: TAtlasCompletionItem;
begin
  mJson := TJSONObject.ParseJSONValue('{"label":"akTop","kind":20,"data":{"expected":"TAnchors","fits":true,' +
    '"ordinal":2,"setOf":"TAnchorKind","checked":true,"setRange":{"start":{"line":4,"character":13},' +
    '"end":{"line":4,"character":23}}}}') as TJSONObject;
  try
    mItem := TAtlasServerCompletionProvider.ItemFromLsp(mJson, 0);
  finally
    mJson.Free;
  end;
  Assert.AreEqual(2, mItem.Ordinal);
  Assert.AreEqual('TAnchorKind', mItem.SetOf);
  Assert.IsTrue(mItem.Checked);
  Assert.AreEqual(4, mItem.SetRange.StartLine);
  Assert.AreEqual(23, mItem.SetRange.EndCharacter);
  // Ohne Bereich kein Mengenmodus.
  mJson := TJSONObject.ParseJSONValue('{"label":"akTop","data":{"setOf":"TAnchorKind"}}') as TJSONObject;
  try
    mItem := TAtlasServerCompletionProvider.ItemFromLsp(mJson, 0);
  finally
    mJson.Free;
  end;
  Assert.AreEqual('', mItem.SetOf);
end;

procedure TAtlasCompletionSetsTests.PinnedCaseItemComesFirst;
var
  mJson: TJSONObject;
  mPinned: TAtlasCompletionItem;
  mItems: TAtlasCompletionItems;
  mOptions: TAtlasRankOptions;
  mTags: TAtlasTags;
begin
  mJson := TJSONObject.ParseJSONValue('{"label":"Alle Werte einfügen","kind":15,"textEdit":{"range":{"start":' +
    '{"line":10,"character":20},"end":{"line":11,"character":4}},"newText":"\n    alNone: $0;"},' +
    '"data":{"expected":"TAlign","fits":true,"action":"case","pinned":true,"count":3}}') as TJSONObject;
  try
    mPinned := TAtlasServerCompletionProvider.ItemFromLsp(mJson, 0);
  finally
    mJson.Free;
  end;
  Assert.IsTrue(mPinned.Pinned);
  Assert.AreEqual(3, Integer(mPinned.Count));
  Assert.IsTrue(mPinned.HasTextEdit);
  Assert.IsFalse(mPinned.IsAction, 'kein „Neue Methode …“');
  mTags := TAtlasItemPresentation.Tags(mPinned);
  Assert.AreEqual('3', mTags[0].Text);
  // Ohne Getipptes ganz oben, vor den Werten; mit Getipptem hinter den Treffern, aber sichtbar.
  mItems := [Value('alClient', 3), mPinned, Value('alNone', 1), Value('alTop', 2)];
  mOptions := TAtlasRankOptions.Defaults;
  Assert.AreEqual('# Alle Werte einfügen alNone alTop alClient', Names(mItems, TAtlasRanking.Order(mItems, '', mOptions)));
  Assert.AreEqual('# alTop Alle Werte einfügen # alNone', Names(mItems, TAtlasRanking.Order(mItems, 'alTo', mOptions)));
end;

function Insert(ALine: Integer; const AText: string): TAtlasTextEdit;
begin
  Result := Default(TAtlasTextEdit);
  Result.StartLine := ALine;
  Result.EndLine := ALine;
  Result.NewText := AText;
end;

/// <summary>Fehlende Methode wie vom Server (#466): Abschnitt, Kommentar und Deklaration vor Zeile 8, Rumpf in
/// 12.</summary>
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
  mView: TSetView;
  mViewRef: IAtlasCompletionView;
  mController: TAtlasCompletionController;
  mCommitted: TAtlasCompletionItem;
  mContext: TAtlasContext;
  mJson: TJSONObject;
  mItem: TAtlasCompletionItem;
begin
  mView := TSetView.Create;
  mViewRef := mView;
  mController := TAtlasCompletionController.Create(TAtlasFixedCompletionProvider.Create([Method('Flush', 'IFlush', 3),
    Method('Export', 'IExporter', 1), Method('Close', 'IExporter', 2)]) as IAtlasCompletionProvider, mViewRef);
  try
    mController.OnCommit :=
      procedure(const AItem: TAtlasCompletionItem)
      begin
        mCommitted := AItem;
      end;
    mContext := Default(TAtlasContext);
    mContext.FileName := 'C:\P\A.pas';
    mController.Start(mContext);
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not mController.Loading;
      end));
    Assert.IsTrue(mController.SetMode);
    Assert.AreEqual('Export Close Flush', mView.Checked);
    // Close abwählen, dann übernehmen.
    Assert.IsTrue(mController.HandleKey(TAtlasNavigationKey.Down));
    Assert.IsTrue(mController.HandleKey(TAtlasNavigationKey.Toggle));
    Assert.IsTrue(mController.HandleKey(TAtlasNavigationKey.Accept));
    Assert.IsTrue(mCommitted.HasTextEdit);
    Assert.AreEqual('', mCommitted.TextEdit.NewText);
    Assert.AreEqual(4, mCommitted.TextEdit.StartCharacter);
    Assert.AreEqual(2, Integer(Length(mCommitted.AdditionalEdits)));
    Assert.AreEqual('  public'#10'    { IExporter }'#10'    procedure Export;'#10'    { IFlush }'#10'    procedure Flush;'#10,
      mCommitted.AdditionalEdits[0].NewText);
    Assert.AreEqual('Export'#10'Flush'#10, mCommitted.AdditionalEdits[1].NewText);
  finally
    mController.Free;
  end;
  mJson := TJSONObject.ParseJSONValue('{"label":"Export","kind":2,"data":{"expected":"IExporter","fits":true,' +
    '"ordinal":1,"setOf":"IExporter","checked":true,"batch":true,"action":"implement","setRange":{"start":' +
    '{"line":7,"character":4},"end":{"line":7,"character":4}}}}') as TJSONObject;
  try
    mItem := TAtlasServerCompletionProvider.ItemFromLsp(mJson, 0);
  finally
    mJson.Free;
  end;
  Assert.IsTrue(mItem.Batch);
  Assert.IsFalse(mItem.IsAction);
  Assert.AreEqual('IExporter', mItem.SetOf);
end;

/// <summary>Eintrag „Alle Felder zuweisen“ wie vom Server (#491) mit seinen drei Zeilen.</summary>
function AssignItemFromServer: TAtlasCompletionItem;
var
  mJson: TJSONObject;
  mLines: TAtlasCompletionItems;
begin
  // Wie vom Server (#491): textEdit über "Opts." mit unverändertem Text, die Zeilen unter data.assign.
  mJson := TJSONObject.ParseJSONValue('{"label":"Alle Felder zuweisen (3)","kind":15,"detail":"TOpts",' +
    '"textEdit":{"range":{"start":{"line":5,"character":2},"end":{"line":5,"character":7}},"newText":"Opts."},' +
    '"data":{"action":"assign","pinned":true,"assign":[{"name":"A","detail":"Integer","text":"Opts.A := 0;\r\n  "},' +
    '{"name":"B","detail":"string","text":"Opts.B := '''';\r\n  "},{"name":"C","detail":"Boolean",' +
    '"text":"Opts.C := False;\r\n  "}]}}') as TJSONObject;
  try
    Result := TAtlasServerCompletionProvider.ItemFromLsp(mJson, 0);
  finally
    mJson.Free;
  end;
  Assert.AreEqual(3, Integer(Length(Result.Assignments)));
  Assert.AreEqual('B', Result.Assignments[1].Name);
  Assert.AreEqual('Opts.C := False;'#13#10'  ', Result.Assignments[2].Text);
  mLines := TAtlasCompletionSets.AssignItems(Result);
  Assert.AreEqual(3, Integer(Length(mLines)));
  Assert.IsTrue(mLines[0].Batch and mLines[0].Assign and mLines[0].Checked);
  Assert.AreEqual('TOpts', mLines[0].SetOf);
  Assert.AreEqual(2, mLines[0].SetRange.StartCharacter);
  Assert.AreEqual(7, mLines[0].SetRange.EndCharacter);
  Assert.AreEqual(7, mLines[0].AdditionalEdits[0].StartCharacter, 'hinter dem Punkt');
end;

procedure TAtlasCompletionSetsTests.AssignListCommitsCheckedLines;
var
  mItem, mCommitted: TAtlasCompletionItem;
  mView: TSetView;
  mViewRef: IAtlasCompletionView;
  mController: TAtlasCompletionController;
  mContext: TAtlasContext;
begin
  mItem := AssignItemFromServer;
  mView := TSetView.Create;
  mViewRef := mView;
  mController := TAtlasCompletionController.Create(TAtlasFixedCompletionProvider.Create([mItem]) as
    IAtlasCompletionProvider, mViewRef);
  try
    mController.OnCommit :=
      procedure(const AItem: TAtlasCompletionItem)
      begin
        mCommitted := AItem;
      end;
    mContext := Default(TAtlasContext);
    mContext.FileName := 'C:\P\A.pas';
    mController.Start(mContext);
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not mController.Loading;
      end));
    // Enter auf dem Eintrag öffnet erst die Liste, alle angehakt.
    Assert.IsTrue(mController.HandleKey(TAtlasNavigationKey.Accept));
    Assert.IsTrue(mController.SetMode);
    Assert.AreEqual('A B C', mView.Checked);
    Assert.AreEqual('', mCommitted.Name, 'noch nichts übernommen');
    // B abwählen, dann übernehmen: der Ausdruck weg, die Zeilen von A und C an seiner Stelle.
    Assert.IsTrue(mController.HandleKey(TAtlasNavigationKey.Down));
    Assert.IsTrue(mController.HandleKey(TAtlasNavigationKey.Toggle));
    Assert.IsTrue(mController.HandleKey(TAtlasNavigationKey.Accept));
    Assert.IsTrue(mCommitted.HasTextEdit);
    Assert.IsTrue(mCommitted.IsAction);
    Assert.AreEqual('', mCommitted.TextEdit.NewText);
    Assert.AreEqual(2, mCommitted.TextEdit.StartCharacter);
    Assert.AreEqual(1, Integer(Length(mCommitted.AdditionalEdits)));
    Assert.AreEqual('Opts.A := 0;'#13#10'  Opts.C := False;'#13#10'  ', mCommitted.AdditionalEdits[0].NewText);
  finally
    mController.Free;
  end;
end;

/// <summary>Hinweis „2 Methoden von IExporter fehlen“ wie vom Server; er entfernt das getippte Wort.</summary>
function ImplementHintFromServer: TAtlasCompletionItem;
var
  mJson: TJSONObject;
begin
  // Der Hinweis entfernt das getippte Wort: textEdit ohne Text bleibt hier erhalten.
  mJson := TJSONObject.ParseJSONValue('{"label":"2 Methoden von IExporter fehlen","kind":15,"textEdit":{"range":' +
    '{"start":{"line":7,"character":4},"end":{"line":7,"character":6}},"newText":""},"data":{"action":"implement",' +
    '"hint":true,"container":"IExporter"}}') as TJSONObject;
  try
    Result := TAtlasServerCompletionProvider.ItemFromLsp(mJson, 0);
  finally
    mJson.Free;
  end;
  Assert.IsTrue(Result.Hint);
  Assert.IsTrue(Result.HasTextEdit);
  Assert.AreEqual('', Result.TextEdit.NewText);
end;

procedure TAtlasCompletionSetsTests.HintStaysOnTopWithoutSelection;
var
  mHint, mItem: TAtlasCompletionItem;
  mItems: TAtlasCompletionItems;
  mView: TSetView;
  mViewRef: IAtlasCompletionView;
  mController: TAtlasCompletionController;
  mContext: TAtlasContext;
begin
  mHint := ImplementHintFromServer;
  mItem := Default(TAtlasCompletionItem);
  mItem.Name := 'Exception';
  mItem.Kind := TAtlasItemKind.Class_;
  mItems := [mItem, mHint];
  Assert.AreEqual('2 Methoden von IExporter fehlen Exception',
    Names(mItems, TAtlasRanking.Order(mItems, 'Ex', TAtlasRankOptions.Defaults)));
  // Vorgewählt ist der erste Eintrag nach dem Hinweis; steht nur der Hinweis da, nichts.
  mView := TSetView.Create;
  mViewRef := mView;
  mController := TAtlasCompletionController.Create(
    TAtlasFixedCompletionProvider.Create(mItems) as IAtlasCompletionProvider, mViewRef);
  try
    mContext := Default(TAtlasContext);
    mContext.FileName := 'C:\P\A.pas';
    mContext.Prefix := 'Ex';
    mController.Start(mContext);
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not mController.Loading;
      end));
    Assert.IsTrue(mController.SelectedItem(mItem));
    Assert.AreEqual('Exception', mItem.Name);
  finally
    mController.Free;
  end;
  mController := TAtlasCompletionController.Create(
    TAtlasFixedCompletionProvider.Create([mHint]) as IAtlasCompletionProvider, mViewRef);
  try
    mContext.Prefix := 'Ex';
    mController.Start(mContext);
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not mController.Loading;
      end));
    Assert.IsFalse(mController.SelectedItem(mItem), 'Hinweis nicht vorgewählt');
    Assert.IsTrue(mController.Passive);
  finally
    mController.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasCompletionSetsTests);

end.
