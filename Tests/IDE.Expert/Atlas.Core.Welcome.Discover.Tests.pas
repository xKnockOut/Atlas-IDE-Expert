unit Atlas.Core.Welcome.Discover.Tests;

// Tests für „Atlas entdecken“ (#757): Tippquelle tips.json, Tippauswahl
// (nie benutzt vor benutzt, lange nicht benutzt zuerst, gesperrte und
// abgeschaltete nie, ohne Zählung der Reihe nach), „Zuletzt vor …“, die
// Reihenfolge je Start und der Zustand der Karte in shortcut-tips.json.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
  TAtlasTipCatalogTests = class
  public
    [Test]
    procedure ParsesTipsWithDefaults;
    [Test]
    procedure SkipsInvalidAndDuplicateTips;
    [Test]
    procedure FindsTipByCommand;
    [Test]
    procedure FileStaysInInstallFolder;
    [Test]
    procedure HighDpiImageWhenScaledAndPresent;
  end;

  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
  TAtlasDiscoverTests = class
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure NeverUsedComesBeforeUsed;
    [Test]
    procedure UsedCommandIsNoLongerNeverUsedAfterRestart;
    [Test]
    procedure LongestUnusedComesFirst;
    [Test]
    procedure BlockedAndDisabledTipsNeverAppear;
    [Test]
    procedure EnabledFollowsSettingAndCommand;
    [Test]
    procedure SettingOnReadsSwitchesAndChoices;
    [Test]
    procedure NewStartBeginsAfterLastShownTip;
    [Test]
    procedure WithoutTrackingTipsComeInOrder;
    [Test]
    procedure WithoutTrackingNothingIsCounted;
    [Test]
    procedure AgeTextsFollowCalendarDays;
    [Test]
    procedure QueueStaysStableWithinSession;
    [Test]
    procedure StateRoundTripsThroughTipsFile;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Commands.Usage,
  Atlas.Core.Commands.Tips,
  Atlas.Core.Welcome.Discover;

const
  cCatalog =
    '{"format":1,"tips":[' +
    '{"id":"codeActions","command":"Atlas.CodeActions","title":"Code-Aktionen","titleEn":"Code actions",' +
      '"text":"Strg+. zeigt, was Atlas hier kann.","textEn":"Ctrl+. shows what Atlas can do here.",' +
      '"image":"Tipps\\code-aktionen.png","sample":"Beispiele\\Entdecken.pas","line":12,"column":5},' +
    '{"id":"expand","command":"Atlas.ExpandSelection","usage":["Atlas.ExpandSelection","Atlas.ShrinkSelection"],' +
      '"title":"Auswahl erweitern","text":"Schritt für Schritt."},' +
    '{"id":"undo","command":"Atlas.UndoChange","setting":"UndoMultiFile","try":"Atlas.ChangeList",' +
      '"title":"Zurücknehmen über Dateien"},' +
    '{"command":"Atlas.SymbolSearch","title":"Symbolsuche"}' +
    ']}';

function Moment(ADay: Word; AHour: Word): TDateTime;
begin
  Result := EncodeDate(2026, 10, ADay) + EncodeTime(AHour, 0, 0, 0);
end;

function Joined(const AIds: TArray<string>): string;
begin
  Result := string.Join(',', AIds);
end;

function Tips: TAtlasTips;
begin
  Result := TAtlasTipCatalog.Parse(cCatalog);
end;

function NoState: TAtlasDiscoverState;
begin
  Result := Default(TAtlasDiscoverState);
end;

{ TAtlasTipCatalogTests }

procedure TAtlasTipCatalogTests.ParsesTipsWithDefaults;
var
  mList: TAtlasTips;
