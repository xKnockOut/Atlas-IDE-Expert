unit Atlas.IDE.Editor.SafeDelete;

// „Sicher löschen“ (#716) im Editor: Alt+Entf (keys.safeDelete) und die
// Code-Aktion des Servers (Client-Befehl atlas.safeDelete mit URI und
// Position) landen hier. Atlas schickt die offenen Puffer, lässt den Server
// prüfen (atlas.server.safeDelete.prepare) und fragt nach den Einstellungen
// refactoring.safeDeleteIncludeOverrides und refactoring.safeDeleteCascade
// (ask: Rückfrage, always, never), ob Überschreibungen und Freigewordenes
// mitgehen. Bleiben Verwendungen, wählt der Benutzer Abbrechen, Anzeigen
// (Fundstellen im Ergebnisfenster) oder Trotzdem löschen. Dann holt Atlas das
// WorkspaceEdit (atlas.server.safeDelete) und übernimmt es sofort oder nach
// der Vorschau (mit Verwendungen, bei einer Unit oder mit
// refactoring.safeDeletePreviewWhenUnused), je Datei ein Rückgängig-Schritt;
// eine gelöschte Unit wandert in den Papierkorb und aus dem Projekt. Nur im
// Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.WorkspacePlan;

type
  TAtlasIdeSafeDelete = class
  public const
    ClientCommand = 'atlas.safeDelete';
  public
    /// <summary>AArgumentsJson: [uri, position]; ASession: laufende Sitzung oder nil; AMessage: Zeile für die
    /// Meldungsansicht.</summary>
    class procedure Execute(ASession: TLspSession; const AArgumentsJson: string; APolicy: TAtlasUnopenedPolicy;
      const AMessage: TProc<string>); static;
  end;

implementation

uses
  System.UITypes,
  System.JSON,
  Vcl.Dialogs,
  Vcl.Forms,
  Vcl.StdCtrls,
  Atlas.UI.Strings,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Results.Model,
  Atlas.Core.Editor.SafeDelete,
  Atlas.UI.Results.Frame,
  Atlas.UI.Results.RenamePreview,
  Atlas.IDE.Editor.Rename,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.ResultsWindow;

const
  // Referenzsuche im Projekt, Nachfahren und uses aller Units: dauert.
  TimeoutMs = 120000;
  // Zeilen in einer Rückfrage.
  MaxListed = 12;

type
  {$SCOPEDENUMS ON}
  TUsageChoice = (Cancel, Show, Force);
  {$SCOPEDENUMS OFF}

function NumberOf(AReply: TJSONObject; const AName: string): Integer;
begin
  Result := 0;
  if (AReply <> nil) and (AReply.GetValue(AName) is TJSONNumber) then
    Result := TJSONNumber(AReply.GetValue(AName)).AsInt;
end;

function Ask(const AText: string): Boolean;
begin
  Result := MessageDlg(AText, TMsgDlgType.mtConfirmation, [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo], 0) = mrYes;
end;

/// <summary>Wahl nach der Einstellung AMode; bei ask die Rückfrage AText.</summary>
function Decide(const AMode, AText: string): Boolean;
begin
  case TAtlasSafeDelete.AnswerOf(AMode) of
    TAtlasSafeDeleteAnswer.Always:
      Result := True;
    TAtlasSafeDeleteAnswer.Never:
      Result := False;
  else
    Result := Ask(AText);
  end;
end;

function Lines(const AUsages: TArray<TAtlasSafeDeleteUsage>): TArray<string>;
var
  Usage: TAtlasSafeDeleteUsage;
begin
  Result := nil;
  for Usage in AUsages do
    Result := Result + [Format('%s:%d  %s', [ExtractFileName(Usage.FileName), Usage.Line + 1, Usage.Text])];
end;

function Entries(const AUsages: TArray<TAtlasSafeDeleteUsage>): TArray<TAtlasResultEntry>;
var
  Usage: TAtlasSafeDeleteUsage;
  Entry: TAtlasResultEntry;
