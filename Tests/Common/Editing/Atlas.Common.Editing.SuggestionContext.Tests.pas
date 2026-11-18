unit Atlas.Common.Editing.SuggestionContext.Tests;

// Tests für das Wissen aus dem Index zu Vorschlägen eines KI-Anbieters (#1922): Klasse der umgebenden Methode,
// Köpfe der Klasse und ihrer Mitglieder, Grenze der Zeilen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TSuggestionContextTests = class
  public
    [Test]
    procedure ClassOfMethodBody;
    [Test]
    procedure ClassOfClassMethodAndConstructor;
    [Test]
    procedure NestedRoutineUsesOuterMethod;
    [Test]
    procedure NothingForPlainRoutineOrInterface;
    [Test]
    procedure MembersStartWithTheClass;
    [Test]
    procedure MembersAreLimited;
    [Test]
    procedure DeclarationsFromDeclaringUnit;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Editing.SuggestionContext;

const
  cBody =
    'unit A;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'procedure Frei;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure TKunde.Speichern(const AName: string);'#10 +
    '  procedure Innen;'#10 +
    '  begin'#10 +
    '  end;'#10 +
    'begin'#10 +
    #10 +
    'end;'#10 +
    'class function TKunde.Neu: TKunde;'#10 +
    'begin'#10 +
    #10 +
    'end;'#10 +
    'constructor TListe.Create;'#10 +
    'begin'#10 +
    #10 +
    'end;'#10 +
    'procedure Danach;'#10 +
    'begin'#10 +
    #10 +
    'end;'#10 +
    'end.';
  cCustomer =
    'unit Kunden;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TKunde = class'#10 +
    '  private'#10 +
    '    FName: string;'#10 +
    '    FAlter: Integer;'#10 +
    '  public'#10 +
    '    procedure Speichern(const AName: string);'#10 +
    '    property Name: string read FName;'#10 +
    '  end;'#10 +
    '  TAnders = class'#10 +
    '    FWert: Integer;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TKunde.Speichern(const AName: string);'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

{ TSuggestionContextTests }

procedure TSuggestionContextTests.ClassOfMethodBody;
begin
  Assert.AreEqual('TKunde', TSuggestionContext.ClassAt(cBody, 11));
end;

procedure TSuggestionContextTests.ClassOfClassMethodAndConstructor;
begin
  Assert.AreEqual('TKunde', TSuggestionContext.ClassAt(cBody, 15));
  Assert.AreEqual('TListe', TSuggestionContext.ClassAt(cBody, 19));
end;

procedure TSuggestionContextTests.NestedRoutineUsesOuterMethod;
begin
  Assert.AreEqual('TKunde', TSuggestionContext.ClassAt(cBody, 8));
end;

procedure TSuggestionContextTests.NothingForPlainRoutineOrInterface;
begin
  Assert.AreEqual('', TSuggestionContext.ClassAt(cBody, 4), 'Routine ohne Klasse');
  Assert.AreEqual('', TSuggestionContext.ClassAt(cBody, 1), 'interface');
  Assert.AreEqual('', TSuggestionContext.ClassAt(cBody, 23), 'Routine ohne Klasse nach einer Methode');
end;

procedure TSuggestionContextTests.MembersStartWithTheClass;
var
  mLines: TArray<string>;
begin
  mLines := TSuggestionContext.MembersOf(TIndexExtractor.ExtractText(cCustomer, 'C:\P\Kunden.pas', nil), 'TKunde');
  Assert.IsTrue(Length(mLines) >= 4, string.Join(' | ', mLines));
  Assert.IsTrue(Pos('TKunde = class', mLines[0]) > 0, mLines[0]);
  Assert.IsTrue(Pos('FName', string.Join(' | ', mLines)) > 0, string.Join(' | ', mLines));
  Assert.IsTrue(Pos('Speichern', string.Join(' | ', mLines)) > 0, string.Join(' | ', mLines));
  Assert.IsFalse(Pos('FWert', string.Join(' | ', mLines)) > 0, 'Mitglied einer anderen Klasse');
end;

procedure TSuggestionContextTests.MembersAreLimited;
var
  mText: string;
  mIndex: Integer;
begin
  mText := 'unit Gross;'#10'interface'#10'type'#10'  TGross = class'#10;
  for mIndex := 1 to TSuggestionContext.cMaxDeclarations + 20 do
  begin
    mText := mText + '    F' + IntToStr(mIndex) + ': Integer;'#10;
  end;
  mText := mText + '  end;'#10'implementation'#10'end.';
  Assert.AreEqual(TSuggestionContext.cMaxDeclarations, Integer(Length(TSuggestionContext.MembersOf(
    TIndexExtractor.ExtractText(mText, 'C:\P\Gross.pas', nil), 'TGross'))));
end;

procedure TSuggestionContextTests.DeclarationsFromDeclaringUnit;
var
  mIndex: ISymbolIndex;
  mLines: TArray<string>;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText(cCustomer, 'C:\P\Kunden.pas', nil, nil, False, True));
  mLines := TSuggestionContext.Declarations(mIndex, 'C:\P\A.pas', cBody, 11);
  Assert.IsTrue(Pos('FAlter', string.Join(' | ', mLines)) > 0, string.Join(' | ', mLines));
  Assert.AreEqual(0, Integer(Length(TSuggestionContext.Declarations(mIndex, 'C:\P\A.pas', cBody, 4))));
  Assert.AreEqual(0, Integer(Length(TSuggestionContext.Declarations(nil, 'C:\P\A.pas', cBody, 11))), 'ohne Index');
end;

initialization
  TDUnitX.RegisterTestFixture(TSuggestionContextTests);

end.
