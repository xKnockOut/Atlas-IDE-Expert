unit Atlas.Core.EditorToolbar.Sections.Tests;

// Atlas-Editorleiste (#1101): Zielsuche der Abschnittssprünge in Unit,
// Programm, Package, Bibliothek und Include-Datei; Kommentare, Strings,
// mehrzeilige Strings, Direktiven und Interface-Typen zählen nicht;
// Hervorhebung des aktuellen Abschnitts und uses des aktuellen Abschnitts.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasSectionScannerTests = class
  public
    [Test]
    procedure FindsUnitSections;
    [Test]
    procedure IgnoresInterfaceTypes;
    [Test]
    procedure IgnoresCommentsStringsAndDirectives;
    [Test]
    procedure IgnoresMultilineStrings;
    [Test]
    procedure FallbackWithoutHeader;
    [Test]
    procedure ProgramHasOnlyUses;
    [Test]
    procedure PackageUsesContains;
    [Test]
    procedure LibraryHasOnlyUses;
    [Test]
    procedure IncludeHasNothing;
    [Test]
    procedure SectionAtHighlightsCurrentPart;
    [Test]
    procedure UsesTargetFollowsCurrentSection;
    [Test]
    procedure UsesTargetTogglesBetweenClauses;
    [Test]
    procedure StopsAtEndDot;
    [Test]
    procedure ScansWholeTextWithCrLf;
    [Test]
    procedure CountsLinesInCommentsStringsAndCr;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Outline.Breadcrumbs,
  Atlas.Core.EditorToolbar.Sections;

const
  cUnitCode =
    'unit uKundeForm;'#10 +                                    // 0
    '{ interface im Kommentar }'#10 +                          // 1
    'interface'#10 +                                           // 2
    ''#10 +                                                    // 3
    'uses Winapi.Windows, Vcl.Forms;'#10 +                     // 4
    'type'#10 +                                                // 5
    '  IKunde = interface'#10 +                                // 6
    '    procedure Speichere;'#10 +                            // 7
    '  end;'#10 +                                              // 8
    '  TfrmKunde = class(TForm)'#10 +                          // 9
    '    procedure btnSpeichernClick(Sender: TObject);'#10 +   // 10
    '  end;'#10 +                                              // 11
    'implementation'#10 +                                      // 12
    'uses System.SysUtils;'#10 +                               // 13
    'procedure TfrmKunde.btnSpeichernClick(Sender: TObject);'#10 + // 14
    'begin'#10 +                                               // 15
    '  if not PruefeEingaben then'#10 +                        // 16
    '    Exit;'#10 +                                           // 17
    'end;'#10 +                                                // 18
    'initialization'#10 +                                      // 19
    '  Registriere;'#10 +                                      // 20
    'finalization'#10 +                                        // 21
    '  Abmelden;'#10 +                                         // 22
    'end.';                                                    // 23

