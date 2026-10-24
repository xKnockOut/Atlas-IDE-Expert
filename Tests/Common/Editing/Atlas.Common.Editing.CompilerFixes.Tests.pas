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
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.CompilerFixes;

const
  LB = #13#10;

function Context: TCompilerFixContext;
begin
  Result := Default(TCompilerFixContext);
  Result.Declaring :=
    function(const AName: string): TArray<string>
    begin
      Result := nil;
      if SameText(AName, 'TStringList') then
        Result := TArray<string>.Create('Meine.Listen', 'Vcl.Klassen.Alt', 'System.Classes')
      else if SameText(AName, 'TJSONArray') then
        Result := TArray<string>.Create('System.JSON');
    end;
  Result.Namespaces := TArray<string>.Create('System', 'Vcl');
end;

function Fixed(const AText: string; const AMessage: TFixMessage; out ATitles: string): string;
var
  Tree: TSyntaxTree;
  Fixes: TArray<TCompilerFix>;
  Item: TCompilerFix;
begin
  Result := '';
  ATitles := '';
  Tree := TPascalParser.Parse(AText);
  try
    Fixes := TCompilerFixes.Fixes(AText, Tree, AMessage, Context);
    for Item in Fixes do
    begin
      ATitles := ATitles + Item.Title;
      if Item.Preferred then
        ATitles := ATitles + ' *';
      ATitles := ATitles + '|';
    end;
    if Length(Fixes) > 0 then
      Result := TChangeSignature.ApplyEdits(AText, Fixes[0].Edits);
  finally
    Tree.Free;
  end;
end;

function Fixed1(const AText: string; const AMessage: TFixMessage): string;
var
  Titles: string;
begin
  Result := Fixed(AText, AMessage, Titles);
end;

function Routine(const ABody: string): string;
begin
  Result := 'unit A;' + LB + 'interface' + LB + 'implementation' + LB + 'uses' + LB + '  System.SysUtils;' + LB +
    ABody + LB + 'end.';
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
  Body = 'function Anzahl(A: TJSONArray): Integer;' + LB + 'begin' + LB + '  Result := A.Count;' + LB + 'end;';
var
  Titles: string;
begin
  Assert.AreEqual(StringReplace(Routine(Body), 'System.SysUtils;', 'System.SysUtils,' + LB +
    '  System.Generics.Collections;', []), Fixed(Routine(Body), TFixMessage.Create('H2443', 7, -1, 'Inline-Funktion ''TJSONArray.GetCount'' wurde ' +
    'nicht expandiert, weil Unit ''System.Generics.Collections'' nicht in der USES-Liste angegeben ist'), Titles));
  Assert.AreEqual('uses System.Generics.Collections ergänzen (H2443) *|', Titles);
  // Schon eingebunden: nichts.
  Assert.AreEqual('', Fixed1(StringReplace(Routine(Body), 'System.SysUtils;', 'System.SysUtils, ' +
    'System.Generics.Collections;', []), TFixMessage.Create('H2443', 7, -1, 'x ''A'' y ''System.Generics.Collections''')));
end;

procedure TCompilerFixesTests.E2003OffersLibraryUnitFirst;
const
  Body = 'procedure Fuelle;' + LB + 'var' + LB + '  L: TStringList;' + LB + 'begin' + LB + 'end;';
var
  Titles: string;
begin
  Assert.AreEqual(StringReplace(Routine(Body), 'System.SysUtils;', 'System.SysUtils,' + LB + '  System.Classes;',
    []), Fixed(Routine(Body), TFixMessage.Create('E2003', 7, -1, 'Undeclared identifier: ''TStringList'''), Titles));
  Assert.AreEqual('uses System.Classes ergänzen (E2003: TStringList) *|' +
    'uses Vcl.Klassen.Alt ergänzen (E2003: TStringList)|uses Meine.Listen ergänzen (E2003: TStringList)|', Titles);
end;

procedure TCompilerFixesTests.E2003NothingWhenAlreadyUsed;
const
  Body = 'procedure Fuelle;' + LB + 'var' + LB + '  L: TStringList;' + LB + 'begin' + LB + 'end;';
begin
  Assert.AreEqual('', Fixed1(StringReplace(Routine(Body), 'System.SysUtils;', 'System.SysUtils, Classes;', []),
    TFixMessage.Create('E2003', 7, -1, 'Undeklarierter Bezeichner: ''TStringList''')), 'über den Namespace');
  Assert.AreEqual('', Fixed1(Routine(Body), TFixMessage.Create('E2003', 7, -1, 'Undeclared identifier: ''Gibts''')));
