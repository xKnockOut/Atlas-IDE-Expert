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
  System.SysUtils,
  System.Classes,
  System.Types,
  System.IOUtils,
  System.JSON,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Commands.KeyConflicts,
  Atlas.Core.Commands.Usage,
  Atlas.Core.Commands.ShortcutTips;

const
  ClassCompletion = 'ecClassCompletion';

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
  Usage: TAtlasCommandUsage;
begin
  Usage := TAtlasCommandUsage.Create;
  try
    // Abnahme: Klasse vervollständigen über das Kontextmenü zeigt einen Tipp mit Strg+Umschalt+C.
    Usage.Count(ClassCompletion, TAtlasCommandInput.Mouse, Moment(10, 0, 0));
    Assert.IsTrue(TAtlasShortcutTips.Decide(Usage.Entry(ClassCompletion), Situation(Moment(10, 0, 0))) =
      TAtlasTipVerdict.Show);
    Assert.AreEqual(1, Usage.Entry(ClassCompletion).Mouse);
  finally
    Usage.Free;
  end;
end;

procedure TAtlasShortcutTipsTests.SecondTipSameDayIsSuppressed;
var
  Entry: TAtlasCommandUsageEntry;
  Later: TAtlasTipSituation;
begin
  Entry := TAtlasCommandUsageEntry.Create(ClassCompletion);
  Assert.IsTrue(TAtlasShortcutTips.Decide(Entry, Situation(Moment(10, 0, 0))) = TAtlasTipVerdict.Show);
  TAtlasShortcutTips.MarkShown(Entry, Moment(10, 0, 0));
  // Zweiter Aufruf am selben Tag (lange nach dem 30-s-Abstand): kein Tipp.
  Later := Situation(Moment(16, 30, 0));
  Later.LastTipAt := Moment(10, 0, 0);
  Assert.IsTrue(TAtlasShortcutTips.Decide(Entry, Later) = TAtlasTipVerdict.ShownToday);
  // Kurz vor Mitternacht noch derselbe Tag, am nächsten Tag wieder.
  Later := Situation(Moment(23, 59, 59));
  Assert.IsTrue(TAtlasShortcutTips.Decide(Entry, Later) = TAtlasTipVerdict.ShownToday);
  Later := Situation(Moment(10, 0, 0) + 1);
  Assert.IsTrue(TAtlasShortcutTips.Decide(Entry, Later) = TAtlasTipVerdict.Show);
  Assert.IsTrue(TAtlasShortcutTips.SameDay(Moment(0, 0, 0), Moment(23, 59, 59)));
  Assert.IsFalse(TAtlasShortcutTips.SameDay(0, Moment(10, 0, 0)), 'nie gezeigt');
end;

procedure TAtlasShortcutTipsTests.ThreeKeyboardUsesStopTips;
var
  Usage: TAtlasCommandUsage;
  Index: Integer;
begin
  Usage := TAtlasCommandUsage.Create;
  try
    for Index := 1 to 2 do
      Usage.Count(ClassCompletion, TAtlasCommandInput.Keyboard, Moment(9, Index, 0));
    Usage.Count(ClassCompletion, TAtlasCommandInput.Mouse, Moment(10, 0, 0));
    Assert.IsTrue(TAtlasShortcutTips.Decide(Usage.Entry(ClassCompletion), Situation(Moment(10, 0, 0))) =
      TAtlasTipVerdict.Show, 'zwei Mal über das Kürzel: noch ein Tipp');
    Usage.Count(ClassCompletion, TAtlasCommandInput.Keyboard, Moment(10, 5, 0));
    Assert.AreEqual(3, Usage.Entry(ClassCompletion).Keyboard);
    Assert.IsTrue(TAtlasShortcutTips.Decide(Usage.Entry(ClassCompletion), Situation(Moment(11, 0, 0) + 1)) =
      TAtlasTipVerdict.Learned, 'nach dreimaliger Nutzung des Kürzels kein Tipp mehr');
  finally
    Usage.Free;
  end;
end;

procedure TAtlasShortcutTipsTests.TipsKeepThirtySecondsApart;
var
  Entry: TAtlasCommandUsageEntry;
  Current: TAtlasTipSituation;
begin
  // Ein anderer Befehl hat gerade einen Tipp bekommen.
  Entry := TAtlasCommandUsageEntry.Create('SearchFindCommand');
  Current := Situation(Moment(10, 0, 29));
  Current.LastTipAt := Moment(10, 0, 0);
  Assert.IsTrue(TAtlasShortcutTips.Decide(Entry, Current) = TAtlasTipVerdict.TooSoon);
  Current := Situation(Moment(10, 0, 31));
  Current.LastTipAt := Moment(10, 0, 0);
  Assert.IsTrue(TAtlasShortcutTips.Decide(Entry, Current) = TAtlasTipVerdict.Show);
  // Zurückgestellte Uhr: auch dann nicht gleich wieder.
  Current := Situation(Moment(9, 59, 50));
  Current.LastTipAt := Moment(10, 0, 0);
  Assert.IsTrue(TAtlasShortcutTips.Decide(Entry, Current) = TAtlasTipVerdict.TooSoon);
end;

procedure TAtlasShortcutTipsTests.NeverShowAgainOnlyForThatCommand;
var
  Usage: TAtlasCommandUsage;
  Entry: TAtlasCommandUsageEntry;
