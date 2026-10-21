unit Atlas.UI.Diagnostics.ProcessesDialog.Tests;

// Fenster „Prozesse am Projekt“ (#62): Kopf, Cache, Sperre mit Marke, Liste,
// Fuß, ungespeicherte Stände und Protokoll; späte Antworten nach dem Schließen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasProcessesDialogTests = class
  public
    /// <summary>Erstgebrauch der VCL (Fenster, Listenansicht, Memo) vor der Leckmessung.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure ShowsWorkspaceProcessesAndLog;
    [Test]
    procedure NoServerAndNoProject;
    [Test]
    procedure DirtyFilesNameMcpOnlyWithMcpProcess;
    [Test]
    procedure RefreshAsksAndCopyGivesMarkdown;
    [Test]
    procedure LateAnswerAfterCloseIsIgnored;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.UI.Strings,
  Atlas.UI.Diagnostics.ProcessesDialog;

const
  Answer =
    '{"workspaces":[{"name":"Gruppe","project":"","cache":"3f9a\\Gruppe.idx","format":17,"saved":"vor 12 s",' +
    '"units":412,"lockHolder":"LSP · Atlas IDE Expert (pid 4711)","builtOnce":true,"processes":[' +
    '{"pid":4711,"kind":"LSP","client":"Atlas IDE Expert","state":"baut Index","writer":true,"own":true},' +
    '{"pid":5120,"kind":"MCP","client":"Claude Code","state":"liest Cache","writer":false,"own":false}],' +
    '"events":[{"time":"10:00:01","text":"LSP 4711: Cache-Sperre erhalten"}]}],"markdown":"## Prozesse"}';
  LspOnly =
    '{"workspaces":[{"name":"Gruppe","cache":"a\\b.idx","format":17,"saved":"vor 1 s","units":3,' +
    '"lockHolder":"","builtOnce":false,"processes":[{"pid":1,"kind":"LSP","client":"","state":"bereit",' +
    '"writer":false,"own":true}],"events":[]}],"markdown":"## Prozesse"}';

function Parse(const AText: string): TJSONValue;
begin
  Result := TJSONObject.ParseJSONValue(AText);
end;

procedure TAtlasProcessesDialogTests.WarmUpFirstUse;
begin
  ShowsWorkspaceProcessesAndLog;
  RefreshAsksAndCopyGivesMarkdown;
  LateAnswerAfterCloseIsIgnored;
end;

procedure TAtlasProcessesDialogTests.ShowsWorkspaceProcessesAndLog;
var
  Dialog: TAtlasProcessesDialog;
  Value: TJSONValue;
begin
  Dialog := TAtlasProcessesDialog.CreateDialog(nil, Default(TAtlasProcessesActions));
  Value := Parse(Answer);
  try
    Dialog.ShowAnswer(Value);
    Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.ProcessesTitle, ['Gruppe']), Dialog.Heading.Caption);
    Assert.AreEqual(Dialog.Heading.Caption, Dialog.Caption);
    Assert.IsFalse(Dialog.Choice.Visible, 'Auswahl erst ab zwei Arbeitsbereichen');
    Assert.AreEqual('3f9a\Gruppe.idx', Dialog.CacheValue.Caption);
    Assert.AreEqual('LSP · Atlas IDE Expert (pid 4711)', Dialog.LockValue.Caption);
    Assert.IsTrue(Dialog.WriterTag.Visible, 'Marke schreibt');
    Assert.IsTrue(Dialog.WriterTag.Left > Dialog.LockValue.Left, 'Marke hinter dem Halter');
    Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.ProcessesSaved, ['vor 12 s', 17]), Dialog.StateValue.Caption);
    Assert.AreEqual(2, Integer(Dialog.List.Items.Count));
    Assert.AreEqual('LSP', Dialog.List.Items[0].Caption);
    Assert.AreEqual('Atlas IDE Expert (pid 4711)' + TAtlasStrings.Text(TAtlasTextId.ProcessesOwn),
      Dialog.List.Items[0].SubItems[0]);
    Assert.AreEqual('liest Cache', Dialog.List.Items[1].SubItems[1]);
    Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.ProcessesBuiltOnce, [412]), Dialog.BuiltOnceLabel.Caption);
    Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.ProcessesCount, [2]), Dialog.CountLabel.Caption);
    Assert.AreEqual(1, Integer(Dialog.Log.Lines.Count));
    Assert.AreEqual('10:00:01  LSP 4711: Cache-Sperre erhalten', Dialog.Log.Lines[0]);
    Assert.AreEqual('', Dialog.StatusLabel.Caption);
  finally
    Value.Free;
    Dialog.Free;
  end;
end;

procedure TAtlasProcessesDialogTests.NoServerAndNoProject;
var
  Dialog: TAtlasProcessesDialog;
  Value: TJSONValue;