function Scan(const AText: string): TAtlasUnitSections;
begin
  Result := TAtlasSectionScanner.Scan(AText.Split([#10]));
end;

procedure CheckMark(const AMark: TAtlasSectionMark; ALine, ACharacter: Integer; const AWhat: string);
begin
  Assert.IsTrue(AMark.Found, AWhat + ' gefunden');
  Assert.AreEqual(ALine, AMark.Line, AWhat + ' Zeile');
  Assert.AreEqual(ACharacter, AMark.Character, AWhat + ' Spalte');
end;

procedure TAtlasSectionScannerTests.FindsUnitSections;
var
  mSections: TAtlasUnitSections;
begin
  mSections := Scan(cUnitCode);
  Assert.AreEqual<TAtlasSourceKind>(TAtlasSourceKind.Unit_, mSections.Kind);
  Assert.IsTrue(mSections.HasParts);
  CheckMark(mSections.InterfacePart, 2, 0, 'interface');
  CheckMark(mSections.ImplementationPart, 12, 0, 'implementation');
  CheckMark(mSections.Initialization_, 19, 0, 'initialization');
  CheckMark(mSections.Finalization_, 21, 0, 'finalization');
  CheckMark(mSections.InterfaceUses.Start, 4, 0, 'uses im interface');
  CheckMark(mSections.InterfaceUses.Stop, 4, 30, 'Ende der uses im interface');
  CheckMark(mSections.ImplementationUses.Start, 13, 0, 'uses in implementation');
  Assert.IsFalse(mSections.HeaderUses.Start.Found);
end;

procedure TAtlasSectionScannerTests.IgnoresInterfaceTypes;
var
  mSections: TAtlasUnitSections;
begin
  // IKunde = interface (Zeile 6) ist kein Abschnitt, auch wenn das echte interface fehlt.
  mSections := Scan('unit U;'#10'type IFoo = interface end;'#10'implementation'#10'end.');
  Assert.IsFalse(mSections.InterfacePart.Found, 'IFoo = interface');
  CheckMark(mSections.ImplementationPart, 2, 0, 'implementation');
  mSections := Scan('unit U;'#10'interface'#10'type'#10'  IFoo ='#10'    interface'#10'  end;'#10'implementation'#10'end.');
  CheckMark(mSections.InterfacePart, 1, 0, 'interface');
  // Auch dispinterface und &interface sind keine Abschnitte.
  mSections := Scan('unit U; type IFoo = dispinterface end; X = &interface; implementation end.');
  Assert.IsFalse(mSections.InterfacePart.Found, 'dispinterface, &interface');
end;

procedure TAtlasSectionScannerTests.IgnoresCommentsStringsAndDirectives;
var
  mSections: TAtlasUnitSections;
begin
  mSections := Scan(
    'unit U;'#10 +                                             // 0
    '(* implementation'#10 +                                   // 1
    '   interface *)'#10 +                                     // 2
    '{$IFDEF implementation} // implementation'#10 +           // 3
    '{$ENDIF}'#10 +                                            // 4
    'interface'#10 +                                           // 5
    'const A = ''implementation''; B = ''It''''s implementation'';'#10 + // 6
    '  C = ''''''''; // implementation'#10 +                     // 7
    '(*$IFDEF interface*)'#10 +                                // 8
    '  implementation'#10 +                                    // 9
    'end.');
  // Kommentare und Direktiven zwischen Kopf und interface zählen nicht; '''' ist ein String mit einem
  // Anführungszeichen, kein mehrzeiliger String.
  CheckMark(mSections.InterfacePart, 5, 0, 'interface');
  CheckMark(mSections.ImplementationPart, 9, 2, 'implementation');
end;

procedure TAtlasSectionScannerTests.IgnoresMultilineStrings;
var
  mSections: TAtlasUnitSections;
begin
  mSections := Scan(
    'unit U;'#10 +                                             // 0
    'interface'#10 +                                           // 1
    'const Text = '''''''#10 +                                 // 2
    '  implementation'#10 +                                    // 3
    '  uses'#10 +                                              // 4
    '  '''''';'#10 +                                           // 5
    'implementation'#10 +                                      // 6
    'end.');
  CheckMark(mSections.InterfacePart, 1, 0, 'interface');
  CheckMark(mSections.ImplementationPart, 6, 0, 'implementation');
  Assert.IsFalse(mSections.ImplementationUses.Start.Found, 'uses im mehrzeiligen String');
end;

procedure TAtlasSectionScannerTests.FallbackWithoutHeader;
var
  mSections: TAtlasUnitSections;
begin
  // Kaputter Kopf ohne Semikolon: das erste interface ohne „=“ davor.
  mSections := Scan('unit U'#10'interface'#10'implementation'#10'end.');
  CheckMark(mSections.InterfacePart, 1, 0, 'interface');
  CheckMark(mSections.ImplementationPart, 2, 0, 'implementation');
  // Gepunkteter Name mit Hinweis-Direktiven.
  mSections := Scan('unit Atlas.Foo.Bar platform deprecated ''alt'';'#10'  interface'#10'implementation'#10'end.');
  CheckMark(mSections.InterfacePart, 1, 2, 'interface eingerückt');
end;

procedure TAtlasSectionScannerTests.ProgramHasOnlyUses;
var
  mSections: TAtlasUnitSections;
  mMark: TAtlasSectionMark;
begin
  mSections := Scan('program AtlasServer;'#10'{$APPTYPE CONSOLE}'#10'uses Atlas.Server.Main;'#10 +
    'const interface_ = 1;'#10'begin'#10'  Run;'#10'end.');
  Assert.AreEqual<TAtlasSourceKind>(TAtlasSourceKind.Program_, mSections.Kind);
  Assert.IsFalse(mSections.HasParts);
  CheckMark(mSections.HeaderUses.Start, 2, 0, 'uses');
  Assert.IsFalse(mSections.Target(TAtlasSectionTarget.InterfacePart, 5, 2, mMark));
  Assert.IsFalse(mSections.Target(TAtlasSectionTarget.ImplementationPart, 5, 2, mMark));
  Assert.IsFalse(mSections.Target(TAtlasSectionTarget.Initialization_, 5, 2, mMark));
  Assert.IsTrue(mSections.Target(TAtlasSectionTarget.UsesClause, 5, 2, mMark));
  CheckMark(mMark, 2, 0, 'Ziel uses');
  Assert.AreEqual<TAtlasCodeSection>(TAtlasCodeSection.UsesClause, mSections.SectionAt(2, 8));
  Assert.AreEqual<TAtlasCodeSection>(TAtlasCodeSection.None, mSections.SectionAt(5, 2));
end;

procedure TAtlasSectionScannerTests.PackageUsesContains;
var
  mSections: TAtlasUnitSections;
begin
  mSections := Scan('package Atlas.IDE.Expert;'#10'requires'#10'  rtl;'#10'contains'#10'  Atlas.Core.Foo in ''Foo.pas'';'#10 +
    'end.');
  Assert.AreEqual<TAtlasSourceKind>(TAtlasSourceKind.Package, mSections.Kind);
  Assert.IsFalse(mSections.HasParts);
  CheckMark(mSections.HeaderUses.Start, 3, 0, 'contains');
  CheckMark(mSections.HeaderUses.Stop, 4, 29, 'Ende von contains');
end;

procedure TAtlasSectionScannerTests.LibraryHasOnlyUses;
var
  mSections: TAtlasUnitSections;
begin
  mSections := Scan('library Atlas;'#10'uses'#10'  System.SysUtils;'#10'exports Foo;'#10'begin'#10'end.');
  Assert.AreEqual<TAtlasSourceKind>(TAtlasSourceKind.Library_, mSections.Kind);
  CheckMark(mSections.HeaderUses.Start, 1, 0, 'uses');
  Assert.IsFalse(mSections.InterfacePart.Found);
end;

procedure TAtlasSectionScannerTests.IncludeHasNothing;
var
  mSections: TAtlasUnitSections;
  mMark: TAtlasSectionMark;
begin
  mSections := Scan('{$IFDEF DEBUG}'#10'interface'#10'implementation'#10'uses Foo;'#10'{$ENDIF}');
  Assert.AreEqual<TAtlasSourceKind>(TAtlasSourceKind.Include, mSections.Kind);
  Assert.IsFalse(mSections.HasParts);
  Assert.IsFalse(mSections.InterfacePart.Found);
  Assert.IsFalse(mSections.ImplementationPart.Found);
  Assert.IsFalse(mSections.Target(TAtlasSectionTarget.UsesClause, 0, 0, mMark));
  Assert.IsFalse(TAtlasSectionScanner.Scan(nil).HasParts, 'leer');
end;

procedure TAtlasSectionScannerTests.SectionAtHighlightsCurrentPart;
var
  mSections: TAtlasUnitSections;
begin
  mSections := Scan(cUnitCode);
  Assert.AreEqual<TAtlasCodeSection>(TAtlasCodeSection.None, mSections.SectionAt(0, 3), 'Kopf');
  Assert.AreEqual<TAtlasCodeSection>(TAtlasCodeSection.InterfacePart, mSections.SectionAt(2, 0), 'auf interface');
  Assert.AreEqual<TAtlasCodeSection>(TAtlasCodeSection.UsesClause, mSections.SectionAt(4, 10), 'uses');
  Assert.AreEqual<TAtlasCodeSection>(TAtlasCodeSection.InterfacePart, mSections.SectionAt(7, 4), 'im Typ');
  Assert.AreEqual<TAtlasCodeSection>(TAtlasCodeSection.UsesClause,
    mSections.SectionAt(13, 6), 'uses der implementation');
  Assert.AreEqual<TAtlasCodeSection>(TAtlasCodeSection.ImplementationPart, mSections.SectionAt(16, 4), 'Methode');
  Assert.AreEqual<TAtlasCodeSection>(TAtlasCodeSection.Initialization_, mSections.SectionAt(20, 2), 'initialization');
  Assert.AreEqual<TAtlasCodeSection>(TAtlasCodeSection.Finalization_, mSections.SectionAt(22, 2), 'finalization');
end;

procedure TAtlasSectionScannerTests.UsesTargetFollowsCurrentSection;
var
  mSections: TAtlasUnitSections;
  mMark: TAtlasSectionMark;
begin
  mSections := Scan(cUnitCode);
  Assert.IsTrue(mSections.Target(TAtlasSectionTarget.UsesClause, 16, 4, mMark));
  CheckMark(mMark, 13, 0, 'uses der implementation');
  Assert.IsTrue(mSections.Target(TAtlasSectionTarget.UsesClause, 7, 4, mMark));
  CheckMark(mMark, 4, 0, 'uses des interface');
  // Ohne uses in der implementation: die des interface.
  mSections := Scan('unit U;'#10'interface'#10'uses A;'#10'implementation'#10'procedure X; begin end;'#10'end.');
  Assert.IsTrue(mSections.Target(TAtlasSectionTarget.UsesClause, 4, 2, mMark));
  CheckMark(mMark, 2, 0, 'Rückfall auf interface');
  Assert.IsTrue(mSections.Target(TAtlasSectionTarget.InterfacePart, 4, 2, mMark));
  CheckMark(mMark, 1, 0, 'interface');
  Assert.IsFalse(mSections.Target(TAtlasSectionTarget.Initialization_, 4, 2, mMark), 'ohne initialization');
end;

procedure TAtlasSectionScannerTests.UsesTargetTogglesBetweenClauses;
var
  mSections: TAtlasUnitSections;
  mMark: TAtlasSectionMark;
  mToImplementation: Boolean;
begin
  mSections := Scan(cUnitCode);
  // In der interface-uses: zur implementation-uses und zurück.
  Assert.IsTrue(mSections.UsesToggle(4, 10, mToImplementation));
  Assert.IsTrue(mToImplementation);
  Assert.IsTrue(mSections.Target(TAtlasSectionTarget.UsesClause, 4, 10, mMark));
  CheckMark(mMark, 13, 0, 'zur implementation-uses');
  Assert.IsTrue(mSections.Target(TAtlasSectionTarget.UsesClause, mMark.Line, mMark.Character, mMark));
  CheckMark(mMark, 4, 0, 'zurück zur interface-uses');
  Assert.IsFalse(mSections.UsesToggle(16, 4, mToImplementation), 'außerhalb einer Klausel');
  // Ohne implementation-uses: zum Schlüsselwort implementation, von dort zurück.
  mSections := Scan('unit U;'#10'interface'#10'uses A;'#10'implementation'#10'procedure X; begin end;'#10'end.');
  Assert.IsTrue(mSections.Target(TAtlasSectionTarget.UsesClause, 2, 0, mMark));
  CheckMark(mMark, 3, 0, 'implementation');
  Assert.IsTrue(mSections.Target(TAtlasSectionTarget.UsesClause, mMark.Line, mMark.Character, mMark));
  CheckMark(mMark, 2, 0, 'zurück zur interface-uses');
  // Ohne interface-uses: zum Schlüsselwort interface, von dort zurück.
  mSections := Scan('unit U;'#10'interface'#10'implementation'#10'uses B;'#10'end.');
  Assert.IsTrue(mSections.Target(TAtlasSectionTarget.UsesClause, 3, 2, mMark));
  CheckMark(mMark, 1, 0, 'interface');
  Assert.IsTrue(mSections.Target(TAtlasSectionTarget.UsesClause, mMark.Line, mMark.Character, mMark));
  CheckMark(mMark, 3, 0, 'zurück zur implementation-uses');
  // Programme: unverändert die Klausel nach dem Kopf.
  mSections := Scan('program P;'#10'uses A;'#10'begin'#10'end.');
  Assert.IsFalse(mSections.UsesToggle(1, 2, mToImplementation));
  Assert.IsTrue(mSections.Target(TAtlasSectionTarget.UsesClause, 1, 2, mMark));
  CheckMark(mMark, 1, 0, 'uses des Programms');
end;

procedure TAtlasSectionScannerTests.StopsAtEndDot;
var
  mSections: TAtlasUnitSections;
begin
  mSections := Scan('unit U;'#10'interface'#10'implementation'#10'end.'#10'initialization'#10'uses X;');
  Assert.IsFalse(mSections.Initialization_.Found);
  Assert.IsFalse(mSections.ImplementationUses.Start.Found);
end;

procedure TAtlasSectionScannerTests.ScansWholeTextWithCrLf;
var
  mSections: TAtlasUnitSections;
begin
  mSections := TAtlasSectionScanner.Scan(cUnitCode.Replace(#10, #13#10));
  CheckMark(mSections.InterfacePart, 2, 0, 'interface');
  CheckMark(mSections.ImplementationPart, 12, 0, 'implementation');
  CheckMark(mSections.InterfaceUses.Stop, 4, 30, 'Ende der uses im interface');
end;

procedure TAtlasSectionScannerTests.CountsLinesInCommentsStringsAndCr;
var
  mSections: TAtlasUnitSections;
begin
  // Zeilen in Kommentaren und mehrzeiligen Strings zählen mit; CR allein trennt ebenfalls.
  mSections := TAtlasSectionScanner.Scan('Unit U;'#13'{ eins'#13#10'zwei }'#10'  INTERFACE'#10 +
    '(* drei'#10'*) const S = '''''''#10'implementation'#10'  '''''';'#13#10'Implementation'#10'end.');
  CheckMark(mSections.InterfacePart, 3, 2, 'interface');
  CheckMark(mSections.ImplementationPart, 8, 0, 'implementation nach dem String');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSectionScannerTests);

end.
