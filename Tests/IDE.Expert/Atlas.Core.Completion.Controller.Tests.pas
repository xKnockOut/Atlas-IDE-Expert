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
    procedure SyntaxNoticeReachesView;
    [Test]
    procedure PartialResultsReplaceThenAppend;
    [Test]
    procedure InaccessibleNamedThenRevealed;
    [Test]
    procedure InaccessibleOnlyShowsEmptyStateWithNotice;
    /// <summary>#2108: Enter auf einem nicht sichtbaren Mitglied mit Befehl schließt die Liste und meldet es
    /// über OnInaccessible statt OnCommit.</summary>
    [Test]
    procedure InaccessibleWithCommandOffersActions;
  end;

  /// <summary>Diagnosemodus (#479) über den ganzen Ablauf: Quellen, Filtern, erste Liste.</summary>
  [TestFixture]
  TAtlasCompletionTimingTests = class
  public
    [TearDown]
    procedure TearDown;
    [Test]
    procedure DelayedProviderIsOverBudget;
    [Test]
    procedure NoSourceTextInMeasurements;
    [Test]
    procedure OffMeasuresNothing;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.Matching,
  Atlas.Core.Completion.Controller,
  Atlas.Core.Completion.Ranking,
  Atlas.Core.Completion.Composite,
  Atlas.Core.Completion.Providers.Fixed,
  Atlas.Core.Diagnostics.Timing;

type
  TFakeView = class(TInterfacedObject, IAtlasCompletionView, IAtlasCompletionSyntaxView)
  public
    Shown: Boolean;
    /// <summary>Hinweis bei unvollständigem Code (#457) und wie oft er kam.</summary>
    Syntax: TAtlasSyntaxNotice;
    SyntaxCount: Integer;
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
    procedure ShowSyntax(const ANotice: TAtlasSyntaxNotice);
  end;

procedure TFakeView.ShowSyntax(const ANotice: TAtlasSyntaxNotice);
begin
  Syntax := ANotice;
  Inc(SyntaxCount);
end;

procedure TFakeView.ShowChips(const ACounts: TAtlasChipCounts; AActive: TAtlasChip; AVisible: Boolean);
begin
end;

procedure TFakeView.ShowList(const AItems: TAtlasCompletionItems; const AOrder: TArray<Integer>;
  ASelected: Integer; const APattern: string);
var
  mIndex: Integer;
begin
  Shown := True;
  Empty := False;
  Inc(ShowCount);
  Names := '';
  for mIndex in AOrder do
  begin
    if Names <> '' then
    begin
      Names := Names + ',';
    end;
    if TAtlasRanking.IsHeader(mIndex) then
    begin
      Names := Names + '#';
    end
    else
    begin
      Names := Names + AItems[mIndex].Name;
    end;
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
  /// <summary>Ansicht, die auch die nicht sichtbaren Treffer (#2108) mitschreibt.</summary>
  TFakeHiddenView = class(TFakeView, IAtlasCompletionHiddenView)
  public
    HiddenNames: string;
    procedure ShowInaccessible(const AItems: TAtlasCompletionItems);
  end;

procedure TFakeHiddenView.ShowInaccessible(const AItems: TAtlasCompletionItems);
var
  mItem: TAtlasCompletionItem;
begin
  HiddenNames := '';
  for mItem in AItems do
  begin
    if HiddenNames <> '' then
    begin
      HiddenNames := HiddenNames + ',';
    end;
    HiddenNames := HiddenNames + mItem.Name;
  end;
end;

/// <summary>FEnde sichtbar, FEintraege nur wegen der Sichtbarkeit (private) nicht.</summary>
function HiddenItems: TAtlasCompletionItems;
var
  mHidden: TAtlasCompletionItem;
begin
  mHidden := Default(TAtlasCompletionItem);
  mHidden.Name := 'FEintraege';
  mHidden.Inaccessible := 'private';
  mHidden.DeclaringClass := 'TZaehler';
  mHidden.Rank := 1;
  Result := [Default(TAtlasCompletionItem), mHidden];
  Result[0].Name := 'FEnde';
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
    /// <summary>Hinweis bei unvollständigem Code (#457); Sure = keiner.</summary>
    Syntax: TAtlasSyntaxNotice;
    procedure Query(const AContext: TAtlasContext; const ASink: IAtlasCompletionSink);
    procedure Cancel;
  end;

procedure TPrefixProvider.Query(const AContext: TAtlasContext; const ASink: IAtlasCompletionSink);
var
  mFirst, mSecond: TAtlasCompletionItem;
begin
  Inc(Queries);
  mFirst := Default(TAtlasCompletionItem);
  mFirst.Name := AContext.Prefix + '1';
  mSecond := Default(TAtlasCompletionItem);
  mSecond.Name := AContext.Prefix + '2';
  if Staged then
  begin
    ASink.AddItems([mFirst]);
    ASink.AddItems([mSecond]);
  end
  else
  begin
    ASink.AddItems([mFirst, mSecond]);
  end;
  if not CompleteList then
  begin
    ASink.MarkIncomplete;
  end;
  if Syntax.Trust <> TAtlasSyntaxTrust.Sure then
  begin
    ASink.MarkSyntax(Syntax);
  end;
  ASink.Complete;
