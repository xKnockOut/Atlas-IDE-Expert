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
  UnitText =
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

  FileName = 'C:\P\Werte.pas';

{ TLspDebugUnavailableTests }

function TLspDebugUnavailableTests.FactsAt(const AName: string; ALine: Integer): TUnavailableFacts;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(UnitText);
  try
    Result := TLspDebugUnavailable.Facts(nil, Tree, FileName, UnitText, AName, ALine);
  finally
    Tree.Free;
  end;
end;

procedure TLspDebugUnavailableTests.LifetimeBeforeWithinAfter;
var
  Facts: TUnavailableFacts;
begin
  Facts := FactsAt('Summe', 21);
  Assert.IsTrue(Facts.Local);
  Assert.AreEqual(22, Facts.FirstUse);
  Assert.AreEqual(29, Facts.LastUse);
  Assert.IsTrue(Facts.Lifetime = TVariableLifetime.Before, 'vor der ersten Verwendung');
  Assert.IsTrue(FactsAt('Summe', 25).Lifetime = TVariableLifetime.Within);
  Assert.IsTrue(FactsAt('Summe', 30).Lifetime = TVariableLifetime.After, 'nach der letzten Verwendung');
end;

procedure TLspDebugUnavailableTests.LoopCountsAsWhole;
var
  Facts: TUnavailableFacts;
begin
  // Rest steht zuletzt in Zeile 25, die Schleife reicht bis 27: am Ende der Schleife lebt Rest noch.
  Facts := FactsAt('Rest', 27);
  Assert.AreEqual(27, Facts.LastUse);
  Assert.IsTrue(Facts.Lifetime = TVariableLifetime.Within);
  Assert.IsTrue(FactsAt('Rest', 28).Lifetime = TVariableLifetime.After);
end;

procedure TLspDebugUnavailableTests.ParameterLivesFromStart;
var
  Facts: TUnavailableFacts;
begin
  Facts := FactsAt('Anzahl', 21);
  Assert.IsTrue(Facts.IsParameter);
  Assert.IsTrue(Facts.Local);
  Assert.AreEqual(14, Facts.FirstUse, 'ab Routinenanfang');
  Assert.IsTrue(Facts.Lifetime = TVariableLifetime.Within);
  Assert.IsTrue(FactsAt('Anzahl', 25).Lifetime = TVariableLifetime.After);
end;

procedure TLspDebugUnavailableTests.InlineAtDeclaration;
var
  Facts: TUnavailableFacts;
begin
  Facts := FactsAt('Result', 12);
  Assert.IsTrue(Facts.HasRoutine);
  Assert.AreEqual('TListe.Schnell', Facts.RoutineName);
  Assert.IsTrue(Facts.RoutineInline, 'inline an der Deklaration in der Klasse');
  Assert.IsTrue(Facts.Local, 'Result ist lokal');
  Assert.IsFalse(FactsAt('Summe', 22).RoutineInline);
end;

procedure TLspDebugUnavailableTests.FieldIsNotLocal;
begin
  Assert.IsFalse(FactsAt('FCount', 26).Local);
  Assert.IsTrue(FactsAt('Gibts', 26).Lifetime = TVariableLifetime.Unused);
end;

procedure TLspDebugUnavailableTests.FixesAroundOuterRoutine;
var
  Facts: TUnavailableFacts;
begin
  // Halt in der lokalen Routine: Direktiven um die äußere Routine (14 bis 31).
  Facts := FactsAt('Summe', 16);
  Assert.IsTrue(Facts.HasRoutine);
  Assert.AreEqual(2, Integer(Length(Facts.RoutineFix)));
  Assert.AreEqual(14, Facts.RoutineFix[0].Range.StartPos.Line);
  Assert.AreEqual('{$OPTIMIZATION OFF}'#10, Facts.RoutineFix[0].NewText);
  Assert.AreEqual(32, Facts.RoutineFix[1].Range.StartPos.Line);
  Assert.AreEqual('{$OPTIMIZATION ON}'#10, Facts.RoutineFix[1].NewText);
  Assert.AreEqual(1, Integer(Length(Facts.UnitFix)));
  Assert.AreEqual(1, Facts.UnitFix[0].Range.StartPos.Line, 'unter unit Werte;');
  Assert.AreEqual('{$O-}'#10, Facts.UnitFix[0].NewText);
end;

function Context(const AUri: string): TCompilerSwitchContext;
begin
  Result := Default(TCompilerSwitchContext);
  Result.FileName := FileName;
  Result.HasProject := True;
  Result.Input.Defines := TArray<string>.Create('DEBUG', '$D+', '$L+', '$O-');
end;

procedure TLspDebugUnavailableTests.HandlerWritesSwitchesAndFacts;
var
  Store: IDocumentStore;
  Handler: TLspDebugUnavailable;
  Dispatcher: TJsonRpcDispatcher;
  Request, Response: TJSONObject;
  Text: string;
begin
  Store := TDocumentStore.Create;
  Store.Open(TDocumentUris.FromPath(FileName), 'delphi', 1, UnitText);
  Handler := TLspDebugUnavailable.Create(Store, nil, nil, Context);
  Dispatcher := TJsonRpcDispatcher.Create;
  try
    Handler.Attach(Dispatcher);
    Request := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":1,"method":"' + TLspDebugUnavailable.Method +
      '","params":{"textDocument":{"uri":"' + TDocumentUris.FromPath(FileName).Replace('\', '\\') +
      '"},"position":{"line":30,"character":0},"name":"Summe"}}') as TJSONObject;
    try
      Response := Dispatcher.DispatchMessage(Request);
    finally
      Request.Free;
    end;
    try
      Text := Response.GetValue('result').ToJSON;
    finally
      Response.Free;
    end;
  finally
    Dispatcher.Free;
    Handler.Free;
  end;
  Assert.IsTrue(Text.Contains('{"name":"O","longName":"OPTIMIZATION","value":"+","projectValue":"-",' +
    '"deviates":true,"origin":{"kind":"directive","text":"{$O+}"'), Text);
  Assert.IsTrue(Text.Contains('"name":"D","longName":"DEBUGINFO","value":"+"'), Text);
  Assert.IsTrue(Text.Contains('"routine":{"name":"TListe.Lauf","inline":false,"startLine":14,"endLine":31}'), Text);
  Assert.IsTrue(Text.Contains('"lifetime":"after"'), Text);
  Assert.IsTrue(Text.Contains('"routineOptimization":{"changes":'), Text);
  Assert.IsTrue(Text.Contains('"unitOptimization":{"changes":'), Text);
end;

end.