end;

procedure TCompilerFixesTests.H2077RemovesPureAssignment;
const
  Body = 'function F(A: Integer): Integer;' + LB + 'var' + LB + '  X: Integer;' + LB + 'begin' + LB +
    '  X := A * 2 + 1;' + LB + '  X := 3;' + LB + '  Result := X;' + LB + 'end;';
var
  Titles: string;
begin
  Assert.AreEqual(StringReplace(Routine(Body), '  X := A * 2 + 1;' + LB, '', []), Fixed(Routine(Body),
    TFixMessage.Create('H2077', 9, -1, 'Value assigned to ''X'' never used'), Titles));
  Assert.AreEqual('Wirkungslose Zuweisung an X entfernen (H2077) *|', Titles);
  // Im Zweig ohne begin bleibt eine leere Anweisung.
  Assert.AreEqual(StringReplace(Routine(StringReplace(Body, '  X := A * 2 + 1;', '  if A > 0 then X := 1;', [])),
    'then X := 1;', 'then ;', []), Fixed1(Routine(StringReplace(Body, '  X := A * 2 + 1;', '  if A > 0 then X := 1;',
    [])), TFixMessage.Create('H2077', 9, -1, 'Auf ''X'' zugewiesener Wert wird niemals benutzt')));
end;

procedure TCompilerFixesTests.H2077KeepsCall;
const
  Body = 'procedure P;' + LB + 'var' + LB + '  X: Integer;' + LB + 'begin' + LB + '  X := Foo();' + LB +
    '  X := Obj.Lies(1, 2);' + LB + 'end;';
var
  Titles: string;
begin
  Assert.AreEqual(StringReplace(Routine(Body), '  X := Foo();', '  Foo();', []), Fixed(Routine(Body),
    TFixMessage.Create('H2077', 9, -1, 'Value assigned to ''X'' never used'), Titles));
  Assert.AreEqual('Zuweisung an X entfernen, nur Foo aufrufen (H2077) *|', Titles);
  Assert.AreEqual(StringReplace(Routine(Body), '  X := Obj.Lies(1, 2);', '  Obj.Lies(1, 2);', []), Fixed1(
    Routine(Body), TFixMessage.Create('H2077', 10, -1, 'Value assigned to ''X'' never used')));
end;

procedure TCompilerFixesTests.H2077NothingForPossibleCall;
const
  Body = 'procedure P;' + LB + 'var' + LB + '  X: Integer;' + LB + 'begin' + LB + '  X := Zaehler;' + LB +
    '  X := Obj.Wert + 1;' + LB + 'end;';
begin
  Assert.AreEqual('', Fixed1(Routine(Body), TFixMessage.Create('H2077', 9, -1, 'Value assigned to ''X'' never used')),
    'Zaehler kann eine Funktion sein');
  Assert.AreEqual('', Fixed1(Routine(Body), TFixMessage.Create('H2077', 10, -1,
    'Value assigned to ''X'' never used')));
  Assert.AreEqual('', Fixed1(Routine(Body), TFixMessage.Create('H2077', 9, -1, 'Value assigned to ''Y'' never used')),
    'anderer Name');
end;

procedure TCompilerFixesTests.W1035InsertsDefault;
const
  Body = 'function F(A: Integer): Integer;' + LB + 'begin' + LB + '    if A > 0 then' + LB + '      Result := A;' +
    LB + 'end;';
  Generic = 'function G: TArray<string>;' + LB + 'begin' + LB + 'end;';
var
  Titles: string;
begin
  Assert.AreEqual(StringReplace(Routine(Body), 'begin' + LB, 'begin' + LB + '    Result := Default(Integer);' + LB,
    []), Fixed(Routine(Body), TFixMessage.Create('W1035', 9, -1,
    'Return value of function ''F'' might be undefined'), Titles));
  Assert.AreEqual('Result := Default(Integer); am Anfang einfügen (W1035) *|', Titles);
  Assert.AreEqual(StringReplace(Routine(Generic), 'begin' + LB, 'begin' + LB + '  Result := Default(TArray<string>);' +
    LB, []), Fixed1(Routine(Generic), TFixMessage.Create('W1035', 7, -1, 'x')));
  Assert.AreEqual('', Fixed1(Routine('procedure P;' + LB + 'begin' + LB + 'end;'), TFixMessage.Create('W1035', 7, -1,
    'x')), 'ohne Ergebnistyp');
