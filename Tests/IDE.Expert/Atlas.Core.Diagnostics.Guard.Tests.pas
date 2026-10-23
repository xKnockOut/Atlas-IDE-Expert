unit Atlas.Core.Diagnostics.Guard.Tests;

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>Absturzsicherheit (#493): Schutz, Sicherung, Protokoll.</summary>
  [TestFixture]
  TAtlasGuardTests = class
  private
    FFolder: string;
    FOldFolder: string;
  public
    /// <summary>Erste Benutzung (VCL, Codepages, RTTI) ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure RunSwallowsExceptions;
    [Test]
    procedure FuseTripsAfterThreeFailuresWithinFiveMinutes;
    [Test]
    procedure OldFailuresDoNotCount;
    [Test]
    procedure TrippedFeatureIsSkippedOthersRun;
    /// <summary>Die Brotkrumenleiste hat eine eigene Sicherung: Fehler der übrigen Editorbefehle schalten sie
    /// nicht ab (sie blieb sonst nach einer Weile stehen).</summary>
    [Test]
    procedure BreadcrumbsHaveTheirOwnFuse;
    [Test]
    procedure LogRotatesAtLimit;
    /// <summary>Scheitert das Rotieren, wird trotzdem angehängt und der Grund einmal vermerkt (Bericht M4); früher
    /// ging dabei jede Zeile verloren.</summary>
    [Test]
    procedure LogKeepsWritingWhenRotationFails;
    /// <summary>Scheitert das Anhängen, zählt das Protokoll die Zeilen, meldet den ersten Fehler über OnError und
    /// vermerkt die Lücke beim nächsten Gelingen (Bericht M4).</summary>
    [Test]
    procedure LogCountsLostLinesAndReportsTheGap;
    /// <summary>Ein Mutex je Ordner, gleich für alle Schreibweisen des Ordners.</summary>
    [Test]
    procedure LogMutexNameDependsOnlyOnTheFolder;
    [Test]
    procedure ProviderFuseTripsOnlyThatProvider;
    [Test]
    procedure LogLineIsShortSingleLineWithVersion;
    [Test]
    procedure ErrorLineCarriesStackFromHook;
    [Test]
    procedure FailingStackHookKeepsErrorLine;
    /// <summary>Derselbe Fehler kurz nach dem gezählten zählt nicht (ein Zeichendurchlauf meldet ihn je Zeile);
    /// fester Abstand, sodass ein dauernder Fehler die Sicherung weiterhin auslöst.</summary>
    [Test]
    procedure RepeatedFailureCountsOncePerWindow;
    /// <summary>Wiederholungen stehen nicht einzeln im Protokoll; die nächste gezählte Zeile nennt ihre Zahl.</summary>
    [Test]
    procedure RepeatsOfOnePaintPassDoNotTrip;
    [Test]
    procedure TripReportsFeatureAndMessage;
    /// <summary>Jede sichtbare Funktion hat eine eigene Sicherung mit eigenem Namen.</summary>
    [Test]
    procedure FeaturesHaveDistinctNames;
    /// <summary>Langsame Quelle: kein Fehler, eine Protokollzeile je Quelle und Minute mit der Zahl der übergangenen.
    /// </summary>
    [Test]
    procedure SlowProviderLogsOncePerInterval;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.DateUtils,
  System.Generics.Collections,
  Atlas.Core.Product.Version,
  Atlas.Core.Diagnostics.Guard;

/// <summary>Löst einen von drei Fehlern an drei verschiedenen Stellen aus: Wiederholungen derselben Stelle zählen
/// innerhalb von TAtlasFuse.RepeatMs nur einmal.</summary>
procedure RaiseAt(AIndex: Integer);
begin
  case AIndex of
    1:
      raise Exception.Create('Fehler 1');
    2:
      raise Exception.Create('Fehler 2');
  else
    raise Exception.Create('Fehler 3');
  end;
end;

/// <summary>RaiseAt als Aufruf für TAtlasGuard.Run; über den Parameter statt die Schleifenvariable gebunden.</summary>
function RaiserAt(AIndex: Integer): TProc;
begin
  Result :=
    procedure
    begin
      RaiseAt(AIndex);
    end;
end;

procedure TAtlasGuardTests.WarmUpFirstUse;
begin
  Setup;
  try
    ProviderFuseTripsOnlyThatProvider;
  finally
    TearDown;
  end;
  // Schreibfehler des Protokolls: Erstgebrauch der Fehlerpfade beim Anhängen.
  Setup;
  try
    LogCountsLostLinesAndReportsTheGap;
  finally
    TearDown;
  end;
end;

procedure TAtlasGuardTests.Setup;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'AtlasGuardTests' + TGUID.NewGuid.ToString);
  FOldFolder := TAtlasGuard.RotatingLog.Folder;
  TAtlasGuard.RotatingLog.Folder := FFolder;
  TAtlasGuard.Fuse.ResetAll;
