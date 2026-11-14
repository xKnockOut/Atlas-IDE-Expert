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
    /// <summary>Scheitert das Rotieren, wird trotzdem angehängt und der Grund einmal vermerkt; früher
    /// ging dabei jede Zeile verloren.</summary>
    [Test]
    procedure LogKeepsWritingWhenRotationFails;
    /// <summary>Scheitert das Anhängen, zählt das Protokoll die Zeilen, meldet den ersten Fehler über OnError und
    /// vermerkt die Lücke beim nächsten Gelingen.</summary>
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
/// innerhalb von TAtlasFuse.cRepeatMs nur einmal.</summary>
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
  // Diese Tests prüfen Inhalte der Zeilen; anonym schreibt das Protokoll sie als text#N (#1478, eigene Tests in
  // Atlas.Core.Diagnostics.LogRedaction.Tests).
  TAtlasGuard.SetLogNames(True);
end;

procedure TAtlasGuardTests.TearDown;
begin
  TAtlasGuard.Fuse.ResetAll;
  TAtlasGuard.SetLogNames(False);
  TAtlasGuard.OnWarning := nil;
  TAtlasGuard.StackOf := nil;
  TAtlasGuard.RotatingLog.Folder := FOldFolder;
  if TDirectory.Exists(FFolder) then
  begin
    TDirectory.Delete(FFolder, True);
  end;
  FFolder := '';
  FOldFolder := '';
end;

procedure TAtlasGuardTests.RunSwallowsExceptions;
var
  mRan: Boolean;
begin
  Assert.IsFalse(TAtlasGuard.Run(TAtlasFeature.Hover,
    procedure
    begin
      raise EInvalidOpException.Create('kaputt');
    end));
  mRan := False;
  Assert.IsTrue(TAtlasGuard.Run(TAtlasFeature.Hover,
    procedure
    begin
      mRan := True;
    end));
  Assert.IsTrue(mRan);
  Assert.Contains(TFile.ReadAllText(TPath.Combine(FFolder, 'atlas.log'), TEncoding.UTF8), 'EInvalidOpException: kaputt');
end;

procedure TAtlasGuardTests.FuseTripsAfterThreeFailuresWithinFiveMinutes;
var
  mFuse: TAtlasFuse;
  mClock: TDateTime;
begin
  mClock := EncodeDateTime(2026, 10, 11, 12, 0, 0, 0);
  mFuse := TAtlasFuse.Create(
    function: TDateTime
    begin
      Result := mClock;
    end);
  try
    Assert.IsFalse(mFuse.Failed(TAtlasFeature.Completion));
    mClock := IncMinute(mClock, 2);
    Assert.IsFalse(mFuse.Failed(TAtlasFeature.Completion));
    mClock := IncMinute(mClock, 2);
    Assert.IsTrue(mFuse.Failed(TAtlasFeature.Completion), 'dritter Fehler in 4 Minuten löst aus');
    Assert.IsTrue(mFuse.Tripped(TAtlasFeature.Completion));
    Assert.IsFalse(mFuse.Tripped(TAtlasFeature.Hover), 'nur das betroffene Feature');
    mFuse.Reset(TAtlasFeature.Completion);
    Assert.IsFalse(mFuse.Tripped(TAtlasFeature.Completion));
  finally
    mFuse.Free;
  end;
end;

procedure TAtlasGuardTests.OldFailuresDoNotCount;
var
  mFuse: TAtlasFuse;
  mClock: TDateTime;
begin
  mClock := EncodeDateTime(2026, 10, 11, 12, 0, 0, 0);
  mFuse := TAtlasFuse.Create(
    function: TDateTime
    begin
      Result := mClock;
    end);
  try
    mFuse.Failed(TAtlasFeature.Pairs);
    mFuse.Failed(TAtlasFeature.Pairs);
    mClock := IncMinute(mClock, 6);
    Assert.IsFalse(mFuse.Failed(TAtlasFeature.Pairs), 'ältere Fehler liegen außerhalb der 5 Minuten');
  finally
    mFuse.Free;
  end;