end;

procedure TCompilerFixesTests.W1057CastsRightSide;
const
  Body = 'procedure P(const A: AnsiString);' + LB + 'var' + LB + '  S: string;' + LB + 'begin' + LB + '  S := A;' +
    LB + 'end;';
var
  Titles: string;
begin
  Assert.AreEqual(StringReplace(Routine(Body), 'S := A;', 'S := string(A);', []), Fixed(Routine(Body),
    TFixMessage.Create('W1057', 9, -1, 'Implicit string cast from ''AnsiString'' to ''string'''), Titles));
  Assert.AreEqual('Explizit umwandeln: string(…) (W1057) *|', Titles);
end;

procedure TCompilerFixesTests.W1058UsesColumn;
const
  Body = 'procedure P(const S: string);' + LB + 'begin' + LB + '  Schreibe(1, S);' + LB + 'end;';
begin
  Assert.AreEqual(StringReplace(Routine(Body), 'Schreibe(1, S)', 'Schreibe(1, AnsiString(S))', []), Fixed1(
    Routine(Body), TFixMessage.Create('W1058', 7, 14, 'Implicit string cast with potential data loss from ' +
    '''string'' to ''AnsiString''')));
  Assert.AreEqual('', Fixed1(Routine(Body), TFixMessage.Create('W1058', 7, -1, 'x ''string'' y ''AnsiString''')),
    'ohne Spalte nur bei genau einer Zuweisung');
end;

procedure TCompilerFixesTests.FixAllCombinesMessages;
const
  Body = 'procedure P(const A: AnsiString);' + LB + 'var' + LB + '  S, T: string;' + LB + 'begin' + LB +
    '  S := A;' + LB + '  T := A;' + LB + '  Zeige(S + T);' + LB + 'end;';
var
  Tree: TSyntaxTree;
  Fix: TCompilerFix;
  Text: string;
begin
  Text := Routine(Body);
  Tree := TPascalParser.Parse(Text);
  try
    Assert.IsTrue(TCompilerFixes.FixAll(Text, Tree, [TFixMessage.Create('W1057', 9, -1, 'x ''AnsiString'' y ''string'''),
      TFixMessage.Create('w1057', 10, -1, 'x ''AnsiString'' y ''string'''), TFixMessage.Create('H2077', 9, -1,
      '''S''')], 'W1057', Context, Fix));
    Assert.AreEqual('Alle W1057 in der Datei beheben (2)', Fix.Title);
    Assert.AreEqual(StringReplace(StringReplace(Text, 'S := A;', 'S := string(A);', []), 'T := A;', 'T := string(A);',
      []), TChangeSignature.ApplyEdits(Text, Fix.Edits));
    Assert.IsFalse(TCompilerFixes.FixAll(Text, Tree, [TFixMessage.Create('W1057', 9, -1, 'x ''A'' y ''string''')],
      'W1057', Context, Fix), 'eine Meldung reicht nicht');
    Assert.IsFalse(TCompilerFixes.FixAll(Text, Tree, nil, 'E2003', Context, Fix), 'E2003 hat eine Auswahl');
  finally
    Tree.Free;
  end;
end;

