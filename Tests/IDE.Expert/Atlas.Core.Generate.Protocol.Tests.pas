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
  System.Generics.Collections,
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
  mValue: TJSONValue;
  mItems: TJSONArray;
  mSelection: TAtlasGenerateSpot;
begin
  // [uri, position, endLine, name, argument]; Text über den Parser vergleichen (Escapes egal).
  mValue := Parse(TAtlasGenerateProtocol.RunArguments(Spot, 'ctor', 'FName, FAlter'));
  try
    Assert.IsTrue(mValue is TJSONArray);
    mItems := TJSONArray(mValue);
    Assert.AreEqual(5, Integer(mItems.Count));
    Assert.AreEqual('file:///C:/P/U.pas', mItems.Items[0].Value);
    Assert.AreEqual('{"line":4,"character":2}', mItems.Items[1].ToJSON);
    Assert.AreEqual('-1', mItems.Items[2].Value);
    Assert.AreEqual('ctor', mItems.Items[3].Value);
    Assert.AreEqual('FName, FAlter', mItems.Items[4].Value);
  finally
    mValue.Free;
  end;
  mValue := Parse(TAtlasGenerateProtocol.ChoicesArguments(Spot, 'ctor'));
  try
    Assert.AreEqual(4, Integer(TJSONArray(mValue).Count));
  finally
    mValue.Free;
  end;
  mValue := Parse(TAtlasGenerateProtocol.MenuArguments(Spot));
  try
    Assert.AreEqual(3, Integer(TJSONArray(mValue).Count));
  finally
    mValue.Free;
  end;
  mSelection := TAtlasGenerateSpot.Create('file:///C:/P/U.pas', 4, 2, 7);
  Assert.IsTrue(mSelection.HasSelection);
  Assert.IsFalse(Spot.HasSelection);
end;

procedure TAtlasGenerateProtocolTests.ParsesMenuOfServer;
var
  mValue: TJSONValue;
  mMenu: TAtlasGenerateServerMenu;
begin
  mValue := Parse('{"enabled":true,"places":["class","interface"],"commands":[' +
    '{"name":"ctor","summary":"Konstruktor","example":"/ctor FName","group":"generate","argument":"optional",' +
    '"choices":true,"multi":true,"separator":", "},' +
    '{"name":"try","summary":"try","example":"","group":"surround","argument":"none","choices":false,' +
    '"multi":false,"separator":""},' +
    '{"name":"","summary":"ohne Namen"},' +
    '{"name":"seltsam","group":"templates","argument":"required"}]}');
  try
    mMenu := TAtlasGenerateProtocol.ParseMenu(mValue);
  finally
    mValue.Free;
  end;
  Assert.IsTrue(mMenu.Enabled);
  Assert.AreEqual('class,interface', string.Join(',', mMenu.Places));
  Assert.AreEqual(3, Integer(Length(mMenu.Entries)), 'ohne Namen entfällt');
  Assert.AreEqual('slash:ctor', mMenu.Entries[0].Id);
  Assert.AreEqual(Ord(TAtlasGenerateGroup.Generate), Ord(mMenu.Entries[0].Group));
  Assert.AreEqual(Ord(TAtlasGenerateArgument.Optional), Ord(mMenu.Entries[0].Argument));
  Assert.IsTrue(mMenu.Entries[0].HasChoices);
  Assert.IsTrue(mMenu.Entries[0].Multi);
  Assert.AreEqual(', ', mMenu.Entries[0].Separator);
  Assert.AreEqual('/ctor FName', mMenu.Entries[0].Example);
  Assert.AreEqual('Konstruktor', mMenu.Entries[0].Caption);
  Assert.AreEqual(Ord(TAtlasGenerateGroup.Surround), Ord(mMenu.Entries[1].Group));
  Assert.AreEqual(' ', mMenu.Entries[1].Separator, 'leer: Leerzeichen');
  // Der Server liefert keine Vorlagen: unbekannte Gruppe wird Erzeugen.
  Assert.AreEqual(Ord(TAtlasGenerateGroup.Generate), Ord(mMenu.Entries[2].Group));
  Assert.AreEqual(Ord(TAtlasGenerateArgument.Required), Ord(mMenu.Entries[2].Argument));
  Assert.IsTrue(mMenu.Entries[2].NeedsStep);
end;

procedure TAtlasGenerateProtocolTests.MenuWithSlashCommandsOff;
var
  mValue: TJSONValue;
  mMenu: TAtlasGenerateServerMenu;
begin
  mValue := Parse('{"enabled":false,"places":["routine"],"commands":[]}');
  try
    mMenu := TAtlasGenerateProtocol.ParseMenu(mValue);
  finally
    mValue.Free;
  end;
  Assert.IsFalse(mMenu.Enabled);
  Assert.AreEqual('routine', string.Join(',', mMenu.Places), 'Orte gibt es trotzdem (für Vorlagen)');
  mMenu := TAtlasGenerateProtocol.ParseMenu(nil);
  Assert.IsFalse(mMenu.Enabled);
  Assert.AreEqual(0, Integer(Length(mMenu.Entries)));
end;

procedure TAtlasGenerateProtocolTests.ParsesChoices;
var
  mValue: TJSONValue;
