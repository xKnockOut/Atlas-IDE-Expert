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
  BaseFile = 'C:\P\Basis.pas';
  MainFile = 'C:\P\Haupt.pas';

  UnitBase =
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

  UnitMain =
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
      if SameText(AFileName, BaseFile) then
        AText := UnitBase
      else if SameText(AFileName, MainFile) then
        AText := UnitMain
      else
        Result := False;
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
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitBase, BaseFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitMain, MainFile, nil));
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
  Owner: TResolvedSymbol;
begin
  Assert.IsTrue(FResolver.ResolveTypeFrom(MainUnit, AType, Owner), AType);
  Assert.IsTrue(FResolver.DeclaredMember(Owner, AName, Result), AType + '.' + AName);
end;

procedure TLspDocumentationTests.LoadsCommentWithoutInheritDoc;
var
  Doc: TXmlDoc;
  Lines: TArray<string>;
begin
  Lines := TLspDocumentation.SplitLines(UnitBase);
  // Zeile 14: procedure Paint im TBasis.
  Doc := TLspDocumentation.Load(nil, Default(TResolvedSymbol), Lines, 14, nil);
  Assert.AreEqual('Zeichnet die Form.', Doc.Summary);
  Assert.AreEqual(1, Integer(Length(Doc.Params)));
  Assert.AreEqual('AFarbe', Doc.Params[0].Name);
  Assert.IsFalse(Doc.InheritDoc);
end;

procedure TLspDocumentationTests.InheritsFromAncestorMember;
var
  Symbol: TResolvedSymbol;
  Doc: TXmlDoc;
begin
  Symbol := Member('TKreis', 'Paint');
  Doc := TLspDocumentation.Load(FResolver, Symbol, TLspDocumentation.SplitLines(UnitMain), SymbolLine(Symbol),
    ReadFiles());
  Assert.AreEqual('Zeichnet die Form.', Doc.Summary);
  Assert.AreEqual(1, Integer(Length(Doc.Params)));
  Assert.IsTrue(Pos('Breite', Doc.Remarks) > 0, Doc.Remarks);
end;

procedure TLspDocumentationTests.OwnSectionsWinMissingComeFromAncestor;
var
  Symbol: TResolvedSymbol;
  Doc: TXmlDoc;
begin
  Symbol := Member('TQuadrat', 'Paint');
  Doc := TLspDocumentation.Load(FResolver, Symbol, TLspDocumentation.SplitLines(UnitMain), SymbolLine(Symbol),
    ReadFiles());
  Assert.AreEqual('Zeichnet vier Ecken.', Doc.Summary);
  Assert.AreEqual(1, Integer(Length(Doc.Params)), 'Parameter vom Vorfahren');
  Assert.AreEqual('Füllfarbe', Doc.Params[0].Text);
end;

procedure TLspDocumentationTests.InheritsFromInterface;
var
  Symbol: TResolvedSymbol;
  Doc: TXmlDoc;
begin
  Symbol := Member('TLaeufer', 'Lauf');
  Doc := TLspDocumentation.Load(FResolver, Symbol, TLspDocumentation.SplitLines(UnitMain), SymbolLine(Symbol),
    ReadFiles());
  Assert.AreEqual('Läuft los.', Doc.Summary);
end;

procedure TLspDocumentationTests.InheritsTypeDocFromAncestorType;
var
  Symbol: TResolvedSymbol;
  Doc: TXmlDoc;
begin
  Assert.IsTrue(FResolver.ResolveTypeFrom(MainUnit, 'TKreis', Symbol));
  Doc := TLspDocumentation.Load(FResolver, Symbol, TLspDocumentation.SplitLines(UnitMain), SymbolLine(Symbol),
    ReadFiles());
  Assert.AreEqual('Die Basis aller Formen.', Doc.Summary);
end;

procedure TLspDocumentationTests.InheritsFromCref;
var
  Symbol: TResolvedSymbol;
  Doc: TXmlDoc;
begin
  Assert.IsTrue(FResolver.ResolveNameFrom(MainUnit, 'Male', Symbol));
  Doc := TLspDocumentation.Load(FResolver, Symbol, TLspDocumentation.SplitLines(UnitMain), SymbolLine(Symbol),
    ReadFiles());
  Assert.AreEqual('Zeichnet die Form.', Doc.Summary);
end;

procedure TLspDocumentationTests.WithoutSymbolKeepsOwnDoc;
var
  Symbol: TResolvedSymbol;
  Doc: TXmlDoc;
begin
  Symbol := Member('TKreis', 'Paint');
  // Ohne Resolver bzw. ohne Lesefunktion bleibt nur der eigene (leere) Kommentar.
  Doc := TLspDocumentation.Load(nil, Symbol, TLspDocumentation.SplitLines(UnitMain), SymbolLine(Symbol), nil);
  Assert.IsTrue(Doc.InheritDoc);
  Assert.AreEqual('', Doc.Summary);
  Doc := TLspDocumentation.Load(FResolver, Symbol, TLspDocumentation.SplitLines(UnitMain), SymbolLine(Symbol),
    nil);
  Assert.AreEqual('', Doc.Summary, 'Basis.pas nicht lesbar');
end;

procedure TLspDocumentationTests.LocatesTypesMembersAndGlobals;
var
  Found: TResolvedSymbol;
