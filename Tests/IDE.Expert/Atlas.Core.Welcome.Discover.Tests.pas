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
  end;

  [TestFixture]
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
  Atlas.Core.Commands.Usage,
  Atlas.Core.Commands.Tips,
  Atlas.Core.Welcome.Discover;

const
  Catalog =
    '{"format":1,"tips":[' +
    '{"id":"codeActions","command":"Atlas.CodeActions","title":"Code-Aktionen","titleEn":"Code actions",' +
      '"text":"Strg+. zeigt, was Atlas hier kann.","textEn":"Ctrl+. shows what Atlas can do here.",' +
      '"image":"Tipps\\code-aktionen.png","sample":"Beispiele\\Entdecken.pas","line":12,"column":5},' +
    '{"id":"expand","command":"Atlas.ExpandSelection","usage":["Atlas.ExpandSelection","Atlas.ShrinkSelection"],' +
      '"title":"Auswahl erweitern","text":"Schritt für Schritt."},' +
    '{"id":"undo","command":"Atlas.UndoChange","setting":"UndoMultiFile","title":"Zurücknehmen über Dateien"},' +
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
  Result := TAtlasTipCatalog.Parse(Catalog);
end;

function NoState: TAtlasDiscoverState;
begin
  Result := Default(TAtlasDiscoverState);
end;

{ TAtlasTipCatalogTests }

procedure TAtlasTipCatalogTests.ParsesTipsWithDefaults;
var
  List: TAtlasTips;
begin
  List := Tips;
  Assert.AreEqual(4, Integer(Length(List)));
  Assert.AreEqual('codeActions', List[0].Id);
  Assert.AreEqual('Atlas.CodeActions', List[0].Command);
  Assert.AreEqual('Code-Aktionen', List[0].TitleIn(False));
  Assert.AreEqual('Code actions', List[0].TitleIn(True));
  Assert.AreEqual('Ctrl+. shows what Atlas can do here.', List[0].TextIn(True));
  Assert.AreEqual('Tipps\code-aktionen.png', List[0].Image);
  Assert.AreEqual('Beispiele\Entdecken.pas', List[0].Sample);
  Assert.AreEqual(12, List[0].Line);
  Assert.AreEqual(5, List[0].Column);
  Assert.AreEqual('Atlas.CodeActions', Joined(List[0].UsageIds), 'ohne usage zählt der Befehl');
  Assert.AreEqual('Atlas.ExpandSelection,Atlas.ShrinkSelection', Joined(List[1].UsageIds));
  Assert.AreEqual('Auswahl erweitern', List[1].TitleIn(True), 'ohne Englisch der deutsche Titel');
  Assert.AreEqual('UndoMultiFile', List[2].Setting);
  Assert.AreEqual('Atlas.SymbolSearch', List[3].Id, 'ohne id gilt der Befehl');
end;

procedure TAtlasTipCatalogTests.SkipsInvalidAndDuplicateTips;
var
  List: TAtlasTips;
begin
  Assert.AreEqual(0, Integer(Length(TAtlasTipCatalog.Parse('kein JSON'))));
  Assert.AreEqual(0, Integer(Length(TAtlasTipCatalog.Parse('{"tips":{}}'))));
  Assert.AreEqual(0, Integer(Length(TAtlasTipCatalog.Parse(''))));
  List := TAtlasTipCatalog.Parse('{"tips":[1,{"title":"ohne Befehl"},{"id":"a"},' +
    '{"id":"a","title":"Erster","usage":"Atlas.X","line":-3},{"id":"A","title":"Doppelt"},' +
    '{"id":"b","title":"Zweiter","futureField":true}]}');
  Assert.AreEqual(2, Integer(Length(List)));
  Assert.AreEqual('Erster', List[0].Title, 'die erste von doppelten Kennungen gilt');
  Assert.AreEqual('Atlas.X', Joined(List[0].UsageIds), 'usage auch als Text');
  Assert.AreEqual(0, List[0].Line, 'negative Zeile wird 0');
  Assert.AreEqual('b', List[1].Id);
