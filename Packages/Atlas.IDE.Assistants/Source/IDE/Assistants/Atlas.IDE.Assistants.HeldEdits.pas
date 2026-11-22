unit Atlas.IDE.Assistants.HeldEdits;

// Zurückgehaltene Änderungen von KI-Assistenten in der IDE (#2605, Liste und Plan in
// Atlas.Core.Assistants.HeldEdits): Der Bearbeitungseingang legt eine Änderung an einer ungespeichert geänderten
// Datei hier ab, statt sie abzulehnen. Der Mensch sieht
// - einen Eintrag in der Benachrichtigungszentrale (nur Text, Quelle „assistants“),
// - im Verhalten „einblenden“ einen Hinweis unten rechts mit „Speichern und übernehmen“, „Als Vergleich öffnen“ und
//   „Verwerfen“,
// - „KI: n Änderungen warten“ im Statusfeld; ein Klick zeigt den Hinweis für die älteste wieder.
// Speichern und übernehmen wendet die Änderung als einen Rückgängig-Schritt an (auf den aktuellen Stand übertragen,
// solange sich die Bereiche nicht überschneiden) und speichert; danach kommt die nächste Änderung an derselben Datei.
// Überschneiden sie sich, bleibt nur der Vergleich. Die Aktionen liegen nur im Hinweis und im Statusfeld, die dem
// Modul gehören, nicht in der Zentrale: Nach dem Abmelden erreicht so nichts mehr das Modul (ADR 0017, Regel 3).

interface

uses
  System.SysUtils,
  System.Types,
  Atlas.Plugin.Files.Contract,
  Atlas.Core.Assistants.EditInbox,
  Atlas.Core.Assistants.HeldEdits,
  Atlas.Core.Assistants.Log,
  Atlas.UI.Notifications.Notice;

type
  TAtlasIdeHeldEdits = class
  public const
    cFieldId = 'atlas.assistants.held';
    /// <summary>Quelle in der Benachrichtigungszentrale; nicht in den bekannten Quellen von Base.</summary>
    cSource = 'assistants';
    cActionSave = 0;
    cActionCompare = 1;
    cActionDiscard = 2;
  private
    FEdits: TAtlasHeldEdits;
    FFiles: IAtlasEditorFiles;
    FLog: TAtlasAssistantsLog;
    FToast: TAtlasNoticeWindow;
    FToastId: Integer;
    FOnMessage: TProc<string>;
    procedure Offer(const AEdit: TAtlasHeldEdit; ANotify: Boolean);
    procedure ShowToast(const AEdit: TAtlasHeldEdit);
    procedure ToastAction(AIndex: Integer);
    procedure StatusClicked(APoint: TPoint);
    /// <summary>Nach dem Ende von AEdit: die nächste an derselben Datei anbieten, sonst den Hinweis schließen.
    /// </summary>
    procedure Next(const AEdit: TAtlasHeldEdit);
  public
    /// <summary>AFiles: offene Dateien der IDE; ALog: KI-Protokoll der Composition (lebt länger), darf nil sein;
    /// AOnMessage: Zeile für die Meldungsansicht, nie nil.</summary>
    constructor Create(const AFiles: IAtlasEditorFiles; ALog: TAtlasAssistantsLog; const AOnMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>Auftrag ARequest zurückhalten und den Menschen fragen; liefert die Kennung.</summary>
    function Hold(const ARequest: TAtlasEditRequest): Integer;
    /// <summary>„Speichern und übernehmen“; False, wenn nur der Vergleich bleibt oder es AId nicht mehr gibt.
    /// </summary>
    function SaveAndApply(AId: Integer): Boolean;
    /// <summary>„Als Vergleich öffnen“: Puffer und Vorschlag; die Änderung wartet weiter.</summary>
    procedure Compare(AId: Integer);
    /// <summary>„Verwerfen“.</summary>
    procedure Discard(AId: Integer);
    /// <summary>Statusfeld nachführen.</summary>
    procedure RefreshStatus;
    /// <summary>Statusfeld „KI: n Änderungen warten“; '' ohne wartende.</summary>
    class function StatusText(ACount: Integer): string; static;
    property Edits: TAtlasHeldEdits read FEdits;
    property Toast: TAtlasNoticeWindow read FToast;
  end;

implementation

uses
  Vcl.Forms,
  Atlas.Core.Status.Contract,
  Atlas.Core.Notifications.Center,
  Atlas.Core.Notifications.Contract,
  Atlas.Plugin.Files.TextDiff,
  Atlas.Core.Editor.WorkspacePlan,
  Atlas.Core.Assistants.EditPlan,
  Atlas.Core.Assistants.EditChange,
  Atlas.IDE.Foundation.Host,
  Atlas.ToolsApi.Theme.Style,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Assistants.LogEntries,
  Atlas.Vcl.Popup.Window,
  Atlas.UI.Undo.DiffView,
  Atlas.UI.Assistants.Strings;

/// <summary>„ (Name)“ des KI-Assistenten, '' wenn unbekannt.</summary>
function ClientPart(const AClient: string): string;
begin
  Result := '';
  if AClient <> '' then
  begin
    Result := ' (' + AClient + ')';
  end;
end;

function TitleOf(const AEdit: TAtlasHeldEdit): string;
begin
  Result := TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.HeldTitle, [ExtractFileName(AEdit.FileName)]);
