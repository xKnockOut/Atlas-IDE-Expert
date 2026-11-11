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
    cClientCommand = 'atlas.safeDelete';
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
  Atlas.UI.Editor.Strings,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Results.Model,
  Atlas.Core.Editor.SafeDelete,
  Atlas.IDE.Editor.Rename,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Editor.ServerEdit,
  Atlas.IDE.Foundation.ResultsWindow,
  Atlas.Text.Json;

const
  // Referenzsuche im Projekt, Nachfahren und uses aller Units: dauert.
  cTimeoutMs = 120000;
  // Zeilen in einer Rückfrage.
  cMaxListed = 12;

type
  {$SCOPEDENUMS ON}
  TUsageChoice = (Cancel, Show, Force);
  {$SCOPEDENUMS OFF}

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
  mUsage: TAtlasSafeDeleteUsage;
begin
  Result := nil;
  for mUsage in AUsages do
  begin
    Result := Result + [Format('%s:%d  %s', [ExtractFileName(mUsage.FileName), mUsage.Line + 1, mUsage.Text])];
  end;
end;

function Entries(const AUsages: TArray<TAtlasSafeDeleteUsage>): TArray<TAtlasResultEntry>;
var
  mUsage: TAtlasSafeDeleteUsage;
  mEntry: TAtlasResultEntry;
begin
  Result := nil;
  for mUsage in AUsages do
  begin
    mEntry := TAtlasResultEntry.Create(mUsage.FileName, mUsage.Line, mUsage.Character);
    mEntry.Text := mUsage.Text;
    Result := Result + [mEntry];
  end;
end;

/// <summary>Abbrechen, Anzeigen oder Trotzdem löschen.</summary>
function ChooseOnUsages(const AInfo: TAtlasSafeDeleteInfo; const AUsages: TArray<TAtlasSafeDeleteUsage>):
  TUsageChoice;
var
  mDialog: TForm;
  mIndex: Integer;
  mButton: TButton;
begin
  mDialog := CreateMessageDialog(TAtlasEditorStrings.Fmt(TAtlasEditorTextId.SafeDeleteUsages, [AInfo.Name,
    Length(AUsages)]) +
    sLineBreak + sLineBreak + TAtlasSafeDelete.Listing(Lines(AUsages), cMaxListed,
    TAtlasEditorStrings.Text(TAtlasEditorTextId.SafeDeleteMore)), TMsgDlgType.mtWarning,
    [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbAll, TMsgDlgBtn.mbCancel], TMsgDlgBtn.mbCancel);
  try
    mDialog.Caption := TAtlasStrings.Text(TAtlasTextId.SafeDeleteCommand);
    for mIndex := 0 to mDialog.ComponentCount - 1 do
    begin
      if mDialog.Components[mIndex] is TButton then
      begin
        mButton := TButton(mDialog.Components[mIndex]);
        case mButton.ModalResult of
          mrYes:
            mButton.Caption := TAtlasEditorStrings.Text(TAtlasEditorTextId.SafeDeleteShow);
          mrAll:
            mButton.Caption := TAtlasEditorStrings.Text(TAtlasEditorTextId.SafeDeleteForce);
          mrCancel:
            mButton.Caption := TAtlasEditorStrings.Text(TAtlasEditorTextId.SafeDeleteCancel);
        end;
      end;
    end;
    case mDialog.ShowModal of
      mrYes:
        Result := TUsageChoice.Show;
      mrAll:
        Result := TUsageChoice.Force;
    else
      Result := TUsageChoice.Cancel;
    end;
  finally
    mDialog.Free;
  end;
end;

/// <summary>Was der Server zum Element sagt (Name, Überschreibungen, Verwendungen …); False mit Meldung, wenn er
/// scheitert.</summary>
function FetchInfo(ASession: TLspSession; const AArgumentsJson: string; const AMessage: TProc<string>;
  out AInfo: TAtlasSafeDeleteInfo): Boolean;
var
  mAnswer: TJSONValue;
begin
  Result := False;
  TAtlasIdeRename.SyncOpenBuffers(ASession);
  try
    mAnswer := ASession.RunCommand(TAtlasSafeDelete.cPrepareCommand, AArgumentsJson, cTimeoutMs);
    try
      AInfo := TAtlasSafeDeleteInfo.FromJson(mAnswer);
    finally
      mAnswer.Free;
    end;
    Result := True;
  except
    on E: ELspClientError do
    begin
      AMessage(TAtlasStrings.Fmt(TAtlasTextId.SafeDeleteFailed, [E.Message]));
    end;
  end;
end;