begin
  Result := nil;
  for Usage in AUsages do
  begin
    Entry := TAtlasResultEntry.Create(Usage.FileName, Usage.Line, Usage.Character);
    Entry.Text := Usage.Text;
    Result := Result + [Entry];
  end;
end;

/// <summary>Abbrechen, Anzeigen oder Trotzdem löschen.</summary>
function ChooseOnUsages(const AInfo: TAtlasSafeDeleteInfo; const AUsages: TArray<TAtlasSafeDeleteUsage>):
  TUsageChoice;
var
  Dialog: TForm;
  Index: Integer;
  Button: TButton;
begin
  Dialog := CreateMessageDialog(TAtlasStrings.Fmt(TAtlasTextId.SafeDeleteUsages, [AInfo.Name, Length(AUsages)]) +
    sLineBreak + sLineBreak + TAtlasSafeDelete.Listing(Lines(AUsages), MaxListed,
    TAtlasStrings.Text(TAtlasTextId.SafeDeleteMore)), TMsgDlgType.mtWarning,
    [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbAll, TMsgDlgBtn.mbCancel], TMsgDlgBtn.mbCancel);
  try
    Dialog.Caption := TAtlasStrings.Text(TAtlasTextId.SafeDeleteCommand);
    for Index := 0 to Dialog.ComponentCount - 1 do
      if Dialog.Components[Index] is TButton then
      begin
        Button := TButton(Dialog.Components[Index]);
        case Button.ModalResult of
          mrYes:
            Button.Caption := TAtlasStrings.Text(TAtlasTextId.SafeDeleteShow);
          mrAll:
            Button.Caption := TAtlasStrings.Text(TAtlasTextId.SafeDeleteForce);
          mrCancel:
            Button.Caption := TAtlasStrings.Text(TAtlasTextId.SafeDeleteCancel);
        end;
      end;
    case Dialog.ShowModal of
      mrYes:
        Result := TUsageChoice.Show;
      mrAll:
        Result := TUsageChoice.Force;
    else
      Result := TUsageChoice.Cancel;
    end;
  finally
    Dialog.Free;
  end;
end;

