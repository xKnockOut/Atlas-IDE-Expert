unit Atlas.Core.Tests.CoveredBy;

// Marke „getestet von“ (#1778) ohne VCL und Open Tools API: Anfrage
// atlas/coveredBy an den Server (Tests je Methode einer normalen Unit),
// Antwort lesen, Namen der Tests zerlegen (Unit.Fixture.Methode) und den
// Stand der Marke aus den Ergebnissen der Läufe zusammenzählen wie die
// Testlinse (#69, #1762): grün erst, wenn jeder Test bestand, gelb bei
// Teilstand, rot bei einem Fehlschlag.

interface

uses
  System.SysUtils,
  System.Types,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Tests.Run;

type
  TAtlasCoveredTest = record
    /// <summary>Unit.Fixture.Methode.</summary>
    Name: string;
    /// <summary>Namen für --run (bei [TestCase] je Fall).</summary>
    RunNames: TArray<string>;
    FileName: string;
    /// <summary>Kopf der Testmethode, 0-basiert.</summary>
    Line: Integer;
    /// <summary>1 = ruft die Methode direkt auf.</summary>
    Level: Integer;
    Inferred: Boolean;
  end;

  TAtlasCoveredMethod = record
    /// <summary>TFoo.Bar bzw. Bar.</summary>
    Name: string;
    /// <summary>Name im Kopf des Rumpfs, 0-basiert: dort steht die Marke.</summary>
    Line: Integer;
    Character: Integer;
    Tests: TArray<TAtlasCoveredTest>;
  end;

  TAtlasCoveredUnit = record
    UnitName: string;
    /// <summary>Die Unit ist eine Testunit: keine Marken.</summary>
    IsTestUnit: Boolean;
    /// <summary>Eine Testunit verwendet die Unit.</summary>
    HasTestUnit: Boolean;
    Methods: TArray<TAtlasCoveredMethod>;
    /// <summary>Der Server stieß an eine Grenze (Zeit, Zahl der Stellen): Es können Tests fehlen.</summary>
    Incomplete: Boolean;
    /// <summary>Index der Methode an der Zeile ALine; -1 ohne.</summary>
    function MethodAt(ALine: Integer): Integer;
    /// <summary>Methoden mit mindestens einem Test.</summary>
    function Tested: Integer;
    /// <summary>Die Tests aller Methoden hintereinander.</summary>
    function AllTests: TArray<TAtlasCoveredTest>;
  end;

  /// <summary>Zuletzt gefragter Stand: Datei, Text und Kennung der Einstellungen (Tiefe, private Methoden); FileName
  /// leer, wenn kein Server antworten konnte; At: Zeitpunkt des Versuchs (0 = nie).</summary>
  TAtlasCoveredByAsked = record
    FileName: string;
    Text: string;
    Key: string;
    At: UInt64;
  end;

