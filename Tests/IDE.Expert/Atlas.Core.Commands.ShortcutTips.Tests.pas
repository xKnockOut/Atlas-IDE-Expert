unit Atlas.Core.Commands.ShortcutTips.Tests;

// Tests für die Tastenkürzel-Tipps (#600): Regeln (je Tag, drei Aufrufe über
// das Kürzel, Abstand 30 s, „Nicht mehr zeigen“, ohne Kürzel, per Tastatur,
// Bereich, Debug-Sitzung, modaler Dialog), Kürzel mit zwei Schritten, Lage
// unten rechts und die Zählung je Befehl: Zähler in usage.json, Zustand der
// Tipps in shortcut-tips.json (gemeinsam mit #757).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasShortcutTipsTests = class
  public
    [Test]
    procedure MouseUseWithShortCutShowsTip;
    [Test]
    procedure SecondTipSameDayIsSuppressed;
    [Test]
    procedure ThreeKeyboardUsesStopTips;
    [Test]
    procedure TipsKeepThirtySecondsApart;
    [Test]
    procedure NeverShowAgainOnlyForThatCommand;
    [Test]
    procedure CommandWithoutShortCutShowsNoTip;
    [Test]
    procedure KeyboardUseShowsNoTip;
    [Test]
    procedure ScopeAtlasSkipsIdeCommands;
    [Test]
    procedure NoTipWhileDebuggingOrModalOrDisabled;
    [Test]
    procedure TwoStepShortCutsKeepBothSteps;
    [Test]
    procedure ParsesStepsForKeyboardCounting;
    [Test]
    procedure AtlasCommandFollowsCurrentKey;
    [Test]
    procedure KeyOnlyFunctionsHaveNoPaletteCommand;
    [Test]
    procedure PlacesTipBottomRight;
    [Test]
    procedure RecognizesShortCutStrokes;
  end;

  [TestFixture]
  TAtlasCommandUsageTests = class
  public
    [Test]
    procedure CountsAndRoundTrips;
    [Test]
    procedure KeepsUnknownTopLevelFields;
    [Test]
    procedure HigherFormatIsNotOverwritten;
    [Test]
    procedure BrokenJsonStartsEmpty;
    /// <summary>Unbrauchbare Datei liegt danach als .defekt daneben; eine beim Lesen gesperrte wird nicht
    /// überschrieben.</summary>
    [Test]
    procedure BrokenFileSetAsideLockedFileKept;
    [Test]
    procedure SavesAndLoadsFile;
    [Test]
    procedure RarelyByKeyboard;
    [Test]
    procedure FileIsNotTheCompletionUsage;
    [Test]
    procedure UsageJsonHoldsOnlyIdsCountersAndDate;
    [Test]
    procedure TrackingOffCountsNothing;
    [Test]
    procedure ResetCountsKeepsTipState;
    [Test]
    procedure OlderTipsFileMovesCountsToUsageJson;
    [Test]
    procedure UsageJsonWinsOverOlderCounts;
    [Test]
    procedure SectionsRoundTrip;
    [Test]
    procedure HigherFormatUsageJsonIsNotOverwritten;
  end;

implementation

uses
  System.DateUtils,
  System.Generics.Collections,
  System.SysUtils,
  System.Classes,
  System.Types,
  System.IOUtils,
  System.JSON,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Commands.KeyConflicts,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Commands.Usage,
  Atlas.Core.Commands.ShortcutTips;

const
  cClassCompletion = 'ecClassCompletion';

function Moment(AHour, AMinute, ASecond: Word): TDateTime;
begin
  Result := EncodeDate(2026, 10, 15) + EncodeTime(AHour, AMinute, ASecond, 0);
end;

function Situation(ANow: TDateTime): TAtlasTipSituation;
begin
  Result := TAtlasTipSituation.Create(True, TAtlasTipScope.All, False, 'Strg+Umschalt+C', ANow);
end;

{ TAtlasShortcutTipsTests }

procedure TAtlasShortcutTipsTests.MouseUseWithShortCutShowsTip;
var
  mUsage: TAtlasCommandUsage;
begin
  mUsage := TAtlasCommandUsage.Create;
  try
    // Abnahme: Klasse vervollständigen über das Kontextmenü zeigt einen Tipp mit Strg+Umschalt+C.
    mUsage.Count(cClassCompletion, TAtlasCommandInput.Mouse, Moment(10, 0, 0));
    Assert.AreEqual<TAtlasTipVerdict>(TAtlasTipVerdict.Show,
      TAtlasShortcutTips.Decide(mUsage.Entry(cClassCompletion), Situation(Moment(10, 0, 0))));
    Assert.AreEqual(1, mUsage.Entry(cClassCompletion).Mouse);
  finally
    mUsage.Free;
  end;
end;

procedure TAtlasShortcutTipsTests.SecondTipSameDayIsSuppressed;
var
  mEntry: TAtlasCommandUsageEntry;
  mLater: TAtlasTipSituation;
begin
  mEntry := TAtlasCommandUsageEntry.Create(cClassCompletion);
  Assert.AreEqual<TAtlasTipVerdict>(TAtlasTipVerdict.Show,
    TAtlasShortcutTips.Decide(mEntry, Situation(Moment(10, 0, 0))));
  TAtlasShortcutTips.MarkShown(mEntry, Moment(10, 0, 0));
  // Zweiter Aufruf am selben Tag (lange nach dem 30-s-Abstand): kein Tipp.
  mLater := Situation(Moment(16, 30, 0));
  mLater.LastTipAt := Moment(10, 0, 0);
  Assert.AreEqual<TAtlasTipVerdict>(TAtlasTipVerdict.ShownToday, TAtlasShortcutTips.Decide(mEntry, mLater));
  // Kurz vor Mitternacht noch derselbe Tag, am nächsten Tag wieder.
  mLater := Situation(Moment(23, 59, 59));
  Assert.AreEqual<TAtlasTipVerdict>(TAtlasTipVerdict.ShownToday, TAtlasShortcutTips.Decide(mEntry, mLater));
  mLater := Situation(Moment(10, 0, 0) + 1);
  Assert.AreEqual<TAtlasTipVerdict>(TAtlasTipVerdict.Show, TAtlasShortcutTips.Decide(mEntry, mLater));
  Assert.IsTrue(TAtlasShortcutTips.SameDay(Moment(0, 0, 0), Moment(23, 59, 59)));
  Assert.IsFalse(TAtlasShortcutTips.SameDay(0, Moment(10, 0, 0)), 'nie gezeigt');
end;

procedure TAtlasShortcutTipsTests.ThreeKeyboardUsesStopTips;
var
  mUsage: TAtlasCommandUsage;
  mIndex: Integer;
