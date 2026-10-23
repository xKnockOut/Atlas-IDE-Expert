unit Atlas.Core.SymbolPath.Model.Tests;

// Weg zwischen Symbolen (#1117), Kern des Plugins: Antwort von
// atlas.symbolPath lesen (von Hand und aus dem echten Server), Units eines
// Wegs, Zeilen der Kette, Argumente des Befehls, qualifizierter Name.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasSymbolPathModelTests = class
  public
    [Test]
    procedure ParsesRouteAndSteps;
    [Test]
    procedure ParsesServerAnswer;
    [Test]
    procedure DisabledBrokenAndAmbiguous;
    [Test]
    procedure RowsAlternateNodesAndSteps;
    [Test]
    procedure CommandArguments;
  end;

/// <summary>Antwort mit einem Weg TKundenForm → Speichern → IKundenRepo.Laden → TKundenRepo.Laden (für Kern- und
/// UI-Tests); der dritte Schritt ist erschlossen.</summary>
function SampleSymbolPathAnswer: string;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Lsp.SymbolPath,
  Atlas.Core.SymbolPath.Model;

function SampleSymbolPathAnswer: string;
begin
  Result := '{"enabled":true,"status":"found","from":"TKundenForm","to":"TKundenRepo.Laden","maxSteps":8,' +
    '"searchedSteps":3,"visited":42,"elapsedMs":7,"routeCount":1,"moreRoutes":false,"callsIncomplete":false,' +
    '"restricted":false,"candidates":[],"routes":[{"nodes":[' +
    '{"caption":"TKundenForm","isUnit":false,"unit":"uKundenForm","file":"C:\\P\\uKundenForm.pas","line":4,' +
      '"character":2,"library":false},' +
    '{"caption":"TKundenForm.btnSpeichernClick","isUnit":false,"unit":"uKundenForm",' +
      '"file":"C:\\P\\uKundenForm.pas","line":8,"character":14,"library":false},' +
    '{"caption":"IKundenRepo.Laden","isUnit":false,"unit":"uRepoIntf","file":"C:\\P\\uRepoIntf.pas","line":5,' +
      '"character":13,"library":false},' +
    '{"caption":"TKundenRepo.Laden","isUnit":false,"unit":"uKundenRepo","file":"C:\\P\\uKundenRepo.pas",' +
      '"line":7,"character":14,"library":false}],"steps":[' +
    '{"kind":"contains","caption":"enthält","inferred":false,"reverse":false,"implementation":false,"file":"",' +
      '"line":0,"character":0},' +
    '{"kind":"calls","caption":"ruft auf","inferred":false,"reverse":false,"implementation":false,' +
      '"file":"C:\\P\\uKundenForm.pas","line":20,"character":4},' +
    '{"kind":"implements","caption":"umgesetzt von","inferred":true,"reverse":true,"implementation":false,' +
      '"file":"C:\\P\\uKundenRepo.pas","line":7,"character":14}]}]}';
end;

const
  AFile = 'C:\P\uA.pas';
  BFile = 'C:\P\uB.pas';
  AText = 'unit uA;'#10'interface'#10'uses uB;'#10'implementation'#10'end.';
  BText = 'unit uB;'#10'interface'#10'implementation'#10'end.';

{ TAtlasSymbolPathModelTests }

procedure TAtlasSymbolPathModelTests.ParsesRouteAndSteps;
var
  Answer: TAtlasSymbolPathAnswer;
  Route: TAtlasSymbolPathRoute;
  Units: TArray<string>;
