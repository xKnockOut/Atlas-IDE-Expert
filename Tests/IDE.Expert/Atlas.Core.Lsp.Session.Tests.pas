unit Atlas.Core.Lsp.Session.Tests;

// Parameter von initialize und Antwort auf workspace/applyEdit (S-03a): Klassenfunktionen von TLspSession
// ohne Server und ohne Windows. Die Tests mit Client und Server stehen in Atlas.Core.Lsp.Tests.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspInitializeParamsTests = class
  public
    [Test]
    procedure InitializeParamsAnnouncesApplyEditOnlyWithHandler;
    [Test]
    procedure InitializeParamsHasPlainTextHoverAndSnippets;
    [Test]
    procedure InitializeParamsCarriesWorkspaceFolders;
    [Test]
    procedure InitializeParamsMergesSettingsAndContexts;
    [Test]
    procedure InitializeParamsWithoutOptionsHasNoInitializationOptions;
    [Test]
    procedure ApplyEditAnswerOmitsEmptyReason;
    /// <summary>#621: data.tag einer CodeAction landet in Tag.</summary>
    [Test]
    procedure CodeActionCarriesTag;
    /// <summary>#503: Gliederung flach, Container = Elternsymbol; SymbolInformation ebenso.</summary>
    [Test]
    procedure DocumentSymbolsAreFlattened;
    [Test]
    procedure InlineValueRefsAreVariableLookups;
  end;

  /// <summary>Antwort von atlas/impact (#1120): Ebenen, Ursachen, Formulare, Tests, Grenzen.</summary>
  [TestFixture]
  TLspImpactResponseTests = class
  public
    [Test]
    procedure ImpactFromJson;
    [Test]
    procedure ImpactWithoutSymbol;
  end;

implementation

uses
  System.Generics.Collections,
  System.SysUtils,
  System.JSON,
  Atlas.Core.Projects.Contract,
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Lsp.Session;

function Context(const AProject: string): TAtlasProjectContext;
begin
  Result := Default(TAtlasProjectContext);
  Result.Project := AProject;
  Result.Configuration := 'Debug';
  Result.Platform := 'Win64';
end;

procedure TLspInitializeParamsTests.InitializeParamsAnnouncesApplyEditOnlyWithHandler;
var
  Params: TJSONObject;
begin
  Params := TLspSession.InitializeParams(nil, '', nil, True);
  try
    Assert.IsTrue(Params.GetValue<Boolean>('capabilities.workspace.applyEdit'));
  finally
    Params.Free;
  end;
  Params := TLspSession.InitializeParams(nil, '', nil, False);
  try
    Assert.IsFalse(Params.GetValue<Boolean>('capabilities.workspace.applyEdit'));
    Assert.IsTrue(Params.GetValue<Boolean>('capabilities.workspace.diagnostics.refreshSupport'));
  finally
    Params.Free;
  end;
end;

procedure TLspInitializeParamsTests.InitializeParamsHasPlainTextHoverAndSnippets;
var
  Params: TJSONObject;
  Formats: TJSONArray;
begin
  Params := TLspSession.InitializeParams(nil, '', nil, False);
  try
    Formats := Params.GetValue<TJSONArray>('capabilities.textDocument.hover.contentFormat');
    Assert.AreEqual(1, Integer(Formats.Count));
    Assert.AreEqual('plaintext', Formats.Items[0].Value);
    Assert.IsTrue(Params.GetValue<Boolean>('capabilities.textDocument.completion.completionItem.snippetSupport'));
    Assert.IsFalse(Params.GetValue<Boolean>('capabilities.textDocument.diagnostic.dynamicRegistration'));
    Assert.AreEqual('Atlas IDE Expert', Params.GetValue<string>('clientInfo.name'));
    Assert.IsTrue(Params.GetValue('processId') is TJSONNull);
  finally
    Params.Free;
  end;
end;

procedure TLspInitializeParamsTests.InitializeParamsCarriesWorkspaceFolders;
var
  Params: TJSONObject;
begin
  Params := TLspSession.InitializeParams(['C:\A\Eins.dproj', 'C:\B\Zwei.dproj'], '', nil, False);
  try
    Assert.AreEqual(2, Params.GetValue<TJSONArray>('workspaceFolders').Count);
    Assert.AreEqual('Eins', TJSONObject(Params.GetValue<TJSONArray>('workspaceFolders').Items[0])
      .GetValue<string>('name'));
  finally
    Params.Free;
  end;
  Params := TLspSession.InitializeParams(nil, '', nil, False);
  try
    Assert.IsNull(Params.GetValue('workspaceFolders'));
  finally
    Params.Free;
  end;
