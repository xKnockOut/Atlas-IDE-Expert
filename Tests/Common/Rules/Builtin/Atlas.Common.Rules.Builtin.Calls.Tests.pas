unit Atlas.Common.Rules.Builtin.Calls.Tests;

// Tests der Regel argument-count-mismatch (#1007): zu wenige und zu viele
// Argumente, Anweisung ohne Klammern, verschachtelte Routinen, Routinen aus
// dem Index, stille Fälle (Überladungen, varargs, Typumwandlungen,
// prozedurale Variablen, System), Korrektur „Signaturhilfe öffnen“ samt
// Client-Befehl und Einstellungen. Dazu overload-resolution (#1371): keine
// Überladung passt (wie E2250), mehrdeutiger Aufruf (wie E2251), Gegenfälle,
// die dcc ohne Meldung übersetzt, und unvollständige Kandidatenlisten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCallRulesTests = class
  public
    [Test]
    procedure IssueExample;
    [Test]
    procedure TooManyArguments;
    [Test]
    procedure StatementWithoutParentheses;
    [Test]
    procedure NestedRoutine;
    [Test]
    procedure RoutineFromIndex;
    /// <summary>Überladungen im Vorfahren (#1326, Indy): override bzw. overload im Nachfahren verdeckt sie nicht;
    /// eine neue Methode ohne beides schon.</summary>
    [Test]
    procedure AncestorOverloads;
    /// <summary>#1326: Ein Vorfahr außerhalb des Index kann den Namen verdecken (Read im with eines
    /// TMemoryStream-Nachfahren, Error in einem TStrings-Nachfahren); Gegenprobe mit vollständiger Kette.</summary>
    [Test]
    procedure UnknownAncestorMayHideName;
    /// <summary>Create über eine Klassenreferenz (FError: ExceptClass) ist der Konstruktor der Zielklasse
    /// (Exception.Create(const Msg: string)), nicht TObject.Create: raise FError.Create('…') bleibt still.</summary>
    [Test]
    procedure ClassReferenceConstructor;
    [Test]
    procedure SilentCases;
    [Test]
    procedure SignatureHelpAction;
    [Test]
    procedure HeaderParts;
    [Test]
    procedure Options;
  end;

  [TestFixture]
  TOverloadResolutionTests = class
  public
    /// <summary>Fall Cm.E2250 aus Tests/Compilermeldungen samt Gegenfällen.</summary>
    [Test]
    procedure NoOverloadFits;
    /// <summary>Fall Cm.E2251 samt Gegenfällen.</summary>
    [Test]
    procedure AmbiguousCall;
    [Test]
    procedure MethodOverloads;
    /// <summary>Aliase auf eingebaute Typen zählen wie ihr Grundtyp, Records mit Implicit-Operator passen.</summary>
    [Test]
    procedure AliasesAndOperators;
    /// <summary>Gegenfälle aus Tests/DccFaelle/Dcc.Ueberladungen.pas: dcc übersetzt sie ohne Meldung.</summary>
    [Test]
    procedure CompilerAccepts;
    /// <summary>Kandidatenliste nicht sicher vollständig: ohne System im Index, unbekannte Unit in uses,
    /// gleichnamige Routine in einer anderen Unit, bedingte Deklaration, with, unbekannter Vorfahr.</summary>
    [Test]
    procedure IncompleteCandidates;
    /// <summary>Argumenttyp nicht sicher: Variant, überladene Funktion im Argument, untypisierte Konstante.</summary>
    [Test]
    procedure UncertainArguments;
    [Test]
    procedure FitTable;
    [Test]
    procedure Options;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.CodeActions,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Rules.Builtin.Calls,
  Atlas.Common.Semantics.ExpressionTypes,
  Atlas.Tests.RuleAssert;

const
  Kopf = 'unit Post;'#10'interface'#10'type'#10'  TKunde = class'#10'    Mail: string;'#10 +
    '    procedure Senden(A: Integer; B: Integer = 0);'#10'    function Name: string;'#10'  end;'#10 +
    'procedure Versenden(const An, Betreff, Text: string);'#10'implementation'#10 +
    'procedure Versenden(const An, Betreff, Text: string);'#10'begin'#10'end;'#10 +
    'procedure TKunde.Senden;'#10'begin'#10'end;'#10'function TKunde.Name: string;'#10'begin'#10'end;'#10;

/// <summary>Unit Post mit Versenden und TKunde; ABody ist der Rumpf von Test(Kunde: TKunde) ab Zeile 21.</summary>
function Post(const ABody: string): string; overload;
begin
  Result := Kopf + 'procedure Test(Kunde: TKunde);'#10'begin'#10 + ABody + #10'end;'#10'end.';
end;

/// <summary>Wie oben, mit zusätzlichen Deklarationen vor Test.</summary>
function Post(const ADeclarations, ABody: string): string; overload;
begin
  Result := Kopf + ADeclarations + 'procedure Test(Kunde: TKunde);'#10'begin'#10 + ABody + #10'end;'#10'end.';
end;

function Findings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TArgumentCountMismatchRule.Create, ASource);
end;

function Findings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TArgumentCountMismatchRule.Create, ASource, AConfig, APath);
end;

function OnlyMessage(const ASource: string): string;
var
  Found: TArray<TRuleFinding>;
begin
  Found := Findings(ASource);
  Assert.AreEqual(1, Integer(Length(Found)), ASource);
  Result := Found[0].Message;
end;

procedure Silent(const ASource: string);
begin
  TRuleAssert.Silent(TArgumentCountMismatchRule.Create, ASource);
end;

{ TCallRulesTests }

procedure TCallRulesTests.IssueExample;
var
  Found: TArray<TRuleFinding>;
