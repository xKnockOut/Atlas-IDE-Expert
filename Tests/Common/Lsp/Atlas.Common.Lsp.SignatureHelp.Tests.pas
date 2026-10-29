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
  HauptFile = 'C:\P\Haupt.pas';
  WerkzeugFile = 'C:\P\Werkzeug.pas';
  ListenFile = 'C:\P\Listen.pas';

  // Überladungen wie bei TStringList.Create (#498), eigene Beispiel-Unit.
  UnitListen =
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

  UnitWerkzeug =
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

  UnitHaupt =
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
  Index, Line, LineStart, Scan: Integer;
begin
  // Cursor hinter AMarker.
  Index := Pos(AMarker, AText);
  if Index = 0 then
    raise Exception.CreateFmt('"%s" nicht gefunden', [AMarker]);
  Inc(Index, Length(AMarker));
  Line := 0;
  LineStart := 1;
  for Scan := 1 to Index - 1 do
    if AText[Scan] = #10 then
    begin
      Inc(Line);
      LineStart := Scan + 1;
    end;
  Result := TTextPosition.Create(Line, Index - LineStart);
end;

function ReadWerkzeug(const AFileName: string; out AText: string): Boolean;
begin
  if SameText(AFileName, ListenFile) then
    AText := UnitListen
  else
    AText := UnitWerkzeug;
  Result := SameText(AFileName, WerkzeugFile) or SameText(AFileName, ListenFile);
end;

{ TLspSignatureHelpTests }

procedure TLspSignatureHelpTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitWerkzeug, WerkzeugFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitListen, ListenFile, nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TLspSignatureHelpTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TLspSignatureHelpTests.HelpAt(const ACode, AMarker: string): TSignatureHelp;
var
  Text: string;
  Tree: TSyntaxTree;
begin
  Text := StringReplace(UnitHaupt, '  |', ACode, []);
  Tree := TPascalParser.Parse(Text);
  try
    Result := TLspSignatureHelp.HelpAt(FResolver, FIndex, Tree, Text, HauptFile, PositionOf(Text, AMarker),
      ReadWerkzeug);
  finally
    Tree.Free;
  end;
end;

procedure TLspSignatureHelpTests.FindsCallSiteAndActiveParameter;
var
  Tree: TSyntaxTree;
  Site: TCallSite;
begin
  Tree := TPascalParser.Parse('begin Rechne(1, 2, ');
  try
    Site := TLspSignatureHelp.CallSiteAt(Tree, TTextPosition.Create(0, 19));
    Assert.IsTrue(Site.Found);
    Assert.AreEqual(6, Site.NamePosition.Character);
    Assert.AreEqual(2, Site.ActiveParameter);
    // Hinter der schließenden Klammer und nach ; ist kein Aufruf mehr offen.
    Assert.IsFalse(TLspSignatureHelp.CallSiteAt(Tree, TTextPosition.Create(0, 5)).Found);
  finally
    Tree.Free;
  end;
  Tree := TPascalParser.Parse('begin Rechne(1); X');
  try
    Assert.IsFalse(TLspSignatureHelp.CallSiteAt(Tree, TTextPosition.Create(0, 18)).Found);
    Assert.IsFalse(TLspSignatureHelp.CallSiteAt(Tree, TTextPosition.Create(0, 15)).Found);
  finally
    Tree.Free;
  end;
end;

procedure TLspSignatureHelpTests.NestedCallsAndBracketsAreSkipped;
var
  Tree: TSyntaxTree;
  Site: TCallSite;
begin
  Tree := TPascalParser.Parse('begin Rechne(Liste[1, 2], (3 + 4), Max(5, 6), ');
  try
    Site := TLspSignatureHelp.CallSiteAt(Tree, TTextPosition.Create(0, 46));
    Assert.IsTrue(Site.Found);
    Assert.AreEqual(6, Site.NamePosition.Character);
    Assert.AreEqual(3, Site.ActiveParameter);
    Site := TLspSignatureHelp.CallSiteAt(Tree, TTextPosition.Create(0, 42));
    Assert.AreEqual(35, Site.NamePosition.Character);
    Assert.AreEqual(1, Site.ActiveParameter);
  finally
    Tree.Free;
  end;
