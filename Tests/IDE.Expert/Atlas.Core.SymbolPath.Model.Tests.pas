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
  System.Generics.Collections,
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
  cAFile = 'C:\P\uA.pas';
  cBFile = 'C:\P\uB.pas';
  cAText = 'unit uA;'#10'interface'#10'uses uB;'#10'implementation'#10'end.';
  cBText = 'unit uB;'#10'interface'#10'implementation'#10'end.';

{ TAtlasSymbolPathModelTests }

procedure TAtlasSymbolPathModelTests.ParsesRouteAndSteps;
var
  mAnswer: TAtlasSymbolPathAnswer;
  mRoute: TAtlasSymbolPathRoute;
  mUnits: TArray<string>;
begin
  Assert.IsTrue(TAtlasSymbolPathAnswer.Parse(SampleSymbolPathAnswer, mAnswer));
  Assert.IsTrue(mAnswer.Enabled);
  Assert.AreEqual<TAtlasSymbolPathStatus>(TAtlasSymbolPathStatus.Found, mAnswer.Status);
  Assert.AreEqual(3, mAnswer.StepCount);
  Assert.AreEqual(42, mAnswer.Visited);
  Assert.AreEqual(7, mAnswer.ElapsedMs);
  mRoute := mAnswer.Routes[0];
  Assert.AreEqual('TKundenForm.btnSpeichernClick', mRoute.Nodes[1].Caption);
  Assert.AreEqual('C:\P\uKundenForm.pas', mRoute.Nodes[1].FileName);
  Assert.AreEqual(8, mRoute.Nodes[1].Line);
  Assert.AreEqual('calls', mRoute.Steps[1].Kind);
  Assert.AreEqual(20, mRoute.Steps[1].Line);
  Assert.IsTrue(mRoute.Steps[2].Inferred);
  Assert.IsTrue(mRoute.Steps[2].Reverse);
  // Units in Reihenfolge, die Form nur einmal.
  mUnits := mRoute.UnitNames;
  Assert.AreEqual('uKundenForm,uRepoIntf,uKundenRepo', string.Join(',', mUnits));
end;

