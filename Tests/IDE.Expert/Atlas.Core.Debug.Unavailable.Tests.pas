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
  Json: TJSONObject;
begin
  Json := TJSONObject.ParseJSONValue(Format('{"changes":{"file:///C:/P/Kunden.pas":[{"range":{"start":' +
    '{"line":%d,"character":0},"end":{"line":%d,"character":0}},"newText":"%s\r\n"}]}}', [ALine, ALine, AText]))
    as TJSONObject;
  try
    Result := TLspWorkspaceEdit.FromJson(Json);
  finally
    Json.Free;
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
  Patterns: TArray<string>;
begin
  Assert.IsTrue(TAtlasDebugUnavailable.MatchesPattern('Wert X nicht lesbar', 'wert * nicht lesbar'));
  Assert.IsFalse(TAtlasDebugUnavailable.MatchesPattern('nicht lesbar: Wert', 'wert * nicht lesbar'),
    'Teile in der Reihenfolge des Musters');
  Patterns := TAtlasDebugUnavailable.ParsePatterns('# eigene Texte' + sLineBreak + sLineBreak +
    '  Wert * nicht lesbar  # Firmen-Debugger' + sLineBreak + 'ausgelagert');
  Assert.AreEqual(2, Integer(Length(Patterns)));
  Assert.AreEqual('Wert * nicht lesbar', Patterns[0]);
  Assert.IsTrue(TAtlasDebugUnavailable.IsUnavailable('Wert Summe nicht lesbar', Patterns));
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
  Facts: TAtlasUnavailableFacts;
  Explanation: TAtlasUnavailableExplanation;
begin
  Facts := LocalFacts;
  Facts.Launch.Configuration := 'Release';
  Facts.Launch.DebugInfo := 'false';
  Facts.Launch.Optimization := 'true';
  Facts.Optimization := Switch('+', TAtlasSwitchSource.Directive);
  Explanation := TAtlasDebugUnavailable.Explain(Facts);
  Assert.AreEqual(Ord(TAtlasUnavailableCause.ReleaseBuild), Ord(Explanation.Cause));
  Assert.AreEqual('Release', Explanation.Configuration);
  Assert.IsTrue(Explanation.HasFix(TAtlasUnavailableFix.RestartWithDebug));
  Assert.AreEqual(1, Integer(Length(Explanation.Checked)), 'nur die Konfiguration geprüft');
  Facts.Launch.DebugInfo := '0';
  Assert.AreEqual(Ord(TAtlasUnavailableCause.ReleaseBuild), Ord(TAtlasDebugUnavailable.Explain(Facts).Cause),
    '0 heißt keine Debug-Informationen');
end;

procedure TAtlasDebugUnavailableTests.DirectiveSwitchesBeforeOptimization;
var
  Facts: TAtlasUnavailableFacts;
  Explanation: TAtlasUnavailableExplanation;
begin
  Facts := LocalFacts;
  Facts.DebugInfo := Switch('-', TAtlasSwitchSource.Directive);
  Facts.Optimization := Switch('+', TAtlasSwitchSource.Directive);
  Explanation := TAtlasDebugUnavailable.Explain(Facts);
  Assert.AreEqual(Ord(TAtlasUnavailableCause.NoDebugInfo), Ord(Explanation.Cause));
  Assert.AreEqual(11, Explanation.Switch.Line);
  Assert.IsTrue(Explanation.HasFix(TAtlasUnavailableFix.ShowDirective));
  Facts := LocalFacts;
  Facts.LocalSymbols := Switch('-', TAtlasSwitchSource.Directive);
  Assert.AreEqual(Ord(TAtlasUnavailableCause.NoLocalSymbols), Ord(TAtlasDebugUnavailable.Explain(Facts).Cause));
  Facts.Local := False;
  Assert.AreEqual(Ord(TAtlasUnavailableCause.Unknown), Ord(TAtlasDebugUnavailable.Explain(Facts).Cause),
    '$L- betrifft nur lokale Namen');
end;

