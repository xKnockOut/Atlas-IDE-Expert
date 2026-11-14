unit Atlas.Common.Lsp.SignatureHelp.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.SignatureHelp;

type
  [TestFixture]
  TLspSignatureHelpTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function HelpAt(const ACode, AMarker: string): TSignatureHelp;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure FindsCallSiteAndActiveParameter;
    [Test]
    procedure NestedCallsAndBracketsAreSkipped;
    [Test]
    procedure ParsesSignatureOverSeveralLines;
    [Test]
    procedure ListsOverloadsWithDocumentation;
    [Test]
    procedure MethodShowsDeclarationOnly;
    [Test]
    procedure WritesSignatureHelp;
    [Test]
    procedure TypesLiteralArguments;
    [Test]
    procedure ArgumentFitsByFamily;
    [Test]
    procedure CharArgumentsDimDuplicatesOverload;
    [Test]
    procedure FirstCharLiteralSkipsBooleanOverload;
    [Test]
    procedure BooleanAndEnumArgumentsPickTheirOverload;
    [Test]
    procedure UnknownArgumentsFitAll;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor;

const
  cHauptFile = 'C:\P\Haupt.pas';
  cWerkzeugFile = 'C:\P\Werkzeug.pas';
  cListenFile = 'C:\P\Listen.pas';

  // Überladungen wie bei TStringList.Create (#498), eigene Beispiel-Unit.
  cUnitListen =
    'unit Listen;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TDoppelte = (dupIgnorieren, dupAnnehmen, dupFehler);'#10 +
    '  TListenOption = (loOhneLeere, loSortiert);'#10 +
    '  TListenOptionen = set of TListenOption;'#10 +
    '  TListe = class'#10 +
    '  public'#10 +
    '    constructor Create; overload;'#10 +
    '    constructor Create(OwnsObjects: Boolean); overload;'#10 +
    '    constructor Create(QuoteChar, Delimiter: Char); overload;'#10 +
    '    constructor Create(QuoteChar, Delimiter: Char; Options: TListenOptionen); overload;'#10 +
    '    constructor Create(Duplicates: TDoppelte; Sorted: Boolean; CaseSensitive: Boolean); overload;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';

  cUnitWerkzeug =
    'unit Werkzeug;'#10 +
    'interface'#10 +
    '/// <summary>Rechnet.</summary>'#10 +
    '/// <param name="Wert">Eingabe</param>'#10 +
    'function Rechne(Wert: Integer): Integer; overload;'#10 +
    'function Rechne(const A, B: Double;'#10 +
    '  Runden: Boolean = True): Double; overload;'#10 +
    'implementation'#10 +
    'function Rechne(Wert: Integer): Integer;'#10 +
    'begin'#10 +
    'end;'#10 +
    'function Rechne(const A, B: Double; Runden: Boolean): Double;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

  cUnitHaupt =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses Werkzeug, Listen;'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '    procedure Bar(Anzahl: Integer; const Name: string);'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TFoo.Bar(Anzahl: Integer; const Name: string);'#10 +
    'begin'#10 +
    '  |'#10 +
    'end;'#10 +
    'end.';

function PositionOf(const AText, AMarker: string): TTextPosition;
var
  mIndex, mLine, mLineStart, mScan: Integer;
begin
  // Cursor hinter AMarker.
  mIndex := Pos(AMarker, AText);
  if mIndex = 0 then
  begin
    raise Exception.CreateFmt('"%s" nicht gefunden', [AMarker]);
  end;
  Inc(mIndex, Length(AMarker));
  mLine := 0;
  mLineStart := 1;
  for mScan := 1 to mIndex - 1 do
  begin
    if AText[mScan] = #10 then
    begin
      Inc(mLine);
      mLineStart := mScan + 1;
    end;
  end;
  Result := TTextPosition.Create(mLine, mIndex - mLineStart);
end;