end;

procedure TLspSignatureHelpTests.ParsesSignatureOverSeveralLines;
var
  Signature: TSignature;
begin
  Signature := TLspSignatureHelp.ParseSignature(['  function TFoo.Rechne(const A, B: Double;',
    '    Runden: Boolean = True): Double; overload;'], 0, 2);
  Assert.AreEqual('function Rechne(const A, B: Double; Runden: Boolean = True): Double', Signature.Text);
  Assert.IsTrue(Signature.Qualified);
  Assert.AreEqual(3, Integer(Length(Signature.Parameters)));
  Assert.AreEqual('A', Copy(Signature.Text, Signature.Parameters[0].StartIndex + 1,
    Signature.Parameters[0].EndIndex - Signature.Parameters[0].StartIndex));
  Assert.AreEqual('B', Copy(Signature.Text, Signature.Parameters[1].StartIndex + 1,
    Signature.Parameters[1].EndIndex - Signature.Parameters[1].StartIndex));
  Assert.AreEqual('Runden: Boolean = True', Copy(Signature.Text, Signature.Parameters[2].StartIndex + 1,
    Signature.Parameters[2].EndIndex - Signature.Parameters[2].StartIndex));
end;

procedure TLspSignatureHelpTests.ListsOverloadsWithDocumentation;
var
  Help: TSignatureHelp;
begin
  Help := HelpAt('  Rechne(1.5, ', 'Rechne(1.5, ');
  Assert.AreEqual(2, Integer(Length(Help.Signatures)));
  Assert.AreEqual('function Rechne(Wert: Integer): Integer', Help.Signatures[0].Text);
  Assert.AreEqual('Rechnet.', Help.Signatures[0].Documentation);
  Assert.AreEqual('Eingabe', Help.Signatures[0].Parameters[0].Documentation);
  Assert.AreEqual(1, Help.ActiveParameter);
  // Die erste Überladung hat nur einen Parameter.
  Assert.AreEqual(1, Help.ActiveSignature);
end;

procedure TLspSignatureHelpTests.MethodShowsDeclarationOnly;
var
  Help: TSignatureHelp;
begin
  Help := HelpAt('  Bar(', '  Bar(');
  Assert.AreEqual(1, Integer(Length(Help.Signatures)));
  Assert.AreEqual('procedure Bar(Anzahl: Integer; const Name: string)', Help.Signatures[0].Text);
  Assert.AreEqual(0, Help.ActiveParameter);
  Assert.IsFalse(HelpAt('  Unbekannt(', 'Unbekannt(').Found);
end;

procedure TLspSignatureHelpTests.WritesSignatureHelp;
var
  Help: TSignatureHelp;
  Json: TJSONValue;
begin
  // Ohne Default stünde in Format.Problem (Aufzählung, nicht verwaltet) ein zufälliger Wert.
  Help := Default(TSignatureHelp);
  SetLength(Help.Signatures, 1);
  Help.Signatures[0].Text := 'procedure P(A: Integer)';
  Help.Signatures[0].Documentation := '';
  SetLength(Help.Signatures[0].Parameters, 1);
  Help.Signatures[0].Parameters[0].StartIndex := 12;
  Help.Signatures[0].Parameters[0].EndIndex := 22;
  Help.Signatures[0].Parameters[0].Documentation := 'Wert';
  Help.Signatures[0].Fits := False;
  Help.Signatures[0].Mismatch := 0;
  Help.ActiveSignature := 0;
  Help.ActiveParameter := 0;
  Json := TLspSignatureHelp.ToJson(Help);
  try
    Assert.AreEqual('{"signatures":[{"label":"procedure P(A: Integer)","parameters":[{"label":[12,22],' +
      '"documentation":"Wert"}],"data":{"fits":false,"mismatch":0}}],"activeSignature":0,"activeParameter":0}',
      Json.ToJSON);
  finally
    Json.Free;
  end;
