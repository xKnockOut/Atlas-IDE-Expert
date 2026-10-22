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
    procedure StopsAtEndDot;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Outline.Breadcrumbs,
  Atlas.Core.EditorToolbar.Sections;

const
  UnitCode =
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
  Sections: TAtlasUnitSections;
begin
  Sections := Scan(UnitCode);
  Assert.IsTrue(Sections.Kind = TAtlasSourceKind.Unit_);
  Assert.IsTrue(Sections.HasParts);
  CheckMark(Sections.InterfacePart, 2, 0, 'interface');
  CheckMark(Sections.ImplementationPart, 12, 0, 'implementation');
  CheckMark(Sections.Initialization_, 19, 0, 'initialization');
  CheckMark(Sections.Finalization_, 21, 0, 'finalization');
  CheckMark(Sections.InterfaceUses.Start, 4, 0, 'uses im interface');
  CheckMark(Sections.InterfaceUses.Stop, 4, 30, 'Ende der uses im interface');
  CheckMark(Sections.ImplementationUses.Start, 13, 0, 'uses in implementation');
  Assert.IsFalse(Sections.HeaderUses.Start.Found);
end;

procedure TAtlasSectionScannerTests.IgnoresInterfaceTypes;
var
  Sections: TAtlasUnitSections;
