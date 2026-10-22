unit Atlas.Common.Rules.Builtin.RtlTypePatterns.Tests;

// Tests für die typbasierten Regeln zu RTL-Mustern aus #153, Stufe 2, und
// für die deklarierten Typen, auf denen sie aufbauen; zuletzt
// managed-type-raw-memory (#921) mit Records, Aliassen, Zeigern, Index und
// Korrekturen, threadvar-managed (#922) und pchar-of-temporary (#923).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRtlTypePatternRulesTests = class
  public
    [Test]
    procedure DeclaredTypesByScope;
    [Test]
    procedure Int32MulOverflow;
    [Test]
    procedure SizeOfPointer;
    [Test]
    procedure CharToPChar;
    [Test]
    procedure FloatEquality;
    [Test]
    procedure ConstructorOnInstance;
    [Test]
    procedure FormatWithoutSettings;
    [Test]
    procedure LocaleSpecifiers;
    [Test]
    procedure ManagedRawMemoryIssueExample;
    [Test]
    procedure ManagedRawMemoryKinds;
    [Test]
    procedure ManagedRawMemoryMoveAndPointers;
    [Test]
    procedure ManagedRawMemorySilentCases;
    [Test]
    procedure ManagedRawMemoryOffAndExclude;
    [Test]
    procedure ThreadvarManaged;
    [Test]
    procedure PCharOfTemporaryIssueExample;
    [Test]
    procedure PCharOfTemporaryVariants;
    [Test]
    procedure PCharOfTemporarySilentCases;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Pascal.DeclaredTypes,
  Atlas.Common.Rules.Builtin.RtlTypePatterns,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Tests.RuleAssert;