end;

procedure TAtlasGuardTests.TrippedFeatureIsSkippedOthersRun;
var
  mIndex, mCalls: Integer;
  mWarning: string;
begin
  TAtlasGuard.OnWarning :=
    procedure(const AText: string)
    begin
      mWarning := AText;
    end;
  for mIndex := 1 to 3 do
  begin
    TAtlasGuard.Run(TAtlasFeature.Problems, RaiserAt(mIndex));
  end;
  Assert.IsTrue(TAtlasGuard.Disabled(TAtlasFeature.Problems));
  Assert.Contains(mWarning, 'Probleme');
  mCalls := 0;
  TAtlasGuard.Run(TAtlasFeature.Problems,
    procedure
    begin
      Inc(mCalls);
    end);
  Assert.AreEqual(0, mCalls, 'abgeschaltet: läuft nicht mehr');
  TAtlasGuard.Run(TAtlasFeature.Hover,
    procedure
    begin
      Inc(mCalls);
    end);
  Assert.AreEqual(1, mCalls, 'andere Features laufen weiter');
  TAtlasGuard.Enable(TAtlasFeature.Problems);
  Assert.IsFalse(TAtlasGuard.Disabled(TAtlasFeature.Problems));
end;

procedure TAtlasGuardTests.BreadcrumbsHaveTheirOwnFuse;
var
  mIndex, mCalls: Integer;
begin
  Assert.AreEqual('Brotkrumenleiste', TAtlasGuard.FeatureName(TAtlasFeature.Breadcrumbs));
  for mIndex := 1 to 3 do
  begin
    TAtlasGuard.Run(TAtlasFeature.EditorCommands, RaiserAt(mIndex));
  end;
  Assert.IsTrue(TAtlasGuard.Disabled(TAtlasFeature.EditorCommands));
  Assert.IsFalse(TAtlasGuard.Disabled(TAtlasFeature.Breadcrumbs), 'Editorbefehle reißen die Leiste nicht mit');
  mCalls := 0;
  TAtlasGuard.Run(TAtlasFeature.Breadcrumbs,
    procedure
    begin
      Inc(mCalls);
    end);
  Assert.AreEqual(1, mCalls);
  for mIndex := 1 to 3 do
  begin
    TAtlasGuard.Run(TAtlasFeature.Breadcrumbs, RaiserAt(mIndex));
  end;
  Assert.IsTrue(TAtlasGuard.Disabled(TAtlasFeature.Breadcrumbs));
  TAtlasGuard.EnableAll;
  Assert.IsFalse(TAtlasGuard.Disabled(TAtlasFeature.Breadcrumbs), 'Abgeschaltete Funktionen einschalten');
end;

procedure TAtlasGuardTests.LogRotatesAtLimit;
var
  mLog: TAtlasRotatingLog;
  mIndex: Integer;
begin
  mLog := TAtlasRotatingLog.Create(FFolder, 200, 3);
  try
    for mIndex := 1 to 40 do
    begin
      mLog.Add(StringOfChar('x', 40));
    end;
    Assert.IsTrue(TFile.Exists(TPath.Combine(FFolder, 'atlas.1.log')));
    Assert.IsTrue(TFile.Exists(TPath.Combine(FFolder, 'atlas.2.log')));
    Assert.IsFalse(TFile.Exists(TPath.Combine(FFolder, 'atlas.3.log')), 'höchstens 3 Dateien');
  finally
    mLog.Free;
  end;
end;

/// <summary>Wie oft ASub in AText vorkommt.</summary>
function Occurrences(const AText, ASub: string): Integer;
var
  mOffset: Integer;
begin
  Result := 0;
  mOffset := Pos(ASub, AText);
  while mOffset > 0 do
  begin
    Inc(Result);
    mOffset := Pos(ASub, AText, mOffset + Length(ASub));
  end;
end;

