unit Atlas.Common.Mcp.RefactorTools.Tests;

// Tests für das MCP-Werkzeug refactor (#2150): Auflisten der Umbauten einer Stelle, Auswahl über kind, title und
// Argumente, Vorbereitung mit Mitgliedern, Vorschau und Schreiben samt neuer und gelöschter Dateien. Die Code-Aktionen
// und Befehle kommen von einem Server-Ersatz; die echten Umbauten prüft Shell.Mcp.RefactorHost.Tests.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpRefactorToolsTests = class
  public
    [Test]
    procedure ListsRefactoringsWithArgumentsAndBlocked;
    [Test]
    procedure ListsAsJson;
    /// <summary>Gleichartige Angebote (createOverload) wählt der Wert der Stelle aus args.</summary>
    [Test]
    procedure SlotArgumentChoosesOfferAndPreviews;
    [Test]
    procedure DryRunFalseWrites;
    [Test]
    procedure WrongArgumentsNameTheExpectedForm;
    [Test]
    procedure UnknownOrBlockedKindIsRefused;
    [Test]
    procedure PreparedRequestTakesMembersByName;
    [Test]
    procedure PreparedWithoutMembersListsCandidates;
    [Test]
    procedure EditActionKeepsChosenParts;
    [Test]
    procedure CommandErrorBecomesToolError;
    [Test]
    procedure DeletedFileIsShownAndRemoved;
    [Test]
    procedure KindsAndExpectedArguments;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Mcp.EditTools,
  Atlas.Common.Mcp.RefactorTools;

const
  cUnitText = 'unit A;' + sLineBreak + 'interface' + sLineBreak + 'implementation' + sLineBreak + 'end.';

type
  /// <summary>Ersatz des Servers: feste Code-Aktionen, Antworten je Befehl, Mitschnitt der Aufrufe.</summary>
  TFakeRefactorServer = class
  public
    Actions: string;
    Answers: TDictionary<string, string>;
    Calls: TList<string>;
    FailOn: string;
    constructor Create;
    destructor Destroy; override;
    function Source: TMcpRefactorSource;
  end;

  /// <summary>Dateien im Speicher; Created und Deleted zählen neue und gelöschte.</summary>
  TRefactorFiles = class
  public
    Files: TDictionary<string, string>;
    Created: TList<string>;
    Deleted: TList<string>;
    constructor Create;
    destructor Destroy; override;
    function Tools: TMcpEditTools;
  end;

{ TFakeRefactorServer }

constructor TFakeRefactorServer.Create;
begin
  inherited Create;
  Answers := TDictionary<string, string>.Create;
  Calls := TList<string>.Create;
end;

destructor TFakeRefactorServer.Destroy;
begin
  Calls.Free;
  Answers.Free;
  inherited Destroy;
end;

function TFakeRefactorServer.Source: TMcpRefactorSource;
var
  mServer: TFakeRefactorServer;
begin
  mServer := Self;
  Result := Default(TMcpRefactorSource);
  Result.Actions :=
    function(const AFileName: string; const ARange: TTextRange): TJSONArray
    begin
      Result := TJSONObject.ParseJSONValue(mServer.Actions) as TJSONArray;
    end;
  Result.Execute :=
    function(const ACommand: string; const AArguments: TJSONArray): TJSONValue
    var
      mAnswer: string;
    begin
      mServer.Calls.Add(ACommand + ' ' + AArguments.ToJSON([]));
      if ACommand = mServer.FailOn then
      begin
        raise EJsonRpcError.Create(-32602, 'kaputt');
      end;
      if not mServer.Answers.TryGetValue(ACommand, mAnswer) then
      begin
        mAnswer := '{}';
      end;
      Result := TJSONObject.ParseJSONValue(mAnswer);
    end;
end;

{ TRefactorFiles }

constructor TRefactorFiles.Create;
begin
  inherited Create;
  Files := TDictionary<string, string>.Create;
  Created := TList<string>.Create;
  Deleted := TList<string>.Create;
end;