end;

procedure TAtlasTipCatalogTests.FindsTipByCommand;
var
  Tip: TAtlasTip;
begin
  Assert.IsTrue(TAtlasTipCatalog.FindByCommand(Tips, 'atlas.codeactions', Tip));
  Assert.AreEqual('codeActions', Tip.Id);
  Assert.IsFalse(TAtlasTipCatalog.FindByCommand(Tips, 'Atlas.Unbekannt', Tip));
  Assert.IsFalse(TAtlasTipCatalog.FindByCommand(Tips, '', Tip));
  Assert.AreEqual(1, TAtlasTipCatalog.IndexOf(Tips, 'EXPAND'));
  Assert.AreEqual(-1, TAtlasTipCatalog.IndexOf(Tips, 'nichts'));
end;

procedure TAtlasTipCatalogTests.FileStaysInInstallFolder;
var
  Folder: string;
begin
  Folder := TPath.Combine(TPath.GetTempPath, 'Atlas');
  Assert.AreEqual(IncludeTrailingPathDelimiter(Folder) + 'Tipps' + PathDelim + 'a.png',
    TAtlasTipCatalog.FileIn(Folder, 'Tipps\a.png'));
  Assert.AreEqual(IncludeTrailingPathDelimiter(Folder) + 'Tipps' + PathDelim + 'a.png',
    TAtlasTipCatalog.FileIn(Folder, 'Tipps/a.png'));
  Assert.AreEqual('', TAtlasTipCatalog.FileIn(Folder, '..\Windows\a.png'));
  Assert.AreEqual('', TAtlasTipCatalog.FileIn(Folder, 'C:\a.png'));
  Assert.AreEqual('', TAtlasTipCatalog.FileIn(Folder, '\a.png'));
  Assert.AreEqual('', TAtlasTipCatalog.FileIn(Folder, ''));
  Assert.AreEqual('', TAtlasTipCatalog.FileIn('', 'Tipps\a.png'));
end;

{ TAtlasDiscoverTests }

procedure TAtlasDiscoverTests.WarmUpFirstUse;
begin
  EnabledFollowsSettingAndCommand;
end;

procedure TAtlasDiscoverTests.NeverUsedComesBeforeUsed;
var
  Usage: TAtlasCommandUsage;
  Order: TArray<string>;
begin
  // Akzeptanz: Ein Befehl, der nie benutzt wurde, wird vor einem bereits benutzten vorgeschlagen.
  Usage := TAtlasCommandUsage.Create;
  try
    Usage.Count('Atlas.CodeActions', TAtlasCommandInput.Mouse, Moment(10, 9));
    Usage.Count('Atlas.ShrinkSelection', TAtlasCommandInput.Keyboard, Moment(11, 9));
    Order := TAtlasDiscover.Order(Tips, Usage, NoState, nil, True);
    Assert.AreEqual('undo,Atlas.SymbolSearch,codeActions,expand', Joined(Order),
      'erst nie benutzte, dann am längsten nicht benutzte; Auswahl erweitern zählt über Verkleinern');
    Assert.IsTrue(TAtlasDiscover.NeverUsed(Tips[2], Usage));
    Assert.IsFalse(TAtlasDiscover.NeverUsed(Tips[1], Usage));
    Assert.IsTrue(TAtlasDiscover.NeverUsed(Tips[0], nil), 'ohne Zählung gilt alles als nie benutzt');
  finally
    Usage.Free;
  end;
end;

procedure TAtlasDiscoverTests.UsedCommandIsNoLongerNeverUsedAfterRestart;
var
  Usage, Loaded: TAtlasCommandUsage;
  Folder, TipsFile, UsageFile: string;
  Order: TArray<string>;
  Age: TAtlasDiscoverAge;
