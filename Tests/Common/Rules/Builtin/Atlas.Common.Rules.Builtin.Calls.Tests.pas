unit Atlas.Common.Rules.Builtin.Calls.Tests;

// Tests der Regel argument-count-mismatch (#1007): zu wenige und zu viele
// Argumente, Anweisung ohne Klammern, verschachtelte Routinen, Routinen aus
// dem Index, stille Fälle (Überladungen, varargs, Typumwandlungen,
// prozedurale Variablen, System), Korrektur „Signaturhilfe öffnen“ samt
// Client-Befehl und Einstellungen.

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
    [Test]
    procedure SilentCases;
    [Test]
    procedure SignatureHelpAction;
    [Test]
    procedure HeaderParts;
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

initialization
  TDUnitX.RegisterTestFixture(TCallRulesTests);

end.