destructor TRefactorFiles.Destroy;
begin
  Deleted.Free;
  Created.Free;
  Files.Free;
  inherited Destroy;
end;

function TRefactorFiles.Tools: TMcpEditTools;
var
  mFiles: TRefactorFiles;
begin
  mFiles := Self;
  Result := TMcpEditTools.Create(nil,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := mFiles.Files.TryGetValue(AFileName, AText);
    end,
    procedure(const AFileName, AText: string)
    begin
      mFiles.Files[AFileName] := AText;
    end,
    function: TArray<string>
    begin
      Result := nil;
    end,
    nil);
  Result.CreateFile :=
    procedure(const AFileName, AText: string)
    begin
      mFiles.Files.Add(AFileName, AText);
      mFiles.Created.Add(AFileName);
    end;
  Result.DeleteFile :=
    function(const AFileName: string; out AError: string): Boolean
    begin
      AError := '';
      Result := mFiles.Files.ContainsKey(AFileName);
      mFiles.Files.Remove(AFileName);
      mFiles.Deleted.Add(AFileName);
    end;
end;

{ Hilfen }

function FileName(const AName: string): string;
begin
  Result := TDocumentUris.ToPath(TDocumentUris.FromPath(IncludeTrailingPathDelimiter(GetCurrentDir) + AName));
end;

function Uri(const AName: string): string;
begin
  Result := TDocumentUris.FromPath(FileName(AName));
end;

/// <summary>Setzt $A (URI von A.pas), $B und $N (neue Datei) in AJson ein.</summary>
function Filled(const AJson: string): string;
begin
  Result := AJson.Replace('$A', Uri('A.pas')).Replace('$B', Uri('B.pas')).Replace('$N', Uri('N.pas'));
end;

/// <summary>Befehlsaktion des Plugins: atlas.AKey mit [uri, Stelle] und AExtra als weiteren Argumenten.</summary>
function CommandAction(const ATitle, AKey, AExtra: string): string;
begin
  Result := '{"title":"' + ATitle + '","kind":"refactor.rewrite","command":{"title":"' + ATitle +
    '","command":"atlas.' + AKey + '","arguments":["$A",{"line":1,"character":2}' + AExtra + ']}}';
end;

function StandardActions: string;
begin
  Result := Filled('[' +
    CommandAction('Überladung (weiterleitend)', 'createOverload', ',"forward"') + ',' +
    CommandAction('Überladung (Kopie)', 'createOverload', ',"copy"') + ',' +
    CommandAction('Interface herauslösen', 'extractInterface', '') + ',' +
    CommandAction('Klasse verschieben', 'moveClass', ',""') + ',' +
    CommandAction('Testunit anlegen', 'testUnit', '') + ',' +
    '{"title":"Sicher löschen","kind":"refactor","disabled":{"reason":"Nicht hier"},' +
    '"command":{"title":"Sicher löschen","command":"atlas.safeDelete","arguments":["$A",{"line":1,"character":2}]}},' +
    '{"title":"Doku-Kommentar","kind":"refactor.rewrite","data":{"tag":"docComment",' +
    '"choices":[{"title":"Kopf"},{"title":"Rumpf"}],"editChoices":[[0],[1]]},' +
    '"edit":{"changes":{"$A":[{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":0}},' +
    '"newText":"// Kopf\r\n"},{"range":{"start":{"line":3,"character":0},"end":{"line":3,"character":0}},' +
    '"newText":"// Rumpf\r\n"}]}}}' +
    ']');
end;

/// <summary>Antwort eines Befehls: A.pas Zeile 2 durch ANewText ersetzen.</summary>
function EditAnswer(const ANewText: string): string;
begin
  Result := Filled('{"edit":{"changes":{"$A":[{"range":{"start":{"line":1,"character":0},' +
    '"end":{"line":1,"character":9}},"newText":"' + ANewText + '"}]}},"warnings":["Bitte prüfen"]}');
end;

