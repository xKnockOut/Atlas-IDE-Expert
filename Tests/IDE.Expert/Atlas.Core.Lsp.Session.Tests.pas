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
    /// <summary>#1458: Sprache der Oberfläche als initializationOptions.locale und locale.</summary>
    [Test]
    procedure InitializeParamsCarriesLocale;
    /// <summary>#1458: Angaben nur mit Sprache, ohne Einstellungen.</summary>
    [Test]
    procedure InitializeOptionsForLocale;
    [Test]
    procedure ApplyEditAnswerOmitsEmptyReason;
    /// <summary>#621: data.tag einer CodeAction landet in Tag.</summary>
    [Test]
    procedure CodeActionCarriesTag;
    /// <summary>#2054: data.choices lesen; abgewählte Teile entfernen ihre Edits.</summary>
    [Test]
    procedure CodeActionChoicesFilterEdits;
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
    /// <summary>Antwort von atlas/affectedTests (#1353): Tests mit Gründen, alle nötig, ohne Objekt.</summary>
    [Test]
    procedure AffectedTestsFromJson;
    /// <summary>Vorfahr TLspSessionJson allein: ohne Objekt leere Ergebnisse; Einrückung für Formatieren.</summary>
    [Test]
    procedure JsonClassWithoutObject;
  end;

implementation

uses
  System.Generics.Collections,
  System.SysUtils,
  System.JSON,
  Atlas.Core.Projects.Contract,
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Lsp.Session.Json;

function Context(const AProject: string): TAtlasProjectContext;
begin
  Result := Default(TAtlasProjectContext);
  Result.Project := AProject;
  Result.Configuration := 'Debug';
  Result.Platform := 'Win64';
end;

procedure TLspInitializeParamsTests.InitializeParamsAnnouncesApplyEditOnlyWithHandler;
var
  mParams: TJSONObject;
begin
  mParams := TLspSession.InitializeParams(nil, '', nil, True);
  try
    Assert.IsTrue(mParams.GetValue<Boolean>('capabilities.workspace.applyEdit'));
  finally
    mParams.Free;
  end;
  mParams := TLspSession.InitializeParams(nil, '', nil, False);
  try
    Assert.IsFalse(mParams.GetValue<Boolean>('capabilities.workspace.applyEdit'));
    Assert.IsTrue(mParams.GetValue<Boolean>('capabilities.workspace.diagnostics.refreshSupport'));
  finally
    mParams.Free;
  end;
end;

procedure TLspInitializeParamsTests.InitializeParamsHasPlainTextHoverAndSnippets;
var
  mParams: TJSONObject;
  mFormats: TJSONArray;
begin
  mParams := TLspSession.InitializeParams(nil, '', nil, False);
  try
    mFormats := mParams.GetValue<TJSONArray>('capabilities.textDocument.hover.contentFormat');
    Assert.AreEqual(1, Integer(mFormats.Count));
    Assert.AreEqual('plaintext', mFormats.Items[0].Value);
    Assert.IsTrue(mParams.GetValue<Boolean>('capabilities.textDocument.completion.completionItem.snippetSupport'));
    Assert.IsFalse(mParams.GetValue<Boolean>('capabilities.textDocument.diagnostic.dynamicRegistration'));
    Assert.AreEqual('Atlas IDE Expert', mParams.GetValue<string>('clientInfo.name'));
    Assert.IsTrue(mParams.GetValue('processId') is TJSONNull);
  finally
    mParams.Free;
  end;
end;

procedure TLspInitializeParamsTests.InitializeParamsCarriesWorkspaceFolders;
var
  mParams: TJSONObject;
begin
  mParams := TLspSession.InitializeParams(['C:\A\Eins.dproj', 'C:\B\Zwei.dproj'], '', nil, False);
  try
    Assert.AreEqual(2, mParams.GetValue<TJSONArray>('workspaceFolders').Count);
    Assert.AreEqual('Eins', TJSONObject(mParams.GetValue<TJSONArray>('workspaceFolders').Items[0])
      .GetValue<string>('name'));
  finally
    mParams.Free;
  end;
  mParams := TLspSession.InitializeParams(nil, '', nil, False);
  try
    Assert.IsNull(mParams.GetValue('workspaceFolders'));
  finally
    mParams.Free;
  end;