end;

procedure TAtlasGuardTests.TearDown;
begin
  TAtlasGuard.Fuse.ResetAll;
  TAtlasGuard.OnWarning := nil;
  TAtlasGuard.StackOf := nil;
  TAtlasGuard.RotatingLog.Folder := FOldFolder;
  if TDirectory.Exists(FFolder) then
    TDirectory.Delete(FFolder, True);
  FFolder := '';
  FOldFolder := '';
end;

procedure TAtlasGuardTests.RunSwallowsExceptions;
var
  Ran: Boolean;
begin
  Assert.IsFalse(TAtlasGuard.Run(TAtlasFeature.Hover,
    procedure
    begin
      raise EInvalidOpException.Create('kaputt');
    end));
  Ran := False;
  Assert.IsTrue(TAtlasGuard.Run(TAtlasFeature.Hover,
    procedure
    begin
      Ran := True;
    end));
  Assert.IsTrue(Ran);
  Assert.Contains(TFile.ReadAllText(TPath.Combine(FFolder, 'atlas.log'), TEncoding.UTF8), 'EInvalidOpException: kaputt');
end;

procedure TAtlasGuardTests.FuseTripsAfterThreeFailuresWithinFiveMinutes;
var
  Fuse: TAtlasFuse;
  Clock: TDateTime;
begin
  Clock := EncodeDateTime(2026, 10, 11, 12, 0, 0, 0);
  Fuse := TAtlasFuse.Create(
    function: TDateTime
    begin
      Result := Clock;
    end);
  try
    Assert.IsFalse(Fuse.Failed(TAtlasFeature.Completion));
    Clock := IncMinute(Clock, 2);
    Assert.IsFalse(Fuse.Failed(TAtlasFeature.Completion));
    Clock := IncMinute(Clock, 2);
    Assert.IsTrue(Fuse.Failed(TAtlasFeature.Completion), 'dritter Fehler in 4 Minuten löst aus');
    Assert.IsTrue(Fuse.Tripped(TAtlasFeature.Completion));
    Assert.IsFalse(Fuse.Tripped(TAtlasFeature.Hover), 'nur das betroffene Feature');
    Fuse.Reset(TAtlasFeature.Completion);
    Assert.IsFalse(Fuse.Tripped(TAtlasFeature.Completion));
  finally
    Fuse.Free;
  end;
end;

procedure TAtlasGuardTests.OldFailuresDoNotCount;
var
  Fuse: TAtlasFuse;
  Clock: TDateTime;
begin
  Clock := EncodeDateTime(2026, 10, 11, 12, 0, 0, 0);
  Fuse := TAtlasFuse.Create(
    function: TDateTime
    begin
      Result := Clock;
    end);
  try
    Fuse.Failed(TAtlasFeature.Pairs);
    Fuse.Failed(TAtlasFeature.Pairs);
    Clock := IncMinute(Clock, 6);
    Assert.IsFalse(Fuse.Failed(TAtlasFeature.Pairs), 'ältere Fehler liegen außerhalb der 5 Minuten');
  finally
    Fuse.Free;
  end;
end;

procedure TAtlasGuardTests.TrippedFeatureIsSkippedOthersRun;
var
  Index, Calls: Integer;
  Warning: string;
