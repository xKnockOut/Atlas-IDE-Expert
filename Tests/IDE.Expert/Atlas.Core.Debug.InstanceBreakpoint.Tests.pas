unit Atlas.Core.Debug.InstanceBreakpoint.Tests;

// Haltepunkt nur für ein bestimmtes Objekt (#857), Kern: Adressen lesen,
// Bedingungen zusammensetzen, Adressbedingungen erkennen, entfernen und
// ersetzen, Anzeige mit Etikett, Felder für „Nur wenn …“ und ob eine Routine
// ein Self hat.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TCoreDebugInstanceBreakpointTests = class
  public
    [Test]
    procedure ParsesAddressesFromDebugger;
    [Test]
    procedure RejectsNilAndText;
    [Test]
    procedure AddressConditionBothStyles;
    [Test]
    procedure KeepsExistingConditionWithAnd;
    [Test]
    procedure ConjunctsRespectOrStringsAndParens;
    [Test]
    procedure RecognizesAddressConditions;
    [Test]
    procedure RestrictReplacesEarlierObject;
    [Test]
    procedure RemovesAndReplacesAddress;
    [Test]
    procedure OrphansAreConditionsWithAddress;
    [Test]
    procedure DisplayShowsLabelInsteadOfAddress;
    [Test]
    procedure FieldChoicesSkipPointersAndObjects;
    [Test]
    procedure RoutineHasSelfOnlyInMethods;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Debug.Evaluate,
  Atlas.Core.Debug.InstanceBreakpoint;

const
  cAddress = UInt64($0A3F1C20);

procedure TCoreDebugInstanceBreakpointTests.ParsesAddressesFromDebugger;
var
  mAddress: UInt64;
begin
  Assert.IsTrue(TAtlasInstanceBreakpoint.TryParseAddress('$A3F1C20', mAddress));
  Assert.AreEqual<UInt64>(cAddress, mAddress);
  Assert.IsTrue(TAtlasInstanceBreakpoint.TryParseAddress(':0A3F1C20', mAddress));
  Assert.AreEqual<UInt64>(cAddress, mAddress);
  Assert.IsTrue(TAtlasInstanceBreakpoint.TryParseAddress(' Pointer($0a3f1c20) ', mAddress));
  Assert.AreEqual<UInt64>(cAddress, mAddress);
  Assert.IsTrue(TAtlasInstanceBreakpoint.TryParseAddress('0x00007FF6A3F1C20', mAddress));
  Assert.AreEqual<UInt64>(mAddress, UInt64($00007FF6A3F1C20));
  Assert.AreEqual('$0A3F1C20', TAtlasInstanceBreakpoint.AddressText(cAddress));
  Assert.AreEqual('$7FF6A3F1C20', TAtlasInstanceBreakpoint.AddressText(UInt64($7FF6A3F1C20)));
end;

procedure TCoreDebugInstanceBreakpointTests.RejectsNilAndText;
var
  mAddress: UInt64;
begin
  Assert.IsFalse(TAtlasInstanceBreakpoint.TryParseAddress('nil', mAddress));
  Assert.IsFalse(TAtlasInstanceBreakpoint.TryParseAddress('$0', mAddress));
  Assert.IsFalse(TAtlasInstanceBreakpoint.TryParseAddress('', mAddress));
  Assert.IsFalse(TAtlasInstanceBreakpoint.TryParseAddress('E2003 Undeclared identifier', mAddress));
  Assert.IsFalse(TAtlasInstanceBreakpoint.TryParseAddress('$12345678901234567', mAddress));
end;

procedure TCoreDebugInstanceBreakpointTests.AddressConditionBothStyles;
begin
  Assert.AreEqual('Pointer(Self) = Pointer($0A3F1C20)',
    TAtlasInstanceBreakpoint.AddressCondition(cAddress, TAtlasInstanceStyle.Pointer));
  Assert.AreEqual('NativeUInt(Self) = $0A3F1C20',
    TAtlasInstanceBreakpoint.AddressCondition(cAddress, TAtlasInstanceStyle.NativeUInt));
  Assert.AreEqual('Nr = 4711', TAtlasInstanceBreakpoint.FieldCondition(' Nr ', '4711'));
  Assert.AreEqual('', TAtlasInstanceBreakpoint.FieldCondition('Nr', ''));
end;

