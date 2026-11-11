unit Atlas.Core.Assistants.EditPlan;

// Entscheidung des Eingangs für schreibende MCP-Werkzeuge (#397), ohne Open
// Tools API und damit ohne IDE testbar (#1967). Die IDE liefert nur den Zustand
// des Puffers der Datei (IAtlasEditorFiles: offen, Text, ungespeichert
// geändert); Decide sagt, was mit dem Auftrag geschieht:
// - Datei nicht offen: ablehnen, der MCP-Server schreibt selbst.
// - Puffer weicht vom gelesenen Stand ab und ist ungespeichert geändert:
//   ablehnen, der MCP-Server schreibt nicht (die Änderung des Benutzers geht vor).
// - Puffer weicht sonst ab (z. B. andere Zeilenenden): ablehnen, der MCP-Server
//   schreibt selbst, und das Neuladen der IDE (#536) holt die Datei.
// - Sonst anwenden; war der Puffer vorher gespeichert, danach speichern, weil
//   der MCP-Server über die Platte liest und vergleicht.
// EditOf baut daraus die kleinste Textänderung an der Datei. Run führt einen
// Auftrag ganz aus: Puffer lesen, entscheiden, anwenden (über AApply, das die
// IDE stellt), speichern; die IDE schreibt nur noch die Antwort.

interface

uses
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Files.Contract;

type
  /// <summary>Was der Eingang mit einem Auftrag tut.</summary>
  TAtlasEditInboxStep = (NotOpen, ModifiedInEditor, DiffersFromDisk, Apply);

  /// <summary>Ergebnis von TAtlasEditInboxPlan.Decide.</summary>
  TAtlasEditInboxDecision = record
    Step: TAtlasEditInboxStep;
    /// <summary>Der Puffer war vor dem Anwenden ungespeichert geändert.</summary>
    WasModified: Boolean;
    /// <summary>Die Änderung wird im Puffer angewendet.</summary>
    function Applies: Boolean;
    /// <summary>Abgelehnt, und der MCP-Server schreibt die Datei selbst (Antwort "notOpen").</summary>
    function ServerWrites: Boolean;
    /// <summary>Grund der Ablehnung für die Antwort an den MCP-Server; '' beim Anwenden.</summary>
    function Reason: string;
    /// <summary>Nach dem Anwenden speichern: Der Puffer war vorher gespeichert.</summary>
    function SaveAfter: Boolean;
  end;

  /// <summary>Wendet AEdit im Editor an; Ergebnis '' oder der Fehlertext.</summary>
  TAtlasEditInboxApply = reference to function(const AEdit: TLspWorkspaceEdit): string;

  /// <summary>Ergebnis von TAtlasEditInboxPlan.Run, wie es in die Antwort an den MCP-Server geht.</summary>
  TAtlasEditInboxOutcome = record
    /// <summary>Die Änderung steht im Puffer.</summary>
    Applied: Boolean;
    /// <summary>Abgelehnt, und der MCP-Server schreibt die Datei selbst.</summary>
    ServerWrites: Boolean;
    /// <summary>Grund der Ablehnung oder Fehlertext; '' beim Anwenden.</summary>
    Reason: string;
  end;

  TAtlasEditInboxPlan = class
  public const
    cReasonNotOpen = 'nicht offen';
    cReasonModified = 'im Editor ungespeichert geändert';
    cReasonDiffers = 'Puffer weicht von der Platte ab';
  public
    /// <summary>Was mit einem Auftrag geschieht, der AExpected als bisherigen Text der Datei nennt.</summary>
    class function Decide(const ABuffer: TAtlasEditorFile; const AExpected: string): TAtlasEditInboxDecision;
      static;
    /// <summary>Änderung von AExpected nach AText als kleinste Textänderung an der Datei AFileName.</summary>
    class function EditOf(const AFileName, AExpected, AText: string): TLspWorkspaceEdit; static;
    /// <summary>Führt den Auftrag aus, AFileName von AExpected auf AText zu ändern: Puffer aus AFiles,
    /// Entscheidung, Anwenden über AApply und Speichern, wenn der Puffer vorher gespeichert war. AApply wird nur
    /// gerufen, wenn die Änderung angewendet wird.</summary>
    class function Run(const AFiles: IAtlasEditorFiles; const AFileName, AExpected, AText: string;
      const AApply: TAtlasEditInboxApply): TAtlasEditInboxOutcome; static;
  end;