{$SCOPEDENUMS ON}
  /// <summary>Was der Zeitgeber tut: nichts (Stand schon gefragt), warten (ohne Server erst nach einer Pause neu),
  /// die Marken leeren (Testunit) oder den Server fragen.</summary>
  TAtlasCoveredByAsk = (Skip, Wait, TestUnit, Ask);
  /// <summary>Beschriftung nach der Zahl der Tests: keiner, einer, mehrere.</summary>
  TAtlasCoveredByCount = (None, One, Many);
  /// <summary>Klick auf die Marke: ohne Test zur Testunit wechseln, mit Strg die Liste, sonst die Tests ausführen.
  /// </summary>
  TAtlasCoveredByClick = (SwitchTestUnit, List, Run);
{$SCOPEDENUMS OFF}

  /// <summary>Stand eines Tests (Unit, Fixture, Methode) nach den Läufen dieser Sitzung.</summary>
  TAtlasCoveredTallyFunc = reference to function(const AUnitName, AFixture, AMethod: string): TAtlasTestTally;

  TAtlasCoveredBy = class
  public const
    cMethod = 'atlas/coveredBy';
    /// <summary>Ohne laufenden Server erst nach so vielen Millisekunden erneut fragen.</summary>
    cRetryMs = 5000;
  public
    /// <summary>Marken zeichnen? Plugin an, „Tests ausführen“ und codeLens.coveredBy.</summary>
    class function Wanted(const ASettings: TAtlasPluginSettings): Boolean; static;
    /// <summary>Ist AText eine Testunit (DUnitX-Fixtures)? Dort zeigt die Test-Lens den Stand; keine Anfrage.
    /// </summary>
    class function IsTestUnit(const AText: string): Boolean; static;
    /// <summary>Parameter der Anfrage als JSON: Datei AUri mit dem Text des Editors, Tiefe und private Methoden.
    /// </summary>
    class function Params(const AUri, AText: string; ADepth: Integer; APrivate: Boolean): string; static;
    /// <summary>Antwort lesen; False, wenn sie kein Objekt ist. AUriToPath macht aus einer URI den Pfad.</summary>
    class function FromJson(const AJson: string; const AUriToPath: TFunc<string, string>;
      out AUnit: TAtlasCoveredUnit): Boolean; static;
    /// <summary>Zerlegt Unit.Fixture.Methode (die Unit darf Punkte enthalten); False bei weniger als drei Teilen.
    /// </summary>
    class function SplitName(const AName: string; out AUnitName, AFixture, AMethod: string): Boolean; static;
    /// <summary>Stand der Tests ATests zusammengezählt: jeder Test zählt einmal.</summary>
    class function TallyOf(const ATests: TArray<TAtlasCoveredTest>; const ATallyOf: TAtlasCoveredTallyFunc):
      TAtlasTestTally; static;
    /// <summary>Alle Namen für --run ohne Doppelte, in Reihenfolge der Tests.</summary>
    class function RunNames(const ATests: TArray<TAtlasCoveredTest>): TArray<string>; static;
    /// <summary>Schlüssel der veralteten Ergebnisse (#1770) in den Testunits der Tests ATests: jede Datei einmal
    /// gelesen (AReadLines) und nach AStaleKeys gefragt; nil ohne AStaleKeys.</summary>
    class function StaleKeysOf(const ATests: TArray<TAtlasCoveredTest>; const AReadLines: TAtlasTestReadLines;
      const AStaleKeys: TAtlasTestStaleKeys): TArray<string>; static;
    /// <summary>Kennung der Einstellungen, die die Antwort ändern: Tiefe und private Methoden.</summary>
    class function AskKey(ADepth: Integer; APrivate: Boolean): string; static;
    /// <summary>Schritt des Zeitgebers für Datei AFileName mit Text AText und Kennung AKey; AElapsedMs seit dem
    /// letzten Versuch AAsked.At.</summary>
    class function AskStep(const AAsked: TAtlasCoveredByAsked; const AFileName, AText, AKey: string;
      AElapsedMs: UInt64): TAtlasCoveredByAsk; static;
    /// <summary>Steht der Kurzname der Methode AMethodName (Bar aus TFoo.Bar) in der Zeile ALine? Sonst ist der
    /// Text seit der Antwort verschoben.</summary>
    class function HeaderShows(const AMethodName, ALine: string): Boolean; static;
    /// <summary>Beschriftung nach der Zahl ATests der Tests der Methode.</summary>
    class function CountOf(ATests: Integer): TAtlasCoveredByCount; static;
    /// <summary>Handlung des Klicks auf eine Marke mit ATests Tests; AList: mit Strg.</summary>
    class function ClickOf(ATests: Integer; AList: Boolean): TAtlasCoveredByClick; static;
    /// <summary>Farbe der Marke nach dem Stand ATally wie an der Test-Lens; ADefault ohne Ergebnis.</summary>
    class function ToneOf(const AColors: TAtlasColors; ADefault: TAtlasColor; const ATally: TAtlasTestTally):
      TAtlasColor; static;
    /// <summary>Index der ersten gezeichneten Marke in ARects unter APoint; -1 ohne.</summary>
    class function HitIndex(const ARects: TArray<TRect>; const APoint: TPoint): Integer; static;
  end;