end;

procedure TPrefixProvider.Cancel;
begin
end;

function Item(const AName: string; ARank: Integer): TAtlasCompletionItem; overload;
begin
  Result := Default(TAtlasCompletionItem);
  Result.Name := AName;
  Result.Rank := ARank;
end;

function Item(const AName: string): TAtlasCompletionItem; overload;
begin
  Result := Item(AName, 0);
end;

function Context(const APrefix: string): TAtlasContext;
begin
  Result := Default(TAtlasContext);
  Result.FileName := 'C:\P\A.pas';
  Result.Prefix := APrefix;
end;

/// <summary>Arbeitet eingereihte Aufrufe ab, bis ACondition gilt oder ATimeoutMs um sind.</summary>
function WaitWithin(const ACondition: TFunc<Boolean>; ATimeoutMs: Cardinal): Boolean;
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
  until TThread.GetTickCount64 - mStart > ATimeoutMs;
  Result := False;
end;

/// <summary>Wie WaitWithin mit der üblichen Wartezeit von drei Sekunden.</summary>
function WaitFor(const ACondition: TFunc<Boolean>): Boolean;
const
  cTimeoutMs = 3000;
begin
  Result := WaitWithin(ACondition, cTimeoutMs);
end;

{ TAtlasCompletionMatcherTests }

procedure TAtlasCompletionControllerTests.InaccessibleNamedThenRevealed;
var
  mView: TFakeHiddenView;
  mViewRef: IAtlasCompletionView;
  mController: TAtlasCompletionController;
  mCommitted: string;
begin
  mView := TFakeHiddenView.Create;
  mViewRef := mView;
  mController := TAtlasCompletionController.Create(
    TAtlasFixedCompletionProvider.Create(HiddenItems) as IAtlasCompletionProvider, mViewRef);
  try
    mCommitted := '';
    mController.OnCommit :=
      procedure(const AItem: TAtlasCompletionItem)
      begin
        mCommitted := AItem.Name;
      end;
    mController.Start(Context('FE'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not mController.Loading;
      end));
    // #2108: Die Liste zeigt nur FEnde, die Fußzeile nennt FEintraege.
    Assert.AreEqual('FEnde', mView.Names);
    Assert.AreEqual('FEintraege', mView.HiddenNames);
    Assert.IsTrue(mController.CanRevealInaccessible);
    // Zweites Strg+Leertaste: ausgegraut am Ende, mit Überschrift; die Fußzeile nennt sie nicht mehr.
    Assert.IsTrue(mController.RevealInaccessible);
    Assert.AreEqual('FEnde,#,FEintraege', mView.Names);
    Assert.AreEqual('', mView.HiddenNames);
    Assert.IsFalse(mController.CanRevealInaccessible);
    // Enter auf dem nicht sichtbaren Mitglied setzt nichts ein; die Liste bleibt offen.
    mController.HandleKey(TAtlasNavigationKey.Last);
    mController.HandleKey(TAtlasNavigationKey.Accept);
    Assert.AreEqual('', mCommitted);
    Assert.IsTrue(mController.Active);
  finally
    mController.Free;
  end;
end;

procedure TAtlasCompletionControllerTests.InaccessibleWithCommandOffersActions;
var
  mItems: TAtlasCompletionItems;
  mView: TFakeHiddenView;
  mViewRef: IAtlasCompletionView;
  mController: TAtlasCompletionController;
  mCommitted, mOffered: string;
begin
  mItems := HiddenItems;
  mItems[1].Command := 'atlas.server.memberActions';
  mView := TFakeHiddenView.Create;
  mViewRef := mView;
  mController := TAtlasCompletionController.Create(
    TAtlasFixedCompletionProvider.Create(mItems) as IAtlasCompletionProvider, mViewRef);
  try
    mCommitted := '';
    mOffered := '';
    mController.OnCommit :=
      procedure(const AItem: TAtlasCompletionItem)
      begin
        mCommitted := AItem.Name;
      end;
    mController.OnInaccessible :=
      procedure(const AItem: TAtlasCompletionItem)
      begin
        mOffered := AItem.Name;
      end;
    mController.Start(Context('FE'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not mController.Loading;
      end));
    Assert.IsTrue(mController.RevealInaccessible);
    mController.HandleKey(TAtlasNavigationKey.Last);
    mController.HandleKey(TAtlasNavigationKey.Accept);
    Assert.AreEqual('', mCommitted);
    Assert.AreEqual('FEintraege', mOffered);
    Assert.IsFalse(mController.Active);
  finally
    mController.Free;
  end;
end;

procedure TAtlasCompletionControllerTests.InaccessibleOnlyShowsEmptyStateWithNotice;
var
  mView: TFakeHiddenView;
  mViewRef: IAtlasCompletionView;
  mController: TAtlasCompletionController;
