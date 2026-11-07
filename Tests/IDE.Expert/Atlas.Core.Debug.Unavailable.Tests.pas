unit Atlas.Core.Debug.Unavailable.Tests;

// „kein Zugriff auf Wert“ (#840): Erkennen der Fehlertexte (deutsch, englisch,
// Platzhalter, Ergänzungen), Reihenfolge der Ursachen mit geprüften Punkten
// und Korrekturen, Startkonfiguration vor dem Projektstand des Servers,
// Lebensdauer aus der Antwort des Servers, Vorschau der Einfügungen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasDebugUnavailableTests = class
  public
    [Test]
    procedure RecognizesKnownTextsInBothLanguages;
    [Test]
    procedure PatternsWithWildcardsAndUserFile;
    [Test]
    procedure RootNameOfExpression;
    [Test]
    procedure ReleaseStartComesFirst;
    [Test]
    procedure DirectiveSwitchesBeforeOptimization;
    [Test]
    procedure LaunchValueWinsOverProjectValue;
    [Test]
    procedure OptimizationAddsLifetimeAndFixes;
    [Test]
    procedure LifetimeInlineAndLibraryInOrder;
    [Test]
    procedure UnknownListsAllChecks;
    [Test]
    procedure ReadsServerAnswer;
    [Test]
    procedure PreviewShowsInsertedLines;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Debug.Unavailable;

function DebugLaunch: TAtlasUnavailableLaunch;
begin
  Result := Default(TAtlasUnavailableLaunch);
  Result.Known := True;
  Result.Configuration := 'Debug';
  Result.DebugInfo := 'true';
  Result.LocalSymbols := 'true';
  Result.Optimization := 'false';
  Result.DebugDcus := 'false';
end;

function Switch(const AValue: string; ASource: TAtlasSwitchSource): TAtlasUnavailableSwitch;
begin
  Result := Default(TAtlasUnavailableSwitch);
  Result.Known := True;
  Result.Value := AValue;
  Result.Source := ASource;
  Result.Line := -1;
  if ASource = TAtlasSwitchSource.Directive then
  begin
    Result.OriginText := '{$O' + AValue + '}';
    Result.FileName := 'C:\P\Kunden.pas';
    Result.Line := 11;
  end;
end;

/// <summary>Lokale Variable im Debug-Start ohne besondere Schalter.</summary>
function LocalFacts: TAtlasUnavailableFacts;
begin
  Result := TAtlasUnavailableFacts.Create(DebugLaunch, False);
  Result.Server := True;
  Result.Local := True;
  Result.Lifetime := TAtlasValueLifetime.Within;
  Result.DebugInfo := Switch('+', TAtlasSwitchSource.Project);
  Result.LocalSymbols := Switch('+', TAtlasSwitchSource.Project);
  Result.Optimization := Switch('-', TAtlasSwitchSource.Project);
end;

function Edit(ALine: Integer; const AText: string): TLspWorkspaceEdit;
var
  mJson: TJSONObject;
begin
  mJson := TJSONObject.ParseJSONValue(Format('{"changes":{"file:///C:/P/Kunden.pas":[{"range":{"start":' +
    '{"line":%d,"character":0},"end":{"line":%d,"character":0}},"newText":"%s\r\n"}]}}', [ALine, ALine, AText]))
    as TJSONObject;
  try
    Result := TLspWorkspaceEdit.FromJson(mJson);
  finally
    mJson.Free;
  end;
end;

{ TAtlasDebugUnavailableTests }

procedure TAtlasDebugUnavailableTests.RecognizesKnownTextsInBothLanguages;
begin
  Assert.IsTrue(TAtlasDebugUnavailable.IsUnavailable('Inaccessible value', nil));
  Assert.IsTrue(TAtlasDebugUnavailable.IsUnavailable(
    'E2171 Variable ''Summe'' inaccessible here due to optimization', nil));
  Assert.IsTrue(TAtlasDebugUnavailable.IsUnavailable(
    'E2171 Auf die Variable ''Summe'' kann hier wegen der Optimierung nicht zugegriffen werden', nil));
  Assert.IsTrue(TAtlasDebugUnavailable.IsUnavailable('<optimized out>', nil), 'LLDB');
  Assert.IsTrue(TAtlasDebugUnavailable.IsUnavailable('Kein Zugriff auf Wert', nil));
  Assert.IsFalse(TAtlasDebugUnavailable.IsUnavailable('Zugriffsverletzung bei Adresse 0040A1B2', nil),
    'andere Fehler bleiben ausgeblendet');
  Assert.IsFalse(TAtlasDebugUnavailable.IsUnavailable('', nil));