begin
  Dialog := TAtlasProcessesDialog.CreateDialog(nil, Default(TAtlasProcessesActions));
  Value := Parse('{"workspaces":[],"markdown":"## Prozesse"}');
  try
    Dialog.ShowAnswer(nil);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer), Dialog.StatusLabel.Caption);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.ProcessesTitleNone), Dialog.Heading.Caption);
    Assert.IsFalse(Dialog.CopyButton.Enabled);
    Dialog.ShowAnswer(Value);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.ProcessesEmpty), Dialog.StatusLabel.Caption);
    Assert.AreEqual(0, Integer(Dialog.List.Items.Count));
    Assert.AreEqual('', Dialog.CacheValue.Caption);
  finally
    Value.Free;
    Dialog.Free;
  end;
end;

procedure TAtlasProcessesDialogTests.DirtyFilesNameMcpOnlyWithMcpProcess;
var
  Dialog: TAtlasProcessesDialog;
  Actions: TAtlasProcessesActions;
  Value: TJSONValue;
begin
  Actions := Default(TAtlasProcessesActions);
  Actions.ModifiedFiles :=
    function: TArray<string>
    begin
      Result := ['C:\p\Main.pas'];
    end;
  Dialog := TAtlasProcessesDialog.CreateDialog(nil, Actions);
  Value := Parse(LspOnly);
  try
    Assert.AreEqual(1, Integer(Dialog.Dirty.Items.Count), 'schon vor der Antwort');
    Dialog.ShowAnswer(Value);
    Assert.AreEqual('Main.pas', Dialog.Dirty.Items[0].Caption);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.ProcessesDirtyIdeText), Dialog.Dirty.Items[0].SubItems[0]);
    Assert.AreEqual('', Dialog.Dirty.Items[0].SubItems[1], 'ohne MCP-Prozess');
    Assert.AreEqual('', Dialog.DirtyNote.Caption);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.ProcessesFree), Dialog.LockValue.Caption);
    Assert.IsFalse(Dialog.WriterTag.Visible);
    Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.ProcessesUnits, [3]), Dialog.BuiltOnceLabel.Caption);
    Value.Free;
    Value := Parse(Answer);
    Dialog.ShowAnswer(Value);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.ProcessesDirtyMcpText), Dialog.Dirty.Items[0].SubItems[1]);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.ProcessesDirtyNote), Dialog.DirtyNote.Caption);
  finally
    Value.Free;
    Dialog.Free;
  end;
end;

procedure TAtlasProcessesDialogTests.RefreshAsksAndCopyGivesMarkdown;
var
  Dialog: TAtlasProcessesDialog;
  Actions: TAtlasProcessesActions;
  Copied: string;
  Asked: Integer;
begin
  Asked := 0;
  Copied := '';
  Actions := Default(TAtlasProcessesActions);
  Actions.Fetch :=
    procedure(ADone: TProc<TJSONValue>)
    var
      Value: TJSONValue;
    begin
      Inc(Asked);
      Value := Parse(Answer);
      try
        ADone(Value);
      finally
        Value.Free;
      end;
    end;
  Actions.CopyText :=
    procedure(AText: string)
    begin
      Copied := AText;
    end;
  Dialog := TAtlasProcessesDialog.CreateDialog(nil, Actions);
  try
    Dialog.Refresh;
    Assert.AreEqual(1, Asked);
    Assert.AreEqual(2, Integer(Dialog.List.Items.Count));
    Assert.IsTrue(Dialog.CopyButton.Enabled);
    Dialog.CopyButton.Click;
    Assert.AreEqual('## Prozesse', Copied);
  finally
    Dialog.Free;
  end;
end;

procedure TAtlasProcessesDialogTests.LateAnswerAfterCloseIsIgnored;
var
  Dialog: TAtlasProcessesDialog;
  Actions: TAtlasProcessesActions;
  Pending: TProc<TJSONValue>;
  Value: TJSONValue;
begin
  Pending := nil;
  Actions := Default(TAtlasProcessesActions);
  Actions.Fetch :=
    procedure(ADone: TProc<TJSONValue>)
    begin
      Pending := ADone;
    end;
  Dialog := TAtlasProcessesDialog.CreateDialog(nil, Actions);
  Dialog.Refresh;
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.ProcessesAsking), Dialog.StatusLabel.Caption);
  Dialog.Free;
  Assert.IsTrue(Assigned(Pending));
  Value := Parse(Answer);
  try
    // Darf das freigegebene Fenster nicht anfassen (sonst Zugriffsverletzung).
    Pending(Value);
  finally
    Value.Free;
    Pending := nil;
  end;
  // Kein Assert.Pass: dessen Ausnahme zählte bei der Leckmessung mit.
  Assert.IsFalse(Assigned(Pending), 'Antwort freigegeben');
end;

end.