begin
  TAtlasGuard.OnWarning :=
    procedure(const AText: string)
    begin
      Warning := AText;
    end;
  for Index := 1 to 3 do
    TAtlasGuard.Run(TAtlasFeature.Problems, RaiserAt(Index));
  Assert.IsTrue(TAtlasGuard.Disabled(TAtlasFeature.Problems));
  Assert.Contains(Warning, 'Probleme');
  Calls := 0;
  TAtlasGuard.Run(TAtlasFeature.Problems,
    procedure
    begin
      Inc(Calls);
    end);
  Assert.AreEqual(0, Calls, 'abgeschaltet: läuft nicht mehr');
  TAtlasGuard.Run(TAtlasFeature.Hover,
    procedure
    begin
      Inc(Calls);
    end);
  Assert.AreEqual(1, Calls, 'andere Features laufen weiter');
  TAtlasGuard.Enable(TAtlasFeature.Problems);
  Assert.IsFalse(TAtlasGuard.Disabled(TAtlasFeature.Problems));
end;

procedure TAtlasGuardTests.BreadcrumbsHaveTheirOwnFuse;
var
  Index, Calls: Integer;
begin
  Assert.AreEqual('Brotkrumenleiste', TAtlasGuard.FeatureName(TAtlasFeature.Breadcrumbs));
  for Index := 1 to 3 do
    TAtlasGuard.Run(TAtlasFeature.EditorCommands, RaiserAt(Index));
  Assert.IsTrue(TAtlasGuard.Disabled(TAtlasFeature.EditorCommands));
  Assert.IsFalse(TAtlasGuard.Disabled(TAtlasFeature.Breadcrumbs), 'Editorbefehle reißen die Leiste nicht mit');
  Calls := 0;
  TAtlasGuard.Run(TAtlasFeature.Breadcrumbs,
    procedure
    begin
      Inc(Calls);
    end);
  Assert.AreEqual(1, Calls);
  for Index := 1 to 3 do
    TAtlasGuard.Run(TAtlasFeature.Breadcrumbs, RaiserAt(Index));
  Assert.IsTrue(TAtlasGuard.Disabled(TAtlasFeature.Breadcrumbs));
  TAtlasGuard.EnableAll;
  Assert.IsFalse(TAtlasGuard.Disabled(TAtlasFeature.Breadcrumbs), 'Abgeschaltete Funktionen einschalten');
end;

procedure TAtlasGuardTests.LogRotatesAtLimit;
var
  Log: TAtlasRotatingLog;
  Index: Integer;
begin
  Log := TAtlasRotatingLog.Create(FFolder, 200, 3);
  try
    for Index := 1 to 40 do
      Log.Add(StringOfChar('x', 40));
    Assert.IsTrue(TFile.Exists(TPath.Combine(FFolder, 'atlas.1.log')));
    Assert.IsTrue(TFile.Exists(TPath.Combine(FFolder, 'atlas.2.log')));
    Assert.IsFalse(TFile.Exists(TPath.Combine(FFolder, 'atlas.3.log')), 'höchstens 3 Dateien');
  finally
    Log.Free;
  end;
end;

/// <summary>Wie oft ASub in AText vorkommt.</summary>
function Occurrences(const AText, ASub: string): Integer;
var
  Offset: Integer;
begin
  Result := 0;
  Offset := Pos(ASub, AText);
  while Offset > 0 do
  begin
    Inc(Result);
    Offset := Pos(ASub, AText, Offset + Length(ASub));
  end;
end;

procedure TAtlasGuardTests.LogKeepsWritingWhenRotationFails;
var
  Log: TAtlasRotatingLog;
  Index: Integer;
  Text: string;