begin
  mView := TFakeHiddenView.Create;
  mViewRef := mView;
  mController := TAtlasCompletionController.Create(
    TAtlasFixedCompletionProvider.Create(HiddenItems) as IAtlasCompletionProvider, mViewRef);
  try
    mController.Start(Context('FEi'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not mController.Loading;
      end));
    Assert.IsTrue(mView.Empty);
    Assert.AreEqual('FEintraege', mView.HiddenNames);
    Assert.IsTrue(mController.RevealInaccessible);
    Assert.IsTrue(mView.Shown);
    Assert.AreEqual('#,FEintraege', mView.Names);
    // Ohne Präfix nennt die Fußzeile nichts.
    mController.UpdatePrefix('');
    Assert.AreEqual('', mView.HiddenNames);
  finally
    mController.Free;
  end;
end;

procedure TAtlasCompletionMatcherTests.RanksExactBeforePrefixBeforeWordStarts;
begin
  Assert.AreEqual(TAtlasCompletionMatcher.cScoreExact, TAtlasCompletionMatcher.Score('add', 'Add'));
  Assert.AreEqual(TAtlasCompletionMatcher.cScorePrefixCase, TAtlasCompletionMatcher.Score('Add', 'AddItem'));
  Assert.AreEqual(TAtlasCompletionMatcher.cScorePrefix, TAtlasCompletionMatcher.Score('add', 'AddItem'));
  Assert.AreEqual(TAtlasCompletionMatcher.cScoreWordStarts, TAtlasCompletionMatcher.Score('ai', 'AddItem'));
  Assert.AreEqual(TAtlasCompletionMatcher.cScoreSubstring, TAtlasCompletionMatcher.Score('dIt', 'AddItem'));
  Assert.AreEqual(TAtlasCompletionMatcher.cNoMatch, TAtlasCompletionMatcher.Score('xy', 'AddItem'));
end;

procedure TAtlasCompletionMatcherTests.MatchesCamelCaseAndSubsequence;
begin
  Assert.AreEqual(TAtlasCompletionMatcher.cScoreWordStarts, TAtlasCompletionMatcher.Score('TSL', 'TStringList'));
  Assert.AreEqual(TAtlasCompletionMatcher.cScoreWordStarts, TAtlasCompletionMatcher.Score('gtc', 'Get_Tick_Count'));
  // Teilfolge nur an Wortgrenzen bzw. zusammenhängend.
  Assert.AreEqual(TAtlasCompletionMatcher.cScoreSubsequence, TAtlasCompletionMatcher.Score('stl', 'TStringList'));
  Assert.AreEqual(TAtlasCompletionMatcher.cScoreSubsequence, TAtlasCompletionMatcher.Score('', 'Beliebig'));
  // Verstreute Treffer sind Rauschen (Fall aus der IDE: "myLis" bei nicht deklariertem myList).
  Assert.AreEqual(TAtlasCompletionMatcher.cNoMatch, TAtlasCompletionMatcher.Score('myLis', 'ERROR_TOO_MANY_LINKS'));
  Assert.AreEqual(TAtlasCompletionMatcher.cNoMatch, TAtlasCompletionMatcher.Score('tsit', 'TStringList'));
end;

procedure TAtlasCompletionMatcherTests.FiltersAndKeepsSourceOrderOnTies;
var
  mItems: TAtlasCompletionItems;
  mOrder: TArray<Integer>;
begin
  mItems := [Item('Count', 2), Item('Capacity', 1), Item('Clear', 0), Item('Add', 3)];
  mOrder := TAtlasCompletionMatcher.Filter(mItems, 'c');
  // Alle drei beginnen mit c: Reihenfolge der Quelle (Rank).
  Assert.AreEqual(3, Integer(Length(mOrder)));
  Assert.AreEqual('Clear', mItems[mOrder[0]].Name);
  Assert.AreEqual('Capacity', mItems[mOrder[1]].Name);
  Assert.AreEqual('Count', mItems[mOrder[2]].Name);
  mOrder := TAtlasCompletionMatcher.Filter(mItems, 'count');
  Assert.AreEqual('Count', mItems[mOrder[0]].Name);
end;

{ TAtlasCompletionControllerTests }

procedure TAtlasCompletionControllerTests.ShowsItemsFilteredByPrefix;
var
  mView: TFakeView;
  mViewRef: IAtlasCompletionView;
  mController: TAtlasCompletionController;
begin
  mView := TFakeView.Create;
  mViewRef := mView;
  mController := TAtlasCompletionController.Create(
    TAtlasFixedCompletionProvider.Create([Item('Add'), Item('Clear'), Item('Count')]) as IAtlasCompletionProvider,
    mViewRef);
  try
    mController.Start(Context('C'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not mController.Loading;
      end));
    Assert.IsTrue(mView.Shown);
    Assert.AreEqual('Clear,Count', mView.Names);
    Assert.AreEqual(0, mView.Selected);
    Assert.IsTrue(mController.Visible);
  finally
    mController.Free;
  end;
end;

procedure TAtlasCompletionControllerTests.TypingRefiltersAndResetsSelection;
var
  mView: TFakeView;
  mViewRef: IAtlasCompletionView;
  mController: TAtlasCompletionController;
