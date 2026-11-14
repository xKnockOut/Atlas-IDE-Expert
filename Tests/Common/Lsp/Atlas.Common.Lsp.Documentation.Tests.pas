unit Atlas.Common.Lsp.Documentation.Tests;

// Tests für XMLDoc in Hover, Parameter-Hint und Vervollständigung (#654,
// #415): Load mit <inheritdoc/> über Vorfahr, Interface, Vorfahrtyp und cref,
// fehlende Abschnitte vom Vorfahren, Locate für Typ, Typ.Mitglied, eigenes
// Mitglied und globale Namen, Targets, ToJson, HintsJson, Reader und
// SplitLines.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver;

type
  [TestFixture]
  TLspDocumentationTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function MainUnit: TUnitIndex;
    function Member(const AType, AName: string): TResolvedSymbol;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure LoadsCommentWithoutInheritDoc;
    [Test]
    procedure InheritsFromAncestorMember;
    [Test]
    procedure OwnSectionsWinMissingComeFromAncestor;
    [Test]
    procedure InheritsFromInterface;
    [Test]
    procedure InheritsTypeDocFromAncestorType;
    [Test]
    procedure InheritsFromCref;
    [Test]
    procedure WithoutSymbolKeepsOwnDoc;
    [Test]
    procedure LocatesTypesMembersAndGlobals;
    [Test]
    procedure TargetsResolveRefsAndExceptions;
    [Test]
    procedure ToJsonCarriesSectionsRunsAndLocations;
    [Test]
    procedure ToJsonOmitsLocationsInIdeUnits;
    [Test]
    procedure HintsJsonPassesSettings;
    [Test]
    procedure ReaderPrefersOwnText;
    [Test]
    procedure SplitLinesHandlesAllLineBreaks;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Pascal.XmlDoc,
  Atlas.Common.Lsp.Documentation;

const
  cBaseFile = 'C:\P\Basis.pas';
  cMainFile = 'C:\P\Haupt.pas';

  cUnitBase =
    'unit Basis;'#10 +
    'interface'#10 +
    'type'#10 +
    '  ELaufFehler = class(Exception);'#10 +
    '  /// <summary>Etwas Laufendes.</summary>'#10 +
    '  ILauf = interface'#10 +
    '    /// <summary>Läuft los.</summary>'#10 +
    '    procedure Lauf;'#10 +
    '  end;'#10 +
    '  /// <summary>Die Basis aller Formen.</summary>'#10 +
    '  TBasis = class'#10 +
    '    /// <summary>Zeichnet die Form.</summary>'#10 +
    '    /// <param name="AFarbe">Füllfarbe</param>'#10 +
    '    /// <remarks>Vorher <see cref="Breite"/> setzen.</remarks>'#10 +
    '    procedure Paint(AFarbe: Integer); virtual;'#10 +
    '    Breite: Integer;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TBasis.Paint(AFarbe: Integer);'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

  cUnitMain =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses Basis;'#10 +
    'type'#10 +
    '  /// <inheritdoc/>'#10 +
    '  TKreis = class(TBasis)'#10 +
    '    /// <inheritdoc/>'#10 +
    '    procedure Paint(AFarbe: Integer); override;'#10 +
    '  end;'#10 +
    '  TQuadrat = class(TBasis)'#10 +
    '    /// <summary>Zeichnet vier Ecken.</summary>'#10 +
    '    /// <inheritdoc/>'#10 +
    '    procedure Paint(AFarbe: Integer); override;'#10 +
    '  end;'#10 +
    '  TLaeufer = class(TInterfacedObject, ILauf)'#10 +
    '    /// <inheritdoc/>'#10 +
    '    procedure Lauf;'#10 +
    '  end;'#10 +
    '/// <inheritdoc cref="TBasis.Paint"/>'#10 +
    'procedure Male(AFarbe: Integer);'#10 +
    '/// <summary>Zählt mit.</summary>'#10 +
    'var Zaehler: Integer;'#10 +
    'implementation'#10 +
    'procedure TKreis.Paint(AFarbe: Integer);'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure TQuadrat.Paint(AFarbe: Integer);'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure TLaeufer.Lauf;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure Male(AFarbe: Integer);'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

function ReadFiles: TDocReadText;
begin
  Result :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := True;
      if SameText(AFileName, cBaseFile) then
      begin
        AText := cUnitBase;
      end
      else if SameText(AFileName, cMainFile) then
      begin
        AText := cUnitMain;
      end
      else
      begin
        Result := False;
      end;
    end;
