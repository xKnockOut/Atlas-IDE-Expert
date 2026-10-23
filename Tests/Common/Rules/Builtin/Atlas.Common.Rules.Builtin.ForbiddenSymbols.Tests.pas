unit Atlas.Common.Rules.Builtin.ForbiddenSymbols.Tests;

// Tests der Regel forbidden-symbol (#1133): Beispiel aus dem Issue, je Art ein
// Treffer, gleichnamige eigene Methode bleibt stumm, Muster mit *, units,
// replacement als Schnellkorrektur, leere Liste, Argumentfilter (Queue(nil),
// Writeln(ErrOutput)), nicht auflösbarer linker Teil, Schweregrad je Eintrag,
// Markierungen ERWARTET-OPTION im Referenzprojekt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TForbiddenSymbolTests = class
  public
    [Test]
    procedure IssueExample;
    [Test]
    procedure EachKindReports;
    [Test]
    procedure OwnSymbolOfSameNameIsSilent;
    [Test]
    procedure StarPattern;
    [Test]
    procedure UnitsRestrict;
    [Test]
    procedure ReplacementFix;
    [Test]
    procedure EmptyListIsSilent;
    [Test]
    procedure FirstArgumentFilters;
    [Test]
    procedure UnresolvedQualifierMatchesTail;
    [Test]
    procedure SeverityPerEntry;
    [Test]
    procedure ParseSymbols;
    [Test]
    procedure ReferenceProjectMatchesMarkers;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.ForbiddenSymbols,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Tests.RuleAssert;

const
  cWerkzeug = 'unit Werkzeug;'#10'interface'#10'type'#10'  TFarbe = (fbRot, fbGruen);'#10 +
    '  TDaten = class'#10'  public'#10'    FWert: Integer;'#10'    procedure Laden;'#10 +
    '    property Wert: Integer read FWert;'#10'  end;'#10'const'#10'  cGrenze = 10;'#10 +
    'function DateiDa(const AName: string): Boolean;'#10'implementation'#10'end.';

/// <summary>Unit Formular mit uses Werkzeug, den Typen ATypes und der Routine Pruefen mit Deklarationen ADecls und
/// Anweisungen ABody.</summary>
function Source(const ATypes, ADecls, ABody: string): string;
begin
  Result := 'unit Formular;'#10'interface'#10'uses Werkzeug;'#10'implementation'#10 + ATypes +
    'procedure Pruefen(ADaten: TDaten);'#10'var'#10 + ADecls + 'begin'#10 + ABody + 'end;'#10'end.';
end;

function Config(const ASymbols: string): string;
begin
  Result := '{"rules": {"forbidden-symbol": {"severity": "warning", "symbols": ' + ASymbols + '}}}';
end;

function Found(const ASource, ASymbols, APath: string): TArray<TRuleFinding>; overload;
var
  mIndex: ISymbolIndex;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText(cWerkzeug, 'C:\Projekt\Werkzeug.pas', nil));
  Result := TRuleAssert.IndexFindings(TForbiddenSymbolRule.Create, ASource, mIndex, Config(ASymbols), APath);
end;

function Found(const ASource, ASymbols: string): TArray<TRuleFinding>; overload;
begin
  Result := Found(ASource, ASymbols, 'Formular.pas');
end;

/// <summary>Text im (einzeiligen) Bereich ARange von AText.</summary>
function Covered(const AText: string; const ARange: TTextRange): string;
var
  mLines: TArray<string>;