function InRoutine(const AVars, ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'var'#10 + AVars + #10'begin'#10 +
    ABody + #10'end;'#10'end.';
end;

procedure TRtlTypePatternRulesTests.DeclaredTypesByScope;
const
  Source = 'unit U;'#10'interface'#10'type'#10'  TFoo = class'#10'  private'#10'    FCount: Int64;'#10 +
    '    procedure Run(A: Integer; const S: string);'#10'  end;'#10'var'#10'  Global: Double;'#10 +
    'implementation'#10'procedure TFoo.Run(A: Integer; const S: string);'#10'var'#10'  L: TArray<Byte>;'#10 +
    'begin'#10'  var C: Char := ''x'';'#10'  FCount := A;'#10'end;'#10'end.';
var
  Tree: TSyntaxTree;
  Types: TDeclaredTypes;
  At: TTextPosition;
begin
  Tree := TPascalParser.Parse(Source);
  Types := TDeclaredTypes.Create(Tree, Source);
  try
    At := TTextPosition.Create(16, 4);
    Assert.AreEqual('Integer', Types.DeclaredType('A', At));
    Assert.AreEqual('string', Types.DeclaredType('s', At));
    Assert.AreEqual('TArray<Byte>', Types.DeclaredType('L', At));
    Assert.AreEqual('Char', Types.DeclaredType('C', At));
    Assert.AreEqual('Int64', Types.DeclaredType('FCount', At));
    Assert.AreEqual('Double', Types.DeclaredType('Global', At));
    Assert.AreEqual('', Types.DeclaredType('Unbekannt', At));
    // Vor der Inline-Deklaration ist C nicht bekannt.
    Assert.AreEqual('', Types.DeclaredType('C', TTextPosition.Create(14, 0)));
  finally
    Types.Free;
    Tree.Free;
  end;
end;

procedure TRtlTypePatternRulesTests.Int32MulOverflow;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TInt32MulOverflowRule.Create, InRoutine('  Total: Int64;'#10 +
    '  Width, Height: Integer;', '  Total := Width * Height;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Int64(Width)', Findings[0].Fixes[0].Edits[0].NewText);
  TRuleAssert.Reports(TInt32MulOverflowRule.Create, InRoutine('  Total: Int64;'#10'  N: Cardinal;',
    '  Total := N * 1000;'));
  TRuleAssert.Silent(TInt32MulOverflowRule.Create, InRoutine('  Total: Int64;'#10'  Width: Int64;'#10 +
    '  Height: Integer;'#10'  Area: Integer;', '  Total := Width * Height;'#10'  Area := Height * Height;'#10 +
    '  Total := Int64(Height) * Height;'));
end;

procedure TRtlTypePatternRulesTests.SizeOfPointer;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TSizeOfPointerRule.Create, InRoutine('  Buffer: TBytes;'#10'  P: PByte;',
    '  FillChar(Buffer[0], SizeOf(Buffer), 0);'#10'  Move(P^, Buffer[0], SizeOf(P));'));
  Assert.AreEqual(2, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Findings[0].Severity));
  TRuleAssert.Silent(TSizeOfPointerRule.Create, InRoutine('  R: TPoint;'#10'  A: array[0..9] of Byte;',
    '  FillChar(R, SizeOf(R), 0);'#10'  FillChar(A, SizeOf(A), 0);'#10'  FillChar(R, SizeOf(TPoint), 0);'));
end;

procedure TRtlTypePatternRulesTests.CharToPChar;
begin
  TRuleAssert.Reports(TCharToPCharRule.Create, InRoutine('  C: Char;', '  ShowMessage(PChar(C));'));
  TRuleAssert.Silent(TCharToPCharRule.Create, InRoutine('  S: string;'#10'  C: Char;',
    '  ShowMessage(PChar(S));'#10'  ShowMessage(PChar(string(C)));'));
end;

procedure TRtlTypePatternRulesTests.FloatEquality;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TFloatEqualityRule.Create, InRoutine('  A, B: Double;',
    '  if A = B then Save;'#10'  if A <> 1.5 then Save;'));
  Assert.AreEqual(2, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
  Assert.AreEqual('SameValue(A, B)', Findings[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual('not SameValue(A, 1.5)', Findings[1].Fixes[0].Edits[0].NewText);
  TRuleAssert.Silent(TFloatEqualityRule.Create, InRoutine('  A: Double;'#10'  N, M: Integer;',
    '  if A = 0 then Save;'#10'  if N = M then Save;'#10'  if A <> 0.0 then Save;'));
  // Zeitstempel werden absichtlich exakt verglichen (#647).
  TRuleAssert.Silent(TFloatEqualityRule.Create, InRoutine('  T, U: TDateTime;',
    '  if T <> U then Save;'));
end;

procedure TRtlTypePatternRulesTests.ConstructorOnInstance;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TConstructorOnInstanceRule.Create, InRoutine('  List: TStringList;',
    '  List.Create;'#10'  try'#10'  finally'#10'    List.Free;'#10'  end;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('TStringList', Findings[0].Fixes[0].Edits[0].NewText);
  TRuleAssert.Silent(TConstructorOnInstanceRule.Create, InRoutine('  List: TStringList;'#10 +
    '  Kind: TComponentClass;'#10'  C: TComponent;', '  List := TStringList.Create;'#10 +
    '  C := Kind.Create(nil);'#10'  inherited Create;'));
end;

procedure TRtlTypePatternRulesTests.FormatWithoutSettings;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TFormatWithoutSettingsRule.Create, InRoutine('  X: Double;',
    '  S := Format(''%.2f'', [X]);'#10'  S := FloatToStr(X);'#10'  D := StrToDate(S);'));
  Assert.AreEqual(3, Integer(Length(Findings)));
  Assert.AreEqual(', FormatSettings', Findings[0].Fixes[0].Edits[0].NewText);
  TRuleAssert.Silent(TFormatWithoutSettingsRule.Create, InRoutine('  N: Integer;',
    '  S := Format(''%d'', [N]);'#10'  S := Format(''%.2f'', [X], FS);'#10'  S := FloatToStr(X, FS);'#10 +
    '  S := Writer.Format(''%f'', [X]);'));
end;

procedure TRtlTypePatternRulesTests.LocaleSpecifiers;
begin
  Assert.IsTrue(TFormatWithoutSettingsRule.HasLocaleSpecifier('%.2f'));
  Assert.IsTrue(TFormatWithoutSettingsRule.HasLocaleSpecifier('Summe: %0:-10.2n'));
  Assert.IsTrue(TFormatWithoutSettingsRule.HasLocaleSpecifier('%m'));
  Assert.IsFalse(TFormatWithoutSettingsRule.HasLocaleSpecifier('%d %s %x'));
  Assert.IsFalse(TFormatWithoutSettingsRule.HasLocaleSpecifier('100%% fertig'));
end;

function WithTypes(const ATypes, AVars, ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'type'#10 + ATypes + #10'implementation'#10'procedure P;'#10'var'#10 +
    AVars + #10'begin'#10 + ABody + #10'end;'#10'end.';
end;

const
  Adresse = '  TAdresse = record'#10'    Strasse: string;'#10'    Ort: string;'#10'  end;'#10 +
    '  PAdresse = ^TAdresse;'#10'  TPunkt = record'#10'    X, Y: Integer;'#10'  end;';

procedure TRtlTypePatternRulesTests.ManagedRawMemoryIssueExample;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := WithTypes(Adresse, '  Adresse: TAdresse;', '  FillChar(Adresse, SizeOf(Adresse), 0);');
  Findings := TRuleAssert.Findings(TManagedTypeRawMemoryRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('TAdresse enthält Strings; FillChar überschreibt die Referenzen ohne Freigabe (Leck, ' +
    'ggf. Zugriffsverletzung).', Findings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual('Adresse := Default(TAdresse)', Findings[0].Fixes[0].Title);
  Fixed := TChangeSignature.ApplyEdits(Source, Findings[0].Fixes[0].Edits);
  Assert.AreEqual(WithTypes(Adresse, '  Adresse: TAdresse;', '  Adresse := Default(TAdresse);'), Fixed);
  TRuleAssert.Silent(TManagedTypeRawMemoryRule.Create, Fixed);
  // Record ohne verwaltete Felder: FillChar ist in Ordnung.
  TRuleAssert.Silent(TManagedTypeRawMemoryRule.Create, WithTypes(Adresse, '  Punkt: TPunkt;',
    '  FillChar(Punkt, SizeOf(Punkt), 0);'));
end;

procedure TRtlTypePatternRulesTests.ManagedRawMemoryKinds;
const
  Types = '  IKunde = interface'#10'  end;'#10'  TMitInterface = record'#10'    Kunde: IKunde;'#10'  end;'#10 +
    '  TMitArray = record'#10'    Werte: array of Integer;'#10'  end;'#10'  TMitVariant = record'#10 +
    '    Wert: Variant;'#10'  end;'#10'  TInnen = record'#10'    Name: string;'#10'  end;'#10 +
    '  TAussen = record'#10'    Innen: array[0..1] of TInnen;'#10'  end;'#10'  TAlias = TAussen;';

  function Message(const AVar, AType: string): string;
  var
    Findings: TArray<TRuleFinding>;
  begin
    Findings := TRuleAssert.Findings(TManagedTypeRawMemoryRule.Create, WithTypes(Types, '  ' + AVar + ': ' + AType +
      ';', '  ZeroMemory(@' + AVar + ', SizeOf(' + AVar + '));'));
    Result := '';
    if Length(Findings) = 1 then
      Result := Findings[0].Message;
  end;

begin
  Assert.StartsWith('TMitInterface enthält Interfaces; ZeroMemory', Message('A', 'TMitInterface'));
  Assert.StartsWith('TMitArray enthält dynamische Arrays;', Message('B', 'TMitArray'));
  Assert.StartsWith('TMitVariant enthält Variants;', Message('C', 'TMitVariant'));
  Assert.StartsWith('TAussen enthält Strings;', Message('D', 'TAussen'), 'statisches Array verschachtelter Records');
  Assert.StartsWith('TAlias enthält Strings;', Message('E', 'TAlias'), 'Alias');
  Assert.StartsWith('string ist ein verwalteter Typ;', Message('F', 'string'));
  Assert.StartsWith('TFormatSettings enthält Strings;', Message('G', 'TFormatSettings'), 'bekannter RTL-Record');
  Assert.AreEqual('', Message('H', 'Integer'));
  Assert.AreEqual('', Message('I', 'TUnbekannt'), 'unbekannter Typ: keine Aussage');
end;

procedure TRtlTypePatternRulesTests.ManagedRawMemoryMoveAndPointers;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := WithTypes(Adresse, '  A, B: TAdresse;', '  Move(A, B, SizeOf(TAdresse));');
  Findings := TRuleAssert.Findings(TManagedTypeRawMemoryRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('TAdresse enthält Strings; Move kopiert die Referenzen ohne Referenzzählung (doppelte Freigabe, ' +
    'ggf. Zugriffsverletzung).', Findings[0].Message);
  Assert.AreEqual(WithTypes(Adresse, '  A, B: TAdresse;', '  B := A;'),
    TChangeSignature.ApplyEdits(Source, Findings[0].Fixes[0].Edits));
  // GetMem und FreeMem über einen Zeiger auf den Record.
  Source := WithTypes(Adresse, '  P: PAdresse;', '  GetMem(P, SizeOf(TAdresse));'#10'  FreeMem(P);');
  Findings := TRuleAssert.Findings(TManagedTypeRawMemoryRule.Create, Source);
  Assert.AreEqual(2, Integer(Length(Findings)));
  Assert.AreEqual('TAdresse enthält Strings; GetMem lässt die Referenzen uninitialisiert (Zugriffsverletzung beim ' +
    'ersten Zuweisen); New oder Initialize verwenden.', Findings[0].Message);
  Assert.AreEqual('TAdresse enthält Strings; FreeMem gibt die Referenzen nicht frei (Leck); Dispose oder Finalize ' +
    'verwenden.', Findings[1].Message);
  Assert.AreEqual(WithTypes(Adresse, '  P: PAdresse;', '  New(P);'#10'  FreeMem(P);'),
    TChangeSignature.ApplyEdits(Source, Findings[0].Fixes[0].Edits));
  Assert.AreEqual(WithTypes(Adresse, '  P: PAdresse;', '  GetMem(P, SizeOf(TAdresse));'#10'  Dispose(P);'),
    TChangeSignature.ApplyEdits(Source, Findings[1].Fixes[0].Edits));
  // Dereferenzierter Zeiger: FillChar(P^, …) ohne Korrektur.
  Findings := TRuleAssert.Findings(TManagedTypeRawMemoryRule.Create, WithTypes(Adresse, '  P: ^TAdresse;',
    '  FillChar(P^, SizeOf(TAdresse), 0);'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
end;

procedure TRtlTypePatternRulesTests.ManagedRawMemorySilentCases;
begin
  // Element eines Arrays, Puffer aus Bytes, Methode eines Objekts.
  TRuleAssert.Silent(TManagedTypeRawMemoryRule.Create, WithTypes(Adresse,
    '  S: string;'#10'  Puffer: array[0..15] of Byte;'#10'  Liste: TListe;',
    '  FillChar(S[1], Length(S) * SizeOf(Char), '' '');'#10'  FillChar(Puffer, SizeOf(Puffer), 0);'#10 +
    '  Liste.Move(0, 1);'));
end;

procedure TRtlTypePatternRulesTests.ManagedRawMemoryOffAndExclude;
var
  Source: string;
begin
  Source := WithTypes(Adresse, '  Adresse: TAdresse;', '  FillChar(Adresse, SizeOf(Adresse), 0);');
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TManagedTypeRawMemoryRule.Create, Source,
    '{"rules": {"managed-type-raw-memory": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TManagedTypeRawMemoryRule.Create, Source,
    '{"rules": {"managed-type-raw-memory": {"exclude": ["Alt/*.pas"]}}}', 'Alt/U.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TManagedTypeRawMemoryRule.Create, Source,
    '{"rules": {"managed-type-raw-memory": {"exclude": ["Alt/*.pas"]}}}', 'Neu/U.pas'))));
end;

procedure TRtlTypePatternRulesTests.ThreadvarManaged;
const
  Head = 'unit U;'#10'interface'#10'type'#10'  TMeldung = record'#10'    Text: string;'#10'  end;'#10 +
    'implementation'#10;
var
  Findings: TArray<TRuleFinding>;
  Source: string;
begin
  Source := Head + 'threadvar'#10'  LetzteMeldung: string;'#10'  Zaehler: Integer;'#10 +
    '  Meldung, Vorige: TMeldung;'#10'end.';
  Findings := TRuleAssert.Findings(TThreadvarManagedRule.Create, Source);
  Assert.AreEqual(3, Integer(Length(Findings)));
  Assert.AreEqual('threadvar mit string wird beim Thread-Ende nicht finalisiert (Leck je Thread).',
    Findings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual(8, Findings[0].Range.StartPos.Line);
  Assert.AreEqual('threadvar mit TMeldung (enthält Strings) wird beim Thread-Ende nicht finalisiert (Leck je ' +
    'Thread).', Findings[1].Message);
  Assert.AreEqual(10, Findings[2].Range.StartPos.Line);
  Assert.AreEqual(11, Findings[2].Range.StartPos.Character);
  // Korrigiert: Zeiger auf einen Puffer bzw. normale var mit string.
  TRuleAssert.Silent(TThreadvarManagedRule.Create, Head + 'threadvar'#10'  LetzteMeldung: PChar;'#10 +
    'var'#10'  Global: string;'#10'end.');
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TThreadvarManagedRule.Create, Source,
    '{"rules": {"threadvar-managed": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TThreadvarManagedRule.Create, Source,
    '{"rules": {"threadvar-managed": {"exclude": ["Alt/*.pas"]}}}', 'Alt/U.pas'))));
  Assert.AreEqual(3, Integer(Length(TRuleAssert.Findings(TThreadvarManagedRule.Create, Source,
    '{"rules": {"threadvar-managed": {"exclude": ["Alt/*.pas"]}}}', 'Neu/U.pas'))));
end;

function Copier(const ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10'procedure Sichern(const Pfad: string; N: Integer);'#10 +
    'var'#10'  Ziel: PChar;'#10'begin'#10 + ABody + #10'end;'#10'end.';
end;

procedure TRtlTypePatternRulesTests.PCharOfTemporaryIssueExample;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := Copier('  Ziel := PChar(Pfad + ''.bak'');'#10'  CopyFile(PChar(Pfad), Ziel, False);');
  Findings := TRuleAssert.Findings(TPCharOfTemporaryRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Der Ausdruck Pfad + ''.bak'' ist temporär; Ziel zeigt nach dieser Zeile auf freigegebenen ' +
    'Speicher.', Findings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual('Zwischenergebnis in ZielText ablegen', Findings[0].Fixes[0].Title);
  Fixed := TChangeSignature.ApplyEdits(Source, Findings[0].Fixes[0].Edits);
  Assert.AreEqual(Copier('  var ZielText: string := Pfad + ''.bak'';'#10'  Ziel := PChar(ZielText);'#10 +
    '  CopyFile(PChar(Pfad), Ziel, False);'), Fixed);
  TRuleAssert.Silent(TPCharOfTemporaryRule.Create, Fixed);
end;

procedure TRtlTypePatternRulesTests.PCharOfTemporaryVariants;
var
  Findings: TArray<TRuleFinding>;
begin
  // Funktionsergebnis, Feld ohne Korrektur, PostMessage hinter LPARAM.
  Findings := TRuleAssert.Findings(TPCharOfTemporaryRule.Create, Copier('  Ziel := PChar(IntToStr(N));'#10 +
    '  FName := PChar(Format(''%d'', [N]));'#10'  PostMessage(Handle, WM_USER, 0, LPARAM(PChar(Pfad + ''x'')));'));
  Assert.AreEqual(3, Integer(Length(Findings)));
  Assert.AreEqual('Der Ausdruck IntToStr(N) ist temporär; Ziel zeigt nach dieser Zeile auf freigegebenen Speicher.',
    Findings[0].Message);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual(0, Integer(Length(Findings[1].Fixes)), 'Feld: keine Korrektur');
  Assert.AreEqual('Der Ausdruck Pfad + ''x'' ist temporär; PostMessage liest den Zeiger erst später aus ' +
    'freigegebenem Speicher.', Findings[2].Message);
  // Name schon vergeben: ZielText2.
  Findings := TRuleAssert.Findings(TPCharOfTemporaryRule.Create, Copier('  ZielText := 1;'#10 +
    '  Ziel := PChar(Pfad + ''.bak'');'));
  Assert.AreEqual('Zwischenergebnis in ZielText2 ablegen', Findings[0].Fixes[0].Title);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TPCharOfTemporaryRule.Create,
    Copier('  Ziel := PChar(IntToStr(N));'), '{"rules": {"pchar-of-temporary": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TPCharOfTemporaryRule.Create,
    Copier('  Ziel := PChar(IntToStr(N));'), '{"rules": {"pchar-of-temporary": {"exclude": ["Alt/*.pas"]}}}',
    'Alt/U.pas'))));
end;

procedure TRtlTypePatternRulesTests.PCharOfTemporarySilentCases;
begin
  // Variable, Konstante, Aufruf mit temporärem Argument, SendMessage (synchron), Zeigerarithmetik.
  TRuleAssert.Silent(TPCharOfTemporaryRule.Create, Copier('  Ziel := PChar(Pfad);'#10 +
    '  Ziel := PChar(''a'' + ''b'');'#10'  CopyFile(PChar(Pfad + ''.bak''), Ziel, False);'#10 +
    '  SendMessage(Handle, WM_USER, 0, LPARAM(PChar(Pfad + ''x'')));'#10'  Ziel := PChar(Ziel + 1);'));
end;

initialization
  TDUnitX.RegisterTestFixture(TRtlTypePatternRulesTests);

end.