end;

procedure TAtlasDebugUnavailableTests.PatternsWithWildcardsAndUserFile;
var
  mPatterns: TArray<string>;
begin
  Assert.IsTrue(TAtlasDebugUnavailable.MatchesPattern('Wert X nicht lesbar', 'wert * nicht lesbar'));
  Assert.IsFalse(TAtlasDebugUnavailable.MatchesPattern('nicht lesbar: Wert', 'wert * nicht lesbar'),
    'Teile in der Reihenfolge des Musters');
  mPatterns := TAtlasDebugUnavailable.ParsePatterns('# eigene Texte' + sLineBreak + sLineBreak +
    '  Wert * nicht lesbar  # Firmen-Debugger' + sLineBreak + 'ausgelagert');
  Assert.AreEqual(2, Integer(Length(mPatterns)));
  Assert.AreEqual('Wert * nicht lesbar', mPatterns[0]);
  Assert.IsTrue(TAtlasDebugUnavailable.IsUnavailable('Wert Summe nicht lesbar', mPatterns));
  Assert.IsFalse(TAtlasDebugUnavailable.IsUnavailable('Wert Summe nicht lesbar', nil));
end;

procedure TAtlasDebugUnavailableTests.RootNameOfExpression;
begin
  Assert.AreEqual('Self', TAtlasDebugUnavailable.RootName('Self.FList.Count'));
  Assert.AreEqual('Kunden', TAtlasDebugUnavailable.RootName('Kunden[I].Name'));
  Assert.AreEqual('Typ', TAtlasDebugUnavailable.RootName('&Typ'));
  Assert.AreEqual('P', TAtlasDebugUnavailable.RootName('P^.Wert'));
end;

procedure TAtlasDebugUnavailableTests.ReleaseStartComesFirst;
var
  mFacts: TAtlasUnavailableFacts;
  mExplanation: TAtlasUnavailableExplanation;
begin
  mFacts := LocalFacts;
  mFacts.Launch.Configuration := 'Release';
  mFacts.Launch.DebugInfo := 'false';
  mFacts.Launch.Optimization := 'true';
  mFacts.Optimization := Switch('+', TAtlasSwitchSource.Directive);
  mExplanation := TAtlasDebugUnavailable.Explain(mFacts);
  Assert.AreEqual(Ord(TAtlasUnavailableCause.ReleaseBuild), Ord(mExplanation.Cause));
  Assert.AreEqual('Release', mExplanation.Configuration);
  Assert.IsTrue(mExplanation.HasFix(TAtlasUnavailableFix.RestartWithDebug));
  Assert.AreEqual(1, Integer(Length(mExplanation.Checked)), 'nur die Konfiguration geprüft');
  mFacts.Launch.DebugInfo := '0';
  Assert.AreEqual(Ord(TAtlasUnavailableCause.ReleaseBuild), Ord(TAtlasDebugUnavailable.Explain(mFacts).Cause),
    '0 heißt keine Debug-Informationen');
end;

procedure TAtlasDebugUnavailableTests.DirectiveSwitchesBeforeOptimization;
var
  mFacts: TAtlasUnavailableFacts;
  mExplanation: TAtlasUnavailableExplanation;
begin
  mFacts := LocalFacts;
  mFacts.DebugInfo := Switch('-', TAtlasSwitchSource.Directive);
  mFacts.Optimization := Switch('+', TAtlasSwitchSource.Directive);
  mExplanation := TAtlasDebugUnavailable.Explain(mFacts);
  Assert.AreEqual(Ord(TAtlasUnavailableCause.NoDebugInfo), Ord(mExplanation.Cause));
  Assert.AreEqual(11, mExplanation.Switch.Line);
  Assert.IsTrue(mExplanation.HasFix(TAtlasUnavailableFix.ShowDirective));
  mFacts := LocalFacts;
  mFacts.LocalSymbols := Switch('-', TAtlasSwitchSource.Directive);
  Assert.AreEqual(Ord(TAtlasUnavailableCause.NoLocalSymbols), Ord(TAtlasDebugUnavailable.Explain(mFacts).Cause));
  mFacts.Local := False;
  Assert.AreEqual(Ord(TAtlasUnavailableCause.Unknown), Ord(TAtlasDebugUnavailable.Explain(mFacts).Cause),
    '$L- betrifft nur lokale Namen');