begin
  mView := TFakeView.Create;
  mViewRef := mView;
  mController := TAtlasCompletionController.Create(
    TAtlasFixedCompletionProvider.Create([Item('Add'), Item('Clear'), Item('Count')]) as IAtlasCompletionProvider,
    mViewRef);
  try
    mController.Start(Context(''));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not mController.Loading;
      end));
    Assert.AreEqual('Add,Clear,Count', mView.Names);
    mController.HandleKey(TAtlasNavigationKey.Down);
    Assert.AreEqual(1, mView.Selected);
    mController.UpdatePrefix('co');
    Assert.AreEqual('Count', mView.Names);
    Assert.AreEqual(0, mView.Selected);
  finally
    mController.Free;
  end;
end;

procedure TAtlasCompletionControllerTests.KeysMoveSelectionAndEnterCommits;
var
  mView: TFakeView;
  mViewRef: IAtlasCompletionView;
  mController: TAtlasCompletionController;
  mCommitted: string;
begin
  mView := TFakeView.Create;
  mViewRef := mView;
  mController := TAtlasCompletionController.Create(
    TAtlasFixedCompletionProvider.Create([Item('A1'), Item('A2'), Item('A3'), Item('A4'), Item('A5')])
      as IAtlasCompletionProvider, mViewRef);
  try
    mCommitted := '';
    mController.OnCommit :=
      procedure(const AItem: TAtlasCompletionItem)
      begin
        mCommitted := AItem.Name;
      end;
    mController.Start(Context('A'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not mController.Loading;
      end));
    Assert.IsTrue(mController.HandleKey(TAtlasNavigationKey.Up));
    Assert.AreEqual(0, mView.Selected, 'Oben bleibt oben');
    mController.HandleKey(TAtlasNavigationKey.PageDown);
    Assert.AreEqual(2, mView.Selected, 'Bild ab um PageSize - 1');
    mController.HandleKey(TAtlasNavigationKey.Last);
    Assert.AreEqual(4, mView.Selected);
    mController.HandleKey(TAtlasNavigationKey.First);
    mController.HandleKey(TAtlasNavigationKey.Down);
    Assert.IsTrue(mController.HandleKey(TAtlasNavigationKey.Accept));
    Assert.AreEqual('A2', mCommitted);
    Assert.IsFalse(mController.Active, 'Übernahme schließt');
    Assert.IsFalse(mView.Shown);
  finally
    mController.Free;
  end;
end;

procedure TAtlasCompletionControllerTests.EscapeClosesAndKeysPassThroughWhenClosed;
var
  mView: TFakeView;
  mViewRef: IAtlasCompletionView;
  mController: TAtlasCompletionController;
begin
  mView := TFakeView.Create;
  mViewRef := mView;
  mController := TAtlasCompletionController.Create(
    TAtlasFixedCompletionProvider.Create([Item('Add')]) as IAtlasCompletionProvider, mViewRef);
  try
    Assert.IsFalse(mController.HandleKey(TAtlasNavigationKey.Down), 'Geschlossen: Taste gehört dem Editor');
    mController.Start(Context(''));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not mController.Loading;
      end));
    Assert.IsTrue(mController.HandleKey(TAtlasNavigationKey.Cancel));
    Assert.IsFalse(mController.Active);
    Assert.IsFalse(mView.Shown);
    Assert.IsFalse(mController.HandleKey(TAtlasNavigationKey.Accept), 'Enter nach Esc gehört dem Editor');
  finally
    mController.Free;
  end;
end;

procedure TAtlasCompletionControllerTests.EscapeBlocksAutomaticReopenInSameWord;
var
  mView: TFakeView;
  mViewRef: IAtlasCompletionView;
  mController: TAtlasCompletionController;
  mTyped: TAtlasContext;
begin
  // #414: Nach Esc öffnet Weitertippen im selben Wort nicht automatisch; Strg+Leer schon.
  mView := TFakeView.Create;
  mViewRef := mView;
  mController := TAtlasCompletionController.Create(
    TAtlasFixedCompletionProvider.Create([Item('Add')]) as IAtlasCompletionProvider, mViewRef);
  try
    mController.Start(Context('A'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not mController.Loading;
      end));
    Assert.IsTrue(mController.HandleKey(TAtlasNavigationKey.Cancel));
    mTyped := Context('Ad');
    mTyped.Character := mTyped.Character + 1;
    mTyped.Automatic := True;
    Assert.IsTrue(mController.Dismissed(mTyped));
    mController.Start(mTyped);
    Assert.IsFalse(mController.Active, 'automatisch im selben Wort: bleibt zu');
    // Neues Wort: wieder automatisch.
    mTyped.Character := mTyped.Character + 5;
    Assert.IsFalse(mController.Dismissed(mTyped));
    // Strg+Leer im gesperrten Wort öffnet und hebt die Sperre auf.
    mTyped := Context('Ad');
    mTyped.Character := mTyped.Character + 1;
    mController.Start(mTyped);
    Assert.IsTrue(mController.Active, 'Strg+Leer öffnet');
    mController.Close;
    mTyped.Automatic := True;
    Assert.IsFalse(mController.Dismissed(mTyped), 'Schließen ohne Esc sperrt nicht');
  finally
    mController.Free;
  end;
end;

procedure TAtlasCompletionControllerTests.NoMatchShowsEmptyState;
var
  mView: TFakeView;
  mViewRef: IAtlasCompletionView;
  mController: TAtlasCompletionController;