begin
  Assert.IsTrue(TAtlasSymbolPathAnswer.Parse(SampleSymbolPathAnswer, Answer));
  Assert.IsTrue(Answer.Enabled);
  Assert.IsTrue(Answer.Status = TAtlasSymbolPathStatus.Found);
  Assert.AreEqual(3, Answer.StepCount);
  Assert.AreEqual(42, Answer.Visited);
  Assert.AreEqual(7, Answer.ElapsedMs);
  Route := Answer.Routes[0];
  Assert.AreEqual('TKundenForm.btnSpeichernClick', Route.Nodes[1].Caption);
  Assert.AreEqual('C:\P\uKundenForm.pas', Route.Nodes[1].FileName);
  Assert.AreEqual(8, Route.Nodes[1].Line);
  Assert.AreEqual('calls', Route.Steps[1].Kind);
  Assert.AreEqual(20, Route.Steps[1].Line);
  Assert.IsTrue(Route.Steps[2].Inferred);
  Assert.IsTrue(Route.Steps[2].Reverse);
  // Units in Reihenfolge, die Form nur einmal.
  Units := Route.UnitNames;
  Assert.AreEqual('uKundenForm,uRepoIntf,uKundenRepo', string.Join(',', Units));
end;

procedure TAtlasSymbolPathModelTests.ParsesServerAnswer;
var
  Index: ISymbolIndex;
  Service: TLspSymbolPath;
  Args: TJSONArray;
  Value: TJSONValue;
  Answer: TAtlasSymbolPathAnswer;
begin
  // Dasselbe Format wie der Server liefert: Weg uA → uB über uses.
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText(AText, AFile, nil));
  Index.AddUnit(TIndexExtractor.ExtractText(BText, BFile, nil));
  Service := TLspSymbolPath.Create(Index,
    function(const AFileName: string; out AContent: string): Boolean
    begin
      Result := True;
      if SameText(AFileName, AFile) then
        AContent := AText
      else if SameText(AFileName, BFile) then
        AContent := BText
      else
        Result := False;
    end,
    function(const AFileName: string): TArray<string>
    begin
      Result := nil;
    end,
    function(const AUnitName: string): Boolean
    begin
      Result := False;
    end,
    function(const AFileName: string; out ASettings: TServerSettings; out ANamespaces: TArray<string>): Boolean
    var
      Issues: TArray<TConfigurationIssue>;
    begin
      ASettings := TConfigurationParser.Parse('{}', Issues);
      ANamespaces := nil;
      Result := True;
    end);
  try
    Args := TJSONArray.Create;
    try
      Args.Add('file:///C:/P/uA.pas');
      Args.AddElement(TJSONObject.ParseJSONValue('{"from":"uA","to":"uB"}'));
      Value := Service.Execute(Args);
      try
        Assert.IsTrue(TAtlasSymbolPathAnswer.Parse(Value.ToJSON, Answer));
      finally
        Value.Free;
      end;
    finally
      Args.Free;
    end;
  finally
    Service.Free;
  end;
  Assert.IsTrue(Answer.Status = TAtlasSymbolPathStatus.Found);
  Assert.AreEqual(1, Answer.StepCount);
  Assert.AreEqual('uses', Answer.Routes[0].Steps[0].Kind);
  Assert.AreEqual('uA,uB', string.Join(',', Answer.Routes[0].UnitNames));
  // Fundstelle des uses-Eintrags: Zeile 3 (0-basiert 2).
  Assert.AreEqual(2, Answer.Routes[0].Steps[0].Line);
end;

procedure TAtlasSymbolPathModelTests.DisabledBrokenAndAmbiguous;
var
  Answer: TAtlasSymbolPathAnswer;
begin
  Assert.IsTrue(TAtlasSymbolPathAnswer.Parse('{"enabled":false}', Answer));
  Assert.IsFalse(Answer.Enabled);
  Assert.IsFalse(TAtlasSymbolPathAnswer.Parse('', Answer));
  Assert.IsFalse(TAtlasSymbolPathAnswer.Parse('kein JSON', Answer));
  Assert.IsFalse(TAtlasSymbolPathAnswer.Parse('[1]', Answer));
  Assert.IsFalse(TAtlasSymbolPathAnswer.Parse('{"enabled":true,"status":"unbekannt"}', Answer));
  // Weg mit falscher Zahl Schritte: beschädigt.
  Assert.IsFalse(TAtlasSymbolPathAnswer.Parse('{"enabled":true,"status":"found","routes":[{"nodes":[{}],' +
    '"steps":[{}]}]}', Answer));
  Assert.IsTrue(TAtlasSymbolPathAnswer.Parse('{"enabled":true,"status":"ambiguous","subject":"Laden",' +
    '"routes":[],"candidates":[{"caption":"TKundenRepo.Laden","unit":"uKundenRepo","file":"C:\\P\\uKundenRepo.pas",' +
    '"line":7,"character":14},{"caption":"TCacheRepo.Laden","unit":"uCacheRepo","file":"C:\\P\\uCacheRepo.pas",' +
    '"line":9,"character":14}]}', Answer));
  Assert.IsTrue(Answer.Status = TAtlasSymbolPathStatus.Ambiguous);
  Assert.AreEqual('Laden', Answer.Subject);
  Assert.AreEqual(2, Integer(Length(Answer.Candidates)));
  Assert.AreEqual(0, Answer.StepCount);
