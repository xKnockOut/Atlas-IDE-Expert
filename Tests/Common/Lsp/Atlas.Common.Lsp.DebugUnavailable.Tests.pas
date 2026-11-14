unit Atlas.Common.Lsp.DebugUnavailable.Tests;

// Warum ein Wert beim Debuggen fehlt (#840), Server: Lebensdauer vor, in und
// nach der Verwendung, Schleifen zählen ganz, Parameter ab Routinenanfang,
// inline an Implementierung und Deklaration, Änderungen für
// {$OPTIMIZATION OFF/ON} um die äußere Routine und {$O-} unter dem Kopf,
// JSON-Antwort mit D, L und O samt Herkunft.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Lsp.DebugUnavailable;

type
  [TestFixture]
  TLspDebugUnavailableTests = class
  private
    function FactsAt(const AName: string; ALine: Integer): TUnavailableFacts;
  public
    [Test]
    procedure LifetimeBeforeWithinAfter;
    [Test]
    procedure LoopCountsAsWhole;
    [Test]
    procedure ParameterLivesFromStart;
    [Test]
    procedure InlineAtDeclaration;
    [Test]
    procedure FieldIsNotLocal;
    [Test]
    procedure FixesAroundOuterRoutine;
    [Test]
    procedure HandlerWritesSwitchesAndFacts;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Lsp.CompilerSwitches;

const
  cUnitText =
    'unit Werte;'#10 +                                  // 0
    'interface'#10 +                                    // 1
    'type'#10 +                                         // 2
    '  TListe = class'#10 +                             // 3
    '    FCount: Integer;'#10 +                         // 4
    '    function Schnell: Integer; inline;'#10 +       // 5
    '    procedure Lauf(Anzahl: Integer);'#10 +         // 6
    '  end;'#10 +                                       // 7
    'implementation'#10 +                               // 8
    '{$O+}'#10 +                                        // 9
    'function TListe.Schnell: Integer;'#10 +            // 10
    'begin'#10 +                                        // 11
    '  Result := FCount;'#10 +                          // 12
    'end;'#10 +                                         // 13
    'procedure TListe.Lauf(Anzahl: Integer);'#10 +      // 14
    '  procedure Innen;'#10 +                           // 15
    '  begin'#10 +                                      // 16
    '  end;'#10 +                                       // 17
    'var'#10 +                                          // 18
    '  Summe, Rest: Integer;'#10 +                      // 19
    'begin'#10 +                                        // 20
    '  Rest := 0;'#10 +                                 // 21
    '  Summe := Anzahl;'#10 +                           // 22
    '  while Rest < 3 do'#10 +                          // 23
    '  begin'#10 +                                      // 24
    '    Inc(Rest);'#10 +                               // 25
    '    FCount := 1;'#10 +                             // 26
    '  end;'#10 +                                       // 27
    '  Innen;'#10 +                                     // 28
    '  Summe := 0;'#10 +                                // 29
    '  FCount := 2;'#10 +                               // 30
    'end;'#10 +                                         // 31
    'end.';

  cFileName = 'C:\P\Werte.pas';

{ TLspDebugUnavailableTests }

function TLspDebugUnavailableTests.FactsAt(const AName: string; ALine: Integer): TUnavailableFacts;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(cUnitText);
  try
    Result := TLspDebugUnavailable.Facts(nil, mTree, cFileName, cUnitText, AName, ALine);
  finally
    mTree.Free;
  end;
end;

procedure TLspDebugUnavailableTests.LifetimeBeforeWithinAfter;
var
  mFacts: TUnavailableFacts;
begin
  mFacts := FactsAt('Summe', 21);
  Assert.IsTrue(mFacts.Local);
  Assert.AreEqual(22, mFacts.FirstUse);
  Assert.AreEqual(29, mFacts.LastUse);
  Assert.AreEqual<TVariableLifetime>(TVariableLifetime.Before, mFacts.Lifetime, 'vor der ersten Verwendung');
  Assert.AreEqual<TVariableLifetime>(TVariableLifetime.Within, FactsAt('Summe', 25).Lifetime);
  Assert.AreEqual<TVariableLifetime>(TVariableLifetime.After,
    FactsAt('Summe', 30).Lifetime, 'nach der letzten Verwendung');
end;

procedure TLspDebugUnavailableTests.LoopCountsAsWhole;
var
  mFacts: TUnavailableFacts;
begin
  // Rest steht zuletzt in Zeile 25, die Schleife reicht bis 27: am Ende der Schleife lebt Rest noch.
  mFacts := FactsAt('Rest', 27);
  Assert.AreEqual(27, mFacts.LastUse);
  Assert.AreEqual<TVariableLifetime>(TVariableLifetime.Within, mFacts.Lifetime);
  Assert.AreEqual<TVariableLifetime>(TVariableLifetime.After, FactsAt('Rest', 28).Lifetime);
end;

procedure TLspDebugUnavailableTests.ParameterLivesFromStart;
var
  mFacts: TUnavailableFacts;
