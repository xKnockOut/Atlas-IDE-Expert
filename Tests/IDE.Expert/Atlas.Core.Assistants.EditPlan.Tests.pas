unit Atlas.Core.Assistants.EditPlan.Tests;

// Tests für die Entscheidung des Eingangs schreibender MCP-Werkzeuge (#397, #1967): Pufferzustand und Auftrag
// ergeben Anwenden, Ablehnen mit oder ohne Schreiben durch den MCP-Server und Speichern danach. Run läuft gegen
// eine Fälschung der offenen Dateien.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Assistants')]
  TAtlasEditInboxPlanTests = class
  public
    [Test]
    procedure ClosedFileLetsTheServerWrite;
    [Test]
    procedure ModifiedDifferentBufferRejectsWithoutServerWrite;
    [Test]
    procedure SavedDifferentBufferLetsTheServerWrite;
    [Test]
    procedure MatchingSavedBufferAppliesAndSaves;
    [Test]
    procedure MatchingModifiedBufferAppliesWithoutSaving;
    [Test]
    procedure EditOfChangesOnlyTheChangedRange;
    [Test]
    procedure EditOfEqualTextsIsEmptyAtTheEnd;
    [Test]
    procedure RunAppliesAndSavesSavedBuffer;
    [Test]
    procedure RunKeepsUnsavedChangesUnsaved;
    [Test]
    procedure RunLeavesClosedFileToTheServer;
    [Test]
    procedure RunReportsApplyErrorWithoutSaving;
  end;

implementation

uses
  Atlas.Core.Files.Contract,
  Atlas.Core.Assistants.EditPlan,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Tests.EditorFilesFake;

procedure TAtlasEditInboxPlanTests.ClosedFileLetsTheServerWrite;
var
  mDecision: TAtlasEditInboxDecision;
begin
  mDecision := TAtlasEditInboxPlan.Decide(TAtlasEditorFile.Closed, 'a');
  Assert.IsTrue(mDecision.Step = TAtlasEditInboxStep.NotOpen, 'nicht offen');
  Assert.IsFalse(mDecision.Applies, 'nicht anwenden');
  Assert.IsTrue(mDecision.ServerWrites, 'der MCP-Server schreibt selbst');
  Assert.AreEqual(TAtlasEditInboxPlan.cReasonNotOpen, mDecision.Reason);
  Assert.IsFalse(mDecision.SaveAfter, 'nichts zu speichern');
end;

procedure TAtlasEditInboxPlanTests.ModifiedDifferentBufferRejectsWithoutServerWrite;
var
  mDecision: TAtlasEditInboxDecision;
begin
  mDecision := TAtlasEditInboxPlan.Decide(TAtlasEditorFile.Opened('a getippt', True), 'a');
  Assert.IsTrue(mDecision.Step = TAtlasEditInboxStep.ModifiedInEditor, 'ungespeichert geändert');
  Assert.IsFalse(mDecision.Applies, 'nicht anwenden');
  Assert.IsFalse(mDecision.ServerWrites, 'die Änderung des Benutzers geht vor');
  Assert.AreEqual(TAtlasEditInboxPlan.cReasonModified, mDecision.Reason);
end;

procedure TAtlasEditInboxPlanTests.SavedDifferentBufferLetsTheServerWrite;
var
  mDecision: TAtlasEditInboxDecision;