begin
  // Akzeptanz: Nach Benutzen des vorgeschlagenen Befehls kommt er beim nächsten Start nicht mehr als
  // „noch nie benutzt“.
  Folder := TPath.Combine(TPath.GetTempPath, 'atlas-discover-' + FormatDateTime('hhnnsszzz', Now));
  TipsFile := TAtlasCommandUsage.DefaultFile(Folder);
  UsageFile := TAtlasCommandUsage.DefaultUsageFile(Folder);
  Usage := TAtlasCommandUsage.Create;
  Loaded := TAtlasCommandUsage.Create;
  try
    Order := TAtlasDiscover.Order(Tips, Usage, NoState, nil, True);
    Assert.AreEqual('codeActions', Order[0]);
    Age := TAtlasDiscover.UsageAge(Tips[0], Usage, True, Moment(15, 10));
    Assert.IsTrue(Age.Kind = TAtlasDiscoverAgeKind.Never);
    // „Ausprobieren“ führt den Befehl über die Palette aus: Das zählt als Aufruf.
    Usage.Count('Atlas.CodeActions', TAtlasCommandInput.Mouse, Moment(15, 10));
    Usage.SaveToFiles(TipsFile, UsageFile);
    // Nächster Start.
    Loaded.LoadFromFiles(TipsFile, UsageFile);
    Order := TAtlasDiscover.Order(Tips, Loaded, NoState, nil, True);
    Assert.AreEqual('expand,undo,Atlas.SymbolSearch,codeActions', Joined(Order));
    Age := TAtlasDiscover.UsageAge(Tips[0], Loaded, True, Moment(16, 9));
    Assert.IsTrue(Age.Kind = TAtlasDiscoverAgeKind.Yesterday, 'nicht mehr „noch nie benutzt“');
  finally
    Loaded.Free;
    Usage.Free;
    if TDirectory.Exists(Folder) then
      TDirectory.Delete(Folder, True);
  end;
end;

procedure TAtlasDiscoverTests.LongestUnusedComesFirst;
var
  Usage: TAtlasCommandUsage;
begin
  Usage := TAtlasCommandUsage.Create;
  try
    Usage.Count('Atlas.CodeActions', TAtlasCommandInput.Mouse, Moment(14, 9));
    Usage.Count('Atlas.ExpandSelection', TAtlasCommandInput.Mouse, Moment(1, 9));
    Usage.Count('Atlas.UndoChange', TAtlasCommandInput.Mouse, Moment(7, 9));
    Usage.Count('Atlas.SymbolSearch', TAtlasCommandInput.Mouse, Moment(7, 9));
    Assert.AreEqual('expand,undo,Atlas.SymbolSearch,codeActions',
      Joined(TAtlasDiscover.Order(Tips, Usage, NoState, nil, True)), 'Gleichstand: wie in tips.json');
  finally
    Usage.Free;
  end;
end;

procedure TAtlasDiscoverTests.BlockedAndDisabledTipsNeverAppear;
var
  Usage: TAtlasCommandUsage;
  State: TAtlasDiscoverState;
  Order: TArray<string>;
begin
  // Akzeptanz: „Nicht mehr zeigen“ sperrt den Tipp dauerhaft; abgeschaltete Funktionen erscheinen nie.
  Usage := TAtlasCommandUsage.Create;
  try
    State := NoState;
    State.Block('CODEACTIONS');
    State.Block('codeActions');
    State.Block('');
    Assert.AreEqual(1, Integer(Length(State.Blocked)));
    Order := TAtlasDiscover.Order(Tips, Usage, State,
      function(ATip: TAtlasTip): Boolean
      begin
        // Einstellung UndoMultiFile aus.
        Result := ATip.Setting <> 'UndoMultiFile';
      end, True);
    Assert.AreEqual('expand,Atlas.SymbolSearch', Joined(Order));
    Order := TAtlasDiscover.Order(Tips, Usage, State,
      function(ATip: TAtlasTip): Boolean
      begin
        Result := False;
      end, False);
    Assert.AreEqual(0, Integer(Length(Order)), 'auch ohne Zählung nie');
    // Dauerhaft: der Zustand übersteht das Speichern.
    State := TAtlasDiscoverState.Parse(State.ToJson);
    Assert.IsTrue(State.IsBlocked('codeactions'));
  finally
    Usage.Free;
  end;