end;

procedure TLspSignatureHelpTests.TypesLiteralArguments;
const
  Code = 'begin P(''a'', ''ab'', 5, 1.5, -3, $FF, nil, [1, 2], True, #13, ''a''#13, ''it''''s'', X + 1, F(2), ';
var
  Tree: TSyntaxTree;
  Site: TCallSite;
  Types: string;
  Index: Integer;
begin
  Tree := TPascalParser.Parse(Code);
  try
    Site := TLspSignatureHelp.CallSiteAt(Tree, TTextPosition.Create(0, Length(Code)));
    Assert.IsTrue(Site.Found);
    Assert.AreEqual(14, Site.ActiveParameter);
    Assert.AreEqual(15, Integer(Length(Site.ArgumentFirst)));
    Types := '';
    for Index := 0 to High(Site.ArgumentFirst) do
      Types := Types + TLspSignatureHelp.ArgumentType(nil, Tree, HauptFile, Site.ArgumentFirst[Index],
        Site.ArgumentLast[Index]) + '|';
    // Ausdrücke, Aufrufe und das leere letzte Argument bleiben unbekannt.
    Assert.AreEqual('Char|string|Integer|Double|Integer|Integer|nil|[]|Boolean|Char|string|string||||', Types);
  finally
    Tree.Free;
  end;
  // Ein offenes String-Literal wird noch getippt.
  Tree := TPascalParser.Parse('begin P(''a');
  try
    Site := TLspSignatureHelp.CallSiteAt(Tree, TTextPosition.Create(0, 10));
    Assert.AreEqual('', TLspSignatureHelp.ArgumentType(nil, Tree, HauptFile, Site.ArgumentFirst[0],
      Site.ArgumentLast[0]));
  finally
    Tree.Free;
  end;
end;

procedure TLspSignatureHelpTests.ArgumentFitsByFamily;
begin
  Assert.IsTrue(TNameResolver.ArgumentFits('Char', 'Char'));
  Assert.IsTrue(TNameResolver.ArgumentFits('WideChar', 'Char'));
  Assert.IsTrue(TNameResolver.ArgumentFits('string', 'Char'), 'Zeichen an string');
  Assert.IsFalse(TNameResolver.ArgumentFits('Char', 'string'));
  Assert.IsFalse(TNameResolver.ArgumentFits('Boolean', 'Char'));
  Assert.IsFalse(TNameResolver.ArgumentFits('TDoppelte', 'Char'), 'Zeichen an Aufzählung');
  Assert.IsTrue(TNameResolver.ArgumentFits('TDoppelte', 'TDoppelte'));
  Assert.IsFalse(TNameResolver.ArgumentFits('Boolean', 'TDoppelte'));
  Assert.IsTrue(TNameResolver.ArgumentFits('Double', 'Integer'), 'Ganzzahl an Gleitkomma');
  Assert.IsFalse(TNameResolver.ArgumentFits('Integer', 'Double'));
  Assert.IsTrue(TNameResolver.ArgumentFits('TStrings', 'TStringList'), 'Klasse ohne Vererbungsprüfung');
  Assert.IsTrue(TNameResolver.ArgumentFits('TObject', 'nil'));
  Assert.IsTrue(TNameResolver.ArgumentFits('Pointer', 'nil'));
  Assert.IsFalse(TNameResolver.ArgumentFits('Integer', 'nil'));
  Assert.IsTrue(TNameResolver.ArgumentFits('PChar', 'string'));
  Assert.IsTrue(TNameResolver.ArgumentFits('Variant', 'Integer'));
  Assert.IsTrue(TNameResolver.ArgumentFits('TListenOptionen', '[]'));
  Assert.IsTrue(TNameResolver.ArgumentFits('array of const', '[]'));
  Assert.IsFalse(TNameResolver.ArgumentFits('array of const', 'Integer'));
  Assert.IsTrue(TNameResolver.ArgumentFits('Boolean', ''), 'unbekannt passt');
  Assert.IsTrue(TNameResolver.ArgumentFits('', 'Integer'), 'untypisiert passt');
end;

procedure TLspSignatureHelpTests.CharArgumentsDimDuplicatesOverload;
var
  Help: TSignatureHelp;
begin
  // TListe.Create('"', ';', : die Variante mit TDoppelte passt nicht, vorgewählt die mit Optionen.
  Help := HelpAt('  TListe.Create(''"'', '';'', ', 'TListe.Create(''"'', '';'', ');
  Assert.AreEqual(5, Integer(Length(Help.Signatures)));
  Assert.AreEqual(2, Help.ActiveParameter);
  Assert.AreEqual('constructor Create(Duplicates: TDoppelte; Sorted: Boolean; CaseSensitive: Boolean)',
    Help.Signatures[4].Text);
  Assert.IsFalse(Help.Signatures[4].Fits);
  Assert.AreEqual(0, Help.Signatures[4].Mismatch);
  Assert.IsFalse(Help.Signatures[1].Fits, 'Boolean');
  Assert.IsTrue(Help.Signatures[2].Fits);
  Assert.IsTrue(Help.Signatures[3].Fits);
  Assert.AreEqual(3, Help.ActiveSignature);
  Assert.AreEqual('TListenOptionen', Help.Signatures[3].Parameters[2].TypeName);
  Assert.AreEqual('Char', Help.Signatures[3].Parameters[1].TypeName);
end;

procedure TLspSignatureHelpTests.FirstCharLiteralSkipsBooleanOverload;
var
  Help: TSignatureHelp;
begin
  // Nicht die kürzeste mit genug Parametern (OwnsObjects), sondern die erste verträgliche.
  Help := HelpAt('  TListe.Create(''"''', 'TListe.Create(''"''');
  Assert.AreEqual(0, Help.ActiveParameter);
  Assert.AreEqual(2, Help.ActiveSignature);