begin
  mUsage := TAtlasCommandUsage.Create;
  try
    for mIndex := 1 to 2 do
    begin
      mUsage.Count(cClassCompletion, TAtlasCommandInput.Keyboard, Moment(9, mIndex, 0));
    end;
    mUsage.Count(cClassCompletion, TAtlasCommandInput.Mouse, Moment(10, 0, 0));
    Assert.AreEqual<TAtlasTipVerdict>(TAtlasTipVerdict.Show,
      TAtlasShortcutTips.Decide(mUsage.Entry(cClassCompletion), Situation(Moment(10, 0, 0))),
      'zwei Mal über das Kürzel: noch ein Tipp');
    mUsage.Count(cClassCompletion, TAtlasCommandInput.Keyboard, Moment(10, 5, 0));
    Assert.AreEqual(3, mUsage.Entry(cClassCompletion).Keyboard);
    Assert.AreEqual<TAtlasTipVerdict>(TAtlasTipVerdict.Learned,
      TAtlasShortcutTips.Decide(mUsage.Entry(cClassCompletion), Situation(Moment(11, 0, 0) + 1)),
      'nach dreimaliger Nutzung des Kürzels kein Tipp mehr');
  finally
    mUsage.Free;
  end;
end;

procedure TAtlasShortcutTipsTests.TipsKeepThirtySecondsApart;
var
  mEntry: TAtlasCommandUsageEntry;
  mCurrent: TAtlasTipSituation;
begin
  // Ein anderer Befehl hat gerade einen Tipp bekommen.
  mEntry := TAtlasCommandUsageEntry.Create('SearchFindCommand');
  mCurrent := Situation(Moment(10, 0, 29));
  mCurrent.LastTipAt := Moment(10, 0, 0);
  Assert.AreEqual<TAtlasTipVerdict>(TAtlasTipVerdict.TooSoon, TAtlasShortcutTips.Decide(mEntry, mCurrent));
  mCurrent := Situation(Moment(10, 0, 31));
  mCurrent.LastTipAt := Moment(10, 0, 0);
  Assert.AreEqual<TAtlasTipVerdict>(TAtlasTipVerdict.Show, TAtlasShortcutTips.Decide(mEntry, mCurrent));
  // Zurückgestellte Uhr: auch dann nicht gleich wieder.
  mCurrent := Situation(Moment(9, 59, 50));
  mCurrent.LastTipAt := Moment(10, 0, 0);
  Assert.AreEqual<TAtlasTipVerdict>(TAtlasTipVerdict.TooSoon, TAtlasShortcutTips.Decide(mEntry, mCurrent));
end;

procedure TAtlasShortcutTipsTests.NeverShowAgainOnlyForThatCommand;
var
  mUsage: TAtlasCommandUsage;
  mEntry: TAtlasCommandUsageEntry;
begin
  mUsage := TAtlasCommandUsage.Create;
  try
    mEntry := mUsage.Entry(cClassCompletion);
    mEntry.Never := True;
    mUsage.Put(mEntry);
    Assert.AreEqual<TAtlasTipVerdict>(TAtlasTipVerdict.Hidden,
      TAtlasShortcutTips.Decide(mUsage.Entry(cClassCompletion), Situation(Moment(10, 0, 0))));
    // Dauerhaft: auch an späteren Tagen und nach dem Lesen der Datei.
    mUsage.Parse(mUsage.ToJson);
    Assert.AreEqual<TAtlasTipVerdict>(TAtlasTipVerdict.Hidden,
      TAtlasShortcutTips.Decide(mUsage.Entry(cClassCompletion), Situation(Moment(10, 0, 0) + 30)));
    // Andere Befehle zeigen weiter Tipps.
    Assert.AreEqual<TAtlasTipVerdict>(TAtlasTipVerdict.Show,
      TAtlasShortcutTips.Decide(mUsage.Entry('SearchFindCommand'), Situation(Moment(10, 0, 0))));
  finally
    mUsage.Free;
  end;
end;

procedure TAtlasShortcutTipsTests.CommandWithoutShortCutShowsNoTip;
var
  mCurrent: TAtlasTipSituation;
begin
  mCurrent := Situation(Moment(10, 0, 0));
  mCurrent.KeyText := '';
  Assert.AreEqual<TAtlasTipVerdict>(TAtlasTipVerdict.NoShortCut,
    TAtlasShortcutTips.Decide(TAtlasCommandUsageEntry.Create('ProjectOptions'), mCurrent));
  mCurrent.KeyText := '   ';
  Assert.AreEqual<TAtlasTipVerdict>(TAtlasTipVerdict.NoShortCut,
    TAtlasShortcutTips.Decide(TAtlasCommandUsageEntry.Create('ProjectOptions'), mCurrent));
end;

procedure TAtlasShortcutTipsTests.KeyboardUseShowsNoTip;
var
  mCurrent: TAtlasTipSituation;
begin
  mCurrent := Situation(Moment(10, 0, 0));
  mCurrent.ViaKeyboard := True;
  Assert.AreEqual<TAtlasTipVerdict>(TAtlasTipVerdict.ViaKeyboard,
    TAtlasShortcutTips.Decide(TAtlasCommandUsageEntry.Create(cClassCompletion), mCurrent));
end;

procedure TAtlasShortcutTipsTests.ScopeAtlasSkipsIdeCommands;
var
  mCurrent: TAtlasTipSituation;
begin
  mCurrent := TAtlasTipSituation.Create(True, TAtlasTipScope.Atlas, False, 'Strg+Umschalt+C', Moment(10, 0, 0));
  Assert.AreEqual<TAtlasTipVerdict>(TAtlasTipVerdict.OutOfScope,
    TAtlasShortcutTips.Decide(TAtlasCommandUsageEntry.Create(cClassCompletion), mCurrent));
  mCurrent := TAtlasTipSituation.Create(True, TAtlasTipScope.Atlas, True, 'Alt+Eingabe', Moment(10, 0, 0));
  Assert.AreEqual<TAtlasTipVerdict>(TAtlasTipVerdict.Show,
    TAtlasShortcutTips.Decide(TAtlasCommandUsageEntry.Create('Atlas.CodeActions'), mCurrent));
  Assert.AreEqual<TAtlasTipScope>(TAtlasTipScope.Atlas, TAtlasShortcutTips.ScopeOf('atlas'));
  Assert.AreEqual<TAtlasTipScope>(TAtlasTipScope.Atlas, TAtlasShortcutTips.ScopeOf(' ATLAS '));
  Assert.AreEqual<TAtlasTipScope>(TAtlasTipScope.All, TAtlasShortcutTips.ScopeOf('all'));
  Assert.AreEqual<TAtlasTipScope>(TAtlasTipScope.All, TAtlasShortcutTips.ScopeOf('unsinn'), 'Vorgabe all');
  Assert.AreEqual('atlas', TAtlasShortcutTips.ScopeName(TAtlasTipScope.Atlas));
  Assert.AreEqual('all', TAtlasShortcutTips.ScopeName(TAtlasTipScope.All));