procedure TAtlasGuardTests.LogKeepsWritingWhenRotationFails;
var
  mLog: TAtlasRotatingLog;
  mIndex: Integer;
  mText: string;
begin
  mLog := TAtlasRotatingLog.Create(FFolder, 100, 3);
  try
    ForceDirectories(FFolder);
    // atlas.1.log lässt sich nicht nach atlas.2.log verschieben, dort liegt ein Ordner.
    TFile.WriteAllText(TPath.Combine(FFolder, 'atlas.1.log'), 'alt');
    TDirectory.CreateDirectory(TPath.Combine(FFolder, 'atlas.2.log'));
    for mIndex := 1 to 10 do
    begin
      mLog.Add('Zeile ' + IntToStr(mIndex));
    end;
    mText := TFile.ReadAllText(mLog.FileName, TEncoding.UTF8);
    Assert.Contains(mText, 'Zeile 10', 'trotz gescheitertem Rotieren angehängt');
    Assert.AreEqual(1, Occurrences(mText, 'Protokoll: Rotieren gescheitert'), 'Grund nur einmal');
    Assert.DoesNotContain(mText, FFolder, 'ohne Ordner (Benutzername)');
    Assert.AreEqual(0, mLog.Lost, 'keine Zeile verloren');
  finally
    mLog.Free;
  end;
end;

procedure TAtlasGuardTests.LogCountsLostLinesAndReportsTheGap;
var
  mLog: TAtlasRotatingLog;
  mReports: TArray<string>;
  mBlocker, mText: string;
begin
  mReports := nil;
  mLog := TAtlasRotatingLog.Create(FFolder);
  try
    mLog.OnError :=
      procedure(const AMessage: string)
      begin
        mReports := mReports + [AMessage];
      end;
    // Ein Ordner namens atlas.log: Anhängen scheitert.
    mBlocker := TPath.Combine(FFolder, 'atlas.log');
    TDirectory.CreateDirectory(mBlocker);
    mLog.Add('eins');
    mLog.Add('zwei');
    mLog.Add('drei');
    Assert.AreEqual(3, mLog.Lost);
    Assert.AreEqual(1, Integer(Length(mReports)), 'nur der erste Fehler wird gemeldet');
    Assert.AreNotEqual('', mReports[0], 'mit Grund');
    Assert.AreEqual(mReports[0], mLog.LastError);
    TDirectory.Delete(mBlocker);
    mLog.Add('vier');
    Assert.AreEqual(2, Integer(Length(mReports)));
    Assert.AreEqual('', mReports[1], 'wieder in Ordnung');
    Assert.AreEqual('', mLog.LastError);
    Assert.AreEqual(3, mLog.Lost, 'die Summe bleibt');
    mText := TFile.ReadAllText(mLog.FileName, TEncoding.UTF8);
    Assert.Contains(mText, 'Protokoll: 3 Zeilen nicht geschrieben');
    Assert.Contains(mText, 'vier');
    Assert.DoesNotContain(mText, 'eins');
    Assert.DoesNotContain(mText, FFolder, 'ohne Ordner (Benutzername)');
  finally
    mLog.Free;
  end;
end;

procedure TAtlasGuardTests.LogMutexNameDependsOnlyOnTheFolder;
var
  mName: string;