begin
  mList := Tips;
  Assert.AreEqual(4, Integer(Length(mList)));
  Assert.AreEqual('codeActions', mList[0].Id);
  Assert.AreEqual('Atlas.CodeActions', mList[0].Command);
  Assert.AreEqual('Code-Aktionen', mList[0].TitleIn(False));
  Assert.AreEqual('Code actions', mList[0].TitleIn(True));
  Assert.AreEqual('Ctrl+. shows what Atlas can do here.', mList[0].TextIn(True));
  Assert.AreEqual('Tipps\code-aktionen.png', mList[0].Image);
  Assert.AreEqual('Beispiele\Entdecken.pas', mList[0].Sample);
  Assert.AreEqual(12, mList[0].Line);
  Assert.AreEqual(5, mList[0].Column);
  Assert.AreEqual('Atlas.CodeActions', Joined(mList[0].UsageIds), 'ohne usage zählt der Befehl');
  Assert.AreEqual('Atlas.ExpandSelection,Atlas.ShrinkSelection', Joined(mList[1].UsageIds));
  Assert.AreEqual('Auswahl erweitern', mList[1].TitleIn(True), 'ohne Englisch der deutsche Titel');
  Assert.AreEqual('UndoMultiFile', mList[2].Setting);
  Assert.AreEqual('Atlas.ChangeList', mList[2].TryId, '„Ausprobieren“ mit eigenem Befehl');
  Assert.AreEqual('Atlas.CodeActions', mList[0].TryId, 'ohne try der Befehl');
  Assert.AreEqual('Atlas.SymbolSearch', mList[3].Id, 'ohne id gilt der Befehl');
end;

procedure TAtlasTipCatalogTests.SkipsInvalidAndDuplicateTips;
var
  mList: TAtlasTips;
begin
  Assert.AreEqual(0, Integer(Length(TAtlasTipCatalog.Parse('kein JSON'))));
  Assert.AreEqual(0, Integer(Length(TAtlasTipCatalog.Parse('{"tips":{}}'))));
  Assert.AreEqual(0, Integer(Length(TAtlasTipCatalog.Parse(''))));
  mList := TAtlasTipCatalog.Parse('{"tips":[1,{"title":"ohne Befehl"},{"id":"a"},' +
    '{"id":"a","title":"Erster","usage":"Atlas.X","line":-3},{"id":"A","title":"Doppelt"},' +
    '{"id":"b","title":"Zweiter","futureField":true}]}');
  Assert.AreEqual(2, Integer(Length(mList)));
  Assert.AreEqual('Erster', mList[0].Title, 'die erste von doppelten Kennungen gilt');
  Assert.AreEqual('Atlas.X', Joined(mList[0].UsageIds), 'usage auch als Text');
  Assert.AreEqual(0, mList[0].Line, 'negative Zeile wird 0');
  Assert.AreEqual('b', mList[1].Id);
end;

procedure TAtlasTipCatalogTests.FindsTipByCommand;
var
  mTip: TAtlasTip;
begin
  Assert.IsTrue(TAtlasTipCatalog.FindByCommand(Tips, 'atlas.codeactions', mTip));
  Assert.AreEqual('codeActions', mTip.Id);
  Assert.IsFalse(TAtlasTipCatalog.FindByCommand(Tips, 'Atlas.Unbekannt', mTip));
  Assert.IsFalse(TAtlasTipCatalog.FindByCommand(Tips, '', mTip));
  Assert.AreEqual(1, TAtlasTipCatalog.IndexOf(Tips, 'EXPAND'));
  Assert.AreEqual(-1, TAtlasTipCatalog.IndexOf(Tips, 'nichts'));
end;

procedure TAtlasTipCatalogTests.FileStaysInInstallFolder;
var
  mFolder: string;
begin
  mFolder := TPath.Combine(TPath.GetTempPath, 'Atlas');
  Assert.AreEqual(IncludeTrailingPathDelimiter(mFolder) + 'Tipps' + PathDelim + 'a.png',
    TAtlasTipCatalog.FileIn(mFolder, 'Tipps\a.png'));
  Assert.AreEqual(IncludeTrailingPathDelimiter(mFolder) + 'Tipps' + PathDelim + 'a.png',
    TAtlasTipCatalog.FileIn(mFolder, 'Tipps/a.png'));
  Assert.AreEqual('', TAtlasTipCatalog.FileIn(mFolder, '..\Windows\a.png'));
  Assert.AreEqual('', TAtlasTipCatalog.FileIn(mFolder, 'C:\a.png'));
  Assert.AreEqual('', TAtlasTipCatalog.FileIn(mFolder, '\a.png'));
  Assert.AreEqual('', TAtlasTipCatalog.FileIn(mFolder, ''));
  Assert.AreEqual('', TAtlasTipCatalog.FileIn('', 'Tipps\a.png'));
