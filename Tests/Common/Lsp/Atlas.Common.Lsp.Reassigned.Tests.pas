unit Atlas.Common.Lsp.Reassigned.Tests;

// Befehl atlas.server.reassigned (#712): Antwort im JSON, Ziele aus den
// Argumenten und Übergabeart über die Namensauflösung aus anderen Units.
// Zeilenbereich (nur Routinen im sichtbaren Teil) und Abbruch der Anfrage.

interface

uses
  DUnitX.TestFramework,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract;

type
  [TestFixture]
  TLspReassignedTests = class
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    function Run(const ASettings: string): TJSONObject; overload;
    function Run(const ASettings: string; const ACancellation: IJsonRpcCancellationToken): TJSONObject; overload;
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
    [Test]
    procedure RangeKeepsOnlyTouchedRoutines;
    [Test]
    procedure RangeCountsWholeRoutine;
    [Test]
    procedure InvalidRangeMeansWholeFile;
    [Test]
    procedure CancelledRequestEnds;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.Reassigned;

const
  cLB = #13#10;
  cMainFile = 'C:\P\Haupt.pas';
  cOtherFile = 'C:\P\Lader.pas';

  cUnitOther =
    'unit Lader;' + cLB +
    'interface' + cLB +
    'procedure Lade(var AWert: Integer);' + cLB +
    'implementation' + cLB +
    'procedure Lade(var AWert: Integer);' + cLB +
    'begin' + cLB +
    'end;' + cLB +
    'end.';

  cUnitMain =
    'unit Haupt;' + cLB +
    'interface' + cLB +
    'implementation' + cLB +
    'uses Lader;' + cLB +
    'procedure Probe(A: Integer);' + cLB +           // 4
    'var' + cLB +
    '  Total, N: Integer;' + cLB +                    // 6
    'begin' + cLB +
    '  Total := 0;' + cLB +                           // 8
    '  for N := 1 to A do' + cLB +
    '    Total := Total + N;' + cLB +                 // 10
    '  A := Total;' + cLB +
    'end;' + cLB +
    'procedure Zweite;' + cLB +
    'var' + cLB +
    '  W: Integer;' + cLB +                           // 15
    'begin' + cLB +
    '  W := 1;' + cLB +
    '  Lade(W);' + cLB +
    'end;' + cLB +
    'end.';

type
  /// <summary>Abbruchsignal einer abgebrochenen Anfrage.</summary>
  TCancelledToken = class(TInterfacedObject, IJsonRpcCancellationToken)
  public
    function IsCancellationRequested: Boolean;
    procedure ThrowIfCancellationRequested;
  end;

function TCancelledToken.IsCancellationRequested: Boolean;
begin
  Result := True;
end;

procedure TCancelledToken.ThrowIfCancellationRequested;
begin
  raise EJsonRpcRequestCancelled.Create;
end;

{ TLspReassignedTests }

procedure TLspReassignedTests.Setup;
begin
  FStore := TDocumentStore.Create;
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitOther, cOtherFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitMain, cMainFile, nil));
end;

procedure TLspReassignedTests.TearDown;
begin
  FStore := nil;
  FIndex := nil;
end;

function TLspReassignedTests.Run(const ASettings: string): TJSONObject;
begin
  Result := Run(ASettings, nil);
end;

function TLspReassignedTests.Run(const ASettings: string; const ACancellation: IJsonRpcCancellationToken): TJSONObject;
var
  mUri: string;
  mArguments: TJSONArray;
  mReply: TJSONValue;
begin
  mUri := TDocumentUris.FromPath(cMainFile);
  FStore.Close(mUri);
  FStore.Open(mUri, 'delphi', 1, cUnitMain);
  mArguments := TJSONArray.Create;
  try
    mArguments.Add(mUri);
    if ASettings <> '' then
    begin
      mArguments.AddElement(TJSONObject.ParseJSONValue(ASettings));
    end;
    mReply := TLspReassigned.Execute(FStore, FIndex, nil, nil, mArguments, ACancellation);
  finally
    mArguments.Free;
  end;
  Assert.IsTrue(mReply is TJSONObject);
  Result := TJSONObject(mReply);
end;

class function TLspReassignedTests.Names(AReply: TJSONObject): string;
var
  mItem: TJSONValue;
begin
  Result := '';
  for mItem in AReply.GetValue('symbols') as TJSONArray do
  begin
    if Result <> '' then
    begin
      Result := Result + ' ';
    end;
    Result := Result + (mItem as TJSONObject).GetValue('name').Value;
  end;
end;

procedure TLspReassignedTests.ReplyCarriesUsesAndWrites;
var
  mReply, mTotal, mUse: TJSONObject;
  mUses_: TJSONArray;
