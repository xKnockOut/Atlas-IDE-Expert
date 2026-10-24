unit Atlas.Common.Rules.Builtin.StringAddress.Tests;

// Tests der Regel first-char-address (#1130): Beispiel aus dem Issue mit
// Korrektur, Umwandlungen um die Adresse, S[Low(S)], Stringtypen, andere
// Indizes und Typen, Korrektur nur bei const-Parametern, Felder, Typen aus
// dem Index, bedingte Deklarationen, Abschalten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFirstCharAddressTests = class
  public
    [Test]
    procedure IssueExampleWithFix;
    [Test]
    procedure CastIsReplacedAsWhole;
    [Test]
    procedure LowIndex;
    [Test]
    procedure AnsiStrings;
    [Test]
    procedure OtherIndexesAndTypesAreSilent;
    [Test]
    procedure NoFixWithoutConst;
    [Test]
    procedure FieldsAndIndexTypes;
    [Test]
    procedure ConditionalDeclarationIsSilent;
    [Test]
    procedure OffAndExclude;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.StringAddress,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Tests.RuleAssert;

/// <summary>Unit mit der Prozedur Senden(AParams) mit Deklarationen ADecls und Anweisungen ABody.</summary>
function Source(const AParams, ADecls, ABody: string): string;
begin
  Result := 'unit Sender;'#10'interface'#10'implementation'#10 +
    'procedure WriteBuffer(const ABuffer: Pointer; ACount: Integer);'#10'begin'#10'end;'#10 +
    'procedure Senden(' + AParams + ');'#10'var'#10 + ADecls + 'begin'#10 + ABody + 'end;'#10'end.';
end;

function Findings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TFirstCharAddressRule.Create, ASource);
end;

function Findings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TFirstCharAddressRule.Create, ASource, AConfig, APath);
end;

/// <summary>Wendet den einzigen einzeiligen Edit einer Korrektur an (Zeilen mit #10).</summary>
function Applied(const AText: string; const AFix: TRuleFix): string;
var
  mLines: TArray<string>;
  mEdit: TRuleEdit;
  mLine: string;