end;

function SymbolLine(const ASymbol: TResolvedSymbol): Integer;
begin
  Result := ASymbol.Range.StartPos.Line;
end;

{ TLspDocumentationTests }

procedure TLspDocumentationTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitBase, cBaseFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitMain, cMainFile, nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TLspDocumentationTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TLspDocumentationTests.MainUnit: TUnitIndex;
begin
  Assert.IsTrue(FIndex.FindUnit('Haupt', Result));
end;

function TLspDocumentationTests.Member(const AType, AName: string): TResolvedSymbol;
var
  mOwner: TResolvedSymbol;
begin
  Assert.IsTrue(FResolver.ResolveTypeFrom(MainUnit, AType, mOwner), AType);
  Assert.IsTrue(FResolver.DeclaredMember(mOwner, AName, Result), AType + '.' + AName);
end;

procedure TLspDocumentationTests.LoadsCommentWithoutInheritDoc;
var
  mDoc: TXmlDoc;
  mLines: TArray<string>;
begin
  mLines := TLspDocumentation.SplitLines(cUnitBase);
  // Zeile 14: procedure Paint im TBasis.
  mDoc := TLspDocumentation.Load(nil, Default(TResolvedSymbol), mLines, 14, nil);
  Assert.AreEqual('Zeichnet die Form.', mDoc.Summary);
  Assert.AreEqual(1, Integer(Length(mDoc.Params)));
  Assert.AreEqual('AFarbe', mDoc.Params[0].Name);
  Assert.IsFalse(mDoc.InheritDoc);
end;

procedure TLspDocumentationTests.InheritsFromAncestorMember;
var
  mSymbol: TResolvedSymbol;
  mDoc: TXmlDoc;
begin
  mSymbol := Member('TKreis', 'Paint');
  mDoc := TLspDocumentation.Load(FResolver, mSymbol, TLspDocumentation.SplitLines(cUnitMain), SymbolLine(mSymbol),
    ReadFiles());
  Assert.AreEqual('Zeichnet die Form.', mDoc.Summary);
  Assert.AreEqual(1, Integer(Length(mDoc.Params)));
  Assert.IsTrue(Pos('Breite', mDoc.Remarks) > 0, mDoc.Remarks);
end;

procedure TLspDocumentationTests.OwnSectionsWinMissingComeFromAncestor;
var
  mSymbol: TResolvedSymbol;
  mDoc: TXmlDoc;
begin
  mSymbol := Member('TQuadrat', 'Paint');
  mDoc := TLspDocumentation.Load(FResolver, mSymbol, TLspDocumentation.SplitLines(cUnitMain), SymbolLine(mSymbol),
    ReadFiles());
  Assert.AreEqual('Zeichnet vier Ecken.', mDoc.Summary);
  Assert.AreEqual(1, Integer(Length(mDoc.Params)), 'Parameter vom Vorfahren');
  Assert.AreEqual('Füllfarbe', mDoc.Params[0].Text);
end;

procedure TLspDocumentationTests.InheritsFromInterface;
var
  mSymbol: TResolvedSymbol;
  mDoc: TXmlDoc;
begin
  mSymbol := Member('TLaeufer', 'Lauf');
  mDoc := TLspDocumentation.Load(FResolver, mSymbol, TLspDocumentation.SplitLines(cUnitMain), SymbolLine(mSymbol),
    ReadFiles());
  Assert.AreEqual('Läuft los.', mDoc.Summary);
end;

procedure TLspDocumentationTests.InheritsTypeDocFromAncestorType;
var
  mSymbol: TResolvedSymbol;
  mDoc: TXmlDoc;
begin
  Assert.IsTrue(FResolver.ResolveTypeFrom(MainUnit, 'TKreis', mSymbol));
  mDoc := TLspDocumentation.Load(FResolver, mSymbol, TLspDocumentation.SplitLines(cUnitMain), SymbolLine(mSymbol),
    ReadFiles());
  Assert.AreEqual('Die Basis aller Formen.', mDoc.Summary);
end;

procedure TLspDocumentationTests.InheritsFromCref;
var
  mSymbol: TResolvedSymbol;
  mDoc: TXmlDoc;
