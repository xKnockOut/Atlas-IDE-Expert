unit Atlas.Common.Lsp.ExitPoints.Tests;

// Befehl atlas.server.exitPoints (#698): Antwort im JSON, Schalter aus den
// Argumenten und Exceptions laut XMLDoc aus der deklarierenden Unit.

interface

uses
  DUnitX.TestFramework,
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
  LB = #13#10;
  MainFile = 'C:\P\Haupt.pas';
  LoaderFile = 'C:\P\Lader.pas';

  UnitLoader =
    'unit Lader;' + LB +
    'interface' + LB +
    'type' + LB +
    '  EBasis = class(TObject);' + LB +
    '  EFehler = class(EBasis);' + LB +
    '/// <summary>Liest.</summary>' + LB +
    '/// <exception cref="EFehler">kaputt</exception>' + LB +
    'procedure Lade;' + LB +
    'implementation' + LB +
    'procedure Lade;' + LB +
    'begin' + LB +
    'end;' + LB +
    'end.';

  UnitMain =
    'unit Haupt;' + LB +
    'interface' + LB +
    'uses Lader;' + LB +
    'function Wert(A: Integer): Integer;' + LB +
    'procedure Probe;' + LB +
    'implementation' + LB +
    'function Wert(A: Integer): Integer;' + LB +    // 6
    'begin' + LB +
    '  if A < 0 then' + LB +
    '    Exit;' + LB +                              // 9
    '  Result := A;' + LB +
    'end;' + LB +
    'procedure Probe;' + LB +                       // 12
    'begin' + LB +
    '  try' + LB +
    '    Lade;' + LB +                              // 15
    '  except' + LB +
    '    on E: EBasis do' + LB +                    // 17
    '      Exit;' + LB +
    '  end;' + LB +
    'end;' + LB +
    'end.';

{ TLspExitPointsTests }

procedure TLspExitPointsTests.Setup;
begin
  FStore := TDocumentStore.Create;
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitLoader, LoaderFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitMain, MainFile, nil));
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
  Uri: string;
  Arguments: TJSONArray;
  Position: TJSONObject;
  Reply: TJSONValue;
begin
  Uri := TDocumentUris.FromPath(MainFile);
  FStore.Close(Uri);
  FStore.Open(Uri, 'delphi', 1, AText);
  Arguments := TJSONArray.Create;
  try
    Arguments.Add(Uri);
    Position := TJSONObject.Create;
    Position.AddPair('line', TJSONNumber.Create(ALine));
    Position.AddPair('character', TJSONNumber.Create(ACharacter));
    Arguments.AddElement(Position);
    if ASettings <> '' then
      Arguments.AddElement(TJSONObject.ParseJSONValue(ASettings));
    Reply := TLspExitPoints.Execute(FStore, FIndex, nil, nil,
      function(const AFileName: string; out AText: string): Boolean
      begin
        Result := SameText(AFileName, LoaderFile);
        if Result then
          AText := UnitLoader;
      end,
      FSettingsFor, Arguments);
  finally
    Arguments.Free;
  end;
  Assert.IsTrue(Reply is TJSONObject);
  Result := TJSONObject(Reply);
end;

class function TLspExitPointsTests.Points(AReply: TJSONObject): string;
var
  Item: TJSONValue;
  Point: TJSONObject;
begin
  Result := '';
  for Item in AReply.GetValue('points') as TJSONArray do
  begin
    Point := Item as TJSONObject;
    if Result <> '' then
      Result := Result + ' ';
    Result := Result + Point.GetValue('kind').Value + '@' + Point.GetValue('line').Value + ':' +
      Point.GetValue('character').Value;
  end;
end;

procedure TLspExitPointsTests.ReplyCarriesRoutineAndPoints;
var
  Reply, Routine, First: TJSONObject;
begin
  // Auf Exit in Wert: die Routine, ihr Exit (ohne Result) und das Ende.
  Reply := Run(UnitMain, 9, 5, '');
  try
    Assert.AreEqual('routine', Reply.GetValue('query').Value);
    Routine := Reply.GetValue('routine') as TJSONObject;
    Assert.AreEqual('Wert', Routine.GetValue('name').Value);
    Assert.AreEqual('6', Routine.GetValue('line').Value);
    Assert.AreEqual('9', Routine.GetValue('character').Value);
    Assert.AreEqual('13', Routine.GetValue('endCharacter').Value);
    Assert.AreEqual('true', Reply.GetValue('function').Value);
    Assert.AreEqual('true', Reply.GetValue('resultMissing').Value);
    Assert.AreEqual('exit@9:4 end@11:0', Points(Reply));
    First := (Reply.GetValue('points') as TJSONArray).Items[0] as TJSONObject;
    Assert.AreEqual('8', First.GetValue('endCharacter').Value);
    Assert.AreEqual('true', First.GetValue('resultMissing').Value);
  finally
    Reply.Free;
  end;
  // Auf Result: die Zuweisungen und die Austritte, an denen Result fehlen kann.
  Reply := Run(UnitMain, 10, 3, '');
  try
    Assert.AreEqual('result', Reply.GetValue('query').Value);
    Assert.AreEqual('exit@9:4 result@10:2 end@11:0', Points(Reply));
  finally
    Reply.Free;
  end;
end;

procedure TLspExitPointsTests.ExceptionsFromDeclaringUnit;
var
  Reply, Source: TJSONObject;
begin
  // Lade steht in Lader und löst laut Doku EFehler aus, das von EBasis abstammt.
  Reply := Run(UnitMain, 17, 5, '');
  try
    Assert.AreEqual('exceptions', Reply.GetValue('query').Value);
    Assert.AreEqual('source@15:4 handler@17:4', Points(Reply));
    Source := (Reply.GetValue('points') as TJSONArray).Items[0] as TJSONObject;
    Assert.AreEqual('EFehler', Source.GetValue('exception').Value);
  finally
    Reply.Free;
  end;
end;

procedure TLspExitPointsTests.SwitchesFromArguments;
var
  Reply: TJSONObject;
begin
  Reply := Run(UnitMain, 17, 5, '{"exceptions":false,"loops":true}');
  try
    Assert.AreEqual('', Reply.GetValue('query').Value);
    Assert.AreEqual('', Points(Reply));
  finally
    Reply.Free;
  end;
end;

procedure TLspExitPointsTests.KeywordsFromConfiguration;
var
  Reply: TJSONObject;
begin
  // Ohne Exit in der Liste bleibt in Wert nur das Ende.
  FSettingsFor :=
    function(const AUri: string): THighlightSettings
    begin
      Result := THighlightSettings.Default;
      Result.ExitKeywords := TArray<string>.Create('raise');
    end;
  Reply := Run(UnitMain, 6, 10, '');
  try
    Assert.AreEqual('routine', Reply.GetValue('query').Value);
    Assert.AreEqual('end@11:0', Points(Reply));
  finally
    Reply.Free;
  end;
end;

procedure TLspExitPointsTests.UnknownDocumentGivesError;
var
  Arguments: TJSONArray;
begin
  Arguments := TJSONObject.ParseJSONValue('["file:///C:/P/Fehlt.pas",{"line":0,"character":0}]') as TJSONArray;
  try
    Assert.WillRaise(
      procedure
      begin
        TLspExitPoints.Execute(FStore, FIndex, nil, nil, nil, nil, Arguments).Free;
      end,
      EJsonRpcError);
  finally
    Arguments.Free;
  end;
end;

end.