implementation

uses
  System.Generics.Collections, // Inline-Funktionen von TJSONArray (H2443)
  System.JSON,
  System.StrUtils,
  Atlas.Core.Tests.Lens,
  Atlas.Text.DUnitX,
  Atlas.Text.Lines;

{ TAtlasCoveredUnit }

function TAtlasCoveredUnit.MethodAt(ALine: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(Methods) do
  begin
    if Methods[mIndex].Line = ALine then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function TAtlasCoveredUnit.Tested: Integer;
var
  mMethod: TAtlasCoveredMethod;
begin
  Result := 0;
  for mMethod in Methods do
  begin
    if Length(mMethod.Tests) > 0 then
    begin
      Inc(Result);
    end;
  end;
end;

function TAtlasCoveredUnit.AllTests: TArray<TAtlasCoveredTest>;
var
  mMethod: TAtlasCoveredMethod;
begin
  Result := nil;
  for mMethod in Methods do
  begin
    Result := Result + mMethod.Tests;
  end;
end;

{ TAtlasCoveredBy }

class function TAtlasCoveredBy.Wanted(const ASettings: TAtlasPluginSettings): Boolean;
begin
  Result := ASettings.Enabled and ASettings.TestRun and ASettings.CodeLensCoveredBy;
end;

class function TAtlasCoveredBy.IsTestUnit(const AText: string): Boolean;
begin
  Result := Length(TDUnitXSource.Scan(TTextLines.SplitLines(AText)).Fixtures) > 0;
end;

class function TAtlasCoveredBy.Params(const AUri, AText: string; ADepth: Integer; APrivate: Boolean): string;
var
  mParams, mDocument: TJSONObject;
begin
  mParams := TJSONObject.Create;
  try
    mDocument := TJSONObject.Create;
    mDocument.AddPair('uri', AUri);
    mParams.AddPair('textDocument', mDocument);
    mParams.AddPair('text', AText);
    mParams.AddPair('depth', TJSONNumber.Create(ADepth));
    mParams.AddPair('includePrivate', TJSONBool.Create(APrivate));
    Result := mParams.ToJSON;
  finally
    mParams.Free;
  end;
end;

/// <summary>Werte des Arrays AName in AEntry; nil ohne.</summary>
function StringsIn(AEntry: TJSONObject; const AName: string): TArray<string>;
var
  mArray: TJSONArray;
  mItem: TJSONValue;
begin
  Result := nil;
  if AEntry.TryGetValue<TJSONArray>(AName, mArray) then
  begin
    for mItem in mArray do
    begin
      Result := Result + [mItem.Value];
    end;
  end;
end;

function TestOf(AEntry: TJSONObject; const AUriToPath: TFunc<string, string>): TAtlasCoveredTest;
var
  mUri: string;
begin
  Result := Default(TAtlasCoveredTest);
  Result.Name := AEntry.GetValue<string>('name', '');
  Result.RunNames := StringsIn(AEntry, 'run');
  if Length(Result.RunNames) = 0 then
  begin
    Result.RunNames := TArray<string>.Create(Result.Name);
  end;
  mUri := AEntry.GetValue<string>('uri', '');
  Result.FileName := mUri;
  if Assigned(AUriToPath) then
  begin
    Result.FileName := AUriToPath(mUri);
  end;
  Result.Line := AEntry.GetValue<Integer>('line', 0);
  Result.Level := AEntry.GetValue<Integer>('level', 1);
  Result.Inferred := AEntry.GetValue<Boolean>('inferred', False);
end;

function MethodOf(AEntry: TJSONObject; const AUriToPath: TFunc<string, string>): TAtlasCoveredMethod;
var
  mTests: TJSONArray;
  mItem: TJSONValue;
begin
  Result := Default(TAtlasCoveredMethod);
  Result.Name := AEntry.GetValue<string>('name', '');
  Result.Line := AEntry.GetValue<Integer>('line', -1);
  Result.Character := AEntry.GetValue<Integer>('character', 0);
  if not AEntry.TryGetValue<TJSONArray>('tests', mTests) then
  begin
    Exit;
  end;
  for mItem in mTests do
  begin
    if mItem is TJSONObject then
    begin
      Result.Tests := Result.Tests + [TestOf(TJSONObject(mItem), AUriToPath)];
    end;
  end;
end;

class function TAtlasCoveredBy.FromJson(const AJson: string; const AUriToPath: TFunc<string, string>;
  out AUnit: TAtlasCoveredUnit): Boolean;
var
  mValue, mItem: TJSONValue;
  mRoot: TJSONObject;
  mMethods, mLimits: TJSONArray;
begin
  AUnit := Default(TAtlasCoveredUnit);
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := mValue is TJSONObject;
    if not Result then
    begin
      Exit;
    end;
    mRoot := TJSONObject(mValue);
    AUnit.UnitName := mRoot.GetValue<string>('unit', '');
    AUnit.IsTestUnit := mRoot.GetValue<Boolean>('testUnit', False);
    AUnit.HasTestUnit := mRoot.GetValue<Boolean>('hasTestUnit', False);
    if mRoot.TryGetValue<TJSONArray>('limits', mLimits) then
    begin
      AUnit.Incomplete := mLimits.Count > 0;
    end;
    if not mRoot.TryGetValue<TJSONArray>('methods', mMethods) then
    begin
      Exit;
    end;
    for mItem in mMethods do
    begin
      if mItem is TJSONObject then
      begin
        AUnit.Methods := AUnit.Methods + [MethodOf(TJSONObject(mItem), AUriToPath)];
      end;
    end;
  finally
    mValue.Free;
  end;
end;

class function TAtlasCoveredBy.SplitName(const AName: string; out AUnitName, AFixture, AMethod: string): Boolean;
var
  mLast, mBefore: Integer;
begin
  AUnitName := '';
  AFixture := '';
  AMethod := '';
  mLast := LastDelimiter('.', AName);
  mBefore := 0;
  if mLast > 1 then
  begin
    mBefore := LastDelimiter('.', Copy(AName, 1, mLast - 1));
  end;
  Result := mBefore > 1;
  if not Result then
  begin
    Exit;
  end;
  AUnitName := Copy(AName, 1, mBefore - 1);
  AFixture := Copy(AName, mBefore + 1, mLast - mBefore - 1);
  AMethod := Copy(AName, mLast + 1, MaxInt);
end;

class function TAtlasCoveredBy.TallyOf(const ATests: TArray<TAtlasCoveredTest>;
  const ATallyOf: TAtlasCoveredTallyFunc): TAtlasTestTally;
var
  mTest: TAtlasCoveredTest;
  mUnitName, mFixture, mMethod: string;
  mOne: TAtlasTestTally;
begin
  Result := Default(TAtlasTestTally);
  for mTest in ATests do
  begin
    Inc(Result.Total);
    if not (Assigned(ATallyOf) and SplitName(mTest.Name, mUnitName, mFixture, mMethod)) then
    begin
      Continue;
    end;
    mOne := ATallyOf(mUnitName, mFixture, mMethod);
    // Ein Test zählt als gelaufen, sobald einer seiner Fälle ein Ergebnis hat; fehlgeschlagen vor bestanden.
    if mOne.Ran = 0 then
    begin
      Continue;
    end;
    Inc(Result.Ran);
    if mOne.Stale > 0 then
    begin
      Inc(Result.Stale);
    end;
    if mOne.Failed > 0 then
    begin
      Inc(Result.Failed);
    end
    else if mOne.Passed > 0 then
    begin
      Inc(Result.Passed);
      if mOne.StalePassed > 0 then
      begin
        Inc(Result.StalePassed);
      end;
    end;
  end;
end;

class function TAtlasCoveredBy.RunNames(const ATests: TArray<TAtlasCoveredTest>): TArray<string>;
var
  mTest: TAtlasCoveredTest;
  mName: string;
begin
  Result := nil;
  for mTest in ATests do
  begin
    for mName in mTest.RunNames do
    begin
      if IndexText(mName, Result) < 0 then
      begin
        Result := Result + [mName];
      end;
    end;
  end;
end;

class function TAtlasCoveredBy.StaleKeysOf(const ATests: TArray<TAtlasCoveredTest>;
  const AReadLines: TAtlasTestReadLines; const AStaleKeys: TAtlasTestStaleKeys): TArray<string>;
var
  mTest: TAtlasCoveredTest;
  mRead: TArray<string>;
  mLines: TArray<string>;
begin
  Result := nil;
  if not (Assigned(AStaleKeys) and Assigned(AReadLines)) then
  begin
    Exit;
  end;
  mRead := nil;
  for mTest in ATests do
  begin
    if (mTest.FileName = '') or (IndexText(mTest.FileName, mRead) >= 0) then
    begin
      Continue;
    end;
    mRead := mRead + [mTest.FileName];
    if AReadLines(mTest.FileName, mLines) then
    begin
      Result := Result + AStaleKeys(TDUnitXSource.Scan(mLines), mLines);
    end;
  end;
end;

class function TAtlasCoveredBy.AskKey(ADepth: Integer; APrivate: Boolean): string;
begin
  Result := Format('%d|%s', [ADepth, BoolToStr(APrivate, True)]);
end;

class function TAtlasCoveredBy.AskStep(const AAsked: TAtlasCoveredByAsked; const AFileName, AText, AKey: string;
  AElapsedMs: UInt64): TAtlasCoveredByAsk;
begin
  if SameText(AAsked.FileName, AFileName) and (AAsked.Text = AText) and (AAsked.Key = AKey) then
  begin
    Result := TAtlasCoveredByAsk.Skip;
  end
  // Ohne laufenden Server (FileName leer) erst nach einer Pause erneut.
  else if (AAsked.FileName = '') and (AAsked.At <> 0) and (AElapsedMs < cRetryMs) then
  begin
    Result := TAtlasCoveredByAsk.Wait;
  end
  // Testunits bekommen keine Marken (dort zeigt die Test-Lens den Stand): ohne Anfrage.
  else if IsTestUnit(AText) then
  begin
    Result := TAtlasCoveredByAsk.TestUnit;
  end
  else
  begin
    Result := TAtlasCoveredByAsk.Ask;
  end;
end;

class function TAtlasCoveredBy.HeaderShows(const AMethodName, ALine: string): Boolean;
var
  mShort: string;
begin
  mShort := Copy(AMethodName, LastDelimiter('.', AMethodName) + 1, MaxInt);
  Result := Pos(LowerCase(mShort), LowerCase(ALine)) > 0;
end;

class function TAtlasCoveredBy.CountOf(ATests: Integer): TAtlasCoveredByCount;
begin
  if ATests = 0 then
  begin
    Result := TAtlasCoveredByCount.None;
  end
  else if ATests = 1 then
  begin
    Result := TAtlasCoveredByCount.One;
  end
  else
  begin
    Result := TAtlasCoveredByCount.Many;
  end;
end;

class function TAtlasCoveredBy.ClickOf(ATests: Integer; AList: Boolean): TAtlasCoveredByClick;
begin
  if ATests = 0 then
  begin
    Result := TAtlasCoveredByClick.SwitchTestUnit;
  end
  else if AList then
  begin
    Result := TAtlasCoveredByClick.List;
  end
  else
  begin
    Result := TAtlasCoveredByClick.Run;
  end;
end;

class function TAtlasCoveredBy.ToneOf(const AColors: TAtlasColors; ADefault: TAtlasColor;
  const ATally: TAtlasTestTally): TAtlasColor;
begin
  Result := TAtlasTestLens.Tone(AColors, ADefault, ATally.Shown, False, ATally.IsStale);
end;

class function TAtlasCoveredBy.HitIndex(const ARects: TArray<TRect>; const APoint: TPoint): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ARects) do
  begin
    if not ARects[mIndex].IsEmpty and ARects[mIndex].Contains(APoint) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

end.
