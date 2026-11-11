unit Atlas.Core.Assistants.EditPlan.Tests;

// Tests für die Entscheidung des Eingangs schreibender MCP-Werkzeuge (#397, #1967): Pufferzustand und Auftrag
// ergeben Anwenden, Ablehnen mit oder ohne Schreiben durch den MCP-Server und Speichern danach.

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
  end;

implementation

uses
  Atlas.Core.Assistants.EditPlan,
  Atlas.Core.Lsp.WorkspaceEdits;

procedure TAtlasEditInboxPlanTests.ClosedFileLetsTheServerWrite;
var
  mDecision: TAtlasEditInboxDecision;
begin
  mDecision := TAtlasEditInboxPlan.Decide(TAtlasEditInboxBuffer.Closed, 'a');
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
  mDecision := TAtlasEditInboxPlan.Decide(TAtlasEditInboxBuffer.Opened('a getippt', True), 'a');
  Assert.IsTrue(mDecision.Step = TAtlasEditInboxStep.ModifiedInEditor, 'ungespeichert geändert');
  Assert.IsFalse(mDecision.Applies, 'nicht anwenden');
  Assert.IsFalse(mDecision.ServerWrites, 'die Änderung des Benutzers geht vor');
  Assert.AreEqual(TAtlasEditInboxPlan.cReasonModified, mDecision.Reason);
end;

procedure TAtlasEditInboxPlanTests.SavedDifferentBufferLetsTheServerWrite;
var
  mDecision: TAtlasEditInboxDecision;
begin
  mDecision := TAtlasEditInboxPlan.Decide(TAtlasEditInboxBuffer.Opened('a'#13#10, False), 'a'#10);
  Assert.IsTrue(mDecision.Step = TAtlasEditInboxStep.DiffersFromDisk, 'andere Zeilenenden');
  Assert.IsFalse(mDecision.Applies, 'nicht anwenden');
  Assert.IsTrue(mDecision.ServerWrites, 'der MCP-Server schreibt, die IDE lädt neu');
  Assert.AreEqual(TAtlasEditInboxPlan.cReasonDiffers, mDecision.Reason);
end;

procedure TAtlasEditInboxPlanTests.MatchingSavedBufferAppliesAndSaves;
var
  mDecision: TAtlasEditInboxDecision;
begin
  mDecision := TAtlasEditInboxPlan.Decide(TAtlasEditInboxBuffer.Opened('a', False), 'a');
  Assert.IsTrue(mDecision.Applies, 'anwenden');
  Assert.IsFalse(mDecision.ServerWrites, 'der MCP-Server schreibt nicht');
  Assert.AreEqual('', mDecision.Reason);
  Assert.IsTrue(mDecision.SaveAfter, 'gespeichert bleibt gespeichert');
end;

procedure TAtlasEditInboxPlanTests.MatchingModifiedBufferAppliesWithoutSaving;
var
  mDecision: TAtlasEditInboxDecision;
begin
  mDecision := TAtlasEditInboxPlan.Decide(TAtlasEditInboxBuffer.Opened('a', True), 'a');
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

end.