begin
  Log := TAtlasRotatingLog.Create(FFolder, 100, 3);
  try
    ForceDirectories(FFolder);
    // atlas.1.log lässt sich nicht nach atlas.2.log verschieben, dort liegt ein Ordner.
    TFile.WriteAllText(TPath.Combine(FFolder, 'atlas.1.log'), 'alt');
    TDirectory.CreateDirectory(TPath.Combine(FFolder, 'atlas.2.log'));
    for Index := 1 to 10 do
      Log.Add('Zeile ' + IntToStr(Index));
    Text := TFile.ReadAllText(Log.FileName);
    Assert.Contains(Text, 'Zeile 10', 'trotz gescheitertem Rotieren angehängt');
    Assert.AreEqual(1, Occurrences(Text, 'Protokoll: Rotieren gescheitert'), 'Grund nur einmal');
    Assert.DoesNotContain(Text, FFolder, 'ohne Ordner (Benutzername)');
    Assert.AreEqual(0, Log.Lost, 'keine Zeile verloren');
  finally
    Log.Free;
  end;
end;

procedure TAtlasGuardTests.LogCountsLostLinesAndReportsTheGap;
var
  Log: TAtlasRotatingLog;
  Reports: TArray<string>;
  Blocker, Text: string;
begin
  Reports := nil;
  Log := TAtlasRotatingLog.Create(FFolder);
  try
    Log.OnError :=
      procedure(const AMessage: string)
      begin
        Reports := Reports + [AMessage];
      end;
    // Ein Ordner namens atlas.log: Anhängen scheitert.
    Blocker := TPath.Combine(FFolder, 'atlas.log');
    TDirectory.CreateDirectory(Blocker);
    Log.Add('eins');
    Log.Add('zwei');
    Log.Add('drei');
    Assert.AreEqual(3, Log.Lost);
    Assert.AreEqual(1, Integer(Length(Reports)), 'nur der erste Fehler wird gemeldet');
    Assert.IsTrue(Reports[0] <> '', 'mit Grund');
    Assert.AreEqual(Reports[0], Log.LastError);
    TDirectory.Delete(Blocker);
    Log.Add('vier');
    Assert.AreEqual(2, Integer(Length(Reports)));
    Assert.AreEqual('', Reports[1], 'wieder in Ordnung');
    Assert.AreEqual('', Log.LastError);
    Assert.AreEqual(3, Log.Lost, 'die Summe bleibt');
    Text := TFile.ReadAllText(Log.FileName);
    Assert.Contains(Text, 'Protokoll: 3 Zeilen nicht geschrieben');
    Assert.Contains(Text, 'vier');
    Assert.DoesNotContain(Text, 'eins');
    Assert.DoesNotContain(Text, FFolder, 'ohne Ordner (Benutzername)');
  finally
    Log.Free;
  end;
end;

procedure TAtlasGuardTests.LogMutexNameDependsOnlyOnTheFolder;
var
  Name: string;