procedure TCoreDebugInstanceBreakpointTests.KeepsExistingConditionWithAnd;
begin
  Assert.AreEqual('(Betrag > 0) and (Pointer(Self) = Pointer($0A3F1C20))',
    TAtlasInstanceBreakpoint.RestrictToObject('Betrag > 0', cAddress, TAtlasInstanceStyle.Pointer));
  Assert.AreEqual('Pointer(Self) = Pointer($0A3F1C20)',
    TAtlasInstanceBreakpoint.RestrictToObject('', cAddress, TAtlasInstanceStyle.Pointer));
  // „or“ bindet schwächer als „and“: die vorhandene Bedingung bleibt als Ganzes in Klammern.
  Assert.AreEqual('(A or B) and (Nr = 4711)', TAtlasInstanceBreakpoint.Combine('A or B', 'Nr = 4711'));
  Assert.AreEqual('Aktiv and (Nr = 4711)', TAtlasInstanceBreakpoint.Combine('Aktiv', 'Nr = 4711'));
  // Eine gleiche Bedingung kommt nicht doppelt hinein.
  Assert.AreEqual('(Nr = 4711) and Aktiv', TAtlasInstanceBreakpoint.Combine('(Nr = 4711) and Aktiv', 'nr=4711'));
end;

procedure TCoreDebugInstanceBreakpointTests.ConjunctsRespectOrStringsAndParens;
var
  mParts: TArray<string>;
begin
  mParts := TAtlasInstanceBreakpoint.Conjuncts('(A > 1) and (Name = ''x and y'') and Sand');
  Assert.AreEqual(3, Integer(Length(mParts)));
  Assert.AreEqual('A > 1', mParts[0]);
  Assert.AreEqual('Name = ''x and y''', mParts[1]);
  Assert.AreEqual('Sand', mParts[2]);
  mParts := TAtlasInstanceBreakpoint.Conjuncts('A and B or C');
  Assert.AreEqual(1, Integer(Length(mParts)));
  Assert.AreEqual('A and B or C', mParts[0]);
  mParts := TAtlasInstanceBreakpoint.Conjuncts('((A) and (B))');
  Assert.AreEqual(2, Integer(Length(mParts)));
  Assert.AreEqual(0, Integer(Length(TAtlasInstanceBreakpoint.Conjuncts('  '))));
end;

procedure TCoreDebugInstanceBreakpointTests.RecognizesAddressConditions;
var
  mAddress: UInt64;
begin
  Assert.IsTrue(TAtlasInstanceBreakpoint.IsAddressCondition('pointer( self )=Pointer($0A3F1C20)', mAddress));
  Assert.AreEqual<UInt64>(cAddress, mAddress);
  Assert.IsTrue(TAtlasInstanceBreakpoint.IsAddressCondition('(NativeUInt(Self) = $A3F1C20)', mAddress));
  Assert.AreEqual<UInt64>(cAddress, mAddress);
  Assert.IsFalse(TAtlasInstanceBreakpoint.IsAddressCondition('Pointer(Kunde) = Pointer($0A3F1C20)', mAddress));
  Assert.IsFalse(TAtlasInstanceBreakpoint.IsAddressCondition('Pointer(Self) = Pointer($0A3F1C20) + 1', mAddress));
  Assert.IsTrue(TAtlasInstanceBreakpoint.HasAddressCondition(
    '(Betrag > 0) and (Pointer(Self) = Pointer($0A3F1C20))'));
  Assert.IsFalse(TAtlasInstanceBreakpoint.HasAddressCondition(
    'Betrag > 0 or Pointer(Self) = Pointer($0A3F1C20)'));
end;

procedure TCoreDebugInstanceBreakpointTests.RestrictReplacesEarlierObject;
begin
  Assert.AreEqual('(Betrag > 0) and (Pointer(Self) = Pointer($00001000))',
    TAtlasInstanceBreakpoint.RestrictToObject('(Betrag > 0) and (Pointer(Self) = Pointer($0A3F1C20))',
    UInt64($1000), TAtlasInstanceStyle.Pointer));
end;

procedure TCoreDebugInstanceBreakpointTests.RemovesAndReplacesAddress;
const
  cCondition = '(Betrag > 0) and (Pointer(Self) = Pointer($0A3F1C20))';
begin
  Assert.AreEqual('Betrag > 0', TAtlasInstanceBreakpoint.WithoutAddress(cCondition));
  Assert.AreEqual('', TAtlasInstanceBreakpoint.WithoutAddress('Pointer(Self) = Pointer($0A3F1C20)'));
  // Ohne Adressteil bleibt die Bedingung, wie sie ist.
  Assert.AreEqual('A or B', TAtlasInstanceBreakpoint.WithoutAddress(' A or B '));
  Assert.AreEqual('(Betrag > 0) and (Nr = 4711)', TAtlasInstanceBreakpoint.ReplaceAddress(cCondition, 'Nr = 4711'));
  Assert.AreEqual('Betrag > 0', TAtlasInstanceBreakpoint.ReplaceAddress('Betrag > 0', 'Nr = 4711'));
end;