function Request(const AKind, AArgs: string; ADryRun: Boolean = True): TMcpRefactorRequest;
begin
  Result := Default(TMcpRefactorRequest);
  Result.FileName := FileName('A.pas');
  Result.Range := TTextRange.Create(1, 2, 1, 2);
  Result.Kind := AKind;
  Result.DryRun := ADryRun;
  if AArgs <> '' then
  begin
    Result.Args := TJSONObject.ParseJSONValue(AArgs) as TJSONObject;
  end;
end;

/// <summary>Führt refactor mit AServer über AFiles aus; gibt ARequest.Args frei.</summary>
function RunRefactor(AServer: TFakeRefactorServer; AFiles: TRefactorFiles; const ARequest: TMcpRefactorRequest): string;
var
  mTools: TMcpEditTools;
begin
  mTools := AFiles.Tools;
  try
    Result := TMcpRefactorTools.Run(mTools, AServer.Source, ARequest);
  finally
    mTools.Free;
    ARequest.Args.Free;
  end;
end;

/// <summary>Meldung des Werkzeugfehlers von refactor; scheitert der Test, wenn kein Fehler kommt.</summary>
function RefactorError(AServer: TFakeRefactorServer; AFiles: TRefactorFiles;
  const ARequest: TMcpRefactorRequest): string;
begin
  Result := '';
  try
    RunRefactor(AServer, AFiles, ARequest);
    Assert.Fail('refactor hätte scheitern müssen');
  except
    on E: EMcpToolError do
      Result := E.Message;
  end;
end;

function NewServer: TFakeRefactorServer;
begin
  Result := TFakeRefactorServer.Create;
  Result.Actions := StandardActions;
end;

function NewFiles: TRefactorFiles;
begin
  Result := TRefactorFiles.Create;
  Result.Files.Add(FileName('A.pas'), cUnitText);
end;

{ TMcpRefactorToolsTests }

procedure TMcpRefactorToolsTests.ListsRefactoringsWithArgumentsAndBlocked;
var
  mServer: TFakeRefactorServer;
  mFiles: TRefactorFiles;
  mText: string;
begin
  mServer := NewServer;
  mFiles := NewFiles;
  try
    mText := RunRefactor(mServer, mFiles, Request('', ''));
    Assert.Contains(mText, '- createOverload – Überladung (Kopie) – args: kind: string = "copy"');
    Assert.Contains(mText, 'extractInterface – Interface herauslösen');
    Assert.Contains(mText, 'members: [id | name, …]');
    Assert.Contains(mText, 'safeDelete – Sicher löschen – gesperrt: Nicht hier');
    Assert.Contains(mText, 'docComment – Doku-Kommentar');
    Assert.Contains(mText, '1 = Kopf');
    Assert.DoesNotContain(mText, 'Testunit', 'Befehl nur des Plugins');
    Assert.AreEqual(0, Integer(mServer.Calls.Count), 'Auflisten führt nichts aus');
  finally
    mFiles.Free;
    mServer.Free;
  end;
end;

procedure TMcpRefactorToolsTests.ListsAsJson;
var
  mServer: TFakeRefactorServer;
  mFiles: TRefactorFiles;
  mRequest: TMcpRefactorRequest;
  mJson: TJSONObject;
  mList: TJSONArray;
begin
  mServer := NewServer;
  mFiles := NewFiles;
  try
    mRequest := Request('', '');
    mRequest.Json := True;
    mJson := TJSONObject.ParseJSONValue(RunRefactor(mServer, mFiles, mRequest)) as TJSONObject;
    try
      mList := mJson.GetValue<TJSONArray>('refactorings');
      Assert.AreEqual(6, Integer(mList.Count));
      Assert.AreEqual('createOverload', mList.Items[0].GetValue<string>('kind'));
      Assert.AreEqual('Nicht hier', mList.Items[4].GetValue<string>('disabled'));
      Assert.AreEqual(2, Integer(mJson.GetValue<Integer>('line')), 'Zeile ab 1');
    finally
      mJson.Free;
    end;
  finally
    mFiles.Free;
    mServer.Free;
  end;
end;

procedure TMcpRefactorToolsTests.SlotArgumentChoosesOfferAndPreviews;
var
  mServer: TFakeRefactorServer;
  mFiles: TRefactorFiles;
  mText: string;