end;

procedure TLspSignatureHelpTests.BooleanAndEnumArgumentsPickTheirOverload;
var
  Help: TSignatureHelp;
begin
  Help := HelpAt('  TListe.Create(True', 'TListe.Create(True');
  Assert.AreEqual(1, Help.ActiveSignature);
  Assert.IsFalse(Help.Signatures[2].Fits);
  Help := HelpAt('  TListe.Create(dupIgnorieren, ', 'TListe.Create(dupIgnorieren, ');
  Assert.AreEqual(4, Help.ActiveSignature);
  Assert.IsFalse(Help.Signatures[2].Fits);
  Assert.IsTrue(Help.Signatures[4].Fits);
  // Bezeichner über die Namensauflösung (Klammer schon geschlossen): Anzahl ist ein Integer-, Name ein
  // string-Parameter von TFoo.Bar.
  Help := HelpAt('  Rechne(Anzahl);', 'Rechne(Anzahl');
  Assert.IsTrue(Help.Signatures[0].Fits);
  Assert.IsTrue(Help.Signatures[1].Fits, 'Ganzzahl an Double');
  Help := HelpAt('  TListe.Create(Name);', 'TListe.Create(Name');
  Assert.IsFalse(Help.Signatures[2].Fits, 'string an Char');
  Assert.IsFalse(Help.Signatures[1].Fits, 'string an Boolean');
end;

procedure TLspSignatureHelpTests.UnknownArgumentsFitAll;
var
  Help: TSignatureHelp;
  Signature: TSignature;
begin
  // Unbekannter Typ gilt als verträglich: lieber eine Variante zu viel.
  Help := HelpAt('  TListe.Create(Gibts.Nicht, ', 'TListe.Create(Gibts.Nicht, ');
  for Signature in Help.Signatures do
    Assert.IsTrue(Signature.Fits);
  Assert.AreEqual(2, Help.ActiveSignature);
  // Passt keine, bleibt die erste mit genug Parametern gewählt.
  Help := HelpAt('  TListe.Create(1.5, ', 'TListe.Create(1.5, ');
  Assert.AreEqual(2, Help.ActiveSignature);
  Assert.IsFalse(Help.Signatures[2].Fits);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspSignatureHelpTests);

end.