begin
  Usage := TAtlasCommandUsage.Create;
  try
    Entry := Usage.Entry(ClassCompletion);
    Entry.Never := True;
    Usage.Put(Entry);
    Assert.IsTrue(TAtlasShortcutTips.Decide(Usage.Entry(ClassCompletion), Situation(Moment(10, 0, 0))) =
      TAtlasTipVerdict.Hidden);
    // Dauerhaft: auch an späteren Tagen und nach dem Lesen der Datei.
    Usage.Parse(Usage.ToJson);
    Assert.IsTrue(TAtlasShortcutTips.Decide(Usage.Entry(ClassCompletion), Situation(Moment(10, 0, 0) + 30)) =
      TAtlasTipVerdict.Hidden);
    // Andere Befehle zeigen weiter Tipps.
    Assert.IsTrue(TAtlasShortcutTips.Decide(Usage.Entry('SearchFindCommand'), Situation(Moment(10, 0, 0))) =
      TAtlasTipVerdict.Show);
  finally
    Usage.Free;
  end;
end;

procedure TAtlasShortcutTipsTests.CommandWithoutShortCutShowsNoTip;
var
  Current: TAtlasTipSituation;
begin
  Current := Situation(Moment(10, 0, 0));
  Current.KeyText := '';
  Assert.IsTrue(TAtlasShortcutTips.Decide(TAtlasCommandUsageEntry.Create('ProjectOptions'), Current) =
    TAtlasTipVerdict.NoShortCut);
  Current.KeyText := '   ';
  Assert.IsTrue(TAtlasShortcutTips.Decide(TAtlasCommandUsageEntry.Create('ProjectOptions'), Current) =
    TAtlasTipVerdict.NoShortCut);
end;

procedure TAtlasShortcutTipsTests.KeyboardUseShowsNoTip;
var
  Current: TAtlasTipSituation;
begin
  Current := Situation(Moment(10, 0, 0));
  Current.ViaKeyboard := True;
  Assert.IsTrue(TAtlasShortcutTips.Decide(TAtlasCommandUsageEntry.Create(ClassCompletion), Current) =
    TAtlasTipVerdict.ViaKeyboard);
end;

procedure TAtlasShortcutTipsTests.ScopeAtlasSkipsIdeCommands;
var
  Current: TAtlasTipSituation;
begin
  Current := TAtlasTipSituation.Create(True, TAtlasTipScope.Atlas, False, 'Strg+Umschalt+C', Moment(10, 0, 0));
  Assert.IsTrue(TAtlasShortcutTips.Decide(TAtlasCommandUsageEntry.Create(ClassCompletion), Current) =
    TAtlasTipVerdict.OutOfScope);
  Current := TAtlasTipSituation.Create(True, TAtlasTipScope.Atlas, True, 'Alt+Eingabe', Moment(10, 0, 0));
  Assert.IsTrue(TAtlasShortcutTips.Decide(TAtlasCommandUsageEntry.Create('Atlas.CodeActions'), Current) =
    TAtlasTipVerdict.Show);
  Assert.IsTrue(TAtlasShortcutTips.ScopeOf('atlas') = TAtlasTipScope.Atlas);
  Assert.IsTrue(TAtlasShortcutTips.ScopeOf(' ATLAS ') = TAtlasTipScope.Atlas);
  Assert.IsTrue(TAtlasShortcutTips.ScopeOf('all') = TAtlasTipScope.All);
  Assert.IsTrue(TAtlasShortcutTips.ScopeOf('unsinn') = TAtlasTipScope.All, 'Vorgabe all');
  Assert.AreEqual('atlas', TAtlasShortcutTips.ScopeName(TAtlasTipScope.Atlas));
  Assert.AreEqual('all', TAtlasShortcutTips.ScopeName(TAtlasTipScope.All));
end;

procedure TAtlasShortcutTipsTests.NoTipWhileDebuggingOrModalOrDisabled;
var
  Current: TAtlasTipSituation;
  Entry: TAtlasCommandUsageEntry;
begin
  Entry := TAtlasCommandUsageEntry.Create(ClassCompletion);
  Current := Situation(Moment(10, 0, 0));
  Current.DebugPaused := True;
  Assert.IsTrue(TAtlasShortcutTips.Decide(Entry, Current) = TAtlasTipVerdict.Debugging);
  Current := Situation(Moment(10, 0, 0));
  Current.ModalOpen := True;
  Assert.IsTrue(TAtlasShortcutTips.Decide(Entry, Current) = TAtlasTipVerdict.Modal);
  Current := Situation(Moment(10, 0, 0));
  Current.Enabled := False;
  Assert.IsTrue(TAtlasShortcutTips.Decide(Entry, Current) = TAtlasTipVerdict.Disabled);
end;

procedure TAtlasShortcutTipsTests.TwoStepShortCutsKeepBothSteps;
var
  Steps: TArray<TArray<string>>;
  View: TAtlasShortcutTipView;