begin
  mServer := NewServer;
  mFiles := NewFiles;
  try
    mServer.Answers.Add('atlas.server.createOverload', EditAnswer('interface // Kopie'));
    mText := RunRefactor(mServer, mFiles, Request('createOverload', '{"kind":"copy"}'));
    Assert.AreEqual(1, Integer(mServer.Calls.Count));
    Assert.StartsWith('atlas.server.createOverload [', mServer.Calls[0]);
    Assert.Contains(mServer.Calls[0], ',"copy"]');
    Assert.Contains(mText, 'Überladung (Kopie)');
    Assert.Contains(mText, '+ interface // Kopie');
    Assert.Contains(mText, 'Bitte prüfen', 'Hinweise des Umbaus');
    Assert.AreEqual(cUnitText, mFiles.Files[FileName('A.pas')], 'Vorschau schreibt nichts');
    mText := RefactorError(mServer, mFiles, Request('createOverload', ''));
    Assert.Contains(mText, 'Überladung (weiterleitend)', 'ohne Wert: mehrdeutig, Titel zur Wahl');
  finally
    mFiles.Free;
    mServer.Free;
  end;
end;

procedure TMcpRefactorToolsTests.DryRunFalseWrites;
var
  mServer: TFakeRefactorServer;
  mFiles: TRefactorFiles;
  mRequest: TMcpRefactorRequest;
begin
  mServer := NewServer;
  mFiles := NewFiles;
  try
    mServer.Answers.Add('atlas.server.createOverload', EditAnswer('interface // neu'));
    mRequest := Request('createOverload', '', False);
    mRequest.Title := 'Überladung (weiterleitend)';
    RunRefactor(mServer, mFiles, mRequest);
    Assert.Contains(mServer.Calls[0], ',"forward"]');
    Assert.Contains(mFiles.Files[FileName('A.pas')], 'interface // neu');
  finally
    mFiles.Free;
    mServer.Free;
  end;
end;

procedure TMcpRefactorToolsTests.WrongArgumentsNameTheExpectedForm;
var
  mServer: TFakeRefactorServer;
  mFiles: TRefactorFiles;
  mText: string;
begin
  mServer := NewServer;
  mFiles := NewFiles;
  try
    mText := RefactorError(mServer, mFiles, Request('moveClass', '{"name":5}'));
    Assert.Contains(mText, 'Argument "name" muss string sein');
    Assert.Contains(mText, 'Erwartet: name: string');
    mText := RefactorError(mServer, mFiles, Request('moveClass', '{"ziel":"X"}'));
    Assert.Contains(mText, 'Unbekanntes Argument "ziel"');
    mText := RefactorError(mServer, mFiles, Request('extractInterface', '{"members":"Suchen"}'));
    Assert.Contains(mText, 'members: [id | name, …]');
    Assert.AreEqual(0, Integer(mServer.Calls.Count), 'falsche Argumente führen nichts aus');
  finally
    mFiles.Free;
    mServer.Free;
  end;
end;

procedure TMcpRefactorToolsTests.UnknownOrBlockedKindIsRefused;
var
  mServer: TFakeRefactorServer;
  mFiles: TRefactorFiles;
  mText: string;
begin
  mServer := NewServer;
  mFiles := NewFiles;
  try
    mText := RefactorError(mServer, mFiles, Request('inlineAccessor', ''));
    Assert.Contains(mText, 'Kein Umbau "inlineAccessor"');
    Assert.Contains(mText, 'extractInterface', 'die Liste der Stelle hilft weiter');
    mText := RefactorError(mServer, mFiles, Request('safeDelete', ''));
    Assert.Contains(mText, 'gesperrt: Nicht hier');
    Assert.AreEqual(0, Integer(mServer.Calls.Count));
  finally
    mFiles.Free;
    mServer.Free;
  end;
end;

procedure TMcpRefactorToolsTests.PreparedRequestTakesMembersByName;
var
  mServer: TFakeRefactorServer;
  mFiles: TRefactorFiles;
  mText: string;