begin
  mLines := AText.Split([#10]);
  Result := Copy(mLines[ARange.StartPos.Line], ARange.StartPos.Character + 1,
    ARange.EndPos.Character - ARange.StartPos.Character);
end;

/// <summary>Wendet die einzeiligen Edits einer Korrektur von hinten nach vorn an (Zeilen mit #10).</summary>
function Applied(const AText: string; const AFix: TRuleFix): string;
var
  mLines: TArray<string>;
  mIndex: Integer;
  mEdit: TRuleEdit;
  mLine: string;
begin
  mLines := AText.Split([#10]);
  for mIndex := High(AFix.Edits) downto 0 do
  begin
    mEdit := AFix.Edits[mIndex];
    Assert.AreEqual(mEdit.Range.StartPos.Line, mEdit.Range.EndPos.Line, 'nur einzeilige Edits');
    mLine := mLines[mEdit.Range.StartPos.Line];
    mLines[mEdit.Range.StartPos.Line] := Copy(mLine, 1, mEdit.Range.StartPos.Character) + mEdit.NewText +
      Copy(mLine, mEdit.Range.EndPos.Character + 1, MaxInt);
  end;
  Result := string.Join(#10, mLines);
end;

{ TForbiddenSymbolTests }

procedure TForbiddenSymbolTests.IssueExample;
var
  mSource: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := 'unit Import;'#10'interface'#10'type'#10'  TImport = class'#10 +
    '    procedure Melden(const AText: string);'#10'  end;'#10'implementation'#10 +
    'procedure TImport.Melden(const AText: string);'#10'begin'#10'  Writeln(AText);'#10'end;'#10'end.';
  mFound := TRuleAssert.Findings(TForbiddenSymbolRule.Create, mSource,
    Config('[{"name": "System.Write*", "kind": "routine", "message": "Nur über ILogger"}]'), 'Import.pas');
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(ForbiddenSymbolRuleId, mFound[0].RuleId);
  Assert.AreEqual('Writeln ist in diesem Projekt verboten: Nur über ILogger (atlas.json › forbidden-symbol).',
    mFound[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFound[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFound[0].Confidence));
  Assert.AreEqual(9, mFound[0].Range.StartPos.Line);
  Assert.AreEqual('Writeln', Covered(mSource, mFound[0].Range));
  Assert.AreEqual(0, Integer(Length(mFound[0].Fixes)));
end;

procedure TForbiddenSymbolTests.EachKindReports;
var
  mSource: string;

  procedure Expect(const AEntry, ACovered: string);
  var
    mFound: TArray<TRuleFinding>;
  begin
    mFound := Found(mSource, '[' + AEntry + ']');
    Assert.AreEqual(1, Integer(Length(mFound)), AEntry);
    Assert.AreEqual(ACovered, Covered(mSource, mFound[0].Range), AEntry);
  end;

begin
  mSource := Source('', '  mFarbe: TFarbe;'#10, '  if DateiDa(''x'') then'#10'    ADaten.FWert := cGrenze;'#10 +
    '  mFarbe := fbGruen;'#10'  Pruefen(nil);'#10'  mFarbe := TFarbe(ADaten.Wert);'#10);
  Expect('{"name": "Werkzeug.DateiDa", "kind": "routine"}', 'DateiDa');
  // TFarbe als Typ der Variablen (TypeReference) und als Umwandlung.
  Assert.AreEqual(2, Integer(Length(Found(mSource, '[{"name": "Werkzeug.TFarbe", "kind": "type"}]'))));
  Expect('{"name": "Werkzeug.cGrenze", "kind": "constant"}', 'cGrenze');
  Expect('{"name": "Werkzeug.TDaten.FWert", "kind": "field"}', 'ADaten.FWert');
  Expect('{"name": "Werkzeug.TDaten.Wert", "kind": "property"}', 'ADaten.Wert');
  Expect('{"name": "Werkzeug.fbGruen", "kind": "enumValue"}', 'fbGruen');
  Expect('{"name": "Werkzeug.TFarbe.fbGruen", "kind": "enumValue"}', 'fbGruen');
  // Bezeichner ohne Auflösung: auch die eigene Routine Pruefen.
  Expect('{"name": "Pruefen", "kind": "identifier"}', 'Pruefen');
  // Falsche Art: DateiDa ist keine Konstante.
  Assert.AreEqual(0, Integer(Length(Found(mSource, '[{"name": "Werkzeug.DateiDa", "kind": "constant"}]'))));
  // Ohne kind jede Art.
  Expect('{"name": "Werkzeug.cGrenze"}', 'cGrenze');
end;

procedure TForbiddenSymbolTests.OwnSymbolOfSameNameIsSilent;
var
  mSource: string;
begin
  // Eigene Methode Writeln und eigene Routine DateiDa verdecken System.Writeln bzw. Werkzeug.DateiDa.
  mSource := 'unit Formular;'#10'interface'#10'uses Werkzeug;'#10'type'#10'  TImport = class'#10 +
    '    procedure Writeln(const AText: string);'#10'    procedure Melden;'#10'  end;'#10 +
    'function DateiDa(const AName: string): Boolean;'#10'implementation'#10 +
    'function DateiDa(const AName: string): Boolean;'#10'begin'#10'  Result := False;'#10'end;'#10 +
    'procedure TImport.Writeln(const AText: string);'#10'begin'#10'end;'#10 +
    'procedure TImport.Melden;'#10'begin'#10'  Writeln(''x'');'#10'  DateiDa(''y'');'#10'end;'#10'end.';
  Assert.AreEqual(0, Integer(Length(Found(mSource,
    '[{"name": "System.Writeln"}, {"name": "Werkzeug.DateiDa"}]'))));
  // Wert einer eigenen Aufzählung namens Write: Deklaration und Verwendung sind nicht System.Write.
  Assert.AreEqual(0, Integer(Length(Found('unit Formular;'#10'interface'#10'type'#10 +
    '  TZugriff = (Read, Write);'#10'implementation'#10'procedure Pruefen(var AZugriff: TZugriff);'#10'begin'#10 +
    '  AZugriff := Write;'#10'end;'#10'end.', '[{"name": "System.Write"}]'))));
  // Gegenprobe: Formular.DateiDa ist gemeint.
  Assert.AreEqual(1, Integer(Length(Found(mSource, '[{"name": "Formular.DateiDa"}]'))));
end;

procedure TForbiddenSymbolTests.StarPattern;
var
  mSource: string;
begin
  mSource := Source('', '', '  ADaten.Laden;'#10'  ADaten.FWert := ADaten.Wert;'#10'  DateiDa(''x'');'#10);
  Assert.AreEqual(3, Integer(Length(Found(mSource, '[{"name": "Werkzeug.TDaten.*"}]'))));
  Assert.AreEqual(1, Integer(Length(Found(mSource, '[{"name": "Werkzeug.Datei*", "kind": "routine"}]'))));
  // Kürzer ab einer Punktgrenze.
  Assert.AreEqual(1, Integer(Length(Found(mSource, '[{"name": "TDaten.Laden"}]'))));
  Assert.AreEqual(0, Integer(Length(Found(mSource, '[{"name": "Daten.Laden"}]'))));
end;

procedure TForbiddenSymbolTests.UnitsRestrict;
var
  mSource: string;
begin
  mSource := Source('', '', '  DateiDa(''x'');'#10);
  Assert.AreEqual(1, Integer(Length(Found(mSource, '[{"name": "Werkzeug.DateiDa", "units": ["Form*"]}]'))));
  Assert.AreEqual(0, Integer(Length(Found(mSource, '[{"name": "Werkzeug.DateiDa", "units": ["Server.*"]}]'))));
  Assert.AreEqual(0, Integer(Length(Found(mSource, '[{"name": "Werkzeug.DateiDa", "units": ["!Formular"]}]'))));
  Assert.AreEqual(1, Integer(Length(Found(mSource, '[{"name": "Werkzeug.DateiDa", "units": ["!Server.*"]}]'))));
end;

procedure TForbiddenSymbolTests.ReplacementFix;
var
  mSource, mFixed: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := Source('', '', '  DateiDa(''x'');'#10'  Werkzeug.DateiDa(''y'');'#10'  ADaten.Laden;'#10);
  mFound := Found(mSource, '[{"name": "Werkzeug.DateiDa", "replacement": "FileExists"}]');
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual('Durch FileExists ersetzen', mFound[0].Fixes[0].Title);
  mFixed := Applied(Applied(mSource, mFound[1].Fixes[0]), mFound[0].Fixes[0]);
  Assert.IsTrue(Pos('  FileExists(''x'');'#10'  FileExists(''y'');', mFixed) > 0, mFixed);
  // Mitglied eines Objekts: nur der Name hinter dem Punkt.
  mFound := Found(mSource, '[{"name": "Werkzeug.TDaten.Laden", "replacement": "Neu"}]');
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.IsTrue(Pos('  ADaten.Neu;', Applied(mSource, mFound[0].Fixes[0])) > 0);
  // Ohne replacement keine Korrektur.
  Assert.AreEqual(0, Integer(Length(Found(mSource, '[{"name": "Werkzeug.TDaten.Laden"}]')[0].Fixes)));
end;

procedure TForbiddenSymbolTests.EmptyListIsSilent;
var
  mSource: string;
begin
  mSource := Source('', '', '  Writeln(''x'');'#10'  DateiDa(''x'');'#10);
  Assert.AreEqual(0, Integer(Length(Found(mSource, '[]'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TForbiddenSymbolRule.Create, mSource,
    '{"rules": {"forbidden-symbol": "warning"}}', 'Formular.pas'))));
  // Eintrag mit unbekannter Art gilt nicht.
  Assert.AreEqual(0, Integer(Length(Found(mSource, '[{"name": "Werkzeug.DateiDa", "kind": "methode"}]'))));
  // Standard aus.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TForbiddenSymbolRule.Create, mSource, '', 'Formular.pas'))));
end;

procedure TForbiddenSymbolTests.FirstArgumentFilters;
var
  mSource: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := Source('', '  mLog: TextFile;'#10, '  Writeln(''a'');'#10'  Writeln(ErrOutput, ''b'');'#10 +
    '  Writeln(mLog, ''c'');'#10'  Write;'#10'  TThread.Queue(nil, nil);'#10'  TThread.Queue(ADaten, nil);'#10 +
    '  TThread.ForceQueue(nil, nil);'#10);
  // Wie Tools/Check-ConsoleOutput.ps1: ErrOutput erlaubt; eine Datei (Typ TextFile) schreibt nicht auf stdout.
  mFound := Found(mSource, '[{"name": "System.Write*", "kind": "routine", "allowFirstArgument": ["ErrOutput", ' +
    '"TextFile", "Text"]}]');
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual('Writeln', Covered(mSource, mFound[0].Range));
  Assert.AreEqual('Write', Covered(mSource, mFound[1].Range));
  // Wie Tools/Check-MainThreadQueue.ps1: nur mit nil als erstem Argument.
  mFound := Found(mSource, '[{"name": "System.Classes.TThread.*Queue", "firstArgument": ["nil"]}]');
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual('TThread.Queue', Covered(mSource, mFound[0].Range));
  Assert.AreEqual('TThread.ForceQueue', Covered(mSource, mFound[1].Range));
end;

procedure TForbiddenSymbolTests.UnresolvedQualifierMatchesTail;
var
  mIndex: ISymbolIndex;
  mSource: string;
begin
  // Mit indexierter Unit: aufgelöst, auch über einen Nachfahren.
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText('unit System.Classes;'#10'interface'#10'type'#10 +
    '  TThread = class'#10'  public'#10'    class procedure Queue(AThread: TThread; AProc: Pointer);'#10 +
    '  end;'#10'implementation'#10'end.', 'C:\BDS\source\System.Classes.pas', nil));
  mSource := 'unit Formular;'#10'interface'#10'uses System.Classes;'#10'type'#10 +
    '  TArbeit = class(TThread)'#10'  end;'#10'implementation'#10'procedure Pruefen;'#10'begin'#10 +
    '  TThread.Queue(nil, nil);'#10'  TArbeit.Queue(nil, nil);'#10'end;'#10'end.';
  Assert.AreEqual(2, Integer(Length(TRuleAssert.IndexFindings(TForbiddenSymbolRule.Create, mSource, mIndex,
    Config('[{"name": "System.Classes.TThread.Queue"}]'), 'Formular.pas'))));
  // Eigene Klasse TThread: aufgelöst als Formular.TThread, also kein Treffer.
  mSource := 'unit Formular;'#10'interface'#10'type'#10'  TThread = class'#10'  public'#10 +
    '    class procedure Queue(AThread: TThread; AProc: Pointer);'#10'  end;'#10'implementation'#10 +
    'class procedure TThread.Queue(AThread: TThread; AProc: Pointer);'#10'begin'#10'end;'#10 +
    'procedure Pruefen;'#10'begin'#10'  TThread.Queue(nil, nil);'#10'end;'#10'end.';
  Assert.AreEqual(0, Integer(Length(Found(mSource, '[{"name": "System.Classes.TThread.Queue"}]'))));
  // Unbekanntes TThread (Unit nicht indexiert): geschriebener Name gegen das Ende des Eintrags.
  mSource := Source('', '', '  TThread.Queue(nil, nil);'#10'  Unbekannt.Queue(nil, nil);'#10'  Queue(nil, nil);'#10);
  Assert.AreEqual(1, Integer(Length(Found(mSource, '[{"name": "System.Classes.TThread.Queue"}]'))));
end;

procedure TForbiddenSymbolTests.SeverityPerEntry;
var
  mSource: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := Source('', '', '  DateiDa(''x'');'#10'  ADaten.Laden;'#10);
  mFound := Found(mSource, '[{"name": "Werkzeug.DateiDa", "severity": "error"}, {"name": "Werkzeug.TDaten.Laden"}, ' +
    '{"name": "Werkzeug.TDaten", "severity": "off"}]');
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(mFound[0].Severity));
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFound[1].Severity));
  Assert.AreEqual('ADaten.Laden ist in diesem Projekt verboten (atlas.json › forbidden-symbol).', mFound[1].Message);
end;

procedure TForbiddenSymbolTests.ParseSymbols;
var
  mSymbols: TArray<TForbiddenSymbol>;
  mKind: TForbiddenKind;
begin
  mSymbols := TForbiddenSymbolRule.ParseSymbols('{"symbols": [{"name": " A.B ", "kind": "enumValue", ' +
    '"message": "M", "replacement": "R", "severity": "hint", "units": ["U*"], "firstArgument": ["nil"], ' +
    '"allowFirstArgument": ["X"]}, {"kind": "type"}, 3]}');
  Assert.AreEqual(1, Integer(Length(mSymbols)));
  Assert.AreEqual('A.B', mSymbols[0].Name);
  Assert.AreEqual(Ord(TForbiddenKind.EnumValue), Ord(mSymbols[0].Kind));
  Assert.AreEqual('M', mSymbols[0].Message);
  Assert.AreEqual('R', mSymbols[0].Replacement);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(mSymbols[0].Severity));
  Assert.AreEqual('U*', mSymbols[0].Units[0]);
  Assert.AreEqual('nil', mSymbols[0].FirstArgument[0]);
  Assert.AreEqual('X', mSymbols[0].AllowFirstArgument[0]);
  Assert.AreEqual(0, Integer(Length(TForbiddenSymbolRule.ParseSymbols(''))));
  Assert.IsTrue(TForbiddenSymbolRule.TryParseKind('Property', mKind));
  Assert.AreEqual(Ord(TForbiddenKind.Property_), Ord(mKind));
  Assert.IsFalse(TForbiddenSymbolRule.TryParseKind('methode', mKind));
  Assert.IsTrue(mSymbols[0].MatchesTail('A.B'));
  Assert.IsFalse(mSymbols[0].MatchesTail('B'));
end;

function ReferenceFolder: string;
var
  mDirectory: string;
begin
  mDirectory := ExtractFileDir(ParamStr(0));
  while mDirectory <> '' do
  begin
    Result := TPath.Combine(mDirectory, TPath.Combine('Tests', 'Referenzprojekt'));
    if TDirectory.Exists(Result) then
      Exit;
    if ExtractFileDir(mDirectory) = mDirectory then
      Break;
    mDirectory := ExtractFileDir(mDirectory);
  end;
  Result := '';
end;

procedure TForbiddenSymbolTests.ReferenceProjectMatchesMarkers;
const
  cMarker = '// ERWARTET-OPTION: forbidden-symbol';
  // Wie im README des Referenzprojekts.
  cSymbols = '[{"name": "System.Write*", "kind": "routine", "message": "Nur über das Protokoll", ' +
    '"allowFirstArgument": ["ErrOutput", "TextFile", "Text"]}, {"name": "Ref.Pruefung.Verstoesse.AltMelden", ' +
    '"replacement": "Melden", "units": ["Ref.*"]}, {"name": "System.Classes.TThread.*Queue", ' +
    '"firstArgument": ["nil"], "units": ["Ref.Pruefung.*"]}]';
var
  mFolder, mFileName, mExpected, mActual: string;
  mFiles, mTexts, mLines: TArray<string>;
  mFormat: TFileFormat;
  mIndex: ISymbolIndex;
  mFinding: TRuleFinding;
  mFile, mLine: Integer;
begin
  // Golden-Korpus mit Optionen (#152): alle Units des Referenzprojekts und TThread als Stub im Index; genau die
  // markierten Zeilen, jede weitere Meldung ist ein Fehlalarm.
  mFolder := ReferenceFolder;
  if mFolder = '' then
    Assert.Pass('Referenzprojekt nicht gefunden; Prüfung übersprungen');
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText('unit System.Classes;'#10'interface'#10'type'#10 +
    '  TThreadProcedure = reference to procedure;'#10'  TThread = class'#10'  public'#10 +
    '    class procedure Queue(const AThread: TThread; const AThreadProc: TThreadProcedure);'#10 +
    '    class function CurrentThread: TThread;'#10'  end;'#10'implementation'#10'end.',
    'C:\BDS\source\System.Classes.pas', nil));
  mFiles := nil;
  mTexts := nil;
  for mFileName in TDirectory.GetFiles(TPath.Combine(mFolder, 'Source'), '*.pas') do
  begin
    mFiles := mFiles + [mFileName];
    mTexts := mTexts + [TFileEncoding.Decode(TFile.ReadAllBytes(mFileName), mFormat)];
    mIndex.AddUnit(TIndexExtractor.ExtractText(mTexts[High(mTexts)], mFileName, nil));
  end;
  mExpected := '';
  mActual := '';
  for mFile := 0 to High(mFiles) do
  begin
    mLines := mTexts[mFile].Replace(#13#10, #10).Split([#10]);
    for mLine := 0 to High(mLines) do
      if mLines[mLine].Contains(cMarker) then
        mExpected := mExpected + ExtractFileName(mFiles[mFile]) + ':' + IntToStr(mLine + 1) + #10;
    for mFinding in TRuleAssert.IndexFindings(TForbiddenSymbolRule.Create, mTexts[mFile], mIndex, Config(cSymbols),
      ExtractFileName(mFiles[mFile])) do
      mActual := mActual + ExtractFileName(mFiles[mFile]) + ':' + IntToStr(mFinding.Range.StartPos.Line + 1) + #10;
  end;
  Assert.IsTrue(mExpected <> '', 'Keine Markierungen im Referenzprojekt');
  Assert.AreEqual(mExpected, mActual);
  mFiles := nil;
  mTexts := nil;
  mLines := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TForbiddenSymbolTests);

end.
