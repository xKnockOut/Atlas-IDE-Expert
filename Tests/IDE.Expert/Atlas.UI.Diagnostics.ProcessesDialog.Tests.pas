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
  Atlas.UI.Diagnostics.Strings,
  Atlas.UI.Diagnostics.ProcessesDialog;

const
  cAnswer =
    '{"workspaces":[{"name":"Gruppe","project":"","cache":"3f9a\\Gruppe.idx","format":17,"saved":"vor 12 s",' +
    '"units":412,"lockHolder":"LSP · Atlas IDE Expert (pid 4711)","builtOnce":true,"processes":[' +
    '{"pid":4711,"kind":"LSP","client":"Atlas IDE Expert","state":"baut Index","writer":true,"own":true},' +
    '{"pid":5120,"kind":"MCP","client":"Claude Code","state":"liest Cache","writer":false,"own":false}],' +
    '"events":[{"time":"10:00:01","text":"LSP 4711: Cache-Sperre erhalten"}]}],"markdown":"## Prozesse"}';
  cLspOnly =
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
  mDialog: TAtlasProcessesDialog;
  mValue: TJSONValue;
begin
  mDialog := TAtlasProcessesDialog.CreateDialog(nil, Default(TAtlasProcessesActions));
  mValue := Parse(cAnswer);
  try
    mDialog.ShowAnswer(mValue);
    Assert.AreEqual(TAtlasDiagnosticsStrings.Fmt(TAtlasDiagnosticsTextId.ProcessesTitle, ['Gruppe']),
      mDialog.Heading.Caption);
    Assert.AreEqual(mDialog.Heading.Caption, mDialog.Caption);
    Assert.IsFalse(mDialog.Choice.Visible, 'Auswahl erst ab zwei Arbeitsbereichen');
    Assert.AreEqual('3f9a\Gruppe.idx', mDialog.CacheValue.Caption);
    Assert.AreEqual('LSP · Atlas IDE Expert (pid 4711)', mDialog.LockValue.Caption);
    Assert.IsTrue(mDialog.WriterTag.Visible, 'Marke schreibt');
    Assert.IsTrue(mDialog.WriterTag.Left > mDialog.LockValue.Left, 'Marke hinter dem Halter');
    Assert.AreEqual(TAtlasDiagnosticsStrings.Fmt(TAtlasDiagnosticsTextId.ProcessesSaved, ['vor 12 s', 17]),
      mDialog.StateValue.Caption);
    Assert.AreEqual(2, Integer(mDialog.List.Items.Count));
    Assert.AreEqual('LSP', mDialog.List.Items[0].Caption);
    Assert.AreEqual('Atlas IDE Expert (pid 4711)' + TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.ProcessesOwn),
      mDialog.List.Items[0].SubItems[0]);
    Assert.AreEqual('liest Cache', mDialog.List.Items[1].SubItems[1]);
    Assert.AreEqual(TAtlasDiagnosticsStrings.Fmt(TAtlasDiagnosticsTextId.ProcessesBuiltOnce, [412]),
      mDialog.BuiltOnceLabel.Caption);
    Assert.AreEqual(TAtlasDiagnosticsStrings.Fmt(TAtlasDiagnosticsTextId.ProcessesCount, [2]),
      mDialog.CountLabel.Caption);
    Assert.AreEqual(1, Integer(mDialog.Log.Lines.Count));
    Assert.AreEqual('10:00:01  LSP 4711: Cache-Sperre erhalten', mDialog.Log.Lines[0]);
    Assert.AreEqual('', mDialog.StatusLabel.Caption);
  finally
    mValue.Free;
    mDialog.Free;
  end;
end;

procedure TAtlasProcessesDialogTests.NoServerAndNoProject;
var
  mDialog: TAtlasProcessesDialog;
  mValue: TJSONValue;
begin
  mDialog := TAtlasProcessesDialog.CreateDialog(nil, Default(TAtlasProcessesActions));
  mValue := Parse('{"workspaces":[],"markdown":"## Prozesse"}');
  try
    mDialog.ShowAnswer(nil);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer), mDialog.StatusLabel.Caption);
    Assert.AreEqual(TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.ProcessesTitleNone), mDialog.Heading.Caption);
    Assert.IsFalse(mDialog.CopyButton.Enabled);
    mDialog.ShowAnswer(mValue);
    Assert.AreEqual(TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.ProcessesEmpty), mDialog.StatusLabel.Caption);
    Assert.AreEqual(0, Integer(mDialog.List.Items.Count));
    Assert.AreEqual('', mDialog.CacheValue.Caption);
  finally
    mValue.Free;
    mDialog.Free;
  end;