end;

procedure TAtlasDebugUnavailableTests.LaunchValueWinsOverProjectValue;
var
  mFacts: TAtlasUnavailableFacts;
begin
  // Der Server kennt die aktive Konfiguration (O+), gestartet wurde aber Debug (O-).
  mFacts := LocalFacts;
  mFacts.Optimization := Switch('+', TAtlasSwitchSource.Project);
  Assert.AreEqual(Ord(TAtlasUnavailableCause.Unknown), Ord(TAtlasDebugUnavailable.Explain(mFacts).Cause));
  // Ohne bekannten Start (angehängt) gilt der Stand des Servers.
  mFacts.Launch.Known := False;
  Assert.AreEqual(Ord(TAtlasUnavailableCause.Optimization), Ord(TAtlasDebugUnavailable.Explain(mFacts).Cause));
  // Eine Direktive gilt immer.
  mFacts := LocalFacts;
  mFacts.Optimization := Switch('+', TAtlasSwitchSource.Directive);
  Assert.AreEqual(Ord(TAtlasUnavailableCause.Optimization), Ord(TAtlasDebugUnavailable.Explain(mFacts).Cause));
end;

procedure TAtlasDebugUnavailableTests.OptimizationAddsLifetimeAndFixes;
var
  mFacts: TAtlasUnavailableFacts;
  mExplanation: TAtlasUnavailableExplanation;
begin
  mFacts := LocalFacts;
  mFacts.Launch.Optimization := 'true';
  mFacts.Lifetime := TAtlasValueLifetime.After;
  mFacts.LastUse := 41;
  mFacts.RoutineEdit := Edit(30, '{$OPTIMIZATION OFF}');
  mFacts.UnitEdit := Edit(2, '{$O-}');
  mExplanation := TAtlasDebugUnavailable.Explain(mFacts);
  Assert.AreEqual(Ord(TAtlasUnavailableCause.Optimization), Ord(mExplanation.Cause));
  Assert.AreEqual(Ord(TAtlasValueLifetime.After), Ord(mExplanation.Lifetime), 'Hinweis zur Lebensdauer');
  Assert.IsTrue(mExplanation.HasFix(TAtlasUnavailableFix.RoutineOptimization));
  Assert.IsTrue(mExplanation.HasFix(TAtlasUnavailableFix.UnitOptimization));
  Assert.IsFalse(mExplanation.HasFix(TAtlasUnavailableFix.ShowDirective), 'O+ aus der .dproj');
  Assert.AreEqual(3, Integer(Length(mExplanation.Checked)));
  // Felder liegen nicht in Registern.
  mFacts.Local := False;
  Assert.AreEqual(Ord(TAtlasUnavailableCause.Unknown), Ord(TAtlasDebugUnavailable.Explain(mFacts).Cause));
end;

procedure TAtlasDebugUnavailableTests.LifetimeInlineAndLibraryInOrder;
var
  mFacts: TAtlasUnavailableFacts;
  mExplanation: TAtlasUnavailableExplanation;
begin
  mFacts := LocalFacts;
  mFacts.Lifetime := TAtlasValueLifetime.Before;
  mFacts.RoutineInline := True;
  mFacts.LibraryFrame := True;
  mExplanation := TAtlasDebugUnavailable.Explain(mFacts);
  Assert.AreEqual(Ord(TAtlasUnavailableCause.Lifetime), Ord(mExplanation.Cause));
  Assert.AreEqual(0, Integer(Length(mExplanation.Fixes)));
  mFacts.Lifetime := TAtlasValueLifetime.Within;
  mFacts.RoutineName := 'TKunde.Summe';
  mExplanation := TAtlasDebugUnavailable.Explain(mFacts);
  Assert.AreEqual(Ord(TAtlasUnavailableCause.InlineRoutine), Ord(mExplanation.Cause));
  Assert.AreEqual('TKunde.Summe', mExplanation.RoutineName);
  mFacts.RoutineInline := False;
  mExplanation := TAtlasDebugUnavailable.Explain(mFacts);
  Assert.AreEqual(Ord(TAtlasUnavailableCause.LibraryFrame), Ord(mExplanation.Cause));
  Assert.IsTrue(mExplanation.HasFix(TAtlasUnavailableFix.DebugDcus));
  mFacts.Launch.DebugDcus := 'true';
  Assert.AreEqual(Ord(TAtlasUnavailableCause.Unknown), Ord(TAtlasDebugUnavailable.Explain(mFacts).Cause),
    'mit Debug-DCUs keine Ursache');