begin
  mView := TFakeView.Create;
  mViewRef := mView;
  mController := TAtlasCompletionController.Create(
    TAtlasFixedCompletionProvider.Create([Item('Add'), Item('Clear')]) as IAtlasCompletionProvider, mViewRef);
  try
    mController.Start(Context('a'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not mController.Loading;
      end));
    // #423: "Lines.Axq" zeigt den leeren Zustand, Rücktaste bis "Lines.A" wieder Treffer.
    mController.UpdatePrefix('axq');
    Assert.IsTrue(mView.Empty);
    Assert.AreEqual('axq/2', mView.EmptyText);
    Assert.IsTrue(mController.Active);
    Assert.IsFalse(mController.HandleKey(TAtlasNavigationKey.Accept), 'Ohne Treffer gehört Enter dem Editor');
    Assert.IsFalse(mController.HandleKey(TAtlasNavigationKey.Down), 'Ohne Treffer gehören Pfeile dem Editor');
    mController.UpdatePrefix('a');
    Assert.IsTrue(mView.Shown);
    Assert.IsFalse(mView.Empty);
    Assert.AreEqual('Add,Clear', mView.Names);
  finally
    mController.Free;
  end;
end;

procedure TAtlasCompletionControllerTests.EmptyResultShowsEmptyStateUntilEscape;
var
  mView: TFakeView;
  mViewRef: IAtlasCompletionView;
  mController: TAtlasCompletionController;
begin
  mView := TFakeView.Create;
  mViewRef := mView;
  mController := TAtlasCompletionController.Create(
    TAtlasFixedCompletionProvider.Create(nil) as IAtlasCompletionProvider, mViewRef);
  try
    mController.Start(Context('mylist'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not mController.Loading;
      end));
    Assert.IsTrue(mView.Empty, 'Nichts gefunden: leerer Zustand statt Verschwinden');
    Assert.AreEqual('mylist/0', mView.EmptyText);
    Assert.IsTrue(mController.HandleKey(TAtlasNavigationKey.Cancel), 'Esc schließt den leeren Zustand');
    Assert.IsFalse(mController.Active);
    Assert.IsFalse(mView.Empty);
  finally
    mController.Free;
  end;
end;

procedure TAtlasCompletionControllerTests.CommitCharacterOnlyForClearMatch;
var
  mView: TFakeView;
  mViewRef: IAtlasCompletionView;
  mController: TAtlasCompletionController;
  mSnippet: TAtlasCompletionItem;
begin
  mView := TFakeView.Create;
  mViewRef := mView;
  // Code-Vorlage (#51): nie über ein Zeichen übernommen.
  mSnippet := Item('while');
  mSnippet.Snippet := 'while ${1:Condition} do';
  mController := TAtlasCompletionController.Create(
    TAtlasFixedCompletionProvider.Create([Item('Add'), Item('AddStrings'), Item('Exchange'), mSnippet])
      as IAtlasCompletionProvider, mViewRef);
  try
    mController.Start(Context(''));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not mController.Loading;
      end));
    Assert.IsFalse(mController.CanCommitOnCharacter, 'Ohne getipptes Wort übernimmt ";" nichts');
    mController.UpdatePrefix('A');
    Assert.IsTrue(mController.CanCommitOnCharacter, '"Lines.A" + "(" ergibt "Lines.Add("');
    mController.UpdatePrefix('as');
    Assert.IsTrue(mController.CanCommitOnCharacter, 'Wortanfänge: AddStrings');
    mController.UpdatePrefix('xch');
    Assert.IsFalse(mController.CanCommitOnCharacter, 'Nur Teilstring von Exchange: Zeichen bleibt allein');
    mController.UpdatePrefix('while');
    Assert.IsFalse(mController.CanCommitOnCharacter, '"while(" setzt keine Vorlage ein');
  finally
    mController.Free;
  end;
end;
procedure TAtlasCompletionControllerTests.TypoSuggestionsTakeOnlyEnter;
var
  mView: TFakeView;
  mViewRef: IAtlasCompletionView;
  mController: TAtlasCompletionController;
  mCommitted: string;
begin
  // #485, Abnahme: "Lenght" zeigt Length unter „Meintest du“ statt des leeren Zustands; ";" übernimmt
  // nichts, Enter übernimmt.
  mView := TFakeView.Create;
  mViewRef := mView;
  mController := TAtlasCompletionController.Create(
    TAtlasFixedCompletionProvider.Create([Item('Length'), Item('Low'), Item('High')])
      as IAtlasCompletionProvider, mViewRef);
  try
    mCommitted := '';
    mController.OnCommit :=
      procedure(const AItem: TAtlasCompletionItem)
      begin
        mCommitted := AItem.Name;
      end;
    mController.Start(Context(''));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not mController.Loading;
      end));
    mController.UpdatePrefix('Lenght');
    Assert.IsFalse(mView.Empty, 'Vorschläge statt des Hinweistexts');
    Assert.AreEqual('#,Length', mView.Names);
    Assert.AreEqual(1, mView.Selected, 'Überschrift wird übersprungen');
    Assert.IsFalse(mController.CanCommitOnCharacter, '";" fügt nur das Zeichen ein');
    Assert.IsTrue(mController.HandleKey(TAtlasNavigationKey.Accept));
    Assert.AreEqual('Length', mCommitted);
  finally
    mController.Free;
  end;
