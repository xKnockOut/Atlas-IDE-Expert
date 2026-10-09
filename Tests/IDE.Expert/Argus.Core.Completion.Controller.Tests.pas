unit Argus.Core.Completion.Controller.Tests;

// Tests für Filtern (#409) und Ablauf der Vervollständigung (#410, #414) ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TArgusCompletionMatcherTests = class
  public
    [Test]
    procedure RanksExactBeforePrefixBeforeWordStarts;
    [Test]
    procedure MatchesCamelCaseAndSubsequence;
    [Test]
    procedure FiltersAndKeepsSourceOrderOnTies;
  end;

  [TestFixture]
  TArgusCompletionControllerTests = class
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
    procedure NoMatchShowsEmptyState;
    [Test]
    procedure EmptyResultShowsEmptyStateUntilEscape;
    [Test]
    procedure CommitCharacterOnlyForClearMatch;
    [Test]
    procedure ItemsAfterCloseAreDropped;
    [Test]
    procedure TruncatedListIsRequeried;
    [Test]
    procedure RequeryKeepsSelectedEntry;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Argus.Core.Completion.Contract,
  Argus.Core.Completion.Matching,
  Argus.Core.Completion.Controller,
  Argus.Core.Completion.Ranking,
  Argus.Core.Completion.Usage,
  Argus.Core.Completion.Providers.Fixed;

type
  TFakeView = class(TInterfacedObject, IArgusCompletionView)
  public
    Shown: Boolean;
    ShowCount: Integer;
    Names: string;
    Selected: Integer;
    Empty: Boolean;
    EmptyText: string;
    procedure ShowList(const AItems: TArgusCompletionItems; const AOrder: TArray<Integer>; ASelected: Integer;
      const APattern: string);
    procedure HideList;
    procedure ShowEmpty(const APrefix: string; ATotal: Integer);
    function PageSize: Integer;
    procedure ShowChips(const ACounts: TArgusChipCounts; AActive: TArgusChip; AVisible: Boolean);
  end;

procedure TFakeView.ShowChips(const ACounts: TArgusChipCounts; AActive: TArgusChip; AVisible: Boolean);
begin
end;