end;

procedure TAtlasProcessesDialogTests.DirtyFilesNameMcpOnlyWithMcpProcess;
var
  mDialog: TAtlasProcessesDialog;
  mActions: TAtlasProcessesActions;
  mValue: TJSONValue;
begin
  mActions := Default(TAtlasProcessesActions);
  mActions.ModifiedFiles :=
    function: TArray<string>
    begin
      Result := ['C:\p\Main.pas'];
    end;
  mDialog := TAtlasProcessesDialog.CreateDialog(nil, mActions);
  mValue := Parse(cLspOnly);
  try
    Assert.AreEqual(1, Integer(mDialog.Dirty.Items.Count), 'schon vor der Antwort');
    mDialog.ShowAnswer(mValue);
    Assert.AreEqual('Main.pas', mDialog.Dirty.Items[0].Caption);
    Assert.AreEqual(TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.ProcessesDirtyIdeText),
      mDialog.Dirty.Items[0].SubItems[0]);
    Assert.AreEqual('', mDialog.Dirty.Items[0].SubItems[1], 'ohne MCP-Prozess');
    Assert.AreEqual('', mDialog.DirtyNote.Caption);
    Assert.AreEqual(TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.ProcessesFree), mDialog.LockValue.Caption);
    Assert.IsFalse(mDialog.WriterTag.Visible);
    Assert.AreEqual(TAtlasDiagnosticsStrings.Fmt(TAtlasDiagnosticsTextId.ProcessesUnits, [3]),
      mDialog.BuiltOnceLabel.Caption);
    mValue.Free;
    mValue := Parse(cAnswer);
    mDialog.ShowAnswer(mValue);
    Assert.AreEqual(TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.ProcessesDirtyMcpText),
      mDialog.Dirty.Items[0].SubItems[1]);
    Assert.AreEqual(TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.ProcessesDirtyNote),
      mDialog.DirtyNote.Caption);
  finally
    mValue.Free;
    mDialog.Free;
  end;
end;

procedure TAtlasProcessesDialogTests.RefreshAsksAndCopyGivesMarkdown;
var
  mDialog: TAtlasProcessesDialog;
  mActions: TAtlasProcessesActions;
  mCopied: string;
  mAsked: Integer;
begin
  mAsked := 0;
  mCopied := '';
  mActions := Default(TAtlasProcessesActions);
  mActions.Fetch :=
    procedure(ADone: TProc<TJSONValue>)
    var
      Value: TJSONValue;
    begin
      Inc(mAsked);
      Value := Parse(cAnswer);
      try
        ADone(Value);
      finally
        Value.Free;
      end;
    end;
  mActions.CopyText :=
    procedure(AText: string)
    begin
      mCopied := AText;
    end;
  mDialog := TAtlasProcessesDialog.CreateDialog(nil, mActions);
  try
    mDialog.Reload;
    Assert.AreEqual(1, mAsked);
    Assert.AreEqual(2, Integer(mDialog.List.Items.Count));
    Assert.IsTrue(mDialog.CopyButton.Enabled);
    mDialog.CopyButton.Click;
    Assert.AreEqual('## Prozesse', mCopied);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasProcessesDialogTests.LateAnswerAfterCloseIsIgnored;
var
  mDialog: TAtlasProcessesDialog;
  mActions: TAtlasProcessesActions;
  mPending: TProc<TJSONValue>;
  mValue: TJSONValue;
begin
  mPending := nil;
  mActions := Default(TAtlasProcessesActions);
  mActions.Fetch :=
    procedure(ADone: TProc<TJSONValue>)
    begin
      mPending := ADone;
    end;
  mDialog := TAtlasProcessesDialog.CreateDialog(nil, mActions);
  mDialog.Reload;
  Assert.AreEqual(TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.ProcessesAsking), mDialog.StatusLabel.Caption);
  mDialog.Free;
  Assert.IsTrue(Assigned(mPending));
  mValue := Parse(cAnswer);
  try
    // Darf das freigegebene Fenster nicht anfassen (sonst Zugriffsverletzung).
    mPending(mValue);
  finally
    mValue.Free;
    mPending := nil;
  end;
  // Kein Assert.Pass: dessen Ausnahme zählte bei der Leckmessung mit.
  Assert.IsFalse(Assigned(mPending), 'Antwort freigegeben');
end;

end.