end;

procedure TAtlasTipCatalogTests.HighDpiImageWhenScaledAndPresent;
var
  mFolder, mSmall, mLarge, mLone: string;
begin
  Assert.AreEqual('Tipps\a@2x.png', TAtlasTipCatalog.HighDpiName('Tipps\a.png'));
  Assert.AreEqual('', TAtlasTipCatalog.HighDpiName(''));
  mFolder := TPath.Combine(TPath.GetTempPath, 'AtlasTipImages' + IntToStr(Random(1000000)));
  ForceDirectories(mFolder);
  try
    mSmall := TPath.Combine(mFolder, 'a.png');
    mLarge := TPath.Combine(mFolder, 'a@2x.png');
    mLone := TPath.Combine(mFolder, 'b.png');
    TFile.WriteAllText(mSmall, 'x');
    TFile.WriteAllText(mLarge, 'x');
    TFile.WriteAllText(mLone, 'x');
    Assert.AreEqual(mSmall, TAtlasTipCatalog.ImageFor(mSmall, 320), '100 %: die einfache Datei Pixel für Pixel');
    Assert.AreEqual(mSmall, TAtlasTipCatalog.ImageFor(mSmall, 250), 'schmale Spalte: verkleinert');
    Assert.AreEqual(mLarge, TAtlasTipCatalog.ImageFor(mSmall, 400), '125 %: doppelte Auflösung, verkleinert');
    Assert.AreEqual(mLarge, TAtlasTipCatalog.ImageFor(mSmall, 640), '200 %: doppelte Auflösung Pixel für Pixel');
    Assert.AreEqual(mLone, TAtlasTipCatalog.ImageFor(mLone, 640), 'ohne @2x die einfache Datei');
    Assert.AreEqual('', TAtlasTipCatalog.ImageFor('', 640));
  finally
    TDirectory.Delete(mFolder, True);
  end;
end;

{ TAtlasDiscoverTests }

procedure TAtlasDiscoverTests.WarmUpFirstUse;
begin
  EnabledFollowsSettingAndCommand;
end;

procedure TAtlasDiscoverTests.NeverUsedComesBeforeUsed;
var
  mUsage: TAtlasCommandUsage;
  mOrder: TArray<string>;
begin
  // Akzeptanz: Ein Befehl, der nie benutzt wurde, wird vor einem bereits benutzten vorgeschlagen.
  mUsage := TAtlasCommandUsage.Create;
  try
    mUsage.Count('Atlas.CodeActions', TAtlasCommandInput.Mouse, Moment(10, 9));
    mUsage.Count('Atlas.ShrinkSelection', TAtlasCommandInput.Keyboard, Moment(11, 9));
    mOrder := TAtlasDiscover.Order(Tips, mUsage, NoState, nil, True);
    Assert.AreEqual('undo,Atlas.SymbolSearch,codeActions,expand', Joined(mOrder),
      'erst nie benutzte, dann am längsten nicht benutzte; Auswahl erweitern zählt über Verkleinern');
    Assert.IsTrue(TAtlasDiscover.NeverUsed(Tips[2], mUsage));
    Assert.IsFalse(TAtlasDiscover.NeverUsed(Tips[1], mUsage));
    Assert.IsTrue(TAtlasDiscover.NeverUsed(Tips[0], nil), 'ohne Zählung gilt alles als nie benutzt');
  finally
    mUsage.Free;
  end;
end;

procedure TAtlasDiscoverTests.UsedCommandIsNoLongerNeverUsedAfterRestart;
var
  mUsage, mLoaded: TAtlasCommandUsage;
  mFolder, mTipsFile, mUsageFile: string;
  mOrder: TArray<string>;
  mAge: TAtlasDiscoverAge;
