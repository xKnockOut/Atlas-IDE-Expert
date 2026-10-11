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
    'uses Werkzeug;'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '    procedure Bar(Anzahl: Integer; const Name: string);'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TFoo.Bar;'#10 +
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
  AText := UnitWerkzeug;
  Result := SameText(AFileName, WerkzeugFile);
end;

{ TLspSignatureHelpTests }

procedure TLspSignatureHelpTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitWerkzeug, WerkzeugFile, nil));
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
  SetLength(Help.Signatures, 1);
  Help.Signatures[0].Text := 'procedure P(A: Integer)';
  Help.Signatures[0].Documentation := '';
  SetLength(Help.Signatures[0].Parameters, 1);
  Help.Signatures[0].Parameters[0].StartIndex := 12;
  Help.Signatures[0].Parameters[0].EndIndex := 22;
  Help.Signatures[0].Parameters[0].Documentation := 'Wert';
  Help.ActiveSignature := 0;
  Help.ActiveParameter := 0;
  Json := TLspSignatureHelp.ToJson(Help);
  try
    Assert.AreEqual('{"signatures":[{"label":"procedure P(A: Integer)","parameters":[{"label":[12,22],' +
      '"documentation":"Wert"}]}],"activeSignature":0,"activeParameter":0}', Json.ToJSON);
  finally
    Json.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspSignatureHelpTests);

end.