procedure TAtlasDebugUnavailableTests.LaunchValueWinsOverProjectValue;
var
  Facts: TAtlasUnavailableFacts;
begin
  // Der Server kennt die aktive Konfiguration (O+), gestartet wurde aber Debug (O-).
  Facts := LocalFacts;
  Facts.Optimization := Switch('+', TAtlasSwitchSource.Project);
  Assert.AreEqual(Ord(TAtlasUnavailableCause.Unknown), Ord(TAtlasDebugUnavailable.Explain(Facts).Cause));
  // Ohne bekannten Start (angehängt) gilt der Stand des Servers.
  Facts.Launch.Known := False;
  Assert.AreEqual(Ord(TAtlasUnavailableCause.Optimization), Ord(TAtlasDebugUnavailable.Explain(Facts).Cause));
  // Eine Direktive gilt immer.
  Facts := LocalFacts;
  Facts.Optimization := Switch('+', TAtlasSwitchSource.Directive);
  Assert.AreEqual(Ord(TAtlasUnavailableCause.Optimization), Ord(TAtlasDebugUnavailable.Explain(Facts).Cause));
end;

procedure TAtlasDebugUnavailableTests.OptimizationAddsLifetimeAndFixes;
var
  Facts: TAtlasUnavailableFacts;
  Explanation: TAtlasUnavailableExplanation;
begin
  Facts := LocalFacts;
  Facts.Launch.Optimization := 'true';
  Facts.Lifetime := TAtlasValueLifetime.After;
  Facts.LastUse := 41;
  Facts.RoutineEdit := Edit(30, '{$OPTIMIZATION OFF}');
  Facts.UnitEdit := Edit(2, '{$O-}');
  Explanation := TAtlasDebugUnavailable.Explain(Facts);
  Assert.AreEqual(Ord(TAtlasUnavailableCause.Optimization), Ord(Explanation.Cause));
  Assert.AreEqual(Ord(TAtlasValueLifetime.After), Ord(Explanation.Lifetime), 'Hinweis zur Lebensdauer');
  Assert.IsTrue(Explanation.HasFix(TAtlasUnavailableFix.RoutineOptimization));
  Assert.IsTrue(Explanation.HasFix(TAtlasUnavailableFix.UnitOptimization));
  Assert.IsFalse(Explanation.HasFix(TAtlasUnavailableFix.ShowDirective), 'O+ aus der .dproj');
  Assert.AreEqual(3, Integer(Length(Explanation.Checked)));
  // Felder liegen nicht in Registern.
  Facts.Local := False;
  Assert.AreEqual(Ord(TAtlasUnavailableCause.Unknown), Ord(TAtlasDebugUnavailable.Explain(Facts).Cause));
end;

procedure TAtlasDebugUnavailableTests.LifetimeInlineAndLibraryInOrder;
var
  Facts: TAtlasUnavailableFacts;
  Explanation: TAtlasUnavailableExplanation;
begin
  Facts := LocalFacts;
  Facts.Lifetime := TAtlasValueLifetime.Before;
  Facts.RoutineInline := True;
  Facts.LibraryFrame := True;
  Explanation := TAtlasDebugUnavailable.Explain(Facts);
  Assert.AreEqual(Ord(TAtlasUnavailableCause.Lifetime), Ord(Explanation.Cause));
  Assert.AreEqual(0, Integer(Length(Explanation.Fixes)));
  Facts.Lifetime := TAtlasValueLifetime.Within;
  Facts.RoutineName := 'TKunde.Summe';
  Explanation := TAtlasDebugUnavailable.Explain(Facts);
  Assert.AreEqual(Ord(TAtlasUnavailableCause.InlineRoutine), Ord(Explanation.Cause));
  Assert.AreEqual('TKunde.Summe', Explanation.RoutineName);
  Facts.RoutineInline := False;
  Explanation := TAtlasDebugUnavailable.Explain(Facts);
  Assert.AreEqual(Ord(TAtlasUnavailableCause.LibraryFrame), Ord(Explanation.Cause));
  Assert.IsTrue(Explanation.HasFix(TAtlasUnavailableFix.DebugDcus));
  Facts.Launch.DebugDcus := 'true';
  Assert.AreEqual(Ord(TAtlasUnavailableCause.Unknown), Ord(TAtlasDebugUnavailable.Explain(Facts).Cause),
    'mit Debug-DCUs keine Ursache');