begin
  mServer := NewServer;
  mFiles := NewFiles;
  try
    mServer.Answers.Add('atlas.server.extractInterface.prepare', '{"name":"IKunde","unit":"Kunde.Intf",' +
      '"candidates":[{"id":1,"name":"Suchen","checked":true},{"id":2,"name":"Anmelden","checked":false}]}');
    mServer.Answers.Add('atlas.server.extractInterface', Filled('{"edit":{"documentChanges":[' +
      '{"kind":"create","uri":"$N","options":{"ignoreIfExists":false}},' +
      '{"textDocument":{"uri":"$N","version":null},"edits":[{"range":{"start":{"line":0,"character":0},' +
      '"end":{"line":0,"character":0}},"newText":"unit N;"}]},' +
      '{"textDocument":{"uri":"$A","version":null},"edits":[{"range":{"start":{"line":1,"character":0},' +
      '"end":{"line":1,"character":9}},"newText":"interface uses N;"}]}]}}'));
    mText := RunRefactor(mServer, mFiles, Request('extractInterface', '{"members":["Anmelden"]}'));
    Assert.AreEqual(2, Integer(mServer.Calls.Count), 'Vorbereitung und Ausführung');
    Assert.StartsWith('atlas.server.extractInterface.prepare [', mServer.Calls[0]);
    Assert.Contains(mServer.Calls[1], '{"name":"IKunde","unit":"Kunde.Intf","members":[2]}');
    Assert.Contains(mText, '2 Anmelden', 'Mitglieder der Vorbereitung im Bericht');
    Assert.Contains(mText, 'neue Datei');
    Assert.Contains(mText, '+ unit N;');
    Assert.AreEqual(0, Integer(mFiles.Created.Count), 'Vorschau legt nichts an');
    RunRefactor(mServer, mFiles, Request('extractInterface', '{"name":"IAnders","members":[1]}', False));
    Assert.Contains(mServer.Calls[3], '{"name":"IAnders","unit":"Kunde.Intf","members":[1]}');
    Assert.AreEqual(1, Integer(mFiles.Created.Count));
    Assert.AreEqual('unit N;', mFiles.Files[FileName('N.pas')]);
    Assert.Contains(mFiles.Files[FileName('A.pas')], 'interface uses N;');
  finally
    mFiles.Free;
    mServer.Free;
  end;
end;

procedure TMcpRefactorToolsTests.PreparedWithoutMembersListsCandidates;
var
  mServer: TFakeRefactorServer;
  mFiles: TRefactorFiles;
  mText: string;
begin
  mServer := NewServer;
  mFiles := NewFiles;
  try
    mServer.Answers.Add('atlas.server.extractInterface.prepare', '{"name":"IKunde","candidates":[' +
      '{"id":1,"name":"Suchen","checked":false},{"id":2,"name":"Anmelden","enabled":false,"reason":"privat"}]}');
    mText := RefactorError(mServer, mFiles, Request('extractInterface', ''));
    Assert.Contains(mText, 'Keine Mitglieder gewählt');
    Assert.Contains(mText, '- 1 Suchen');
    Assert.Contains(mText, '- 2 Anmelden – gesperrt: privat');
    mText := RefactorError(mServer, mFiles, Request('extractInterface', '{"members":["Fehlt"]}'));
    Assert.Contains(mText, 'Kein Mitglied "Fehlt"');
    Assert.AreEqual(2, Integer(mServer.Calls.Count), 'nur die Vorbereitungen');
  finally
    mFiles.Free;
    mServer.Free;
  end;
end;

procedure TMcpRefactorToolsTests.EditActionKeepsChosenParts;
var
  mServer: TFakeRefactorServer;
  mFiles: TRefactorFiles;
  mText: string;
