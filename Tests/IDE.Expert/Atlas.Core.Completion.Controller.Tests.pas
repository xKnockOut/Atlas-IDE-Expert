unit Atlas.Core.Completion.Controller.Tests;

// Tests für Filtern (#409) und Ablauf der Vervollständigung (#410, #414) ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasCompletionMatcherTests = class
  public
    [Test]
    procedure RanksExactBeforePrefixBeforeWordStarts;
    [Test]
    procedure MatchesCamelCaseAndSubsequence;
    [Test]
    procedure FiltersAndKeepsSourceOrderOnTies;
  end;

  [TestFixture]
  TAtlasCompletionControllerTests = class
  public
    [Test]
    procedure ShowsItemsFilteredByPrefix;
    [Test]
    procedure TypingRefiltersAndResetsSelection;
    [Test]
    procedure KeysMoveSelectionAndEnterCommits;
    [Test]
    procedure EscapeClosesAndKeysPassThroughWhenClosed;
    [Test]
    procedure EscapeBlocksAutomaticReopenInSameWord;
    [Test]
    procedure NoMatchShowsEmptyState;
    [Test]
    procedure EmptyResultShowsEmptyStateUntilEscape;
    [Test]
    procedure CommitCharacterOnlyForClearMatch;
    [Test]
    procedure TypoSuggestionsTakeOnlyEnter;
    [Test]
    procedure ItemsAfterCloseAreDropped;
    [Test]
    procedure TruncatedListIsRequeried;
    [Test]
    procedure RequeryKeepsSelectedEntry;
    [Test]
    procedure CompleteListFiltersLocallyUntilPrefixShrinks;
    [Test]
    procedure PartialResultsReplaceThenAppend;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.Matching,
  Atlas.Core.Completion.Controller,
  Atlas.Core.Completion.Ranking,
  Atlas.Core.Completion.Usage,
  Atlas.Core.Completion.Providers.Fixed;

type
  TFakeView = class(TInterfacedObject, IAtlasCompletionView)
  public
    Shown: Boolean;
    ShowCount: Integer;
    Names: string;
    Selected: Integer;
    Empty: Boolean;
    EmptyText: string;
    procedure ShowList(const AItems: TAtlasCompletionItems; const AOrder: TArray<Integer>; ASelected: Integer;
      const APattern: string);
    procedure HideList;
    procedure ShowEmpty(const APrefix: string; ATotal: Integer);
    function PageSize: Integer;
    procedure ShowChips(const ACounts: TAtlasChipCounts; AActive: TAtlasChip; AVisible: Boolean);
  end;

procedure TFakeView.ShowChips(const ACounts: TAtlasChipCounts; AActive: TAtlasChip; AVisible: Boolean);
begin
end;

procedure TFakeView.ShowList(const AItems: TAtlasCompletionItems; const AOrder: TArray<Integer>;
  ASelected: Integer; const APattern: string);
var
  Index: Integer;
begin
  Shown := True;
  Empty := False;
  Inc(ShowCount);
  Names := '';
  for Index in AOrder do
  begin
    if Names <> '' then
      Names := Names + ',';
    if TAtlasRanking.IsHeader(Index) then
      Names := Names + '#'
    else
      Names := Names + AItems[Index].Name;
  end;
  Selected := ASelected;
end;

procedure TFakeView.HideList;
begin
  Shown := False;
  Empty := False;
end;

procedure TFakeView.ShowEmpty(const APrefix: string; ATotal: Integer);
begin
  Shown := False;
  Empty := True;
  EmptyText := Format('%s/%d', [APrefix, ATotal]);
end;

function TFakeView.PageSize: Integer;
begin
  Result := 3;
end;

type
  /// <summary>Liefert sofort zwei Einträge aus dem Präfix und meldet die Liste als gekürzt.</summary>
  TPrefixProvider = class(TInterfacedObject, IAtlasCompletionProvider)
  public
    Queries: Integer;
    /// <summary>Liste vollständig melden (#616).</summary>
    CompleteList: Boolean;
    /// <summary>Jeden Eintrag als eigenes Teilergebnis liefern (#616).</summary>
    Staged: Boolean;
    procedure Query(const AContext: TAtlasContext; const ASink: IAtlasCompletionSink);
    procedure Cancel;
  end;