implementation

uses
  Atlas.Core.Lsp.TextChanges;

function TAtlasEditInboxDecision.Applies: Boolean;
begin
  Result := Step = TAtlasEditInboxStep.Apply;
end;

function TAtlasEditInboxDecision.ServerWrites: Boolean;
begin
  Result := Step in [TAtlasEditInboxStep.NotOpen, TAtlasEditInboxStep.DiffersFromDisk];
end;

function TAtlasEditInboxDecision.Reason: string;
begin
  case Step of
    TAtlasEditInboxStep.NotOpen:
      Result := TAtlasEditInboxPlan.cReasonNotOpen;
    TAtlasEditInboxStep.ModifiedInEditor:
      Result := TAtlasEditInboxPlan.cReasonModified;
    TAtlasEditInboxStep.DiffersFromDisk:
      Result := TAtlasEditInboxPlan.cReasonDiffers;
  else
    Result := '';
  end;
end;

function TAtlasEditInboxDecision.SaveAfter: Boolean;
begin
  Result := Applies and not WasModified;
end;

class function TAtlasEditInboxPlan.Decide(const ABuffer: TAtlasEditorFile;
  const AExpected: string): TAtlasEditInboxDecision;
begin
  Result.WasModified := ABuffer.Modified;
  if not ABuffer.Open then
  begin
    Result.Step := TAtlasEditInboxStep.NotOpen;
  end
  else if ABuffer.Text <> AExpected then
  begin
    if ABuffer.Modified then
    begin
      Result.Step := TAtlasEditInboxStep.ModifiedInEditor;
    end
    else
    begin
      Result.Step := TAtlasEditInboxStep.DiffersFromDisk;
    end;
  end
  else
  begin
    Result.Step := TAtlasEditInboxStep.Apply;
  end;
end;

class function TAtlasEditInboxPlan.EditOf(const AFileName, AExpected, AText: string): TLspWorkspaceEdit;
var
  mChange: TLspTextChange;
  mTextEdit: TLspTextEdit;
begin
  mChange := TLspTextChanges.Between(AExpected, AText);
  mTextEdit.StartPos := mChange.StartPos;
  mTextEdit.EndPos := mChange.EndPos;
  mTextEdit.NewText := mChange.Text;
  Result := Default(TLspWorkspaceEdit);
  Result.Files := [Default(TLspFileEdits)];
  Result.Files[0].FileName := AFileName;
  Result.Files[0].Edits := [mTextEdit];
end;

class function TAtlasEditInboxPlan.Run(const AFiles: IAtlasEditorFiles; const AFileName, AExpected, AText: string;
  const AApply: TAtlasEditInboxApply): TAtlasEditInboxOutcome;
var
  mDecision: TAtlasEditInboxDecision;
begin
  Result := Default(TAtlasEditInboxOutcome);
  mDecision := Decide(AFiles.Buffer(AFileName), AExpected);
  if not mDecision.Applies then
  begin
    Result.ServerWrites := mDecision.ServerWrites;
    Result.Reason := mDecision.Reason;
    Exit;
  end;
  Result.Reason := AApply(EditOf(AFileName, AExpected, AText));
  if Result.Reason <> '' then
  begin
    Exit;
  end;
  if mDecision.SaveAfter then
  begin
    AFiles.Save(AFileName);
  end;
  Result.Applied := True;
end;

end.