function ReadWerkzeug(const AFileName: string; out AText: string): Boolean;
begin
  if SameText(AFileName, cListenFile) then
  begin
    AText := cUnitListen;
  end
  else
  begin
    AText := cUnitWerkzeug;
  end;
  Result := SameText(AFileName, cWerkzeugFile) or SameText(AFileName, cListenFile);
end;

{ TLspSignatureHelpTests }

procedure TLspSignatureHelpTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitWerkzeug, cWerkzeugFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitListen, cListenFile, nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TLspSignatureHelpTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TLspSignatureHelpTests.HelpAt(const ACode, AMarker: string): TSignatureHelp;
var
  mText: string;
  mTree: TSyntaxTree;
begin
  mText := StringReplace(cUnitHaupt, '  |', ACode, []);
  mTree := TPascalParser.Parse(mText);
  try
    Result := TLspSignatureHelp.HelpAt(TSignatureHelpRequest.Create(FResolver, FIndex, mTree, mText, cHauptFile,
      ReadWerkzeug), PositionOf(mText, AMarker));
  finally
    mTree.Free;
  end;
end;

procedure TLspSignatureHelpTests.FindsCallSiteAndActiveParameter;
var
  mTree: TSyntaxTree;
  mSite: TCallSite;
begin
  mTree := TPascalParser.Parse('begin Rechne(1, 2, ');
  try
    mSite := TLspSignatureHelp.CallSiteAt(mTree, TTextPosition.Create(0, 19));
    Assert.IsTrue(mSite.Found);
    Assert.AreEqual(6, mSite.NamePosition.Character);
    Assert.AreEqual(2, mSite.ActiveParameter);
    // Hinter der schließenden Klammer und nach ; ist kein Aufruf mehr offen.
    Assert.IsFalse(TLspSignatureHelp.CallSiteAt(mTree, TTextPosition.Create(0, 5)).Found);
  finally
    mTree.Free;
  end;
  mTree := TPascalParser.Parse('begin Rechne(1); X');
  try
    Assert.IsFalse(TLspSignatureHelp.CallSiteAt(mTree, TTextPosition.Create(0, 18)).Found);
    Assert.IsFalse(TLspSignatureHelp.CallSiteAt(mTree, TTextPosition.Create(0, 15)).Found);
  finally
    mTree.Free;
  end;
end;

procedure TLspSignatureHelpTests.NestedCallsAndBracketsAreSkipped;
var
  mTree: TSyntaxTree;
  mSite: TCallSite;
begin
  mTree := TPascalParser.Parse('begin Rechne(Liste[1, 2], (3 + 4), Max(5, 6), ');
  try
    mSite := TLspSignatureHelp.CallSiteAt(mTree, TTextPosition.Create(0, 46));
    Assert.IsTrue(mSite.Found);
    Assert.AreEqual(6, mSite.NamePosition.Character);
    Assert.AreEqual(3, mSite.ActiveParameter);
    mSite := TLspSignatureHelp.CallSiteAt(mTree, TTextPosition.Create(0, 42));
    Assert.AreEqual(35, mSite.NamePosition.Character);
    Assert.AreEqual(1, mSite.ActiveParameter);
  finally
    mTree.Free;
  end;
end;

procedure TLspSignatureHelpTests.ParsesSignatureOverSeveralLines;
var
  mSignature: TSignature;
begin
  mSignature := TLspSignatureHelp.ParseSignature(['  function TFoo.Rechne(const A, B: Double;',
    '    Runden: Boolean = True): Double; overload;'], 0, 2);
  Assert.AreEqual('function Rechne(const A, B: Double; Runden: Boolean = True): Double', mSignature.Text);
  Assert.IsTrue(mSignature.Qualified);
  Assert.AreEqual(3, Integer(Length(mSignature.Parameters)));
  Assert.AreEqual('A', Copy(mSignature.Text, mSignature.Parameters[0].StartIndex + 1,
    mSignature.Parameters[0].EndIndex - mSignature.Parameters[0].StartIndex));
  Assert.AreEqual('B', Copy(mSignature.Text, mSignature.Parameters[1].StartIndex + 1,
    mSignature.Parameters[1].EndIndex - mSignature.Parameters[1].StartIndex));
  Assert.AreEqual('Runden: Boolean = True', Copy(mSignature.Text, mSignature.Parameters[2].StartIndex + 1,
    mSignature.Parameters[2].EndIndex - mSignature.Parameters[2].StartIndex));