begin
  Found := Findings(Post('  Versenden(Kunde.Mail, ''Rechnung'');'));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(ArgumentCountMismatchRuleId, Found[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Found[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Found[0].Confidence));
  Assert.AreEqual('Versenden erwartet 3 Argumente, übergeben sind 2; Text fehlt (wie E2035).', Found[0].Message);
  Assert.AreEqual(21, Found[0].Range.StartPos.Line);
  Assert.AreEqual(2, Found[0].Range.StartPos.Character);
  Assert.AreEqual(35, Found[0].Range.EndPos.Character);
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual('Signaturhilfe öffnen', Found[0].Fixes[0].Title);
  Assert.IsTrue(Found[0].Fixes[0].HasJump);
  Assert.IsTrue(Found[0].Fixes[0].OpensSignature);
  Assert.AreEqual(0, Integer(Length(Found[0].Fixes[0].Edits)));
  // Vor die schließende Klammer: dort zeigt der Parameter-Hint den fehlenden Parameter.
  Assert.AreEqual(21, Found[0].Fixes[0].JumpTo.Line);
  Assert.AreEqual(34, Found[0].Fixes[0].JumpTo.Character);
  // Korrigiert und ein naheliegender Negativfall.
  Silent(Post('  Versenden(Kunde.Mail, ''Rechnung'', ''Text'');'));
  Silent(Post('  Kunde.Senden(1);'#10'  Kunde.Senden(1, 2);'));
  Assert.AreEqual('Versenden erwartet 3 Argumente, übergeben ist 1; Betreff und Text fehlen (wie E2035).',
    OnlyMessage(Post('  Versenden(Kunde.Mail);')));
  Assert.AreEqual('Senden erwartet mindestens 1 Argument, übergeben ist keins; A fehlt (wie E2035).',
    OnlyMessage(Post('  Kunde.Senden();')));
end;

procedure TCallRulesTests.TooManyArguments;
var
  Found: TArray<TRuleFinding>;
begin
  Found := Findings(Post('  Kunde.Senden(1, 2, 3);'));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Senden erwartet höchstens 2 Argumente, übergeben sind 3 (wie E2034).', Found[0].Message);
  // Markiert wird das überzählige Argument.
  Assert.AreEqual(21, Found[0].Range.StartPos.Line);
  Assert.AreEqual(21, Found[0].Range.StartPos.Character);
  Assert.AreEqual(22, Found[0].Range.EndPos.Character);
  Assert.AreEqual('Versenden erwartet 3 Argumente, übergeben sind 4 (wie E2034).',
    OnlyMessage(Post('  Versenden(''a'', ''b'', ''c'', ''d'');')));
  Assert.AreEqual('Name erwartet keine Argumente, übergeben ist 1 (wie E2034).',
    OnlyMessage(Post('  if Kunde.Name(1) = '''' then'#10'    Exit;')));
end;

procedure TCallRulesTests.StatementWithoutParentheses;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Post('  Versenden;');
  Found := Findings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Versenden erwartet 3 Argumente, übergeben ist keins; An, Betreff und Text fehlen (wie E2035).',
    Found[0].Message);
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes[0].Edits)));
  Assert.AreEqual('()', Found[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual(21, Found[0].Fixes[0].Edits[0].Range.StartPos.Line);
  Assert.AreEqual(11, Found[0].Fixes[0].Edits[0].Range.StartPos.Character);
  // Nach dem Einfügen steht die Schreibmarke zwischen den Klammern.
  Assert.AreEqual(12, Found[0].Fixes[0].JumpTo.Character);
  Fixed := StringReplace(Source, '  Versenden;', '  Versenden();', []);
  Assert.AreEqual(1, Integer(Length(Findings(Fixed))));
  // Ohne Pflichtparameter darf die Klammer fehlen.
  Silent(Post('  Kunde.Senden(1);'#10'  Kunde.Name;'));
  Assert.AreEqual('Senden erwartet mindestens 1 Argument, übergeben ist keins; A fehlt (wie E2035).',
    OnlyMessage(Post('  Kunde.Senden;')));
end;

procedure TCallRulesTests.NestedRoutine;
begin
  Assert.AreEqual('Teilen erwartet 2 Argumente, übergeben ist 1; Rest fehlt (wie E2035).', OnlyMessage(
    'unit Lokal;'#10'interface'#10'implementation'#10'procedure Aussen;'#10 +
    '  procedure Teilen(Wert: Integer; var Rest: Integer);'#10'  begin'#10'  end;'#10'var'#10'  R: Integer;'#10 +
    'begin'#10'  Teilen(7);'#10'  Teilen(7, R);'#10'end;'#10'end.'));
  // Überladene verschachtelte Routinen bleiben beim Compiler.
  Silent('unit Lokal;'#10'interface'#10'implementation'#10'procedure Aussen;'#10 +
    '  procedure Teilen(Wert: Integer); overload;'#10'  begin'#10'  end;'#10 +
    '  procedure Teilen(Wert, Rest: Integer); overload;'#10'  begin'#10'  end;'#10 +
    'begin'#10'  Teilen(7);'#10'  Teilen(7, 1);'#10'end;'#10'end.');
end;

procedure TCallRulesTests.RoutineFromIndex;
var
  Index: ISymbolIndex;
  Found: TArray<TRuleFinding>;
  Source: string;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText('unit Mailer;'#10'interface'#10 +
    'procedure Versenden(const An, Betreff: string; const Text: string = '''');'#10 +
    'function Format(const F: string; const Args: array of const): string; overload;'#10 +
    'function Format(const F: string): string; overload;'#10 +
    'function Summe(A: Integer): Integer; cdecl; varargs;'#10 +
    'implementation'#10'end.', 'C:\Projekt\Mailer.pas', nil));
  Source := 'unit Kunden;'#10'interface'#10'implementation'#10'uses'#10'  Mailer;'#10'procedure Test;'#10 +
    'begin'#10'  Versenden(''a'');'#10'  Versenden(''a'', ''b'');'#10'  Mailer.Versenden(''a'', ''b'', ''c'', ''d'');'#10 +
    '  Format(''x'', [1], 2);'#10'  Summe(1, 2, 3);'#10'end;'#10'end.';
  Found := TRuleAssert.IndexFindings(TArgumentCountMismatchRule.Create, Source, Index, '', '');
  Assert.AreEqual(2, Integer(Length(Found)));
  Assert.AreEqual('Versenden erwartet mindestens 2 Argumente, übergeben ist 1; Betreff fehlt (wie E2035).',
    Found[0].Message);
  Assert.AreEqual('Versenden erwartet höchstens 3 Argumente, übergeben sind 4 (wie E2034).', Found[1].Message);
end;

procedure TCallRulesTests.AncestorOverloads;
var
  mIndex: ISymbolIndex;
  mFound: TArray<TRuleFinding>;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText('unit Verbindung;'#10'interface'#10'type'#10'  TVerbindung = class'#10 +
    '  public'#10'    procedure Trennen; overload;'#10'    procedure Trennen(AMelden: Boolean); overload; virtual;'#10 +
    '    function Senden(ABefehl: string; const AAntwort: SmallInt = -1): SmallInt; overload;'#10 +
    '    function Senden(ABefehl: string; const AAntworten: array of SmallInt): SmallInt; overload; virtual;'#10 +
    '  end;'#10'implementation'#10'end.', 'C:\Projekt\Verbindung.pas', nil));
  // Indy: TIdSMTP.Disconnect(Boolean) override neben TIdTCPConnection.Disconnect; overload.
  mFound := TRuleAssert.IndexFindings(TArgumentCountMismatchRule.Create, 'unit Post;'#10'interface'#10'uses'#10 +
    '  Verbindung;'#10'type'#10'  TPost = class(TVerbindung)'#10'  public'#10 +
    '    procedure Trennen(AMelden: Boolean); override;'#10 +
    '    function Senden(ABefehl: string; const AAntworten: array of SmallInt): SmallInt; override;'#10 +
    '    procedure Lauf;'#10'  end;'#10'  TNeu = class(TVerbindung)'#10'  public'#10 +
    '    procedure Trennen(AMelden: Boolean); overload;'#10'  end;'#10'implementation'#10 +
    'procedure TPost.Trennen(AMelden: Boolean);'#10'begin'#10'end;'#10 +
    'function TPost.Senden(ABefehl: string; const AAntworten: array of SmallInt): SmallInt;'#10'begin'#10 +
    '  Result := 0;'#10'end;'#10'procedure TPost.Lauf;'#10'begin'#10'  Trennen;'#10'  Senden(''MODE'');'#10 +
    '  Self.Trennen;'#10'end;'#10'procedure TNeu.Trennen(AMelden: Boolean);'#10'begin'#10'end;'#10 +
    'procedure Test(APost: TPost; ANeu: TNeu);'#10'begin'#10'  APost.Trennen;'#10'  ANeu.Trennen;'#10'end;'#10 +
    'end.', mIndex, '', '');
  Assert.AreEqual(0, Integer(Length(mFound)));
  // Gegenprobe: ohne overload und override verdeckt die neue Methode die des Vorfahren (wie E2035).
  mFound := TRuleAssert.IndexFindings(TArgumentCountMismatchRule.Create, 'unit Post;'#10'interface'#10'uses'#10 +
    '  Verbindung;'#10'type'#10'  TVerdeckt = class(TVerbindung)'#10'  public'#10 +
    '    procedure Trennen(AMelden: Boolean);'#10'  end;'#10'implementation'#10 +
    'procedure TVerdeckt.Trennen(AMelden: Boolean);'#10'begin'#10'end;'#10 +
    'procedure Test(AVerdeckt: TVerdeckt);'#10'begin'#10'  AVerdeckt.Trennen;'#10'end;'#10'end.', mIndex, '', '');
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Trennen erwartet 1 Argument, übergeben ist keins; AMelden fehlt (wie E2035).', mFound[0].Message);
end;

procedure TCallRulesTests.ClassReferenceConstructor;
var
  mIndex: ISymbolIndex;
  mFound: TArray<TRuleFinding>;
begin
  // Wie System und System.SysUtils: TObject.Create ohne, Exception.Create mit einem Parameter.
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText('unit Fehler;'#10'interface'#10'type'#10'  TObject = class'#10 +
    '    constructor Create;'#10'  end;'#10'  Exception = class(TObject)'#10 +
    '    constructor Create(const Msg: string);'#10'  end;'#10'  ExceptClass = class of Exception;'#10 +
    '  TFehlerKlasse = ExceptClass;'#10'implementation'#10'end.', 'C:\Projekt\Fehler.pas', nil));
  // Feld, Parameter und Alias einer Klassenreferenz aus dem Index.
  mFound := TRuleAssert.IndexFindings(TArgumentCountMismatchRule.Create, 'unit Regeln;'#10'interface'#10'uses'#10 +
    '  Fehler;'#10'type'#10'  TRegel = class'#10'  private'#10'    FError: ExceptClass;'#10'  public'#10 +
    '    procedure Check(AKlasse: TFehlerKlasse);'#10'  end;'#10'implementation'#10 +
    'procedure TRegel.Check(AKlasse: TFehlerKlasse);'#10'begin'#10'  if AKlasse = nil then'#10 +
    '    raise AKlasse.Create(''Fehlt'');'#10'  raise FError.Create(''Regel gescheitert'');'#10 +
    '  FError.Create;'#10'  raise AKlasse.Create(''a'', ''b'');'#10'end;'#10'end.', mIndex, '', '');
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual('Create erwartet 1 Argument, übergeben ist keins; Msg fehlt (wie E2035).', mFound[0].Message);
  Assert.AreEqual(17, mFound[0].Range.StartPos.Line);
  Assert.AreEqual('Create erwartet 1 Argument, übergeben sind 2 (wie E2034).', mFound[1].Message);
  Assert.AreEqual(18, mFound[1].Range.StartPos.Line);
  // Klassenreferenz in derselben Datei; über den Typ selbst (TFehler.Create) wie bisher.
  Silent('unit Lokal;'#10'interface'#10'type'#10'  TObject = class'#10'    constructor Create;'#10'  end;'#10 +
    '  TFehler = class(TObject)'#10'    constructor Create(const AText: string);'#10'  end;'#10 +
    '  TFehlerKlasse = class of TFehler;'#10'implementation'#10'constructor TObject.Create;'#10'begin'#10'end;'#10 +
    'constructor TFehler.Create(const AText: string);'#10'begin'#10'end;'#10 +
    'procedure Test(AKlasse: TFehlerKlasse);'#10'begin'#10'  AKlasse.Create(''x'').Free;'#10 +
    '  TFehler.Create(''y'');'#10'end;'#10'end.');
end;

procedure TCallRulesTests.UnknownAncestorMayHideName;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := TRuleAssert.Findings(TArgumentCountMismatchRule.Create, 'unit Tags;'#10'interface'#10'uses'#10 +
    '  System.Classes;'#10'type'#10'  TTagStrom = class(TMemoryStream)'#10'  end;'#10'  TRahmen = class'#10 +
    '  public'#10'    procedure Read;'#10'    procedure Lesen(AStrom: TTagStrom);'#10'  end;'#10 +
    '  TListe = class(TStrings)'#10'  public'#10'    procedure Holen(AIndex: Integer);'#10'  end;'#10 +
    'procedure Error(const AText: string);'#10'implementation'#10'procedure Error(const AText: string);'#10 +
    'begin'#10'end;'#10'procedure TRahmen.Read;'#10'begin'#10'end;'#10 +
    'procedure TRahmen.Lesen(AStrom: TTagStrom);'#10'var'#10'  mWert: Byte;'#10'begin'#10'  with AStrom do'#10 +
    '    Read(mWert, 1);'#10'end;'#10'procedure TListe.Holen(AIndex: Integer);'#10'begin'#10 +
    '  Error(''Index'', AIndex);'#10'end;'#10'end.');
  Assert.AreEqual(0, Integer(Length(mFound)));
  // Gegenprobe: Ohne unbekannten Vorfahren meinen beide Namen die Routinen der Unit.
  mFound := TRuleAssert.Findings(TArgumentCountMismatchRule.Create, 'unit Tags;'#10'interface'#10'type'#10 +
    '  TTagStrom = class'#10'  end;'#10'  TRahmen = class'#10'  public'#10'    procedure Read;'#10 +
    '    procedure Lesen(AStrom: TTagStrom);'#10'  end;'#10'  TListe = class'#10'  public'#10 +
    '    procedure Holen(AIndex: Integer);'#10'  end;'#10'procedure Error(const AText: string);'#10 +
    'implementation'#10'procedure Error(const AText: string);'#10'begin'#10'end;'#10 +
    'procedure TRahmen.Read;'#10'begin'#10'end;'#10'procedure TRahmen.Lesen(AStrom: TTagStrom);'#10'var'#10 +
    '  mWert: Byte;'#10'begin'#10'  with AStrom do'#10'    Read(mWert, 1);'#10'end;'#10 +
    'procedure TListe.Holen(AIndex: Integer);'#10'begin'#10'  Error(''Index'', AIndex);'#10'end;'#10'end.');
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual('Read erwartet keine Argumente, übergeben sind 2 (wie E2034).', mFound[0].Message);
  Assert.AreEqual('Error erwartet 1 Argument, übergeben sind 2 (wie E2034).', mFound[1].Message);
end;

procedure TCallRulesTests.SilentCases;
begin
  // Überladungen, auch in derselben Unit.
  Silent(Post('function Teil(A: Integer): Integer; overload;'#10'begin'#10'  Result := A;'#10'end;'#10 +
    'function Teil(A, B: Integer): Integer; overload;'#10'begin'#10'  Result := A + B;'#10'end;'#10,
    '  Teil(1, 2, 3);'));
  // Typumwandlung, prozedurale Variable, Property und Bezeichner von System.
  Silent(Post('type'#10'  TMelden = procedure(A, B: Integer);'#10'var'#10'  Melden: TMelden;'#10,
    '  TKunde(Kunde).Senden(1);'#10'  Melden(1);'#10'  Writeln(1, 2, 3);'#10'  Inc(Kunde.Mail);'#10 +
    '  Exit(1);'));
  // Unbekannte Routinen und Aufrufe über das Ergebnis.
  Silent(Post('  Unbekannt(1, 2);'#10'  Kunde.Fehlt(1);'#10'  inherited Senden(1, 2, 3);'));
  // Funktion mit prozeduralem bzw. unbekanntem Ergebnistyp: F(1) könnte das Ergebnis aufrufen.
  Silent(Post('type'#10'  TMelden = reference to procedure(A: Integer);'#10 +
    'function Melder: TMelden;'#10'begin'#10'end;'#10'function Fremd: TFremd;'#10'begin'#10'end;'#10,
    '  Melder(1);'#10'  Fremd(1);'));
  // Bedingte Deklarationen mit verschiedenen Listen.
  Silent(Post('{$IFDEF ALT}'#10'procedure Alt(A: Integer);'#10'begin'#10'end;'#10'{$ELSE}'#10 +
    'procedure Alt;'#10'begin'#10'end;'#10'{$ENDIF}'#10, '  Alt;'));
  Silent(Post('{$IFDEF ALT}'#10'procedure Neu(A: Integer);'#10'{$ELSE}'#10'procedure Neu(A, B: Integer);'#10 +
    '{$ENDIF}'#10'begin'#10'end;'#10, '  Neu(1);'#10'  Neu(1, 2);'));
  // Gleichnamige Methode im Nachfahren mit anderer Liste: Verdeckung klärt der Compiler.
  Silent('unit Erben;'#10'interface'#10'type'#10'  TBasis = class'#10'    procedure Melden(A: Integer);'#10 +
    '  end;'#10'  TKind = class(TBasis)'#10'    procedure Melden(A, B: Integer); overload;'#10'  end;'#10 +
    'implementation'#10'procedure TBasis.Melden(A: Integer);'#10'begin'#10'end;'#10 +
    'procedure TKind.Melden(A, B: Integer);'#10'begin'#10'end;'#10'procedure Test(K: TKind);'#10 +
    'begin'#10'  K.Melden(1);'#10'end;'#10'end.');
end;

procedure TCallRulesTests.SignatureHelpAction;
var
  Source: string;
  Found: TArray<TRuleFinding>;
  Actions: TArray<TCodeAction>;
begin
  Source := Post('  Versenden(Kunde.Mail, ''Rechnung'');');
  Found := Findings(Source);
  Actions := TRuleCodeActions.ForFindings(Found, Source, Found[0].Range);
  Assert.AreEqual('Signaturhilfe öffnen', Actions[0].Title);
  Assert.AreEqual(ShowSignatureHelpCommand, Actions[0].Command);
  Assert.AreEqual(2, Integer(Length(Actions[0].CommandArguments)));
  Assert.AreEqual('21', Actions[0].CommandArguments[0]);
  Assert.AreEqual('34', Actions[0].CommandArguments[1]);
  Assert.AreEqual(RuleFixTag, Actions[0].Tag);
  // Ein gewöhnlicher Sprung bleibt atlas.goToPosition.
  Found[0].Fixes[0].OpensSignature := False;
  Actions := TRuleCodeActions.ForFindings(Found, Source, Found[0].Range);
  Assert.AreEqual(GoToPositionCommand, Actions[0].Command);
end;

procedure TCallRulesTests.HeaderParts;
var
  Parameters, Tail: string;
begin
  Assert.IsTrue(TArgumentCountMismatchRule.SplitHeader('procedure Versenden(const An, Betreff: string)',
    Parameters, Tail));
  Assert.AreEqual('const An, Betreff: string', Parameters);
  Assert.AreEqual('', Tail);
  Assert.IsTrue(TArgumentCountMismatchRule.SplitHeader('function Liste<T: class>(A: TArray<T>; B: Integer = ' +
    'Ord(''('')): T; overload', Parameters, Tail));
  Assert.AreEqual('A: TArray<T>; B: Integer = Ord(''('')', Parameters);
  Assert.AreEqual(': T; overload', Tail);
  Assert.IsTrue(TArgumentCountMismatchRule.SplitHeader('function Zahl: Integer; deprecated ''(alt)''', Parameters,
    Tail));
  Assert.AreEqual('', Parameters);
  Assert.AreEqual(': Integer; deprecated ''(alt)''', Tail);
  Assert.AreEqual('', TArgumentCountMismatchRule.MissingText(nil));
  Assert.AreEqual('Text fehlt', TArgumentCountMismatchRule.MissingText(['Text']));
  Assert.AreEqual('A, B und C fehlen', TArgumentCountMismatchRule.MissingText(['A', 'B', 'C']));
end;

procedure TCallRulesTests.Options;
var
  Source: string;
begin
  Source := Post('  Versenden(Kunde.Mail);');
  Assert.AreEqual(1, Integer(Length(Findings(Source, '', 'Source/Post.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(Source, '{"rules": {"argument-count-mismatch": "off"}}',
    'Source/Post.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(Source, '{"rules": {"group:compiler": "off"}}', 'Source/Post.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(Source,
    '{"rules": {"argument-count-mismatch": {"exclude": ["Source/*.pas"]}}}', 'Source/Post.pas'))));
  Assert.AreEqual(1, Integer(Length(Findings(Source,
    '{"rules": {"argument-count-mismatch": {"exclude": ["Alt/*.pas"]}}}', 'Source/Post.pas'))));
end;

{ TOverloadResolutionTests }

const
  cSystem = 'unit System;'#10'interface'#10'type'#10'  TObject = class'#10'  end;'#10'implementation'#10'end.';
  // Zeilen 0–8; Fall beginnt nach den Deklarationen.
  cNimm = 'unit Faelle;'#10'interface'#10'implementation'#10'procedure Nimm(AWert: Integer); overload;'#10 +
    'begin'#10'end;'#10'procedure Nimm(const AWert: string); overload;'#10'begin'#10'end;'#10;
  cFall = 'procedure Fall(AZahl: Double; AFlag: Boolean; AText: string; AZeichen: Char; AWert: Variant);'#10 +
    'begin'#10;

/// <summary>Index mit einer kleinen Unit System: Ohne sie schweigt overload-resolution.</summary>
function SystemIndex: ISymbolIndex;
begin
  Result := TSymbolIndex.Create;
  Result.AddUnit(TIndexExtractor.ExtractText(cSystem, 'C:\Delphi\System.pas', nil));
end;

/// <summary>Unit mit den beiden Überladungen von Nimm (Integer, string), ADeclarations und Fall mit ABody.</summary>
function NimmUnit(const ADeclarations, ABody: string): string;
begin
  Result := cNimm + ADeclarations + cFall + ABody + #10'end;'#10'end.';
end;

/// <summary>Unit mit ADeclarations und Fall mit ABody, ohne Nimm.</summary>
function FallUnit(const ADeclarations, ABody: string): string;
begin
  Result := 'unit Faelle;'#10'interface'#10'implementation'#10 + ADeclarations + cFall + ABody + #10'end;'#10'end.';
end;

function OverloadFindings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.IndexFindings(TOverloadResolutionRule.Create, ASource, SystemIndex, '', '');
end;

function OverloadFindings(const ASource: string; const AIndex: ISymbolIndex): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.IndexFindings(TOverloadResolutionRule.Create, ASource, AIndex, '', '');
end;

function OverloadMessage(const ASource: string): string;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := OverloadFindings(ASource);
  Assert.AreEqual(1, Integer(Length(mFound)), ASource);
  Result := mFound[0].Message;
end;

procedure OverloadSilent(const ASource: string); overload;
begin
  Assert.AreEqual(0, Integer(Length(OverloadFindings(ASource))), ASource);
end;

procedure OverloadSilent(const ASource: string; const AIndex: ISymbolIndex); overload;
begin
  Assert.AreEqual(0, Integer(Length(OverloadFindings(ASource, AIndex))), ASource);
end;

procedure TOverloadResolutionTests.NoOverloadFits;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := OverloadFindings(NimmUnit('', '  Nimm(1.5);'));
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(OverloadResolutionRuleId, mFound[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(mFound[0].Severity));
  Assert.AreEqual('Keine der 2 Überladungen von Nimm passt zu den Argumenten (Extended) (wie E2250).',
    mFound[0].Message);
  Assert.AreEqual(11, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(2, mFound[0].Range.StartPos.Character);
  Assert.AreEqual(11, mFound[0].Range.EndPos.Character);
  Assert.AreEqual('Signaturhilfe öffnen', mFound[0].Fixes[0].Title);
  Assert.IsTrue(mFound[0].Fixes[0].OpensSignature);
  Assert.AreEqual(10, mFound[0].Fixes[0].JumpTo.Character);
  Assert.AreEqual('Keine der 2 Überladungen von Nimm passt zu den Argumenten (Double) (wie E2250).',
    OverloadMessage(NimmUnit('', '  Nimm(AZahl);')));
  Assert.AreEqual('Keine der 2 Überladungen von Nimm passt zu den Argumenten (Boolean) (wie E2250).',
    OverloadMessage(NimmUnit('', '  Nimm(AFlag);')));
  Assert.AreEqual('Keine der 2 Überladungen von Nimm passt zu den Argumenten (Integer, Integer) (wie E2250).',
    OverloadMessage(NimmUnit('', '  Nimm(1, 2);')));
  Assert.AreEqual('Keine der 2 Überladungen von Nimm lässt sich ohne Argumente aufrufen (wie E2250).',
    OverloadMessage(NimmUnit('', '  Nimm;')));
  // Gegenfälle: Ganzzahl, string, Char und Char-Literal passen.
  OverloadSilent(NimmUnit('', '  Nimm(1);'#10'  Nimm(''Text'');'#10'  Nimm(AText);'#10'  Nimm(''a'');'#10 +
    '  Nimm(AZeichen);'#10'  Nimm(Length(AText));'));
end;

procedure TOverloadResolutionTests.AmbiguousCall;
const
  cZwei = 'procedure Zwei(AWert: Integer; AText: string = ''''); overload;'#10'begin'#10'end;'#10 +
    'procedure Zwei(AWert: Integer; AZahl: Integer = 0); overload;'#10'begin'#10'end;'#10;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := OverloadFindings(FallUnit(cZwei, '  Zwei(1);'));
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Aufruf von Zwei ist mehrdeutig: (AWert: Integer; AText: string = '''') und ' +
    '(AWert: Integer; AZahl: Integer = 0) passen gleich gut (wie E2251).', mFound[0].Message);
  // Beispiel der Delphi-Hilfe zu Standardparametern und Überladungen.
  Assert.AreEqual('Aufruf von Verwirrt ist mehrdeutig: (I: Integer) und (I: Integer; J: Integer = 0) passen ' +
    'gleich gut (wie E2251).', OverloadMessage(FallUnit('procedure Verwirrt(I: Integer); overload;'#10'begin'#10 +
    'end;'#10'procedure Verwirrt(I: Integer; J: Integer = 0); overload;'#10'begin'#10'end;'#10, '  Verwirrt(1);')));
  Assert.AreEqual('Aufruf von Zwei ist mehrdeutig: (AWert: Integer; AText: string = ''''), ' +
    '(AWert: Integer; AZahl: Integer = 0) und (AWert: Integer; AFlag: Boolean = False) passen gleich gut ' +
    '(wie E2251).', OverloadMessage(FallUnit(cZwei + 'procedure Zwei(AWert: Integer; AFlag: Boolean = False); ' +
    'overload;'#10'begin'#10'end;'#10, '  Zwei(1);')));
  // Gegenfälle: weitere Argumente entscheiden; verschiedene Typen entscheidet dcc nach der besseren Umwandlung.
  OverloadSilent(FallUnit(cZwei, '  Zwei(1, ''x'');'#10'  Zwei(1, 2);'));
  OverloadSilent(FallUnit('procedure Wahl(AWert: Integer; AText: string = ''''); overload;'#10'begin'#10'end;'#10 +
    'procedure Wahl(AWert: Double; AZahl: Integer = 0); overload;'#10'begin'#10'end;'#10, '  Wahl(1);'));
  // Die zweite Überladung steht erst hinter dem Aufruf: dcc sieht sie dort nicht.
  OverloadSilent('unit Faelle;'#10'interface'#10'implementation'#10 +
    'procedure Spaet(AWert: Integer; AText: string = ''''); overload;'#10'begin'#10'end;'#10 + cFall +
    '  Spaet(1);'#10'end;'#10'procedure Spaet(AWert: Integer; AZahl: Integer = 0); overload;'#10'begin'#10'end;'#10 +
    'end.');
  // var gegen Wert und ein Argument, dessen Typ nicht genau der des Parameters ist.
  OverloadSilent(FallUnit('procedure Teil(var AWert: Integer; AText: string = ''''); overload;'#10'begin'#10 +
    'end;'#10'procedure Teil(AWert: Integer; AZahl: Integer = 0); overload;'#10'begin'#10'end;'#10 +
    'procedure Breit(AWert: Int64; AText: string = ''''); overload;'#10'begin'#10'end;'#10 +
    'procedure Breit(AWert: Int64; AZahl: Integer = 0); overload;'#10'begin'#10'end;'#10,
    '  Teil(1);'#10'  Breit(1);'));
end;

procedure TOverloadResolutionTests.MethodOverloads;
const
  cRechner = 'unit Faelle;'#10'interface'#10'type'#10'  TRechner = class'#10'  public'#10 +
    '    procedure Merke(AWert: Integer); overload;'#10'    procedure Merke(const AText: string); overload;'#10 +
    '    procedure Teile(AWert: Integer; ARest: Integer = 0); overload;'#10 +
    '    procedure Teile(AWert: Integer; const AText: string = ''''); overload;'#10'    procedure Lauf;'#10 +
    '  end;'#10'  TBasis = class'#10'  public'#10'    procedure Nenne(AWert: Integer); overload;'#10 +
    '    procedure Zaehle(AWert: Integer); overload;'#10'  end;'#10'  TKind = class(TBasis)'#10'  public'#10 +
    '    procedure Nenne(const AText: string); overload;'#10 +
    '    procedure Zaehle(AWert: Integer; ARest: Integer = 0); overload;'#10'  end;'#10'implementation'#10 +
    'procedure TRechner.Merke(AWert: Integer);'#10'begin'#10'end;'#10 +
    'procedure TRechner.Merke(const AText: string);'#10'begin'#10'end;'#10 +
    'procedure TRechner.Teile(AWert: Integer; ARest: Integer);'#10'begin'#10'end;'#10 +
    'procedure TRechner.Teile(AWert: Integer; const AText: string);'#10'begin'#10'end;'#10 +
    'procedure TRechner.Lauf;'#10'begin'#10'  Merke(True);'#10'end;'#10 +
    'procedure TBasis.Nenne(AWert: Integer);'#10'begin'#10'end;'#10 +
    'procedure TBasis.Zaehle(AWert: Integer);'#10'begin'#10'end;'#10 +
    'procedure TKind.Nenne(const AText: string);'#10'begin'#10'end;'#10 +
    'procedure TKind.Zaehle(AWert: Integer; ARest: Integer);'#10'begin'#10'end;'#10 +
    'procedure Test(ARechner: TRechner; AKind: TKind);'#10'begin'#10;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := OverloadFindings(cRechner + '  ARechner.Merke(1.5);'#10'  ARechner.Teile(1);'#10 +
    '  AKind.Nenne(1.5);'#10'end;'#10'end.');
  Assert.AreEqual(4, Integer(Length(mFound)));
  Assert.AreEqual('Keine der 2 Überladungen von Merke passt zu den Argumenten (Boolean) (wie E2250).',
    mFound[0].Message);
  Assert.AreEqual('Keine der 2 Überladungen von Merke passt zu den Argumenten (Extended) (wie E2250).',
    mFound[1].Message);
  Assert.AreEqual('Aufruf von Teile ist mehrdeutig: (AWert: Integer; ARest: Integer = 0) und ' +
    '(AWert: Integer; const AText: string = '''') passen gleich gut (wie E2251).', mFound[2].Message);
  // Überladungen aus dem Vorfahren zählen mit.
  Assert.AreEqual('Keine der 2 Überladungen von Nenne passt zu den Argumenten (Extended) (wie E2250).',
    mFound[3].Message);
  // Gegenfälle; Überladungen aus verschiedenen Klassen der Hierarchie gelten nie als mehrdeutig.
  mFound := OverloadFindings(cRechner + '  ARechner.Merke(1);'#10'  ARechner.Teile(1, 2);'#10 +
    '  AKind.Nenne(1);'#10'  AKind.Nenne(''x'');'#10'  AKind.Zaehle(1);'#10'end;'#10'end.');
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Keine der 2 Überladungen von Merke passt zu den Argumenten (Boolean) (wie E2250).',
    mFound[0].Message);
end;

procedure TOverloadResolutionTests.AliasesAndOperators;
const
  cTypen = 'type'#10'  TText = string;'#10'  TZahl = Integer;'#10'  TBetrag = record'#10 +
    '    class operator Implicit(AWert: Double): TBetrag;'#10'  end;'#10 +
    'class operator TBetrag.Implicit(AWert: Double): TBetrag;'#10'begin'#10'end;'#10 +
    'procedure Nenne(const AText: TText); overload;'#10'begin'#10'end;'#10 +
    'procedure Nenne(AWert: TZahl); overload;'#10'begin'#10'end;'#10 +
    'procedure Buche(const ABetrag: TBetrag); overload;'#10'begin'#10'end;'#10 +
    'procedure Buche(const AText: string); overload;'#10'begin'#10'end;'#10;
begin
  Assert.AreEqual('Keine der 2 Überladungen von Nenne passt zu den Argumenten (Extended) (wie E2250).',
    OverloadMessage(FallUnit(cTypen, '  Nenne(1.5);')));
  OverloadSilent(FallUnit(cTypen, '  Nenne(1);'#10'  Nenne(AText);'#10'  Buche(1.5);'#10'  Buche(AZahl);'));
end;

procedure TOverloadResolutionTests.CompilerAccepts;
begin
  // UL1–UL7 aus Tests/DccFaelle/Dcc.Ueberladungen.pas.
  OverloadSilent(NimmUnit('procedure Zahl(AWert: Double); overload;'#10'begin'#10'end;'#10 +
    'procedure Zahl(const AText: string); overload;'#10'begin'#10'end;'#10 +
    'procedure Zeichen(AWert: Char); overload;'#10'begin'#10'end;'#10 +
    'procedure Zeichen(AWert: Integer); overload;'#10'begin'#10'end;'#10 +
    'const'#10'  cZeichen = ''a'';'#10,
    '  Nimm(1);'#10'  Nimm(''Text'');'#10'  Nimm(''a'');'#10'  Zahl(1);'#10'  Zahl(AZahl);'#10 +
    '  Zeichen(cZeichen);'#10'  Zeichen(''b'');'));
end;

procedure TOverloadResolutionTests.IncompleteCandidates;
var
  mIndex: ISymbolIndex;
begin
  // Ohne System im Index.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TOverloadResolutionRule.Create,
    NimmUnit('', '  Nimm(1.5);')))));
  // Unbekannte Unit in uses: Sie kann weitere Überladungen von Nimm deklarieren.
  OverloadSilent(StringReplace(NimmUnit('', '  Nimm(1.5);'), 'implementation'#10, 'implementation'#10'uses'#10 +
    '  Fremd;'#10, []));
  // Eine andere Unit deklariert Nimm: dcc nimmt deren Überladungen mit.
  mIndex := SystemIndex;
  mIndex.AddUnit(TIndexExtractor.ExtractText('unit Fremd;'#10'interface'#10'procedure Nimm(AWert: Double); ' +
    'overload;'#10'implementation'#10'procedure Nimm(AWert: Double);'#10'begin'#10'end;'#10'end.',
    'C:\Projekt\Fremd.pas', nil));
  OverloadSilent(StringReplace(NimmUnit('', '  Nimm(1.5);'), 'implementation'#10, 'implementation'#10'uses'#10 +
    '  Fremd;'#10, []), mIndex);
  // Gegenprobe: Ohne Fremd in uses sieht dcc dessen Nimm nicht.
  Assert.AreEqual(1, Integer(Length(OverloadFindings(NimmUnit('', '  Nimm(1.5);'), mIndex))));
  // Gegenprobe: Fremd ohne Nimm.
  mIndex := SystemIndex;
  mIndex.AddUnit(TIndexExtractor.ExtractText('unit Fremd;'#10'interface'#10'implementation'#10'end.',
    'C:\Projekt\Fremd.pas', nil));
  Assert.AreEqual(1, Integer(Length(OverloadFindings(StringReplace(NimmUnit('', '  Nimm(1.5);'),
    'implementation'#10, 'implementation'#10'uses'#10'  Fremd;'#10, []), mIndex))));
  // Bedingte Überladung, with, unbekannter Vorfahr, verschachtelte und generische Routinen, keine Überladung.
  OverloadSilent(NimmUnit('{$IFDEF ALT}'#10'procedure Nimm(AWert: Double); overload;'#10'begin'#10'end;'#10 +
    '{$ENDIF}'#10, '  Nimm(1.5);'));
  OverloadSilent(NimmUnit('', '  with TObject.Create do'#10'    Nimm(1.5);'));
  OverloadSilent(NimmUnit('type'#10'  TFenster = class(TForm)'#10'    procedure Lauf;'#10'  end;'#10 +
    'procedure TFenster.Lauf;'#10'begin'#10'  Nimm(1.5);'#10'end;'#10, ''));
  OverloadSilent(FallUnit('procedure Aussen;'#10'  procedure Innen(AWert: Integer); overload;'#10'  begin'#10 +
    '  end;'#10'  procedure Innen(const AText: string); overload;'#10'  begin'#10'  end;'#10'begin'#10 +
    '  Innen(1.5);'#10'end;'#10, ''));
  OverloadSilent(FallUnit('type'#10'  TListe = class'#10'    procedure Add<T>(AWert: T); overload;'#10 +
    '    procedure Add(AWert: Integer); overload;'#10'  end;'#10'procedure TListe.Add<T>(AWert: T);'#10'begin'#10 +
    'end;'#10'procedure TListe.Add(AWert: Integer);'#10'begin'#10'end;'#10'procedure Lauf(AListe: TListe);'#10 +
    'begin'#10'  AListe.Add(1.5);'#10'end;'#10, ''));
  OverloadSilent(FallUnit('procedure Einzeln(AWert: Integer);'#10'begin'#10'end;'#10, '  Einzeln(1.5);'));
end;

procedure TOverloadResolutionTests.UncertainArguments;
begin
  OverloadSilent(NimmUnit('function Wert: Integer; overload;'#10'begin'#10'end;'#10 +
    'function Wert(AWert: Integer): Double; overload;'#10'begin'#10'end;'#10 +
    'procedure Zeiger(AText: PChar); overload;'#10'begin'#10'end;'#10 +
    'procedure Zeiger(AWert: Integer); overload;'#10'begin'#10'end;'#10 +
    'procedure Liste(const AWerte: array of Integer); overload;'#10'begin'#10'end;'#10 +
    'procedure Liste(AFlag: Boolean); overload;'#10'begin'#10'end;'#10 +
    'procedure Zeichen(AWert: Char); overload;'#10'begin'#10'end;'#10 +
    'procedure Zeichen(AWert: Integer); overload;'#10'begin'#10'end;'#10 +
    'const'#10'  cZeichen = ''a'';'#10,
    '  Nimm(AWert);'#10'  Nimm(Wert(1));'#10'  Zeiger(''abc'');'#10'  Liste([1]);'#10'  Liste(1.5);'#10 +
    '  Zeichen(cZeichen);'));
end;

procedure TOverloadResolutionTests.FitTable;
begin
  Assert.AreEqual(Ord(TArgumentFit.Fails), Ord(TOverloadResolutionRule.Fit(TExpressionCategory.Integer_,
    TExpressionCategory.Float)));
  Assert.AreEqual(Ord(TArgumentFit.Fits), Ord(TOverloadResolutionRule.Fit(TExpressionCategory.Float,
    TExpressionCategory.Integer_)));
  Assert.AreEqual(Ord(TArgumentFit.Fits), Ord(TOverloadResolutionRule.Fit(TExpressionCategory.Currency_,
    TExpressionCategory.Integer_)));
  Assert.AreEqual(Ord(TArgumentFit.Fits), Ord(TOverloadResolutionRule.Fit(TExpressionCategory.Float,
    TExpressionCategory.Currency_)));
  Assert.AreEqual(Ord(TArgumentFit.Fits), Ord(TOverloadResolutionRule.Fit(TExpressionCategory.String_,
    TExpressionCategory.Char_)));
  Assert.AreEqual(Ord(TArgumentFit.Fails), Ord(TOverloadResolutionRule.Fit(TExpressionCategory.Char_,
    TExpressionCategory.String_)));
  Assert.AreEqual(Ord(TArgumentFit.Fails), Ord(TOverloadResolutionRule.Fit(TExpressionCategory.Integer_,
    TExpressionCategory.Boolean_)));
  Assert.AreEqual(Ord(TArgumentFit.Fails), Ord(TOverloadResolutionRule.Fit(TExpressionCategory.String_,
    TExpressionCategory.Integer_)));
  Assert.AreEqual(Ord(TArgumentFit.Fits), Ord(TOverloadResolutionRule.Fit(TExpressionCategory.Variant_,
    TExpressionCategory.Boolean_)));
  Assert.AreEqual(Ord(TArgumentFit.Unknown), Ord(TOverloadResolutionRule.Fit(TExpressionCategory.Other,
    TExpressionCategory.Integer_)));
  Assert.AreEqual(Ord(TArgumentFit.Unknown), Ord(TOverloadResolutionRule.Fit(TExpressionCategory.Integer_,
    TExpressionCategory.Variant_)));
  Assert.AreEqual(Ord(TArgumentFit.Unknown), Ord(TOverloadResolutionRule.Fit(TExpressionCategory.Pointer_,
    TExpressionCategory.String_)));
  Assert.IsTrue(TOverloadResolutionRule.SameTypeName('Integer', 'LongInt'));
  Assert.IsTrue(TOverloadResolutionRule.SameTypeName('string', 'UnicodeString'));
  Assert.IsTrue(TOverloadResolutionRule.SameTypeName('System.Char', 'WideChar'));
  Assert.IsFalse(TOverloadResolutionRule.SameTypeName('Integer', 'Int64'));
  Assert.IsFalse(TOverloadResolutionRule.SameTypeName('', ''));
end;

procedure TOverloadResolutionTests.Options;
var
  mSource: string;
begin
  mSource := NimmUnit('', '  Nimm(1.5);');
  Assert.AreEqual(1, Integer(Length(TRuleAssert.IndexFindings(TOverloadResolutionRule.Create, mSource,
    SystemIndex, '', 'Source/Faelle.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.IndexFindings(TOverloadResolutionRule.Create, mSource,
    SystemIndex, '{"rules": {"overload-resolution": "off"}}', 'Source/Faelle.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.IndexFindings(TOverloadResolutionRule.Create, mSource,
    SystemIndex, '{"rules": {"group:compiler": "off"}}', 'Source/Faelle.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.IndexFindings(TOverloadResolutionRule.Create, mSource,
    SystemIndex, '{"rules": {"group:compiler": {"typeLevel": "off"}}}', 'Source/Faelle.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TCallRulesTests);
  TDUnitX.RegisterTestFixture(TOverloadResolutionTests);

end.