begin
  Assert.IsTrue(FResolver.ResolveNameFrom(MainUnit, 'Male', mSymbol));
  mDoc := TLspDocumentation.Load(FResolver, mSymbol, TLspDocumentation.SplitLines(cUnitMain), SymbolLine(mSymbol),
    ReadFiles());
  Assert.AreEqual('Zeichnet die Form.', mDoc.Summary);
end;

procedure TLspDocumentationTests.WithoutSymbolKeepsOwnDoc;
var
  mSymbol: TResolvedSymbol;
  mDoc: TXmlDoc;
begin
  mSymbol := Member('TKreis', 'Paint');
  // Ohne Resolver bzw. ohne Lesefunktion bleibt nur der eigene (leere) Kommentar.
  mDoc := TLspDocumentation.Load(nil, mSymbol, TLspDocumentation.SplitLines(cUnitMain), SymbolLine(mSymbol), nil);
  Assert.IsTrue(mDoc.InheritDoc);
  Assert.AreEqual('', mDoc.Summary);
  mDoc := TLspDocumentation.Load(FResolver, mSymbol, TLspDocumentation.SplitLines(cUnitMain), SymbolLine(mSymbol),
    nil);
  Assert.AreEqual('', mDoc.Summary, 'Basis.pas nicht lesbar');
end;

procedure TLspDocumentationTests.LocatesTypesMembersAndGlobals;
var
  mFound: TResolvedSymbol;
begin
  Assert.IsTrue(FResolver.LocateCref(MainUnit, '', 'TBasis', mFound));
  Assert.AreEqual('TBasis', mFound.Name);
  Assert.IsTrue(FResolver.LocateCref(MainUnit, '', 'TBasis.Paint(System.Int32)', mFound));
  Assert.AreEqual('Paint', mFound.Name);
  Assert.AreEqual(cBaseFile, mFound.FileName);
  Assert.IsTrue(FResolver.LocateCref(MainUnit, 'TBasis', 'Breite', mFound), 'Eigenes Mitglied');
  Assert.AreEqual('Breite', mFound.Name);
  Assert.IsTrue(FResolver.LocateCref(MainUnit, '', 'Zaehler', mFound), 'Globale Variable');
  Assert.AreEqual(cMainFile, mFound.FileName);
  Assert.IsFalse(FResolver.LocateCref(MainUnit, '', 'Unbekannt', mFound));
  Assert.IsFalse(FResolver.LocateCref(MainUnit, '', '  ', mFound));
  Assert.IsFalse(FResolver.LocateCref(MainUnit, '', 'Integer', mFound), 'Eingebaute Typen nicht');
end;

procedure TLspDocumentationTests.TargetsResolveRefsAndExceptions;
var
  mDoc: TXmlDoc;
  mTargets: TArray<TDocTarget>;
begin
  mDoc := TXmlDoc.Parse('<summary>Siehe <see cref="TBasis"/> und <see cref="TBasis"/>, nicht ' +
    '<see cref="Gibtsnicht"/>.</summary><exception cref="ELaufFehler">bei Fehler</exception>');
  mTargets := TLspDocumentation.Targets(FResolver, MainUnit, '', mDoc);
  Assert.AreEqual(2, Integer(Length(mTargets)), 'Doppelte einmal, unbekannte fehlen');
  Assert.AreEqual('TBasis', mTargets[0].Cref);
  Assert.AreEqual(cBaseFile, mTargets[0].FileName);
  Assert.AreEqual('Basis', mTargets[0].UnitName);
  Assert.AreEqual(10, mTargets[0].Line);
  Assert.AreEqual(2, mTargets[0].Character);
  Assert.AreEqual('ELaufFehler', mTargets[1].Name);
  Assert.AreEqual(0, Integer(Length(TLspDocumentation.Targets(nil, MainUnit, '', mDoc))));
  mTargets := nil;
end;

procedure TLspDocumentationTests.ToJsonOmitsLocationsInIdeUnits;
var
  mDoc: TXmlDoc;
  mTarget: TDocTarget;
  mJson: TJSONObject;
  mText: string;