procedure TPrefixProvider.Query(const AContext: TAtlasContext; const ASink: IAtlasCompletionSink);
var
  First, Second: TAtlasCompletionItem;
begin
  Inc(Queries);
  First := Default(TAtlasCompletionItem);
  First.Name := AContext.Prefix + '1';
  Second := Default(TAtlasCompletionItem);
  Second.Name := AContext.Prefix + '2';
  if Staged then
  begin
    ASink.AddItems([First]);
    ASink.AddItems([Second]);
  end
  else
    ASink.AddItems([First, Second]);
  if not CompleteList then
    ASink.MarkIncomplete;
  ASink.Complete;
end;

procedure TPrefixProvider.Cancel;
begin
end;

function Item(const AName: string; ARank: Integer = 0): TAtlasCompletionItem;
begin
  Result := Default(TAtlasCompletionItem);
  Result.Name := AName;
  Result.Rank := ARank;
end;

function Context(const APrefix: string): TAtlasContext;
begin
  Result := Default(TAtlasContext);
  Result.FileName := 'C:\P\A.pas';
  Result.Prefix := APrefix;
end;

/// <summary>Arbeitet eingereihte Aufrufe ab, bis ACondition gilt oder die Zeit um ist.</summary>
function WaitFor(const ACondition: TFunc<Boolean>; ATimeoutMs: Cardinal = 3000): Boolean;
var
  Start: UInt64;
begin
  Start := TThread.GetTickCount64;
  repeat
    CheckSynchronize(5);
    if ACondition() then
      Exit(True);
  until TThread.GetTickCount64 - Start > ATimeoutMs;
  Result := False;
end;

{ TAtlasCompletionMatcherTests }

procedure TAtlasCompletionMatcherTests.RanksExactBeforePrefixBeforeWordStarts;
begin
  Assert.AreEqual(TAtlasCompletionMatcher.ScoreExact, TAtlasCompletionMatcher.Score('add', 'Add'));
  Assert.AreEqual(TAtlasCompletionMatcher.ScorePrefixCase, TAtlasCompletionMatcher.Score('Add', 'AddItem'));
  Assert.AreEqual(TAtlasCompletionMatcher.ScorePrefix, TAtlasCompletionMatcher.Score('add', 'AddItem'));
  Assert.AreEqual(TAtlasCompletionMatcher.ScoreWordStarts, TAtlasCompletionMatcher.Score('ai', 'AddItem'));
  Assert.AreEqual(TAtlasCompletionMatcher.ScoreSubstring, TAtlasCompletionMatcher.Score('dIt', 'AddItem'));
  Assert.AreEqual(TAtlasCompletionMatcher.NoMatch, TAtlasCompletionMatcher.Score('xy', 'AddItem'));
end;

procedure TAtlasCompletionMatcherTests.MatchesCamelCaseAndSubsequence;
begin
  Assert.AreEqual(TAtlasCompletionMatcher.ScoreWordStarts, TAtlasCompletionMatcher.Score('TSL', 'TStringList'));
  Assert.AreEqual(TAtlasCompletionMatcher.ScoreWordStarts, TAtlasCompletionMatcher.Score('gtc', 'Get_Tick_Count'));
  // Teilfolge nur an Wortgrenzen bzw. zusammenhängend.
  Assert.AreEqual(TAtlasCompletionMatcher.ScoreSubsequence, TAtlasCompletionMatcher.Score('stl', 'TStringList'));
  Assert.AreEqual(TAtlasCompletionMatcher.ScoreSubsequence, TAtlasCompletionMatcher.Score('', 'Beliebig'));
  // Verstreute Treffer sind Rauschen (Fall aus der IDE: "myLis" bei nicht deklariertem myList).
  Assert.AreEqual(TAtlasCompletionMatcher.NoMatch, TAtlasCompletionMatcher.Score('myLis', 'ERROR_TOO_MANY_LINKS'));
  Assert.AreEqual(TAtlasCompletionMatcher.NoMatch, TAtlasCompletionMatcher.Score('tsit', 'TStringList'));
end;

procedure TAtlasCompletionMatcherTests.FiltersAndKeepsSourceOrderOnTies;
var
  Items: TAtlasCompletionItems;
  Order: TArray<Integer>;