procedure TFakeView.ShowList(const AItems: TArgusCompletionItems; const AOrder: TArray<Integer>;
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
    if Index = TArgusRanking.Header then
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
  TPrefixProvider = class(TInterfacedObject, IArgusCompletionProvider)
  public
    Queries: Integer;
    procedure Query(const AContext: TArgusContext; const ASink: IArgusCompletionSink);
    procedure Cancel;
  end;

procedure TPrefixProvider.Query(const AContext: TArgusContext; const ASink: IArgusCompletionSink);
var
  First, Second: TArgusCompletionItem;
begin
  Inc(Queries);
  First := Default(TArgusCompletionItem);
  First.Name := AContext.Prefix + '1';
  Second := Default(TArgusCompletionItem);
  Second.Name := AContext.Prefix + '2';
  ASink.AddItems([First, Second]);
  ASink.MarkIncomplete;
  ASink.Complete;
end;

procedure TPrefixProvider.Cancel;
begin
end;

function Item(const AName: string; ARank: Integer = 0): TArgusCompletionItem;
begin
  Result := Default(TArgusCompletionItem);
  Result.Name := AName;
  Result.Rank := ARank;
end;

function Context(const APrefix: string): TArgusContext;
begin
  Result := Default(TArgusContext);
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

{ TArgusCompletionMatcherTests }

procedure TArgusCompletionMatcherTests.RanksExactBeforePrefixBeforeWordStarts;
begin
  Assert.AreEqual(TArgusCompletionMatcher.ScoreExact, TArgusCompletionMatcher.Score('add', 'Add'));
  Assert.AreEqual(TArgusCompletionMatcher.ScorePrefixCase, TArgusCompletionMatcher.Score('Add', 'AddItem'));
  Assert.AreEqual(TArgusCompletionMatcher.ScorePrefix, TArgusCompletionMatcher.Score('add', 'AddItem'));
  Assert.AreEqual(TArgusCompletionMatcher.ScoreWordStarts, TArgusCompletionMatcher.Score('ai', 'AddItem'));
  Assert.AreEqual(TArgusCompletionMatcher.ScoreSubstring, TArgusCompletionMatcher.Score('dIt', 'AddItem'));
  Assert.AreEqual(TArgusCompletionMatcher.NoMatch, TArgusCompletionMatcher.Score('xy', 'AddItem'));
end;

procedure TArgusCompletionMatcherTests.MatchesCamelCaseAndSubsequence;
begin
  Assert.AreEqual(TArgusCompletionMatcher.ScoreWordStarts, TArgusCompletionMatcher.Score('TSL', 'TStringList'));
  Assert.AreEqual(TArgusCompletionMatcher.ScoreWordStarts, TArgusCompletionMatcher.Score('gtc', 'Get_Tick_Count'));
  // Teilfolge nur an Wortgrenzen bzw. zusammenhängend.
  Assert.AreEqual(TArgusCompletionMatcher.ScoreSubsequence, TArgusCompletionMatcher.Score('stl', 'TStringList'));
  Assert.AreEqual(TArgusCompletionMatcher.ScoreSubsequence, TArgusCompletionMatcher.Score('', 'Beliebig'));
  // Verstreute Treffer sind Rauschen (Fall aus der IDE: "myLis" bei nicht deklariertem myList).
  Assert.AreEqual(TArgusCompletionMatcher.NoMatch, TArgusCompletionMatcher.Score('myLis', 'ERROR_TOO_MANY_LINKS'));
  Assert.AreEqual(TArgusCompletionMatcher.NoMatch, TArgusCompletionMatcher.Score('tsit', 'TStringList'));
end;

procedure TArgusCompletionMatcherTests.FiltersAndKeepsSourceOrderOnTies;
var
  Items: TArgusCompletionItems;
  Order: TArray<Integer>;
begin
  Items := [Item('Count', 2), Item('Capacity', 1), Item('Clear', 0), Item('Add', 3)];
  Order := TArgusCompletionMatcher.Filter(Items, 'c');
  // Alle drei beginnen mit c: Reihenfolge der Quelle (Rank).
  Assert.AreEqual(3, Integer(Length(Order)));
  Assert.AreEqual('Clear', Items[Order[0]].Name);
  Assert.AreEqual('Capacity', Items[Order[1]].Name);
  Assert.AreEqual('Count', Items[Order[2]].Name);
  Order := TArgusCompletionMatcher.Filter(Items, 'count');
  Assert.AreEqual('Count', Items[Order[0]].Name);
end;

{ TArgusCompletionControllerTests }

procedure TArgusCompletionControllerTests.ShowsItemsFilteredByPrefix;
var
  View: TFakeView;
  ViewRef: IArgusCompletionView;
  Controller: TArgusCompletionController;
begin
  View := TFakeView.Create;
  ViewRef := View;
  Controller := TArgusCompletionController.Create(
    TArgusFixedCompletionProvider.Create([Item('Add'), Item('Clear'), Item('Count')]) as IArgusCompletionProvider,
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

procedure TArgusCompletionControllerTests.TypingRefiltersAndResetsSelection;
var
  View: TFakeView;
  ViewRef: IArgusCompletionView;
  Controller: TArgusCompletionController;
begin
  View := TFakeView.Create;
  ViewRef := View;
  Controller := TArgusCompletionController.Create(
    TArgusFixedCompletionProvider.Create([Item('Add'), Item('Clear'), Item('Count')]) as IArgusCompletionProvider,
    ViewRef);
  try
    Controller.Start(Context(''));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.AreEqual('Add,Clear,Count', View.Names);
    Controller.HandleKey(TArgusNavigationKey.Down);
    Assert.AreEqual(1, View.Selected);
    Controller.UpdatePrefix('co');
    Assert.AreEqual('Count', View.Names);
    Assert.AreEqual(0, View.Selected);
  finally
    Controller.Free;
  end;
end;

procedure TArgusCompletionControllerTests.KeysMoveSelectionAndEnterCommits;
var
  View: TFakeView;
  ViewRef: IArgusCompletionView;
  Controller: TArgusCompletionController;
  Committed: string;
begin
  View := TFakeView.Create;
  ViewRef := View;
  Controller := TArgusCompletionController.Create(
    TArgusFixedCompletionProvider.Create([Item('A1'), Item('A2'), Item('A3'), Item('A4'), Item('A5')])
      as IArgusCompletionProvider, ViewRef);
  try
    Committed := '';
    Controller.OnCommit :=
      procedure(const AItem: TArgusCompletionItem)
      begin
        Committed := AItem.Name;
      end;
    Controller.Start(Context('A'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.IsTrue(Controller.HandleKey(TArgusNavigationKey.Up));
    Assert.AreEqual(0, View.Selected, 'Oben bleibt oben');
    Controller.HandleKey(TArgusNavigationKey.PageDown);
    Assert.AreEqual(2, View.Selected, 'Bild ab um PageSize - 1');
    Controller.HandleKey(TArgusNavigationKey.Last);
    Assert.AreEqual(4, View.Selected);
    Controller.HandleKey(TArgusNavigationKey.First);
    Controller.HandleKey(TArgusNavigationKey.Down);
    Assert.IsTrue(Controller.HandleKey(TArgusNavigationKey.Accept));
    Assert.AreEqual('A2', Committed);
    Assert.IsFalse(Controller.Active, 'Übernahme schließt');
    Assert.IsFalse(View.Shown);
  finally
    Controller.Free;
  end;
end;

procedure TArgusCompletionControllerTests.EscapeClosesAndKeysPassThroughWhenClosed;
var
  View: TFakeView;
  ViewRef: IArgusCompletionView;
  Controller: TArgusCompletionController;
begin
  View := TFakeView.Create;
  ViewRef := View;
  Controller := TArgusCompletionController.Create(
    TArgusFixedCompletionProvider.Create([Item('Add')]) as IArgusCompletionProvider, ViewRef);
  try
    Assert.IsFalse(Controller.HandleKey(TArgusNavigationKey.Down), 'Geschlossen: Taste gehört dem Editor');
    Controller.Start(Context(''));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.IsTrue(Controller.HandleKey(TArgusNavigationKey.Cancel));
    Assert.IsFalse(Controller.Active);
    Assert.IsFalse(View.Shown);
    Assert.IsFalse(Controller.HandleKey(TArgusNavigationKey.Accept), 'Enter nach Esc gehört dem Editor');
  finally
    Controller.Free;
  end;
end;

procedure TArgusCompletionControllerTests.NoMatchShowsEmptyState;
var
  View: TFakeView;
  ViewRef: IArgusCompletionView;
  Controller: TArgusCompletionController;
begin
  View := TFakeView.Create;
  ViewRef := View;
  Controller := TArgusCompletionController.Create(
    TArgusFixedCompletionProvider.Create([Item('Add'), Item('Clear')]) as IArgusCompletionProvider, ViewRef);
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
    Assert.IsFalse(Controller.HandleKey(TArgusNavigationKey.Accept), 'Ohne Treffer gehört Enter dem Editor');
    Assert.IsFalse(Controller.HandleKey(TArgusNavigationKey.Down), 'Ohne Treffer gehören Pfeile dem Editor');
    Controller.UpdatePrefix('a');
    Assert.IsTrue(View.Shown);
    Assert.IsFalse(View.Empty);
    Assert.AreEqual('Add,Clear', View.Names);
  finally
    Controller.Free;
  end;
end;

procedure TArgusCompletionControllerTests.EmptyResultShowsEmptyStateUntilEscape;
var
  View: TFakeView;
  ViewRef: IArgusCompletionView;
  Controller: TArgusCompletionController;
begin
  View := TFakeView.Create;
  ViewRef := View;
  Controller := TArgusCompletionController.Create(
    TArgusFixedCompletionProvider.Create(nil) as IArgusCompletionProvider, ViewRef);
  try
    Controller.Start(Context('mylist'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.IsTrue(View.Empty, 'Nichts gefunden: leerer Zustand statt Verschwinden');
    Assert.AreEqual('mylist/0', View.EmptyText);
    Assert.IsTrue(Controller.HandleKey(TArgusNavigationKey.Cancel), 'Esc schließt den leeren Zustand');
    Assert.IsFalse(Controller.Active);
    Assert.IsFalse(View.Empty);
  finally
    Controller.Free;
  end;
end;

procedure TArgusCompletionControllerTests.CommitCharacterOnlyForClearMatch;
var
  View: TFakeView;
  ViewRef: IArgusCompletionView;
  Controller: TArgusCompletionController;
begin
  View := TFakeView.Create;
  ViewRef := View;
  Controller := TArgusCompletionController.Create(
    TArgusFixedCompletionProvider.Create([Item('Add'), Item('AddStrings'), Item('Exchange')])
      as IArgusCompletionProvider, ViewRef);
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
  finally
    Controller.Free;
  end;
end;
procedure TArgusCompletionControllerTests.ItemsAfterCloseAreDropped;
var
  View: TFakeView;
  ViewRef: IArgusCompletionView;
  Controller: TArgusCompletionController;
begin
  View := TFakeView.Create;
  ViewRef := View;
  Controller := TArgusCompletionController.Create(
    TArgusFixedCompletionProvider.Create([Item('Spaet')], 100) as IArgusCompletionProvider, ViewRef);
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

procedure TArgusCompletionControllerTests.TruncatedListIsRequeried;
var
  View: TFakeView;
  ViewRef: IArgusCompletionView;
  Provider: TPrefixProvider;
  ProviderRef: IArgusCompletionProvider;
  Controller: TArgusCompletionController;
begin
  View := TFakeView.Create;
  ViewRef := View;
  Provider := TPrefixProvider.Create;
  ProviderRef := Provider;
  Controller := TArgusCompletionController.Create(ProviderRef, ViewRef);
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

procedure TArgusCompletionControllerTests.RequeryKeepsSelectedEntry;
var
  View: TFakeView;
  ViewRef: IArgusCompletionView;
  Controller: TArgusCompletionController;
begin
  View := TFakeView.Create;
  ViewRef := View;
  Controller := TArgusCompletionController.Create(TPrefixProvider.Create as IArgusCompletionProvider, ViewRef);
  try
    Controller.Start(Context('ab'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Controller.HandleKey(TArgusNavigationKey.Down);
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

initialization  TDUnitX.RegisterTestFixture(TArgusCompletionMatcherTests);
  TDUnitX.RegisterTestFixture(TArgusCompletionControllerTests);

end.