end;

procedure TAtlasSymbolPathModelTests.RowsAlternateNodesAndSteps;
var
  Answer: TAtlasSymbolPathAnswer;
  Rows: TArray<TAtlasSymbolPathRow>;
begin
  Assert.IsTrue(TAtlasSymbolPathAnswer.Parse(SampleSymbolPathAnswer, Answer));
  Rows := Answer.Rows;
  // Ein Weg: keine Überschrift, 4 Knoten und 3 Schritte im Wechsel.
  Assert.AreEqual(7, Integer(Length(Rows)));
  Assert.IsTrue(Rows[0].Kind = TAtlasSymbolPathRowKind.Node);
  Assert.IsTrue(Rows[1].Kind = TAtlasSymbolPathRowKind.Step);
  // Schritt ohne Fundstelle springt zum Knoten, zu dem er führt.
  Assert.AreEqual('C:\P\uKundenForm.pas', Rows[1].FileName);
  Assert.AreEqual(8, Rows[1].Line);
  Assert.AreEqual(20, Rows[3].Line);
  Assert.IsTrue(Rows[5].Inferred);
  Assert.IsFalse(Rows[3].Inferred);
  // Zwei Wege: je eine Überschrift.
  Answer.Routes := Answer.Routes + [Answer.Routes[0]];
  Rows := Answer.Rows;
  Assert.AreEqual(16, Integer(Length(Rows)));
  Assert.IsTrue(Rows[0].Kind = TAtlasSymbolPathRowKind.Header);
  Assert.IsTrue(Rows[8].Kind = TAtlasSymbolPathRowKind.Header);
  Assert.AreEqual(1, Rows[8].Route);
  // Mehrdeutig: nur die Treffer.
  Answer.Status := TAtlasSymbolPathStatus.Ambiguous;
  Answer.Candidates := Answer.Routes[0].Nodes;
  Rows := Answer.Rows;
  Assert.AreEqual(4, Integer(Length(Rows)));
  Assert.IsTrue(Rows[0].Kind = TAtlasSymbolPathRowKind.Candidate);
  Assert.AreEqual(7, Rows[3].Line);
end;

procedure TAtlasSymbolPathModelTests.CommandArguments;
begin
  Assert.AreEqual('["file:///C:/P/App.dproj",{"from":"TKundenForm","to":"uDatenbank","maxSteps":5,"all":true}]',
    TAtlasSymbolPathCommands.Arguments('file:///C:/P/App.dproj', ' TKundenForm ', 'uDatenbank', 5, True));
  // Außerhalb 1–16: Vorgabe des Servers.
  Assert.AreEqual('["u",{"from":"a","to":"b","all":false}]', TAtlasSymbolPathCommands.Arguments('u', 'a', 'b', 0,
    False));
  Assert.AreEqual('["u",{"from":"a","to":"b","all":false}]', TAtlasSymbolPathCommands.Arguments('u', 'a', 'b', 17,
    False));
  Assert.AreEqual('TFoo.Bar', TAtlasSymbolPathCommands.QualifiedName('Bar', 'TFoo'));
  Assert.AreEqual('Run', TAtlasSymbolPathCommands.QualifiedName('Run', ''));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSymbolPathModelTests);

end.
