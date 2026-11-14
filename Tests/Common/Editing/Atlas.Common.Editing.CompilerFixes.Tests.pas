unit Atlas.Common.Editing.CompilerFixes.Tests;

// Tests für die Schnellkorrekturen an Compilermeldungen, Teil 2 (#549). Der
// Golden-Test wendet je Meldung die bevorzugte Korrektur auf den Vorher-Text
// an und vergleicht mit Atlas.Common.Editing.CompilerFixesGolden.pas; dass
// das Ergebnis ohne Hinweis übersetzt, zeigt der Delphi-Testlauf.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCompilerFixesTests = class
  public
    [Test]
    procedure QuotedNamesFromMessages;
    /// <summary>Abnahme: H2443 für System.Generics.Collections trägt die Unit ein.</summary>
    [Test]
    procedure H2443AddsUnit;
    /// <summary>Abnahme: E2003 auf TStringList bietet System.Classes an erster Stelle an.</summary>
    [Test]
    procedure E2003OffersLibraryUnitFirst;
    [Test]
    procedure E2003NothingWhenAlreadyUsed;
    [Test]
    procedure H2077RemovesPureAssignment;
    /// <summary>Abnahme: H2077 auf X := Foo(); entfernt nicht den Aufruf.</summary>
    [Test]
    procedure H2077KeepsCall;
    [Test]
    procedure H2077NothingForPossibleCall;
    /// <summary>Abnahme: W1035 fügt Result := Default(Integer); ein.</summary>
    [Test]
    procedure W1035InsertsDefault;
    [Test]
    procedure W1057CastsRightSide;
    [Test]
    procedure W1058UsesColumn;
    [Test]
    procedure FixAllCombinesMessages;
    [Test]
    procedure MatchesGoldenFile;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.CompilerFixes;

const
  cLB = #13#10;

function Context: TCompilerFixContext;
begin
  Result := Default(TCompilerFixContext);
  Result.Declaring :=
    function(const AName: string): TArray<string>
    begin
      Result := nil;
      if SameText(AName, 'TStringList') then
      begin
        Result := TArray<string>.Create('Meine.Listen', 'Vcl.Klassen.Alt', 'System.Classes');
      end
      else if SameText(AName, 'TJSONArray') then
      begin
        Result := TArray<string>.Create('System.JSON');
      end;
    end;
  Result.Namespaces := TArray<string>.Create('System', 'Vcl');
end;

function Fixed(const AText: string; const AMessage: TFixMessage; out ATitles: string): string;
var
  mTree: TSyntaxTree;
  mFixes: TArray<TCompilerFix>;
  mItem: TCompilerFix;
begin
  Result := '';
  ATitles := '';
  mTree := TPascalParser.Parse(AText);
  try
    mFixes := TCompilerFixes.Fixes(AText, mTree, AMessage, Context);
    for mItem in mFixes do
    begin
      ATitles := ATitles + mItem.Title;
      if mItem.Preferred then
      begin
        ATitles := ATitles + ' *';
      end;
      ATitles := ATitles + '|';
    end;
    if Length(mFixes) > 0 then
    begin
      Result := TChangeSignature.ApplyEdits(AText, mFixes[0].Edits);
    end;
  finally
    mTree.Free;
  end;
end;

function Fixed1(const AText: string; const AMessage: TFixMessage): string;
var
  mTitles: string;
begin
  Result := Fixed(AText, AMessage, mTitles);
end;

function Routine(const ABody: string): string;
begin
  Result := 'unit A;' + cLB + 'interface' + cLB + 'implementation' + cLB + 'uses' + cLB + '  System.SysUtils;' + cLB +
    ABody + cLB + 'end.';
end;

procedure TCompilerFixesTests.QuotedNamesFromMessages;
begin
  Assert.AreEqual('Add|System.Generics.Collections', string.Join('|', TCompilerFixes.QuotedNames(
    'Inline function ''Add'' has not been expanded because unit ''System.Generics.Collections'' is not ' +
    'specified in USES list')));
  Assert.AreEqual('AnsiString|string', string.Join('|', TCompilerFixes.QuotedNames(
    'Implizite String-Umwandlung von ''AnsiString'' zu ''string''')));
  Assert.AreEqual('', string.Join('|', TCompilerFixes.QuotedNames('ohne Namen ''offen')));