begin
  Items := [Item('Count', 2), Item('Capacity', 1), Item('Clear', 0), Item('Add', 3)];
  Order := TAtlasCompletionMatcher.Filter(Items, 'c');
  // Alle drei beginnen mit c: Reihenfolge der Quelle (Rank).
  Assert.AreEqual(3, Integer(Length(Order)));
  Assert.AreEqual('Clear', Items[Order[0]].Name);
  Assert.AreEqual('Capacity', Items[Order[1]].Name);
  Assert.AreEqual('Count', Items[Order[2]].Name);
  Order := TAtlasCompletionMatcher.Filter(Items, 'count');
  Assert.AreEqual('Count', Items[Order[0]].Name);
end;

{ TAtlasCompletionControllerTests }

procedure TAtlasCompletionControllerTests.ShowsItemsFilteredByPrefix;
var
  View: TFakeView;
  ViewRef: IAtlasCompletionView;
  Controller: TAtlasCompletionController;
begin
  View := TFakeView.Create;
  ViewRef := View;
  Controller := TAtlasCompletionController.Create(
    TAtlasFixedCompletionProvider.Create([Item('Add'), Item('Clear'), Item('Count')]) as IAtlasCompletionProvider,
    ViewRef);
  try
    Controller.Start(Context('C'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.IsTrue(View.Shown);
    Assert.AreEqual('Clear,Count', View.Names);
    Assert.AreEqual(0, View.Selected);
    Assert.IsTrue(Controller.Visible);
  finally
    Controller.Free;
  end;
end;

procedure TAtlasCompletionControllerTests.TypingRefiltersAndResetsSelection;
var
  View: TFakeView;
  ViewRef: IAtlasCompletionView;
  Controller: TAtlasCompletionController;
begin
  View := TFakeView.Create;
  ViewRef := View;
  Controller := TAtlasCompletionController.Create(
    TAtlasFixedCompletionProvider.Create([Item('Add'), Item('Clear'), Item('Count')]) as IAtlasCompletionProvider,
    ViewRef);
  try
    Controller.Start(Context(''));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.AreEqual('Add,Clear,Count', View.Names);
    Controller.HandleKey(TAtlasNavigationKey.Down);
    Assert.AreEqual(1, View.Selected);
    Controller.UpdatePrefix('co');
    Assert.AreEqual('Count', View.Names);
    Assert.AreEqual(0, View.Selected);
  finally
    Controller.Free;
  end;
end;

procedure TAtlasCompletionControllerTests.KeysMoveSelectionAndEnterCommits;
var
  View: TFakeView;
  ViewRef: IAtlasCompletionView;
  Controller: TAtlasCompletionController;
  Committed: string;
begin
  View := TFakeView.Create;
  ViewRef := View;
  Controller := TAtlasCompletionController.Create(
    TAtlasFixedCompletionProvider.Create([Item('A1'), Item('A2'), Item('A3'), Item('A4'), Item('A5')])
      as IAtlasCompletionProvider, ViewRef);
  try
    Committed := '';
    Controller.OnCommit :=
      procedure(const AItem: TAtlasCompletionItem)
      begin
        Committed := AItem.Name;
      end;
    Controller.Start(Context('A'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.IsTrue(Controller.HandleKey(TAtlasNavigationKey.Up));
    Assert.AreEqual(0, View.Selected, 'Oben bleibt oben');
    Controller.HandleKey(TAtlasNavigationKey.PageDown);
    Assert.AreEqual(2, View.Selected, 'Bild ab um PageSize - 1');
    Controller.HandleKey(TAtlasNavigationKey.Last);
    Assert.AreEqual(4, View.Selected);
    Controller.HandleKey(TAtlasNavigationKey.First);
    Controller.HandleKey(TAtlasNavigationKey.Down);
    Assert.IsTrue(Controller.HandleKey(TAtlasNavigationKey.Accept));
    Assert.AreEqual('A2', Committed);
    Assert.IsFalse(Controller.Active, 'Übernahme schließt');
    Assert.IsFalse(View.Shown);
  finally
    Controller.Free;
  end;
end;

procedure TAtlasCompletionControllerTests.EscapeClosesAndKeysPassThroughWhenClosed;
var
  View: TFakeView;
  ViewRef: IAtlasCompletionView;
  Controller: TAtlasCompletionController;
begin
  View := TFakeView.Create;
  ViewRef := View;
  Controller := TAtlasCompletionController.Create(
    TAtlasFixedCompletionProvider.Create([Item('Add')]) as IAtlasCompletionProvider, ViewRef);
  try
    Assert.IsFalse(Controller.HandleKey(TAtlasNavigationKey.Down), 'Geschlossen: Taste gehört dem Editor');
    Controller.Start(Context(''));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.IsTrue(Controller.HandleKey(TAtlasNavigationKey.Cancel));
    Assert.IsFalse(Controller.Active);
    Assert.IsFalse(View.Shown);
    Assert.IsFalse(Controller.HandleKey(TAtlasNavigationKey.Accept), 'Enter nach Esc gehört dem Editor');
  finally
    Controller.Free;
  end;
end;

procedure TAtlasCompletionControllerTests.EscapeBlocksAutomaticReopenInSameWord;
var
  View: TFakeView;
  ViewRef: IAtlasCompletionView;
  Controller: TAtlasCompletionController;
  Typed: TAtlasContext;
begin
  // #414: Nach Esc öffnet Weitertippen im selben Wort nicht automatisch; Strg+Leer schon.
  View := TFakeView.Create;
  ViewRef := View;
  Controller := TAtlasCompletionController.Create(
    TAtlasFixedCompletionProvider.Create([Item('Add')]) as IAtlasCompletionProvider, ViewRef);
  try
    Controller.Start(Context('A'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.IsTrue(Controller.HandleKey(TAtlasNavigationKey.Cancel));
    Typed := Context('Ad');
    Typed.Character := Typed.Character + 1;
    Typed.Automatic := True;
    Assert.IsTrue(Controller.Dismissed(Typed));
    Controller.Start(Typed);
    Assert.IsFalse(Controller.Active, 'automatisch im selben Wort: bleibt zu');
    // Neues Wort: wieder automatisch.
    Typed.Character := Typed.Character + 5;
    Assert.IsFalse(Controller.Dismissed(Typed));
    // Strg+Leer im gesperrten Wort öffnet und hebt die Sperre auf.
    Typed := Context('Ad');
    Typed.Character := Typed.Character + 1;
    Controller.Start(Typed);
    Assert.IsTrue(Controller.Active, 'Strg+Leer öffnet');
    Controller.Close;
    Typed.Automatic := True;
    Assert.IsFalse(Controller.Dismissed(Typed), 'Schließen ohne Esc sperrt nicht');
  finally
    Controller.Free;
  end;
end;

procedure TAtlasCompletionControllerTests.NoMatchShowsEmptyState;
var
  View: TFakeView;
  ViewRef: IAtlasCompletionView;
  Controller: TAtlasCompletionController;
begin
  View := TFakeView.Create;
  ViewRef := View;
  Controller := TAtlasCompletionController.Create(
    TAtlasFixedCompletionProvider.Create([Item('Add'), Item('Clear')]) as IAtlasCompletionProvider, ViewRef);
  try
    Controller.Start(Context('a'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    // #423: "Lines.Axq" zeigt den leeren Zustand, Rücktaste bis "Lines.A" wieder Treffer.
    Controller.UpdatePrefix('axq');
    Assert.IsTrue(View.Empty);
    Assert.AreEqual('axq/2', View.EmptyText);
    Assert.IsTrue(Controller.Active);
    Assert.IsFalse(Controller.HandleKey(TAtlasNavigationKey.Accept), 'Ohne Treffer gehört Enter dem Editor');
    Assert.IsFalse(Controller.HandleKey(TAtlasNavigationKey.Down), 'Ohne Treffer gehören Pfeile dem Editor');
    Controller.UpdatePrefix('a');
    Assert.IsTrue(View.Shown);
    Assert.IsFalse(View.Empty);
    Assert.AreEqual('Add,Clear', View.Names);
  finally
    Controller.Free;
  end;
end;

procedure TAtlasCompletionControllerTests.EmptyResultShowsEmptyStateUntilEscape;
var
  View: TFakeView;
  ViewRef: IAtlasCompletionView;
  Controller: TAtlasCompletionController;
begin
  View := TFakeView.Create;
  ViewRef := View;
  Controller := TAtlasCompletionController.Create(
    TAtlasFixedCompletionProvider.Create(nil) as IAtlasCompletionProvider, ViewRef);
  try
    Controller.Start(Context('mylist'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.IsTrue(View.Empty, 'Nichts gefunden: leerer Zustand statt Verschwinden');
    Assert.AreEqual('mylist/0', View.EmptyText);
    Assert.IsTrue(Controller.HandleKey(TAtlasNavigationKey.Cancel), 'Esc schließt den leeren Zustand');
    Assert.IsFalse(Controller.Active);
    Assert.IsFalse(View.Empty);
  finally
    Controller.Free;
  end;
end;

procedure TAtlasCompletionControllerTests.CommitCharacterOnlyForClearMatch;
var
  View: TFakeView;
  ViewRef: IAtlasCompletionView;
  Controller: TAtlasCompletionController;
  Snippet: TAtlasCompletionItem;
begin
  View := TFakeView.Create;
  ViewRef := View;
  // Code-Vorlage (#51): nie über ein Zeichen übernommen.
  Snippet := Item('while');
  Snippet.Snippet := 'while ${1:Condition} do';
  Controller := TAtlasCompletionController.Create(
    TAtlasFixedCompletionProvider.Create([Item('Add'), Item('AddStrings'), Item('Exchange'), Snippet])
      as IAtlasCompletionProvider, ViewRef);
  try
    Controller.Start(Context(''));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.IsFalse(Controller.CanCommitOnCharacter, 'Ohne getipptes Wort übernimmt ";" nichts');
    Controller.UpdatePrefix('A');
    Assert.IsTrue(Controller.CanCommitOnCharacter, '"Lines.A" + "(" ergibt "Lines.Add("');
    Controller.UpdatePrefix('as');
    Assert.IsTrue(Controller.CanCommitOnCharacter, 'Wortanfänge: AddStrings');
    Controller.UpdatePrefix('xch');
    Assert.IsFalse(Controller.CanCommitOnCharacter, 'Nur Teilstring von Exchange: Zeichen bleibt allein');
    Controller.UpdatePrefix('while');
    Assert.IsFalse(Controller.CanCommitOnCharacter, '"while(" setzt keine Vorlage ein');
  finally
    Controller.Free;
  end;
end;
procedure TAtlasCompletionControllerTests.TypoSuggestionsTakeOnlyEnter;
var
  View: TFakeView;
  ViewRef: IAtlasCompletionView;
  Controller: TAtlasCompletionController;
  Committed: string;
begin
  // #485, Abnahme: "Lenght" zeigt Length unter „Meintest du“ statt des leeren Zustands; ";" übernimmt
  // nichts, Enter übernimmt.
  View := TFakeView.Create;
  ViewRef := View;
  Controller := TAtlasCompletionController.Create(
    TAtlasFixedCompletionProvider.Create([Item('Length'), Item('Low'), Item('High')])
      as IAtlasCompletionProvider, ViewRef);
  try
    Committed := '';
    Controller.OnCommit :=
      procedure(const AItem: TAtlasCompletionItem)
      begin
        Committed := AItem.Name;
      end;
    Controller.Start(Context(''));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Controller.UpdatePrefix('Lenght');
    Assert.IsFalse(View.Empty, 'Vorschläge statt des Hinweistexts');
    Assert.AreEqual('#,Length', View.Names);
    Assert.AreEqual(1, View.Selected, 'Überschrift wird übersprungen');
    Assert.IsFalse(Controller.CanCommitOnCharacter, '";" fügt nur das Zeichen ein');
    Assert.IsTrue(Controller.HandleKey(TAtlasNavigationKey.Accept));
    Assert.AreEqual('Length', Committed);
  finally
    Controller.Free;
  end;
end;

procedure TAtlasCompletionControllerTests.ItemsAfterCloseAreDropped;
var
  View: TFakeView;
  ViewRef: IAtlasCompletionView;
  Controller: TAtlasCompletionController;
begin
  View := TFakeView.Create;
  ViewRef := View;
  Controller := TAtlasCompletionController.Create(
    TAtlasFixedCompletionProvider.Create([Item('Spaet')], 100) as IAtlasCompletionProvider, ViewRef);
  try
    Controller.Start(Context(''));
    Controller.Close;
    WaitFor(
      function: Boolean
      begin
        Result := False;
      end, 300);
    Assert.AreEqual(0, View.ShowCount);
    Assert.IsFalse(Controller.Active);
  finally
    Controller.Free;
  end;
end;

procedure TAtlasCompletionControllerTests.TruncatedListIsRequeried;
var
  View: TFakeView;
  ViewRef: IAtlasCompletionView;
  Provider: TPrefixProvider;
  ProviderRef: IAtlasCompletionProvider;
  Controller: TAtlasCompletionController;
begin
  View := TFakeView.Create;
  ViewRef := View;
  Provider := TPrefixProvider.Create;
  ProviderRef := Provider;
  Controller := TAtlasCompletionController.Create(ProviderRef, ViewRef);
  try
    Controller.Start(Context('ab'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.AreEqual('ab1,ab2', View.Names);
    Assert.IsTrue(Controller.Incomplete, 'Gekürzte Liste gemeldet');
    // #431: Weitertippen fragt neu, die neue Liste ersetzt die alte.
    Controller.Requery(Context('abc'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.AreEqual(2, Provider.Queries);
    Assert.AreEqual('abc1,abc2', View.Names);
    Assert.IsTrue(View.Shown);
  finally
    Controller.Free;
  end;
end;

procedure TAtlasCompletionControllerTests.CompleteListFiltersLocallyUntilPrefixShrinks;
var
  View: TFakeView;
  ViewRef: IAtlasCompletionView;
  Provider: TPrefixProvider;
  ProviderRef: IAtlasCompletionProvider;
  Controller: TAtlasCompletionController;
begin
  View := TFakeView.Create;
  ViewRef := View;
  Provider := TPrefixProvider.Create;
  Provider.CompleteList := True;
  ProviderRef := Provider;
  Controller := TAtlasCompletionController.Create(ProviderRef, ViewRef);
  try
    Controller.Start(Context('ab'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.IsFalse(Controller.Incomplete);
    // Der Server hat nach "ab" gefiltert: Weitertippen filtert lokal, kürzer oder anders fragt neu (#616).
    Assert.IsFalse(Controller.NeedsQuery('abc'));
    Assert.IsFalse(Controller.NeedsQuery('ABx'), 'Groß- und Kleinschreibung egal');
    Assert.IsTrue(Controller.NeedsQuery('a'));
    Assert.IsTrue(Controller.NeedsQuery('xb'));
    Controller.UpdatePrefix('ab1');
    Assert.AreEqual(1, Provider.Queries);
    // Lokal gefiltert; ab2 steht als Tippfehler-Kandidat unter „Meintest du“ (#485, # = Überschrift).
    Assert.AreEqual('ab1,#,ab2', View.Names);
    Controller.Close;
    Assert.IsFalse(Controller.NeedsQuery('a'), 'geschlossen');
  finally
    Controller.Free;
  end;
end;

procedure TAtlasCompletionControllerTests.PartialResultsReplaceThenAppend;
var
  View: TFakeView;
  ViewRef: IAtlasCompletionView;
  Provider: TPrefixProvider;
  ProviderRef: IAtlasCompletionProvider;
  Controller: TAtlasCompletionController;
begin
  View := TFakeView.Create;
  ViewRef := View;
  Provider := TPrefixProvider.Create;
  Provider.Staged := True;
  ProviderRef := Provider;
  Controller := TAtlasCompletionController.Create(ProviderRef, ViewRef);
  try
    Controller.Start(Context('ab'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.AreEqual('ab1,ab2', View.Names);
    // Requery: Das erste Teil ersetzt die alte Liste, das zweite hängt an (#616).
    Controller.Requery(Context('a'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.AreEqual('a1,a2', View.Names);
  finally
    Controller.Free;
  end;
end;

procedure TAtlasCompletionControllerTests.RequeryKeepsSelectedEntry;
var
  View: TFakeView;
  ViewRef: IAtlasCompletionView;
  Controller: TAtlasCompletionController;
begin
  View := TFakeView.Create;
  ViewRef := View;
  Controller := TAtlasCompletionController.Create(TPrefixProvider.Create as IAtlasCompletionProvider, ViewRef);
  try
    Controller.Start(Context('ab'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Controller.HandleKey(TAtlasNavigationKey.Down);
    Assert.AreEqual(1, View.Selected);
    // Neue Einträge verschieben die Auswahl nicht (#431).
    Controller.Requery(Context('ab'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.AreEqual('ab1,ab2', View.Names);
    Assert.AreEqual(1, View.Selected);
  finally
    Controller.Free;
  end;
end;

initialization  TDUnitX.RegisterTestFixture(TAtlasCompletionMatcherTests);
  TDUnitX.RegisterTestFixture(TAtlasCompletionControllerTests);

end.