begin
  mReply := Run('');
  try
    // Vorgabe: lokale Variablen und Wertparameter; N ist ein Schleifenzähler.
    Assert.AreEqual('A Total W', Names(mReply));
    mTotal := ((mReply.GetValue('symbols') as TJSONArray).Items[1]) as TJSONObject;
    Assert.AreEqual('local', mTotal.GetValue('kind').Value);
    Assert.AreEqual('2', mTotal.GetValue('writes').Value);
    Assert.AreEqual('Probe', mTotal.GetValue('routine').Value);
    Assert.AreEqual('[8,10]', mTotal.GetValue('writeLines').ToJSON);
    mUses_ := mTotal.GetValue('uses') as TJSONArray;
    Assert.AreEqual(5, mUses_.Count);
    mUse := mUses_.Items[0] as TJSONObject;
    Assert.AreEqual('6', mUse.GetValue('line').Value);
    Assert.AreEqual('2', mUse.GetValue('character').Value);
    Assert.AreEqual('7', mUse.GetValue('endCharacter').Value);
    Assert.AreEqual('false', mUse.GetValue('write').Value);
    Assert.AreEqual('true', (mUses_.Items[1] as TJSONObject).GetValue('write').Value);
  finally
    mReply.Free;
  end;
end;

procedure TLspReassignedTests.TargetsFromArguments;
var
  mReply: TJSONObject;
begin
  mReply := Run('{"targets":["loopVars"]}');
  try
    Assert.AreEqual('N', Names(mReply));
  finally
    mReply.Free;
  end;
  mReply := Run('{"targets":[]}');
  try
    Assert.AreEqual('', Names(mReply));
  finally
    mReply.Free;
  end;
end;

procedure TLspReassignedTests.VarArgumentOfOtherUnit;
var
  mReply, W: TJSONObject;
begin
  // Lade steht in Lader und nimmt W als var-Parameter: zweite Zuweisung.
  mReply := Run('{"targets":["locals"]}');
  try
    Assert.AreEqual('Total W', Names(mReply));
    W := ((mReply.GetValue('symbols') as TJSONArray).Items[1]) as TJSONObject;
    Assert.AreEqual('2', W.GetValue('writes').Value);
  finally
    mReply.Free;
  end;
end;

procedure TLspReassignedTests.UnknownDocumentGivesError;
var
  mArguments: TJSONArray;
begin
  mArguments := TJSONObject.ParseJSONValue('["file:///C:/P/Fehlt.pas"]') as TJSONArray;
  try
    Assert.WillRaise(
      procedure
      begin
        TLspReassigned.Execute(FStore, FIndex, nil, nil, mArguments, nil).Free;
      end,
      EJsonRpcError);
  finally
    mArguments.Free;
  end;
end;

procedure TLspReassignedTests.RangeKeepsOnlyTouchedRoutines;
var
  mReply: TJSONObject;
begin
  // Nur Zweite (Zeilen 13 bis 19) reicht in den Bereich: Probe bleibt außen vor.
  mReply := Run('{"targets":["locals","valueParams"],"range":{"start":16,"end":18}}');
  try
    Assert.AreEqual('W', Names(mReply));
  finally
    mReply.Free;
  end;
  mReply := Run('{"range":{"start":0,"end":5}}');
  try
    Assert.AreEqual('A Total', Names(mReply));
  finally
    mReply.Free;
  end;
end;

procedure TLspReassignedTests.RangeCountsWholeRoutine;
var
  mReply, mTotal: TJSONObject;
begin
  // Der Bereich trifft nur den Kopf von Probe; alle Stellen der Routine zählen trotzdem.
  mReply := Run('{"targets":["locals"],"range":{"start":4,"end":4}}');
  try
    Assert.AreEqual('Total', Names(mReply));
    mTotal := ((mReply.GetValue('symbols') as TJSONArray).Items[0]) as TJSONObject;
    Assert.AreEqual('2', mTotal.GetValue('writes').Value);
    Assert.AreEqual(5, (mTotal.GetValue('uses') as TJSONArray).Count);
  finally
    mReply.Free;
  end;
end;

procedure TLspReassignedTests.InvalidRangeMeansWholeFile;
var
  mReply: TJSONObject;
begin
  mReply := Run('{"targets":["locals"],"range":{"start":12,"end":3}}');
  try
    Assert.AreEqual('Total W', Names(mReply));
  finally
    mReply.Free;
  end;
end;

procedure TLspReassignedTests.CancelledRequestEnds;
begin
  Assert.WillRaise(
    procedure
    begin
      Run('', TCancelledToken.Create).Free;
    end,
    EJsonRpcRequestCancelled);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspReassignedTests);

end.