end;

procedure TAtlasDiscoverTests.EnabledFollowsSettingAndCommand;
var
  List: TAtlasTips;
  SettingOn, CommandExists: TFunc<string, Boolean>;
  Order: TArray<string>;
begin
  List := Tips;
  // Nur UndoMultiFile ist eine bekannte Einstellung, und sie ist aus; die Palette kennt keine Symbolsuche.
  SettingOn :=
    function(AName: string): Boolean
    begin
      Result := False;
    end;
  CommandExists :=
    function(AId: string): Boolean
    begin
      Result := not SameText(AId, 'Atlas.SymbolSearch');
    end;
  Assert.IsTrue(TAtlasDiscover.IsEnabled(List[0], SettingOn, CommandExists), 'ohne Einstellung: Befehl zählt');
  Assert.IsFalse(TAtlasDiscover.IsEnabled(List[2], SettingOn, CommandExists), 'Einstellung aus');
  Assert.IsFalse(TAtlasDiscover.IsEnabled(List[3], SettingOn, CommandExists), 'Befehl nicht in der Palette');
  Assert.IsTrue(TAtlasDiscover.IsEnabled(List[2], nil, nil), 'ohne Prüfung alles');
  Order := TAtlasDiscover.Order(List, nil, NoState,
    function(ATip: TAtlasTip): Boolean
    begin
      Result := TAtlasDiscover.IsEnabled(ATip, SettingOn, CommandExists);
    end, True);
  Assert.AreEqual('codeActions,expand', Joined(Order));
  SettingOn :=
    function(AName: string): Boolean
    begin
      Result := SameText(AName, 'UndoMultiFile');
    end;
  Assert.IsTrue(TAtlasDiscover.IsEnabled(List[2], SettingOn, CommandExists), 'Einstellung an');
  // Die Closures liegen im selben Rahmen wie die Variablen, die sie halten: Kreis lösen.
  SettingOn := nil;
  CommandExists := nil;
end;

procedure TAtlasDiscoverTests.NewStartBeginsAfterLastShownTip;
var
  Usage: TAtlasCommandUsage;
  State: TAtlasDiscoverState;
begin
  // Je IDE-Start ein anderer Tipp: die nie benutzten beginnen nach dem zuletzt gezeigten.
  Usage := TAtlasCommandUsage.Create;
  try
    State := NoState;
    State.Last := 'expand';
    Assert.AreEqual('undo,Atlas.SymbolSearch,codeActions,expand',
      Joined(TAtlasDiscover.Order(Tips, Usage, State, nil, True)));
    State.Last := 'Atlas.SymbolSearch';
    Assert.AreEqual('codeActions,expand,undo,Atlas.SymbolSearch',
      Joined(TAtlasDiscover.Order(Tips, Usage, State, nil, True)));
    // Der zuletzt gezeigte ist inzwischen benutzt: Die nie benutzten beginnen trotzdem nach ihm.
    Usage.Count('Atlas.ExpandSelection', TAtlasCommandInput.Mouse, Moment(15, 9));
    State.Last := 'expand';
    Assert.AreEqual('undo,Atlas.SymbolSearch,codeActions,expand',
      Joined(TAtlasDiscover.Order(Tips, Usage, State, nil, True)));
    State.Last := 'gibt-es-nicht';
    Assert.AreEqual('codeActions,undo,Atlas.SymbolSearch,expand',
      Joined(TAtlasDiscover.Order(Tips, Usage, State, nil, True)));
  finally
    Usage.Free;
  end;