end;

procedure TLspSignatureHelpTests.ListsOverloadsWithDocumentation;
var
  mHelp: TSignatureHelp;
begin
  mHelp := HelpAt('  Rechne(1.5, ', 'Rechne(1.5, ');
  Assert.AreEqual(2, Integer(Length(mHelp.Signatures)));
  Assert.AreEqual('function Rechne(Wert: Integer): Integer', mHelp.Signatures[0].Text);
  Assert.AreEqual('Rechnet.', mHelp.Signatures[0].Documentation);
  Assert.AreEqual('Eingabe', mHelp.Signatures[0].Parameters[0].Documentation);
  Assert.AreEqual(1, mHelp.ActiveParameter);
  // Die erste Überladung hat nur einen Parameter.
  Assert.AreEqual(1, mHelp.ActiveSignature);
end;

procedure TLspSignatureHelpTests.MethodShowsDeclarationOnly;
var
  mHelp: TSignatureHelp;
begin
  mHelp := HelpAt('  Bar(', '  Bar(');
  Assert.AreEqual(1, Integer(Length(mHelp.Signatures)));
  Assert.AreEqual('procedure Bar(Anzahl: Integer; const Name: string)', mHelp.Signatures[0].Text);
  Assert.AreEqual(0, mHelp.ActiveParameter);
  Assert.IsFalse(HelpAt('  Unbekannt(', 'Unbekannt(').Found);
end;

procedure TLspSignatureHelpTests.WritesSignatureHelp;
var
  mHelp: TSignatureHelp;
  mJson: TJSONValue;
begin
  // Ohne Default stünde in Format.Problem (Aufzählung, nicht verwaltet) ein zufälliger Wert.
  mHelp := Default(TSignatureHelp);
  SetLength(mHelp.Signatures, 1);
  mHelp.Signatures[0].Text := 'procedure P(A: Integer)';
  mHelp.Signatures[0].Documentation := '';
  SetLength(mHelp.Signatures[0].Parameters, 1);
  mHelp.Signatures[0].Parameters[0].StartIndex := 12;
  mHelp.Signatures[0].Parameters[0].EndIndex := 22;
  mHelp.Signatures[0].Parameters[0].Documentation := 'Wert';
  mHelp.Signatures[0].Fits := False;
  mHelp.Signatures[0].Mismatch := 0;
  mHelp.ActiveSignature := 0;
  mHelp.ActiveParameter := 0;
  mJson := TLspSignatureHelp.ToJson(mHelp);
  try
    Assert.AreEqual('{"signatures":[{"label":"procedure P(A: Integer)","parameters":[{"label":[12,22],' +
      '"documentation":"Wert"}],"data":{"fits":false,"mismatch":0}}],"activeSignature":0,"activeParameter":0}',
      mJson.ToJSON);
  finally
    mJson.Free;
  end;
end;