end;

procedure TLspInitializeParamsTests.InitializeOptionsForLocale;
var
  mOptions: TLspInitializeOptions;
begin
  mOptions := TLspInitializeOptions.ForLocale('de');
  Assert.AreEqual('de', mOptions.Locale);
  Assert.AreEqual('', mOptions.Settings);
end;

procedure TLspInitializeParamsTests.InitializeParamsCarriesLocale;
var
  mParams: TJSONObject;
begin
  mParams := TLspSession.InitializeParams(nil, '', nil, False, 'en');
  try
    Assert.AreEqual('en', mParams.GetValue<string>('initializationOptions.locale'));
    Assert.AreEqual('en', mParams.GetValue<string>('locale'));
  finally
    mParams.Free;
  end;
  mParams := TLspSession.InitializeParams(nil, '', nil, False, '');
  try
    Assert.IsNull(mParams.GetValue('locale'));
    Assert.IsNull(mParams.GetValue('initializationOptions'));
  finally
    mParams.Free;
  end;
end;

procedure TLspInitializeParamsTests.InitializeParamsMergesSettingsAndContexts;
var
  mParams: TJSONObject;
begin
  mParams := TLspSession.InitializeParams(nil, '{"rules":{"x":"off"}}',
    [Context('C:\A\Eins.dproj'), Context('C:\B\Zwei.dproj')], False);
  try
    Assert.AreEqual('off', mParams.GetValue<string>('initializationOptions.settings.atlas.rules.x'));
    Assert.AreEqual(2, mParams.GetValue<TJSONArray>('initializationOptions.projectContexts').Count);
    Assert.AreEqual('Win64', TJSONObject(mParams.GetValue<TJSONArray>('initializationOptions.projectContexts')
      .Items[1]).GetValue<string>('platform'));
  finally
    mParams.Free;
  end;
  // Nur Kontexte: initializationOptions entsteht trotzdem.
  mParams := TLspSession.InitializeParams(nil, '', [Context('C:\A\Eins.dproj')], False);
  try
    Assert.AreEqual(1, mParams.GetValue<TJSONArray>('initializationOptions.projectContexts').Count);
    Assert.IsNull(mParams.GetValue<TJSONObject>('initializationOptions').GetValue('settings'));
  finally
    mParams.Free;
  end;
end;

procedure TLspInitializeParamsTests.InitializeParamsWithoutOptionsHasNoInitializationOptions;
var
  mParams: TJSONObject;
begin
  mParams := TLspSession.InitializeParams(['C:\A\Eins.dproj'], '', nil, True);
  try
    Assert.IsNull(mParams.GetValue('initializationOptions'));
  finally
    mParams.Free;
  end;
end;

procedure TLspInitializeParamsTests.ApplyEditAnswerOmitsEmptyReason;
var
  mAnswer: TJSONObject;
begin
  mAnswer := TLspSession.ApplyEditAnswer(True, '');
  try
    Assert.IsTrue(mAnswer.GetValue<Boolean>('applied'));
    Assert.IsNull(mAnswer.GetValue('failureReason'));
  finally
    mAnswer.Free;
  end;
  mAnswer := TLspSession.ApplyEditAnswer(False, 'Datei schreibgeschützt');
  try
    Assert.IsFalse(mAnswer.GetValue<Boolean>('applied'));
    Assert.AreEqual('Datei schreibgeschützt', mAnswer.GetValue<string>('failureReason'));
  finally
    mAnswer.Free;
  end;
end;

procedure TLspInitializeParamsTests.CodeActionCarriesTag;
var
  mValue: TJSONValue;
  mAction: TLspCodeAction;
begin
  mValue := TJSONObject.ParseJSONValue('{"title":"Vcl.Grids entfernen","kind":"quickfix","data":{"tag":"uses.remove"}}');
  try
    Assert.IsTrue(TLspCodeAction.FromJson(mValue, mAction));
    Assert.AreEqual('uses.remove', mAction.Tag);
  finally
    mValue.Free;
  end;
  mValue := TJSONObject.ParseJSONValue('{"title":"Ohne","kind":"quickfix"}');
  try
    Assert.IsTrue(TLspCodeAction.FromJson(mValue, mAction));
    Assert.AreEqual('', mAction.Tag);
  finally
    mValue.Free;
  end;