end;

procedure TAtlasCompletionControllerTests.ItemsAfterCloseAreDropped;
var
  mView: TFakeView;
  mViewRef: IAtlasCompletionView;
  mController: TAtlasCompletionController;
begin
  mView := TFakeView.Create;
  mViewRef := mView;
  mController := TAtlasCompletionController.Create(
    TAtlasFixedCompletionProvider.Create([Item('Spaet')], 100) as IAtlasCompletionProvider, mViewRef);
  try
    mController.Start(Context(''));
    mController.Close;
    WaitWithin(
      function: Boolean
      begin
        Result := False;
      end, 300);
    Assert.AreEqual(0, mView.ShowCount);
    Assert.IsFalse(mController.Active);
  finally
    mController.Free;
  end;
end;

procedure TAtlasCompletionControllerTests.TruncatedListIsRequeried;
var
  mView: TFakeView;
  mViewRef: IAtlasCompletionView;
  mProvider: TPrefixProvider;
  mProviderRef: IAtlasCompletionProvider;
  mController: TAtlasCompletionController;
begin
  mView := TFakeView.Create;
  mViewRef := mView;
  mProvider := TPrefixProvider.Create;
  mProviderRef := mProvider;
  mController := TAtlasCompletionController.Create(mProviderRef, mViewRef);
  try
    mController.Start(Context('ab'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not mController.Loading;
      end));
    Assert.AreEqual('ab1,ab2', mView.Names);
    Assert.IsTrue(mController.Incomplete, 'Gekürzte Liste gemeldet');
    // #431: Weitertippen fragt neu, die neue Liste ersetzt die alte.
    mController.Requery(Context('abc'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not mController.Loading;
      end));
    Assert.AreEqual(2, mProvider.Queries);
    Assert.AreEqual('abc1,abc2', mView.Names);
    Assert.IsTrue(mView.Shown);
  finally
    mController.Free;
  end;
end;

procedure TAtlasCompletionControllerTests.SyntaxNoticeReachesView;
var
  mView: TFakeView;
  mViewRef: IAtlasCompletionView;
  mProvider: TPrefixProvider;
  mProviderRef: IAtlasCompletionProvider;
  mController: TAtlasCompletionController;
begin
  // #457: Der Hinweis der Quelle geht an die Ansicht; die nächste Abfrage ohne Hinweis blendet ihn aus.
  mView := TFakeView.Create;
  mViewRef := mView;
  mProvider := TPrefixProvider.Create;
  mProvider.Syntax.Trust := TAtlasSyntaxTrust.Limited;
  mProvider.Syntax.Line := 12;
  mProvider.Syntax.Message := 'Ausdruck erwartet';
  mProviderRef := mProvider;
  mController := TAtlasCompletionController.Create(mProviderRef, mViewRef);
  try
    mController.Start(Context('ab'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not mController.Loading;
      end));
    Assert.AreEqual(Ord(TAtlasSyntaxTrust.Limited), Ord(mController.Syntax.Trust));
    Assert.AreEqual(Ord(TAtlasSyntaxTrust.Limited), Ord(mView.Syntax.Trust));
    Assert.AreEqual(12, mView.Syntax.Line);
    Assert.AreEqual('ab1,ab2', mView.Names, 'Einträge bleiben');
    mProvider.Syntax := Default(TAtlasSyntaxNotice);
    mController.Requery(Context('abc'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not mController.Loading;
      end));
    Assert.AreEqual(Ord(TAtlasSyntaxTrust.Sure), Ord(mController.Syntax.Trust));
    Assert.AreEqual(Ord(TAtlasSyntaxTrust.Sure), Ord(mView.Syntax.Trust));
    // Schließen setzt zurück.
    mProvider.Syntax.Trust := TAtlasSyntaxTrust.Unknown;
    mController.Requery(Context('abcd'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not mController.Loading;
      end));
    Assert.AreEqual(Ord(TAtlasSyntaxTrust.Unknown), Ord(mController.Syntax.Trust));
    mController.Close;
    Assert.AreEqual(Ord(TAtlasSyntaxTrust.Sure), Ord(mController.Syntax.Trust));
  finally
    mController.Free;
  end;
end;

procedure TAtlasCompletionControllerTests.CompleteListFiltersLocallyUntilPrefixShrinks;
var
  mView: TFakeView;
  mViewRef: IAtlasCompletionView;
  mProvider: TPrefixProvider;
  mProviderRef: IAtlasCompletionProvider;
  mController: TAtlasCompletionController;