end;

procedure TAtlasShortcutTipsTests.NoTipWhileDebuggingOrModalOrDisabled;
var
  mCurrent: TAtlasTipSituation;
  mEntry: TAtlasCommandUsageEntry;
begin
  mEntry := TAtlasCommandUsageEntry.Create(cClassCompletion);
  mCurrent := Situation(Moment(10, 0, 0));
  mCurrent.DebugPaused := True;
  Assert.AreEqual<TAtlasTipVerdict>(TAtlasTipVerdict.Debugging, TAtlasShortcutTips.Decide(mEntry, mCurrent));
  mCurrent := Situation(Moment(10, 0, 0));
  mCurrent.ModalOpen := True;
  Assert.AreEqual<TAtlasTipVerdict>(TAtlasTipVerdict.Modal, TAtlasShortcutTips.Decide(mEntry, mCurrent));
  mCurrent := Situation(Moment(10, 0, 0));
  mCurrent.Enabled := False;
  Assert.AreEqual<TAtlasTipVerdict>(TAtlasTipVerdict.Disabled, TAtlasShortcutTips.Decide(mEntry, mCurrent));
end;

procedure TAtlasShortcutTipsTests.TwoStepShortCutsKeepBothSteps;
var
  mSteps: TArray<TArray<string>>;
  mView: TAtlasShortcutTipView;