begin
  Steps := TAtlasShortcutTips.Steps('Strg+Umschalt+C');
  Assert.AreEqual(1, Integer(Length(Steps)));
  Assert.AreEqual(3, Integer(Length(Steps[0])));
  Assert.AreEqual('Strg', Steps[0][0]);
  Assert.AreEqual('Umschalt', Steps[0][1]);
  Assert.AreEqual('C', Steps[0][2]);
  // Zwei Schritte: beide mit ihren Tasten.
  Steps := TAtlasShortcutTips.Steps('Strg+K, Strg+D');
  Assert.AreEqual(2, Integer(Length(Steps)));
  Assert.AreEqual('Strg', Steps[0][0]);
  Assert.AreEqual('K', Steps[0][1]);
  Assert.AreEqual('Strg', Steps[1][0]);
  Assert.AreEqual('D', Steps[1][1]);
  Assert.AreEqual('Strg+K, Strg+D', TAtlasShortcutTips.StepsText(Steps));
  Steps := TAtlasShortcutTips.Steps('Ctrl+K, D');
  Assert.AreEqual(2, Integer(Length(Steps)));
  Assert.AreEqual(1, Integer(Length(Steps[1])));
  Assert.AreEqual('D', Steps[1][0]);
  // Plus und Komma als Taste.
  Steps := TAtlasShortcutTips.Steps('Strg++');
  Assert.AreEqual(1, Integer(Length(Steps)));
  Assert.AreEqual(2, Integer(Length(Steps[0])));
  Assert.AreEqual('+', Steps[0][1]);
  Steps := TAtlasShortcutTips.Steps('Strg+,');
  Assert.AreEqual(1, Integer(Length(Steps)));
  Assert.AreEqual(',', Steps[0][1]);
  Assert.AreEqual(0, Integer(Length(TAtlasShortcutTips.Steps(''))));
  View := TAtlasShortcutTipView.Create('Strg+K, Strg+D', 'Zeile löschen', True);
  Assert.AreEqual(2, Integer(Length(View.Steps)));
  Assert.AreEqual('Strg+K, Strg+D', View.KeyText);
  Assert.AreEqual('Zeile löschen', View.Command);
  Assert.IsTrue(View.ShowAllKeys);
  // Kürzel aus der Menübeschriftung (Text hinter dem Tabulator).
  Assert.AreEqual('Strg+K, Strg+1', TAtlasShortcutTips.KeyTextOfCaption('Lesezeichen &1'#9'Strg+K, Strg+1'));
  Assert.AreEqual('', TAtlasShortcutTips.KeyTextOfCaption('Speichern'));
end;

procedure TAtlasShortcutTipsTests.ParsesStepsForKeyboardCounting;
var
  Keys: TArray<Word>;
begin
  Keys := TAtlasShortcutTips.ParseSteps('Strg+Umschalt+C');
  Assert.AreEqual(1, Integer(Length(Keys)));
  Assert.AreEqual(Integer(TAtlasKeyConflicts.scCtrl or TAtlasKeyConflicts.scShift or Ord('C')), Integer(Keys[0]));
  Keys := TAtlasShortcutTips.ParseSteps('Ctrl+K, Ctrl+D');
  Assert.AreEqual(2, Integer(Length(Keys)));
  Assert.AreEqual(Integer(TAtlasKeyConflicts.scCtrl or Ord('K')), Integer(Keys[0]));
  Assert.AreEqual(Integer(TAtlasKeyConflicts.scCtrl or Ord('D')), Integer(Keys[1]));
  Keys := TAtlasShortcutTips.ParseSteps('Strg+K, D');
  Assert.AreEqual(2, Integer(Length(Keys)));
  Assert.AreEqual(Integer(Ord('D')), Integer(Keys[1]));
  Assert.AreEqual(0, Integer(Length(TAtlasShortcutTips.ParseSteps('Strg+Unsinn'))));
  Assert.AreEqual(IntToStr(TAtlasKeyConflicts.scCtrl or Ord('K')) + ',' +
    IntToStr(TAtlasKeyConflicts.scCtrl or Ord('D')), TAtlasShortcutTips.StepsKey(TAtlasShortcutTips.ParseSteps(
    'Strg+K, Strg+D')));
end;

procedure TAtlasShortcutTipsTests.AtlasCommandFollowsCurrentKey;
var
  Settings: TAtlasPluginSettings;
  Func: TAtlasKeyFunction;
  Entry: TAtlasKeyEntry;
  Key: Word;
begin
  // Jede Atlas-Taste hat einen Befehl, den die Zählung und die Tipps kennen. Mehrere Tasten können denselben
  // Befehl haben (#775 zwei Tasten, #777 eigene Taste und Strg+F12); der Befehl führt dann zur ersten.
  for Func := Low(TAtlasKeyFunction) to High(TAtlasKeyFunction) do
  begin
    Assert.IsTrue(TAtlasShortcutTips.AtlasCommandId(Func).StartsWith('Atlas.'));
    Assert.IsTrue(TAtlasShortcutTips.AtlasFunctionOf(TAtlasShortcutTips.AtlasCommandId(Func), Entry.Func));
    Assert.AreEqual(TAtlasShortcutTips.AtlasCommandId(Func), TAtlasShortcutTips.AtlasCommandId(Entry.Func));
    Assert.IsTrue(Ord(Entry.Func) <= Ord(Func));
  end;
  Assert.IsTrue(TAtlasShortcutTips.AtlasFunctionOf('Atlas.ToggleMethod', Func));
  Assert.IsTrue(Func = TAtlasKeyFunction.MethodToggleUp);
  Assert.IsTrue(TAtlasShortcutTips.AtlasFunctionOf('Atlas.UnitSearch', Func));
  Assert.IsTrue(Func = TAtlasKeyFunction.UnitSearch);
  Assert.IsTrue(TAtlasShortcutTips.AtlasFunctionOf('Atlas.SwitchTestUnit', Func));
  Assert.IsTrue(Func = TAtlasKeyFunction.TestUnit);
  Assert.AreEqual('Atlas.ExpandSelection', TAtlasShortcutTips.AtlasCommandId(TAtlasKeyFunction.ExpandSelection));
  Assert.AreEqual('Atlas.CommandPalette', TAtlasShortcutTips.AtlasCommandId(TAtlasKeyFunction.Palette));
  Assert.IsFalse(TAtlasShortcutTips.AtlasFunctionOf('ecClassCompletion', Func));
  // Neu belegt: Die Taste kommt aus den aktuellen Einstellungen, nicht aus einem Zwischenstand.
  Settings := TAtlasPluginSettings.Defaults;
  Settings.ExpandKey := TAtlasKeyConflicts.scCtrl or TAtlasKeyConflicts.scAlt or Ord('E');
  Assert.IsTrue(TAtlasShortcutTips.AtlasFunctionOf('atlas.expandselection', Func), 'ohne Groß/klein');
  Key := 0;
  for Entry in TAtlasKeyEntry.AllFromSettings(Settings) do
    if Entry.Func = Func then
      Key := Entry.Key;
  Assert.AreEqual(Integer(TAtlasKeyConflicts.scCtrl or TAtlasKeyConflicts.scAlt or Ord('E')), Integer(Key));
end;

procedure TAtlasShortcutTipsTests.KeyOnlyFunctionsHaveNoPaletteCommand;
var
  Func: TAtlasKeyFunction;
begin
  // Karte „Atlas entdecken“ (#757): Tipps zu Tasten ohne Befehl der Palette zeigen die Taste selbst.
  Assert.IsTrue(TAtlasShortcutTips.IsKeyOnly(TAtlasShortcutTips.PaletteCommandId, Func));
  Assert.IsTrue(Func = TAtlasKeyFunction.Palette);
  Assert.IsTrue(TAtlasShortcutTips.IsKeyOnly('atlas.completion', Func), 'ohne Groß/klein');
  Assert.IsTrue(Func = TAtlasKeyFunction.Completion);
  Assert.IsTrue(TAtlasShortcutTips.IsKeyOnly('Atlas.Signature', Func));
  Assert.IsTrue(TAtlasShortcutTips.IsKeyOnly('Atlas.WelcomeSearch', Func));
  Assert.IsFalse(TAtlasShortcutTips.IsKeyOnly('Atlas.ExpandSelection', Func), 'Befehl der Palette');
  Assert.IsFalse(TAtlasShortcutTips.IsKeyOnly('Atlas.QuickToggles', Func), 'Befehl der Palette');
  Assert.IsFalse(TAtlasShortcutTips.IsKeyOnly('Atlas.Rename', Func), 'keine Atlas-Taste');
  Assert.IsFalse(TAtlasShortcutTips.IsKeyOnly('', Func));
end;

procedure TAtlasShortcutTipsTests.PlacesTipBottomRight;
var
  Placed: TRect;
begin
  Placed := TAtlasShortcutTips.PlaceBottomRight(Rect(100, 200, 900, 800), 300, 60, 12);
  Assert.AreEqual(588, Placed.Left);
  Assert.AreEqual(728, Placed.Top);
  Assert.AreEqual(888, Placed.Right);
  Assert.AreEqual(788, Placed.Bottom);
  // Zu klein: bleibt in der Fläche, links bzw. oben bündig.
  Placed := TAtlasShortcutTips.PlaceBottomRight(Rect(100, 200, 300, 230), 300, 60, 12);
  Assert.AreEqual(100, Placed.Left);
  Assert.AreEqual(200, Placed.Top);
  Assert.AreEqual(400, Placed.Right);
end;

procedure TAtlasShortcutTipsTests.RecognizesShortCutStrokes;
begin
  Assert.IsTrue(TAtlasShortcutTips.IsShortCutStroke(TAtlasKeyConflicts.scCtrl or Ord('S')));
  Assert.IsTrue(TAtlasShortcutTips.IsShortCutStroke(TAtlasKeyConflicts.scAlt or $0D));
  Assert.IsTrue(TAtlasShortcutTips.IsShortCutStroke($78), 'F9');
  Assert.IsTrue(TAtlasShortcutTips.IsShortCutStroke(TAtlasKeyConflicts.scShift or $7B), 'Umschalt+F12');
  Assert.IsFalse(TAtlasShortcutTips.IsShortCutStroke(Ord('A')), 'Tippen');
  Assert.IsFalse(TAtlasShortcutTips.IsShortCutStroke(TAtlasKeyConflicts.scShift or Ord('A')), 'Großbuchstabe');
  Assert.IsFalse(TAtlasShortcutTips.IsShortCutStroke(TAtlasKeyConflicts.scCtrl), 'nur Umschalttaste');
end;

{ TAtlasCommandUsageTests }

procedure TAtlasCommandUsageTests.CountsAndRoundTrips;
var
  Usage, Loaded: TAtlasCommandUsage;
  Entry: TAtlasCommandUsageEntry;
begin
  Usage := TAtlasCommandUsage.Create;
  Loaded := TAtlasCommandUsage.Create;
  try
    Assert.IsFalse(Usage.Changed);
    Usage.Count(ClassCompletion, TAtlasCommandInput.Mouse, Moment(9, 0, 0));
    Usage.Count('ECCLASSCOMPLETION', TAtlasCommandInput.Mouse, Moment(9, 30, 0));
    Usage.Count(ClassCompletion, TAtlasCommandInput.Keyboard, Moment(10, 0, 0));
    Usage.Count('Atlas.CodeActions', TAtlasCommandInput.Mouse, Moment(10, 1, 0));
    Usage.Count('', TAtlasCommandInput.Mouse, Moment(10, 1, 0));
    Assert.IsTrue(Usage.Changed);
    Entry := Usage.Entry(ClassCompletion);
    TAtlasShortcutTips.MarkShown(Entry, Moment(9, 0, 1));
    Usage.Put(Entry);
    Assert.AreEqual(2, Integer(Length(Usage.Entries)), 'Groß/klein egal, leere Id nicht');
    // Zustand der Tipps aus shortcut-tips.json, Zähler aus usage.json (#757).
    Assert.IsTrue(Loaded.Parse(Usage.ToJson));
    Assert.IsTrue(Loaded.ParseCounts(Usage.CountsToJson));
    Assert.IsTrue(Loaded.Find('ecclasscompletion', Entry));
    Assert.AreEqual(ClassCompletion, Entry.Id);
    Assert.AreEqual(2, Entry.Mouse);
    Assert.AreEqual(1, Entry.Keyboard);
    Assert.AreEqual(3, Loaded.UseCount(ClassCompletion));
    Assert.AreEqual(1, Loaded.UseCount('Atlas.CodeActions'));
    Assert.AreEqual(0, Loaded.UseCount('Unbekannt'));
    Assert.AreEqual(TAtlasCommandUsage.TimeText(Moment(10, 0, 0)), TAtlasCommandUsage.TimeText(Entry.LastUsed));
    Assert.AreEqual(TAtlasCommandUsage.TimeText(Moment(9, 0, 1)), TAtlasCommandUsage.TimeText(Entry.LastTip));
    Assert.IsFalse(Entry.Never);
    Assert.IsFalse(Loaded.Find('Unbekannt', Entry));
    Assert.AreEqual('Unbekannt', Entry.Id);
    Assert.AreEqual(0, Entry.Total);
    Assert.AreEqual('2026-10-15T09:30:00', TAtlasCommandUsage.TimeText(Moment(9, 30, 0)));
    Assert.AreEqual('', TAtlasCommandUsage.TimeText(0));
    Assert.AreEqual(TAtlasCommandUsage.TimeText(Moment(9, 30, 0)),
      TAtlasCommandUsage.TimeText(TAtlasCommandUsage.TimeOf('2026-10-15T09:30:00.123Z')));
    Assert.IsTrue(TAtlasCommandUsage.TimeOf('gestern') = 0);
  finally
    Loaded.Free;
    Usage.Free;
  end;
end;

procedure TAtlasCommandUsageTests.KeepsUnknownTopLevelFields;
var
  Usage: TAtlasCommandUsage;
  Json: string;
begin
  Usage := TAtlasCommandUsage.Create;
  try
    Assert.IsTrue(Usage.Parse('{"format":1,"commands":{"X":{"mouse":1,"keyboard":"2","extra":true}},' +
      '"discover":{"seen":["Atlas.CodeActions"]}}'));
    Assert.AreEqual(2, Usage.Entry('X').Keyboard, 'Zahl auch als Text');
    Json := Usage.ToJson;
    Assert.Contains(Json, '"discover"');
    Assert.Contains(Json, 'Atlas.CodeActions');
    Assert.Contains(Json, '"format":1');
  finally
    Usage.Free;
  end;
end;

procedure TAtlasCommandUsageTests.HigherFormatIsNotOverwritten;
var
  Usage: TAtlasCommandUsage;
  FileName: string;
begin
  Usage := TAtlasCommandUsage.Create;
  try
    Assert.IsFalse(Usage.Parse('{"format":2,"commands":{"X":{"mouse":1}}}'));
    Assert.IsFalse(Usage.Writable);
    Assert.AreEqual(0, Usage.UseCount('X'));
    FileName := TPath.Combine(TPath.GetTempPath, 'atlas-usage-' + FormatDateTime('hhnnsszzz', Now) + '.json');
    TFile.WriteAllText(FileName, '{"format":2}');
    try
      Usage.Clear;
      Assert.IsTrue(Usage.Writable);
      Usage.Count('X', TAtlasCommandInput.Mouse, Moment(10, 0, 0));
      Assert.IsFalse(Usage.SaveToFile(FileName), 'neuere Fassung bleibt');
      Assert.IsFalse(Usage.Writable);
      Assert.Contains(TFile.ReadAllText(FileName), '"format":2');
    finally
      System.SysUtils.DeleteFile(FileName);
    end;
  finally
    Usage.Free;
  end;
end;

procedure TAtlasCommandUsageTests.BrokenJsonStartsEmpty;
var
  Usage: TAtlasCommandUsage;
begin
  Usage := TAtlasCommandUsage.Create;
  try
    Usage.Count('X', TAtlasCommandInput.Mouse, Moment(10, 0, 0));
    Assert.IsFalse(Usage.Parse('kein JSON'));
    Assert.AreEqual(0, Integer(Length(Usage.Entries)));
    Assert.IsTrue(Usage.Writable);
    Assert.IsFalse(Usage.Parse('[1,2]'));
    Assert.IsTrue(Usage.Parse('{"commands":{"":{"mouse":1},"Y":5}}'));
    Assert.AreEqual(0, Integer(Length(Usage.Entries)), 'leere Namen und Nicht-Objekte übergangen');
    Assert.IsFalse(Usage.LoadFromFile(TPath.Combine(TPath.GetTempPath, 'atlas-gibt-es-nicht.json')));
  finally
    Usage.Free;
  end;
end;

procedure TAtlasCommandUsageTests.SavesAndLoadsFile;
var
  Usage, Loaded: TAtlasCommandUsage;
  Folder, FileName: string;
  Entry: TAtlasCommandUsageEntry;
begin
  Folder := TPath.Combine(TPath.GetTempPath, 'atlas-usage-' + FormatDateTime('hhnnsszzz', Now));
  FileName := TAtlasCommandUsage.DefaultFile(Folder);
  Usage := TAtlasCommandUsage.Create;
  Loaded := TAtlasCommandUsage.Create;
  try
    Usage.Count(ClassCompletion, TAtlasCommandInput.Mouse, Moment(10, 0, 0));
    Entry := Usage.Entry(ClassCompletion);
    Entry.Never := True;
    Usage.Put(Entry);
    Usage.SaveToFiles(FileName, TAtlasCommandUsage.DefaultUsageFile(Folder));
    Assert.IsTrue(TFile.Exists(FileName), 'legt den Ordner an');
    Assert.IsTrue(TFile.Exists(TAtlasCommandUsage.DefaultUsageFile(Folder)));
    Assert.IsFalse(Usage.Changed);
    Loaded.LoadFromFiles(FileName, TAtlasCommandUsage.DefaultUsageFile(Folder));
    Assert.IsTrue(Loaded.Entry(ClassCompletion).Never);
    Assert.AreEqual(1, Loaded.Entry(ClassCompletion).Mouse);
    Assert.IsFalse(Loaded.Changed);
    Assert.IsFalse(TFile.Exists(FileName + '.tmp'));
    Assert.IsFalse(TFile.Exists(TAtlasCommandUsage.DefaultUsageFile(Folder) + '.tmp'));
  finally
    Loaded.Free;
    Usage.Free;
    if TDirectory.Exists(Folder) then
      TDirectory.Delete(Folder, True);
  end;
end;

procedure TAtlasCommandUsageTests.RarelyByKeyboard;
var
  Entry: TAtlasCommandUsageEntry;
begin
  Entry := TAtlasCommandUsageEntry.Create('X');
  Entry.Mouse := 2;
  Assert.IsFalse(Entry.RarelyByKeyboard, 'zu wenige Aufrufe');
  Entry.Mouse := 3;
  Assert.IsTrue(Entry.RarelyByKeyboard);
  Entry.Keyboard := 1;
  Assert.IsFalse(Entry.RarelyByKeyboard, 'ein Viertel per Tastatur');
  Entry.Mouse := 8;
  Assert.IsTrue(Entry.RarelyByKeyboard);
  Entry.Mouse := 0;
  Entry.Keyboard := 5;
  Assert.IsFalse(Entry.RarelyByKeyboard);
end;

procedure TAtlasCommandUsageTests.FileIsNotTheCompletionUsage;
var
  FileName: string;
begin
  // %APPDATA%\Atlas\usage.json gehört der lernenden Vervollständigung (#418) und bleibt unberührt; die Zählung
  // der Befehle (#757) liegt in %LOCALAPPDATA%\Atlas\usage.json, der Zustand der Tipps in shortcut-tips.json.
  FileName := TAtlasCommandUsage.DefaultFile('LocalAppData');
  Assert.IsTrue(FileName.EndsWith('shortcut-tips.json'));
  Assert.IsTrue(FileName.StartsWith(IncludeTrailingPathDelimiter('LocalAppData') + 'Atlas'));
  FileName := TAtlasCommandUsage.DefaultUsageFile('LocalAppData');
  Assert.AreEqual(IncludeTrailingPathDelimiter(IncludeTrailingPathDelimiter('LocalAppData') + 'Atlas') + 'usage.json',
    FileName);
end;

/// <summary>Namen aller Felder in den Einträgen von "commands", sortiert und ohne Doppelte, mit Komma.</summary>
function FieldNames(const AJson: string): string;
var
  Root: TJSONValue;
  Commands: TJSONValue;
  Index, Inner: Integer;
  Item: TJSONObject;
  Names: TStringList;
begin
  Result := '';
  Root := TJSONObject.ParseJSONValue(AJson);
  Names := TStringList.Create;
  try
    Names.Sorted := True;
    Names.Duplicates := dupIgnore;
    if not (Root is TJSONObject) then
      Exit;
    Commands := TJSONObject(Root).GetValue('commands');
    if not (Commands is TJSONObject) then
      Exit;
    for Index := 0 to TJSONObject(Commands).Count - 1 do
      if TJSONObject(Commands).Pairs[Index].JsonValue is TJSONObject then
      begin
        Item := TJSONObject(TJSONObject(Commands).Pairs[Index].JsonValue);
        for Inner := 0 to Item.Count - 1 do
          Names.Add(Item.Pairs[Inner].JsonString.Value);
      end;
    Result := Names.CommaText;
  finally
    Names.Free;
    Root.Free;
  end;
end;

/// <summary>Namen der Felder oberster Ebene, sortiert, mit Komma.</summary>
function TopNames(const AJson: string): string;
var
  Root: TJSONValue;
  Index: Integer;
  Names: TStringList;
begin
  Result := '';
  Root := TJSONObject.ParseJSONValue(AJson);
  Names := TStringList.Create;
  try
    Names.Sorted := True;
    if Root is TJSONObject then
      for Index := 0 to TJSONObject(Root).Count - 1 do
        Names.Add(TJSONObject(Root).Pairs[Index].JsonString.Value);
    Result := Names.CommaText;
  finally
    Names.Free;
    Root.Free;
  end;
end;

procedure TAtlasCommandUsageTests.UsageJsonHoldsOnlyIdsCountersAndDate;
var
  Usage: TAtlasCommandUsage;
  Entry: TAtlasCommandUsageEntry;
begin
  // #757: usage.json enthält nur Befehlskennungen, Zähler und Datum.
  Usage := TAtlasCommandUsage.Create;
  try
    Usage.Count('Atlas.CodeActions', TAtlasCommandInput.Mouse, Moment(9, 0, 0));
    Usage.Count(ClassCompletion, TAtlasCommandInput.Keyboard, Moment(9, 5, 0));
    Entry := Usage.Entry(ClassCompletion);
    Entry.Never := True;
    TAtlasShortcutTips.MarkShown(Entry, Moment(9, 6, 0));
    Usage.Put(Entry);
    Usage.SetSection('discover', '{"blocked":["rename"],"last":"codeActions"}');
    Assert.AreEqual('commands,format', TopNames(Usage.CountsToJson));
    Assert.AreEqual('keyboard,lastUsed,mouse', FieldNames(Usage.CountsToJson));
    Assert.Contains(Usage.CountsToJson, '"Atlas.CodeActions"');
    Assert.Contains(Usage.CountsToJson, '"lastUsed":"2026-10-15T09:05:00"');
    Assert.DoesNotContain(Usage.CountsToJson, 'rename');
    // Zustand der Tipps ohne Zähler in shortcut-tips.json.
    Assert.AreEqual('lastTip,never', FieldNames(Usage.ToJson));
    Assert.AreEqual('commands,discover,format', TopNames(Usage.ToJson));
    Assert.DoesNotContain(Usage.ToJson, 'Atlas.CodeActions', False, 'ohne Tipp-Zustand kein Eintrag');
  finally
    Usage.Free;
  end;
end;

procedure TAtlasCommandUsageTests.TrackingOffCountsNothing;
var
  Usage: TAtlasCommandUsage;
  Entry: TAtlasCommandUsageEntry;
begin
  Usage := TAtlasCommandUsage.Create;
  try
    Assert.IsTrue(Usage.Tracking, 'Vorgabe: zählen');
    Usage.Tracking := False;
    Usage.Count('Atlas.CodeActions', TAtlasCommandInput.Mouse, Moment(9, 0, 0));
    Usage.Count('Atlas.CodeActions', TAtlasCommandInput.Keyboard, Moment(9, 0, 0));
    Assert.AreEqual(0, Usage.UseCount('Atlas.CodeActions'));
    Assert.IsFalse(Usage.CountsChanged, 'nichts zu schreiben');
    // Tipps dürfen weiter ihren Zustand merken.
    Entry := Usage.Entry('Atlas.CodeActions');
    Entry.Never := True;
    Usage.Put(Entry);
    Assert.IsTrue(Usage.TipsChanged);
    Assert.IsFalse(Usage.CountsChanged);
    Usage.Clear;
    Assert.IsFalse(Usage.Tracking, 'Clear lässt die Einstellung');
    Usage.Tracking := True;
    Usage.Count('Atlas.CodeActions', TAtlasCommandInput.Mouse, Moment(9, 0, 0));
    Assert.AreEqual(1, Usage.UseCount('Atlas.CodeActions'));
  finally
    Usage.Free;
  end;
end;

procedure TAtlasCommandUsageTests.ResetCountsKeepsTipState;
var
  Usage: TAtlasCommandUsage;
  Entry: TAtlasCommandUsageEntry;
begin
  Usage := TAtlasCommandUsage.Create;
  try
    Usage.Count('Atlas.CodeActions', TAtlasCommandInput.Mouse, Moment(9, 0, 0));
    Usage.Count(ClassCompletion, TAtlasCommandInput.Mouse, Moment(9, 0, 0));
    Entry := Usage.Entry(ClassCompletion);
    Entry.Never := True;
    Usage.Put(Entry);
    Usage.Changed := False;
    Usage.ResetCounts;
    Assert.IsTrue(Usage.CountsChanged);
    Assert.AreEqual(0, Usage.UseCount('Atlas.CodeActions'));
    Assert.AreEqual(0, Usage.UseCount(ClassCompletion));
    Assert.IsTrue(Usage.Entry(ClassCompletion).Never, '„Nicht mehr zeigen“ bleibt');
    Assert.IsTrue(Usage.Entry('Atlas.CodeActions').LastUsed = 0);
    Assert.AreEqual('', FieldNames(Usage.CountsToJson), 'usage.json leer');
    Usage.Changed := False;
    Usage.ResetCounts;
    Assert.IsFalse(Usage.Changed, 'nichts mehr zurückzusetzen');
  finally
    Usage.Free;
  end;
end;

procedure TAtlasCommandUsageTests.OlderTipsFileMovesCountsToUsageJson;
var
  Usage, Loaded: TAtlasCommandUsage;
  Folder, TipsFile, UsageFile: string;
begin
  // Ältere Fassung von #600: Zähler in shortcut-tips.json, usage.json fehlt.
  Folder := TPath.Combine(TPath.GetTempPath, 'atlas-usage-' + FormatDateTime('hhnnsszzz', Now) + '-m');
  TipsFile := TAtlasCommandUsage.DefaultFile(Folder);
  UsageFile := TAtlasCommandUsage.DefaultUsageFile(Folder);
  ForceDirectories(ExtractFileDir(TipsFile));
  TFile.WriteAllText(TipsFile, '{"format":1,"commands":{"Atlas.Rename":{"mouse":2,"keyboard":1,' +
    '"lastUsed":"2026-10-01T08:00:00","never":true}}}');
  Usage := TAtlasCommandUsage.Create;
  Loaded := TAtlasCommandUsage.Create;
  try
    Usage.LoadFromFiles(TipsFile, UsageFile);
    Assert.AreEqual(3, Usage.UseCount('Atlas.Rename'));
    Assert.IsTrue(Usage.Entry('Atlas.Rename').Never);
    Assert.IsTrue(Usage.CountsChanged, 'beim nächsten Speichern umziehen');
    Usage.SaveToFiles(TipsFile, UsageFile);
    Assert.IsTrue(TFile.Exists(UsageFile));
    Assert.DoesNotContain(TFile.ReadAllText(TipsFile), 'mouse');
    Assert.Contains(TFile.ReadAllText(UsageFile), '"mouse":2');
    Loaded.LoadFromFiles(TipsFile, UsageFile);
    Assert.AreEqual(3, Loaded.UseCount('Atlas.Rename'));
    Assert.IsTrue(Loaded.Entry('Atlas.Rename').Never);
    Assert.IsFalse(Loaded.Changed);
  finally
    Loaded.Free;
    Usage.Free;
    if TDirectory.Exists(Folder) then
      TDirectory.Delete(Folder, True);
  end;
end;

procedure TAtlasCommandUsageTests.UsageJsonWinsOverOlderCounts;
var
  Usage: TAtlasCommandUsage;
begin
  Usage := TAtlasCommandUsage.Create;
  try
    Assert.IsTrue(Usage.Parse('{"format":1,"commands":{"A":{"mouse":5,"never":true},"B":{"keyboard":4}}}'));
    Assert.IsTrue(Usage.ParseCounts('{"format":1,"commands":{"A":{"mouse":1,"lastUsed":"2026-10-01T08:00:00"},' +
      '"C":{"keyboard":"2"},"":{"mouse":1},"D":7}}'));
    Assert.AreEqual(1, Usage.UseCount('A'));
    Assert.IsTrue(Usage.Entry('A').Never);
    Assert.AreEqual(0, Usage.UseCount('B'), 'alte Zähler fallen weg');
    Assert.AreEqual(2, Usage.UseCount('C'));
    Assert.AreEqual(0, Usage.UseCount('D'));
    Assert.IsFalse(Usage.ParseCounts('kein JSON'));
    Assert.IsTrue(Usage.CountsWritable);
  finally
    Usage.Free;
  end;
end;

procedure TAtlasCommandUsageTests.SectionsRoundTrip;
var
  Usage, Loaded: TAtlasCommandUsage;
begin
  Usage := TAtlasCommandUsage.Create;
  Loaded := TAtlasCommandUsage.Create;
  try
    Assert.AreEqual('', Usage.Section('discover'));
    Usage.SetSection('discover', '{"blocked":["rename"],"last":"codeActions"}');
    Assert.IsTrue(Usage.TipsChanged);
    Assert.IsFalse(Usage.CountsChanged);
    Assert.Contains(Usage.Section('discover'), '"rename"');
    Usage.SetSection('other', '[1,2]');
    Assert.IsTrue(Loaded.Parse(Usage.ToJson));
    Assert.Contains(Loaded.Section('discover'), '"last":"codeActions"');
    Assert.AreEqual('[1,2]', Loaded.Section('other'));
    // Vergebene Namen und kaputter Text ändern nichts.
    Loaded.SetSection('commands', '{}');
    Loaded.SetSection('format', '2');
    Loaded.SetSection('discover', '{kaputt');
    Assert.Contains(Loaded.ToJson, '"format":1');
    Assert.Contains(Loaded.Section('discover'), 'codeActions');
    Loaded.SetSection('discover', '');
    Assert.AreEqual('', Loaded.Section('discover'));
    Assert.DoesNotContain(Loaded.ToJson, 'discover');
    Assert.AreEqual('[1,2]', Loaded.Section('other'));
  finally
    Loaded.Free;
    Usage.Free;
  end;
end;

procedure TAtlasCommandUsageTests.HigherFormatUsageJsonIsNotOverwritten;
var
  Usage: TAtlasCommandUsage;
  FileName: string;
begin
  Usage := TAtlasCommandUsage.Create;
  try
    Assert.IsFalse(Usage.ParseCounts('{"format":2,"commands":{"X":{"mouse":1}}}'));
    Assert.IsFalse(Usage.CountsWritable);
    Assert.AreEqual(0, Usage.UseCount('X'));
    FileName := TPath.Combine(TPath.GetTempPath, 'atlas-usage-' + FormatDateTime('hhnnsszzz', Now) + '-f.json');
    TFile.WriteAllText(FileName, '{"format":2}');
    try
      Usage.Clear;
      Assert.IsTrue(Usage.CountsWritable);
      Usage.Count('X', TAtlasCommandInput.Mouse, Moment(10, 0, 0));
      Assert.IsFalse(Usage.SaveCountsToFile(FileName), 'neuere Fassung bleibt');
      Assert.IsFalse(Usage.CountsWritable);
      Assert.Contains(TFile.ReadAllText(FileName), '"format":2');
    finally
      System.SysUtils.DeleteFile(FileName);
    end;
  finally
    Usage.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasShortcutTipsTests);
  TDUnitX.RegisterTestFixture(TAtlasCommandUsageTests);

end.