begin
  mDoc := TXmlDoc.Parse('<summary>Wie <see cref="TForm"/></summary><exception cref="EFormFehler">x</exception>');
  mTarget := Default(TDocTarget);
  mTarget.Cref := 'TForm';
  mTarget.Name := 'TForm';
  mTarget.UnitName := 'Vcl.Forms';
  mTarget.FileName := 'atlas-ide:Vcl.Forms.pas';
  mTarget.Line := 3;
  mTarget.Character := 2;
  mJson := TLspDocumentation.ToJson(mDoc, [mTarget]);
  try
    mText := mJson.ToJSON;
    // Name und Unit bleiben, ein Fundort (und damit ein Sprungziel) fehlt.
    Assert.Contains(mText, '"target":"TForm","name":"TForm","unit":"Vcl.Forms"');
    Assert.IsFalse(Pos('atlas-ide:', mText) > 0, mText);
    Assert.IsFalse(Pos('"file"', mText) > 0, mText);
  finally
    mJson.Free;
  end;
end;

procedure TLspDocumentationTests.ToJsonCarriesSectionsRunsAndLocations;
var
  mDoc: TXmlDoc;
  mTarget: TDocTarget;
  mJson: TJSONObject;
  mText: string;
begin
  mDoc := TXmlDoc.Parse('<summary><b>Fett</b> und <see cref="TBasis"/></summary>' +
    '<param name="A">Wert</param><exception cref="ELaufFehler">kaputt</exception>');
  mTarget := Default(TDocTarget);
  mTarget.Cref := 'TBasis';
  mTarget.Name := 'TBasis';
  mTarget.UnitName := 'Basis';
  mTarget.FileName := cBaseFile;
  mTarget.Line := 10;
  mTarget.Character := 2;
  mJson := TLspDocumentation.ToJson(mDoc, [mTarget]);
  try
    mText := mJson.ToJSON;
    Assert.AreEqual(3, (mJson.GetValue('sections') as TJSONArray).Count);
    Assert.Contains(mText, '"kind":"summary"');
    Assert.Contains(mText, '"bold":true');
    Assert.Contains(mText, '"target":"TBasis","name":"TBasis","unit":"Basis"');
    Assert.Contains(mText, '"line":10,"character":2');
    Assert.Contains(mText, '"kind":"param","name":"A"');
    // Exception ohne Fundort: kein "ref".
    Assert.IsFalse(Pos('"ref":{', mText) > 0, mText);
  finally
    mJson.Free;
  end;
  mJson := TLspDocumentation.ToJson(Default(TXmlDoc), nil);
  try
    Assert.AreEqual('{"sections":[]}', mJson.ToJSON);
  finally
    mJson.Free;
  end;
end;

procedure TLspDocumentationTests.HintsJsonPassesSettings;
var
  mHints: THintSettings;
  mJson: TJSONObject;
begin
  mHints := THintSettings.Default;
  mHints.XmlDocExpand := THintSettings.cExpandExpanded;
  mHints.XmlDocMaxLines := 12;
  mJson := TLspDocumentation.HintsJson(mHints);
  try
    Assert.AreEqual('{"expand":"expanded","maxLines":12}', mJson.ToJSON);
  finally
    mJson.Free;
  end;
  mHints.XmlDocExpand := THintSettings.cExpandCollapsed;
  mHints.XmlDocMaxLines := 0;
  mJson := TLspDocumentation.HintsJson(mHints);
  try
    Assert.AreEqual('{"expand":"collapsed","maxLines":0}', mJson.ToJSON);
  finally
    mJson.Free;
  end;
end;

procedure TLspDocumentationTests.ReaderPrefersOwnText;
var
  mReader: TDocReadText;
  mText: string;
begin
  mReader := TLspDocumentation.Reader(cMainFile, 'ungespeichert', ReadFiles());
  Assert.IsTrue(mReader('c:\p\haupt.pas', mText));
  Assert.AreEqual('ungespeichert', mText, 'Editorinhalt vor der Datei');
  Assert.IsTrue(mReader(cBaseFile, mText));
  Assert.AreEqual(cUnitBase, mText);
  Assert.IsFalse(mReader('C:\P\Fehlt.pas', mText));
  mReader := TLspDocumentation.Reader(cMainFile, 'x', nil);
  Assert.IsFalse(mReader(cBaseFile, mText), 'Ohne Lesefunktion nur die eigene Datei');
  mReader := nil;
end;

procedure TLspDocumentationTests.SplitLinesHandlesAllLineBreaks;
var
  mLines: TArray<string>;
begin
  mLines := TLspDocumentation.SplitLines('a'#13#10'b'#10'c'#13'd');
  Assert.AreEqual(4, Integer(Length(mLines)));
  Assert.AreEqual('a', mLines[0]);
  Assert.AreEqual('d', mLines[3]);
  mLines := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspDocumentationTests);

end.