begin
  mSteps := TAtlasShortcutTips.Steps('Strg+Umschalt+C');
  Assert.AreEqual(1, Integer(Length(mSteps)));
  Assert.AreEqual(3, Integer(Length(mSteps[0])));
  Assert.AreEqual('Strg', mSteps[0][0]);
  Assert.AreEqual('Umschalt', mSteps[0][1]);
  Assert.AreEqual('C', mSteps[0][2]);
  // Zwei Schritte: beide mit ihren Tasten.
  mSteps := TAtlasShortcutTips.Steps('Strg+K, Strg+D');
  Assert.AreEqual(2, Integer(Length(mSteps)));
  Assert.AreEqual('Strg', mSteps[0][0]);
  Assert.AreEqual('K', mSteps[0][1]);
  Assert.AreEqual('Strg', mSteps[1][0]);
  Assert.AreEqual('D', mSteps[1][1]);
  Assert.AreEqual('Strg+K, Strg+D', TAtlasShortcutTips.StepsText(mSteps));
  mSteps := TAtlasShortcutTips.Steps('Ctrl+K, D');
  Assert.AreEqual(2, Integer(Length(mSteps)));
  Assert.AreEqual(1, Integer(Length(mSteps[1])));
  Assert.AreEqual('D', mSteps[1][0]);
  // Plus und Komma als Taste.
  mSteps := TAtlasShortcutTips.Steps('Strg++');
  Assert.AreEqual(1, Integer(Length(mSteps)));
  Assert.AreEqual(2, Integer(Length(mSteps[0])));
  Assert.AreEqual('+', mSteps[0][1]);
  mSteps := TAtlasShortcutTips.Steps('Strg+,');
  Assert.AreEqual(1, Integer(Length(mSteps)));
  Assert.AreEqual(',', mSteps[0][1]);
  Assert.AreEqual(0, Integer(Length(TAtlasShortcutTips.Steps(''))));
  mView := TAtlasShortcutTipView.Create('Strg+K, Strg+D', 'Zeile löschen', True);
  Assert.AreEqual(2, Integer(Length(mView.Steps)));
  Assert.AreEqual('Strg+K, Strg+D', mView.KeyText);
  Assert.AreEqual('Zeile löschen', mView.Command);
  Assert.IsTrue(mView.ShowAllKeys);
  // Kürzel aus der Menübeschriftung (Text hinter dem Tabulator).
  Assert.AreEqual('Strg+K, Strg+1', TAtlasShortcutTips.KeyTextOfCaption('Lesezeichen &1'#9'Strg+K, Strg+1'));
  Assert.AreEqual('', TAtlasShortcutTips.KeyTextOfCaption('Speichern'));
end;

procedure TAtlasShortcutTipsTests.ParsesStepsForKeyboardCounting;
var
  mKeys: TArray<Word>;
begin
  mKeys := TAtlasShortcutTips.ParseSteps('Strg+Umschalt+C');
  Assert.AreEqual(1, Integer(Length(mKeys)));
  Assert.AreEqual(Integer(TAtlasKeyConflicts.cScCtrl or TAtlasKeyConflicts.cScShift or Ord('C')), Integer(mKeys[0]));
  mKeys := TAtlasShortcutTips.ParseSteps('Ctrl+K, Ctrl+D');
  Assert.AreEqual(2, Integer(Length(mKeys)));
  Assert.AreEqual(Integer(TAtlasKeyConflicts.cScCtrl or Ord('K')), Integer(mKeys[0]));
  Assert.AreEqual(Integer(TAtlasKeyConflicts.cScCtrl or Ord('D')), Integer(mKeys[1]));
  mKeys := TAtlasShortcutTips.ParseSteps('Strg+K, D');
  Assert.AreEqual(2, Integer(Length(mKeys)));
  Assert.AreEqual(Integer(Ord('D')), Integer(mKeys[1]));
  Assert.AreEqual(0, Integer(Length(TAtlasShortcutTips.ParseSteps('Strg+Unsinn'))));
  Assert.AreEqual(IntToStr(TAtlasKeyConflicts.cScCtrl or Ord('K')) + ',' +
    IntToStr(TAtlasKeyConflicts.cScCtrl or Ord('D')), TAtlasShortcutTips.StepsKey(TAtlasShortcutTips.ParseSteps(
    'Strg+K, Strg+D')));
end;

procedure TAtlasShortcutTipsTests.AtlasCommandFollowsCurrentKey;
var
  mSettings: TAtlasPluginSettings;
  mFunc: TAtlasKeyFunction;
  mEntry: TAtlasKeyEntry;
  mKey: Word;
begin
  // Jede Atlas-Taste hat einen Befehl, den die Zählung und die Tipps kennen. Mehrere Tasten können denselben
  // Befehl haben (#775 zwei Tasten, #777 eigene Taste und Strg+F12); der Befehl führt dann zur ersten.
  for mFunc := Low(TAtlasKeyFunction) to High(TAtlasKeyFunction) do
  begin
    Assert.IsTrue(TAtlasShortcutTips.AtlasCommandId(mFunc).StartsWith('Atlas.'));
    Assert.IsTrue(TAtlasShortcutTips.AtlasFunctionOf(TAtlasShortcutTips.AtlasCommandId(mFunc), mEntry.Func));
    Assert.AreEqual(TAtlasShortcutTips.AtlasCommandId(mFunc), TAtlasShortcutTips.AtlasCommandId(mEntry.Func));
    Assert.IsTrue(Ord(mEntry.Func) <= Ord(mFunc));
  end;
  Assert.IsTrue(TAtlasShortcutTips.AtlasFunctionOf('Atlas.ToggleMethod', mFunc));
  Assert.AreEqual<TAtlasKeyFunction>(TAtlasKeyFunction.MethodToggleUp, mFunc);
  Assert.IsTrue(TAtlasShortcutTips.AtlasFunctionOf('Atlas.UnitSearch', mFunc));
  Assert.AreEqual<TAtlasKeyFunction>(TAtlasKeyFunction.UnitSearch, mFunc);
  Assert.IsTrue(TAtlasShortcutTips.AtlasFunctionOf('Atlas.SwitchTestUnit', mFunc));
  Assert.AreEqual<TAtlasKeyFunction>(TAtlasKeyFunction.TestUnit, mFunc);
  Assert.AreEqual('Atlas.ExpandSelection', TAtlasShortcutTips.AtlasCommandId(TAtlasKeyFunction.ExpandSelection));
  Assert.AreEqual('Atlas.CommandPalette', TAtlasShortcutTips.AtlasCommandId(TAtlasKeyFunction.Palette));
  Assert.IsFalse(TAtlasShortcutTips.AtlasFunctionOf('ecClassCompletion', mFunc));
  // Neu belegt: Die Taste kommt aus den aktuellen Einstellungen, nicht aus einem Zwischenstand.
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.ExpandKey := TAtlasKeyConflicts.cScCtrl or TAtlasKeyConflicts.cScAlt or Ord('E');
  Assert.IsTrue(TAtlasShortcutTips.AtlasFunctionOf('atlas.expandselection', mFunc), 'ohne Groß/klein');
  mKey := 0;
  for mEntry in TAtlasKeyEntry.AllFromSettings(mSettings) do
  begin
    if mEntry.Func = mFunc then
    begin
      mKey := mEntry.Key;
    end;
  end;
  Assert.AreEqual(Integer(TAtlasKeyConflicts.cScCtrl or TAtlasKeyConflicts.cScAlt or Ord('E')), Integer(mKey));
end;

procedure TAtlasShortcutTipsTests.KeyOnlyFunctionsHaveNoPaletteCommand;
var
  mFunc: TAtlasKeyFunction;
begin
  // Karte „Atlas entdecken“ (#757): Tipps zu Tasten ohne Befehl der Palette zeigen die Taste selbst.
  Assert.IsTrue(TAtlasShortcutTips.IsKeyOnly(TAtlasShortcutTips.cPaletteCommandId, mFunc));
  Assert.AreEqual<TAtlasKeyFunction>(TAtlasKeyFunction.Palette, mFunc);
  Assert.IsTrue(TAtlasShortcutTips.IsKeyOnly('atlas.completion', mFunc), 'ohne Groß/klein');
  Assert.AreEqual<TAtlasKeyFunction>(TAtlasKeyFunction.Completion, mFunc);
  Assert.IsTrue(TAtlasShortcutTips.IsKeyOnly('Atlas.Signature', mFunc));
  Assert.IsTrue(TAtlasShortcutTips.IsKeyOnly('Atlas.WelcomeSearch', mFunc));
  // Schnellaktionen der Willkommensseite (#764): Knopf und Taste, kein Befehl der Palette.
  Assert.IsTrue(TAtlasShortcutTips.IsKeyOnly('Atlas.WelcomeQuickBuild', mFunc));
  Assert.AreEqual<TAtlasKeyFunction>(TAtlasKeyFunction.WelcomeQuickBuild, mFunc);
  Assert.IsTrue(TAtlasShortcutTips.IsKeyOnly('Atlas.WelcomeQuickTests', mFunc));
  Assert.AreEqual<TAtlasKeyFunction>(TAtlasKeyFunction.WelcomeQuickTests, mFunc);
  Assert.IsFalse(TAtlasShortcutTips.IsKeyOnly('Atlas.ExpandSelection', mFunc), 'Befehl der Palette');
  Assert.IsFalse(TAtlasShortcutTips.IsKeyOnly('Atlas.QuickToggles', mFunc), 'Befehl der Palette');
  Assert.IsFalse(TAtlasShortcutTips.IsKeyOnly('Atlas.Rename', mFunc), 'keine Atlas-Taste');
  Assert.IsFalse(TAtlasShortcutTips.IsKeyOnly('', mFunc));
end;

procedure TAtlasShortcutTipsTests.PlacesTipBottomRight;
var
  mPlaced: TRect;
begin
  mPlaced := TAtlasShortcutTips.PlaceBottomRight(Rect(100, 200, 900, 800), 300, 60, 12);
  Assert.AreEqual(588, mPlaced.Left);
  Assert.AreEqual(728, mPlaced.Top);
  Assert.AreEqual(888, mPlaced.Right);
  Assert.AreEqual(788, mPlaced.Bottom);
  // Zu klein: bleibt in der Fläche, links bzw. oben bündig.
  mPlaced := TAtlasShortcutTips.PlaceBottomRight(Rect(100, 200, 300, 230), 300, 60, 12);
  Assert.AreEqual(100, mPlaced.Left);
  Assert.AreEqual(200, mPlaced.Top);
  Assert.AreEqual(400, mPlaced.Right);
end;

procedure TAtlasShortcutTipsTests.RecognizesShortCutStrokes;
begin
  Assert.IsTrue(TAtlasShortcutTips.IsShortCutStroke(TAtlasKeyConflicts.cScCtrl or Ord('S')));
  Assert.IsTrue(TAtlasShortcutTips.IsShortCutStroke(TAtlasKeyConflicts.cScAlt or $0D));
  Assert.IsTrue(TAtlasShortcutTips.IsShortCutStroke($78), 'F9');
  Assert.IsTrue(TAtlasShortcutTips.IsShortCutStroke(TAtlasKeyConflicts.cScShift or $7B), 'Umschalt+F12');
  Assert.IsFalse(TAtlasShortcutTips.IsShortCutStroke(Ord('A')), 'Tippen');
  Assert.IsFalse(TAtlasShortcutTips.IsShortCutStroke(TAtlasKeyConflicts.cScShift or Ord('A')), 'Großbuchstabe');
  Assert.IsFalse(TAtlasShortcutTips.IsShortCutStroke(TAtlasKeyConflicts.cScCtrl), 'nur Umschalttaste');
end;

{ TAtlasCommandUsageTests }

procedure TAtlasCommandUsageTests.CountsAndRoundTrips;
var
  mUsage, mLoaded: TAtlasCommandUsage;
  mEntry: TAtlasCommandUsageEntry;
begin
  mUsage := TAtlasCommandUsage.Create;
  mLoaded := TAtlasCommandUsage.Create;
  try
    Assert.IsFalse(mUsage.Changed);
    mUsage.Count(cClassCompletion, TAtlasCommandInput.Mouse, Moment(9, 0, 0));
    mUsage.Count('ECCLASSCOMPLETION', TAtlasCommandInput.Mouse, Moment(9, 30, 0));
    mUsage.Count(cClassCompletion, TAtlasCommandInput.Keyboard, Moment(10, 0, 0));
    mUsage.Count('Atlas.CodeActions', TAtlasCommandInput.Mouse, Moment(10, 1, 0));
    mUsage.Count('', TAtlasCommandInput.Mouse, Moment(10, 1, 0));
    Assert.IsTrue(mUsage.Changed);
    mEntry := mUsage.Entry(cClassCompletion);
    TAtlasShortcutTips.MarkShown(mEntry, Moment(9, 0, 1));
    mUsage.Put(mEntry);
    Assert.AreEqual(2, Integer(Length(mUsage.Entries)), 'Groß/klein egal, leere Id nicht');
    // Zustand der Tipps aus shortcut-tips.json, Zähler aus usage.json (#757).
    Assert.IsTrue(mLoaded.Parse(mUsage.ToJson));
    Assert.IsTrue(mLoaded.ParseCounts(mUsage.CountsToJson));
    Assert.IsTrue(mLoaded.Find('ecclasscompletion', mEntry));
    Assert.AreEqual(cClassCompletion, mEntry.Id);
    Assert.AreEqual(2, mEntry.Mouse);
    Assert.AreEqual(1, mEntry.Keyboard);
    Assert.AreEqual(3, mLoaded.UseCount(cClassCompletion));
    Assert.AreEqual(1, mLoaded.UseCount('Atlas.CodeActions'));
    Assert.AreEqual(0, mLoaded.UseCount('Unbekannt'));
    Assert.AreEqual(TAtlasCommandUsage.TimeText(Moment(10, 0, 0)), TAtlasCommandUsage.TimeText(mEntry.LastUsed));
    Assert.AreEqual(TAtlasCommandUsage.TimeText(Moment(9, 0, 1)), TAtlasCommandUsage.TimeText(mEntry.LastTip));
    Assert.IsFalse(mEntry.Never);
    Assert.IsFalse(mLoaded.Find('Unbekannt', mEntry));
    Assert.AreEqual('Unbekannt', mEntry.Id);
    Assert.AreEqual(0, mEntry.Total);
    Assert.AreEqual('2026-10-15T09:30:00', TAtlasCommandUsage.TimeText(Moment(9, 30, 0)));
    Assert.AreEqual('', TAtlasCommandUsage.TimeText(0));
    Assert.AreEqual(TAtlasCommandUsage.TimeText(Moment(9, 30, 0)),
      TAtlasCommandUsage.TimeText(TAtlasCommandUsage.TimeOf('2026-10-15T09:30:00.123Z')));
    Assert.AreEqual<TDateTime>(0, TAtlasCommandUsage.TimeOf('gestern'));
  finally
    mLoaded.Free;
    mUsage.Free;
  end;
end;

procedure TAtlasCommandUsageTests.KeepsUnknownTopLevelFields;
var
  mUsage: TAtlasCommandUsage;
  mJson: string;
begin
  mUsage := TAtlasCommandUsage.Create;
  try
    Assert.IsTrue(mUsage.Parse('{"format":1,"commands":{"X":{"mouse":1,"keyboard":"2","extra":true}},' +
      '"discover":{"seen":["Atlas.CodeActions"]}}'));
    Assert.AreEqual(2, mUsage.Entry('X').Keyboard, 'Zahl auch als Text');
    mJson := mUsage.ToJson;
    Assert.Contains(mJson, '"discover"');
    Assert.Contains(mJson, 'Atlas.CodeActions');
    Assert.Contains(mJson, '"format":1');
  finally
    mUsage.Free;
  end;
end;

procedure TAtlasCommandUsageTests.HigherFormatIsNotOverwritten;
var
  mUsage: TAtlasCommandUsage;
  mFileName: string;
begin
  mUsage := TAtlasCommandUsage.Create;
  try
    Assert.IsFalse(mUsage.Parse('{"format":2,"commands":{"X":{"mouse":1}}}'));
    Assert.IsFalse(mUsage.Writable);
    Assert.AreEqual(0, mUsage.UseCount('X'));
    mFileName := TPath.Combine(TPath.GetTempPath, 'atlas-usage-' + FormatDateTime('hhnnsszzz', Now) + '.json');
    TFile.WriteAllText(mFileName, '{"format":2}');
    try
      mUsage.Clear;
      Assert.IsTrue(mUsage.Writable);
      mUsage.Count('X', TAtlasCommandInput.Mouse, Moment(10, 0, 0));
      Assert.IsFalse(mUsage.SaveToFile(mFileName), 'neuere Fassung bleibt');
      Assert.IsFalse(mUsage.Writable);
      Assert.Contains(TFile.ReadAllText(mFileName, TEncoding.UTF8), '"format":2');
    finally
      System.SysUtils.DeleteFile(mFileName);
    end;
  finally
    mUsage.Free;
  end;
end;

procedure TAtlasCommandUsageTests.BrokenJsonStartsEmpty;
var
  mUsage: TAtlasCommandUsage;
begin
  mUsage := TAtlasCommandUsage.Create;
  try
    mUsage.Count('X', TAtlasCommandInput.Mouse, Moment(10, 0, 0));
    Assert.IsFalse(mUsage.Parse('kein JSON'));
    Assert.AreEqual(0, Integer(Length(mUsage.Entries)));
    Assert.IsTrue(mUsage.Writable);
    Assert.IsFalse(mUsage.Parse('[1,2]'));
    Assert.IsTrue(mUsage.Parse('{"commands":{"":{"mouse":1},"Y":5}}'));
    Assert.AreEqual(0, Integer(Length(mUsage.Entries)), 'leere Namen und Nicht-Objekte übergangen');
    Assert.IsFalse(mUsage.LoadFromFile(TPath.Combine(TPath.GetTempPath, 'atlas-gibt-es-nicht.json')));
  finally
    mUsage.Free;
  end;
end;

procedure TAtlasCommandUsageTests.SavesAndLoadsFile;
var
  mUsage, mLoaded: TAtlasCommandUsage;
  mFolder, mFileName: string;
  mEntry: TAtlasCommandUsageEntry;
begin
  mFolder := TPath.Combine(TPath.GetTempPath, 'atlas-usage-' + FormatDateTime('hhnnsszzz', Now));
  mFileName := TAtlasCommandUsage.DefaultFile(mFolder);
  mUsage := TAtlasCommandUsage.Create;
  mLoaded := TAtlasCommandUsage.Create;
  try
    mUsage.Count(cClassCompletion, TAtlasCommandInput.Mouse, Moment(10, 0, 0));
    mEntry := mUsage.Entry(cClassCompletion);
    mEntry.Never := True;
    mUsage.Put(mEntry);
    mUsage.SaveToFiles(mFileName, TAtlasCommandUsage.DefaultUsageFile(mFolder));
    Assert.IsTrue(TFile.Exists(mFileName), 'legt den Ordner an');
    Assert.IsTrue(TFile.Exists(TAtlasCommandUsage.DefaultUsageFile(mFolder)));
    Assert.IsFalse(mUsage.Changed);
    mLoaded.LoadFromFiles(mFileName, TAtlasCommandUsage.DefaultUsageFile(mFolder));
    Assert.IsTrue(mLoaded.Entry(cClassCompletion).Never);
    Assert.AreEqual(1, mLoaded.Entry(cClassCompletion).Mouse);
    Assert.IsFalse(mLoaded.Changed);
    Assert.IsFalse(TFile.Exists(mFileName + '.tmp'));
    Assert.IsFalse(TFile.Exists(TAtlasCommandUsage.DefaultUsageFile(mFolder) + '.tmp'));
  finally
    mLoaded.Free;
    mUsage.Free;
    if TDirectory.Exists(mFolder) then
    begin
      TDirectory.Delete(mFolder, True);
    end;
  end;
end;

procedure TAtlasCommandUsageTests.RarelyByKeyboard;
var
  mEntry: TAtlasCommandUsageEntry;
begin
  mEntry := TAtlasCommandUsageEntry.Create('X');
  mEntry.Mouse := 2;
  Assert.IsFalse(mEntry.RarelyByKeyboard, 'zu wenige Aufrufe');
  mEntry.Mouse := 3;
  Assert.IsTrue(mEntry.RarelyByKeyboard);
  mEntry.Keyboard := 1;
  Assert.IsFalse(mEntry.RarelyByKeyboard, 'ein Viertel per Tastatur');
  mEntry.Mouse := 8;
  Assert.IsTrue(mEntry.RarelyByKeyboard);
  mEntry.Mouse := 0;
  mEntry.Keyboard := 5;
  Assert.IsFalse(mEntry.RarelyByKeyboard);
end;

procedure TAtlasCommandUsageTests.FileIsNotTheCompletionUsage;
var
  mFileName: string;
begin
  // %APPDATA%\Atlas\usage.json gehört der lernenden Vervollständigung (#418) und bleibt unberührt; die Zählung
  // der Befehle (#757) liegt in %LOCALAPPDATA%\Atlas\usage.json, der Zustand der Tipps in shortcut-tips.json.
  mFileName := TAtlasCommandUsage.DefaultFile('LocalAppData');
  Assert.IsTrue(mFileName.EndsWith('shortcut-tips.json'));
  Assert.IsTrue(mFileName.StartsWith(IncludeTrailingPathDelimiter('LocalAppData') + 'Atlas'));
  mFileName := TAtlasCommandUsage.DefaultUsageFile('LocalAppData');
  Assert.AreEqual(IncludeTrailingPathDelimiter(IncludeTrailingPathDelimiter('LocalAppData') + 'Atlas') + 'usage.json',
    mFileName);
end;

/// <summary>Namen aller Felder in den Einträgen von "commands", sortiert und ohne Doppelte, mit Komma.</summary>
function FieldNames(const AJson: string): string;
var
  mRoot: TJSONValue;
  mCommands: TJSONValue;
  mIndex, mInner: Integer;
  mItem: TJSONObject;
  mNames: TStringList;
begin
  Result := '';
  mRoot := TJSONObject.ParseJSONValue(AJson);
  mNames := TStringList.Create;
  try
    mNames.Sorted := True;
    mNames.Duplicates := dupIgnore;
    if not (mRoot is TJSONObject) then
    begin
      Exit;
    end;
    mCommands := TJSONObject(mRoot).GetValue('commands');
    if not (mCommands is TJSONObject) then
    begin
      Exit;
    end;
    for mIndex := 0 to TJSONObject(mCommands).Count - 1 do
    begin
      if TJSONObject(mCommands).Pairs[mIndex].JsonValue is TJSONObject then
      begin
        mItem := TJSONObject(TJSONObject(mCommands).Pairs[mIndex].JsonValue);
        for mInner := 0 to mItem.Count - 1 do
        begin
          mNames.Add(mItem.Pairs[mInner].JsonString.Value);
        end;
      end;
    end;
    Result := mNames.CommaText;
  finally
    mNames.Free;
    mRoot.Free;
  end;
end;

/// <summary>Namen der Felder oberster Ebene, sortiert, mit Komma.</summary>
function TopNames(const AJson: string): string;
var
  mRoot: TJSONValue;
  mIndex: Integer;
  mNames: TStringList;
begin
  Result := '';
  mRoot := TJSONObject.ParseJSONValue(AJson);
  mNames := TStringList.Create;
  try
    mNames.Sorted := True;
    if mRoot is TJSONObject then
    begin
      for mIndex := 0 to TJSONObject(mRoot).Count - 1 do
      begin
        mNames.Add(TJSONObject(mRoot).Pairs[mIndex].JsonString.Value);
      end;
    end;
    Result := mNames.CommaText;
  finally
    mNames.Free;
    mRoot.Free;
  end;
end;

procedure TAtlasCommandUsageTests.UsageJsonHoldsOnlyIdsCountersAndDate;
var
  mUsage: TAtlasCommandUsage;
  mEntry: TAtlasCommandUsageEntry;
begin
  // #757: usage.json enthält nur Befehlskennungen, Zähler und Datum.
  mUsage := TAtlasCommandUsage.Create;
  try
    mUsage.Count('Atlas.CodeActions', TAtlasCommandInput.Mouse, Moment(9, 0, 0));
    mUsage.Count(cClassCompletion, TAtlasCommandInput.Keyboard, Moment(9, 5, 0));
    mEntry := mUsage.Entry(cClassCompletion);
    mEntry.Never := True;
    TAtlasShortcutTips.MarkShown(mEntry, Moment(9, 6, 0));
    mUsage.Put(mEntry);
    mUsage.SetSection('discover', '{"blocked":["rename"],"last":"codeActions"}');
    Assert.AreEqual('commands,format', TopNames(mUsage.CountsToJson));
    Assert.AreEqual('keyboard,lastUsed,mouse', FieldNames(mUsage.CountsToJson));
    Assert.Contains(mUsage.CountsToJson, '"Atlas.CodeActions"');
    Assert.Contains(mUsage.CountsToJson, '"lastUsed":"2026-10-15T09:05:00"');
    Assert.DoesNotContain(mUsage.CountsToJson, 'rename');
    // Zustand der Tipps ohne Zähler in shortcut-tips.json.
    Assert.AreEqual('lastTip,never', FieldNames(mUsage.ToJson));
    Assert.AreEqual('commands,discover,format', TopNames(mUsage.ToJson));
    Assert.DoesNotContain(mUsage.ToJson, 'Atlas.CodeActions', False, 'ohne Tipp-Zustand kein Eintrag');
  finally
    mUsage.Free;
  end;
end;

procedure TAtlasCommandUsageTests.TrackingOffCountsNothing;
var
  mUsage: TAtlasCommandUsage;
  mEntry: TAtlasCommandUsageEntry;
begin
  mUsage := TAtlasCommandUsage.Create;
  try
    Assert.IsTrue(mUsage.Tracking, 'Vorgabe: zählen');
    mUsage.Tracking := False;
    mUsage.Count('Atlas.CodeActions', TAtlasCommandInput.Mouse, Moment(9, 0, 0));
    mUsage.Count('Atlas.CodeActions', TAtlasCommandInput.Keyboard, Moment(9, 0, 0));
    Assert.AreEqual(0, mUsage.UseCount('Atlas.CodeActions'));
    Assert.IsFalse(mUsage.CountsChanged, 'nichts zu schreiben');
    // Tipps dürfen weiter ihren Zustand merken.
    mEntry := mUsage.Entry('Atlas.CodeActions');
    mEntry.Never := True;
    mUsage.Put(mEntry);
    Assert.IsTrue(mUsage.TipsChanged);
    Assert.IsFalse(mUsage.CountsChanged);
    mUsage.Clear;
    Assert.IsFalse(mUsage.Tracking, 'Clear lässt die Einstellung');
    mUsage.Tracking := True;
    mUsage.Count('Atlas.CodeActions', TAtlasCommandInput.Mouse, Moment(9, 0, 0));
    Assert.AreEqual(1, mUsage.UseCount('Atlas.CodeActions'));
  finally
    mUsage.Free;
  end;
end;

procedure TAtlasCommandUsageTests.ResetCountsKeepsTipState;
var
  mUsage: TAtlasCommandUsage;
  mEntry: TAtlasCommandUsageEntry;
begin
  mUsage := TAtlasCommandUsage.Create;
  try
    mUsage.Count('Atlas.CodeActions', TAtlasCommandInput.Mouse, Moment(9, 0, 0));
    mUsage.Count(cClassCompletion, TAtlasCommandInput.Mouse, Moment(9, 0, 0));
    mEntry := mUsage.Entry(cClassCompletion);
    mEntry.Never := True;
    mUsage.Put(mEntry);
    mUsage.Changed := False;
    mUsage.ResetCounts;
    Assert.IsTrue(mUsage.CountsChanged);
    Assert.AreEqual(0, mUsage.UseCount('Atlas.CodeActions'));
    Assert.AreEqual(0, mUsage.UseCount(cClassCompletion));
    Assert.IsTrue(mUsage.Entry(cClassCompletion).Never, '„Nicht mehr zeigen“ bleibt');
    Assert.AreEqual<TDateTime>(0, mUsage.Entry('Atlas.CodeActions').LastUsed);
    Assert.AreEqual('', FieldNames(mUsage.CountsToJson), 'usage.json leer');
    mUsage.Changed := False;
    mUsage.ResetCounts;
    Assert.IsFalse(mUsage.Changed, 'nichts mehr zurückzusetzen');
  finally
    mUsage.Free;
  end;
end;

procedure TAtlasCommandUsageTests.OlderTipsFileMovesCountsToUsageJson;
var
  mUsage, mLoaded: TAtlasCommandUsage;
  mFolder, mTipsFile, mUsageFile: string;
begin
  // Ältere Fassung von #600: Zähler in shortcut-tips.json, usage.json fehlt.
  mFolder := TPath.Combine(TPath.GetTempPath, 'atlas-usage-' + FormatDateTime('hhnnsszzz', Now) + '-m');
  mTipsFile := TAtlasCommandUsage.DefaultFile(mFolder);
  mUsageFile := TAtlasCommandUsage.DefaultUsageFile(mFolder);
  ForceDirectories(ExtractFileDir(mTipsFile));
  TFile.WriteAllText(mTipsFile, '{"format":1,"commands":{"Atlas.Rename":{"mouse":2,"keyboard":1,' +
    '"lastUsed":"2026-10-01T08:00:00","never":true}}}');
  mUsage := TAtlasCommandUsage.Create;
  mLoaded := TAtlasCommandUsage.Create;
  try
    mUsage.LoadFromFiles(mTipsFile, mUsageFile);
    Assert.AreEqual(3, mUsage.UseCount('Atlas.Rename'));
    Assert.IsTrue(mUsage.Entry('Atlas.Rename').Never);
    Assert.IsTrue(mUsage.CountsChanged, 'beim nächsten Speichern umziehen');
    mUsage.SaveToFiles(mTipsFile, mUsageFile);
    Assert.IsTrue(TFile.Exists(mUsageFile));
    Assert.DoesNotContain(TFile.ReadAllText(mTipsFile, TEncoding.UTF8), 'mouse');
    Assert.Contains(TFile.ReadAllText(mUsageFile, TEncoding.UTF8), '"mouse":2');
    mLoaded.LoadFromFiles(mTipsFile, mUsageFile);
    Assert.AreEqual(3, mLoaded.UseCount('Atlas.Rename'));
    Assert.IsTrue(mLoaded.Entry('Atlas.Rename').Never);
    Assert.IsFalse(mLoaded.Changed);
  finally
    mLoaded.Free;
    mUsage.Free;
    if TDirectory.Exists(mFolder) then
    begin
      TDirectory.Delete(mFolder, True);
    end;
  end;
end;

procedure TAtlasCommandUsageTests.UsageJsonWinsOverOlderCounts;
var
  mUsage: TAtlasCommandUsage;
begin
  mUsage := TAtlasCommandUsage.Create;
  try
    Assert.IsTrue(mUsage.Parse('{"format":1,"commands":{"A":{"mouse":5,"never":true},"B":{"keyboard":4}}}'));
    Assert.IsTrue(mUsage.ParseCounts('{"format":1,"commands":{"A":{"mouse":1,"lastUsed":"2026-10-01T08:00:00"},' +
      '"C":{"keyboard":"2"},"":{"mouse":1},"D":7}}'));
    Assert.AreEqual(1, mUsage.UseCount('A'));
    Assert.IsTrue(mUsage.Entry('A').Never);
    Assert.AreEqual(0, mUsage.UseCount('B'), 'alte Zähler fallen weg');
    Assert.AreEqual(2, mUsage.UseCount('C'));
    Assert.AreEqual(0, mUsage.UseCount('D'));
    Assert.IsFalse(mUsage.ParseCounts('kein JSON'));
    Assert.IsTrue(mUsage.CountsWritable);
  finally
    mUsage.Free;
  end;
end;

procedure TAtlasCommandUsageTests.SectionsRoundTrip;
var
  mUsage, mLoaded: TAtlasCommandUsage;
begin
  mUsage := TAtlasCommandUsage.Create;
  mLoaded := TAtlasCommandUsage.Create;
  try
    Assert.AreEqual('', mUsage.Section('discover'));
    mUsage.SetSection('discover', '{"blocked":["rename"],"last":"codeActions"}');
    Assert.IsTrue(mUsage.TipsChanged);
    Assert.IsFalse(mUsage.CountsChanged);
    Assert.Contains(mUsage.Section('discover'), '"rename"');
    mUsage.SetSection('other', '[1,2]');
    Assert.IsTrue(mLoaded.Parse(mUsage.ToJson));
    Assert.Contains(mLoaded.Section('discover'), '"last":"codeActions"');
    Assert.AreEqual('[1,2]', mLoaded.Section('other'));
    // Vergebene Namen und kaputter Text ändern nichts.
    mLoaded.SetSection('commands', '{}');
    mLoaded.SetSection('format', '2');
    mLoaded.SetSection('discover', '{kaputt');
    Assert.Contains(mLoaded.ToJson, '"format":1');
    Assert.Contains(mLoaded.Section('discover'), 'codeActions');
    mLoaded.SetSection('discover', '');
    Assert.AreEqual('', mLoaded.Section('discover'));
    Assert.DoesNotContain(mLoaded.ToJson, 'discover');
    Assert.AreEqual('[1,2]', mLoaded.Section('other'));
  finally
    mLoaded.Free;
    mUsage.Free;
  end;
end;

procedure TAtlasCommandUsageTests.HigherFormatUsageJsonIsNotOverwritten;
var
  mUsage: TAtlasCommandUsage;
  mFileName: string;
begin
  mUsage := TAtlasCommandUsage.Create;
  try
    Assert.IsFalse(mUsage.ParseCounts('{"format":2,"commands":{"X":{"mouse":1}}}'));
    Assert.IsFalse(mUsage.CountsWritable);
    Assert.AreEqual(0, mUsage.UseCount('X'));
    mFileName := TPath.Combine(TPath.GetTempPath, 'atlas-usage-' + FormatDateTime('hhnnsszzz', Now) + '-f.json');
    TFile.WriteAllText(mFileName, '{"format":2}');
    try
      mUsage.Clear;
      Assert.IsTrue(mUsage.CountsWritable);
      mUsage.Count('X', TAtlasCommandInput.Mouse, Moment(10, 0, 0));
      Assert.IsFalse(mUsage.SaveCountsToFile(mFileName), 'neuere Fassung bleibt');
      Assert.IsFalse(mUsage.CountsWritable);
      Assert.Contains(TFile.ReadAllText(mFileName, TEncoding.UTF8), '"format":2');
    finally
      System.SysUtils.DeleteFile(mFileName);
    end;
  finally
    mUsage.Free;
  end;
end;

procedure TAtlasCommandUsageTests.BrokenFileSetAsideLockedFileKept;
var
  mUsage: TAtlasCommandUsage;
  mFolder, mTipsFile, mUsageFile: string;
  mLock: TFileStream;
begin
  mFolder := TPath.Combine(TPath.GetTempPath, 'atlas-usage-' + IntToStr(Random(MaxInt)));
  mTipsFile := TPath.Combine(mFolder, 'shortcut-tips.json');
  mUsageFile := TPath.Combine(mFolder, 'usage.json');
  ForceDirectories(mFolder);
  mUsage := TAtlasCommandUsage.Create;
  try
    TFile.WriteAllText(mTipsFile, '{kaputt');
    TFile.WriteAllText(mUsageFile, '[1, 2]');
    mUsage.LoadFromFiles(mTipsFile, mUsageFile);
    Assert.IsTrue(TFile.Exists(mTipsFile + TAtlasDataFile.cDefectExtension), 'Tipps beiseitegelegt');
    Assert.IsTrue(TFile.Exists(mUsageFile + TAtlasDataFile.cDefectExtension), 'Zähler beiseitegelegt');
    Assert.IsTrue(mUsage.Writable);
    Assert.IsTrue(mUsage.CountsWritable);
    mUsage.Count('X', TAtlasCommandInput.Mouse, Moment(10, 0, 0));
    Assert.IsTrue(mUsage.SaveCountsToFile(mUsageFile));
    mLock := TFileStream.Create(mUsageFile, fmOpenRead or fmShareExclusive);
    try
      mUsage.LoadFromFiles(mTipsFile, mUsageFile);
    finally
      mLock.Free;
    end;
    Assert.IsFalse(mUsage.CountsWritable, 'beim Lesen gesperrt');
    Assert.AreEqual(0, mUsage.UseCount('X'));
    mUsage.Count('Y', TAtlasCommandInput.Mouse, Moment(10, 0, 0));
    Assert.IsFalse(mUsage.SaveCountsToFile(mUsageFile), 'nicht überschreiben');
    Assert.Contains(TFile.ReadAllText(mUsageFile, TEncoding.UTF8), '"X"');
    Assert.DoesNotContain(TFile.ReadAllText(mUsageFile, TEncoding.UTF8), '"Y"');
  finally
    mUsage.Free;
    TDirectory.Delete(mFolder, True);
  end;
  // Gemeldete Datendateien vergessen: Das Register bliebe sonst als Leck stehen.
  TAtlasDataFile.ForgetReports;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasShortcutTipsTests);
  TDUnitX.RegisterTestFixture(TAtlasCommandUsageTests);

end.