begin
  mName := TAtlasRotatingLog.MutexName('C:\Users\Anna\AppData\Local\Atlas\Logs');
  Assert.AreEqual(mName, TAtlasRotatingLog.MutexName(
    IncludeTrailingPathDelimiter('c:\users\anna\appdata\local\atlas\logs')), 'Schreibweise und Schlussstrich egal');
  Assert.AreNotEqual(mName, TAtlasRotatingLog.MutexName('C:\Users\Anna\AppData\Local\Temp\AtlasTests\Logs'));
  Assert.IsTrue(mName.StartsWith('Local\Atlas.Log.'), mName);
  Assert.AreEqual(0, Pos('\', Copy(mName, 7, MaxInt)), 'kein Backslash nach dem Namensraum');
end;

procedure TAtlasGuardTests.ProviderFuseTripsOnlyThatProvider;
var
  mIndex, mCalls: Integer;
  mWarning: string;
begin
  TAtlasGuard.OnWarning :=
    procedure(const AText: string)
    begin
      mWarning := AText;
    end;
  for mIndex := 1 to 2 do
  begin
    TAtlasGuard.ReportProvider('SQL', 'kaputt');
  end;
  Assert.IsFalse(TAtlasGuard.ProviderDisabled('SQL'));
  Assert.AreEqual('', mWarning, 'noch keine Warnung');
  TAtlasGuard.ReportProvider('SQL', 'kaputt');
  Assert.IsTrue(TAtlasGuard.ProviderDisabled('SQL'));
  Assert.IsTrue(TAtlasGuard.ProviderDisabled('sql'));
  Assert.Contains(mWarning, '„SQL“');
  Assert.Contains(mWarning, 'Tools > Optionen > Drittanbieter > Atlas');
  Assert.AreEqual(1, Integer(Length(TAtlasGuard.DisabledProviders)));
  Assert.AreEqual('SQL', TAtlasGuard.DisabledProviders[0]);
  Assert.IsFalse(TAtlasGuard.ProviderDisabled('Server'));
  Assert.AreEqual<TAtlasFeatures>([], TAtlasGuard.DisabledSet, 'Features bleiben an');
  mCalls := 0;
  Assert.IsFalse(TAtlasGuard.RunProvider('SQL',
    procedure
    begin
      Inc(mCalls);
    end));
  Assert.IsTrue(TAtlasGuard.RunProvider('Server',
    procedure
    begin
      Inc(mCalls);
    end));
  Assert.AreEqual(1, mCalls);
  TAtlasGuard.EnableAll;
  Assert.IsFalse(TAtlasGuard.ProviderDisabled('SQL'));
end;

procedure TAtlasGuardTests.LogLineIsShortSingleLineWithVersion;
var
  mText: string;
begin
  TAtlasGuard.Run(TAtlasFeature.Hover,
    procedure
    begin
      raise EInvalidOpException.Create('Zeile 1' + sLineBreak + 'procedure Geheim;' + sLineBreak +
        StringOfChar('x', 1000));
    end);
  mText := TFile.ReadAllText(TPath.Combine(FFolder, 'atlas.log'), TEncoding.UTF8);
  Assert.Contains(mText, 'Atlas ' + TAtlasPluginVersion.cVersion);
  Assert.Contains(mText, 'Fehler in Tooltip: EInvalidOpException: Zeile 1 procedure Geheim;');
  Assert.IsFalse(mText.Contains(StringOfChar('x', TAtlasGuard.cMaxMessageLength)), 'Meldung gekürzt');
  Assert.AreEqual(1, Integer(Length(mText.Trim.Split([sLineBreak]))), 'eine Zeile ohne Stack-Trace-Anbieter');
  Assert.AreEqual('a b', TAtlasGuard.SafeMessage(' a'#13#10'b '));
end;

procedure TAtlasGuardTests.ErrorLineCarriesStackFromHook;
var
  mText: string;
  mSeen: Exception;
begin
  // Ohne E.StackTrace liefert der Mitschnitt des Plugins die Rahmen; er bekommt die behandelte Ausnahme.
  mSeen := nil;
  TAtlasGuard.StackOf :=
    function(AE: Exception): string
    begin
      mSeen := AE;
      Result := 'Atlas.IDE.Expert370.bpl+$10 Atlas.IDE.Editor.Minimap.Paint (Minimap.pas:12)' + sLineBreak +
        'rtl370.bpl+$20';
    end;
  TAtlasGuard.Run(TAtlasFeature.Hover,
    procedure
    begin
      raise EInvalidOpException.Create('kaputt');
    end);
  Assert.IsNotNull(mSeen, 'Haken aufgerufen');
  mText := TFile.ReadAllText(TPath.Combine(FFolder, 'atlas.log'), TEncoding.UTF8);
  Assert.Contains(mText, '  Stack: Atlas.IDE.Expert370.bpl+$10 Atlas.IDE.Editor.Minimap.Paint (Minimap.pas:12)');
  Assert.Contains(mText, sLineBreak + '  rtl370.bpl+$20');
end;

procedure TAtlasGuardTests.FailingStackHookKeepsErrorLine;
var
  mText: string;
begin
  TAtlasGuard.StackOf :=
    function(AE: Exception): string
    begin
      if AE <> nil then
      begin
        raise EInvalidOpException.Create('Map kaputt');
      end;
      Result := '';
    end;
  TAtlasGuard.Run(TAtlasFeature.Hover,
    procedure
    begin
      raise EInvalidOpException.Create('eigentlicher Fehler');
    end);
  mText := TFile.ReadAllText(TPath.Combine(FFolder, 'atlas.log'), TEncoding.UTF8);
  Assert.Contains(mText, 'EInvalidOpException: eigentlicher Fehler');
  Assert.Contains(mText, 'Stack: nicht verfügbar (EInvalidOpException)');
end;

procedure TAtlasGuardTests.RepeatedFailureCountsOncePerWindow;
var
  mFuse: TAtlasFuse;
  mClock: TDateTime;
  mRepeated: Boolean;
  mSkipped, mIndex: Integer;
begin
  mClock := EncodeDateTime(2026, 10, 22, 12, 0, 0, 0);
  mFuse := TAtlasFuse.Create(
    function: TDateTime
    begin
      Result := mClock;
    end);
  try
    Assert.IsFalse(mFuse.Failed(TAtlasFeature.Minimap, 'EAccessViolation@1', mRepeated, mSkipped));
    Assert.IsFalse(mRepeated, 'erster Fehler zählt');
    // Dieselbe Stelle für 40 Zeilen desselben Zeichendurchlaufs.
    for mIndex := 1 to 40 do
    begin
      mClock := IncMilliSecond(mClock, 5);
      Assert.IsFalse(mFuse.Failed(TAtlasFeature.Minimap, 'EAccessViolation@1', mRepeated, mSkipped));
      Assert.IsTrue(mRepeated);
    end;
    // Fester Abstand ab dem gezählten, nicht gleitend: Ein dauernder Fehler zählt einmal je RepeatMs.
    mClock := IncMilliSecond(mClock, TAtlasFuse.cRepeatMs);
    Assert.IsFalse(mFuse.Failed(TAtlasFeature.Minimap, 'EAccessViolation@1', mRepeated, mSkipped));
    Assert.IsFalse(mRepeated, 'nach RepeatMs zählt er wieder');
    Assert.AreEqual(40, mSkipped, 'die übergangenen Wiederholungen');
    Assert.IsFalse(mFuse.Tripped(TAtlasFeature.Minimap), 'zwei gezählte Fehler');
    // Ein anderer Fehler zählt sofort, hier als dritter, und löst aus.
    mClock := IncMilliSecond(mClock, 5);
    Assert.IsTrue(mFuse.Failed(TAtlasFeature.Minimap, 'EInvalidOp@2', mRepeated, mSkipped), 'dritter gezählt');
    Assert.IsFalse(mRepeated);
    Assert.AreEqual(0, mSkipped);
    Assert.IsTrue(mFuse.Tripped(TAtlasFeature.Minimap));
    Assert.IsFalse(mFuse.Tripped(TAtlasFeature.Outline), 'nur die Minimap');
  finally
    mFuse.Free;
  end;
end;

procedure TAtlasGuardTests.RepeatsOfOnePaintPassDoNotTrip;
var
  mIndex: Integer;
  mText: string;
begin
  for mIndex := 1 to 30 do
  begin
    TAtlasGuard.Run(TAtlasFeature.StickyScroll,
      procedure
      begin
        raise EInvalidOpException.Create('beim Zeichnen');
      end);
  end;
  Assert.IsFalse(TAtlasGuard.Disabled(TAtlasFeature.StickyScroll), 'ein Zeichendurchlauf ist ein Fehler');
  mText := TFile.ReadAllText(TPath.Combine(FFolder, 'atlas.log'), TEncoding.UTF8);
  Assert.AreEqual(1, Integer(Length(mText.Trim.Split([sLineBreak]))), 'Wiederholungen nicht einzeln im Protokoll');
  Assert.Contains(mText, 'Fehler in Mitlaufender Kopf: EInvalidOpException: beim Zeichnen');
end;

procedure TAtlasGuardTests.TripReportsFeatureAndMessage;
var
  mIndex, mCalls: Integer;
  mTripped: TAtlasFeature;
  mMessage: string;
begin
  mCalls := 0;
  mTripped := TAtlasFeature.Completion;
  TAtlasGuard.OnTripped :=
    procedure(AFeature: TAtlasFeature; const AMessage: string)
    begin
      Inc(mCalls);
      mTripped := AFeature;
      mMessage := AMessage;
    end;
  try
    for mIndex := 1 to 3 do
    begin
      TAtlasGuard.Run(TAtlasFeature.Outline, RaiserAt(mIndex));
    end;
    Assert.AreEqual(1, mCalls, 'einmal beim Auslösen');
    Assert.AreEqual<TAtlasFeature>(TAtlasFeature.Outline, mTripped);
    Assert.AreEqual('Fehler 3', mMessage);
    TAtlasGuard.Run(TAtlasFeature.Outline,
      procedure
      begin
        RaiseAt(1);
      end);
    Assert.AreEqual(1, mCalls, 'abgeschaltet: nicht noch einmal');
    Assert.IsFalse(TAtlasGuard.Disabled(TAtlasFeature.Breadcrumbs), 'Brotkrumen laufen weiter');
    Assert.IsFalse(TAtlasGuard.Disabled(TAtlasFeature.StickyScroll), 'Sticky Scroll läuft weiter');
  finally
    TAtlasGuard.OnTripped := nil;
    mMessage := '';
  end;
end;

procedure TAtlasGuardTests.FeaturesHaveDistinctNames;
var
  mFeature: TAtlasFeature;
  mSeen: TDictionary<string, TAtlasFeature>;
begin
  mSeen := TDictionary<string, TAtlasFeature>.Create;
  try
    for mFeature := Low(TAtlasFeature) to High(TAtlasFeature) do
    begin
      Assert.AreNotEqual('', TAtlasGuard.FeatureName(mFeature), 'Name fehlt');
      Assert.IsFalse(mSeen.ContainsKey(TAtlasGuard.FeatureName(mFeature)), TAtlasGuard.FeatureName(mFeature));
      mSeen.Add(TAtlasGuard.FeatureName(mFeature), mFeature);
    end;
  finally
    mSeen.Free;
  end;
  Assert.AreEqual('Minimap', TAtlasGuard.FeatureName(TAtlasFeature.Minimap));
  Assert.AreEqual('Gehe zu Definition', TAtlasGuard.FeatureName(TAtlasFeature.GoToDefinition));
  Assert.AreEqual('Editorleiste', TAtlasGuard.FeatureName(TAtlasFeature.EditorToolbar));
  Assert.AreEqual('Schnelle Lesezeichen', TAtlasGuard.FeatureName(TAtlasFeature.QuickBookmarks));
  Assert.AreEqual('Atlas-Statusleiste', TAtlasGuard.FeatureName(TAtlasFeature.StatusBar));
  Assert.AreEqual('Architekturübersicht', TAtlasGuard.FeatureName(TAtlasFeature.Architecture));
  Assert.AreEqual('Unit-Beziehungen', TAtlasGuard.FeatureName(TAtlasFeature.UnitRelations));
  Assert.AreEqual('Weg zwischen Symbolen', TAtlasGuard.FeatureName(TAtlasFeature.SymbolPath));
  Assert.AreEqual('Projektaufgaben', TAtlasGuard.FeatureName(TAtlasFeature.Tasks));
  Assert.AreEqual('Debuggen', TAtlasGuard.FeatureName(TAtlasFeature.Debugger));
  Assert.AreEqual('Austrittspunkte', TAtlasGuard.FeatureName(TAtlasFeature.ExitPoints));
  Assert.AreEqual('Neu zugewiesene Variablen', TAtlasGuard.FeatureName(TAtlasFeature.Reassigned));
  Assert.AreEqual('Typ des Ausdrucks', TAtlasGuard.FeatureName(TAtlasFeature.ExpressionType));
  Assert.AreEqual('Methodenreihenfolge', TAtlasGuard.FeatureName(TAtlasFeature.MethodPlacement));
  Assert.AreEqual('Regionen falten', TAtlasGuard.FeatureName(TAtlasFeature.RegionFolds));
  Assert.AreEqual('Einrückung beim Tippen', TAtlasGuard.FeatureName(TAtlasFeature.SmartIndent));
  Assert.AreEqual('Gelernte Vorschläge', TAtlasGuard.FeatureName(TAtlasFeature.LearnedSuggestions));
  Assert.AreEqual('Issue-Kennungen', TAtlasGuard.FeatureName(TAtlasFeature.IssueLinks));
  Assert.AreEqual('Issues in der Zeilenhistorie', TAtlasGuard.FeatureName(TAtlasFeature.BlameIssues));
  Assert.AreEqual('Code-Abfragen', TAtlasGuard.FeatureName(TAtlasFeature.Query));
  Assert.AreEqual('Hotspots', TAtlasGuard.FeatureName(TAtlasFeature.Hotspots));
  Assert.AreEqual('Designer-Leiste', TAtlasGuard.FeatureName(TAtlasFeature.DesignerBar));
end;

procedure TAtlasGuardTests.SlowProviderLogsOncePerInterval;
var
  mFuse: TAtlasFuse;
  mClock: TDateTime;
  mSkipped: Integer;
  mText: string;
begin
  mClock := EncodeDateTime(2026, 10, 22, 12, 0, 0, 0);
  mFuse := TAtlasFuse.Create(
    function: TDateTime
    begin
      Result := mClock;
    end);
  try
    Assert.IsTrue(mFuse.ProviderSlow('Wörter', mSkipped), 'die erste Meldung wird protokolliert');
    Assert.AreEqual(0, mSkipped);
    mClock := IncSecond(mClock, 10);
    Assert.IsFalse(mFuse.ProviderSlow('wörter', mSkipped), 'Name ohne Groß-/Kleinschreibung');
    Assert.IsFalse(mFuse.ProviderSlow('Wörter', mSkipped));
    Assert.IsTrue(mFuse.ProviderSlow('Andere', mSkipped), 'je Quelle getrennt');
    mClock := IncSecond(mClock, TAtlasFuse.cSlowLogSeconds);
    Assert.IsTrue(mFuse.ProviderSlow('Wörter', mSkipped));
    Assert.AreEqual(2, mSkipped, 'die übergangenen seit der letzten Zeile');
    Assert.IsFalse(mFuse.ProviderTripped('Wörter'), 'langsam ist kein Fehler');
  finally
    mFuse.Free;
  end;
  TAtlasGuard.ReportProviderSlow('Wörter', 'keine Antwort innerhalb von 200 ms');
  TAtlasGuard.ReportProviderSlow('Wörter', 'keine Antwort innerhalb von 200 ms');
  mText := TFile.ReadAllText(TPath.Combine(FFolder, 'atlas.log'), TEncoding.UTF8);
  Assert.AreEqual(1, Integer(Length(mText.Trim.Split([sLineBreak]))));
  Assert.Contains(mText, 'Quelle Wörter langsam: keine Antwort innerhalb von 200 ms; zählt nicht als Fehler');
  Assert.IsFalse(TAtlasGuard.ProviderDisabled('Wörter'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasGuardTests);

end.