end;

procedure TLspInitializeParamsTests.CodeActionChoicesFilterEdits;
var
  mValue: TJSONValue;
  mAction, mChosen: TLspCodeAction;
begin
  mValue := TJSONObject.ParseJSONValue('{"title":"Methode extrahieren und 2 gleiche Stellen ersetzen",' +
    '"kind":"refactor.extract","edit":{"changes":{"file:///C:/P/U.pas":[' +
    '{"range":{"start":{"line":1,"character":0},"end":{"line":1,"character":0}},"newText":"neu"},' +
    '{"range":{"start":{"line":3,"character":0},"end":{"line":3,"character":4}},"newText":"A"},' +
    '{"range":{"start":{"line":5,"character":0},"end":{"line":5,"character":4}},"newText":"B"},' +
    '{"range":{"start":{"line":7,"character":0},"end":{"line":7,"character":4}},"newText":""}]}},' +
    '"data":{"choices":[{"title":"Zeile 4 in TA.X","range":{"start":{"line":3,"character":0}}},' +
    '{"title":"Zeile 6 in TA.Y","range":{"start":{"line":5,"character":0}}}],' +
    '"editChoices":[[],[0],[1],[0,1]]}}');
  try
    Assert.IsTrue(TLspCodeAction.FromJson(mValue, mAction));
  finally
    mValue.Free;
  end;
  Assert.AreEqual(2, Integer(Length(mAction.Choices)));
  Assert.AreEqual('Zeile 6 in TA.Y', mAction.Choices[1].Title);
  Assert.AreEqual(5, mAction.Choices[1].Line);
  mChosen := mAction.WithChoices([True, True]);
  Assert.AreEqual(4, Integer(Length(mChosen.Edit.Files[0].Edits)));
  mChosen := mAction.WithChoices([True, False]);
  Assert.AreEqual(2, Integer(Length(mChosen.Edit.Files[0].Edits)));
  Assert.AreEqual('A', mChosen.Edit.Files[0].Edits[1].NewText);
  // Das Original bleibt vollständig.
  Assert.AreEqual(4, Integer(Length(mAction.Edit.Files[0].Edits)));
end;

procedure TLspInitializeParamsTests.DocumentSymbolsAreFlattened;
var
  mResponse: TJSONValue;
  mSymbols: TArray<TAtlasSymbol>;
begin
  mResponse := TJSONObject.ParseJSONValue('[{"name":"TKunde","kind":5,"range":{"start":{"line":3,"character":2}},' +
    '"selectionRange":{"start":{"line":3,"character":4}},"children":[{"name":"Laden","kind":6,' +
    '"selectionRange":{"start":{"line":9,"character":14}}}]},{"name":"Hilfe","kind":12,' +
    '"range":{"start":{"line":20,"character":0}}}]');
  try
    mSymbols := TLspSession.SymbolsOfDocument(mResponse, 'C:\P\Kunden.pas');
  finally
    mResponse.Free;
  end;
  Assert.AreEqual(3, Integer(Length(mSymbols)));
  Assert.AreEqual('TKunde', mSymbols[0].Name);
  Assert.AreEqual(4, mSymbols[0].Character);
  Assert.AreEqual('Laden', mSymbols[1].Name);
  Assert.AreEqual('TKunde', mSymbols[1].Container);
  Assert.AreEqual(9, mSymbols[1].Line);
  Assert.AreEqual('C:\P\Kunden.pas', mSymbols[1].FileName);
  Assert.AreEqual('Hilfe', mSymbols[2].Name);
  Assert.AreEqual(20, mSymbols[2].Line);
  Assert.AreEqual('', mSymbols[2].Container);
  mResponse := TJSONObject.ParseJSONValue('[{"name":"Laden","kind":6,"containerName":"TKunde",' +
    '"location":{"uri":"file:///C:/P/Kunden.pas","range":{"start":{"line":7,"character":3}}}}]');
  try
    mSymbols := TLspSession.SymbolsOfDocument(mResponse, 'C:\P\Kunden.pas');
  finally
    mResponse.Free;
  end;
  Assert.AreEqual(1, Integer(Length(mSymbols)));
  Assert.AreEqual('TKunde', mSymbols[0].Container);
  Assert.AreEqual(7, mSymbols[0].Line);
  Assert.AreEqual(Integer(0), Integer(Length(TLspSession.SymbolsOfDocument(nil, 'x'))));
