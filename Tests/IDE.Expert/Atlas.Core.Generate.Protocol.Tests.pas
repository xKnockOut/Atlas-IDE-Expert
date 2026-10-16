unit Atlas.Core.Generate.Protocol.Tests;

// Tests für das Erzeugen-Menü (#719), Austausch mit dem Server: Argumente
// der Befehle, Antworten von slashMenu, slashChoices und slashRun sowie die
// Einträge aus Code-Vorlagen (Kontext) und Code-Aktionen (nur refactor).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasGenerateProtocolTests = class
  public
    [Test]
    procedure ArgumentsAsJsonArray;
    [Test]
    procedure ParsesMenuOfServer;
    [Test]
    procedure MenuWithSlashCommandsOff;
    [Test]
    procedure ParsesChoices;
    [Test]
    procedure RunGivesEditsOrReason;
    [Test]
    procedure SnippetsByContext;
    [Test]
    procedure ActionsOnlyRefactor;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Completion.Snippets,
  Atlas.Core.Generate.Menu,
  Atlas.Core.Generate.Protocol;

function Spot: TAtlasGenerateSpot;
begin
  Result := TAtlasGenerateSpot.Create('file:///C:/P/U.pas', 4, 2, -1);
end;

function Parse(const AText: string): TJSONValue;
begin
  Result := TJSONObject.ParseJSONValue(AText);
end;

procedure TAtlasGenerateProtocolTests.ArgumentsAsJsonArray;
var
  Value: TJSONValue;
  Items: TJSONArray;
  Selection: TAtlasGenerateSpot;
begin
  // [uri, position, endLine, name, argument]; Text über den Parser vergleichen (Escapes egal).
  Value := Parse(TAtlasGenerateProtocol.RunArguments(Spot, 'ctor', 'FName, FAlter'));
  try
    Assert.IsTrue(Value is TJSONArray);
    Items := TJSONArray(Value);
    Assert.AreEqual(5, Items.Count);
    Assert.AreEqual('file:///C:/P/U.pas', Items.Items[0].Value);
    Assert.AreEqual('{"line":4,"character":2}', Items.Items[1].ToJSON);
    Assert.AreEqual('-1', Items.Items[2].Value);
    Assert.AreEqual('ctor', Items.Items[3].Value);
    Assert.AreEqual('FName, FAlter', Items.Items[4].Value);
  finally
    Value.Free;
  end;
  Value := Parse(TAtlasGenerateProtocol.ChoicesArguments(Spot, 'ctor'));
  try
    Assert.AreEqual(4, TJSONArray(Value).Count);
  finally
    Value.Free;
  end;
  Value := Parse(TAtlasGenerateProtocol.MenuArguments(Spot));
  try
    Assert.AreEqual(3, TJSONArray(Value).Count);
  finally
    Value.Free;
  end;
  Selection := TAtlasGenerateSpot.Create('file:///C:/P/U.pas', 4, 2, 7);
  Assert.IsTrue(Selection.HasSelection);
  Assert.IsFalse(Spot.HasSelection);
end;

procedure TAtlasGenerateProtocolTests.ParsesMenuOfServer;
var
  Value: TJSONValue;
  Menu: TAtlasGenerateServerMenu;
begin
  Value := Parse('{"enabled":true,"places":["class","interface"],"commands":[' +
    '{"name":"ctor","summary":"Konstruktor","example":"/ctor FName","group":"generate","argument":"optional",' +
    '"choices":true,"multi":true,"separator":", "},' +
    '{"name":"try","summary":"try","example":"","group":"surround","argument":"none","choices":false,' +
    '"multi":false,"separator":""},' +
    '{"name":"","summary":"ohne Namen"},' +
    '{"name":"seltsam","group":"templates","argument":"required"}]}');
  try
    Menu := TAtlasGenerateProtocol.ParseMenu(Value);
  finally
    Value.Free;
  end;
  Assert.IsTrue(Menu.Enabled);
  Assert.AreEqual('class,interface', string.Join(',', Menu.Places));
  Assert.AreEqual(3, Integer(Length(Menu.Entries)), 'ohne Namen entfällt');
  Assert.AreEqual('slash:ctor', Menu.Entries[0].Id);
  Assert.AreEqual(Ord(TAtlasGenerateGroup.Generate), Ord(Menu.Entries[0].Group));
  Assert.AreEqual(Ord(TAtlasGenerateArgument.Optional), Ord(Menu.Entries[0].Argument));
  Assert.IsTrue(Menu.Entries[0].HasChoices);
  Assert.IsTrue(Menu.Entries[0].Multi);
  Assert.AreEqual(', ', Menu.Entries[0].Separator);
  Assert.AreEqual('/ctor FName', Menu.Entries[0].Example);
  Assert.AreEqual('Konstruktor', Menu.Entries[0].Caption);
  Assert.AreEqual(Ord(TAtlasGenerateGroup.Surround), Ord(Menu.Entries[1].Group));
  Assert.AreEqual(' ', Menu.Entries[1].Separator, 'leer: Leerzeichen');
  // Der Server liefert keine Vorlagen: unbekannte Gruppe wird Erzeugen.
  Assert.AreEqual(Ord(TAtlasGenerateGroup.Generate), Ord(Menu.Entries[2].Group));
  Assert.AreEqual(Ord(TAtlasGenerateArgument.Required), Ord(Menu.Entries[2].Argument));
  Assert.IsTrue(Menu.Entries[2].NeedsStep);
end;

procedure TAtlasGenerateProtocolTests.MenuWithSlashCommandsOff;
var
  Value: TJSONValue;
  Menu: TAtlasGenerateServerMenu;