/// <summary>Wegsuche über zwei Units: uA verwendet uB.</summary>
function CreateUsesPathService: TLspSymbolPath;
var
  mIndex: ISymbolIndex;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText(cAText, cAFile, nil));
  mIndex.AddUnit(TIndexExtractor.ExtractText(cBText, cBFile, nil));
  Result := TLspSymbolPath.Create(mIndex,
    function(const AFileName: string; out AContent: string): Boolean
    begin
      Result := True;
      if SameText(AFileName, cAFile) then
      begin
        AContent := cAText;
      end
      else if SameText(AFileName, cBFile) then
      begin
        AContent := cBText;
      end
      else
      begin
        Result := False;
      end;
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
end;

procedure TAtlasSymbolPathModelTests.ParsesServerAnswer;
var
  mService: TLspSymbolPath;
  mArgs: TJSONArray;
  mValue: TJSONValue;
  mAnswer: TAtlasSymbolPathAnswer;
begin
  // Dasselbe Format wie der Server liefert: Weg uA → uB über uses.
  mService := CreateUsesPathService;
  try
    mArgs := TJSONArray.Create;
    try
      mArgs.Add('file:///C:/P/uA.pas');
      mArgs.AddElement(TJSONObject.ParseJSONValue('{"from":"uA","to":"uB"}'));
      mValue := mService.Execute(mArgs);
      try
        Assert.IsTrue(TAtlasSymbolPathAnswer.Parse(mValue.ToJSON, mAnswer));
      finally
        mValue.Free;
      end;
    finally
      mArgs.Free;
    end;
  finally
    mService.Free;
  end;
  Assert.AreEqual<TAtlasSymbolPathStatus>(TAtlasSymbolPathStatus.Found, mAnswer.Status);
  Assert.AreEqual(1, mAnswer.StepCount);
  Assert.AreEqual('uses', mAnswer.Routes[0].Steps[0].Kind);
  Assert.AreEqual('uA,uB', string.Join(',', mAnswer.Routes[0].UnitNames));
  // Fundstelle des uses-Eintrags: Zeile 3 (0-basiert 2).
  Assert.AreEqual(2, mAnswer.Routes[0].Steps[0].Line);
end;

procedure TAtlasSymbolPathModelTests.DisabledBrokenAndAmbiguous;
var
  mAnswer: TAtlasSymbolPathAnswer;
begin
  Assert.IsTrue(TAtlasSymbolPathAnswer.Parse('{"enabled":false}', mAnswer));
  Assert.IsFalse(mAnswer.Enabled);
  Assert.IsFalse(TAtlasSymbolPathAnswer.Parse('', mAnswer));
  Assert.IsFalse(TAtlasSymbolPathAnswer.Parse('kein JSON', mAnswer));
  Assert.IsFalse(TAtlasSymbolPathAnswer.Parse('[1]', mAnswer));
  Assert.IsFalse(TAtlasSymbolPathAnswer.Parse('{"enabled":true,"status":"unbekannt"}', mAnswer));
  // Weg mit falscher Zahl Schritte: beschädigt.
  Assert.IsFalse(TAtlasSymbolPathAnswer.Parse('{"enabled":true,"status":"found","routes":[{"nodes":[{}],' +
    '"steps":[{}]}]}', mAnswer));
  Assert.IsTrue(TAtlasSymbolPathAnswer.Parse('{"enabled":true,"status":"ambiguous","subject":"Laden",' +
    '"routes":[],"candidates":[{"caption":"TKundenRepo.Laden","unit":"uKundenRepo","file":"C:\\P\\uKundenRepo.pas",' +
    '"line":7,"character":14},{"caption":"TCacheRepo.Laden","unit":"uCacheRepo","file":"C:\\P\\uCacheRepo.pas",' +
    '"line":9,"character":14}]}', mAnswer));
  Assert.AreEqual<TAtlasSymbolPathStatus>(TAtlasSymbolPathStatus.Ambiguous, mAnswer.Status);
  Assert.AreEqual('Laden', mAnswer.Subject);
  Assert.AreEqual(2, Integer(Length(mAnswer.Candidates)));
  Assert.AreEqual(0, mAnswer.StepCount);
end;

procedure TAtlasSymbolPathModelTests.RowsAlternateNodesAndSteps;
var
  mAnswer: TAtlasSymbolPathAnswer;
  mRows: TArray<TAtlasSymbolPathRow>;
begin
  Assert.IsTrue(TAtlasSymbolPathAnswer.Parse(SampleSymbolPathAnswer, mAnswer));
  mRows := mAnswer.Rows;
  // Ein Weg: keine Überschrift, 4 Knoten und 3 Schritte im Wechsel.
  Assert.AreEqual(7, Integer(Length(mRows)));
  Assert.AreEqual<TAtlasSymbolPathRowKind>(TAtlasSymbolPathRowKind.Node, mRows[0].Kind);
  Assert.AreEqual<TAtlasSymbolPathRowKind>(TAtlasSymbolPathRowKind.Step, mRows[1].Kind);
  // Schritt ohne Fundstelle springt zum Knoten, zu dem er führt.
  Assert.AreEqual('C:\P\uKundenForm.pas', mRows[1].FileName);
  Assert.AreEqual(8, mRows[1].Line);
  Assert.AreEqual(20, mRows[3].Line);
  Assert.IsTrue(mRows[5].Inferred);
  Assert.IsFalse(mRows[3].Inferred);
  // Zwei Wege: je eine Überschrift.
  mAnswer.Routes := mAnswer.Routes + [mAnswer.Routes[0]];
  mRows := mAnswer.Rows;
  Assert.AreEqual(16, Integer(Length(mRows)));
  Assert.AreEqual<TAtlasSymbolPathRowKind>(TAtlasSymbolPathRowKind.Header, mRows[0].Kind);
  Assert.AreEqual<TAtlasSymbolPathRowKind>(TAtlasSymbolPathRowKind.Header, mRows[8].Kind);
  Assert.AreEqual(1, mRows[8].Route);
  // Mehrdeutig: nur die Treffer.
  mAnswer.Status := TAtlasSymbolPathStatus.Ambiguous;
  mAnswer.Candidates := mAnswer.Routes[0].Nodes;
  mRows := mAnswer.Rows;
  Assert.AreEqual(4, Integer(Length(mRows)));
  Assert.AreEqual<TAtlasSymbolPathRowKind>(TAtlasSymbolPathRowKind.Candidate, mRows[0].Kind);
  Assert.AreEqual(7, mRows[3].Line);
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