begin
  mFacts := FactsAt('Anzahl', 21);
  Assert.IsTrue(mFacts.IsParameter);
  Assert.IsTrue(mFacts.Local);
  Assert.AreEqual(14, mFacts.FirstUse, 'ab Routinenanfang');
  Assert.AreEqual<TVariableLifetime>(TVariableLifetime.Within, mFacts.Lifetime);
  Assert.AreEqual<TVariableLifetime>(TVariableLifetime.After, FactsAt('Anzahl', 25).Lifetime);
end;

procedure TLspDebugUnavailableTests.InlineAtDeclaration;
var
  mFacts: TUnavailableFacts;
begin
  mFacts := FactsAt('Result', 12);
  Assert.IsTrue(mFacts.HasRoutine);
  Assert.AreEqual('TListe.Schnell', mFacts.RoutineName);
  Assert.IsTrue(mFacts.RoutineInline, 'inline an der Deklaration in der Klasse');
  Assert.IsTrue(mFacts.Local, 'Result ist lokal');
  Assert.IsFalse(FactsAt('Summe', 22).RoutineInline);
end;

procedure TLspDebugUnavailableTests.FieldIsNotLocal;
begin
  Assert.IsFalse(FactsAt('FCount', 26).Local);
  Assert.AreEqual<TVariableLifetime>(TVariableLifetime.Unused, FactsAt('Gibts', 26).Lifetime);
end;

procedure TLspDebugUnavailableTests.FixesAroundOuterRoutine;
var
  mFacts: TUnavailableFacts;
begin
  // Halt in der lokalen Routine: Direktiven um die äußere Routine (14 bis 31).
  mFacts := FactsAt('Summe', 16);
  Assert.IsTrue(mFacts.HasRoutine);
  Assert.AreEqual(2, Integer(Length(mFacts.RoutineFix)));
  Assert.AreEqual(14, mFacts.RoutineFix[0].Range.StartPos.Line);
  Assert.AreEqual('{$OPTIMIZATION OFF}'#10, mFacts.RoutineFix[0].NewText);
  Assert.AreEqual(32, mFacts.RoutineFix[1].Range.StartPos.Line);
  Assert.AreEqual('{$OPTIMIZATION ON}'#10, mFacts.RoutineFix[1].NewText);
  Assert.AreEqual(1, Integer(Length(mFacts.UnitFix)));
  Assert.AreEqual(1, mFacts.UnitFix[0].Range.StartPos.Line, 'unter unit Werte;');
  Assert.AreEqual('{$O-}'#10, mFacts.UnitFix[0].NewText);
end;

function Context(const AUri: string): TCompilerSwitchContext;
begin
  Result := Default(TCompilerSwitchContext);
  Result.FileName := cFileName;
  Result.HasProject := True;
  Result.Input.Defines := TArray<string>.Create('DEBUG', '$D+', '$L+', '$O-');
end;

procedure TLspDebugUnavailableTests.HandlerWritesSwitchesAndFacts;
var
  mStore: IDocumentStore;
  mHandler: TLspDebugUnavailable;
  mDispatcher: TJsonRpcDispatcher;
  mRequest, mResponse: TJSONObject;
  mText: string;
begin
  mStore := TDocumentStore.Create;
  mStore.Open(TDocumentUris.FromPath(cFileName), 'delphi', 1, cUnitText);
  mHandler := TLspDebugUnavailable.Create(mStore, nil, nil, Context);
  mDispatcher := TJsonRpcDispatcher.Create;
  try
    mHandler.Attach(mDispatcher);
    mRequest := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":1,"method":"' + TLspDebugUnavailable.cMethod +
      '","params":{"textDocument":{"uri":"' + TDocumentUris.FromPath(cFileName).Replace('\', '\\') +
      '"},"position":{"line":30,"character":0},"name":"Summe"}}') as TJSONObject;
    try
      mResponse := mDispatcher.DispatchMessage(mRequest);
    finally
      mRequest.Free;
    end;
    try
      mText := mResponse.GetValue('result').ToJSON;
    finally
      mResponse.Free;
    end;
  finally
    mDispatcher.Free;
    mHandler.Free;
  end;
  Assert.IsTrue(mText.Contains('{"name":"O","longName":"OPTIMIZATION","value":"+","projectValue":"-",' +
    '"deviates":true,"origin":{"kind":"directive","text":"{$O+}"'), mText);
  Assert.IsTrue(mText.Contains('"name":"D","longName":"DEBUGINFO","value":"+"'), mText);
  Assert.IsTrue(mText.Contains('"routine":{"name":"TListe.Lauf","inline":false,"startLine":14,"endLine":31}'), mText);
  Assert.IsTrue(mText.Contains('"lifetime":"after"'), mText);
  Assert.IsTrue(mText.Contains('"routineOptimization":{"changes":'), mText);
  Assert.IsTrue(mText.Contains('"unitOptimization":{"changes":'), mText);
end;

end.