end;

procedure TCompilerFixesTests.H2443AddsUnit;
const
  cBody = 'function Anzahl(A: TJSONArray): Integer;' + cLB + 'begin' + cLB + '  Result := A.Count;' + cLB + 'end;';
var
  mTitles: string;
begin
  Assert.AreEqual(StringReplace(Routine(cBody), 'System.SysUtils;', 'System.SysUtils,' + cLB +
    '  System.Generics.Collections;', []), Fixed(Routine(cBody), TFixMessage.Create('H2443', 7, -1, 'Inline-Funktion ''TJSONArray.GetCount'' wurde ' +
    'nicht expandiert, weil Unit ''System.Generics.Collections'' nicht in der USES-Liste angegeben ist'), mTitles));
  Assert.AreEqual('uses System.Generics.Collections ergänzen (H2443) *|', mTitles);
  // Schon eingebunden: nichts.
  Assert.AreEqual('', Fixed1(StringReplace(Routine(cBody), 'System.SysUtils;', 'System.SysUtils, ' +
    'System.Generics.Collections;', []), TFixMessage.Create('H2443', 7, -1, 'x ''A'' y ''System.Generics.Collections''')));
end;

procedure TCompilerFixesTests.E2003OffersLibraryUnitFirst;
const
  cBody = 'procedure Fuelle;' + cLB + 'var' + cLB + '  L: TStringList;' + cLB + 'begin' + cLB + 'end;';
var
  mTitles: string;
begin
  Assert.AreEqual(StringReplace(Routine(cBody), 'System.SysUtils;', 'System.SysUtils,' + cLB + '  System.Classes;',
    []), Fixed(Routine(cBody), TFixMessage.Create('E2003', 7, -1, 'Undeclared identifier: ''TStringList'''), mTitles));
  Assert.AreEqual('uses System.Classes ergänzen (E2003: TStringList) *|' +
    'uses Vcl.Klassen.Alt ergänzen (E2003: TStringList)|uses Meine.Listen ergänzen (E2003: TStringList)|', mTitles);
end;

procedure TCompilerFixesTests.E2003NothingWhenAlreadyUsed;
const
  cBody = 'procedure Fuelle;' + cLB + 'var' + cLB + '  L: TStringList;' + cLB + 'begin' + cLB + 'end;';
begin
  Assert.AreEqual('', Fixed1(StringReplace(Routine(cBody), 'System.SysUtils;', 'System.SysUtils, Classes;', []),
    TFixMessage.Create('E2003', 7, -1, 'Undeklarierter Bezeichner: ''TStringList''')), 'über den Namespace');
  Assert.AreEqual('', Fixed1(Routine(cBody), TFixMessage.Create('E2003', 7, -1, 'Undeclared identifier: ''Gibts''')));
end;

procedure TCompilerFixesTests.H2077RemovesPureAssignment;
const
  cBody = 'function F(A: Integer): Integer;' + cLB + 'var' + cLB + '  X: Integer;' + cLB + 'begin' + cLB +
    '  X := A * 2 + 1;' + cLB + '  X := 3;' + cLB + '  Result := X;' + cLB + 'end;';
var
  mTitles: string;
begin
  Assert.AreEqual(StringReplace(Routine(cBody), '  X := A * 2 + 1;' + cLB, '', []), Fixed(Routine(cBody),
    TFixMessage.Create('H2077', 9, -1, 'Value assigned to ''X'' never used'), mTitles));
  Assert.AreEqual('Wirkungslose Zuweisung an X entfernen (H2077) *|', mTitles);
  // Im Zweig ohne begin bleibt eine leere Anweisung.
  Assert.AreEqual(StringReplace(Routine(StringReplace(cBody, '  X := A * 2 + 1;', '  if A > 0 then X := 1;', [])),
    'then X := 1;', 'then ;', []), Fixed1(Routine(StringReplace(cBody, '  X := A * 2 + 1;', '  if A > 0 then X := 1;',
    [])), TFixMessage.Create('H2077', 9, -1, 'Auf ''X'' zugewiesener Wert wird niemals benutzt')));