/// <summary>Fragt (je nach Einstellung) nach Überschreibungen, verbleibenden Verwendungen und abhängigen Elementen.
/// False, wenn der Benutzer abbricht oder die Verwendungen anzeigen lässt.</summary>
function AskOptions(const AInfo: TAtlasSafeDeleteInfo; out AOverrides, ACascade, AForced: Boolean): Boolean;
var
  mBlocking: TArray<TAtlasSafeDeleteUsage>;
begin
  ACascade := False;
  AForced := False;
  // Erst die Überschreibungen: Bleiben sie, zählen sie als Verwendung.
  AOverrides := (AInfo.Overrides <> nil) and Decide(AInfo.OverridesMode, TAtlasStrings.Fmt(
    TAtlasTextId.SafeDeleteAskOverrides, [AInfo.Name, Length(AInfo.Overrides), sLineBreak,
    TAtlasSafeDelete.Listing(Lines(AInfo.Overrides), cMaxListed,
    TAtlasEditorStrings.Text(TAtlasEditorTextId.SafeDeleteMore)),
    sLineBreak + sLineBreak]));
  mBlocking := AInfo.Blocking(AOverrides);
  Result := mBlocking = nil;
  if not Result then
  begin
    case ChooseOnUsages(AInfo, mBlocking) of
      TUsageChoice.Show:
        TAtlasIdeResultsWindow.ShowEntries(TAtlasEditorStrings.Fmt(TAtlasEditorTextId.SafeDeleteUsagesTitle,
          [AInfo.Name]),
          Entries(mBlocking));
      TUsageChoice.Force:
        begin
          AForced := True;
          Result := True;
        end;
    else
      // Abbrechen: nichts tun.
    end;
  end;
  if Result then
  begin
    ACascade := (AInfo.Cascade <> nil) and Decide(AInfo.CascadeMode, TAtlasStrings.Fmt(
      TAtlasTextId.SafeDeleteAskCascade, [sLineBreak, TAtlasSafeDelete.Listing(AInfo.Cascade, cMaxListed,
      TAtlasEditorStrings.Text(TAtlasEditorTextId.SafeDeleteMore)), sLineBreak + sLineBreak]));
  end;
end;

class procedure TAtlasIdeSafeDelete.Execute(ASession: TLspSession; const AArgumentsJson: string;
  APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
var
  mInfo: TAtlasSafeDeleteInfo;
  mOverrides, mCascade, mForced: Boolean;
  mTitle, mHint: string;
  mDeleted: Integer;
  mReply: TAtlasServerEditReply;
  mOutcome: TAtlasWorkspaceEditResult;
begin
  if ASession = nil then
  begin
    AMessage(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Exit;
  end;
  if not FetchInfo(ASession, AArgumentsJson, AMessage, mInfo) or
    not AskOptions(mInfo, mOverrides, mCascade, mForced) then
  begin
    Exit;
  end;
  mTitle := mInfo.Title;
  if mTitle = '' then
  begin
    mTitle := TAtlasStrings.Text(TAtlasTextId.SafeDeleteCommand);
  end;
  mDeleted := 0;
  if not TAtlasIdeServerEdit.Fetch(ASession, TAtlasServerEditCommand.Create(TAtlasSafeDelete.cApplyCommand,
    TAtlasSafeDelete.ApplyArguments(AArgumentsJson, mOverrides, mCascade, mForced), cTimeoutMs,
    TAtlasTextId.SafeDeleteFailed),
    procedure(const AReply: TJSONObject)
    begin
      mDeleted := TJsonRead.Int(AReply, 'deleted');
    end, AMessage, mReply) then
  begin
    Exit;
  end;
  if mReply.Edit.IsEmpty then
  begin
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.SafeDeleteFailed, [mTitle]));
    Exit;
  end;
  mHint := TAtlasEditorStrings.Fmt(TAtlasEditorTextId.SafeDeletePreviewHint, [mDeleted, mReply.Edit.EditCount,
    Length(mReply.Edit.Files)]) + TAtlasIdeServerEdit.WarningLines(mReply, TAtlasTextId.SafeDeleteWarning);
  if (not mInfo.NeedsPreview(mForced) or TAtlasIdeServerEdit.Confirm(mTitle, mHint,
    TAtlasEditorStrings.Text(TAtlasEditorTextId.SafeDeleteApply),
    mReply.Edit)) and TAtlasIdeServerEdit.Apply(mReply.Edit,
    APolicy, TAtlasStrings.Text(TAtlasTextId.SafeDeleteCommand), AMessage, mOutcome) then
  begin
    AMessage(TAtlasEditorStrings.Fmt(TAtlasEditorTextId.SafeDeleteDone, [mDeleted, mOutcome.Edits, mOutcome.Files]));
    TAtlasIdeServerEdit.ReportAfter(mReply, mOutcome, TAtlasTextId.SafeDeleteWarning, AMessage);
  end;
end;

end.