end;

procedure TAtlasDiscoverTests.WithoutTrackingTipsComeInOrder;
var
  Usage: TAtlasCommandUsage;
  State: TAtlasDiscoverState;
  Age: TAtlasDiscoverAge;
begin
  // tips.usageTracking aus: der Reihe nach, ohne Bezug zur Nutzung.
  Usage := TAtlasCommandUsage.Create;
  try
    Usage.Count('Atlas.CodeActions', TAtlasCommandInput.Mouse, Moment(14, 9));
    State := NoState;
    Assert.AreEqual('codeActions,expand,undo,Atlas.SymbolSearch',
      Joined(TAtlasDiscover.Order(Tips, Usage, State, nil, False)));
    State.Last := 'codeActions';
    Assert.AreEqual('expand,undo,Atlas.SymbolSearch,codeActions',
      Joined(TAtlasDiscover.Order(Tips, Usage, State, nil, False)));
    Age := TAtlasDiscover.UsageAge(Tips[0], Usage, False, Moment(15, 9));
    Assert.IsTrue(Age.Kind = TAtlasDiscoverAgeKind.None, 'kein Hinweis zur Nutzung');
    Assert.AreEqual('codeActions,expand,undo,Atlas.SymbolSearch',
      Joined(TAtlasDiscover.Order(Tips, nil, NoState, nil, True)), 'ohne Zählung (nil) ebenso');
  finally
    Usage.Free;
  end;
end;

procedure TAtlasDiscoverTests.WithoutTrackingNothingIsCounted;
var
  Usage: TAtlasCommandUsage;
begin
  // Akzeptanz: Mit tips.usageTracking aus wird nichts gezählt.
  Usage := TAtlasCommandUsage.Create;
  try
    Usage.Tracking := False;
    Usage.Count('Atlas.CodeActions', TAtlasCommandInput.Mouse, Moment(14, 9));
    Assert.IsTrue(TAtlasDiscover.NeverUsed(Tips[0], Usage));
    Assert.IsFalse(Usage.CountsChanged);
    Assert.DoesNotContain(Usage.CountsToJson, 'Atlas.CodeActions');
  finally
    Usage.Free;
  end;
end;

procedure TAtlasDiscoverTests.AgeTextsFollowCalendarDays;

  procedure Check(ALastUsed, ANow: TDateTime; AKind: TAtlasDiscoverAgeKind; ACount: Integer; const AMessage: string);
  var
    Age: TAtlasDiscoverAge;
  begin
    Age := TAtlasDiscover.AgeOf(ALastUsed, ANow);
    Assert.IsTrue(Age.Kind = AKind, AMessage);
    Assert.AreEqual(ACount, Age.Count, AMessage);
  end;

var
  Now_: TDateTime;
begin
  Now_ := EncodeDate(2026, 10, 15) + EncodeTime(9, 0, 0, 0);
  Check(0, Now_, TAtlasDiscoverAgeKind.Never, 0, 'nie');
  Check(Now_ - 1 / 24, Now_, TAtlasDiscoverAgeKind.Today, 0, 'heute');
  Check(EncodeDate(2026, 10, 14) + EncodeTime(23, 0, 0, 0), Now_, TAtlasDiscoverAgeKind.Yesterday, 1, 'gestern');
  Check(Now_ - 5, Now_, TAtlasDiscoverAgeKind.Days, 5, 'Tage');
  Check(Now_ - 13, Now_, TAtlasDiscoverAgeKind.Days, 13, 'Tage');
  Check(Now_ - 21, Now_, TAtlasDiscoverAgeKind.Weeks, 3, 'vor 3 Wochen');
  Check(Now_ - 59, Now_, TAtlasDiscoverAgeKind.Weeks, 8, 'Wochen');
  Check(Now_ - 95, Now_, TAtlasDiscoverAgeKind.Months, 3, 'Monate');
  Check(Now_ - 400, Now_, TAtlasDiscoverAgeKind.Years, 1, 'Jahr');
  Check(Now_ + 1, Now_, TAtlasDiscoverAgeKind.Today, 0, 'Uhr zurückgestellt');