begin
  Assert.IsTrue(FResolver.LocateCref(MainUnit, '', 'TBasis', Found));
  Assert.AreEqual('TBasis', Found.Name);
  Assert.IsTrue(FResolver.LocateCref(MainUnit, '', 'TBasis.Paint(System.Int32)', Found));
  Assert.AreEqual('Paint', Found.Name);
  Assert.AreEqual(BaseFile, Found.FileName);
  Assert.IsTrue(FResolver.LocateCref(MainUnit, 'TBasis', 'Breite', Found), 'Eigenes Mitglied');
  Assert.AreEqual('Breite', Found.Name);
  Assert.IsTrue(FResolver.LocateCref(MainUnit, '', 'Zaehler', Found), 'Globale Variable');
  Assert.AreEqual(MainFile, Found.FileName);
  Assert.IsFalse(FResolver.LocateCref(MainUnit, '', 'Unbekannt', Found));
  Assert.IsFalse(FResolver.LocateCref(MainUnit, '', '  ', Found));
  Assert.IsFalse(FResolver.LocateCref(MainUnit, '', 'Integer', Found), 'Eingebaute Typen nicht');
end;

procedure TLspDocumentationTests.TargetsResolveRefsAndExceptions;
var
  Doc: TXmlDoc;
  Targets: TArray<TDocTarget>;
begin
  Doc := TXmlDoc.Parse('<summary>Siehe <see cref="TBasis"/> und <see cref="TBasis"/>, nicht ' +
    '<see cref="Gibtsnicht"/>.</summary><exception cref="ELaufFehler">bei Fehler</exception>');
  Targets := TLspDocumentation.Targets(FResolver, MainUnit, '', Doc);
  Assert.AreEqual(2, Integer(Length(Targets)), 'Doppelte einmal, unbekannte fehlen');
  Assert.AreEqual('TBasis', Targets[0].Cref);
  Assert.AreEqual(BaseFile, Targets[0].FileName);
  Assert.AreEqual('Basis', Targets[0].UnitName);
  Assert.AreEqual(10, Targets[0].Line);
  Assert.AreEqual(2, Targets[0].Character);
  Assert.AreEqual('ELaufFehler', Targets[1].Name);
  Assert.AreEqual(0, Integer(Length(TLspDocumentation.Targets(nil, MainUnit, '', Doc))));
  Targets := nil;
end;

procedure TLspDocumentationTests.ToJsonCarriesSectionsRunsAndLocations;
var
  Doc: TXmlDoc;
  Target: TDocTarget;
  Json: TJSONObject;
  Text: string;
begin
  Doc := TXmlDoc.Parse('<summary><b>Fett</b> und <see cref="TBasis"/></summary>' +
    '<param name="A">Wert</param><exception cref="ELaufFehler">kaputt</exception>');
  Target := Default(TDocTarget);
  Target.Cref := 'TBasis';
  Target.Name := 'TBasis';
  Target.UnitName := 'Basis';
  Target.FileName := BaseFile;
  Target.Line := 10;
  Target.Character := 2;
  Json := TLspDocumentation.ToJson(Doc, [Target]);
  try
    Text := Json.ToJSON;
    Assert.AreEqual(3, (Json.GetValue('sections') as TJSONArray).Count);
    Assert.Contains(Text, '"kind":"summary"');
    Assert.Contains(Text, '"bold":true');
    Assert.Contains(Text, '"target":"TBasis","name":"TBasis","unit":"Basis"');
    Assert.Contains(Text, '"line":10,"character":2');
    Assert.Contains(Text, '"kind":"param","name":"A"');
    // Exception ohne Fundort: kein "ref".
    Assert.IsFalse(Pos('"ref":{', Text) > 0, Text);
  finally
    Json.Free;
  end;
  Json := TLspDocumentation.ToJson(Default(TXmlDoc), nil);
  try
    Assert.AreEqual('{"sections":[]}', Json.ToJSON);
  finally
    Json.Free;
  end;
end;

procedure TLspDocumentationTests.HintsJsonPassesSettings;
var
  Hints: THintSettings;
  Json: TJSONObject;
begin
  Hints := THintSettings.Default;
  Hints.XmlDocExpand := THintSettings.ExpandExpanded;
  Hints.XmlDocMaxLines := 12;
  Json := TLspDocumentation.HintsJson(Hints);
  try
    Assert.AreEqual('{"expand":"expanded","maxLines":12}', Json.ToJSON);
  finally
    Json.Free;
  end;
  Hints.XmlDocExpand := THintSettings.ExpandCollapsed;
  Hints.XmlDocMaxLines := 0;
  Json := TLspDocumentation.HintsJson(Hints);
  try
    Assert.AreEqual('{"expand":"collapsed","maxLines":0}', Json.ToJSON);
  finally
    Json.Free;
  end;
end;

procedure TLspDocumentationTests.ReaderPrefersOwnText;
var
  Reader: TDocReadText;
  Text: string;
begin
  Reader := TLspDocumentation.Reader(MainFile, 'ungespeichert', ReadFiles());
  Assert.IsTrue(Reader('c:\p\haupt.pas', Text));
  Assert.AreEqual('ungespeichert', Text, 'Editorinhalt vor der Datei');
  Assert.IsTrue(Reader(BaseFile, Text));
  Assert.AreEqual(UnitBase, Text);
  Assert.IsFalse(Reader('C:\P\Fehlt.pas', Text));
  Reader := TLspDocumentation.Reader(MainFile, 'x', nil);
  Assert.IsFalse(Reader(BaseFile, Text), 'Ohne Lesefunktion nur die eigene Datei');
  Reader := nil;
end;

procedure TLspDocumentationTests.SplitLinesHandlesAllLineBreaks;
var
  Lines: TArray<string>;
begin
  Lines := TLspDocumentation.SplitLines('a'#13#10'b'#10'c'#13'd');
  Assert.AreEqual(4, Integer(Length(Lines)));
  Assert.AreEqual('a', Lines[0]);
  Assert.AreEqual('d', Lines[3]);
  Lines := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspDocumentationTests);

end.