end;

procedure TAtlasDebugUnavailableTests.UnknownListsAllChecks;
var
  mExplanation: TAtlasUnavailableExplanation;
  mCheck: TAtlasUnavailableCheck;
begin
  mExplanation := TAtlasDebugUnavailable.Explain(LocalFacts);
  Assert.AreEqual(Ord(TAtlasUnavailableCause.Unknown), Ord(mExplanation.Cause));
  Assert.AreEqual(Ord(High(TAtlasUnavailableCheck)) + 1, Integer(Length(mExplanation.Checked)));
  for mCheck := Low(TAtlasUnavailableCheck) to High(TAtlasUnavailableCheck) do
  begin
    Assert.AreEqual(Ord(mCheck), Ord(mExplanation.Checked[Ord(mCheck)]), 'Reihenfolge der Prüfung');
  end;
  Assert.AreEqual(0, Integer(Length(mExplanation.Fixes)));
end;

procedure TAtlasDebugUnavailableTests.ReadsServerAnswer;
var
  mJson: TJSONValue;
  mFacts: TAtlasUnavailableFacts;
begin
  mJson := TJSONObject.ParseJSONValue('{"switches":[' +
    '{"name":"D","value":"+","origin":{"kind":"project","text":"DCC_DebugInformation"}},' +
    '{"name":"O","value":"+","origin":{"kind":"directive","text":"{$O+}","file":"C:\\P\\Kunden.pas","line":3}}],' +
    '"routine":{"name":"TKunde.Summe","inline":true,"startLine":10,"endLine":20},' +
    '"variable":{"local":true,"parameter":false,"firstUse":12,"lastUse":15,"lifetime":"after"},' +
    '"fixes":{"routineOptimization":{"changes":{"file:///C:/P/Kunden.pas":[{"range":{"start":{"line":9,' +
    '"character":0},"end":{"line":9,"character":0}},"newText":"{$OPTIMIZATION OFF}\r\n"}]}}}}');
  try
    mFacts := TAtlasUnavailableFacts.Create(DebugLaunch, False);
    mFacts.ReadServer(mJson);
  finally
    mJson.Free;
  end;
  Assert.IsTrue(mFacts.Server);
  Assert.IsTrue(mFacts.DebugInfo.Known);
  Assert.AreEqual(Ord(TAtlasSwitchSource.Project), Ord(mFacts.DebugInfo.Source));
  Assert.IsFalse(mFacts.LocalSymbols.Known, 'L fehlt in der Antwort');
  Assert.IsTrue(mFacts.Optimization.IsDirective);
  Assert.AreEqual(3, mFacts.Optimization.Line);
  Assert.AreEqual('TKunde.Summe', mFacts.RoutineName);
  Assert.IsTrue(mFacts.RoutineInline);
  Assert.IsTrue(mFacts.Local);
  Assert.AreEqual(15, mFacts.LastUse);
  Assert.AreEqual(Ord(TAtlasValueLifetime.After), Ord(mFacts.Lifetime));
  Assert.IsFalse(mFacts.RoutineEdit.IsEmpty);
  Assert.IsTrue(mFacts.UnitEdit.IsEmpty);
  mFacts := TAtlasUnavailableFacts.Create(DebugLaunch, False);
  mFacts.ReadServer(nil);
  Assert.IsFalse(mFacts.Server, 'ohne Antwort');
end;

procedure TAtlasDebugUnavailableTests.PreviewShowsInsertedLines;
var
  mLines: TArray<string>;
begin
  mLines := TAtlasDebugUnavailable.PreviewLines(Edit(9, '{$OPTIMIZATION OFF}'));
  Assert.AreEqual(1, Integer(Length(mLines)));
  Assert.AreEqual('10: {$OPTIMIZATION OFF}', mLines[0]);
end;

end.
