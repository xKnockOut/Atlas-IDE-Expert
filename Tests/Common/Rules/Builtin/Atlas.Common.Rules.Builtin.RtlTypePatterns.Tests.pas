unit Atlas.Common.Rules.Builtin.RtlTypePatterns.Tests;

// Tests für die typbasierten Regeln zu RTL-Mustern aus #153, Stufe 2, und
// für die deklarierten Typen, auf denen sie aufbauen; zuletzt
// managed-type-raw-memory (#921) mit Records, Aliassen, Zeigern, Index und
// Korrekturen, threadvar-managed (#922), pchar-of-temporary (#923) und
// stringlist-unsorted (#925), writeln-in-gui-app (#926) und unchecked-conversion (#932).

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
    [Test]
    procedure StringListUnsortedIssueExample;
    [Test]
    procedure StringListUnsortedVariants;
    [Test]
    procedure StringListUnsortedSilentCases;
    [Test]
    procedure WritelnInGuiAppIssueExample;
    [Test]
    procedure WritelnInGuiAppApplicationKind;
    [Test]
    procedure WritelnInGuiAppVariants;
    [Test]
    procedure WritelnInGuiAppSilentCases;
    [Test]
    procedure WritelnInGuiAppOptions;
    [Test]
    procedure UncheckedConversionIssueExample;
    [Test]
    procedure UncheckedConversionVariants;
    [Test]
    procedure UncheckedConversionSilentCases;
    [Test]
    procedure UncheckedConversionOptions;
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
  Atlas.Common.Configuration.Parser,
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