begin
  Assert.AreEqual(1, Integer(Length(AFix.Edits)));
  mEdit := AFix.Edits[0];
  Assert.AreEqual(mEdit.Range.StartPos.Line, mEdit.Range.EndPos.Line, 'nur einzeilige Edits');
  mLines := AText.Split([#10]);
  mLine := mLines[mEdit.Range.StartPos.Line];
  mLines[mEdit.Range.StartPos.Line] := Copy(mLine, 1, mEdit.Range.StartPos.Character) + mEdit.NewText +
    Copy(mLine, mEdit.Range.EndPos.Character + 1, MaxInt);
  Result := string.Join(#10, mLines);
end;

{ TFirstCharAddressTests }

procedure TFirstCharAddressTests.IssueExampleWithFix;
var
  mSource: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := Source('const AText: string', '', '  WriteBuffer(@AText[1], Length(AText) * SizeOf(Char));'#10);
  mFound := Findings(mSource);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(FirstCharAddressRuleId, mFound[0].RuleId);
  Assert.AreEqual('Bei leerem AText löst @AText[1] mit Bereichsprüfung einen Fehler aus. PChar(AText) ist auch ' +
    'für leere Strings sicher.', mFound[0].Message);
  Assert.AreEqual('Durch PChar(AText) ersetzen', mFound[0].Fixes[0].Title);
  Assert.IsTrue(Applied(mSource, mFound[0].Fixes[0]).Contains(
    #10'  WriteBuffer(PChar(AText), Length(AText) * SizeOf(Char));'#10));
end;

procedure TFirstCharAddressTests.CastIsReplacedAsWhole;
var
  mSource: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := Source('const AText: string', '  mZeiger: PChar;'#10'  mRoh: Pointer;'#10,
    '  mZeiger := PChar(@AText[1]);'#10'  mRoh := Pointer(@AText[1]);'#10);
  mFound := Findings(mSource);
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.IsTrue(Applied(mSource, mFound[0].Fixes[0]).Contains(#10'  mZeiger := PChar(AText);'#10));
  Assert.IsTrue(Applied(mSource, mFound[1].Fixes[0]).Contains(#10'  mRoh := Pointer(AText);'#10));
end;

procedure TFirstCharAddressTests.LowIndex;
begin
  TRuleAssert.Reports(TFirstCharAddressRule.Create, Source('const AText: string', '',
    '  WriteBuffer(@AText[Low(AText)], 1);'#10));
  TRuleAssert.Silent(TFirstCharAddressRule.Create, Source('const AText, AAnderer: string', '',
    '  WriteBuffer(@AText[Low(AAnderer)], 1);'#10));
end;

procedure TFirstCharAddressTests.AnsiStrings;
var
  mSource: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := Source('const AText: AnsiString; const AWeit: UnicodeString; const ABreit: WideString', '',
    '  WriteBuffer(@AText[1], 1);'#10'  WriteBuffer(@AWeit[1], 1);'#10'  WriteBuffer(@ABreit[1], 1);'#10);
  mFound := Findings(mSource);
  Assert.AreEqual(3, Integer(Length(mFound)));
  Assert.AreEqual('PAnsiChar(AText)', mFound[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual('PChar(AWeit)', mFound[1].Fixes[0].Edits[0].NewText);
  Assert.AreEqual('PChar(ABreit)', mFound[2].Fixes[0].Edits[0].NewText);
end;

procedure TFirstCharAddressTests.OtherIndexesAndTypesAreSilent;
begin
  // Anderer Index, Kurzstring (S[1] ist gültig), Arrays, Adresse ohne Index.
  TRuleAssert.Silent(TFirstCharAddressRule.Create, Source('const AText: string; const AKurz: ShortString; ' +
    'const ABytes: TBytes; const AFeld: array of Char', '  mPos: Integer;'#10,
    '  WriteBuffer(@AText[2], 1);'#10'  WriteBuffer(@AText[mPos], 1);'#10'  WriteBuffer(@AKurz[1], 1);'#10 +
    '  WriteBuffer(@ABytes[0], 1);'#10'  WriteBuffer(@AFeld[1], 1);'#10'  WriteBuffer(@AText, 1);'#10 +
    '  WriteBuffer(PChar(AText), 1);'#10));
end;

procedure TFirstCharAddressTests.NoFixWithoutConst;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := Findings(Source('var AText: string; AWert: string', '  mText: string;'#10,
    '  WriteBuffer(@AText[1], 1);'#10'  WriteBuffer(@AWert[1], 1);'#10'  WriteBuffer(@mText[1], 1);'#10));
  Assert.AreEqual(3, Integer(Length(mFound)));
  Assert.AreEqual('Bei leerem mText löst @mText[1] mit Bereichsprüfung einen Fehler aus. Zum Lesen ist ' +
    'PChar(mText) auch für leere Strings sicher, zum Schreiben vorher UniqueString(mText).', mFound[2].Message);
  Assert.AreEqual(0, Integer(Length(mFound[0].Fixes)));
  Assert.AreEqual(0, Integer(Length(mFound[1].Fixes)));
  Assert.AreEqual(0, Integer(Length(mFound[2].Fixes)));
end;

procedure TFirstCharAddressTests.FieldsAndIndexTypes;
var
  mIndex: ISymbolIndex;
  mSource: string;
  mFound: TArray<TRuleFinding>;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText('unit System;'#10'interface'#10'type'#10 +
    '  RawByteString = type AnsiString;'#10'  UTF8String = type AnsiString;'#10'implementation'#10'end.',
    'C:\BDS\source\System.pas', nil));
  mIndex.AddUnit(TIndexExtractor.ExtractText('unit Puffer;'#10'interface'#10'type'#10'  TText = string;'#10 +
    '  TPuffer = class'#10'  public'#10'    Inhalt: string;'#10'    Name: TText;'#10'    Roh: RawByteString;'#10 +
    '    Utf8: UTF8String;'#10'  end;'#10 +
    'implementation'#10'end.', 'C:\Projekt\Puffer.pas', nil));
  mSource := 'unit Sender;'#10'interface'#10'uses Puffer;'#10'implementation'#10 +
    'procedure Senden(APuffer: TPuffer; P: Pointer);'#10'begin'#10'  P := @APuffer.Inhalt[1];'#10 +
    '  P := @APuffer.Name[1];'#10'  P := @APuffer.Roh[1];'#10'  P := @APuffer.Utf8[1];'#10'end;'#10'end.';
  mFound := TRuleAssert.IndexFindings(TFirstCharAddressRule.Create, mSource, mIndex, '', 'Sender.pas');
  Assert.AreEqual(4, Integer(Length(mFound)));
  Assert.AreEqual(6, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(7, mFound[1].Range.StartPos.Line);
  Assert.Contains(mFound[2].Message, 'PAnsiChar(APuffer.Roh)');
  Assert.Contains(mFound[3].Message, 'PAnsiChar(APuffer.Utf8)');
end;

procedure TFirstCharAddressTests.ConditionalDeclarationIsSilent;
begin
  TRuleAssert.Silent(TFirstCharAddressRule.Create, Source('const AText: string',
    '{$IFDEF BREIT}'#10'  mPuffer: string;'#10'{$ELSE}'#10'  mPuffer: array[1..10] of Byte;'#10'{$ENDIF}'#10,
    '  WriteBuffer(@mPuffer[1], 1);'#10));
end;

procedure TFirstCharAddressTests.OffAndExclude;
var
  mSource: string;
begin
  mSource := Source('const AText: string', '', '  WriteBuffer(@AText[1], 1);'#10);
  Assert.AreEqual(1, Integer(Length(Findings(mSource, '', 'Source/Sender.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(mSource, '{"rules": {"first-char-address": "off"}}',
    'Source/Sender.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(mSource, '{"rules": {"group:find-bugs": "off"}}',
    'Source/Sender.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(mSource,
    '{"rules": {"first-char-address": {"exclude": ["Source/*.pas"]}}}', 'Source/Sender.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TFirstCharAddressTests);

end.