class procedure TAtlasIdeSafeDelete.Execute(ASession: TLspSession; const AArgumentsJson: string;
  APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
var
  Answer, Item: TJSONValue;
  Reply: TJSONObject;
  Info: TAtlasSafeDeleteInfo;
  Overrides, Cascade, Forced: Boolean;
  Blocking: TArray<TAtlasSafeDeleteUsage>;
  Hint, Warning, Title: string;
  Warnings: TArray<string>;
  Deleted: Integer;
  Edit: TLspWorkspaceEdit;
  Outcome: TAtlasWorkspaceEditResult;
  Preview: TArray<TAtlasResultEntry>;
  Open: TAtlasResultsOpen;
begin
  if ASession = nil then
  begin
    AMessage(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Exit;
  end;
  TAtlasIdeRename.SyncOpenBuffers(ASession);
  try
    Answer := ASession.RunCommand(TAtlasSafeDelete.PrepareCommand, AArgumentsJson, TimeoutMs);
    try
      Info := TAtlasSafeDeleteInfo.FromJson(Answer);
    finally
      Answer.Free;
    end;
  except
    on E: ELspClientError do
    begin
      AMessage(TAtlasStrings.Fmt(TAtlasTextId.SafeDeleteFailed, [E.Message]));
      Exit;
    end;
  end;
  Title := Info.Title;
  if Title = '' then
    Title := TAtlasStrings.Text(TAtlasTextId.SafeDeleteCommand);
  // Erst die Überschreibungen: Bleiben sie, zählen sie als Verwendung.
  Overrides := (Info.Overrides <> nil) and Decide(Info.OverridesMode, TAtlasStrings.Fmt(
    TAtlasTextId.SafeDeleteAskOverrides, [Info.Name, Length(Info.Overrides), sLineBreak,
    TAtlasSafeDelete.Listing(Lines(Info.Overrides), MaxListed, TAtlasStrings.Text(TAtlasTextId.SafeDeleteMore)),
    sLineBreak + sLineBreak]));
  Blocking := Info.Blocking(Overrides);
  Forced := False;
  if Blocking <> nil then
    case ChooseOnUsages(Info, Blocking) of
      TUsageChoice.Show:
        begin
          TAtlasIdeResultsWindow.ShowEntries(TAtlasStrings.Fmt(TAtlasTextId.SafeDeleteUsagesTitle, [Info.Name]),
            Entries(Blocking));
          Exit;
        end;
      TUsageChoice.Force:
        Forced := True;
    else
      Exit;
    end;
  Cascade := (Info.Cascade <> nil) and Decide(Info.CascadeMode, TAtlasStrings.Fmt(TAtlasTextId.SafeDeleteAskCascade,
    [sLineBreak, TAtlasSafeDelete.Listing(Info.Cascade, MaxListed, TAtlasStrings.Text(TAtlasTextId.SafeDeleteMore)),
    sLineBreak + sLineBreak]));
  Warnings := nil;
  Deleted := 0;
  try
    Answer := ASession.RunCommand(TAtlasSafeDelete.ApplyCommand, TAtlasSafeDelete.ApplyArguments(AArgumentsJson,
      Overrides, Cascade, Forced), TimeoutMs);
    try
      Reply := nil;
      if Answer is TJSONObject then
        Reply := TJSONObject(Answer);
      Edit := TLspWorkspaceEdit.FromJson(nil);
      if Reply <> nil then
      begin
        Edit := TLspWorkspaceEdit.FromJson(Reply.GetValue('edit'));
        Deleted := NumberOf(Reply, 'deleted');
        if Reply.GetValue('warnings') is TJSONArray then
          for Item in TJSONArray(Reply.GetValue('warnings')) do
            Warnings := Warnings + [Item.Value];
      end;
    finally
      Answer.Free;
    end;
  except
    on E: ELspClientError do
    begin
      AMessage(TAtlasStrings.Fmt(TAtlasTextId.SafeDeleteFailed, [E.Message]));
      Exit;
    end;
  end;
  if Edit.IsEmpty then
  begin
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.SafeDeleteFailed, [Title]));
    Exit;
  end;
  if Info.NeedsPreview(Forced) then
  begin
    Hint := TAtlasStrings.Fmt(TAtlasTextId.SafeDeletePreviewHint, [Deleted, Edit.EditCount, Length(Edit.Files)]);
    for Warning in Warnings do
      Hint := Hint + sLineBreak + TAtlasStrings.Fmt(TAtlasTextId.SafeDeleteWarning, [Warning]);
    Preview := TAtlasResults.RenamePreview(Edit,
      function(const AFileName: string): string
      begin
        Result := TAtlasIdeWorkspaceEdit.CurrentText(AFileName);
      end);
    Open :=
      procedure(const AFileName: string; ALine, ACharacter: Integer)
      begin
        TAtlasIdeNavigation.GoToLocation(AFileName, ALine, ACharacter);
      end;
    if not TAtlasRenamePreview.Execute(Title, Hint, TAtlasStrings.Text(TAtlasTextId.SafeDeleteApply),
      TAtlasResults.Group(Preview), Open) then
      Exit;
  end;
  Outcome := TAtlasIdeWorkspaceEdit.Apply(Edit, APolicy, TAtlasStrings.Text(TAtlasTextId.SafeDeleteCommand));
  if Outcome.Error <> '' then
  begin
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [Outcome.Error]));
    Exit;
  end;
  AMessage(TAtlasStrings.Fmt(TAtlasTextId.SafeDeleteDone, [Deleted, Outcome.Edits, Outcome.Files]));
  for Warning in Warnings do
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.SafeDeleteWarning, [Warning]));
  if Outcome.Written > 0 then
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.EditWritten, [Outcome.Written]));
end;

end.
