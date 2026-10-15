unit Atlas.Core.Commands.ShortcutTips.Tests;

// Tests für die Tastenkürzel-Tipps (#600): Regeln (je Tag, drei Aufrufe über
// das Kürzel, Abstand 30 s, „Nicht mehr zeigen“, ohne Kürzel, per Tastatur,
// Bereich, Debug-Sitzung, modaler Dialog), Kürzel mit zwei Schritten, Lage
// unten rechts und die Zählung je Befehl in shortcut-tips.json (auch für #757).

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
  end;

implementation

uses
  System.SysUtils,
  System.Types,
  System.IOUtils,
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
  // Jede Atlas-Taste hat einen eigenen Befehl, den die Zählung und die Tipps kennen.
  for Func := Low(TAtlasKeyFunction) to High(TAtlasKeyFunction) do
  begin
    Assert.IsTrue(TAtlasShortcutTips.AtlasCommandId(Func).StartsWith('Atlas.'));
    Assert.IsTrue(TAtlasShortcutTips.AtlasFunctionOf(TAtlasShortcutTips.AtlasCommandId(Func), Entry.Func));
    Assert.IsTrue(Entry.Func = Func);
  end;
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
    Assert.IsTrue(Loaded.Parse(Usage.ToJson));
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
    Assert.IsTrue(Usage.SaveToFile(FileName), 'legt den Ordner an');
    Assert.IsFalse(Usage.Changed);
    Assert.IsTrue(Loaded.LoadFromFile(FileName));
    Assert.IsTrue(Loaded.Entry(ClassCompletion).Never);
    Assert.AreEqual(1, Loaded.Entry(ClassCompletion).Mouse);
    Assert.IsFalse(TFile.Exists(FileName + '.tmp'));
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
  // %APPDATA%\Atlas\usage.json gehört der lernenden Vervollständigung (#418) und bleibt unberührt.
  FileName := TAtlasCommandUsage.DefaultFile('LocalAppData');
  Assert.IsTrue(FileName.EndsWith('shortcut-tips.json'));
  Assert.IsTrue(FileName.StartsWith(IncludeTrailingPathDelimiter('LocalAppData') + 'Atlas'));
  Assert.IsFalse(FileName.EndsWith('usage.json'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasShortcutTipsTests);
  TDUnitX.RegisterTestFixture(TAtlasCommandUsageTests);

end.