end;

procedure TCompilerFixesTests.H2077KeepsCall;
const
  cBody = 'procedure P;' + cLB + 'var' + cLB + '  X: Integer;' + cLB + 'begin' + cLB + '  X := Foo();' + cLB +
    '  X := Obj.Lies(1, 2);' + cLB + 'end;';
var
  mTitles: string;
begin
  Assert.AreEqual(StringReplace(Routine(cBody), '  X := Foo();', '  Foo();', []), Fixed(Routine(cBody),
    TFixMessage.Create('H2077', 9, -1, 'Value assigned to ''X'' never used'), mTitles));
  Assert.AreEqual('Zuweisung an X entfernen, nur Foo aufrufen (H2077) *|', mTitles);
  Assert.AreEqual(StringReplace(Routine(cBody), '  X := Obj.Lies(1, 2);', '  Obj.Lies(1, 2);', []), Fixed1(
    Routine(cBody), TFixMessage.Create('H2077', 10, -1, 'Value assigned to ''X'' never used')));
end;

procedure TCompilerFixesTests.H2077NothingForPossibleCall;
const
  cBody = 'procedure P;' + cLB + 'var' + cLB + '  X: Integer;' + cLB + 'begin' + cLB + '  X := Zaehler;' + cLB +
    '  X := Obj.Wert + 1;' + cLB + 'end;';
begin
  Assert.AreEqual('', Fixed1(Routine(cBody), TFixMessage.Create('H2077', 9, -1, 'Value assigned to ''X'' never used')),
    'Zaehler kann eine Funktion sein');
  Assert.AreEqual('', Fixed1(Routine(cBody), TFixMessage.Create('H2077', 10, -1,
    'Value assigned to ''X'' never used')));
  Assert.AreEqual('', Fixed1(Routine(cBody), TFixMessage.Create('H2077', 9, -1, 'Value assigned to ''Y'' never used')),
    'anderer Name');
end;

procedure TCompilerFixesTests.W1035InsertsDefault;
const
  cBody = 'function F(A: Integer): Integer;' + cLB + 'begin' + cLB + '    if A > 0 then' + cLB + '      Result := A;' +
    cLB + 'end;';
  cGeneric = 'function G: TArray<string>;' + cLB + 'begin' + cLB + 'end;';
var
  mTitles: string;
begin
  Assert.AreEqual(StringReplace(Routine(cBody), 'begin' + cLB, 'begin' + cLB + '    Result := Default(Integer);' + cLB,
    []), Fixed(Routine(cBody), TFixMessage.Create('W1035', 9, -1,
    'Return value of function ''F'' might be undefined'), mTitles));
  Assert.AreEqual('Result := Default(Integer); am Anfang einfügen (W1035) *|', mTitles);
  Assert.AreEqual(StringReplace(Routine(cGeneric), 'begin' + cLB, 'begin' + cLB + '  Result := Default(TArray<string>);' +
    cLB, []), Fixed1(Routine(cGeneric), TFixMessage.Create('W1035', 7, -1, 'x')));
  Assert.AreEqual('', Fixed1(Routine('procedure P;' + cLB + 'begin' + cLB + 'end;'), TFixMessage.Create('W1035', 7, -1,
    'x')), 'ohne Ergebnistyp');
end;

procedure TCompilerFixesTests.W1057CastsRightSide;
const
  cBody = 'procedure P(const A: AnsiString);' + cLB + 'var' + cLB + '  S: string;' + cLB + 'begin' + cLB + '  S := A;' +
    cLB + 'end;';
var
  mTitles: string;
begin
  Assert.AreEqual(StringReplace(Routine(cBody), 'S := A;', 'S := string(A);', []), Fixed(Routine(cBody),
    TFixMessage.Create('W1057', 9, -1, 'Implicit string cast from ''AnsiString'' to ''string'''), mTitles));
  Assert.AreEqual('Explizit umwandeln: string(…) (W1057) *|', mTitles);
end;

procedure TCompilerFixesTests.W1058UsesColumn;
const
  cBody = 'procedure P(const S: string);' + cLB + 'begin' + cLB + '  Schreibe(1, S);' + cLB + 'end;';