begin
  Value := Parse('{"enabled":false,"places":["routine"],"commands":[]}');
  try
    Menu := TAtlasGenerateProtocol.ParseMenu(Value);
  finally
    Value.Free;
  end;
  Assert.IsFalse(Menu.Enabled);
  Assert.AreEqual('routine', string.Join(',', Menu.Places), 'Orte gibt es trotzdem (für Vorlagen)');
  Menu := TAtlasGenerateProtocol.ParseMenu(nil);
  Assert.IsFalse(Menu.Enabled);
  Assert.AreEqual(0, Integer(Length(Menu.Entries)));
end;

procedure TAtlasGenerateProtocolTests.ParsesChoices;
var
  Value: TJSONValue;
begin
  Value := Parse('["FName", 3, "FAlter"]');
  try
    Assert.AreEqual('FName,FAlter', string.Join(',', TAtlasGenerateProtocol.ParseChoices(Value)));
  finally
    Value.Free;
  end;
  Assert.AreEqual(0, Integer(Length(TAtlasGenerateProtocol.ParseChoices(nil))));
end;

procedure TAtlasGenerateProtocolTests.RunGivesEditsOrReason;
var
  Value: TJSONValue;
  Edits: TArray<TLspTextEdit>;
  Reason: string;
  Done: Boolean;
begin
  Value := Parse('{"edits":[{"range":{"start":{"line":3,"character":0},"end":{"line":3,"character":0}},' +
    '"newText":"x"}],"reason":""}');
  try
    Done := TAtlasGenerateProtocol.ParseRun(Value, Edits, Reason);
  finally
    Value.Free;
  end;
  Assert.IsTrue(Done);
  Assert.AreEqual(1, Integer(Length(Edits)));
  Assert.AreEqual('x', Edits[0].NewText);
  Assert.AreEqual('', Reason);
  Value := Parse('{"edits":[],"reason":"Keine Felder"}');
  try
    Done := TAtlasGenerateProtocol.ParseRun(Value, Edits, Reason);
  finally
    Value.Free;
  end;
  Assert.IsFalse(Done);
  Assert.AreEqual('Keine Felder', Reason);
  Value := Parse('{"edits":[]}');
  try
    Done := TAtlasGenerateProtocol.ParseRun(Value, Edits, Reason);
  finally
    Value.Free;
  end;
  Assert.IsFalse(Done);
  Assert.AreNotEqual('', Reason, 'ohne Änderung ein Grund');
  Assert.IsFalse(TAtlasGenerateProtocol.ParseRun(nil, Edits, Reason));
  Assert.AreNotEqual('', Reason);
end;

procedure TAtlasGenerateProtocolTests.SnippetsByContext;
var
  Snippets: TAtlasSnippetList;
  Entries: TArray<TAtlasGenerateEntry>;
begin
  SetLength(Snippets, 5);
  Snippets[0].Prefix := 'tryf';
  Snippets[0].Name := 'try…finally';
  Snippets[0].Context := 'statement';
  Snippets[1].Prefix := 'cls';
  Snippets[1].Context := 'declaration';
  Snippets[2].Prefix := 'todo';
  Snippets[2].Context := '';
  Snippets[3].Prefix := 'nn';
  Snippets[3].Postfix := True;
  // Dateivorlage (#759): nur für „Neu mit Atlas“, nie am Cursor.
  Snippets[4].Prefix := 'newunit';
  Snippets[4].FileKind := 'unit';
  // In einer Routine: Anweisungen und „überall“, keine Deklarationen, keine Postfix-Vorlagen.
  Entries := TAtlasGenerateProtocol.FromSnippets(Snippets, ['routine', 'implementation']);
  Assert.AreEqual(2, Integer(Length(Entries)));
  Assert.AreEqual('snippet:tryf', Entries[0].Id);
  Assert.AreEqual('try…finally', Entries[0].Caption);
  Assert.AreEqual(0, Entries[0].Source);
  Assert.AreEqual(Ord(TAtlasGenerateGroup.Templates), Ord(Entries[0].Group));
  Assert.AreEqual('todo', Entries[1].Caption, 'ohne Namen: Kürzel');
  Assert.AreEqual(2, Entries[1].Source);
  // Auf Unit-Ebene: Deklarationen statt Anweisungen.
  Entries := TAtlasGenerateProtocol.FromSnippets(Snippets, ['implementation']);
  Assert.AreEqual('snippet:cls,snippet:todo', Entries[0].Id + ',' + Entries[1].Id);
  // Kommentar oder String (keine Orte): keine Vorlage.
  Assert.AreEqual(0, Integer(Length(TAtlasGenerateProtocol.FromSnippets(Snippets, nil))));
end;

procedure TAtlasGenerateProtocolTests.ActionsOnlyRefactor;
var
  Actions: TArray<TLspCodeAction>;
  Entries: TArray<TAtlasGenerateEntry>;
begin
  SetLength(Actions, 3);
  Actions[0].Title := 'Methode extrahieren';
  Actions[0].Kind := 'refactor.extract';
  Actions[1].Title := 'Schreibfehler beheben';
  Actions[1].Kind := 'quickfix';
  Actions[2].Title := 'Variable einführen';
  Actions[2].Kind := 'refactor.extract';
  Actions[2].Disabled := 'Keine Auswahl';
  Entries := TAtlasGenerateProtocol.FromActions(Actions);
  Assert.AreEqual(1, Integer(Length(Entries)));
  Assert.AreEqual('action:Methode extrahieren', Entries[0].Id);
  Assert.AreEqual(0, Entries[0].Source);
  Assert.AreEqual('', Entries[0].CommandName, 'Code-Aktionen haben keinen /name');
  Assert.AreEqual(Ord(TAtlasGenerateGroup.Generate), Ord(Entries[0].Group));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasGenerateProtocolTests);

end.