begin
  // IKunde = interface (Zeile 6) ist kein Abschnitt, auch wenn das echte interface fehlt.
  Sections := Scan('unit U;'#10'type IFoo = interface end;'#10'implementation'#10'end.');
  Assert.IsFalse(Sections.InterfacePart.Found, 'IFoo = interface');
  CheckMark(Sections.ImplementationPart, 2, 0, 'implementation');
  Sections := Scan('unit U;'#10'interface'#10'type'#10'  IFoo ='#10'    interface'#10'  end;'#10'implementation'#10'end.');
  CheckMark(Sections.InterfacePart, 1, 0, 'interface');
  // Auch dispinterface und &interface sind keine Abschnitte.
  Sections := Scan('unit U; type IFoo = dispinterface end; X = &interface; implementation end.');
  Assert.IsFalse(Sections.InterfacePart.Found, 'dispinterface, &interface');
end;

procedure TAtlasSectionScannerTests.IgnoresCommentsStringsAndDirectives;
var
  Sections: TAtlasUnitSections;
begin
  Sections := Scan(
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
  CheckMark(Sections.InterfacePart, 5, 0, 'interface');
  CheckMark(Sections.ImplementationPart, 9, 2, 'implementation');
end;

procedure TAtlasSectionScannerTests.IgnoresMultilineStrings;
var
  Sections: TAtlasUnitSections;
begin
  Sections := Scan(
    'unit U;'#10 +                                             // 0
    'interface'#10 +                                           // 1
    'const Text = '''''''#10 +                                 // 2
    '  implementation'#10 +                                    // 3
    '  uses'#10 +                                              // 4
    '  '''''';'#10 +                                           // 5
    'implementation'#10 +                                      // 6
    'end.');
  CheckMark(Sections.InterfacePart, 1, 0, 'interface');
  CheckMark(Sections.ImplementationPart, 6, 0, 'implementation');
  Assert.IsFalse(Sections.ImplementationUses.Start.Found, 'uses im mehrzeiligen String');
end;

procedure TAtlasSectionScannerTests.FallbackWithoutHeader;
var
  Sections: TAtlasUnitSections;
begin
  // Kaputter Kopf ohne Semikolon: das erste interface ohne „=“ davor.
  Sections := Scan('unit U'#10'interface'#10'implementation'#10'end.');
  CheckMark(Sections.InterfacePart, 1, 0, 'interface');
  CheckMark(Sections.ImplementationPart, 2, 0, 'implementation');
  // Gepunkteter Name mit Hinweis-Direktiven.
  Sections := Scan('unit Atlas.Foo.Bar platform deprecated ''alt'';'#10'  interface'#10'implementation'#10'end.');
  CheckMark(Sections.InterfacePart, 1, 2, 'interface eingerückt');
end;

procedure TAtlasSectionScannerTests.ProgramHasOnlyUses;
var
  Sections: TAtlasUnitSections;
  Mark: TAtlasSectionMark;
begin
  Sections := Scan('program AtlasServer;'#10'{$APPTYPE CONSOLE}'#10'uses Atlas.Server.Main;'#10 +
    'const interface_ = 1;'#10'begin'#10'  Run;'#10'end.');
  Assert.IsTrue(Sections.Kind = TAtlasSourceKind.Program_);
  Assert.IsFalse(Sections.HasParts);
  CheckMark(Sections.HeaderUses.Start, 2, 0, 'uses');
  Assert.IsFalse(Sections.Target(TAtlasSectionTarget.InterfacePart, 5, 2, Mark));
  Assert.IsFalse(Sections.Target(TAtlasSectionTarget.ImplementationPart, 5, 2, Mark));
  Assert.IsFalse(Sections.Target(TAtlasSectionTarget.Initialization_, 5, 2, Mark));
  Assert.IsTrue(Sections.Target(TAtlasSectionTarget.UsesClause, 5, 2, Mark));
  CheckMark(Mark, 2, 0, 'Ziel uses');
  Assert.IsTrue(Sections.SectionAt(2, 8) = TAtlasCodeSection.UsesClause);
  Assert.IsTrue(Sections.SectionAt(5, 2) = TAtlasCodeSection.None);
end;

procedure TAtlasSectionScannerTests.PackageUsesContains;
var
  Sections: TAtlasUnitSections;
begin
  Sections := Scan('package Atlas.IDE.Expert;'#10'requires'#10'  rtl;'#10'contains'#10'  Atlas.Core.Foo in ''Foo.pas'';'#10 +
    'end.');
  Assert.IsTrue(Sections.Kind = TAtlasSourceKind.Package);
  Assert.IsFalse(Sections.HasParts);
  CheckMark(Sections.HeaderUses.Start, 3, 0, 'contains');
  CheckMark(Sections.HeaderUses.Stop, 4, 29, 'Ende von contains');
end;

procedure TAtlasSectionScannerTests.LibraryHasOnlyUses;
var
  Sections: TAtlasUnitSections;
begin
  Sections := Scan('library Atlas;'#10'uses'#10'  System.SysUtils;'#10'exports Foo;'#10'begin'#10'end.');
  Assert.IsTrue(Sections.Kind = TAtlasSourceKind.Library_);
  CheckMark(Sections.HeaderUses.Start, 1, 0, 'uses');
  Assert.IsFalse(Sections.InterfacePart.Found);
end;

procedure TAtlasSectionScannerTests.IncludeHasNothing;
var
  Sections: TAtlasUnitSections;
  Mark: TAtlasSectionMark;
begin
  Sections := Scan('{$IFDEF DEBUG}'#10'interface'#10'implementation'#10'uses Foo;'#10'{$ENDIF}');
  Assert.IsTrue(Sections.Kind = TAtlasSourceKind.Include);
  Assert.IsFalse(Sections.HasParts);
  Assert.IsFalse(Sections.InterfacePart.Found);
  Assert.IsFalse(Sections.ImplementationPart.Found);
  Assert.IsFalse(Sections.Target(TAtlasSectionTarget.UsesClause, 0, 0, Mark));
  Assert.IsFalse(TAtlasSectionScanner.Scan(nil).HasParts, 'leer');
end;

procedure TAtlasSectionScannerTests.SectionAtHighlightsCurrentPart;
var
  Sections: TAtlasUnitSections;
begin
  Sections := Scan(UnitCode);
  Assert.IsTrue(Sections.SectionAt(0, 3) = TAtlasCodeSection.None, 'Kopf');
  Assert.IsTrue(Sections.SectionAt(2, 0) = TAtlasCodeSection.InterfacePart, 'auf interface');
  Assert.IsTrue(Sections.SectionAt(4, 10) = TAtlasCodeSection.UsesClause, 'uses');
  Assert.IsTrue(Sections.SectionAt(7, 4) = TAtlasCodeSection.InterfacePart, 'im Typ');
  Assert.IsTrue(Sections.SectionAt(13, 6) = TAtlasCodeSection.UsesClause, 'uses der implementation');
  Assert.IsTrue(Sections.SectionAt(16, 4) = TAtlasCodeSection.ImplementationPart, 'Methode');
  Assert.IsTrue(Sections.SectionAt(20, 2) = TAtlasCodeSection.Initialization_, 'initialization');
  Assert.IsTrue(Sections.SectionAt(22, 2) = TAtlasCodeSection.Finalization_, 'finalization');
end;

procedure TAtlasSectionScannerTests.UsesTargetFollowsCurrentSection;
var
  Sections: TAtlasUnitSections;
  Mark: TAtlasSectionMark;
begin
  Sections := Scan(UnitCode);
  Assert.IsTrue(Sections.Target(TAtlasSectionTarget.UsesClause, 16, 4, Mark));
  CheckMark(Mark, 13, 0, 'uses der implementation');
  Assert.IsTrue(Sections.Target(TAtlasSectionTarget.UsesClause, 7, 4, Mark));
  CheckMark(Mark, 4, 0, 'uses des interface');
  // Ohne uses in der implementation: die des interface.
  Sections := Scan('unit U;'#10'interface'#10'uses A;'#10'implementation'#10'procedure X; begin end;'#10'end.');
  Assert.IsTrue(Sections.Target(TAtlasSectionTarget.UsesClause, 4, 2, Mark));
  CheckMark(Mark, 2, 0, 'Rückfall auf interface');
  Assert.IsTrue(Sections.Target(TAtlasSectionTarget.InterfacePart, 4, 2, Mark));
  CheckMark(Mark, 1, 0, 'interface');
  Assert.IsFalse(Sections.Target(TAtlasSectionTarget.Initialization_, 4, 2, Mark), 'ohne initialization');
end;

procedure TAtlasSectionScannerTests.StopsAtEndDot;
var
  Sections: TAtlasUnitSections;
begin
  Sections := Scan('unit U;'#10'interface'#10'implementation'#10'end.'#10'initialization'#10'uses X;');
  Assert.IsFalse(Sections.Initialization_.Found);
  Assert.IsFalse(Sections.ImplementationUses.Start.Found);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSectionScannerTests);

end.