end;

function TextOf(const AEdit: TAtlasHeldEdit): string;
var
  mChange: TAtlasEditChange;
begin
  mChange := AEdit.Change;
  Result := TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.HeldText, [ExtractFileName(AEdit.FileName),
    ClientPart(AEdit.Client), mChange.FirstLine, mChange.LastLine]);
end;

{ TAtlasIdeHeldEdits }

constructor TAtlasIdeHeldEdits.Create(const AFiles: IAtlasEditorFiles; ALog: TAtlasAssistantsLog;
  const AOnMessage: TProc<string>);
begin
  inherited Create;
  FFiles := AFiles;
  FLog := ALog;
  FOnMessage := AOnMessage;
  FEdits := TAtlasHeldEdits.Create;
end;

destructor TAtlasIdeHeldEdits.Destroy;
begin
  // Regel 3: Hinweis und Statusfeld halten Rückrufe in dieses Objekt; beide gehen mit ihm.
  FreeAndNil(FToast);
  TAtlasIdeHost.SetStatusItem(TAtlasStatusExtra.Make(cFieldId, '', '', nil));
  FEdits.Free;
  inherited Destroy;
end;

function TAtlasIdeHeldEdits.Hold(const ARequest: TAtlasEditRequest): Integer;
var
  mEdit: TAtlasHeldEdit;
begin
  Result := FEdits.Add(ARequest.FileName, ARequest.Expected, ARequest.Text, ARequest.Client, Now);
  TAtlasIdeLogEntries.AddEdit(FLog, TAtlasAssistantsLogKind.Held, ARequest.FileName, ARequest.Client,
    ARequest.Expected, ARequest.Text);
  RefreshStatus;
  // Mehrere Änderungen an derselben Datei kommen nacheinander: Angeboten wird die älteste.
  if FEdits.TryNextFor(ARequest.FileName, mEdit) and (mEdit.Id = Result) then
  begin
    Offer(mEdit, True);
  end
  else if FEdits.TryGet(Result, mEdit) then
  begin
    TAtlasNotificationCenter.Default.Notify(cSource, TAtlasNotificationSeverity.Info, TitleOf(mEdit),
      TextOf(mEdit));
  end;
end;

procedure TAtlasIdeHeldEdits.Offer(const AEdit: TAtlasHeldEdit; ANotify: Boolean);
begin
  if not ANotify then
  begin
    ShowToast(AEdit);
    Exit;
  end;
  if TAtlasNotificationCenter.Default.Notify(cSource, TAtlasNotificationSeverity.Info, TitleOf(AEdit),
    TextOf(AEdit)) = TAtlasNotificationMode.Show then
  begin
    ShowToast(AEdit);
  end;
end;

procedure TAtlasIdeHeldEdits.ShowToast(const AEdit: TAtlasHeldEdit);
var
  mArea: TRect;
begin
  if FToast = nil then
  begin
    FToast := TAtlasNoticeWindow.Create(nil);
    FToast.OnAction := ToastAction;
  end;
  FToastId := AEdit.Id;
  mArea := Screen.WorkAreaRect;
  if Application.MainForm <> nil then
  begin
    mArea := Application.MainForm.BoundsRect;
  end;
  FToast.Colors := TAtlasIdeStyle.Colors;
  FToast.SetScaling(TAtlasPopupWindow.MonitorPPI(mArea.BottomRight), 1, '', 10);
  FToast.ShowNotice(TitleOf(AEdit), TextOf(AEdit), TArray<string>.Create(
    TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.HeldSaveApply),
    TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.HeldCompare),
    TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.HeldDiscard)), mArea);
end;

procedure TAtlasIdeHeldEdits.ToastAction(AIndex: Integer);
begin
  case AIndex of
    cActionSave:
      SaveAndApply(FToastId);
    cActionCompare:
      Compare(FToastId);
    cActionDiscard:
      Discard(FToastId);
  end;
end;

procedure TAtlasIdeHeldEdits.StatusClicked(APoint: TPoint);
var
  mEdit: TAtlasHeldEdit;
begin
  if FEdits.TryFirst(mEdit) then
  begin
    Offer(mEdit, False);
  end;