end;

procedure TAtlasDebugUnavailableTests.UnknownListsAllChecks;
var
  Explanation: TAtlasUnavailableExplanation;
  Check: TAtlasUnavailableCheck;
begin
  Explanation := TAtlasDebugUnavailable.Explain(LocalFacts);
  Assert.AreEqual(Ord(TAtlasUnavailableCause.Unknown), Ord(Explanation.Cause));
  Assert.AreEqual(Ord(High(TAtlasUnavailableCheck)) + 1, Integer(Length(Explanation.Checked)));
  for Check := Low(TAtlasUnavailableCheck) to High(TAtlasUnavailableCheck) do
    Assert.AreEqual(Ord(Check), Ord(Explanation.Checked[Ord(Check)]), 'Reihenfolge der Prüfung');
  Assert.AreEqual(0, Integer(Length(Explanation.Fixes)));
end;

procedure TAtlasDebugUnavailableTests.ReadsServerAnswer;
var
  Json: TJSONValue;
  Facts: TAtlasUnavailableFacts;
begin
  Json := TJSONObject.ParseJSONValue('{"switches":[' +
    '{"name":"D","value":"+","origin":{"kind":"project","text":"DCC_DebugInformation"}},' +
    '{"name":"O","value":"+","origin":{"kind":"directive","text":"{$O+}","file":"C:\\P\\Kunden.pas","line":3}}],' +
    '"routine":{"name":"TKunde.Summe","inline":true,"startLine":10,"endLine":20},' +
    '"variable":{"local":true,"parameter":false,"firstUse":12,"lastUse":15,"lifetime":"after"},' +
    '"fixes":{"routineOptimization":{"changes":{"file:///C:/P/Kunden.pas":[{"range":{"start":{"line":9,' +
    '"character":0},"end":{"line":9,"character":0}},"newText":"{$OPTIMIZATION OFF}\r\n"}]}}}}');
  try
    Facts := TAtlasUnavailableFacts.Create(DebugLaunch, False);
    Facts.ReadServer(Json);
  finally
    Json.Free;
  end;
  Assert.IsTrue(Facts.Server);
  Assert.IsTrue(Facts.DebugInfo.Known);
  Assert.AreEqual(Ord(TAtlasSwitchSource.Project), Ord(Facts.DebugInfo.Source));
  Assert.IsFalse(Facts.LocalSymbols.Known, 'L fehlt in der Antwort');
  Assert.IsTrue(Facts.Optimization.IsDirective);
  Assert.AreEqual(3, Facts.Optimization.Line);
  Assert.AreEqual('TKunde.Summe', Facts.RoutineName);
  Assert.IsTrue(Facts.RoutineInline);
  Assert.IsTrue(Facts.Local);
  Assert.AreEqual(15, Facts.LastUse);
  Assert.AreEqual(Ord(TAtlasValueLifetime.After), Ord(Facts.Lifetime));
  Assert.IsFalse(Facts.RoutineEdit.IsEmpty);
  Assert.IsTrue(Facts.UnitEdit.IsEmpty);
  Facts := TAtlasUnavailableFacts.Create(DebugLaunch, False);
  Facts.ReadServer(nil);
  Assert.IsFalse(Facts.Server, 'ohne Antwort');
end;

procedure TAtlasDebugUnavailableTests.PreviewShowsInsertedLines;
var
  Lines: TArray<string>;
begin
  Lines := TAtlasDebugUnavailable.PreviewLines(Edit(9, '{$OPTIMIZATION OFF}'));
  Assert.AreEqual(1, Integer(Length(Lines)));
  Assert.AreEqual('10: {$OPTIMIZATION OFF}', Lines[0]);
end;

end.