procedure TLspSignatureHelpTests.TypesLiteralArguments;
const
  cCode = 'begin P(''a'', ''ab'', 5, 1.5, -3, $FF, nil, [1, 2], True, #13, ''a''#13, ''it''''s'', X + 1, F(2), ';
var
  mTree: TSyntaxTree;
  mSite: TCallSite;
  mTypes: string;
  mIndex: Integer;
begin
  mTree := TPascalParser.Parse(cCode);
  try
    mSite := TLspSignatureHelp.CallSiteAt(mTree, TTextPosition.Create(0, Length(cCode)));
    Assert.IsTrue(mSite.Found);
    Assert.AreEqual(14, mSite.ActiveParameter);
    Assert.AreEqual(15, Integer(Length(mSite.ArgumentFirst)));
    mTypes := '';
    for mIndex := 0 to High(mSite.ArgumentFirst) do
    begin
      mTypes := mTypes + TLspSignatureHelp.ArgumentType(nil, mTree, cHauptFile, mSite.ArgumentFirst[mIndex],
        mSite.ArgumentLast[mIndex]) + '|';
    end;
    // Ausdrücke, Aufrufe und das leere letzte Argument bleiben unbekannt.
    Assert.AreEqual('Char|string|Integer|Double|Integer|Integer|nil|[]|Boolean|Char|string|string||||', mTypes);
  finally
    mTree.Free;
  end;
  // Ein offenes String-Literal wird noch getippt.
  mTree := TPascalParser.Parse('begin P(''a');
  try
    mSite := TLspSignatureHelp.CallSiteAt(mTree, TTextPosition.Create(0, 10));
    Assert.AreEqual('', TLspSignatureHelp.ArgumentType(nil, mTree, cHauptFile, mSite.ArgumentFirst[0],
      mSite.ArgumentLast[0]));
  finally
    mTree.Free;
  end;
end;

procedure TLspSignatureHelpTests.ArgumentFitsByFamily;
begin
  Assert.IsTrue(TResolverText.ArgumentFits('Char', 'Char'));
  Assert.IsTrue(TResolverText.ArgumentFits('WideChar', 'Char'));
  Assert.IsTrue(TResolverText.ArgumentFits('string', 'Char'), 'Zeichen an string');
  Assert.IsFalse(TResolverText.ArgumentFits('Char', 'string'));
  Assert.IsFalse(TResolverText.ArgumentFits('Boolean', 'Char'));
  Assert.IsFalse(TResolverText.ArgumentFits('TDoppelte', 'Char'), 'Zeichen an Aufzählung');
  Assert.IsTrue(TResolverText.ArgumentFits('TDoppelte', 'TDoppelte'));
  Assert.IsFalse(TResolverText.ArgumentFits('Boolean', 'TDoppelte'));
  Assert.IsTrue(TResolverText.ArgumentFits('Double', 'Integer'), 'Ganzzahl an Gleitkomma');
  Assert.IsFalse(TResolverText.ArgumentFits('Integer', 'Double'));
  Assert.IsTrue(TResolverText.ArgumentFits('TStrings', 'TStringList'), 'Klasse ohne Vererbungsprüfung');
  Assert.IsTrue(TResolverText.ArgumentFits('TObject', 'nil'));
  Assert.IsTrue(TResolverText.ArgumentFits('Pointer', 'nil'));
  Assert.IsFalse(TResolverText.ArgumentFits('Integer', 'nil'));
  Assert.IsTrue(TResolverText.ArgumentFits('PChar', 'string'));
  Assert.IsTrue(TResolverText.ArgumentFits('Variant', 'Integer'));
  Assert.IsTrue(TResolverText.ArgumentFits('TListenOptionen', '[]'));
  Assert.IsTrue(TResolverText.ArgumentFits('array of const', '[]'));
  Assert.IsFalse(TResolverText.ArgumentFits('array of const', 'Integer'));
  Assert.IsTrue(TResolverText.ArgumentFits('Boolean', ''), 'unbekannt passt');
  Assert.IsTrue(TResolverText.ArgumentFits('', 'Integer'), 'untypisiert passt');
end;

procedure TLspSignatureHelpTests.CharArgumentsDimDuplicatesOverload;
var
  mHelp: TSignatureHelp;
begin
  // TListe.Create('"', ';', : die Variante mit TDoppelte passt nicht, vorgewählt die mit Optionen.
  mHelp := HelpAt('  TListe.Create(''"'', '';'', ', 'TListe.Create(''"'', '';'', ');
  Assert.AreEqual(5, Integer(Length(mHelp.Signatures)));
  Assert.AreEqual(2, mHelp.ActiveParameter);
  Assert.AreEqual('constructor Create(Duplicates: TDoppelte; Sorted: Boolean; CaseSensitive: Boolean)',
    mHelp.Signatures[4].Text);
  Assert.IsFalse(mHelp.Signatures[4].Fits);
  Assert.AreEqual(0, mHelp.Signatures[4].Mismatch);
  Assert.IsFalse(mHelp.Signatures[1].Fits, 'Boolean');
  Assert.IsTrue(mHelp.Signatures[2].Fits);
  Assert.IsTrue(mHelp.Signatures[3].Fits);
  Assert.AreEqual(3, mHelp.ActiveSignature);
  Assert.AreEqual('TListenOptionen', mHelp.Signatures[3].Parameters[2].TypeName);
  Assert.AreEqual('Char', mHelp.Signatures[3].Parameters[1].TypeName);
end;

procedure TLspSignatureHelpTests.FirstCharLiteralSkipsBooleanOverload;
var
  mHelp: TSignatureHelp;
begin
  // Nicht die kürzeste mit genug Parametern (OwnsObjects), sondern die erste verträgliche.
  mHelp := HelpAt('  TListe.Create(''"''', 'TListe.Create(''"''');
  Assert.AreEqual(0, mHelp.ActiveParameter);
  Assert.AreEqual(2, mHelp.ActiveSignature);