end;

{ TLspImpactResponseTests }

const
  cImpactJson =
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
  mJson: TJSONValue;
  mImpact: TAtlasImpact;
  mChildren: TArray<Integer>;
begin
  mJson := TJSONObject.ParseJSONValue(cImpactJson);
  try
    mImpact := TLspSession.ImpactFromJson(mJson);
  finally
    mJson.Free;
  end;
  Assert.IsTrue(mImpact.Found);
  Assert.AreEqual('Ziel', mImpact.Symbol.Name);
  Assert.AreEqual(2, mImpact.Depth);
  Assert.AreEqual(3, Integer(Length(mImpact.Places)));
  Assert.AreEqual(1, mImpact.LevelCount(1));
  Assert.AreEqual(2, mImpact.LevelCount(2));
  Assert.AreEqual(2, mImpact.CountFrom(2));
  mChildren := mImpact.Children(0);
  Assert.AreEqual(2, Integer(Length(mChildren)));
  Assert.AreEqual(1, mChildren[0]);
  Assert.AreEqual(1, Integer(Length(mImpact.Children(-1))));
  // Doppelklick: erste Verwendung der Ursache in der Stelle.
  Assert.AreEqual(2, mImpact.Places[0].UseCount);
  Assert.AreEqual(33, mImpact.Places[0].UseLine);
  Assert.AreEqual(2, mImpact.Places[0].UseCharacter);
  // Ohne Verwendung (Override) die Stelle selbst.
  Assert.AreEqual(11, mImpact.Places[2].UseLine);
  Assert.AreEqual(25, mImpact.Places[2].UseCharacter);
  Assert.IsTrue(mImpact.Places[1].Item.Confidence.Inferred);
  Assert.AreEqual(1, Integer(Length(mImpact.Places[1].Forms)));
  Assert.AreEqual('OnClick = Button1Click', mImpact.Places[1].Forms[0].Text);
  Assert.AreEqual(2, mImpact.Places[1].Forms[0].Line);
  Assert.AreEqual('Werkzeug.Tests.TWerkzeugTests.PrueftHilfe', mImpact.Places[2].Test);
  Assert.AreEqual(3, Integer(Length(mImpact.Tests)));
  Assert.AreEqual(11, mImpact.Tests[0].Line);
  // Ohne "run" läuft der Test unter seinem Namen.
  Assert.AreEqual('B.T.Ohne', mImpact.Tests[2].RunNames[0]);
  Assert.AreEqual(4, Integer(Length(mImpact.RunNames)));
  Assert.AreEqual('A.T.Fall.Zwei', mImpact.RunNames[2]);
  Assert.IsTrue(mImpact.DepthReached);
  Assert.IsFalse(mImpact.CountReached);
  Assert.IsTrue(mImpact.TimeReached);
  Assert.AreEqual(2, mImpact.Unexpanded);
  Assert.AreEqual(8000, mImpact.TimeoutMs);
end;

procedure TLspImpactResponseTests.ImpactWithoutSymbol;
var
  mJson: TJSONValue;
begin
  Assert.IsFalse(TLspSession.ImpactFromJson(nil).Found);
  mJson := TJSONNull.Create;
  try
    Assert.IsFalse(TLspSession.ImpactFromJson(mJson).Found);
  finally
    mJson.Free;
  end;
end;

procedure TLspImpactResponseTests.AffectedTestsFromJson;
var
  mJson: TJSONValue;
  mFound: TAtlasAffectedTests;
