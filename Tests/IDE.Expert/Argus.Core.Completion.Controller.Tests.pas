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
    procedure NoMatchHidesButStaysActive;
    [Test]
    procedure EmptyResultClosesWithoutShowing;
    [Test]
    procedure ItemsAfterCloseAreDropped;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Argus.Core.Completion.Contract,
  Argus.Core.Completion.Matching,
  Argus.Core.Completion.Controller,
  Argus.Core.Completion.Providers.Fixed;

type
  TFakeView = class(TInterfacedObject, IArgusCompletionView)
  public
    Shown: Boolean;
    ShowCount: Integer;
    Names: string;
    Selected: Integer;
    procedure ShowList(const AItems: TArgusCompletionItems; const AOrder: TArray<Integer>; ASelected: Integer);
    procedure HideList;
    function PageSize: Integer;
  end;

procedure TFakeView.ShowList(const AItems: TArgusCompletionItems; const AOrder: TArray<Integer>;
  ASelected: Integer);
var
  Index: Integer;
begin
  Shown := True;
  Inc(ShowCount);
  Names := '';
  for Index in AOrder do
  begin
    if Names <> '' then
      Names := Names + ',';
    Names := Names + AItems[Index].Name;
  end;
  Selected := ASelected;
end;

procedure TFakeView.HideList;
begin
  Shown := False;
end;

function TFakeView.PageSize: Integer;
begin
  Result := 3;
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
  Assert.AreEqual(TArgusCompletionMatcher.ScoreSubsequence, TArgusCompletionMatcher.Score('tsit', 'TStringList'));
  Assert.AreEqual(TArgusCompletionMatcher.ScoreSubsequence, TArgusCompletionMatcher.Score('', 'Beliebig'));
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

procedure TArgusCompletionControllerTests.NoMatchHidesButStaysActive;
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
    Controller.UpdatePrefix('axq');
    Assert.IsFalse(View.Shown);
    Assert.IsTrue(Controller.Active);
    Assert.IsFalse(Controller.HandleKey(TArgusNavigationKey.Accept), 'Ohne Treffer gehört Enter dem Editor');
    // Rücktaste: Treffer wieder da.
    Controller.UpdatePrefix('a');
    Assert.IsTrue(View.Shown);
    Assert.AreEqual('Add,Clear', View.Names);
  finally
    Controller.Free;
  end;
end;

procedure TArgusCompletionControllerTests.EmptyResultClosesWithoutShowing;
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
    Controller.Start(Context(''));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Active;
      end));
    Assert.AreEqual(0, View.ShowCount);
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

initialization
  TDUnitX.RegisterTestFixture(TArgusCompletionMatcherTests);
  TDUnitX.RegisterTestFixture(TArgusCompletionControllerTests);

end.