const
  GoldenBefore =
    'unit Atlas.Common.Editing.CompilerFixesGolden;' + LB +
    '' + LB +
    '// Golden-Datei für die Schnellkorrekturen an Compilermeldungen, Teil 2' + LB +
    '// (#549): genau das, was die Korrekturen aus dem Vorher-Text in' + LB +
    '// Atlas.Common.Editing.CompilerFixes.Tests erzeugen. Der Delphi-Testlauf' + LB +
    '// zeigt, dass das Ergebnis ohne Warnung und Hinweis übersetzt. Nicht von' + LB +
    '// Hand ändern, sondern neu erzeugen.' + LB +
    '' + LB +
    'interface' + LB +
    '' + LB +
    'uses' + LB +
    '  System.JSON;' + LB +
    '' + LB +
    'function Anzahl(AListe: TJSONArray): Integer;' + LB +
    'function Zeilen(const AText: string): Integer;' + LB +
    'function Erster(const AText: string): Integer;' + LB +
    'function Doppelt(const AText: string): Integer;' + LB +
    'function Breit(const AText: AnsiString): string;' + LB +
    'function Schmal(const AText: string): AnsiString;' + LB +
    '' + LB +
    'implementation' + LB +
    '' + LB +
    'uses' + LB +
    '  System.SysUtils;' + LB +
    '' + LB +
    'function Anzahl(AListe: TJSONArray): Integer;' + LB +            // 26
    'begin' + LB +
    '  Result := AListe.Count;' + LB +                                 // 28: H2443
    'end;' + LB +
    '' + LB +
    'function Zeilen(const AText: string): Integer;' + LB +           // 31
    'var' + LB +
    '  Liste: TStringList;' + LB +                                     // 33: E2003
    'begin' + LB +
    '  Liste := TStringList.Create;' + LB +
    '  try' + LB +
    '    Liste.Text := AText;' + LB +
    '    Result := Liste.Count;' + LB +
    '  finally' + LB +
    '    Liste.Free;' + LB +
    '  end;' + LB +
    'end;' + LB +
    '' + LB +
    'function Erster(const AText: string): Integer;' + LB +            // 44
    'begin' + LB +
    '  if AText <> '''' then' + LB +
    '    Result := Ord(AText[1]);' + LB +
    'end;' + LB +                                                       // 48: W1035
    '' + LB +
    'function Doppelt(const AText: string): Integer;' + LB +           // 50
    'var' + LB +
    '  Wert: Integer;' + LB +
    'begin' + LB +
    '  Wert := 0;' + LB +                                               // 54: H2077 rein
    '  Wert := Zeilen(AText);' + LB +                                   // 55: H2077 Aufruf
    '  Wert := 2;' + LB +
    '  Result := Wert * 2;' + LB +
    'end;' + LB +
    '' + LB +
    'function Breit(const AText: AnsiString): string;' + LB +          // 60
    'begin' + LB +
    '  Result := AText;' + LB +                                         // 62: W1057
    'end;' + LB +
    '' + LB +
    'function Schmal(const AText: string): AnsiString;' + LB +
    'begin' + LB +
    '  Result := AText;' + LB +                                         // 67: W1058
    'end;' + LB +
    '' + LB +
    'end.' + LB;

function TestsFile(const ARelative: string): string;
var
  Starts: TArray<string>;
  Start, Directory: string;
begin
  Starts := [ExtractFileDir(ParamStr(0)), GetCurrentDir];
  for Start in Starts do
  begin
    Directory := Start;
    while Directory <> '' do
    begin
      Result := TPath.Combine(Directory, TPath.Combine('Tests', ARelative));
      if TFile.Exists(Result) then
        Exit;
      if ExtractFileDir(Directory) = Directory then
        Break;
      Directory := ExtractFileDir(Directory);
    end;
  end;
  Result := '';
end;

procedure TCompilerFixesTests.MatchesGoldenFile;
const
  // Von unten nach oben, damit die Zeilen darüber gelten; die uses-Korrekturen zuletzt.
  Codes: array[0..6] of string = ('W1058', 'W1057', 'H2077', 'H2077', 'W1035', 'E2003', 'H2443');
  Lines: array[0..6] of Integer = (66, 61, 54, 53, 47, 32, 27);
  Texts: array[0..6] of string = ('x ''string'' y ''AnsiString''', 'x ''AnsiString'' y ''string''', '''Wert''',
    '''Wert''', '''Erster''', 'Undeclared identifier: ''TStringList''',
    'x ''TJSONArray.GetCount'' y ''System.Generics.Collections''');
var
  FileName, Golden, Text: string;
  Index: Integer;
begin
  Text := GoldenBefore;
  for Index := 0 to High(Codes) do
  begin
    Text := Fixed1(Text, TFixMessage.Create(Codes[Index], Lines[Index], -1, Texts[Index]));
    Assert.IsTrue(Text <> '', Codes[Index]);
  end;
  FileName := TestsFile(TPath.Combine('Common', TPath.Combine('Editing',
    'Atlas.Common.Editing.CompilerFixesGolden.pas')));
  Assert.IsTrue(FileName <> '', 'Golden-Datei nicht gefunden');
  Golden := TFile.ReadAllText(FileName, TEncoding.UTF8);
  if (Golden <> '') and (Golden[1] = #$FEFF) then
    Delete(Golden, 1, 1);
  Assert.AreEqual(Golden, Text);
end;

initialization
  TDUnitX.RegisterTestFixture(TCompilerFixesTests);

end.
