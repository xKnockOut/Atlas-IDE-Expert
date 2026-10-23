unit Atlas.Common.Lsp.Reassigned.Tests;

// Befehl atlas.server.reassigned (#712): Antwort im JSON, Ziele aus den
// Argumenten und Übergabeart über die Namensauflösung aus anderen Units.

interface

uses
  DUnitX.TestFramework,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract;

type
  [TestFixture]
  TLspReassignedTests = class
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    function Run(const ASettings: string): TJSONObject;
    /// <summary>Namen der Antwort, mit Leerzeichen getrennt.</summary>
    class function Names(AReply: TJSONObject): string; static;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ReplyCarriesUsesAndWrites;
    [Test]
    procedure TargetsFromArguments;
    [Test]
    procedure VarArgumentOfOtherUnit;
    [Test]
    procedure UnknownDocumentGivesError;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.Reassigned;

const
  LB = #13#10;
  MainFile = 'C:\P\Haupt.pas';
  OtherFile = 'C:\P\Lader.pas';

  UnitOther =
    'unit Lader;' + LB +
    'interface' + LB +
    'procedure Lade(var AWert: Integer);' + LB +
    'implementation' + LB +
    'procedure Lade(var AWert: Integer);' + LB +
    'begin' + LB +
    'end;' + LB +
    'end.';

  UnitMain =
    'unit Haupt;' + LB +
    'interface' + LB +
    'implementation' + LB +
    'uses Lader;' + LB +
    'procedure Probe(A: Integer);' + LB +           // 4
    'var' + LB +
    '  Total, N: Integer;' + LB +                    // 6
    'begin' + LB +
    '  Total := 0;' + LB +                           // 8
    '  for N := 1 to A do' + LB +
    '    Total := Total + N;' + LB +                 // 10
    '  A := Total;' + LB +
    'end;' + LB +
    'procedure Zweite;' + LB +
    'var' + LB +
    '  W: Integer;' + LB +                           // 15
    'begin' + LB +
    '  W := 1;' + LB +
    '  Lade(W);' + LB +
    'end;' + LB +
    'end.';

{ TLspReassignedTests }

procedure TLspReassignedTests.Setup;
begin
  FStore := TDocumentStore.Create;
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitOther, OtherFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitMain, MainFile, nil));
end;

procedure TLspReassignedTests.TearDown;
begin
  FStore := nil;
  FIndex := nil;
end;

function TLspReassignedTests.Run(const ASettings: string): TJSONObject;
var
  Uri: string;
  Arguments: TJSONArray;
  Reply: TJSONValue;
begin
  Uri := TDocumentUris.FromPath(MainFile);
  FStore.Close(Uri);
  FStore.Open(Uri, 'delphi', 1, UnitMain);
  Arguments := TJSONArray.Create;
  try
    Arguments.Add(Uri);
    if ASettings <> '' then
      Arguments.AddElement(TJSONObject.ParseJSONValue(ASettings));
    Reply := TLspReassigned.Execute(FStore, FIndex, nil, nil, Arguments);
  finally
    Arguments.Free;
  end;
  Assert.IsTrue(Reply is TJSONObject);
  Result := TJSONObject(Reply);
end;

class function TLspReassignedTests.Names(AReply: TJSONObject): string;
var
  Item: TJSONValue;
begin
  Result := '';
  for Item in AReply.GetValue('symbols') as TJSONArray do
  begin
    if Result <> '' then
      Result := Result + ' ';
    Result := Result + (Item as TJSONObject).GetValue('name').Value;
  end;
end;

procedure TLspReassignedTests.ReplyCarriesUsesAndWrites;
var
  Reply, Total, Use: TJSONObject;
  Uses_: TJSONArray;
begin
  Reply := Run('');
  try
    // Vorgabe: lokale Variablen und Wertparameter; N ist ein Schleifenzähler.
    Assert.AreEqual('A Total W', Names(Reply));
    Total := ((Reply.GetValue('symbols') as TJSONArray).Items[1]) as TJSONObject;
    Assert.AreEqual('local', Total.GetValue('kind').Value);
    Assert.AreEqual('2', Total.GetValue('writes').Value);
    Assert.AreEqual('Probe', Total.GetValue('routine').Value);
    Assert.AreEqual('[8,10]', Total.GetValue('writeLines').ToJSON);
    Uses_ := Total.GetValue('uses') as TJSONArray;
    Assert.AreEqual(5, Uses_.Count);
    Use := Uses_.Items[0] as TJSONObject;
    Assert.AreEqual('6', Use.GetValue('line').Value);
    Assert.AreEqual('2', Use.GetValue('character').Value);
    Assert.AreEqual('7', Use.GetValue('endCharacter').Value);
    Assert.AreEqual('false', Use.GetValue('write').Value);
    Assert.AreEqual('true', (Uses_.Items[1] as TJSONObject).GetValue('write').Value);
  finally
    Reply.Free;
  end;
end;

procedure TLspReassignedTests.TargetsFromArguments;
var
  Reply: TJSONObject;
begin
  Reply := Run('{"targets":["loopVars"]}');
  try
    Assert.AreEqual('N', Names(Reply));
  finally
    Reply.Free;
  end;
  Reply := Run('{"targets":[]}');
  try
    Assert.AreEqual('', Names(Reply));
  finally
    Reply.Free;
  end;
end;

procedure TLspReassignedTests.VarArgumentOfOtherUnit;
var
  Reply, W: TJSONObject;
begin
  // Lade steht in Lader und nimmt W als var-Parameter: zweite Zuweisung.
  Reply := Run('{"targets":["locals"]}');
  try
    Assert.AreEqual('Total W', Names(Reply));
    W := ((Reply.GetValue('symbols') as TJSONArray).Items[1]) as TJSONObject;
    Assert.AreEqual('2', W.GetValue('writes').Value);
  finally
    Reply.Free;
  end;
end;

procedure TLspReassignedTests.UnknownDocumentGivesError;
var
  Arguments: TJSONArray;
begin
  Arguments := TJSONObject.ParseJSONValue('["file:///C:/P/Fehlt.pas"]') as TJSONArray;
  try
    Assert.WillRaise(
      procedure
      begin
        TLspReassigned.Execute(FStore, FIndex, nil, nil, Arguments).Free;
      end,
      EJsonRpcError);
  finally
    Arguments.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspReassignedTests);

end.