end;

procedure TLspInitializeParamsTests.InitializeParamsMergesSettingsAndContexts;
var
  Params: TJSONObject;
begin
  Params := TLspSession.InitializeParams(nil, '{"rules":{"x":"off"}}',
    [Context('C:\A\Eins.dproj'), Context('C:\B\Zwei.dproj')], False);
  try
    Assert.AreEqual('off', Params.GetValue<string>('initializationOptions.settings.atlas.rules.x'));
    Assert.AreEqual(2, Params.GetValue<TJSONArray>('initializationOptions.projectContexts').Count);
    Assert.AreEqual('Win64', TJSONObject(Params.GetValue<TJSONArray>('initializationOptions.projectContexts')
      .Items[1]).GetValue<string>('platform'));
  finally
    Params.Free;
  end;
  // Nur Kontexte: initializationOptions entsteht trotzdem.
  Params := TLspSession.InitializeParams(nil, '', [Context('C:\A\Eins.dproj')], False);
  try
    Assert.AreEqual(1, Params.GetValue<TJSONArray>('initializationOptions.projectContexts').Count);
    Assert.IsNull(Params.GetValue<TJSONObject>('initializationOptions').GetValue('settings'));
  finally
    Params.Free;
  end;
end;

procedure TLspInitializeParamsTests.InitializeParamsWithoutOptionsHasNoInitializationOptions;
var
  Params: TJSONObject;
begin
  Params := TLspSession.InitializeParams(['C:\A\Eins.dproj'], '', nil, True);
  try
    Assert.IsNull(Params.GetValue('initializationOptions'));
  finally
    Params.Free;
  end;
end;

procedure TLspInitializeParamsTests.ApplyEditAnswerOmitsEmptyReason;
var
  Answer: TJSONObject;
begin
  Answer := TLspSession.ApplyEditAnswer(True, '');
  try
    Assert.IsTrue(Answer.GetValue<Boolean>('applied'));
    Assert.IsNull(Answer.GetValue('failureReason'));
  finally
    Answer.Free;
  end;
  Answer := TLspSession.ApplyEditAnswer(False, 'Datei schreibgeschützt');
  try
    Assert.IsFalse(Answer.GetValue<Boolean>('applied'));
    Assert.AreEqual('Datei schreibgeschützt', Answer.GetValue<string>('failureReason'));
  finally
    Answer.Free;
  end;
end;

procedure TLspInitializeParamsTests.CodeActionCarriesTag;
var
  Value: TJSONValue;
  Action: TLspCodeAction;
begin
  Value := TJSONObject.ParseJSONValue('{"title":"Vcl.Grids entfernen","kind":"quickfix","data":{"tag":"uses.remove"}}');
  try
    Assert.IsTrue(TLspCodeAction.FromJson(Value, Action));
    Assert.AreEqual('uses.remove', Action.Tag);
  finally
    Value.Free;
  end;
  Value := TJSONObject.ParseJSONValue('{"title":"Ohne","kind":"quickfix"}');
  try
    Assert.IsTrue(TLspCodeAction.FromJson(Value, Action));
    Assert.AreEqual('', Action.Tag);
  finally
    Value.Free;
  end;
end;

procedure TLspInitializeParamsTests.DocumentSymbolsAreFlattened;
var
  Response: TJSONValue;
  Symbols: TArray<TAtlasSymbol>;
