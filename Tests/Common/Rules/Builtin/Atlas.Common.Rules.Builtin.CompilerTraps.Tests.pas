unit Atlas.Common.Rules.Builtin.CompilerTraps.Tests;

// Tests der Compiler-Fallen aus #1345: Exit([...]) bei Array-Ergebnis, String-Helfer auf TCaption, TBitmap hinter
// Winapi.Windows und Units nur im implementation-uses, jeweils mit Korrektur und stillen Fällen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCompilerTrapsTests = class
  public
    [Test]
    procedure ExitArrayLiteral;
    [Test]
    procedure ExitArrayLiteralSilentCases;
    [Test]
    procedure CaptionStringHelper;
    [Test]
    procedure UsesOrderHidesBitmap;
    [Test]
    procedure InterfaceNeedsImplementationUses;
    [Test]
    procedure RulesAreRegistered;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Builtin.CompilerTraps,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Tests.RuleAssert;

function Messages(const AFound: TArray<TRuleFinding>): string;
var
  mFinding: TRuleFinding;
begin
  Result := '';
  for mFinding in AFound do
  begin
    Result := Result + IntToStr(mFinding.Range.StartPos.Line) + ': ' + mFinding.Message + '|';
  end;
end;

/// <summary>Index mit Unit Werk.Basis: TCaption (type string), TKnopf mit Caption und TZahlen.</summary>
function BasisIndex: ISymbolIndex;
begin
  Result := TSymbolIndex.Create;
  Result.AddUnit(TIndexExtractor.ExtractText('unit Werk.Basis;'#10'interface'#10'type'#10 +
    '  TCaption = type string;'#10'  TKnopf = class'#10'  private'#10'    FCaption: TCaption;'#10'  public'#10 +
    '    property Caption: TCaption read FCaption write FCaption;'#10'  end;'#10 +
    '  TZahlen = TArray<Integer>;'#10'implementation'#10'end.', 'C:\P\Werk.Basis.pas', nil));
  Result.AddUnit(TIndexExtractor.ExtractText('unit Werk.Neben;'#10'interface'#10'const'#10'  cNeben = 1;'#10 +
    'implementation'#10'end.', 'C:\P\Werk.Neben.pas', nil));
end;

{ TCompilerTrapsTests }

procedure TCompilerTrapsTests.ExitArrayLiteral;
var
  mSource, mFixed: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := 'unit U;'#10'interface'#10'implementation'#10'function Namen(A: Boolean): TArray<string>;'#10 +
    'begin'#10'  if A then'#10'    Exit([''a'', ''b'']);'#10'  Exit([''c'']);'#10'end;'#10'end.';
  mFound := TRuleAssert.Findings(TExitArrayLiteralRule.Create, mSource);
  Assert.AreEqual('6: Exit([''a'', ''b'']): Delphi liest [...] hier als Menge, nicht als TArray<string> (wie E2001 ' +
    'bzw. E2010). Erst Result zuweisen, dann Exit.|7: Exit([''c'']): Delphi liest [...] hier als Menge, nicht als ' +
    'TArray<string> (wie E2001 bzw. E2010). Erst Result zuweisen, dann Exit.|', Messages(mFound));
  Assert.IsTrue(mFound[0].Fixes[0].Safe);
  mFixed := TChangeSignature.ApplyEdits(mSource, mFound[1].Fixes[0].Edits);
  mFixed := TChangeSignature.ApplyEdits(mFixed, mFound[0].Fixes[0].Edits);
  Assert.AreEqual(StringReplace(StringReplace(mSource, 'Exit([''a'', ''b''])',
    'begin Result := [''a'', ''b'']; Exit; end', []), 'Exit([''c''])', 'Result := [''c'']; Exit', []), mFixed);
  Assert.AreEqual('', Messages(TRuleAssert.Findings(TExitArrayLiteralRule.Create, mFixed)));
  // Eigener Typ der Datei (array of) und TBytes.
  Assert.AreEqual(2, Integer(Length(TRuleAssert.Findings(TExitArrayLiteralRule.Create, 'unit U;'#10'interface'#10 +
    'type'#10'  TListe = array of Integer;'#10'implementation'#10'function A: TListe;'#10'begin'#10 +
    '  Exit([1]);'#10'end;'#10'function B: TBytes;'#10'begin'#10'  Exit([1]);'#10'end;'#10'end.'))));
end;

procedure TCompilerTrapsTests.ExitArrayLiteralSilentCases;
begin
  // Mengen-Ergebnis, leere Klammern, anderer Wert, Prozedur, anonyme Methode.
  TRuleAssert.Silent(TExitArrayLiteralRule.Create, 'unit U;'#10'interface'#10'type'#10 +
    '  TFarben = set of (Rot, Blau);'#10'implementation'#10'function A: TFarben;'#10'begin'#10'  Exit([Rot]);'#10 +
    'end;'#10'function B: TArray<Integer>;'#10'begin'#10'  if True then'#10'    Exit([]);'#10'  Exit(nil);'#10 +
    'end;'#10'procedure C;'#10'begin'#10'  Exit;'#10'end;'#10'function D: TArray<Integer>;'#10'var'#10 +
    '  F: TFunc<TFarben>;'#10'begin'#10'  F := function: TFarben'#10'    begin'#10'      Exit([Blau]);'#10 +
    '    end;'#10'  Result := nil;'#10'end;'#10'end.');
end;

procedure TCompilerTrapsTests.CaptionStringHelper;
var
  mSource, mFixed: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := 'unit U;'#10'interface'#10'uses'#10'  Werk.Basis;'#10'implementation'#10 +
    'procedure Lauf(K: TKnopf; S: string);'#10'begin'#10'  if K.Caption.StartsWith(''a'') or S.Contains(''b'') or ' +
    'string(K.Caption).EndsWith(''c'') then'#10'    K.Caption := '''';'#10'end;'#10'end.';
  mFound := TRuleAssert.IndexFindings(TCaptionStringHelperRule.Create, mSource, BasisIndex, '', 'U.pas');
  Assert.AreEqual('7: K.Caption ist vom Typ TCaption, einem eigenen String-Typ: StartsWith aus TStringHelper gilt ' +
    'dafür nicht (wie E2018). string(...) darum setzen.|', Messages(mFound));
  mFixed := TChangeSignature.ApplyEdits(mSource, mFound[0].Fixes[0].Edits);
  Assert.AreEqual(StringReplace(mSource, 'K.Caption.StartsWith', 'string(K.Caption).StartsWith', []), mFixed);
end;

procedure TCompilerTrapsTests.UsesOrderHidesBitmap;
var
  mSource, mFixed: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := 'unit U;'#10'interface'#10'uses'#10'  System.SysUtils,'#10'  Vcl.Graphics,'#10'  Winapi.Windows;'#10 +
    'implementation'#10'procedure Lauf;'#10'begin'#10'  TBitmap.Create.Free;'#10'end;'#10'end.';
  mFound := TRuleAssert.Findings(TUsesOrderHidesTypeRule.Create, mSource);
  Assert.AreEqual('5: Winapi.Windows steht in uses hinter Vcl.Graphics: TBitmap meint hier den Record aus ' +
    'Winapi.Windows, TBitmap.Create und die Methoden scheitern (wie E2003). Winapi.Windows vor Vcl.Graphics ' +
    'einbinden.|', Messages(mFound));
  mFixed := TChangeSignature.ApplyEdits(mSource, mFound[0].Fixes[0].Edits);
  Assert.AreEqual(StringReplace(mSource, '  Vcl.Graphics,'#10'  Winapi.Windows;',
    '  Winapi.Windows,'#10'  Vcl.Graphics;', []), mFixed);
  Assert.AreEqual('', Messages(TRuleAssert.Findings(TUsesOrderHidesTypeRule.Create, mFixed)));
  // Über interface und implementation hinweg: Meldung ohne Korrektur.
  mFound := TRuleAssert.Findings(TUsesOrderHidesTypeRule.Create, 'unit U;'#10'interface'#10'uses'#10 +
    '  Vcl.Graphics;'#10'implementation'#10'uses'#10'  Winapi.Windows;'#10'procedure Lauf(B: TBitmap);'#10 +
    'begin'#10'end;'#10'end.');
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(0, Integer(Length(mFound[0].Fixes)));
  // TBitmap nur im interface-Teil: Das implementation-uses wirkt dort nicht (MinimapLayers).
  TRuleAssert.Silent(TUsesOrderHidesTypeRule.Create, 'unit U;'#10'interface'#10'uses'#10'  Vcl.Graphics;'#10 +
    'type'#10'  TBild = class'#10'    FBild: TBitmap;'#10'  end;'#10'implementation'#10'uses'#10 +
    '  Winapi.Windows;'#10'end.');
  // Ohne TBitmap oder nur qualifiziert.
  TRuleAssert.Silent(TUsesOrderHidesTypeRule.Create, 'unit U;'#10'interface'#10'uses'#10 +
    '  Vcl.Graphics, Winapi.Windows;'#10'implementation'#10'procedure Lauf(B: Vcl.Graphics.TBitmap; C: TCanvas);' +
    #10'begin'#10'end;'#10'end.');
end;

procedure TCompilerTrapsTests.InterfaceNeedsImplementationUses;
var
  mSource, mFixed: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := 'unit U;'#10'interface'#10'uses'#10'  Werk.Neben;'#10'type'#10'  TLeser = class'#10 +
    '    // TZahlen nur im Kommentar'#10'    function Liste: TZahlen;'#10'    function Zwei: TZahlen;'#10'  end;'#10 +
    'implementation'#10'uses'#10'  Werk.Basis;'#10'function TLeser.Liste: TZahlen;'#10'begin'#10 +
    '  Result := nil;'#10'end;'#10'function TLeser.Zwei: TZahlen;'#10'begin'#10'  Result := nil;'#10'end;'#10'end.';
  mFound := TRuleAssert.IndexFindings(TInterfaceUsesMissingRule.Create, mSource, BasisIndex, '', 'U.pas');
  Assert.AreEqual('7: TZahlen kommt aus Werk.Basis, die nur im uses des implementation-Teils steht; im ' +
    'interface-Teil ist der Name unbekannt (wie E2003).|', Messages(mFound));
  mFixed := TChangeSignature.ApplyEdits(mSource, mFound[0].Fixes[0].Edits);
  Assert.AreEqual(StringReplace(StringReplace(mSource, '  Werk.Neben;', '  Werk.Neben, Werk.Basis;', []),
    'implementation'#10'uses'#10'  Werk.Basis;'#10, 'implementation'#10#10, []), mFixed);
  Assert.AreEqual('', Messages(TRuleAssert.IndexFindings(TInterfaceUsesMissingRule.Create, mFixed, BasisIndex, '',
    'U.pas')));  // Gleichnamige Deklaration im interface ist keine Verwendung.
  Assert.AreEqual('', Messages(TRuleAssert.IndexFindings(TInterfaceUsesMissingRule.Create, 'unit U;'#10 +
    'interface'#10'procedure cNeben(A: Integer);'#10'implementation'#10'uses'#10'  Werk.Neben;'#10 +
    'procedure cNeben(A: Integer);'#10'begin'#10'end;'#10'end.', BasisIndex, '', 'U.pas')));
end;

procedure TCompilerTrapsTests.RulesAreRegistered;
var
  mRule: IRule;
  mIds: string;
begin
  mIds := '';
  for mRule in BuiltinRules do
  begin
    if (mRule.Descriptor.Id = cExitArrayLiteralRuleId) or (mRule.Descriptor.Id = cCaptionStringHelperRuleId) or
      (mRule.Descriptor.Id = cUsesOrderHidesTypeRuleId) or (mRule.Descriptor.Id = cInterfaceUsesMissingRuleId) then
    begin
      mIds := mIds + mRule.Descriptor.Id + ' ';
    end;
  end;
  Assert.AreEqual('exit-array-literal caption-string-helper uses-order-hides-type interface-uses-missing ', mIds);
end;

initialization
  TDUnitX.RegisterTestFixture(TCompilerTrapsTests);

end.