begin
  Assert.AreEqual(StringReplace(Routine(cBody), 'Schreibe(1, S)', 'Schreibe(1, AnsiString(S))', []), Fixed1(
    Routine(cBody), TFixMessage.Create('W1058', 7, 14, 'Implicit string cast with potential data loss from ' +
    '''string'' to ''AnsiString''')));
  Assert.AreEqual('', Fixed1(Routine(cBody), TFixMessage.Create('W1058', 7, -1, 'x ''string'' y ''AnsiString''')),
    'ohne Spalte nur bei genau einer Zuweisung');
end;

procedure TCompilerFixesTests.FixAllCombinesMessages;
const
  cBody = 'procedure P(const A: AnsiString);' + cLB + 'var' + cLB + '  S, T: string;' + cLB + 'begin' + cLB +
    '  S := A;' + cLB + '  T := A;' + cLB + '  Zeige(S + T);' + cLB + 'end;';
var
  mTree: TSyntaxTree;
  mFix: TCompilerFix;
  mText: string;
begin
  mText := Routine(cBody);
  mTree := TPascalParser.Parse(mText);
  try
    Assert.IsTrue(TCompilerFixes.FixAll(mText, mTree, [TFixMessage.Create('W1057', 9, -1, 'x ''AnsiString'' y ''string'''),
      TFixMessage.Create('w1057', 10, -1, 'x ''AnsiString'' y ''string'''), TFixMessage.Create('H2077', 9, -1,
      '''S''')], 'W1057', Context, mFix));
    Assert.AreEqual('Alle W1057 in der Datei beheben (2)', mFix.Title);
    Assert.AreEqual(StringReplace(StringReplace(mText, 'S := A;', 'S := string(A);', []), 'T := A;', 'T := string(A);',
      []), TChangeSignature.ApplyEdits(mText, mFix.Edits));
    Assert.IsFalse(TCompilerFixes.FixAll(mText, mTree, [TFixMessage.Create('W1057', 9, -1, 'x ''A'' y ''string''')],
      'W1057', Context, mFix), 'eine Meldung reicht nicht');
    Assert.IsFalse(TCompilerFixes.FixAll(mText, mTree, nil, 'E2003', Context, mFix), 'E2003 hat eine Auswahl');
  finally
    mTree.Free;
  end;
end;