end;

procedure TAtlasIdeHeldEdits.Next(const AEdit: TAtlasHeldEdit);
var
  mNext: TAtlasHeldEdit;
begin
  RefreshStatus;
  if FEdits.TryNextFor(AEdit.FileName, mNext) then
  begin
    Offer(mNext, False);
  end
  else if (FToast <> nil) and (FToastId = AEdit.Id) then
  begin
    FToast.Dismiss;
  end;
end;

function TAtlasIdeHeldEdits.SaveAndApply(AId: Integer): Boolean;
var
  mEdit: TAtlasHeldEdit;
  mBuffer: TAtlasEditorFile;
  mNewText, mError: string;
begin
  Result := False;
  if not FEdits.TryGet(AId, mEdit) then
  begin
    Exit;
  end;
  mBuffer := FFiles.Buffer(mEdit.FileName);
  if not mBuffer.Open then
  begin
    FEdits.Remove(AId);
    TAtlasIdeLogEntries.AddPlain(FLog, TAtlasAssistantsLogKind.Discarded, mEdit.FileName, mEdit.Client, '');
    FOnMessage(TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.HeldNotOpen, [ExtractFileName(mEdit.FileName)]));
    Next(mEdit);
    Exit;
  end;
  if not TAtlasHeldEdits.Plan(mEdit, mBuffer.Text, mNewText) then
  begin
    // Überschneidet sich mit den Änderungen des Menschen: nur der Vergleich.
    FOnMessage(TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.HeldOverlaps, [ExtractFileName(mEdit.FileName)]));
    Compare(AId);
    Exit;
  end;
  mError := TAtlasIdeWorkspaceEdit.Apply(TAtlasEditInboxPlan.EditOf(mEdit.FileName, mBuffer.Text, mNewText),
    TAtlasUnopenedPolicy.OpenInEditor, TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.UndoActionMcp)).Error;
  if mError <> '' then
  begin
    FOnMessage(TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.HeldFailed,
      [ExtractFileName(mEdit.FileName), mError]));
    Exit;
  end;
  FFiles.Save(mEdit.FileName);
  FEdits.Remove(AId);
  TAtlasIdeLogEntries.AddEdit(FLog, TAtlasAssistantsLogKind.Edited, mEdit.FileName, mEdit.Client, mBuffer.Text,
    mNewText);
  FOnMessage(TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.HeldApplied, [ExtractFileName(mEdit.FileName)]));
  Next(mEdit);
  Result := True;
end;

procedure TAtlasIdeHeldEdits.Compare(AId: Integer);
var
  mEdit: TAtlasHeldEdit;
  mBuffer: TAtlasEditorFile;
  mCurrent: string;
begin
  if not FEdits.TryGet(AId, mEdit) then
  begin
    Exit;
  end;
  mBuffer := FFiles.Buffer(mEdit.FileName);
  mCurrent := mEdit.Expected;
  if mBuffer.Open then
  begin
    mCurrent := mBuffer.Text;
  end;
  TAtlasUndoDiffView.Execute(TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.HeldCompareTitle,
    [ExtractFileName(mEdit.FileName)]), TAtlasTextDiff.Lines(mCurrent, mEdit.Text));
end;

procedure TAtlasIdeHeldEdits.Discard(AId: Integer);
var
  mEdit: TAtlasHeldEdit;
begin
  if not FEdits.TryGet(AId, mEdit) then
  begin
    Exit;
  end;
  FEdits.Remove(AId);
  TAtlasIdeLogEntries.AddEdit(FLog, TAtlasAssistantsLogKind.Discarded, mEdit.FileName, mEdit.Client,
    mEdit.Expected, mEdit.Text);
  FOnMessage(TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.HeldDiscarded, [ExtractFileName(mEdit.FileName)]));
  Next(mEdit);
end;

class function TAtlasIdeHeldEdits.StatusText(ACount: Integer): string;
begin
  if ACount <= 0 then
  begin
    Result := '';
  end
  else if ACount = 1 then
  begin
    Result := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.HeldStatusOne);
  end
  else
  begin
    Result := TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.HeldStatusMany, [ACount]);
  end;
end;

procedure TAtlasIdeHeldEdits.RefreshStatus;
var
  mExtra: TAtlasStatusExtra;
begin
  mExtra := Default(TAtlasStatusExtra);
  mExtra.Id := cFieldId;
  mExtra.Text := StatusText(FEdits.Count);
  if mExtra.Text <> '' then
  begin
    mExtra.Hint := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.HeldStatusHint);
    mExtra.State := TAtlasStatusState.Yellow;
    mExtra.OnClick := StatusClicked;
  end;
  TAtlasIdeHost.SetStatusItem(mExtra);
end;

end.
