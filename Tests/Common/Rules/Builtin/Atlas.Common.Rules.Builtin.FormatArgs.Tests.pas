unit Atlas.Common.Rules.Builtin.FormatArgs.Tests;

// Tests der Regel format-args (#56): Beispiel aus dem Issue, passende und
// unbekannte Formatstrings, ungültige Platzhalter, Argumentzahl, Typen mit
// Aufzählungen und Boolean, "*", Konstanten und resourcestrings aus der Datei
// und dem Index, CreateFmt und FmtStr, eigene Format-Methoden, Option
// formatMethods, Abschalten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFormatArgsTests = class
  public
    [Test]
    procedure IssueExample;
    [Test]
    procedure MatchingAndUnknownFormatsAreSilent;
    [Test]
    procedure InvalidFormatStrings;
    [Test]
    procedure ArgumentCount;
    [Test]
    procedure ArgumentTypes;
    [Test]
    procedure StarNeedsInteger;
    [Test]
    procedure ConstantsAndResourceStrings;
    [Test]
    procedure IndexConstant;
    [Test]
    procedure OtherRoutines;
    [Test]
    procedure OwnFormatIsSilent;
    [Test]
    procedure FormatMethodsOption;
    [Test]
    procedure OffAndExclude;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.FormatArgs,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Tests.RuleAssert;

/// <summary>Unit Bericht mit Deklarationen ADecls vor der Prozedur Melden und deren Anweisungen ABody.</summary>
function Source(const ADecls, ABody: string): string;
begin
  Result := 'unit Bericht;'#10'interface'#10'implementation'#10'uses System.SysUtils;'#10'type'#10 +
    '  TArt = (Kunde, Lieferant);'#10'  TKunde = class'#10'  end;'#10 + ADecls +
    'procedure Melden(const AName: string; ACount: Integer; ABetrag: Double; AArt: TArt; AAktiv: Boolean;'#10 +
    '  AKunde: TKunde; AZeichen: Char; AWert: Variant; const AFormat: string);'#10'var'#10'  S: string;'#10 +
    'begin'#10 + ABody + 'end;'#10'end.';
end;

function Findings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TFormatArgsRule.Create, ASource);
end;

function Findings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TFormatArgsRule.Create, ASource, AConfig, APath);
end;