const
  cGoldenBefore =
    'unit Atlas.Common.Editing.CompilerFixesGolden;' + cLB +
    '' + cLB +
    '// Golden-Datei für die Schnellkorrekturen an Compilermeldungen, Teil 2' + cLB +
    '// (#549): genau das, was die Korrekturen aus dem Vorher-Text in' + cLB +
    '// Atlas.Common.Editing.CompilerFixes.Tests erzeugen. Der Delphi-Testlauf' + cLB +
    '// zeigt, dass das Ergebnis ohne Warnung und Hinweis übersetzt. Nicht von' + cLB +
    '// Hand ändern, sondern neu erzeugen.' + cLB +
    '' + cLB +
    'interface' + cLB +
    '' + cLB +
    'uses' + cLB +
    '  System.JSON;' + cLB +
    '' + cLB +
    'function Anzahl(AListe: TJSONArray): Integer;' + cLB +
    'function Zeilen(const AText: string): Integer;' + cLB +
    'function Erster(const AText: string): Integer;' + cLB +
    'function Doppelt(const AText: string): Integer;' + cLB +
    'function Breit(const AText: AnsiString): string;' + cLB +
    'function Schmal(const AText: string): AnsiString;' + cLB +
    '' + cLB +
    'implementation' + cLB +
    '' + cLB +
    'uses' + cLB +
    '  System.SysUtils;' + cLB +
    '' + cLB +
    'function Anzahl(AListe: TJSONArray): Integer;' + cLB +            // 26
    'begin' + cLB +
    '  Result := AListe.Count;' + cLB +                                 // 28: H2443
    'end;' + cLB +
    '' + cLB +
    'function Zeilen(const AText: string): Integer;' + cLB +           // 31
    'var' + cLB +
    '  Liste: TStringList;' + cLB +                                     // 33: E2003
    'begin' + cLB +
    '  Liste := TStringList.Create;' + cLB +
    '  try' + cLB +
    '    Liste.Text := AText;' + cLB +
    '    Result := Liste.Count;' + cLB +
    '  finally' + cLB +
    '    Liste.Free;' + cLB +
    '  end;' + cLB +
    'end;' + cLB +
    '' + cLB +
    'function Erster(const AText: string): Integer;' + cLB +            // 44
    'begin' + cLB +
    '  if AText <> '''' then' + cLB +
    '  begin' + cLB +
    '    Result := Ord(AText[1]);' + cLB +
    '  end;' + cLB +
    'end;' + cLB +                                                       // 50: W1035
    '' + cLB +
    'function Doppelt(const AText: string): Integer;' + cLB +           // 52
    'var' + cLB +
    '  Wert: Integer;' + cLB +
    'begin' + cLB +
    '  Wert := 0;' + cLB +                                               // 56: H2077 rein
    '  Wert := Zeilen(AText);' + cLB +                                   // 57: H2077 Aufruf
    '  Wert := 2;' + cLB +
    '  Result := Wert * 2;' + cLB +
    'end;' + cLB +
    '' + cLB +
    'function Breit(const AText: AnsiString): string;' + cLB +          // 62
    'begin' + cLB +
    '  Result := AText;' + cLB +                                         // 64: W1057
    'end;' + cLB +
    '' + cLB +
    'function Schmal(const AText: string): AnsiString;' + cLB +
    'begin' + cLB +
    '  Result := AText;' + cLB +                                         // 69: W1058
    'end;' + cLB +
    '' + cLB +
    'end.' + cLB;

function TestsFile(const ARelative: string): string;
var
  mStarts: TArray<string>;
  mStart, mDirectory: string;
begin
  mStarts := [ExtractFileDir(ParamStr(0)), GetCurrentDir];
  for mStart in mStarts do
  begin
    mDirectory := mStart;
    while mDirectory <> '' do
    begin
      Result := TPath.Combine(mDirectory, TPath.Combine('Tests', ARelative));
      if TFile.Exists(Result) then
      begin
        Exit;
      end;
      if ExtractFileDir(mDirectory) = mDirectory then
      begin
        Break;
      end;
      mDirectory := ExtractFileDir(mDirectory);
    end;
  end;
  Result := '';
end;

procedure TCompilerFixesTests.MatchesGoldenFile;
const
  // Von unten nach oben, damit die Zeilen darüber gelten; die uses-Korrekturen zuletzt.
  cCodes: array[0..6] of string = ('W1058', 'W1057', 'H2077', 'H2077', 'W1035', 'E2003', 'H2443');
  cLines: array[0..6] of Integer = (68, 63, 56, 55, 49, 32, 27);
  cTexts: array[0..6] of string = ('x ''string'' y ''AnsiString''', 'x ''AnsiString'' y ''string''', '''Wert''',
    '''Wert''', '''Erster''', 'Undeclared identifier: ''TStringList''',
    'x ''TJSONArray.GetCount'' y ''System.Generics.Collections''');
var
  mFileName, mGolden, mText: string;
  mIndex: Integer;
begin
  mText := cGoldenBefore;
  for mIndex := 0 to High(cCodes) do
  begin
    mText := Fixed1(mText, TFixMessage.Create(cCodes[mIndex], cLines[mIndex], -1, cTexts[mIndex]));
    Assert.AreNotEqual('', mText, cCodes[mIndex]);
  end;
  mFileName := TestsFile(TPath.Combine('Common', TPath.Combine('Editing',
    'Atlas.Common.Editing.CompilerFixesGolden.pas')));
  Assert.AreNotEqual('', mFileName, 'Golden-Datei nicht gefunden');
  mGolden := TFile.ReadAllText(mFileName, TEncoding.UTF8);
  if (mGolden <> '') and (mGolden[1] = #$FEFF) then
  begin
    Delete(mGolden, 1, 1);
  end;
  Assert.AreEqual(mGolden, mText);
end;

initialization
  TDUnitX.RegisterTestFixture(TCompilerFixesTests);

end.