function Lister(const AVars, ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10'procedure Suchen(const Datei, Suche: string);'#10 +
    'var'#10'  Namen: TStringList;'#10'  Index: Integer;'#10 + AVars + 'begin'#10 + ABody + #10'end;'#10'end.';
end;

procedure TRtlTypePatternRulesTests.StringListUnsortedIssueExample;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := Lister('', '  Namen := TStringList.Create;'#10'  Namen.LoadFromFile(Datei);'#10 +
    '  if Namen.Find(Suche, Index) then'#10'    Namen.Delete(Index);'#10'  Namen.Free;');
  Findings := TRuleAssert.Findings(TStringListUnsortedRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Find setzt eine sortierte Liste voraus; Namen ist nicht sortiert.', Findings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
  Assert.AreEqual(2, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('Sorted := True nach dem Erzeugen ergänzen', Findings[0].Fixes[0].Title);
  Assert.AreEqual(Lister('', '  Namen := TStringList.Create;'#10'  Namen.Sorted := True;'#10 +
    '  Namen.LoadFromFile(Datei);'#10'  if Namen.Find(Suche, Index) then'#10'    Namen.Delete(Index);'#10 +
    '  Namen.Free;'), TChangeSignature.ApplyEdits(Source, Findings[0].Fixes[0].Edits));
  TRuleAssert.Silent(TStringListUnsortedRule.Create, TChangeSignature.ApplyEdits(Source, Findings[0].Fixes[0].Edits));
  Assert.AreEqual('IndexOf statt Find verwenden', Findings[0].Fixes[1].Title);
  Assert.AreEqual(Lister('', '  Namen := TStringList.Create;'#10'  Namen.LoadFromFile(Datei);'#10 +
    '  Index := Namen.IndexOf(Suche);'#10'  if Index >= 0 then'#10'    Namen.Delete(Index);'#10'  Namen.Free;'),
    TChangeSignature.ApplyEdits(Source, Findings[0].Fixes[1].Edits));
  TRuleAssert.Silent(TStringListUnsortedRule.Create, TChangeSignature.ApplyEdits(Source, Findings[0].Fixes[1].Edits));
end;

procedure TRtlTypePatternRulesTests.StringListUnsortedVariants;
var
  Findings: TArray<TRuleFinding>;
  Source: string;
begin
  // Duplicates ohne Sorted, Find in while ohne IndexOf-Korrektur.
  Findings := TRuleAssert.Findings(TStringListUnsortedRule.Create, Lister('', '  Namen := TStringList.Create;'#10 +
    '  Namen.Duplicates := dupIgnore;'#10'  while Namen.Find(Suche, Index) do'#10'    Namen.Delete(Index);'));
  Assert.AreEqual(2, Integer(Length(Findings)));
  Assert.AreEqual('Duplicates wirkt nur bei sortierten Listen; Namen ist nicht sortiert.', Findings[0].Message);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual(1, Integer(Length(Findings[1].Fixes)), 'while: nur Sorted');
  // Insert verträgt kein Sorted: nur IndexOf.
  Findings := TRuleAssert.Findings(TStringListUnsortedRule.Create, Lister('', '  Namen := TStringList.Create;'#10 +
    '  Namen.Insert(0, Suche);'#10'  if Namen.Find(Suche, Index) then'#10'    Exit;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('IndexOf statt Find verwenden', Findings[0].Fixes[0].Title);
  // Inline-Variable und Feld, das im Konstruktor erzeugt wird.
  Findings := TRuleAssert.Findings(TStringListUnsortedRule.Create, Lister('',
    '  var Liste := TStringList.Create;'#10'  if Liste.Find(Suche, Index) then'#10'    Exit;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Find setzt eine sortierte Liste voraus; Liste ist nicht sortiert.', Findings[0].Message);
  Source := 'unit U;'#10'interface'#10'type'#10'  TCache = class'#10'    FNamen: TStringList;'#10 +
    '    constructor Create;'#10'    function Hat(const S: string): Boolean;'#10'  end;'#10'implementation'#10 +
    'constructor TCache.Create;'#10'begin'#10'  FNamen := TStringList.Create;'#10'end;'#10 +
    'function TCache.Hat(const S: string): Boolean;'#10'var'#10'  I: Integer;'#10'begin'#10 +
    '  Result := Self.FNamen.Find(S, I);'#10'end;'#10'end.';
  Findings := TRuleAssert.Findings(TStringListUnsortedRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Find setzt eine sortierte Liste voraus; FNamen ist nicht sortiert.', Findings[0].Message);
  // Eine gleichnamige sortierte Variable in einer anderen Routine zählt nicht.
  Findings := TRuleAssert.Findings(TStringListUnsortedRule.Create, Lister('',
    '  Namen := TStringList.Create;'#10'  if Namen.Find(Suche, Index) then'#10'    Exit;'#10'end;'#10 +
    'procedure Andere;'#10'var'#10'  Namen: TStringList;'#10'begin'#10'  Namen := TStringList.Create;'#10 +
    '  Namen.Sorted := True;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TStringListUnsortedRule.Create,
    Lister('', '  Namen := TStringList.Create;'#10'  Namen.Find(Suche, Index);'),
    '{"rules": {"stringlist-unsorted": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TStringListUnsortedRule.Create,
    Lister('', '  Namen := TStringList.Create;'#10'  Namen.Find(Suche, Index);'),
    '{"rules": {"stringlist-unsorted": {"exclude": ["Alt/*.pas"]}}}', 'Alt/U.pas'))));
end;

procedure TRtlTypePatternRulesTests.StringListUnsortedSilentCases;
begin
  // Sorted, sortierender Konstruktor, Sort, Weitergabe, with, Parameter ohne Erzeugen, dupAccept.
  TRuleAssert.Silent(TStringListUnsortedRule.Create, Lister('', '  Namen := TStringList.Create;'#10 +
    '  Namen.Sorted := True;'#10'  Namen.Find(Suche, Index);'));
  TRuleAssert.Silent(TStringListUnsortedRule.Create, Lister('',
    '  Namen := TStringList.Create(dupIgnore, True, False);'#10'  Namen.Find(Suche, Index);'));
  TRuleAssert.Silent(TStringListUnsortedRule.Create, Lister('', '  Namen := TStringList.Create;'#10 +
    '  Namen.Sort;'#10'  Namen.Find(Suche, Index);'));
  TRuleAssert.Silent(TStringListUnsortedRule.Create, Lister('', '  Namen := TStringList.Create;'#10 +
    '  Fuellen(Namen);'#10'  Namen.Find(Suche, Index);'));
  TRuleAssert.Silent(TStringListUnsortedRule.Create, Lister('', '  Namen := TStringList.Create;'#10 +
    '  with Namen do'#10'    Sorted := True;'#10'  Namen.Find(Suche, Index);'));
  TRuleAssert.Silent(TStringListUnsortedRule.Create, Lister('', '  Namen.Find(Suche, Index);'));
  TRuleAssert.Silent(TStringListUnsortedRule.Create, Lister('', '  Namen := TStringList.Create;'#10 +
    '  Namen.Duplicates := dupAccept;'#10'  Index := Namen.IndexOf(Suche);'));
end;

function GuiUnit(const ABody: string): string;
begin
  Result := 'unit Haupt;'#10'interface'#10'uses'#10'  Vcl.Forms;'#10'type'#10'  TfrmHaupt = class(TForm)'#10 +
    '    procedure btnStartClick(Sender: TObject);'#10'  end;'#10'implementation'#10'uses'#10 +
    '  System.SysUtils;'#10'procedure TfrmHaupt.btnStartClick(Sender: TObject);'#10'begin'#10 + ABody + #10 +
    'end;'#10'end.';
end;

function GuiProgram(const AVars, ABody: string): string;
begin
  Result := 'program Werkzeug;'#10'uses'#10'  Vcl.Forms;'#10 + AVars + 'begin'#10 + ABody + #10'end.';
end;

procedure TRtlTypePatternRulesTests.WritelnInGuiAppIssueExample;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := GuiUnit('  Writeln(''Start: '', TimeToStr(Now));');
  Findings := TRuleAssert.ApplicationFindings(TWritelnInGuiAppRule.Create, Source, TRuleApplicationKind.Gui);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Das Projekt hat keine Konsole; Writeln löst zur Laufzeit E/A-Fehler 105 aus.', Findings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual('Durch OutputDebugString ersetzen', Findings[0].Fixes[0].Title);
  Fixed := TChangeSignature.ApplyEdits(Source, Findings[0].Fixes[0].Edits);
  Assert.IsTrue(Pos('  OutputDebugString(PChar(''Start: '' + TimeToStr(Now)));', Fixed) > 0, Fixed);
  Assert.IsTrue(Pos('Winapi.Windows', Fixed) > 0, 'uses ergänzt: ' + Fixed);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ApplicationFindings(TWritelnInGuiAppRule.Create, Fixed,
    TRuleApplicationKind.Gui))));
  // Konsolenprojekt und Unit ohne Projekt: keine Meldung.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ApplicationFindings(TWritelnInGuiAppRule.Create, Source,
    TRuleApplicationKind.Console))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ApplicationFindings(TWritelnInGuiAppRule.Create, Source,
    TRuleApplicationKind.Unknown))));
end;

procedure TRtlTypePatternRulesTests.WritelnInGuiAppApplicationKind;
begin
  Assert.AreEqual(Ord(TRuleApplicationKind.Gui), Ord(TWritelnInGuiAppRule.ApplicationKind('',
    'program P;'#10'uses Vcl.Forms;'#10'{$R *.res}'#10'begin'#10'end.')));
  Assert.AreEqual(Ord(TRuleApplicationKind.Console), Ord(TWritelnInGuiAppRule.ApplicationKind('',
    'program P;'#10'{$APPTYPE CONSOLE}'#10'begin'#10'end.')));
  Assert.AreEqual(Ord(TRuleApplicationKind.Console), Ord(TWritelnInGuiAppRule.ApplicationKind('',
    'program P;'#10'{$IFNDEF TESTINSIGHT}'#10'{$apptype console}'#10'{$ENDIF}'#10'begin'#10'end.')));
  Assert.AreEqual(Ord(TRuleApplicationKind.Console), Ord(TWritelnInGuiAppRule.ApplicationKind('true',
    'program P;'#10'begin'#10'end.')));
  // Auskommentiert zählt nicht.
  Assert.AreEqual(Ord(TRuleApplicationKind.Gui), Ord(TWritelnInGuiAppRule.ApplicationKind('false',
    '// Werkzeug'#10'program P;'#10'// {$APPTYPE CONSOLE}'#10'begin'#10'end.')));
  Assert.AreEqual(Ord(TRuleApplicationKind.Unknown), Ord(TWritelnInGuiAppRule.ApplicationKind('',
    'library L;'#10'begin'#10'end.')));
  Assert.AreEqual(Ord(TRuleApplicationKind.Unknown), Ord(TWritelnInGuiAppRule.ApplicationKind('', '')));
end;

procedure TRtlTypePatternRulesTests.WritelnInGuiAppVariants;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  // Die .dpr selbst ohne Projekt; Readln ohne Korrektur, Output fällt weg, Zahl über IntToStr.
  Source := GuiProgram('var'#10'  Anzahl: Integer;'#10, '  Writeln(Output, ''Anzahl: '', Anzahl);'#10 +
    '  Readln;'#10'  Write(Anzahl:5);');
  Findings := TRuleAssert.Findings(TWritelnInGuiAppRule.Create, Source);
  Assert.AreEqual(3, Integer(Length(Findings)));
  Assert.IsTrue(Pos('OutputDebugString(PChar(''Anzahl: '' + IntToStr(Anzahl)))',
    TChangeSignature.ApplyEdits(Source, Findings[0].Fixes[0].Edits)) > 0);
  Assert.IsTrue(Pos('System.SysUtils', TChangeSignature.ApplyEdits(Source, Findings[0].Fixes[0].Edits)) > 0,
    'IntToStr braucht SysUtils');
  Assert.AreEqual('Das Projekt hat keine Konsole; Readln löst zur Laufzeit E/A-Fehler 104 aus.', Findings[1].Message);
  Assert.AreEqual(0, Integer(Length(Findings[1].Fixes)));
  Assert.AreEqual(0, Integer(Length(Findings[2].Fixes)), 'Breitenangabe: keine Korrektur');
  // Unbekannter Typ: Meldung ohne Korrektur.
  Findings := TRuleAssert.Findings(TWritelnInGuiAppRule.Create, GuiProgram('', '  Writeln(Fremd);'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
end;

procedure TRtlTypePatternRulesTests.WritelnInGuiAppSilentCases;
begin
  // Konsolenprogramm, Textdatei, IsConsole, eigene Routine Writeln, Write als Methode, Stream.Read.
  TRuleAssert.Silent(TWritelnInGuiAppRule.Create, 'program P;'#10'{$APPTYPE CONSOLE}'#10'begin'#10 +
    '  Writeln(''x'');'#10'end.');
  TRuleAssert.Silent(TWritelnInGuiAppRule.Create, GuiProgram('var'#10'  F: TextFile;'#10,
    '  Writeln(F, ''x'');'#10'  Writeln(F);'));
  TRuleAssert.Silent(TWritelnInGuiAppRule.Create, GuiProgram('', '  if IsConsole then'#10'    Writeln(''x'');'));
  TRuleAssert.Silent(TWritelnInGuiAppRule.Create, GuiProgram('procedure Writeln(const S: string);'#10'begin'#10 +
    'end;'#10, '  Writeln(''x'');'));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ApplicationFindings(TWritelnInGuiAppRule.Create,
    GuiUnit('  Write(Buffer, 4);'#10'  Stream.Read(Buffer, 4);'#10'  Log.Writeln(''x'');'),
    TRuleApplicationKind.Gui))));
  TRuleAssert.Silent(TWritelnInGuiAppRule.Create, 'library L;'#10'begin'#10'  Writeln(''x'');'#10'end.');
end;

procedure TRtlTypePatternRulesTests.WritelnInGuiAppOptions;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
  Issues: TArray<TConfigurationIssue>;
begin
  Source := GuiProgram('', '  Writeln(''Start'');');
  Findings := TRuleAssert.Findings(TWritelnInGuiAppRule.Create, Source,
    '{"rules": {"writeln-in-gui-app": {"replacement": "Log.Info"}}}', 'Werkzeug.dpr');
  Assert.AreEqual('Durch Log.Info ersetzen', Findings[0].Fixes[0].Title);
  Assert.AreEqual(GuiProgram('', '  Log.Info(''Start'');'), TChangeSignature.ApplyEdits(Source,
    Findings[0].Fixes[0].Edits));
  Findings := TRuleAssert.Findings(TWritelnInGuiAppRule.Create, Source,
    '{"rules": {"writeln-in-gui-app": {"replacement": "Logger.Log(TLogLevel.Info, %s)"}}}', 'Werkzeug.dpr');
  Assert.AreEqual('Durch Logger.Log ersetzen', Findings[0].Fixes[0].Title);
  Assert.AreEqual(GuiProgram('', '  Logger.Log(TLogLevel.Info, ''Start'');'), TChangeSignature.ApplyEdits(Source,
    Findings[0].Fixes[0].Edits));
  Assert.AreEqual('OutputDebugString', TWritelnInGuiAppRule.Replacement(''));
  Assert.AreEqual('OutputDebugString', TWritelnInGuiAppRule.Replacement('{"replacement": " "}'));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TWritelnInGuiAppRule.Create, Source,
    '{"rules": {"writeln-in-gui-app": "off"}}', 'Werkzeug.dpr'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TWritelnInGuiAppRule.Create, Source,
    '{"rules": {"writeln-in-gui-app": {"exclude": ["Alt/*.dpr"]}}}', 'Alt/Werkzeug.dpr'))));
  TConfigurationParser.Parse('{"rules": {"writeln-in-gui-app": {"replacement": ["Log.Info"]}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.AreEqual('"replacement" muss ein Text sein', Issues[0].Message);
end;

function Eingabe(const AVars, ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'type'#10'  TfrmBestellung = class(TForm)'#10'    edtMenge: TEdit;'#10 +
    '    FAnzahl: Integer;'#10'  end;'#10'implementation'#10'procedure TfrmBestellung.btnOkClick(Sender: TObject);'#10 +
    'var'#10'  Menge: Integer;'#10 + AVars + 'begin'#10 + ABody + #10'end;'#10'end.';
end;

procedure TRtlTypePatternRulesTests.UncheckedConversionIssueExample;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := Eingabe('', '  Menge := StrToInt(edtMenge.Text);');
  Findings := TRuleAssert.Findings(TUncheckedConversionRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Eingabe aus edtMenge.Text ohne Prüfung umgewandelt; eine Fehleingabe löst EConvertError aus.',
    Findings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
  Assert.AreEqual('In TryStrToInt mit Fehlerzweig umschreiben', Findings[0].Fixes[0].Title);
  Fixed := TChangeSignature.ApplyEdits(Source, Findings[0].Fixes[0].Edits);
  Assert.AreEqual(Eingabe('', '  if not TryStrToInt(edtMenge.Text, Menge) then'#10 +
    '    raise EConvertError.Create(''Menge ist keine Zahl'');'), Fixed);
  TRuleAssert.Silent(TUncheckedConversionRule.Create, Fixed);
end;

procedure TRtlTypePatternRulesTests.UncheckedConversionVariants;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TUncheckedConversionRule.Create, Eingabe('  Preis: Double;'#10'  Am: TDateTime;'#10 +
    '  Summe: Integer;'#10, '  Preis := StrToFloat(Trim(Grid.Cells[1, Zeile]));'#10 +
    '  Am := SysUtils.StrToDate(Memo.Lines[0]);'#10'  FAnzahl := StrToInt(edtMenge.Text);'#10 +
    '  Summe := Summe + StrToInt(edtMenge.Text);'#10'  if Pruefen then'#10'    Menge := StrToInt(edtMenge.Text)'#10 +
    '  else'#10'    Menge := 0;'#10'  Preis := StrToInt(edtMenge.Text);'));
  Assert.AreEqual(6, Integer(Length(Findings)));
  Assert.AreEqual('Eingabe aus Grid.Cells[1, Zeile] ohne Prüfung umgewandelt; eine Fehleingabe löst EConvertError ' +
    'aus.', Findings[0].Message);
  Assert.AreEqual('if not TryStrToFloat(Trim(Grid.Cells[1, Zeile]), Preis) then'#10 +
    '    raise EConvertError.Create(''Preis ist keine Zahl'')', Findings[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual('Eingabe aus Memo.Lines[0] ohne Prüfung umgewandelt; eine Fehleingabe löst EConvertError aus.',
    Findings[1].Message);
  Assert.AreEqual('In TryStrToDate mit Fehlerzweig umschreiben', Findings[1].Fixes[0].Title);
  // Feld: Korrektur; Ausdruck, then-Zweig ohne begin und unpassender Typ: ohne Korrektur.
  Assert.AreEqual(1, Integer(Length(Findings[2].Fixes)));
  Assert.AreEqual(0, Integer(Length(Findings[3].Fixes)));
  Assert.AreEqual(0, Integer(Length(Findings[4].Fixes)));
  Assert.AreEqual(0, Integer(Length(Findings[5].Fixes)));
end;

procedure TRtlTypePatternRulesTests.UncheckedConversionSilentCases;
begin
  // Im try/except, Konstante, Variable statt Eingabe, IntToStr, StrToIntDef.
  TRuleAssert.Silent(TUncheckedConversionRule.Create, Eingabe('', '  try'#10 +
    '    Menge := StrToInt(edtMenge.Text);'#10'  except'#10'    on EConvertError do'#10'      Menge := 0;'#10 +
    '  end;'#10'  Menge := StrToInt(''42'');'#10'  Menge := StrToInt(Zeile);'#10 +
    '  edtMenge.Text := IntToStr(Menge);'#10'  Menge := StrToIntDef(edtMenge.Text, 0);'));
  // try/finally schützt nicht.
  TRuleAssert.Reports(TUncheckedConversionRule.Create, Eingabe('', '  try'#10 +
    '    Menge := StrToInt(edtMenge.Text);'#10'  finally'#10'    Fertig;'#10'  end;'));
end;

procedure TRtlTypePatternRulesTests.UncheckedConversionOptions;
var
  Source: string;
  Issues: TArray<TConfigurationIssue>;
begin
  Source := Eingabe('', '  Menge := StrToInt(edtMenge.Text);'#10'  Menge := StrToInt(Query.Params[0].AsString);'#10 +
    '  Menge := StrToUInt(edtMenge.Text);');
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TUncheckedConversionRule.Create, Source))));
  Assert.AreEqual(2, Integer(Length(TRuleAssert.Findings(TUncheckedConversionRule.Create, Source,
    '{"rules": {"unchecked-conversion": {"sources": ["Text", "AsString"]}}}', 'U.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TUncheckedConversionRule.Create, Source,
    '{"rules": {"unchecked-conversion": {"functions": ["StrToUInt"]}}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TUncheckedConversionRule.Create, Source,
    '{"rules": {"unchecked-conversion": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TUncheckedConversionRule.Create, Source,
    '{"rules": {"unchecked-conversion": {"exclude": ["Alt/*.pas"]}}}', 'Alt/U.pas'))));
  TConfigurationParser.Parse('{"rules": {"unchecked-conversion": {"functions": "StrToInt", "sources": [1]}}}', Issues);
  Assert.AreEqual(2, Integer(Length(Issues)));
end;

initialization
  TDUnitX.RegisterTestFixture(TRtlTypePatternRulesTests);

end.