begin
  mView := TFakeView.Create;
  mViewRef := mView;
  mProvider := TPrefixProvider.Create;
  mProvider.CompleteList := True;
  mProviderRef := mProvider;
  mController := TAtlasCompletionController.Create(mProviderRef, mViewRef);
  try
    mController.Start(Context('ab'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not mController.Loading;
      end));
    Assert.IsFalse(mController.Incomplete);
    // Der Server hat nach "ab" gefiltert: Weitertippen filtert lokal, kürzer oder anders fragt neu (#616).
    Assert.IsFalse(mController.NeedsQuery('abc'));
    Assert.IsFalse(mController.NeedsQuery('ABx'), 'Groß- und Kleinschreibung egal');
    Assert.IsTrue(mController.NeedsQuery('a'));
    Assert.IsTrue(mController.NeedsQuery('xb'));
    mController.UpdatePrefix('ab1');
    Assert.AreEqual(1, mProvider.Queries);
    // Lokal gefiltert; ab2 steht als Tippfehler-Kandidat unter „Meintest du“ (#485, # = Überschrift).
    Assert.AreEqual('ab1,#,ab2', mView.Names);
    mController.Close;
    Assert.IsFalse(mController.NeedsQuery('a'), 'geschlossen');
  finally
    mController.Free;
  end;
end;

procedure TAtlasCompletionControllerTests.PartialResultsReplaceThenAppend;
var
  mView: TFakeView;
  mViewRef: IAtlasCompletionView;
  mProvider: TPrefixProvider;
  mProviderRef: IAtlasCompletionProvider;
  mController: TAtlasCompletionController;
begin
  mView := TFakeView.Create;
  mViewRef := mView;
  mProvider := TPrefixProvider.Create;
  mProvider.Staged := True;
  mProviderRef := mProvider;
  mController := TAtlasCompletionController.Create(mProviderRef, mViewRef);
  try
    mController.Start(Context('ab'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not mController.Loading;
      end));
    Assert.AreEqual('ab1,ab2', mView.Names);
    // Requery: Das erste Teil ersetzt die alte Liste, das zweite hängt an (#616).
    mController.Requery(Context('a'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not mController.Loading;
      end));
    Assert.AreEqual('a1,a2', mView.Names);
  finally
    mController.Free;
  end;
end;

procedure TAtlasCompletionControllerTests.RequeryKeepsSelectedEntry;
var
  mView: TFakeView;
  mViewRef: IAtlasCompletionView;
  mController: TAtlasCompletionController;
begin
  mView := TFakeView.Create;
  mViewRef := mView;
  mController := TAtlasCompletionController.Create(TPrefixProvider.Create as IAtlasCompletionProvider, mViewRef);
  try
    mController.Start(Context('ab'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not mController.Loading;
      end));
    mController.HandleKey(TAtlasNavigationKey.Down);
    Assert.AreEqual(1, mView.Selected);
    // Neue Einträge verschieben die Auswahl nicht (#431).
    mController.Requery(Context('ab'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not mController.Loading;
      end));
    Assert.AreEqual('ab1,ab2', mView.Names);
    Assert.AreEqual(1, mView.Selected);
  finally
    mController.Free;
  end;
end;

{ TAtlasCompletionTimingTests }

/// <summary>Zwei Quellen mit Namen: "Langsam" liefert nach ADelayMs, "Schnell" sofort.</summary>
function TimedProviders(ADelayMs: Cardinal): IAtlasCompletionProvider;
var
  mProviders: TAtlasCompletionProviders;
  mSlow, mFast: TAtlasFixedCompletionProvider;
begin
  mProviders := TAtlasCompletionProviders.Create;
  Result := mProviders;
  // Zeitlimit höher als die Verzögerung: Die Quelle liefert spät, wird aber nicht abgebrochen.
  mProviders.TimeLimitMs := 2000;
  mSlow := TAtlasFixedCompletionProvider.Create([Item('Langsam1'), Item('Langsam2')], ADelayMs);
  mSlow.Name := 'Langsam';
  mProviders.Add(mSlow);
  mFast := TAtlasFixedCompletionProvider.Create([Item('Schnell')]);
  mFast.Name := 'Schnell';
  mProviders.Add(mFast);
end;

procedure TAtlasCompletionTimingTests.TearDown;
begin
  TAtlasQueryTimings.Enabled := False;
  TAtlasQueryTimings.Shared.Clear;
end;

procedure TAtlasCompletionTimingTests.DelayedProviderIsOverBudget;
var
  mView: TFakeView;
  mViewRef: IAtlasCompletionView;
  mController: TAtlasCompletionController;
  mStart: TAtlasContext;
  mQueries: TArray<TAtlasQueryTiming>;
  mRows: TArray<TAtlasTimingRow>;
  mRow: TAtlasTimingRow;
  mSlowWarn, mFastSeen: Boolean;