begin
  // Akzeptanz: Nach Benutzen des vorgeschlagenen Befehls kommt er beim nächsten Start nicht mehr als
  // „noch nie benutzt“.
  mFolder := TPath.Combine(TPath.GetTempPath, 'atlas-discover-' + FormatDateTime('hhnnsszzz', Now));
  mTipsFile := TAtlasCommandUsage.DefaultFile(mFolder);
  mUsageFile := TAtlasCommandUsage.DefaultUsageFile(mFolder);
  mUsage := TAtlasCommandUsage.Create;
  mLoaded := TAtlasCommandUsage.Create;
  try
    mOrder := TAtlasDiscover.Order(Tips, mUsage, NoState, nil, True);
    Assert.AreEqual('codeActions', mOrder[0]);
    mAge := TAtlasDiscover.UsageAge(Tips[0], mUsage, True, Moment(15, 10));
    Assert.IsTrue(mAge.Kind = TAtlasDiscoverAgeKind.Never);
    // „Ausprobieren“ führt den Befehl über die Palette aus: Das zählt als Aufruf.
    mUsage.Count('Atlas.CodeActions', TAtlasCommandInput.Mouse, Moment(15, 10));
    mUsage.SaveToFiles(mTipsFile, mUsageFile);
    // Nächster Start.
    mLoaded.LoadFromFiles(mTipsFile, mUsageFile);
    mOrder := TAtlasDiscover.Order(Tips, mLoaded, NoState, nil, True);
    Assert.AreEqual('expand,undo,Atlas.SymbolSearch,codeActions', Joined(mOrder));
    mAge := TAtlasDiscover.UsageAge(Tips[0], mLoaded, True, Moment(16, 9));
    Assert.IsTrue(mAge.Kind = TAtlasDiscoverAgeKind.Yesterday, 'nicht mehr „noch nie benutzt“');
  finally
    mLoaded.Free;
    mUsage.Free;
    if TDirectory.Exists(mFolder) then
    begin
      TDirectory.Delete(mFolder, True);
    end;
  end;
end;

procedure TAtlasDiscoverTests.LongestUnusedComesFirst;
var
  mUsage: TAtlasCommandUsage;
begin
  mUsage := TAtlasCommandUsage.Create;
  try
    mUsage.Count('Atlas.CodeActions', TAtlasCommandInput.Mouse, Moment(14, 9));
    mUsage.Count('Atlas.ExpandSelection', TAtlasCommandInput.Mouse, Moment(1, 9));
    mUsage.Count('Atlas.UndoChange', TAtlasCommandInput.Mouse, Moment(7, 9));
    mUsage.Count('Atlas.SymbolSearch', TAtlasCommandInput.Mouse, Moment(7, 9));
    Assert.AreEqual('expand,undo,Atlas.SymbolSearch,codeActions',
      Joined(TAtlasDiscover.Order(Tips, mUsage, NoState, nil, True)), 'Gleichstand: wie in tips.json');
  finally
    mUsage.Free;
  end;
end;

procedure TAtlasDiscoverTests.BlockedAndDisabledTipsNeverAppear;
var
  mUsage: TAtlasCommandUsage;
  mState: TAtlasDiscoverState;
  mOrder: TArray<string>;
begin
  // Akzeptanz: „Nicht mehr zeigen“ sperrt den Tipp dauerhaft; abgeschaltete Funktionen erscheinen nie.
  mUsage := TAtlasCommandUsage.Create;
  try
    mState := NoState;
    mState.Block('CODEACTIONS');
    mState.Block('codeActions');
    mState.Block('');
    Assert.AreEqual(1, Integer(Length(mState.Blocked)));
    mOrder := TAtlasDiscover.Order(Tips, mUsage, mState,
      function(ATip: TAtlasTip): Boolean
      begin
        // Einstellung UndoMultiFile aus.
        Result := ATip.Setting <> 'UndoMultiFile';
      end, True);
    Assert.AreEqual('expand,Atlas.SymbolSearch', Joined(mOrder));
    mOrder := TAtlasDiscover.Order(Tips, mUsage, mState,
      function(ATip: TAtlasTip): Boolean
      begin
        Result := False;
      end, False);
    Assert.AreEqual(0, Integer(Length(mOrder)), 'auch ohne Zählung nie');
    // Dauerhaft: der Zustand übersteht das Speichern.
    mState := TAtlasDiscoverState.Parse(mState.ToJson);
    Assert.IsTrue(mState.IsBlocked('codeactions'));
  finally
    mUsage.Free;
  end;
end;

procedure TAtlasDiscoverTests.EnabledFollowsSettingAndCommand;
var
  mList: TAtlasTips;
  mSettingOn, mCommandExists: TFunc<string, Boolean>;
  mOrder: TArray<string>;