begin
  mValue := Parse('["FName", 3, "FAlter"]');
  try
    Assert.AreEqual('FName,FAlter', string.Join(',', TAtlasGenerateProtocol.ParseChoices(mValue)));
  finally
    mValue.Free;
  end;
  Assert.AreEqual(0, Integer(Length(TAtlasGenerateProtocol.ParseChoices(nil))));
end;

procedure TAtlasGenerateProtocolTests.RunGivesEditsOrReason;
var
  mValue: TJSONValue;
  mEdits: TArray<TLspTextEdit>;
  mReason: string;
  mDone: Boolean;
begin
  mValue := Parse('{"edits":[{"range":{"start":{"line":3,"character":0},"end":{"line":3,"character":0}},' +
    '"newText":"x"}],"reason":""}');
  try
    mDone := TAtlasGenerateProtocol.ParseRun(mValue, mEdits, mReason);
  finally
    mValue.Free;
  end;
  Assert.IsTrue(mDone);
  Assert.AreEqual(1, Integer(Length(mEdits)));
  Assert.AreEqual('x', mEdits[0].NewText);
  Assert.AreEqual('', mReason);
  mValue := Parse('{"edits":[],"reason":"Keine Felder"}');
  try
    mDone := TAtlasGenerateProtocol.ParseRun(mValue, mEdits, mReason);
  finally
    mValue.Free;
  end;
  Assert.IsFalse(mDone);
  Assert.AreEqual('Keine Felder', mReason);
  mValue := Parse('{"edits":[]}');
  try
    mDone := TAtlasGenerateProtocol.ParseRun(mValue, mEdits, mReason);
  finally
    mValue.Free;
  end;
  Assert.IsFalse(mDone);
  Assert.AreNotEqual('', mReason, 'ohne Änderung ein Grund');
  Assert.IsFalse(TAtlasGenerateProtocol.ParseRun(nil, mEdits, mReason));
  Assert.AreNotEqual('', mReason);
end;

procedure TAtlasGenerateProtocolTests.SnippetsByContext;
var
  mSnippets: TAtlasSnippetList;
  mEntries: TArray<TAtlasGenerateEntry>;
begin
  SetLength(mSnippets, 5);
  mSnippets[0].Prefix := 'tryf';
  mSnippets[0].Name := 'try…finally';
  mSnippets[0].Context := 'statement';
  mSnippets[1].Prefix := 'cls';
  mSnippets[1].Context := 'declaration';
  mSnippets[2].Prefix := 'todo';
  mSnippets[2].Context := '';
  mSnippets[3].Prefix := 'nn';
  mSnippets[3].Postfix := True;
  // Dateivorlage (#759): nur für „Neu mit Atlas“, nie am Cursor.
  mSnippets[4].Prefix := 'newunit';
  mSnippets[4].FileKind := 'unit';
  // In einer Routine: Anweisungen und „überall“, keine Deklarationen, keine Postfix-Vorlagen.
  mEntries := TAtlasGenerateProtocol.FromSnippets(mSnippets, ['routine', 'implementation']);
  Assert.AreEqual(2, Integer(Length(mEntries)));
  Assert.AreEqual('snippet:tryf', mEntries[0].Id);
  Assert.AreEqual('try…finally', mEntries[0].Caption);
  Assert.AreEqual(0, mEntries[0].Source);
  Assert.AreEqual(Ord(TAtlasGenerateGroup.Templates), Ord(mEntries[0].Group));
  Assert.AreEqual('todo', mEntries[1].Caption, 'ohne Namen: Kürzel');
  Assert.AreEqual(2, mEntries[1].Source);
  // Auf Unit-Ebene: Deklarationen statt Anweisungen.
  mEntries := TAtlasGenerateProtocol.FromSnippets(mSnippets, ['implementation']);
  Assert.AreEqual('snippet:cls,snippet:todo', mEntries[0].Id + ',' + mEntries[1].Id);
  // Kommentar oder String (keine Orte): keine Vorlage.
  Assert.AreEqual(0, Integer(Length(TAtlasGenerateProtocol.FromSnippets(mSnippets, nil))));
end;

procedure TAtlasGenerateProtocolTests.ActionsOnlyRefactor;
var
  mActions: TArray<TLspCodeAction>;
  mEntries: TArray<TAtlasGenerateEntry>;
begin
  SetLength(mActions, 3);
  mActions[0].Title := 'Methode extrahieren';
  mActions[0].Kind := 'refactor.extract';
  mActions[1].Title := 'Schreibfehler beheben';
  mActions[1].Kind := 'quickfix';
  mActions[2].Title := 'Variable einführen';
  mActions[2].Kind := 'refactor.extract';
  mActions[2].Disabled := 'Keine Auswahl';
  mEntries := TAtlasGenerateProtocol.FromActions(mActions);
  Assert.AreEqual(1, Integer(Length(mEntries)));
  Assert.AreEqual('action:Methode extrahieren', mEntries[0].Id);
  Assert.AreEqual(0, mEntries[0].Source);
  Assert.AreEqual('', mEntries[0].CommandName, 'Code-Aktionen haben keinen /name');
  Assert.AreEqual(Ord(TAtlasGenerateGroup.Generate), Ord(mEntries[0].Group));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasGenerateProtocolTests);

end.