begin
  TAtlasQueryTimings.Shared.Clear;
  TAtlasQueryTimings.Enabled := True;
  mView := TFakeView.Create;
  mViewRef := mView;
  mController := TAtlasCompletionController.Create(TimedProviders(200), mViewRef);
  try
    mStart := Context('');
    mStart.Started := TAtlasQueryTimings.Stamp;
    mController.Start(mStart);
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not mController.Loading;
      end));
  finally
    mController.Free;
  end;
  mQueries := TAtlasQueryTimings.Shared.Snapshot;
  Assert.AreEqual(1, Integer(Length(mQueries)));
  Assert.AreEqual(2, Integer(Length(mQueries[0].Providers)), 'beide Quellen mit Namen');
  Assert.IsTrue(mQueries[0].ContextMs >= 0, 'Kontext gemessen');
  Assert.IsTrue(mQueries[0].FilterSortSteps > 0, 'Filtern und Sortieren gemessen');
  Assert.IsTrue(mQueries[0].FirstVisibleMs >= 0, 'erste Liste gemessen');
  Assert.AreEqual(3, Integer(mQueries[0].Count));
  // Abnahme: Die Zeit des verzögerten Providers erscheint in Warnfarbe, die des schnellen nicht.
  mRows := TAtlasTimingRows.Build(mQueries);
  mSlowWarn := False;
  mFastSeen := False;
  for mRow in mRows do
  begin
    if mRow.Kind = TAtlasTimingRowKind.Provider then
    begin
      if mRow.Name = 'Langsam' then
      begin
        Assert.IsTrue(mRow.Last >= 150, 'Verzögerung gemessen');
        mSlowWarn := mRow.LastWarn;
      end
      else if mRow.Name = 'Schnell' then
      begin
        mFastSeen := True;
        Assert.IsFalse(mRow.LastWarn, 'schnelle Quelle im Budget');
      end;
    end;
  end;
  Assert.IsTrue(mSlowWarn, 'verzögerte Quelle über dem Budget');
  Assert.IsTrue(mFastSeen);
end;

procedure TAtlasCompletionTimingTests.NoSourceTextInMeasurements;
var
  mView: TFakeView;
  mViewRef: IAtlasCompletionView;
  mController: TAtlasCompletionController;
  mStart: TAtlasContext;
  mInput: TAtlasTimingReportInput;
  mReport: string;
begin
  TAtlasQueryTimings.Shared.Clear;
  TAtlasQueryTimings.Enabled := True;
  mView := TFakeView.Create;
  mViewRef := mView;
  mController := TAtlasCompletionController.Create(TimedProviders(0), mViewRef);
  try
    mStart := Context('Lan');
    mStart.FileName := 'C:\Users\Tester\Projekt\GeheimeUnit.pas';
    mStart.Text := 'procedure GeheimerQuelltext; begin Lan end;';
    mController.Start(mStart);
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not mController.Loading;
      end));
  finally
    mController.Free;
  end;
  mInput := Default(TAtlasTimingReportInput);
  mInput.AtlasVersion := '1.0.0';
  mInput.IdeVersion := '37.0';
  mInput.Platform := 'Win64';
  mInput.Settings := '{}';
  mInput.Created := Now;
  // Abnahme: Der kopierte Bericht enthält keinen Quelltext und ohne Häkchen keinen Dateinamen.
  mReport := TAtlasTimingReport.Build(TAtlasQueryTimings.Shared.Snapshot, mInput);
  Assert.IsFalse(mReport.Contains('GeheimerQuelltext'), 'kein Quelltext');
  Assert.IsFalse(mReport.Contains('begin Lan'), 'kein Quelltext');
  Assert.IsFalse(mReport.Contains('GeheimeUnit'), 'Dateiname nur auf Wunsch');
  Assert.IsFalse(mReport.Contains('Tester'), 'kein Ordner');
  mInput.FileNames := True;
  mReport := TAtlasTimingReport.Build(TAtlasQueryTimings.Shared.Snapshot, mInput);
  Assert.IsTrue(mReport.Contains('GeheimeUnit.pas'), 'auf Wunsch der Dateiname');
  Assert.IsFalse(mReport.Contains('Tester'), 'auch dann ohne Ordner');
  Assert.IsFalse(mReport.Contains('GeheimerQuelltext'), 'auch dann kein Quelltext');
end;

procedure TAtlasCompletionTimingTests.OffMeasuresNothing;
var
  mView: TFakeView;
  mViewRef: IAtlasCompletionView;
  mController: TAtlasCompletionController;
  mVersion: Integer;
begin
  // Abnahme: Mit diagnosticMode.enabled aus misst Atlas nichts; der Ablauf ist derselbe.
  TAtlasQueryTimings.Shared.Clear;
  TAtlasQueryTimings.Enabled := False;
  mVersion := TAtlasQueryTimings.Shared.Version;
  mView := TFakeView.Create;
  mViewRef := mView;
  mController := TAtlasCompletionController.Create(TimedProviders(0), mViewRef);
  try
    mController.Start(Context(''));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not mController.Loading;
      end));
    // Beide Quellen liefern wie sonst; die Reihenfolge hängt davon ab, welche zuerst fertig ist.
    Assert.Contains(mView.Names, 'Langsam1');
    Assert.Contains(mView.Names, 'Schnell');
  finally
    mController.Free;
  end;
  Assert.AreEqual(mVersion, TAtlasQueryTimings.Shared.Version, 'keine Messung');
  Assert.AreEqual(0, Integer(Length(TAtlasQueryTimings.Shared.Snapshot)));
end;

initialization  TDUnitX.RegisterTestFixture(TAtlasCompletionMatcherTests);
  TDUnitX.RegisterTestFixture(TAtlasCompletionControllerTests);
  TDUnitX.RegisterTestFixture(TAtlasCompletionTimingTests);

end.