begin
  mList := Tips;
  // Nur UndoMultiFile ist eine bekannte Einstellung, und sie ist aus; die Palette kennt keine Symbolsuche.
  mSettingOn :=
    function(AName: string): Boolean
    begin
      Result := False;
    end;
  mCommandExists :=
    function(AId: string): Boolean
    begin
      Result := not SameText(AId, 'Atlas.SymbolSearch');
    end;
  Assert.IsTrue(TAtlasDiscover.IsEnabled(mList[0], mSettingOn, mCommandExists), 'ohne Einstellung: Befehl zählt');
  Assert.IsFalse(TAtlasDiscover.IsEnabled(mList[2], mSettingOn, mCommandExists), 'Einstellung aus');
  Assert.IsFalse(TAtlasDiscover.IsEnabled(mList[3], mSettingOn, mCommandExists), 'Befehl nicht in der Palette');
  Assert.IsTrue(TAtlasDiscover.IsEnabled(mList[2], nil, nil), 'ohne Prüfung alles');
  mOrder := TAtlasDiscover.Order(mList, nil, NoState,
    function(ATip: TAtlasTip): Boolean
    begin
      Result := TAtlasDiscover.IsEnabled(ATip, mSettingOn, mCommandExists);
    end, True);
  Assert.AreEqual('codeActions,expand', Joined(mOrder));
  mSettingOn :=
    function(AName: string): Boolean
    begin
      Result := SameText(AName, 'UndoMultiFile');
    end;
  Assert.IsTrue(TAtlasDiscover.IsEnabled(mList[2], mSettingOn, mCommandExists), 'Einstellung an');
  // Die Closures liegen im selben Rahmen wie die Variablen, die sie halten: Kreis lösen.
  mSettingOn := nil;
  mCommandExists := nil;
end;

procedure TAtlasDiscoverTests.SettingOnReadsSwitchesAndChoices;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.UndoMultiFile := True;
  mSettings.KeyOverview := False;
  Assert.IsTrue(TAtlasDiscover.SettingOn(mSettings, 'UndoMultiFile'));
  Assert.IsTrue(TAtlasDiscover.SettingOn(mSettings, 'undomultifile'), 'ohne Groß/klein');
  Assert.IsFalse(TAtlasDiscover.SettingOn(mSettings, 'KeyOverview'));
  // Auswahl: alles außer „off“ heißt an.
  mSettings.WelcomePageWhatsNew := 'afterUpdate';
  Assert.IsTrue(TAtlasDiscover.SettingOn(mSettings, 'WelcomePageWhatsNew'));
  mSettings.WelcomePageWhatsNew := 'off';
  Assert.IsFalse(TAtlasDiscover.SettingOn(mSettings, 'WelcomePageWhatsNew'));
  Assert.IsFalse(TAtlasDiscover.SettingOn(mSettings, 'GibtEsNicht'), 'unbekannt: aus');
  Assert.IsFalse(TAtlasDiscover.SettingOn(mSettings, ''));
end;

procedure TAtlasDiscoverTests.NewStartBeginsAfterLastShownTip;
var
  mUsage: TAtlasCommandUsage;
  mState: TAtlasDiscoverState;
begin
  // Je IDE-Start ein anderer Tipp: die nie benutzten beginnen nach dem zuletzt gezeigten.
  mUsage := TAtlasCommandUsage.Create;
  try
    mState := NoState;
    mState.Last := 'expand';
    Assert.AreEqual('undo,Atlas.SymbolSearch,codeActions,expand',
      Joined(TAtlasDiscover.Order(Tips, mUsage, mState, nil, True)));
    mState.Last := 'Atlas.SymbolSearch';
    Assert.AreEqual('codeActions,expand,undo,Atlas.SymbolSearch',
      Joined(TAtlasDiscover.Order(Tips, mUsage, mState, nil, True)));
    // Der zuletzt gezeigte ist inzwischen benutzt: Die nie benutzten beginnen trotzdem nach ihm.
    mUsage.Count('Atlas.ExpandSelection', TAtlasCommandInput.Mouse, Moment(15, 9));
    mState.Last := 'expand';
    Assert.AreEqual('undo,Atlas.SymbolSearch,codeActions,expand',
      Joined(TAtlasDiscover.Order(Tips, mUsage, mState, nil, True)));
    mState.Last := 'gibt-es-nicht';
    Assert.AreEqual('codeActions,undo,Atlas.SymbolSearch,expand',
      Joined(TAtlasDiscover.Order(Tips, mUsage, mState, nil, True)));
  finally
    mUsage.Free;
  end;