procedure TCoreDebugInstanceBreakpointTests.OrphansAreConditionsWithAddress;
var
  mOrphans: TArray<Integer>;
begin
  mOrphans := TAtlasInstanceBreakpoint.Orphans(TArray<string>.Create('', 'Betrag > 0',
    'Pointer(Self) = Pointer($0A3F1C20)', 'Nr = 4711 and (NativeUInt(Self) = $1000)'));
  Assert.AreEqual(2, Integer(Length(mOrphans)));
  Assert.AreEqual(2, mOrphans[0]);
  Assert.AreEqual(3, mOrphans[1]);
end;

procedure TCoreDebugInstanceBreakpointTests.DisplayShowsLabelInsteadOfAddress;
var
  mLabels: TArray<TAtlasObjectLabel>;
begin
  SetLength(mLabels, 1);
  mLabels[0].Address := cAddress;
  mLabels[0].Caption := 'Kunde A';
  Assert.AreEqual('Betrag > 0 and nur Objekt Kunde A', TAtlasInstanceBreakpoint.DisplayText(
    '(Betrag > 0) and (Pointer(Self) = Pointer($0A3F1C20))', 'nur Objekt %s', mLabels));
  Assert.AreEqual('nur Objekt $00001000', TAtlasInstanceBreakpoint.DisplayText(
    'NativeUInt(Self) = $1000', 'nur Objekt %s', mLabels));
  Assert.AreEqual('A > 1', TAtlasInstanceBreakpoint.DisplayText(' A > 1', 'nur Objekt %s', mLabels));
end;

procedure TCoreDebugInstanceBreakpointTests.FieldChoicesSkipPointersAndObjects;
var
  mFields: TAtlasEvalParts;
begin
  mFields := TAtlasInstanceBreakpoint.FieldChoices(
    '((FOwner: nil; FName: ''Basis''); FNr: 4711; FName: ''Meier''; FListe: $0A3F1C20; ' +
    'FAdresse: (Ort: ''Köln''); FAktiv: True; FArt: kaPrivat; FCallback: Pointer($1000))');
  Assert.AreEqual(4, Integer(Length(mFields)));
  Assert.AreEqual('FName', mFields[0].Name);
  Assert.AreEqual('''Basis''', mFields[0].Value);
  Assert.AreEqual('FNr', mFields[1].Name);
  Assert.AreEqual('4711', mFields[1].Value);
  Assert.AreEqual('FAktiv', mFields[2].Name);
  Assert.AreEqual('FArt', mFields[3].Name);
  Assert.AreEqual(0, Integer(Length(TAtlasInstanceBreakpoint.FieldChoices('$0A3F1C20'))));
end;

procedure TCoreDebugInstanceBreakpointTests.RoutineHasSelfOnlyInMethods;
var
  mLines: TArray<string>;
begin
  mLines := TArray<string>.Create(
    'implementation',                          // 0
    '',                                        // 1
    'procedure TKunde.Speichere;',             // 2
    '',                                        // 3
    '  procedure Innen;',                      // 4
    '  begin',                                 // 5
    '    Schreibe;',                           // 6
    '  end;',                                  // 7
    '',                                        // 8
    'begin',                                   // 9
    '  Innen;',                                // 10
    'end;',                                    // 11
    '',                                        // 12
    'procedure Frei;',                         // 13
    'begin',                                   // 14
    '  Tue;',                                  // 15
    'end;',                                    // 16
    '',                                        // 17
    'class function TKunde.Neu: TKunde;',      // 18
    'begin',                                   // 19
    '  Result := nil;',                        // 20
    'end;',                                    // 21
    '',                                        // 22
    'var',                                     // 23
    '  GZaehler: Integer;');                   // 24
  Assert.IsTrue(TAtlasInstanceBreakpoint.RoutineHasSelf(mLines, 10));
  Assert.IsTrue(TAtlasInstanceBreakpoint.RoutineHasSelf(mLines, 6), 'verschachtelte Routine in einer Methode');
  Assert.IsTrue(TAtlasInstanceBreakpoint.RoutineHasSelf(mLines, 2));
  Assert.IsFalse(TAtlasInstanceBreakpoint.RoutineHasSelf(mLines, 15), 'freie Routine');
  Assert.IsFalse(TAtlasInstanceBreakpoint.RoutineHasSelf(mLines, 20), 'Klassenmethode');
  Assert.IsFalse(TAtlasInstanceBreakpoint.RoutineHasSelf(mLines, 24), 'außerhalb einer Routine');
  Assert.IsFalse(TAtlasInstanceBreakpoint.RoutineHasSelf(mLines, 0));
  Assert.IsFalse(TAtlasInstanceBreakpoint.RoutineHasSelf(mLines, 99));
end;

end.