procedure TFormatArgsTests.IssueExample;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := Findings(Source('', '  S := Format(''%d'', [AName]);'#10));
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(FormatArgsRuleId, mFound[0].RuleId);
  Assert.AreEqual('%d erwartet eine Ganzzahl, AName ist vom Typ string: EConvertError zur Laufzeit.',
    mFound[0].Message);
  Assert.AreEqual(13, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(21, mFound[0].Range.StartPos.Character);
  Assert.AreEqual(26, mFound[0].Range.EndPos.Character);
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFound[0].Confidence));
end;

procedure TFormatArgsTests.MatchingAndUnknownFormatsAreSilent;
begin
  // Passende Typen, Formatstring aus Variable bzw. Parameter, Index doppelt, Variant überall, Zeiger und
  // Objekte bei %p, Literale, Argumentliste ohne [...].
  TRuleAssert.Silent(TFormatArgsRule.Create, Source('',
    '  S := Format(''%s'', [AName]);'#10 +
    '  S := Format(AFormat, [AName]);'#10 +
    '  S := Format(''%0:s %0:s'', [AName]);'#10 +
    '  S := Format(''%s %d %u %x %e %f %g %n %m'', [AZeichen, ACount, ACount, ACount, ABetrag, ABetrag,'#10 +
    '    ABetrag, ABetrag, ABetrag]);'#10 +
    '  S := Format(''%d %s %f'', [AWert, AWert, AWert]);'#10 +
    '  S := Format(''%p %p %p'', [AKunde, nil, Pointer(AKunde)]);'#10 +
    '  S := Format(''%s %d %d %.1f %s'', [''Text'', 42, -1, 1.5, #65]);'#10 +
    '  S := Format(''%d'', [Ord(AArt)]);'#10 +
    '  S := Format(''100%% von %s'', [AName]);'#10));
end;

procedure TFormatArgsTests.InvalidFormatStrings;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := Findings(Source('',
    '  S := Format(''Wert %q'', [ACount]);'#10 +
    '  S := Format(''100%'', []);'#10 +
    '  S := Format(''Breite %5'', [ACount]);'#10 +
    '  S := Format(''%0:'', [ACount]);'#10 +
    '  S := Format(''%0:-'', [ACount]);'#10));
  Assert.AreEqual(5, Integer(Length(mFound)));
  Assert.AreEqual('Ungültiger Formatstring: In %q ist "q" kein Typbuchstabe (d, u, e, f, g, n, m, p, s, x): ' +
    'EConvertError zur Laufzeit.', mFound[0].Message);
  Assert.AreEqual(13, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(14, mFound[0].Range.StartPos.Character);
  Assert.AreEqual(23, mFound[0].Range.EndPos.Character);
  Assert.AreEqual('Ungültiger Formatstring: % am Ende ist unvollständig: EConvertError zur Laufzeit.',
    mFound[1].Message);
  Assert.AreEqual('Ungültiger Formatstring: %5 am Ende ist unvollständig: EConvertError zur Laufzeit.',
    mFound[2].Message);
  Assert.AreEqual('Ungültiger Formatstring: %0: am Ende ist unvollständig: EConvertError zur Laufzeit.',
    mFound[3].Message);
  Assert.AreEqual('Ungültiger Formatstring: %0:- am Ende ist unvollständig: EConvertError zur Laufzeit.',
    mFound[4].Message);
  mFound := Findings(Source('', '  S := Format(''%0: %s'', [AName]);'#10));
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Ungültiger Formatstring: %0:  hat einen Index, aber keinen Typbuchstaben: EConvertError zur ' +
    'Laufzeit.', mFound[0].Message);
end;

procedure TFormatArgsTests.ArgumentCount;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := Findings(Source('',
    '  S := Format(''%s hat %d'', [AName]);'#10 +
    '  S := Format(''%s'', [AName, ACount]);'#10 +
    '  S := Format(''%1:s'', [AName]);'#10 +
    '  S := Format(''%1:s'', [AName, AName, ACount]);'#10));
  Assert.AreEqual(3, Integer(Length(mFound)));
  Assert.AreEqual('Der Formatstring braucht 2 Argumente, die Liste hat 1: EConvertError zur Laufzeit.',
    mFound[0].Message);
  Assert.AreEqual(27, mFound[0].Range.StartPos.Character);
  Assert.AreEqual(34, mFound[0].Range.EndPos.Character);
  Assert.AreEqual('Argument 2 (ACount) kommt im Formatstring nicht vor und wird nicht ausgegeben.',
    mFound[1].Message);
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(mFound[1].Confidence));
  Assert.AreEqual(28, mFound[1].Range.StartPos.Character);
  Assert.AreEqual('Der Formatstring braucht 2 Argumente, die Liste hat 1: EConvertError zur Laufzeit.',
    mFound[2].Message);
end;

procedure TFormatArgsTests.ArgumentTypes;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := Findings(Source('',
    '  S := Format(''%d'', [AArt]);'#10 +
    '  S := Format(''%d'', [AAktiv]);'#10 +
    '  S := Format(''%d'', [Kunde]);'#10 +
    '  S := Format(''%s'', [True]);'#10 +
    '  S := Format(''%f'', [ACount]);'#10 +
    '  S := Format(''%d'', [ABetrag]);'#10 +
    '  S := Format(''%s'', [AKunde]);'#10 +
    '  S := Format(''%x'', [''A'']);'#10 +
    '  S := Format(''%p'', [ACount]);'#10 +
    '  S := Format(''%n'', [''1,5'']);'#10));
  Assert.AreEqual(10, Integer(Length(mFound)));
  Assert.AreEqual('%d erwartet eine Ganzzahl, AArt ist vom Typ TArt: EConvertError zur Laufzeit. Ord(AArt) ' +
    'übergeben.', mFound[0].Message);
  Assert.AreEqual('%d erwartet eine Ganzzahl, AAktiv ist vom Typ Boolean: EConvertError zur Laufzeit. ' +
    'BoolToStr(AAktiv, True) übergeben.', mFound[1].Message);
  Assert.AreEqual('%d erwartet eine Ganzzahl, Kunde ist vom Typ TArt: EConvertError zur Laufzeit. Ord(Kunde) ' +
    'übergeben.', mFound[2].Message);
  Assert.AreEqual('%s erwartet einen String, ein Zeichen oder einen Variant, True ist vom Typ Boolean: ' +
    'EConvertError zur Laufzeit. BoolToStr(True, True) übergeben.', mFound[3].Message);
  Assert.AreEqual('%f erwartet eine Gleitkommazahl, ACount ist vom Typ Integer: EConvertError zur Laufzeit.',
    mFound[4].Message);
  Assert.AreEqual('%d erwartet eine Ganzzahl, ABetrag ist vom Typ Double: EConvertError zur Laufzeit.',
    mFound[5].Message);
  Assert.AreEqual('%s erwartet einen String, ein Zeichen oder einen Variant, AKunde ist vom Typ TKunde: ' +
    'EConvertError zur Laufzeit.', mFound[6].Message);
  Assert.AreEqual('%x erwartet eine Ganzzahl, ''A'' ist ein String: EConvertError zur Laufzeit.', mFound[7].Message);
  Assert.AreEqual('%p erwartet einen Zeiger, ACount ist vom Typ Integer: EConvertError zur Laufzeit.',
    mFound[8].Message);
  Assert.AreEqual('%n erwartet eine Gleitkommazahl, ''1,5'' ist ein String: EConvertError zur Laufzeit.',
    mFound[9].Message);
end;

procedure TFormatArgsTests.StarNeedsInteger;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := Findings(Source('',
    '  S := Format(''%*d'', [AName, ACount]);'#10 +
    '  S := Format(''%.*f'', [ACount, ABetrag]);'#10 +
    '  S := Format(''%*.*f'', [ACount]);'#10));
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual('Das * in %*d erwartet eine Ganzzahl für Breite bzw. Genauigkeit, AName ist vom Typ string: ' +
    'EConvertError zur Laufzeit.', mFound[0].Message);
  Assert.AreEqual('Der Formatstring braucht 3 Argumente, die Liste hat 1: EConvertError zur Laufzeit.',
    mFound[1].Message);
end;

procedure TFormatArgsTests.ConstantsAndResourceStrings;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := Findings(Source('const'#10'  cKopf = ''Kunde '';'#10'  cZeile = cKopf + ''%s: %d'';'#10 +
    '  cTyped: string = ''%s'';'#10'resourcestring'#10'  rsFehler = ''Fehler %d in %s'';'#10,
    '  S := Format(cZeile, [AName, AName]);'#10 +
    '  S := Format(rsFehler, [AName]);'#10 +
    '  S := Format(cKopf + ''%d'', [ACount]);'#10 +
    '  S := Format(cTyped, [ACount]);'#10));
  Assert.AreEqual(3, Integer(Length(mFound)));
  Assert.AreEqual('%d erwartet eine Ganzzahl, AName ist vom Typ string: EConvertError zur Laufzeit.',
    mFound[0].Message);
  Assert.AreEqual(19, mFound[0].Range.StartPos.Line);
  Assert.AreEqual('Der Formatstring braucht 2 Argumente, die Liste hat 1: EConvertError zur Laufzeit.',
    mFound[1].Message);
  // Typisierte Konstante; cKopf + '%d' passt.
  Assert.AreEqual('%s erwartet einen String, ein Zeichen oder einen Variant, ACount ist vom Typ Integer: ' +
    'EConvertError zur Laufzeit.', mFound[2].Message);
end;

procedure TFormatArgsTests.IndexConstant;
var
  mIndex: ISymbolIndex;
  mFound: TArray<TRuleFinding>;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText('unit Texte;'#10'interface'#10'resourcestring'#10 +
    '  rsAnzahl = ''%d Kunden'';'#10'const'#10'  cName = ''Name: %s'';'#10'implementation'#10'end.',
    'C:\Projekt\Texte.pas', nil));
  mFound := TRuleAssert.IndexFindings(TFormatArgsRule.Create, 'unit Bericht;'#10'interface'#10 +
    'implementation'#10'uses System.SysUtils, Texte;'#10'procedure Melden(const AName: string);'#10 +
    'var'#10'  S: string;'#10'begin'#10'  S := Format(rsAnzahl, [AName]);'#10'  S := Format(cName, [AName]);'#10 +
    '  S := Format(Texte.rsAnzahl, [AName]);'#10'end;'#10'end.', mIndex, '', 'Bericht.pas');
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual(8, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(10, mFound[1].Range.StartPos.Line);
end;

procedure TFormatArgsTests.OtherRoutines;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := Findings(Source('type'#10'  EImport = class(Exception);'#10,
    '  FmtStr(S, ''%d'', [AName]);'#10 +
    '  raise Exception.CreateFmt(''Kunde %s fehlt'', []);'#10 +
    '  raise EImport.CreateFmt(''Zeile %d'', [AName]);'#10 +
    '  raise EImport.CreateFmtHelp(''Zeile %d'', [ACount, AName], 7);'#10 +
    '  S := SysUtils.Format(''%q'', [AName]);'#10 +
    '  S := WideFormat(''%d'', [AName]);'#10));
  Assert.AreEqual(6, Integer(Length(mFound)));
  Assert.Contains(mFound[0].Message, '%d erwartet eine Ganzzahl');
  Assert.Contains(mFound[1].Message, 'braucht 1 Argumente, die Liste hat 0');
  Assert.Contains(mFound[2].Message, '%d erwartet eine Ganzzahl');
  Assert.Contains(mFound[3].Message, 'Argument 2 (AName) kommt im Formatstring nicht vor');
  Assert.Contains(mFound[4].Message, 'In %q ist');
  Assert.Contains(mFound[5].Message, '%d erwartet eine Ganzzahl');
  // Andere Methoden namens Format bleiben ohne Auflösung still.
  TRuleAssert.Silent(TFormatArgsRule.Create, Source('', '  S := Writer.Format(''%d'', [AName]);'#10 +
    '  S := FormatFloat(''%d'', ABetrag);'#10));
end;

procedure TFormatArgsTests.OwnFormatIsSilent;
begin
  TRuleAssert.Silent(TFormatArgsRule.Create, Source(
    'function Format(const AText: string; const AWerte: array of const): string;'#10'begin'#10 +
    '  Result := AText;'#10'end;'#10, '  S := Format(''%d %q'', [AName]);'#10));
end;

procedure TFormatArgsTests.FormatMethodsOption;
var
  mSource: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := Source('', '  Log.LogFmt(''%d'', [AName]);'#10'  Protokoll(''Eintrag %s'', [AName, ACount]);'#10);
  Assert.AreEqual(0, Integer(Length(Findings(mSource, '', 'Bericht.pas'))));
  mFound := Findings(mSource, '{"rules": {"format-args": {"formatMethods": ["TLogger.LogFmt", "Protokoll"]}}}',
    'Bericht.pas');
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.Contains(mFound[0].Message, '%d erwartet eine Ganzzahl');
  Assert.Contains(mFound[1].Message, 'Argument 2 (ACount)');
end;

procedure TFormatArgsTests.OffAndExclude;
var
  mSource: string;
begin
  mSource := Source('', '  S := Format(''%d'', [AName]);'#10);
  Assert.AreEqual(1, Integer(Length(Findings(mSource, '', 'Source/Bericht.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(mSource, '{"rules": {"format-args": "off"}}', 'Source/Bericht.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(mSource, '{"rules": {"group:find-bugs": "off"}}',
    'Source/Bericht.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(mSource, '{"rules": {"format-args": {"exclude": ["Source/*.pas"]}}}',
    'Source/Bericht.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TFormatArgsTests);

end.