end;

procedure TAtlasDiscoverTests.WithoutTrackingTipsComeInOrder;
var
  mUsage: TAtlasCommandUsage;
  mState: TAtlasDiscoverState;
  mAge: TAtlasDiscoverAge;
begin
  // tips.usageTracking aus: der Reihe nach, ohne Bezug zur Nutzung.
  mUsage := TAtlasCommandUsage.Create;
  try
    mUsage.Count('Atlas.CodeActions', TAtlasCommandInput.Mouse, Moment(14, 9));
    mState := NoState;
    Assert.AreEqual('codeActions,expand,undo,Atlas.SymbolSearch',
      Joined(TAtlasDiscover.Order(Tips, mUsage, mState, nil, False)));
    mState.Last := 'codeActions';
    Assert.AreEqual('expand,undo,Atlas.SymbolSearch,codeActions',
      Joined(TAtlasDiscover.Order(Tips, mUsage, mState, nil, False)));
    mAge := TAtlasDiscover.UsageAge(Tips[0], mUsage, False, Moment(15, 9));
    Assert.IsTrue(mAge.Kind = TAtlasDiscoverAgeKind.None, 'kein Hinweis zur Nutzung');
    Assert.AreEqual('codeActions,expand,undo,Atlas.SymbolSearch',
      Joined(TAtlasDiscover.Order(Tips, nil, NoState, nil, True)), 'ohne Zählung (nil) ebenso');
  finally
    mUsage.Free;
  end;
end;

procedure TAtlasDiscoverTests.WithoutTrackingNothingIsCounted;
var
  mUsage: TAtlasCommandUsage;
begin
  // Akzeptanz: Mit tips.usageTracking aus wird nichts gezählt.
  mUsage := TAtlasCommandUsage.Create;
  try
    mUsage.Tracking := False;
    mUsage.Count('Atlas.CodeActions', TAtlasCommandInput.Mouse, Moment(14, 9));
    Assert.IsTrue(TAtlasDiscover.NeverUsed(Tips[0], mUsage));
    Assert.IsFalse(mUsage.CountsChanged);
    Assert.DoesNotContain(mUsage.CountsToJson, 'Atlas.CodeActions');
  finally
    mUsage.Free;
  end;
end;

procedure TAtlasDiscoverTests.AgeTextsFollowCalendarDays;

  procedure Check(ALastUsed, ANow: TDateTime; AKind: TAtlasDiscoverAgeKind; ACount: Integer; const AMessage: string);
  var
    mAge: TAtlasDiscoverAge;
  begin
    mAge := TAtlasDiscover.AgeOf(ALastUsed, ANow);
    Assert.IsTrue(mAge.Kind = AKind, AMessage);
    Assert.AreEqual(ACount, mAge.Count, AMessage);
  end;

var
  mNow_: TDateTime;
begin
  mNow_ := EncodeDate(2026, 10, 15) + EncodeTime(9, 0, 0, 0);
  Check(0, mNow_, TAtlasDiscoverAgeKind.Never, 0, 'nie');
  Check(mNow_ - 1 / 24, mNow_, TAtlasDiscoverAgeKind.Today, 0, 'heute');
  Check(EncodeDate(2026, 10, 14) + EncodeTime(23, 0, 0, 0), mNow_, TAtlasDiscoverAgeKind.Yesterday, 1, 'gestern');
  Check(mNow_ - 5, mNow_, TAtlasDiscoverAgeKind.Days, 5, 'Tage');
  Check(mNow_ - 13, mNow_, TAtlasDiscoverAgeKind.Days, 13, 'Tage');
  Check(mNow_ - 21, mNow_, TAtlasDiscoverAgeKind.Weeks, 3, 'vor 3 Wochen');
  Check(mNow_ - 59, mNow_, TAtlasDiscoverAgeKind.Weeks, 8, 'Wochen');
  Check(mNow_ - 95, mNow_, TAtlasDiscoverAgeKind.Months, 3, 'Monate');
  Check(mNow_ - 400, mNow_, TAtlasDiscoverAgeKind.Years, 1, 'Jahr');
  Check(mNow_ + 1, mNow_, TAtlasDiscoverAgeKind.Today, 0, 'Uhr zurückgestellt');