begin
  mJson := TJSONObject.ParseJSONValue('{"base":"main","depth":3,"all":false,"reason":"","run":["B.T.M",' +
    '"B.T.N"],"tests":[{"name":"B.T.M","unit":"B","fixture":"T","method":"M","run":["B.T.M"],' +
    '"uri":"file:///c%3A/p/B.pas","line":7,"reasons":[{"change":"TBaseline.Match","path":["TBaseline.Match",' +
    '"T.M"],"inferred":true}]},{"name":"B.T.N","uri":"file:///c%3A/p/B.pas","line":9,"reasons":[]}],' +
    '"changes":[{"kind":"symbol","name":"TBaseline.Match","place":"implementation","uri":"file:///c%3A/p/A.pas"}],' +
    '"skipped":[],"limits":{}}');
  try
    mFound := TLspSession.AffectedTestsFromJson(mJson);
  finally
    mJson.Free;
  end;
  Assert.AreEqual('main', mFound.Base);
  Assert.AreEqual(3, mFound.Depth);
  Assert.IsFalse(mFound.All);
  Assert.AreEqual(2, Integer(Length(mFound.Run)));
  Assert.AreEqual(2, Integer(Length(mFound.Tests)));
  Assert.AreEqual('B.T.M', mFound.Tests[0].Name);
  Assert.AreEqual(7, mFound.Tests[0].Line);
  Assert.AreEqual('TBaseline.Match → T.M (erschlossen)', mFound.Tests[0].Reasons[0]);
  // Ohne "run" läuft der Test unter seinem Namen.
  Assert.AreEqual('B.T.N', mFound.Tests[1].RunNames[0]);
  Assert.AreEqual('TBaseline.Match', mFound.Changes[0]);
  mJson := TJSONObject.ParseJSONValue('{"base":"BASE","all":true,"reason":"Testprogramm Tests.dpr geändert"}');
  try
    mFound := TLspSession.AffectedTestsFromJson(mJson);
  finally
    mJson.Free;
  end;
  Assert.IsTrue(mFound.All);
  Assert.AreEqual('Testprogramm Tests.dpr geändert', mFound.AllReason);
  Assert.AreEqual(0, Integer(Length(TLspSession.AffectedTestsFromJson(nil).Tests)));
end;

procedure TLspInitializeParamsTests.InlineValueRefsAreVariableLookups;
var
  mResponse: TJSONValue;
  mRefs: TAtlasInlineValueRefs;
begin
  // #508: nur variableName; Text- und Ausdrucks-Werte wertet Atlas nicht aus (keine Nebenwirkungen).
  mResponse := TJSONObject.ParseJSONValue('[{"range":{"start":{"line":23,"character":2},"end":{"line":23,' +
    '"character":7}},"variableName":"Summe","caseSensitiveLookup":false,"atlasType":"Integer"},' +
    '{"range":{"start":{"line":24,"character":0}},"text":"x"},' +
    '{"range":{"start":{"line":24,"character":4}},"expression":"Liste.Count"},' +
    '{"range":{"start":{"line":24,"character":9}},"variableName":"Datum"}]');
  try
    mRefs := TLspSession.InlineValueRefsOf(mResponse);
  finally
    mResponse.Free;
  end;
  Assert.AreEqual(2, Integer(Length(mRefs)));
  Assert.AreEqual('Summe', mRefs[0].Name);
  Assert.AreEqual(23, mRefs[0].Line);
  Assert.AreEqual(2, mRefs[0].Character);
  Assert.AreEqual('Integer', mRefs[0].TypeName);
  Assert.AreEqual('Datum', mRefs[1].Name);
  Assert.AreEqual('', mRefs[1].TypeName);
  Assert.AreEqual(0, Integer(Length(TLspSession.InlineValueRefsOf(nil))), 'ohne Antwort');
end;

procedure TLspImpactResponseTests.JsonClassWithoutObject;
var
  mOptions: TLspFormatOptions;
begin
  Assert.AreEqual(0, Integer(Length(TLspSessionJson.ImpactFromJson(nil).Places)));
  Assert.AreEqual(0, Integer(Length(TLspSessionJson.AffectedTestsFromJson(nil).Tests)));
  Assert.AreEqual(0, Integer(Length(TLspSessionJson.LocationsOf(nil))));
  mOptions := TLspFormatOptions.Create(4, False);
  Assert.AreEqual(4, mOptions.TabSize);
  Assert.IsFalse(mOptions.InsertSpaces);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspInitializeParamsTests);
  TDUnitX.RegisterTestFixture(TLspImpactResponseTests);

end.