begin
  mServer := NewServer;
  mFiles := NewFiles;
  try
    RunRefactor(mServer, mFiles, Request('docComment', '{"choices":[2]}', False));
    mText := mFiles.Files[FileName('A.pas')];
    Assert.Contains(mText, '// Rumpf');
    Assert.DoesNotContain(mText, '// Kopf', 'Teil 1 abgewählt');
    mText := RefactorError(mServer, mFiles, Request('docComment', '{"name":"x"}'));
    Assert.Contains(mText, 'Unbekanntes Argument "name"');
    Assert.AreEqual(0, Integer(mServer.Calls.Count), 'Aktion mit Edits braucht keinen Befehl');
  finally
    mFiles.Free;
    mServer.Free;
  end;
end;

procedure TMcpRefactorToolsTests.CommandErrorBecomesToolError;
var
  mServer: TFakeRefactorServer;
  mFiles: TRefactorFiles;
  mText: string;
begin
  mServer := NewServer;
  mFiles := NewFiles;
  try
    mServer.FailOn := 'atlas.server.moveClass';
    mText := RefactorError(mServer, mFiles, Request('moveClass', '{"name":"Ziel"}'));
    Assert.Contains(mText, 'Klasse verschieben geht nicht: kaputt');
    Assert.Contains(mText, 'args: name: string');
    Assert.Contains(mServer.Calls[0], ',"Ziel"]', 'name ersetzt die Stelle 2');
    mServer.FailOn := '';
    mText := RefactorError(mServer, mFiles, Request('moveClass', ''));
    Assert.Contains(mText, 'liefert keine Änderungen');
  finally
    mFiles.Free;
    mServer.Free;
  end;
end;

procedure TMcpRefactorToolsTests.DeletedFileIsShownAndRemoved;
var
  mServer: TFakeRefactorServer;
  mFiles: TRefactorFiles;
  mText: string;
begin
  mServer := NewServer;
  mFiles := NewFiles;
  try
    mFiles.Files.Add(FileName('B.pas'), 'unit B;');
    mServer.Answers.Add('atlas.server.moveClass', Filled('{"edit":{"documentChanges":[' +
      '{"textDocument":{"uri":"$A","version":null},"edits":[{"range":{"start":{"line":1,"character":0},' +
      '"end":{"line":1,"character":9}},"newText":"interface uses B;"}]},' +
      '{"kind":"delete","uri":"$B","options":{"ignoreIfNotExists":true}}]}}'));
    mText := RunRefactor(mServer, mFiles, Request('moveClass', ''));
    Assert.Contains(mText, 'wird gelöscht');
    Assert.AreEqual(0, Integer(mFiles.Deleted.Count), 'Vorschau löscht nichts');
    RunRefactor(mServer, mFiles, Request('moveClass', '', False));
    Assert.AreEqual(1, Integer(mFiles.Deleted.Count));
    Assert.IsFalse(mFiles.Files.ContainsKey(FileName('B.pas')));
    Assert.Contains(mFiles.Files[FileName('A.pas')], 'interface uses B;');
    mServer.Answers['atlas.server.moveClass'] := Filled('{"edit":{"documentChanges":[' +
      '{"kind":"rename","oldUri":"$A","newUri":"$B"}]}}');
    mText := RefactorError(mServer, mFiles, Request('moveClass', ''));
    Assert.Contains(mText, 'Umbenennen von Dateien');
  finally
    mFiles.Free;
    mServer.Free;
  end;
end;

procedure TMcpRefactorToolsTests.KindsAndExpectedArguments;
var
  mKinds: TArray<string>;
begin
  mKinds := TMcpRefactorTools.CommandKinds;
  Assert.AreEqual(17, Integer(Length(mKinds)));
  Assert.AreEqual('promoteVariable', mKinds[0]);
  Assert.AreEqual('name: string, scope: string', TMcpRefactorTools.ExpectedArguments('typeAlias'));
  Assert.AreEqual('', TMcpRefactorTools.ExpectedArguments('inlineTypeAlias'));
  Assert.AreEqual('', TMcpRefactorTools.ExpectedArguments('disableWarning'));
  Assert.Contains(TMcpRefactorTools.ExpectedArguments('changeSignature'),
    'parameters: [{origin?, name, type, modifier?, value?}, …]');
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpRefactorToolsTests);

end.
