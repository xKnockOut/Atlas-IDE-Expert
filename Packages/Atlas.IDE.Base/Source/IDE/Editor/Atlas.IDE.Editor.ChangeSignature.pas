unit Atlas.IDE.Editor.ChangeSignature;

// Code-Aktion „Signatur ändern …“ (#100): Der Server bietet sie als
// Client-Befehl atlas.changeSignature mit URI und Position an. Atlas schickt
// die offenen Puffer, holt die heutige Signatur
// (atlas.server.changeSignature.prepare), zeigt den Dialog als Eingabemaske,
// holt mit der neuen Liste das WorkspaceEdit (atlas.server.changeSignature),
// zeigt die Vorschau wie beim Umbenennen mit den Warnungen des Servers und
// übernimmt erst nach Bestätigung. Abbrüche (gebundener Bibliothekshandler,
// im Rumpf benutzter Parameter, Kollision) meldet der Server als Fehler.
// Abschaltbar über refactoring.changeSignature: Dann bietet der Server die
// Aktion nicht an. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.WorkspacePlan;

type
  TAtlasIdeChangeSignature = class
  public const
    ClientCommand = 'atlas.changeSignature';
  public
    /// <summary>AArgumentsJson: Argumente der Code-Aktion ([uri, position]); ASession: laufende Sitzung oder nil;
    /// AMessage: Zeile für die Meldungsansicht.</summary>
    class procedure Execute(ASession: TLspSession; const AArgumentsJson: string; APolicy: TAtlasUnopenedPolicy;
      const AMessage: TProc<string>); static;
  end;

implementation

uses
  System.JSON,
  Atlas.UI.Strings,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Editor.ChangeSignature,
  Atlas.UI.Editor.ChangeSignature,
  Atlas.IDE.Editor.Rename,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Editor.ServerEdit;

const
  PrepareCommand = 'atlas.server.changeSignature.prepare';
  ApplyCommand = 'atlas.server.changeSignature';
  // Alle Aufrufer im Projekt suchen dauert; wie beim Umbenennen.
  TimeoutMs = 60000;

/// <summary>Modell der Signatur vom Server; False mit Meldung, wenn er scheitert.</summary>
function FetchModel(ASession: TLspSession; const AArgumentsJson: string; const AMessage: TProc<string>;
  out AModel: TAtlasSignatureModel): Boolean;
var
  mAnswer: TJSONValue;
begin
  Result := False;
  AModel := nil;
  TAtlasIdeRename.SyncOpenBuffers(ASession);
  try
    mAnswer := ASession.RunCommand(PrepareCommand, AArgumentsJson, TimeoutMs);
    try
      AModel := TAtlasSignatureModel.Create(TAtlasIdeServerEdit.AsObject(mAnswer));
    finally
      mAnswer.Free;
    end;
    Result := True;
  except
    on E: ELspClientError do
    begin
      AMessage(TAtlasStrings.Fmt(TAtlasTextId.SigFailed, [E.Message]));
    end;
  end;
end;

/// <summary>Zeigt den Dialog; AApplyArguments sind die Argumente der Aktion mit der neuen Liste. False bei Abbruch
/// oder ohne Änderung (dann mit Meldung).</summary>
function ChooseSignature(ASession: TLspSession; const AArgumentsJson: string; const AMessage: TProc<string>;
  out AApplyArguments: string): Boolean;
var
  mModel: TAtlasSignatureModel;
begin
  AApplyArguments := '';
  Result := FetchModel(ASession, AArgumentsJson, AMessage, mModel);
  if not Result then
  begin
    Exit;
  end;
  try
    Result := TAtlasChangeSignatureDialog.Execute(mModel);
    if Result and not mModel.Changed then
    begin
      AMessage(TAtlasStrings.Text(TAtlasTextId.SigNothing));
      Result := False;
    end;
    // Argumente der Aktion um die neue Liste ergänzen.
    Result := Result and TAtlasIdeServerEdit.Appended(AArgumentsJson, mModel.RequestJson, AApplyArguments);
  finally
    mModel.Free;
  end;
end;

class procedure TAtlasIdeChangeSignature.Execute(ASession: TLspSession; const AArgumentsJson: string;
  APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
var
  mApplyArguments, mHint: string;
  mReply: TAtlasServerEditReply;
  mOutcome: TAtlasWorkspaceEditResult;
begin
  if ASession = nil then
  begin
    AMessage(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Exit;
  end;
  if not ChooseSignature(ASession, AArgumentsJson, AMessage, mApplyArguments) or
    not TAtlasIdeServerEdit.Fetch(ASession, TAtlasServerEditCommand.Create(ApplyCommand, mApplyArguments, TimeoutMs,
    TAtlasTextId.SigFailed), nil, AMessage, mReply) then
  begin
    Exit;
  end;
  if mReply.Edit.IsEmpty then
  begin
    AMessage(TAtlasStrings.Text(TAtlasTextId.SigNothing));
    Exit;
  end;
  // Vorschau wie beim Umbenennen (#400); Warnungen (Methodenzeiger, schreibgeschützte Aufrufer) im Hinweis.
  mHint := TAtlasStrings.Fmt(TAtlasTextId.SigPreviewHint, [mReply.Edit.EditCount, Length(mReply.Edit.Files)]) +
    TAtlasIdeServerEdit.WarningLines(mReply, TAtlasTextId.SigWarning);
  if not TAtlasIdeServerEdit.Confirm(TAtlasStrings.Text(TAtlasTextId.SigPreviewTitle), mHint,
    TAtlasStrings.Text(TAtlasTextId.SigPreviewApply), mReply.Edit) then
  begin
    Exit;
  end;
  // Warnungen auch dann, wenn das Übernehmen scheitert.
  if TAtlasIdeServerEdit.Apply(mReply.Edit, APolicy, TAtlasStrings.Text(TAtlasTextId.SigPreviewTitle), AMessage,
    mOutcome) then
  begin
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.SigDone, [mOutcome.Edits, mOutcome.Files]));
  end;
  TAtlasIdeServerEdit.ReportAfter(mReply, mOutcome, TAtlasTextId.SigWarning, AMessage);
end;

end.