begin
  Response := TJSONObject.ParseJSONValue('[{"name":"TKunde","kind":5,"range":{"start":{"line":3,"character":2}},' +
    '"selectionRange":{"start":{"line":3,"character":4}},"children":[{"name":"Laden","kind":6,' +
    '"selectionRange":{"start":{"line":9,"character":14}}}]},{"name":"Hilfe","kind":12,' +
    '"range":{"start":{"line":20,"character":0}}}]');
  try
    Symbols := TLspSession.SymbolsOfDocument(Response, 'C:\P\Kunden.pas');
  finally
    Response.Free;
  end;
  Assert.AreEqual(3, Integer(Length(Symbols)));
  Assert.AreEqual('TKunde', Symbols[0].Name);
  Assert.AreEqual(4, Symbols[0].Character);
  Assert.AreEqual('Laden', Symbols[1].Name);
  Assert.AreEqual('TKunde', Symbols[1].Container);
  Assert.AreEqual(9, Symbols[1].Line);
  Assert.AreEqual('C:\P\Kunden.pas', Symbols[1].FileName);
  Assert.AreEqual('Hilfe', Symbols[2].Name);
  Assert.AreEqual(20, Symbols[2].Line);
  Assert.AreEqual('', Symbols[2].Container);
  Response := TJSONObject.ParseJSONValue('[{"name":"Laden","kind":6,"containerName":"TKunde",' +
    '"location":{"uri":"file:///C:/P/Kunden.pas","range":{"start":{"line":7,"character":3}}}}]');
  try
    Symbols := TLspSession.SymbolsOfDocument(Response, 'C:\P\Kunden.pas');
  finally
    Response.Free;
  end;
  Assert.AreEqual(1, Integer(Length(Symbols)));
  Assert.AreEqual('TKunde', Symbols[0].Container);
  Assert.AreEqual(7, Symbols[0].Line);
  Assert.AreEqual(Integer(0), Integer(Length(TLspSession.SymbolsOfDocument(nil, 'x'))));
end;

{ TLspImpactResponseTests }

const
  ImpactJson =
    '{"symbol":{"name":"Ziel","uri":"file:///c%3A/p/Werkzeug.pas","selectionRange":{"start":{"line":13,' +
    '"character":10},"end":{"line":13,"character":14}}},"symbolForms":[],"depth":2,"places":[' +
    '{"level":1,"edge":"call","cause":-1,"item":{"name":"Hilfe","uri":"file:///c%3A/p/Werkzeug.pas",' +
    '"selectionRange":{"start":{"line":31,"character":10},"end":{"line":31,"character":15}}},"ranges":[' +
    '{"start":{"line":33,"character":2},"end":{"line":33,"character":6}},{"start":{"line":34,"character":2},' +
    '"end":{"line":34,"character":6}}],"forms":[]},' +
    '{"level":2,"edge":"call","cause":0,"item":{"name":"Button1Click","uri":"file:///c%3A/p/Haupt.pas",' +
    '"selectionRange":{"start":{"line":9,"character":17},"end":{"line":9,"character":29}}},"ranges":[' +
    '{"start":{"line":11,"character":2},"end":{"line":11,"character":6}}],"atlasConfidence":{"level":"inferred",' +
    '"reason":"virtual","detail":"über Basis"},"forms":[{"uri":"file:///c%3A/p/Haupt.dfm","range":{"start":' +
    '{"line":2,"character":14},"end":{"line":2,"character":26}},"text":"OnClick = Button1Click"}]},' +
    '{"level":2,"edge":"call","cause":0,"item":{"name":"PrueftHilfe","uri":"file:///c%3A/p/Werkzeug.Tests.pas",' +
    '"selectionRange":{"start":{"line":11,"character":25},"end":{"line":11,"character":36}}},"ranges":[],' +
    '"forms":[],"test":"Werkzeug.Tests.TWerkzeugTests.PrueftHilfe"}],' +
    '"tests":[{"name":"Werkzeug.Tests.TWerkzeugTests.PrueftHilfe","run":["Werkzeug.Tests.TWerkzeugTests.PrueftHilfe"],' +
    '"uri":"file:///c%3A/p/Werkzeug.Tests.pas","line":11,"level":2},{"name":"A.T.Fall","run":["A.T.Fall.Eins",' +
    '"A.T.Fall.Zwei"],"uri":"file:///c%3A/p/A.pas","line":3,"level":2},{"name":"B.T.Ohne","uri":' +
    '"file:///c%3A/p/B.pas","line":4,"level":2}],"limits":{"depth":true,"count":false,"time":true},' +
    '"unexpanded":2,"maxPlaces":1000,"timeoutMs":8000}';

procedure TLspImpactResponseTests.ImpactFromJson;
var
  Json: TJSONValue;
  Impact: TAtlasImpact;
  Children: TArray<Integer>;
