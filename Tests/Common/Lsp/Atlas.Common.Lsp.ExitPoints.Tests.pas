unit Atlas.Common.Lsp.ExitPoints.Tests;

// Befehl atlas.server.exitPoints (#698): Antwort im JSON, Schalter aus den
// Argumenten und Exceptions laut XMLDoc aus der deklarierenden Unit.

interface

uses
  DUnitX.TestFramework,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Lsp.DocumentHighlights;

type
  [TestFixture]
  TLspExitPointsTests = class
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    FSettingsFor: THighlightSettingsProvider;
    /// <summary>Führt den Befehl aus; ASettings ist der dritte Eintrag oder leer.</summary>
    function Run(const AText: string; ALine, ACharacter: Integer; const ASettings: string): TJSONObject;
    /// <summary>Arten und Positionen der Punkte als "kind@line:char", mit Leerzeichen getrennt.</summary>
    class function Points(AReply: TJSONObject): string; static;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ReplyCarriesRoutineAndPoints;
    [Test]
    procedure ExceptionsFromDeclaringUnit;
    [Test]
    procedure SwitchesFromArguments;
    /// <summary>highlight.exitKeywords der Konfiguration bestimmt, was als Austritt zählt.</summary>
    [Test]
    procedure KeywordsFromConfiguration;
    [Test]
    procedure UnknownDocumentGivesError;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.ExitPoints;

const
  cLB = #13#10;
  cMainFile = 'C:\P\Haupt.pas';
  cLoaderFile = 'C:\P\Lader.pas';

  cUnitLoader =
    'unit Lader;' + cLB +
    'interface' + cLB +
    'type' + cLB +
    '  EBasis = class(TObject);' + cLB +
    '  EFehler = class(EBasis);' + cLB +
    '/// <summary>Liest.</summary>' + cLB +
    '/// <exception cref="EFehler">kaputt</exception>' + cLB +
    'procedure Lade;' + cLB +
    'implementation' + cLB +
    'procedure Lade;' + cLB +
    'begin' + cLB +
    'end;' + cLB +
    'end.';

  cUnitMain =
    'unit Haupt;' + cLB +
    'interface' + cLB +
    'uses Lader;' + cLB +
    'function Wert(A: Integer): Integer;' + cLB +
    'procedure Probe;' + cLB +
    'implementation' + cLB +
    'function Wert(A: Integer): Integer;' + cLB +    // 6
    'begin' + cLB +
    '  if A < 0 then' + cLB +
    '    Exit;' + cLB +                              // 9
    '  Result := A;' + cLB +
    'end;' + cLB +
    'procedure Probe;' + cLB +                       // 12
    'begin' + cLB +
    '  try' + cLB +
    '    Lade;' + cLB +                              // 15
    '  except' + cLB +
    '    on E: EBasis do' + cLB +                    // 17
    '      Exit;' + cLB +
    '  end;' + cLB +
    'end;' + cLB +
    'end.';

/// <summary>Liest nur die Unit des Laders.</summary>
function LoaderReader(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  Result := SameText(AFileName, cLoaderFile);
  if Result then
  begin
    AText := cUnitLoader;
  end;
end;

{ TLspExitPointsTests }

procedure TLspExitPointsTests.Setup;
begin
  FStore := TDocumentStore.Create;
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitLoader, cLoaderFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitMain, cMainFile, nil));
end;

procedure TLspExitPointsTests.TearDown;
begin
  FStore := nil;
  FIndex := nil;
  FSettingsFor := nil;
end;

function TLspExitPointsTests.Run(const AText: string; ALine, ACharacter: Integer;
  const ASettings: string): TJSONObject;
var
  mUri: string;
  mArguments: TJSONArray;
  mPosition: TJSONObject;
  mReply: TJSONValue;
begin
  mUri := TDocumentUris.FromPath(cMainFile);
  FStore.Close(mUri);
  FStore.Open(mUri, 'delphi', 1, AText);
  mArguments := TJSONArray.Create;
  try
    mArguments.Add(mUri);
    mPosition := TJSONObject.Create;
    mPosition.AddPair('line', TJSONNumber.Create(ALine));
    mPosition.AddPair('character', TJSONNumber.Create(ACharacter));
    mArguments.AddElement(mPosition);
    if ASettings <> '' then
    begin
      mArguments.AddElement(TJSONObject.ParseJSONValue(ASettings));
    end;
    mReply := TLspExitPoints.Execute(FStore, FIndex, nil, nil, TExitPointsReaders.Create(LoaderReader, FSettingsFor),
      mArguments);
  finally
    mArguments.Free;
  end;
  Assert.IsTrue(mReply is TJSONObject);
  Result := TJSONObject(mReply);