end;

procedure TAtlasDiscoverTests.QueueStaysStableWithinSession;
var
  mQueue, mAllowed: TArray<string>;
  mCurrent: string;
begin
  mQueue := ['a', 'b', 'c', 'd'];
  mAllowed := mQueue;
  mCurrent := TAtlasDiscover.Pick(mQueue, mAllowed, '');
  Assert.AreEqual('a', mCurrent, 'je Start der erste');
  mCurrent := TAtlasDiscover.NextAfter(mQueue, mAllowed, mCurrent);
  Assert.AreEqual('b', mCurrent, '„Nächster Tipp“');
  // „Nicht mehr zeigen“ auf b: der nächste rückt nach.
  mAllowed := ['a', 'c', 'd'];
  Assert.AreEqual('c', TAtlasDiscover.Pick(mQueue, mAllowed, mCurrent));
  // Funktion von d abgeschaltet, eine neue Funktion e eingeschaltet: e hinten an.
  mAllowed := ['a', 'c', 'e'];
  Assert.AreEqual('a,c,e', Joined(TAtlasDiscover.Effective(mQueue, mAllowed)));
  Assert.AreEqual('e', TAtlasDiscover.NextAfter(mQueue, mAllowed, 'c'));
  Assert.AreEqual('a', TAtlasDiscover.NextAfter(mQueue, mAllowed, 'e'), 'am Ende wieder vorn');
  Assert.AreEqual('a', TAtlasDiscover.Pick(mQueue, mAllowed, 'd'), 'nach d kommt wieder a');
  Assert.AreEqual('', TAtlasDiscover.Pick(mQueue, nil, 'a'), 'nichts mehr übrig');
  Assert.AreEqual('', TAtlasDiscover.NextAfter(mQueue, nil, 'a'));
  Assert.AreEqual(2, TAtlasDiscover.IndexIn(mQueue, 'C'));
end;

procedure TAtlasDiscoverTests.StateRoundTripsThroughTipsFile;
var
  mUsage, mLoaded: TAtlasCommandUsage;
  mState: TAtlasDiscoverState;
  mFolder, mTipsFile, mUsageFile: string;
begin
  mFolder := TPath.Combine(TPath.GetTempPath, 'atlas-discover-' + FormatDateTime('hhnnsszzz', Now) + '-s');
  mTipsFile := TAtlasCommandUsage.DefaultFile(mFolder);
  mUsageFile := TAtlasCommandUsage.DefaultUsageFile(mFolder);
  mUsage := TAtlasCommandUsage.Create;
  mLoaded := TAtlasCommandUsage.Create;
  try
    mState := NoState;
    mState.Block('rename');
    mState.Last := 'codeActions';
    mUsage.SetSection(TAtlasDiscover.cSectionName, mState.ToJson);
    mUsage.SaveToFiles(mTipsFile, mUsageFile);
    Assert.IsFalse(TFile.Exists(mUsageFile), 'ohne Zählung keine usage.json');
    mLoaded.LoadFromFiles(mTipsFile, mUsageFile);
    mState := TAtlasDiscoverState.Parse(mLoaded.Section(TAtlasDiscover.cSectionName));
    Assert.IsTrue(mState.IsBlocked('rename'));
    Assert.AreEqual('codeActions', mState.Last);
    mState := TAtlasDiscoverState.Parse('{kaputt');
    Assert.AreEqual(0, Integer(Length(mState.Blocked)));
    Assert.AreEqual('', mState.Last);
  finally
    mLoaded.Free;
    mUsage.Free;
    if TDirectory.Exists(mFolder) then
    begin
      TDirectory.Delete(mFolder, True);
    end;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTipCatalogTests);
  TDUnitX.RegisterTestFixture(TAtlasDiscoverTests);

end.