begin
  Json := TJSONObject.ParseJSONValue(ImpactJson);
  try
    Impact := TLspSession.ImpactFromJson(Json);
  finally
    Json.Free;
  end;
  Assert.IsTrue(Impact.Found);
  Assert.AreEqual('Ziel', Impact.Symbol.Name);
  Assert.AreEqual(2, Impact.Depth);
  Assert.AreEqual(3, Integer(Length(Impact.Places)));
  Assert.AreEqual(1, Impact.LevelCount(1));
  Assert.AreEqual(2, Impact.LevelCount(2));
  Assert.AreEqual(2, Impact.CountFrom(2));
  Children := Impact.Children(0);
  Assert.AreEqual(2, Integer(Length(Children)));
  Assert.AreEqual(1, Children[0]);
  Assert.AreEqual(1, Integer(Length(Impact.Children(-1))));
  // Doppelklick: erste Verwendung der Ursache in der Stelle.
  Assert.AreEqual(2, Impact.Places[0].UseCount);
  Assert.AreEqual(33, Impact.Places[0].UseLine);
  Assert.AreEqual(2, Impact.Places[0].UseCharacter);
  // Ohne Verwendung (Override) die Stelle selbst.
  Assert.AreEqual(11, Impact.Places[2].UseLine);
  Assert.AreEqual(25, Impact.Places[2].UseCharacter);
  Assert.IsTrue(Impact.Places[1].Item.Confidence.Inferred);
  Assert.AreEqual(1, Integer(Length(Impact.Places[1].Forms)));
  Assert.AreEqual('OnClick = Button1Click', Impact.Places[1].Forms[0].Text);
  Assert.AreEqual(2, Impact.Places[1].Forms[0].Line);
  Assert.AreEqual('Werkzeug.Tests.TWerkzeugTests.PrueftHilfe', Impact.Places[2].Test);
  Assert.AreEqual(3, Integer(Length(Impact.Tests)));
  Assert.AreEqual(11, Impact.Tests[0].Line);
  // Ohne "run" läuft der Test unter seinem Namen.
  Assert.AreEqual('B.T.Ohne', Impact.Tests[2].RunNames[0]);
  Assert.AreEqual(4, Integer(Length(Impact.RunNames)));
  Assert.AreEqual('A.T.Fall.Zwei', Impact.RunNames[2]);
  Assert.IsTrue(Impact.DepthReached);
  Assert.IsFalse(Impact.CountReached);
  Assert.IsTrue(Impact.TimeReached);
  Assert.AreEqual(2, Impact.Unexpanded);
  Assert.AreEqual(8000, Impact.TimeoutMs);
end;

procedure TLspImpactResponseTests.ImpactWithoutSymbol;
var
  Json: TJSONValue;
begin
  Assert.IsFalse(TLspSession.ImpactFromJson(nil).Found);
  Json := TJSONNull.Create;
  try
    Assert.IsFalse(TLspSession.ImpactFromJson(Json).Found);
  finally
    Json.Free;
  end;
end;

procedure TLspInitializeParamsTests.InlineValueRefsAreVariableLookups;
var
  Response: TJSONValue;
  Refs: TAtlasInlineValueRefs;
begin
  // #508: nur variableName; Text- und Ausdrucks-Werte wertet Atlas nicht aus (keine Nebenwirkungen).
  Response := TJSONObject.ParseJSONValue('[{"range":{"start":{"line":23,"character":2},"end":{"line":23,' +
    '"character":7}},"variableName":"Summe","caseSensitiveLookup":false,"atlasType":"Integer"},' +
    '{"range":{"start":{"line":24,"character":0}},"text":"x"},' +
    '{"range":{"start":{"line":24,"character":4}},"expression":"Liste.Count"},' +
    '{"range":{"start":{"line":24,"character":9}},"variableName":"Datum"}]');
  try
    Refs := TLspSession.InlineValueRefsOf(Response);
  finally
    Response.Free;
  end;
  Assert.AreEqual(2, Integer(Length(Refs)));
  Assert.AreEqual('Summe', Refs[0].Name);
  Assert.AreEqual(23, Refs[0].Line);
  Assert.AreEqual(2, Refs[0].Character);
  Assert.AreEqual('Integer', Refs[0].TypeName);
  Assert.AreEqual('Datum', Refs[1].Name);
  Assert.AreEqual('', Refs[1].TypeName);
  Assert.AreEqual(0, Integer(Length(TLspSession.InlineValueRefsOf(nil))), 'ohne Antwort');
end;

initialization
  TDUnitX.RegisterTestFixture(TLspInitializeParamsTests);
  TDUnitX.RegisterTestFixture(TLspImpactResponseTests);

end.