end;

procedure TLspSignatureHelpTests.BooleanAndEnumArgumentsPickTheirOverload;
var
  mHelp: TSignatureHelp;
begin
  mHelp := HelpAt('  TListe.Create(True', 'TListe.Create(True');
  Assert.AreEqual(1, mHelp.ActiveSignature);
  Assert.IsFalse(mHelp.Signatures[2].Fits);
  mHelp := HelpAt('  TListe.Create(dupIgnorieren, ', 'TListe.Create(dupIgnorieren, ');
  Assert.AreEqual(4, mHelp.ActiveSignature);
  Assert.IsFalse(mHelp.Signatures[2].Fits);
  Assert.IsTrue(mHelp.Signatures[4].Fits);
  // Bezeichner über die Namensauflösung (Klammer schon geschlossen): Anzahl ist ein Integer-, Name ein
  // string-Parameter von TFoo.Bar.
  mHelp := HelpAt('  Rechne(Anzahl);', 'Rechne(Anzahl');
  Assert.IsTrue(mHelp.Signatures[0].Fits);
  Assert.IsTrue(mHelp.Signatures[1].Fits, 'Ganzzahl an Double');
  mHelp := HelpAt('  TListe.Create(Name);', 'TListe.Create(Name');
  Assert.IsFalse(mHelp.Signatures[2].Fits, 'string an Char');
  Assert.IsFalse(mHelp.Signatures[1].Fits, 'string an Boolean');
end;

procedure TLspSignatureHelpTests.UnknownArgumentsFitAll;
var
  mHelp: TSignatureHelp;
  mSignature: TSignature;
begin
  // Unbekannter Typ gilt als verträglich: lieber eine Variante zu viel.
  mHelp := HelpAt('  TListe.Create(Gibts.Nicht, ', 'TListe.Create(Gibts.Nicht, ');
  for mSignature in mHelp.Signatures do
  begin
    Assert.IsTrue(mSignature.Fits);
  end;
  Assert.AreEqual(2, mHelp.ActiveSignature);
  // Passt keine, bleibt die erste mit genug Parametern gewählt.
  mHelp := HelpAt('  TListe.Create(1.5, ', 'TListe.Create(1.5, ');
  Assert.AreEqual(2, mHelp.ActiveSignature);
  Assert.IsFalse(mHelp.Signatures[2].Fits);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspSignatureHelpTests);

end.