end;

class function TLspExitPointsTests.Points(AReply: TJSONObject): string;
var
  mItem: TJSONValue;
  mPoint: TJSONObject;
begin
  Result := '';
  for mItem in AReply.GetValue('points') as TJSONArray do
  begin
    mPoint := mItem as TJSONObject;
    if Result <> '' then
    begin
      Result := Result + ' ';
    end;
    Result := Result + mPoint.GetValue('kind').Value + '@' + mPoint.GetValue('line').Value + ':' +
      mPoint.GetValue('character').Value;
  end;
end;

procedure TLspExitPointsTests.ReplyCarriesRoutineAndPoints;
var
  mReply, mRoutine, mFirst: TJSONObject;
begin
  // Auf Exit in Wert: die Routine, ihr Exit (ohne Result) und das Ende.
  mReply := Run(cUnitMain, 9, 5, '');
  try
    Assert.AreEqual('routine', mReply.GetValue('query').Value);
    mRoutine := mReply.GetValue('routine') as TJSONObject;
    Assert.AreEqual('Wert', mRoutine.GetValue('name').Value);
    Assert.AreEqual('6', mRoutine.GetValue('line').Value);
    Assert.AreEqual('9', mRoutine.GetValue('character').Value);
    Assert.AreEqual('13', mRoutine.GetValue('endCharacter').Value);
    Assert.AreEqual('true', mReply.GetValue('function').Value);
    Assert.AreEqual('true', mReply.GetValue('resultMissing').Value);
    Assert.AreEqual('exit@9:4 end@11:0', Points(mReply));
    mFirst := (mReply.GetValue('points') as TJSONArray).Items[0] as TJSONObject;
    Assert.AreEqual('8', mFirst.GetValue('endCharacter').Value);
    Assert.AreEqual('true', mFirst.GetValue('resultMissing').Value);
  finally
    mReply.Free;
  end;
  // Auf Result: die Zuweisungen und die Austritte, an denen Result fehlen kann.
  mReply := Run(cUnitMain, 10, 3, '');
  try
    Assert.AreEqual('result', mReply.GetValue('query').Value);
    Assert.AreEqual('exit@9:4 result@10:2 end@11:0', Points(mReply));
  finally
    mReply.Free;
  end;
end;

procedure TLspExitPointsTests.ExceptionsFromDeclaringUnit;
var
  mReply, mSource: TJSONObject;
begin
  // Lade steht in Lader und löst laut Doku EFehler aus, das von EBasis abstammt.
  mReply := Run(cUnitMain, 17, 5, '');
  try
    Assert.AreEqual('exceptions', mReply.GetValue('query').Value);
    Assert.AreEqual('source@15:4 handler@17:4', Points(mReply));
    mSource := (mReply.GetValue('points') as TJSONArray).Items[0] as TJSONObject;
    Assert.AreEqual('EFehler', mSource.GetValue('exception').Value);
  finally
    mReply.Free;
  end;
end;

procedure TLspExitPointsTests.SwitchesFromArguments;
var
  mReply: TJSONObject;
begin
  mReply := Run(cUnitMain, 17, 5, '{"exceptions":false,"loops":true}');
  try
    Assert.AreEqual('', mReply.GetValue('query').Value);
    Assert.AreEqual('', Points(mReply));
  finally
    mReply.Free;
  end;
end;

procedure TLspExitPointsTests.KeywordsFromConfiguration;
var
  mReply: TJSONObject;
begin
  // Ohne Exit in der Liste bleibt in Wert nur das Ende.
  FSettingsFor :=
    function(const AUri: string): THighlightSettings
    begin
      Result := THighlightSettings.Default;
      Result.ExitKeywords := TArray<string>.Create('raise');
    end;
  mReply := Run(cUnitMain, 6, 10, '');
  try
    Assert.AreEqual('routine', mReply.GetValue('query').Value);
    Assert.AreEqual('end@11:0', Points(mReply));
  finally
    mReply.Free;
  end;
end;

procedure TLspExitPointsTests.UnknownDocumentGivesError;
var
  mArguments: TJSONArray;
begin
  mArguments := TJSONObject.ParseJSONValue('["file:///C:/P/Fehlt.pas",{"line":0,"character":0}]') as TJSONArray;
  try
    Assert.WillRaise(
      procedure
      begin
        TLspExitPoints.Execute(FStore, FIndex, nil, nil, TExitPointsReaders.Create(nil, nil), mArguments).Free;
      end,
      EJsonRpcError);
  finally
    mArguments.Free;
  end;
end;

end.