begin
  Name := TAtlasRotatingLog.MutexName('C:\Users\Anna\AppData\Local\Atlas\Logs');
  Assert.AreEqual(Name, TAtlasRotatingLog.MutexName(
    IncludeTrailingPathDelimiter('c:\users\anna\appdata\local\atlas\logs')), 'Schreibweise und Schlussstrich egal');
  Assert.AreNotEqual(Name, TAtlasRotatingLog.MutexName('C:\Users\Anna\AppData\Local\Temp\AtlasTests\Logs'));
  Assert.IsTrue(Name.StartsWith('Local\Atlas.Log.'), Name);
  Assert.AreEqual(0, Pos('\', Copy(Name, 7, MaxInt)), 'kein Backslash nach dem Namensraum');
end;

procedure TAtlasGuardTests.ProviderFuseTripsOnlyThatProvider;
var
  Index, Calls: Integer;
  Warning: string;
begin
  TAtlasGuard.OnWarning :=
    procedure(const AText: string)
    begin
      Warning := AText;
    end;
  for Index := 1 to 2 do
    TAtlasGuard.ReportProvider('SQL', 'kaputt');
  Assert.IsFalse(TAtlasGuard.ProviderDisabled('SQL'));
  Assert.AreEqual('', Warning, 'noch keine Warnung');
  TAtlasGuard.ReportProvider('SQL', 'kaputt');
  Assert.IsTrue(TAtlasGuard.ProviderDisabled('SQL'));
  Assert.IsTrue(TAtlasGuard.ProviderDisabled('sql'));
  Assert.Contains(Warning, '„SQL“');
  Assert.Contains(Warning, 'Tools > Optionen > Drittanbieter > Atlas');
  Assert.AreEqual(1, Integer(Length(TAtlasGuard.DisabledProviders)));
  Assert.AreEqual('SQL', TAtlasGuard.DisabledProviders[0]);
  Assert.IsFalse(TAtlasGuard.ProviderDisabled('Server'));
  Assert.IsTrue(TAtlasGuard.DisabledSet = [], 'Features bleiben an');
  Calls := 0;
  Assert.IsFalse(TAtlasGuard.RunProvider('SQL',
    procedure
    begin
      Inc(Calls);
    end));
  Assert.IsTrue(TAtlasGuard.RunProvider('Server',
    procedure
    begin
      Inc(Calls);
    end));
  Assert.AreEqual(1, Calls);
  TAtlasGuard.EnableAll;
  Assert.IsFalse(TAtlasGuard.ProviderDisabled('SQL'));
end;

procedure TAtlasGuardTests.LogLineIsShortSingleLineWithVersion;
var
  Text: string;
begin
  TAtlasGuard.Run(TAtlasFeature.Hover,
    procedure
    begin
      raise EInvalidOpException.Create('Zeile 1' + sLineBreak + 'procedure Geheim;' + sLineBreak +
        StringOfChar('x', 1000));
    end);
  Text := TFile.ReadAllText(TPath.Combine(FFolder, 'atlas.log'), TEncoding.UTF8);
  Assert.Contains(Text, 'Atlas ' + TAtlasPluginVersion.Version);
  Assert.Contains(Text, 'Fehler in Tooltip: EInvalidOpException: Zeile 1 procedure Geheim;');
  Assert.IsFalse(Text.Contains(StringOfChar('x', TAtlasGuard.MaxMessageLength)), 'Meldung gekürzt');
  Assert.AreEqual(1, Integer(Length(Text.Trim.Split([sLineBreak]))), 'eine Zeile ohne Stack-Trace-Anbieter');
  Assert.AreEqual('a b', TAtlasGuard.SafeMessage(' a'#13#10'b '));
end;

procedure TAtlasGuardTests.ErrorLineCarriesStackFromHook;
var
  Text: string;
  Seen: Exception;
begin
  // Ohne E.StackTrace liefert der Mitschnitt des Plugins die Rahmen; er bekommt die behandelte Ausnahme.
  Seen := nil;
  TAtlasGuard.StackOf :=
    function(E: Exception): string
    begin
      Seen := E;
      Result := 'Atlas.IDE.Expert370.bpl+$10 Atlas.IDE.Editor.Minimap.Paint (Minimap.pas:12)' + sLineBreak +
        'rtl370.bpl+$20';
    end;
  TAtlasGuard.Run(TAtlasFeature.Hover,
    procedure
    begin
      raise EInvalidOpException.Create('kaputt');
    end);
  Assert.IsTrue(Seen <> nil, 'Haken aufgerufen');
  Text := TFile.ReadAllText(TPath.Combine(FFolder, 'atlas.log'), TEncoding.UTF8);
  Assert.Contains(Text, '  Stack: Atlas.IDE.Expert370.bpl+$10 Atlas.IDE.Editor.Minimap.Paint (Minimap.pas:12)');
  Assert.Contains(Text, sLineBreak + '  rtl370.bpl+$20');
end;

procedure TAtlasGuardTests.FailingStackHookKeepsErrorLine;
var
  Text: string;
begin
  TAtlasGuard.StackOf :=
    function(E: Exception): string
    begin
      if E <> nil then
        raise EInvalidOpException.Create('Map kaputt');
      Result := '';
    end;
  TAtlasGuard.Run(TAtlasFeature.Hover,
    procedure
    begin
      raise EInvalidOpException.Create('eigentlicher Fehler');
    end);
  Text := TFile.ReadAllText(TPath.Combine(FFolder, 'atlas.log'), TEncoding.UTF8);
  Assert.Contains(Text, 'EInvalidOpException: eigentlicher Fehler');
  Assert.Contains(Text, 'Stack: nicht verfügbar (EInvalidOpException)');
end;

procedure TAtlasGuardTests.RepeatedFailureCountsOncePerWindow;
var
  Fuse: TAtlasFuse;
  Clock: TDateTime;
  Repeated: Boolean;
  Skipped, Index: Integer;
begin
  Clock := EncodeDateTime(2026, 10, 22, 12, 0, 0, 0);
  Fuse := TAtlasFuse.Create(
    function: TDateTime
    begin
      Result := Clock;
    end);
  try
    Assert.IsFalse(Fuse.Failed(TAtlasFeature.Minimap, 'EAccessViolation@1', Repeated, Skipped));
    Assert.IsFalse(Repeated, 'erster Fehler zählt');
    // Dieselbe Stelle für 40 Zeilen desselben Zeichendurchlaufs.
    for Index := 1 to 40 do
    begin
      Clock := IncMilliSecond(Clock, 5);
      Assert.IsFalse(Fuse.Failed(TAtlasFeature.Minimap, 'EAccessViolation@1', Repeated, Skipped));
      Assert.IsTrue(Repeated);
    end;
    // Fester Abstand ab dem gezählten, nicht gleitend: Ein dauernder Fehler zählt einmal je RepeatMs.
    Clock := IncMilliSecond(Clock, TAtlasFuse.RepeatMs);
    Assert.IsFalse(Fuse.Failed(TAtlasFeature.Minimap, 'EAccessViolation@1', Repeated, Skipped));
    Assert.IsFalse(Repeated, 'nach RepeatMs zählt er wieder');
    Assert.AreEqual(40, Skipped, 'die übergangenen Wiederholungen');
    Assert.IsFalse(Fuse.Tripped(TAtlasFeature.Minimap), 'zwei gezählte Fehler');
    // Ein anderer Fehler zählt sofort, hier als dritter, und löst aus.
    Clock := IncMilliSecond(Clock, 5);
    Assert.IsTrue(Fuse.Failed(TAtlasFeature.Minimap, 'EInvalidOp@2', Repeated, Skipped), 'dritter gezählt');
    Assert.IsFalse(Repeated);
    Assert.AreEqual(0, Skipped);
    Assert.IsTrue(Fuse.Tripped(TAtlasFeature.Minimap));
    Assert.IsFalse(Fuse.Tripped(TAtlasFeature.Outline), 'nur die Minimap');
  finally
    Fuse.Free;
  end;
end;

procedure TAtlasGuardTests.RepeatsOfOnePaintPassDoNotTrip;
var
  Index: Integer;
  Text: string;
begin
  for Index := 1 to 30 do
    TAtlasGuard.Run(TAtlasFeature.StickyScroll,
      procedure
      begin
        raise EInvalidOpException.Create('beim Zeichnen');
      end);
  Assert.IsFalse(TAtlasGuard.Disabled(TAtlasFeature.StickyScroll), 'ein Zeichendurchlauf ist ein Fehler');
  Text := TFile.ReadAllText(TPath.Combine(FFolder, 'atlas.log'), TEncoding.UTF8);
  Assert.AreEqual(1, Integer(Length(Text.Trim.Split([sLineBreak]))), 'Wiederholungen nicht einzeln im Protokoll');
  Assert.Contains(Text, 'Fehler in Mitlaufender Kopf: EInvalidOpException: beim Zeichnen');
end;

procedure TAtlasGuardTests.TripReportsFeatureAndMessage;
var
  Index, Calls: Integer;
  Tripped: TAtlasFeature;
  Message: string;
begin
  Calls := 0;
  Tripped := TAtlasFeature.Completion;
  TAtlasGuard.OnTripped :=
    procedure(AFeature: TAtlasFeature; const AMessage: string)
    begin
      Inc(Calls);
      Tripped := AFeature;
      Message := AMessage;
    end;
  try
    for Index := 1 to 3 do
      TAtlasGuard.Run(TAtlasFeature.Outline, RaiserAt(Index));
    Assert.AreEqual(1, Calls, 'einmal beim Auslösen');
    Assert.IsTrue(Tripped = TAtlasFeature.Outline);
    Assert.AreEqual('Fehler 3', Message);
    TAtlasGuard.Run(TAtlasFeature.Outline,
      procedure
      begin
        RaiseAt(1);
      end);
    Assert.AreEqual(1, Calls, 'abgeschaltet: nicht noch einmal');
    Assert.IsFalse(TAtlasGuard.Disabled(TAtlasFeature.Breadcrumbs), 'Brotkrumen laufen weiter');
    Assert.IsFalse(TAtlasGuard.Disabled(TAtlasFeature.StickyScroll), 'Sticky Scroll läuft weiter');
  finally
    TAtlasGuard.OnTripped := nil;
    Message := '';
  end;
end;

procedure TAtlasGuardTests.FeaturesHaveDistinctNames;
var
  Feature: TAtlasFeature;
  Seen: TDictionary<string, TAtlasFeature>;
begin
  Seen := TDictionary<string, TAtlasFeature>.Create;
  try
    for Feature := Low(TAtlasFeature) to High(TAtlasFeature) do
    begin
      Assert.IsTrue(TAtlasGuard.FeatureName(Feature) <> '', 'Name fehlt');
      Assert.IsFalse(Seen.ContainsKey(TAtlasGuard.FeatureName(Feature)), TAtlasGuard.FeatureName(Feature));
      Seen.Add(TAtlasGuard.FeatureName(Feature), Feature);
    end;
  finally
    Seen.Free;
  end;
  Assert.AreEqual('Minimap', TAtlasGuard.FeatureName(TAtlasFeature.Minimap));
  Assert.AreEqual('Gehe zu Definition', TAtlasGuard.FeatureName(TAtlasFeature.GoToDefinition));
  Assert.AreEqual('Editorleiste', TAtlasGuard.FeatureName(TAtlasFeature.EditorToolbar));
  Assert.AreEqual('Schnelle Lesezeichen', TAtlasGuard.FeatureName(TAtlasFeature.QuickBookmarks));
  Assert.AreEqual('Debugger-Hilfen', TAtlasGuard.FeatureName(TAtlasFeature.Debugger));
end;

procedure TAtlasGuardTests.SlowProviderLogsOncePerInterval;
var
  Fuse: TAtlasFuse;
  Clock: TDateTime;
  Skipped: Integer;
  Text: string;
begin
  Clock := EncodeDateTime(2026, 10, 22, 12, 0, 0, 0);
  Fuse := TAtlasFuse.Create(
    function: TDateTime
    begin
      Result := Clock;
    end);
  try
    Assert.IsTrue(Fuse.ProviderSlow('Wörter', Skipped), 'die erste Meldung wird protokolliert');
    Assert.AreEqual(0, Skipped);
    Clock := IncSecond(Clock, 10);
    Assert.IsFalse(Fuse.ProviderSlow('wörter', Skipped), 'Name ohne Groß-/Kleinschreibung');
    Assert.IsFalse(Fuse.ProviderSlow('Wörter', Skipped));
    Assert.IsTrue(Fuse.ProviderSlow('Andere', Skipped), 'je Quelle getrennt');
    Clock := IncSecond(Clock, TAtlasFuse.SlowLogSeconds);
    Assert.IsTrue(Fuse.ProviderSlow('Wörter', Skipped));
    Assert.AreEqual(2, Skipped, 'die übergangenen seit der letzten Zeile');
    Assert.IsFalse(Fuse.ProviderTripped('Wörter'), 'langsam ist kein Fehler');
  finally
    Fuse.Free;
  end;
  TAtlasGuard.ReportProviderSlow('Wörter', 'keine Antwort innerhalb von 200 ms');
  TAtlasGuard.ReportProviderSlow('Wörter', 'keine Antwort innerhalb von 200 ms');
  Text := TFile.ReadAllText(TPath.Combine(FFolder, 'atlas.log'), TEncoding.UTF8);
  Assert.AreEqual(1, Integer(Length(Text.Trim.Split([sLineBreak]))));
  Assert.Contains(Text, 'Quelle Wörter langsam: keine Antwort innerhalb von 200 ms; zählt nicht als Fehler');
  Assert.IsFalse(TAtlasGuard.ProviderDisabled('Wörter'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasGuardTests);

end.