begin
  mDecision := TAtlasEditInboxPlan.Decide(TAtlasEditorFile.Opened('a'#13#10, False), 'a'#10);
  Assert.IsTrue(mDecision.Step = TAtlasEditInboxStep.DiffersFromDisk, 'andere Zeilenenden');
  Assert.IsFalse(mDecision.Applies, 'nicht anwenden');
  Assert.IsTrue(mDecision.ServerWrites, 'der MCP-Server schreibt, die IDE lädt neu');
  Assert.AreEqual(TAtlasEditInboxPlan.cReasonDiffers, mDecision.Reason);
end;

procedure TAtlasEditInboxPlanTests.MatchingSavedBufferAppliesAndSaves;
var
  mDecision: TAtlasEditInboxDecision;
begin
  mDecision := TAtlasEditInboxPlan.Decide(TAtlasEditorFile.Opened('a', False), 'a');
  Assert.IsTrue(mDecision.Applies, 'anwenden');
  Assert.IsFalse(mDecision.ServerWrites, 'der MCP-Server schreibt nicht');
  Assert.AreEqual('', mDecision.Reason);
  Assert.IsTrue(mDecision.SaveAfter, 'gespeichert bleibt gespeichert');
end;

procedure TAtlasEditInboxPlanTests.MatchingModifiedBufferAppliesWithoutSaving;
var
  mDecision: TAtlasEditInboxDecision;
begin
  mDecision := TAtlasEditInboxPlan.Decide(TAtlasEditorFile.Opened('a', True), 'a');
  Assert.IsTrue(mDecision.Applies, 'anwenden');
  Assert.IsFalse(mDecision.SaveAfter, 'ungespeicherte Änderungen des Benutzers nicht mitspeichern');
end;

procedure TAtlasEditInboxPlanTests.EditOfChangesOnlyTheChangedRange;
var
  mEdit: TLspWorkspaceEdit;
begin
  mEdit := TAtlasEditInboxPlan.EditOf('C:\p\U.pas', 'eins'#13#10'zwei'#13#10'drei', 'eins'#13#10'ZWEI'#13#10'drei');
  Assert.AreEqual(1, Integer(Length(mEdit.Files)), 'eine Datei');
  Assert.AreEqual('C:\p\U.pas', mEdit.Files[0].FileName);
  Assert.AreEqual(1, Integer(Length(mEdit.Files[0].Edits)), 'eine Änderung');
  Assert.AreEqual(1, mEdit.Files[0].Edits[0].StartPos.Line, 'Startzeile');
  Assert.AreEqual(0, mEdit.Files[0].Edits[0].StartPos.Character, 'Startspalte');
  Assert.AreEqual(1, mEdit.Files[0].Edits[0].EndPos.Line, 'Endzeile');
  Assert.AreEqual(4, mEdit.Files[0].Edits[0].EndPos.Character, 'Endspalte');
  Assert.AreEqual('ZWEI', mEdit.Files[0].Edits[0].NewText);
end;

procedure TAtlasEditInboxPlanTests.EditOfEqualTextsIsEmptyAtTheEnd;
var
  mEdit: TLspWorkspaceEdit;
begin
  mEdit := TAtlasEditInboxPlan.EditOf('U.pas', 'ab', 'ab');
  Assert.AreEqual('', mEdit.Files[0].Edits[0].NewText, 'kein neuer Text');
  Assert.AreEqual(0, mEdit.Files[0].Edits[0].StartPos.Line);
  Assert.AreEqual(2, mEdit.Files[0].Edits[0].StartPos.Character, 'leerer Bereich am Ende');
  Assert.AreEqual(2, mEdit.Files[0].Edits[0].EndPos.Character);
end;

procedure TAtlasEditInboxPlanTests.RunAppliesAndSavesSavedBuffer;
var
  mFiles: TAtlasEditorFilesFake;
  mKeep: IAtlasEditorFiles;
  mApplied: TArray<TLspWorkspaceEdit>;
  mOutcome: TAtlasEditInboxOutcome;
begin
  mFiles := TAtlasEditorFilesFake.Create;
  mKeep := mFiles;
  mFiles.Put('U.pas', 'alt', False);
  mOutcome := TAtlasEditInboxPlan.Run(mKeep, 'U.pas', 'alt', 'neu',
    function(const AEdit: TLspWorkspaceEdit): string
    begin
      mApplied := mApplied + [AEdit];
      Result := '';
    end);
  Assert.IsTrue(mOutcome.Applied, 'angewendet');
  Assert.AreEqual('', mOutcome.Reason, 'kein Grund');
  Assert.AreEqual(1, Integer(Length(mApplied)), 'einmal angewendet');
  Assert.AreEqual('neu', mApplied[0].Files[0].Edits[0].NewText);
  Assert.AreEqual(1, Integer(Length(mFiles.Saved)), 'danach gespeichert');
  Assert.AreEqual('U.pas', mFiles.Saved[0]);
end;

procedure TAtlasEditInboxPlanTests.RunKeepsUnsavedChangesUnsaved;
var
  mFiles: TAtlasEditorFilesFake;
  mKeep: IAtlasEditorFiles;
  mOutcome: TAtlasEditInboxOutcome;
begin
  mFiles := TAtlasEditorFilesFake.Create;
  mKeep := mFiles;
  mFiles.Put('U.pas', 'alt', True);
  mOutcome := TAtlasEditInboxPlan.Run(mKeep, 'U.pas', 'alt', 'neu',
    function(const AEdit: TLspWorkspaceEdit): string
    begin
      Result := '';
    end);
  Assert.IsTrue(mOutcome.Applied, 'angewendet');
  Assert.AreEqual(0, Integer(Length(mFiles.Saved)), 'ungespeicherte Änderungen des Benutzers nicht mitspeichern');
end;

procedure TAtlasEditInboxPlanTests.RunLeavesClosedFileToTheServer;
var
  mFiles: TAtlasEditorFilesFake;
  mKeep: IAtlasEditorFiles;
  mCalls: Integer;
  mOutcome: TAtlasEditInboxOutcome;
begin
  mFiles := TAtlasEditorFilesFake.Create;
  mKeep := mFiles;
  mCalls := 0;
  mOutcome := TAtlasEditInboxPlan.Run(mKeep, 'Zu.pas', 'alt', 'neu',
    function(const AEdit: TLspWorkspaceEdit): string
    begin
      Inc(mCalls);
      Result := '';
    end);
  Assert.IsFalse(mOutcome.Applied, 'nicht angewendet');
  Assert.IsTrue(mOutcome.ServerWrites, 'der MCP-Server schreibt selbst');
  Assert.AreEqual(TAtlasEditInboxPlan.cReasonNotOpen, mOutcome.Reason);
  Assert.AreEqual(0, mCalls, 'nichts angewendet');
  Assert.AreEqual(0, Integer(Length(mFiles.Saved)), 'nichts gespeichert');
end;

procedure TAtlasEditInboxPlanTests.RunReportsApplyErrorWithoutSaving;
var
  mFiles: TAtlasEditorFilesFake;
  mKeep: IAtlasEditorFiles;
  mOutcome: TAtlasEditInboxOutcome;
begin
  mFiles := TAtlasEditorFilesFake.Create;
  mKeep := mFiles;
  mFiles.Put('U.pas', 'alt', False);
  mOutcome := TAtlasEditInboxPlan.Run(mKeep, 'U.pas', 'alt', 'neu',
    function(const AEdit: TLspWorkspaceEdit): string
    begin
      Result := 'schreibgeschützt';
    end);
  Assert.IsFalse(mOutcome.Applied, 'nicht angewendet');
  Assert.IsFalse(mOutcome.ServerWrites, 'der MCP-Server schreibt nicht über den Fehler hinweg');
  Assert.AreEqual('schreibgeschützt', mOutcome.Reason);
  Assert.AreEqual(0, Integer(Length(mFiles.Saved)), 'nicht gespeichert');
end;

end.