end;

procedure TAtlasDiscoverTests.QueueStaysStableWithinSession;
var
  Queue, Allowed: TArray<string>;
  Current: string;
begin
  Queue := ['a', 'b', 'c', 'd'];
  Allowed := Queue;
  Current := TAtlasDiscover.Pick(Queue, Allowed, '');
  Assert.AreEqual('a', Current, 'je Start der erste');
  Current := TAtlasDiscover.NextAfter(Queue, Allowed, Current);
  Assert.AreEqual('b', Current, '„Nächster Tipp“');
  // „Nicht mehr zeigen“ auf b: der nächste rückt nach.
  Allowed := ['a', 'c', 'd'];
  Assert.AreEqual('c', TAtlasDiscover.Pick(Queue, Allowed, Current));
  // Funktion von d abgeschaltet, eine neue Funktion e eingeschaltet: e hinten an.
  Allowed := ['a', 'c', 'e'];
  Assert.AreEqual('a,c,e', Joined(TAtlasDiscover.Effective(Queue, Allowed)));
  Assert.AreEqual('e', TAtlasDiscover.NextAfter(Queue, Allowed, 'c'));
  Assert.AreEqual('a', TAtlasDiscover.NextAfter(Queue, Allowed, 'e'), 'am Ende wieder vorn');
  Assert.AreEqual('a', TAtlasDiscover.Pick(Queue, Allowed, 'd'), 'nach d kommt wieder a');
  Assert.AreEqual('', TAtlasDiscover.Pick(Queue, nil, 'a'), 'nichts mehr übrig');
  Assert.AreEqual('', TAtlasDiscover.NextAfter(Queue, nil, 'a'));
  Assert.AreEqual(2, TAtlasDiscover.IndexIn(Queue, 'C'));
end;

procedure TAtlasDiscoverTests.StateRoundTripsThroughTipsFile;
var
  Usage, Loaded: TAtlasCommandUsage;
  State: TAtlasDiscoverState;
  Folder, TipsFile, UsageFile: string;
begin
  Folder := TPath.Combine(TPath.GetTempPath, 'atlas-discover-' + FormatDateTime('hhnnsszzz', Now) + '-s');
  TipsFile := TAtlasCommandUsage.DefaultFile(Folder);
  UsageFile := TAtlasCommandUsage.DefaultUsageFile(Folder);
  Usage := TAtlasCommandUsage.Create;
  Loaded := TAtlasCommandUsage.Create;
  try
    State := NoState;
    State.Block('rename');
    State.Last := 'codeActions';
    Usage.SetSection(TAtlasDiscover.SectionName, State.ToJson);
    Usage.SaveToFiles(TipsFile, UsageFile);
    Assert.IsFalse(TFile.Exists(UsageFile), 'ohne Zählung keine usage.json');
    Loaded.LoadFromFiles(TipsFile, UsageFile);
    State := TAtlasDiscoverState.Parse(Loaded.Section(TAtlasDiscover.SectionName));
    Assert.IsTrue(State.IsBlocked('rename'));
    Assert.AreEqual('codeActions', State.Last);
    State := TAtlasDiscoverState.Parse('{kaputt');
    Assert.AreEqual(0, Integer(Length(State.Blocked)));
    Assert.AreEqual('', State.Last);
  finally
    Loaded.Free;
    Usage.Free;
    if TDirectory.Exists(Folder) then
      TDirectory.Delete(Folder, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTipCatalogTests);
  TDUnitX.RegisterTestFixture(TAtlasDiscoverTests);

end.
