unit Atlas.UI.Tracker.CommentEditor;

// Kommentarfeld von Atlas (#1278), reine VCL ohne Open Tools API, für die
// Vorschau (#1264) und den Beenden-Dialog (#1266); Beschreibung (#1268) und
// Rückfrage beim Ziehen (#1272) setzen es genauso ein:
//   ┌──────────────────────────────────────────────┐
//   │ Behoben in 4f2c9e1, @an                      │  Memo (Markdown)
//   │   ┌──────────────────────────┐               │
//   │   │ @anna · Anna Berger      │               │  Vorschläge an der
//   │   │ @andreas · Andreas Koch  │               │  Schreibmarke
//   └───┴──────────────────────────┴───────────────┘
//   [Vorschau] [Textbaustein ▾]   Entwurf gespeichert  [Verwerfen]
// - "@" mit Buchstaben schlägt Benutzer vor, "#…" bzw. "ATL-…" Issues (über
//   IAtlasCommentAssist im Hintergrund, 300 ms nach der letzten Eingabe).
//   Pfeile wählen, Enter oder Tab fügen ein, Esc schließt die Liste.
// - Strg+Leer oder „Textbaustein ▾“: Textbausteine mit Platzhaltern.
// - Strg+B fett, Strg+I kursiv, Strg+Umschalt+K Code-Block (pascal);
//   „Vorschau“ setzt den Text mit demselben Renderer wie die Vorschau (#1264).
// - Entwurf: beim Binden angeboten (leeres Feld: gleich eingesetzt, sonst
//   „Übernehmen“), 2 s nach der letzten Änderung und beim Lösen gespeichert,
//   nach dem Senden (Sent) gelöscht. Unveränderte Vorgaben (Vorlage des
//   Beenden-Dialogs) werden nicht als Entwurf gespeichert.
// - Strg+Enter löst OnSend aus, Esc (ohne Liste) OnCancel.
// - Enhanced = False (issues.commentEditor aus): ein einfaches Textfeld wie
//   bisher, nur Strg+Enter sendet.
// Die Liste liegt auf der Form (nicht im Feld), damit sie nicht abgeschnitten
// wird; das Memo behält den Fokus.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  System.Generics.Collections,
  Winapi.Messages,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Forms,
  Vcl.Menus,
  Atlas.Core.Style.Palette,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.CommentEditor;

type
  TAtlasCommentEditor = class(TCustomPanel)
  public const
    /// <summary>Wartezeit nach der letzten Eingabe bis zur Anfrage.</summary>
    DelayMs = 300;
    /// <summary>Wartezeit nach der letzten Änderung bis zum Speichern des Entwurfs.</summary>
    DraftDelayMs = 2000;
    ListWidth = 340;
  private
    FMemo: TMemo;
    FBar: TPanel;
    FPreviewButton: TButton;
    FSnippetButton: TButton;
    FDraftNote: TLabel;
    FDraftButton: TButton;
    FPreview: TScrollBox;
    FList: TListBox;
    FSnippetMenu: TPopupMenu;
    FTimer: TTimer;
    FDraftTimer: TTimer;
    FAssist: IAtlasCommentAssist;
    FEnhanced: Boolean;
    FTrigger: TAtlasCommentTrigger;
    FUsers: TArray<TAtlasTrackerUser>;
    FIssues: TArray<TAtlasTrackerIssue>;
    FRows: TArray<string>;
    FSelected: Integer;
    FListKind: TAtlasCommentTriggerKind;
    FPreviewing: Boolean;
    FInitialText: string;
    FOfferedDraft: string;
    FDraftRestored: Boolean;
    FSwallowChar: Boolean;
    FChanging: Boolean;
    FGeneration: Integer;
    FRequestDelay: Integer;
    FColors: TAtlasColors;
    FMono: TFont;
    FPreviewParts: TList<TControl>;
    FOnSend: TNotifyEvent;
    FOnCancel: TNotifyEvent;
    procedure MemoChange(Sender: TObject);
    procedure MemoKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure MemoKeyPress(Sender: TObject; var Key: Char);
    procedure MemoClick(Sender: TObject);
    procedure MemoExit(Sender: TObject);
    procedure ListClick(Sender: TObject);
    procedure TimerTick(Sender: TObject);
    procedure DraftTimerTick(Sender: TObject);
    procedure PreviewClick(Sender: TObject);
    procedure SnippetClick(Sender: TObject);
    procedure SnippetItemClick(Sender: TObject);
    procedure DraftButtonClick(Sender: TObject);
    procedure SetEnhanced(AValue: Boolean);
    procedure SetPreviewing(AValue: Boolean);
    procedure SetMonoFont(AValue: TFont);
    function GetText: string;
    procedure Request;
    procedure UsersAnswered(AGeneration: Integer; const AUsers: TArray<TAtlasTrackerUser>);
    procedure IssuesAnswered(AGeneration: Integer; const AIssues: TArray<TAtlasTrackerIssue>);
    procedure ShowRows(AKind: TAtlasCommentTriggerKind; const ARows: TArray<string>);
    procedure PlaceList;
    procedure MoveSelection(ADelta: Integer);
    procedure ApplyEdit(const AText: string; AStart, ALength: Integer);
    procedure BuildPreview;
    procedure ClearPreview;
    procedure ShowDraftNote(const AText, AButton: string);
    procedure SnippetReady(const AText: string; const AValues: TAtlasCommentValues);
    procedure RestartDraftTimer;
    function ListShown: Boolean;
    procedure PopupSnippets(const AScreen: TPoint);
    function CaretScreenPoint: TPoint;
    function Changed: Boolean;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>An Tracker, Issue und Feld binden (über AAssist); bietet den Entwurf an. nil löst nur.</summary>
    procedure Bind(const AAssist: IAtlasCommentAssist);
    /// <summary>Entwurf speichern und lösen (Wechsel des Issues, Schließen).</summary>
    procedure Unbind;
    /// <summary>Entwurf jetzt speichern, wenn sich der Text gegenüber der Vorgabe geändert hat.</summary>
    procedure KeepDraft;
    /// <summary>Gesendet: Entwurf löschen, Feld leeren.</summary>
    procedure Sent;
    /// <summary>Vorgabe setzen (Zeilen mit #10 oder #13#10); gilt nicht als Entwurf.</summary>
    procedure SetText(const AText: string);
    /// <summary>Vorschlagsliste schließen und offene Anfragen verwerfen.</summary>
    procedure HideList;
    /// <summary>Vorschlag AIndex der Liste einfügen.</summary>
    procedure Accept(AIndex: Integer);
    /// <summary>Textbaustein AIndex an der Schreibmarke einfügen (Platzhalter über die IDE).</summary>
    procedure InsertSnippet(AIndex: Integer);
    /// <summary>Strg+B, Strg+I bzw. Strg+Umschalt+K auf die Auswahl anwenden.</summary>
    procedure Bold;
    procedure Italic;
    procedure CodeBlock;
    /// <summary>Auslöser an der Schreibmarke neu bestimmen (nach Eingabe, für Tests auch direkt).</summary>
    procedure CheckTrigger;
    procedure ApplyColors(const AColors: TAtlasColors);
    /// <summary>Text mit #10 als Zeilenumbruch, wie er an den Tracker geht.</summary>
    property Text: string read GetText;
    property Memo: TMemo read FMemo;
    property Assist: IAtlasCommentAssist read FAssist;
    /// <summary>issues.commentEditor: Ergänzung, Textbausteine, Vorschau und Entwürfe.</summary>
    property Enhanced: Boolean read FEnhanced write SetEnhanced;
    property Previewing: Boolean read FPreviewing write SetPreviewing;
    property Trigger: TAtlasCommentTrigger read FTrigger;
    /// <summary>Zeilen der Vorschlagsliste und die gewählte (-1 ohne).</summary>
    property Rows: TArray<string> read FRows;
    property Selected: Integer read FSelected;
    property PreviewButton: TButton read FPreviewButton;
    property SnippetButton: TButton read FSnippetButton;
    property DraftNote: TLabel read FDraftNote;
    property DraftButton: TButton read FDraftButton;
    property PreviewBox: TScrollBox read FPreview;
    /// <summary>Entwurf, der angeboten, aber nicht eingesetzt wurde; '' ohne.</summary>
    property OfferedDraft: string read FOfferedDraft;
    property MonoFont: TFont read FMono write SetMonoFont;
    /// <summary>Wartezeit vor der Anfrage (Vorgabe DelayMs); 0 fragt sofort (Tests).</summary>
    property RequestDelay: Integer read FRequestDelay write FRequestDelay;
    property OnSend: TNotifyEvent read FOnSend write FOnSend;
    property OnCancel: TNotifyEvent read FOnCancel write FOnCancel;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  System.DateUtils,
  System.UITypes,
  Atlas.Core.Style.Color,
  Atlas.Core.Tracker.Markdown,
  Atlas.Core.Tracker.PaletteSearch,
  Atlas.UI.Strings,
  Atlas.UI.Tracker.IssueFrame;

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

function MemoText(const AText: string): string;
begin
  Result := AdjustLineBreaks(AText, tlbsCRLF);
end;

{ TAtlasCommentEditor }

constructor TAtlasCommentEditor.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  ShowCaption := False;
  Caption := '';
  FEnhanced := True;
  FSelected := -1;
  FRequestDelay := DelayMs;
  FTrigger := TAtlasCommentTrigger.None;
  FColors := TAtlasColors.Light;
  FMono := TFont.Create;
  FMono.Name := 'Consolas';
  FMono.Size := 10;
  FPreviewParts := TList<TControl>.Create;

  FBar := TPanel.Create(Self);
  FBar.Parent := Self;
  FBar.Align := alBottom;
  FBar.BevelOuter := bvNone;
  FBar.ShowCaption := False;
  FBar.Height := 30;
  FPreviewButton := TButton.Create(Self);
  FPreviewButton.Parent := FBar;
  FPreviewButton.Align := alLeft;
  FPreviewButton.AlignWithMargins := True;
  FPreviewButton.Width := 90;
  FPreviewButton.Caption := TAtlasStrings.Text(TAtlasTextId.CommentEditorPreview);
  FPreviewButton.OnClick := PreviewClick;
  FSnippetButton := TButton.Create(Self);
  FSnippetButton.Parent := FBar;
  FSnippetButton.Align := alLeft;
  FSnippetButton.AlignWithMargins := True;
  FSnippetButton.Left := 100;
  FSnippetButton.Width := 120;
  FSnippetButton.Caption := TAtlasStrings.Text(TAtlasTextId.CommentEditorSnippets);
  FSnippetButton.OnClick := SnippetClick;
  FDraftButton := TButton.Create(Self);
  FDraftButton.Parent := FBar;
  FDraftButton.Align := alRight;
  FDraftButton.AlignWithMargins := True;
  FDraftButton.Width := 100;
  FDraftButton.Visible := False;
  FDraftButton.OnClick := DraftButtonClick;
  FDraftNote := TLabel.Create(Self);
  FDraftNote.Parent := FBar;
  FDraftNote.Align := alClient;
  FDraftNote.AlignWithMargins := True;
  FDraftNote.Margins.Top := 7;
  FDraftNote.Alignment := taRightJustify;
  FDraftNote.ShowAccelChar := False;
  FDraftNote.Font.Color := clGrayText;
  FDraftNote.Caption := '';

  FMemo := TMemo.Create(Self);
  FMemo.Parent := Self;
  FMemo.Align := alClient;
  FMemo.ScrollBars := ssVertical;
  FMemo.WantReturns := True;
  FMemo.WantTabs := False;
  FMemo.Hint := TAtlasStrings.Text(TAtlasTextId.CommentEditorHint);
  FMemo.ShowHint := True;
  FMemo.OnChange := MemoChange;
  FMemo.OnKeyDown := MemoKeyDown;
  FMemo.OnKeyPress := MemoKeyPress;
  FMemo.OnClick := MemoClick;
  FMemo.OnExit := MemoExit;

  FPreview := TScrollBox.Create(Self);
  FPreview.Parent := Self;
  FPreview.Align := alClient;
  FPreview.Visible := False;
  FPreview.VertScrollBar.Tracking := True;

  FSnippetMenu := TPopupMenu.Create(Self);
  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := DelayMs;
  FTimer.OnTimer := TimerTick;
  FDraftTimer := TTimer.Create(Self);
  FDraftTimer.Enabled := False;
  FDraftTimer.Interval := DraftDelayMs;
  FDraftTimer.OnTimer := DraftTimerTick;
end;

destructor TAtlasCommentEditor.Destroy;
begin
  // Nichts darf nach dem Freigeben ankommen: offene Anfragen verwerfen. Den Entwurf sichert der Gastgeber mit
  // Unbind, solange das Fenster lebt; hier nur noch, wenn das Memo sein Fenster hat (ohne Fenster wäre der Text
  // veraltet und könnte den Entwurf löschen).
  if FAssist <> nil then
  begin
    if (FMemo <> nil) and FMemo.HandleAllocated then
      KeepDraft;
    FAssist.Cancel;
    FAssist := nil;
  end;
  if FTimer <> nil then
    FTimer.Enabled := False;
  if FDraftTimer <> nil then
    FDraftTimer.Enabled := False;
  FPreviewParts.Free;
  FPreviewParts := nil;
  FMono.Free;
  inherited;
end;

procedure TAtlasCommentEditor.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  // Die Liste liegt auf der Form; geht die zuerst, gibt sie die Liste mit frei.
  if (Operation = opRemove) and (AComponent = FList) then
    FList := nil;
end;

function TAtlasCommentEditor.GetText: string;
begin
  Result := StringReplace(FMemo.Text, #13#10, #10, [rfReplaceAll]);
end;

procedure TAtlasCommentEditor.SetText(const AText: string);
begin
  HideList;
  FChanging := True;
  try
    FMemo.Text := MemoText(AText);
  finally
    FChanging := False;
  end;
  FInitialText := FMemo.Text;
end;

function TAtlasCommentEditor.Changed: Boolean;
begin
  Result := FMemo.Text <> FInitialText;
end;

procedure TAtlasCommentEditor.ShowDraftNote(const AText, AButton: string);
begin
  FDraftNote.Caption := AText;
  FDraftButton.Caption := AButton;
  FDraftButton.Visible := AButton <> '';
end;

procedure TAtlasCommentEditor.Bind(const AAssist: IAtlasCommentAssist);
var
  mText, mWhen: string;
  mSaved: TDateTime;
begin
  if FAssist <> nil then
    Unbind;
  FAssist := AAssist;
  FOfferedDraft := '';
  FDraftRestored := False;
  ShowDraftNote('', '');
  FInitialText := FMemo.Text;
  if (FAssist = nil) or not FEnhanced then
    Exit;
  if not FAssist.LoadDraft(mText, mSaved) or (Trim(mText) = '') or (MemoText(mText) = FMemo.Text) then
    Exit;
  mWhen := FormatDateTime('dd.mm. hh:nn', TTimeZone.Local.ToLocalTime(mSaved));
  if Trim(FMemo.Text) = '' then
  begin
    // Leeres Feld: der Entwurf gleich darin, mit „Verwerfen“.
    FChanging := True;
    try
      FMemo.Text := MemoText(mText);
    finally
      FChanging := False;
    end;
    FDraftRestored := True;
    ShowDraftNote(TAtlasStrings.Fmt(TAtlasTextId.CommentEditorDraftRestored, [mWhen]),
      TAtlasStrings.Text(TAtlasTextId.CommentEditorDraftDiscard));
  end
  else
  begin
    // Vorgefülltes Feld (Vorlage beim Beenden): Entwurf nur anbieten.
    FOfferedDraft := mText;
    ShowDraftNote(TAtlasStrings.Fmt(TAtlasTextId.CommentEditorDraftOffered, [mWhen]),
      TAtlasStrings.Text(TAtlasTextId.CommentEditorDraftApply));
  end;
end;

procedure TAtlasCommentEditor.Unbind;
begin
  KeepDraft;
  HideList;
  if FAssist <> nil then
    FAssist.Cancel;
  FAssist := nil;
  FOfferedDraft := '';
  ShowDraftNote('', '');
end;

procedure TAtlasCommentEditor.KeepDraft;
begin
  if FDraftTimer <> nil then
    FDraftTimer.Enabled := False;
  if (FAssist = nil) or not FEnhanced or not Changed then
    Exit;
  // Leer gemacht heißt: kein Entwurf mehr.
  FAssist.SaveDraft(Text);
end;

procedure TAtlasCommentEditor.Sent;
begin
  FDraftTimer.Enabled := False;
  if FAssist <> nil then
    FAssist.DeleteDraft;
  HideList;
  Previewing := False;
  FChanging := True;
  try
    FMemo.Clear;
  finally
    FChanging := False;
  end;
  FInitialText := '';
  FOfferedDraft := '';
  FDraftRestored := False;
  ShowDraftNote('', '');
end;

procedure TAtlasCommentEditor.DraftButtonClick(Sender: TObject);
begin
  if FOfferedDraft <> '' then
  begin
    FChanging := True;
    try
      FMemo.Text := MemoText(FOfferedDraft);
    finally
      FChanging := False;
    end;
    FOfferedDraft := '';
    ShowDraftNote('', '');
    RestartDraftTimer;
  end
  else if FDraftRestored then
  begin
    if FAssist <> nil then
      FAssist.DeleteDraft;
    FChanging := True;
    try
      FMemo.Text := FInitialText;
    finally
      FChanging := False;
    end;
    FDraftRestored := False;
    ShowDraftNote('', '');
  end;
  if FMemo.CanFocus and FMemo.Showing then
    FMemo.SetFocus;
end;

procedure TAtlasCommentEditor.RestartDraftTimer;
begin
  if not FEnhanced or (FAssist = nil) then
    Exit;
  FDraftTimer.Enabled := False;
  FDraftTimer.Enabled := True;
end;

procedure TAtlasCommentEditor.DraftTimerTick(Sender: TObject);
begin
  FDraftTimer.Enabled := False;
  if (FAssist = nil) or not Changed then
    Exit;
  KeepDraft;
  if not FDraftButton.Visible then
    ShowDraftNote(TAtlasStrings.Text(TAtlasTextId.CommentEditorDraftSaved), '');
end;

procedure TAtlasCommentEditor.SetEnhanced(AValue: Boolean);
begin
  FEnhanced := AValue;
  FBar.Visible := AValue;
  FMemo.ShowHint := AValue;
  if AValue then
    Exit;
  HideList;
  Previewing := False;
  ShowDraftNote('', '');
end;

procedure TAtlasCommentEditor.SetMonoFont(AValue: TFont);
begin
  FMono.Assign(AValue);
  if FPreviewing then
    BuildPreview;
end;

procedure TAtlasCommentEditor.ApplyColors(const AColors: TAtlasColors);
begin
  FColors := AColors;
  FPreview.Color := ToColor(AColors.Surface);
  FPreview.ParentBackground := False;
  if FPreviewing then
    BuildPreview;
end;

procedure TAtlasCommentEditor.MemoChange(Sender: TObject);
begin
  if FChanging then
    Exit;
  RestartDraftTimer;
  CheckTrigger;
end;

procedure TAtlasCommentEditor.MemoClick(Sender: TObject);
begin
  // Die Schreibmarke kann in ein anderes Wort gesprungen sein.
  if ListShown or (FTrigger.Kind <> TAtlasCommentTriggerKind.None) then
    CheckTrigger;
end;

procedure TAtlasCommentEditor.MemoExit(Sender: TObject);
var
  mForm: TCustomForm;
begin
  // Ein Klick in die Liste nimmt dem Memo den Fokus: dann bleibt sie offen.
  mForm := GetParentForm(Self);
  if (FList <> nil) and (mForm <> nil) and (mForm.ActiveControl = FList) then
    Exit;
  HideList;
end;

function TAtlasCommentEditor.ListShown: Boolean;
begin
  Result := Length(FRows) > 0;
end;

procedure TAtlasCommentEditor.CheckTrigger;
var
  mTrigger: TAtlasCommentTrigger;
begin
  if not FEnhanced or (FAssist = nil) or FMemo.ReadOnly or FPreviewing or (FMemo.SelLength > 0) then
  begin
    HideList;
    Exit;
  end;
  mTrigger := TAtlasCommentEditing.Trigger(FMemo.Text, FMemo.SelStart, FAssist.Target);
  if mTrigger.Kind = TAtlasCommentTriggerKind.None then
  begin
    HideList;
    Exit;
  end;
  if mTrigger.SameAs(FTrigger) then
  begin
    // Dasselbe Wort an neuer Stelle (Text davor geändert): nur die Lage merken.
    FTrigger := mTrigger;
    Exit;
  end;
  FTrigger := mTrigger;
  Inc(FGeneration);
  FTimer.Enabled := False;
  // Zuletzt geöffnete Issues ("ATL-") brauchen kein Netz: sofort.
  if (FRequestDelay <= 0) or ((mTrigger.Kind = TAtlasCommentTriggerKind.Issue) and
    (mTrigger.Query.Kind = TAtlasIssueSearchKind.Recent)) then
    Request
  else
  begin
    FTimer.Interval := Cardinal(FRequestDelay);
    FTimer.Enabled := True;
  end;
end;

procedure TAtlasCommentEditor.TimerTick(Sender: TObject);
begin
  FTimer.Enabled := False;
  Request;
end;

procedure TAtlasCommentEditor.Request;
var
  mSelf: TAtlasCommentEditor;
  mGeneration: Integer;
begin
  FTimer.Enabled := False;
  if (FAssist = nil) or (FTrigger.Kind = TAtlasCommentTriggerKind.None) then
    Exit;
  mSelf := Self;
  mGeneration := FGeneration;
  if FTrigger.Kind = TAtlasCommentTriggerKind.Mention then
    FAssist.FindUsers(FTrigger.Text,
      procedure(const AUsers: TArray<TAtlasTrackerUser>)
      begin
        mSelf.UsersAnswered(mGeneration, AUsers);
      end)
  else
    FAssist.FindIssues(FTrigger.Query,
      procedure(const AIssues: TArray<TAtlasTrackerIssue>)
      begin
        mSelf.IssuesAnswered(mGeneration, AIssues);
      end);
end;

procedure TAtlasCommentEditor.UsersAnswered(AGeneration: Integer; const AUsers: TArray<TAtlasTrackerUser>);
var
  mRows: TArray<string>;
  mIndex: Integer;
begin
  // Weitergetippt, geschlossen oder anderes Wort: Die Antwort zählt nicht mehr.
  if (AGeneration <> FGeneration) or (FTrigger.Kind <> TAtlasCommentTriggerKind.Mention) then
    Exit;
  FUsers := Copy(AUsers, 0, TAtlasCommentEditing.MaxSuggestions);
  FIssues := nil;
  SetLength(mRows, Length(FUsers));
  for mIndex := 0 to High(FUsers) do
    mRows[mIndex] := TAtlasCommentEditing.UserRow(FUsers[mIndex]);
  ShowRows(TAtlasCommentTriggerKind.Mention, mRows);
end;

procedure TAtlasCommentEditor.IssuesAnswered(AGeneration: Integer; const AIssues: TArray<TAtlasTrackerIssue>);
var
  mRows: TArray<string>;
  mIndex: Integer;
begin
  if (AGeneration <> FGeneration) or (FTrigger.Kind <> TAtlasCommentTriggerKind.Issue) then
    Exit;
  FIssues := Copy(AIssues, 0, TAtlasCommentEditing.MaxSuggestions);
  FUsers := nil;
  SetLength(mRows, Length(FIssues));
  for mIndex := 0 to High(FIssues) do
    mRows[mIndex] := TAtlasCommentEditing.IssueRow(FIssues[mIndex]);
  ShowRows(TAtlasCommentTriggerKind.Issue, mRows);
end;

procedure TAtlasCommentEditor.ShowRows(AKind: TAtlasCommentTriggerKind; const ARows: TArray<string>);
begin
  FListKind := AKind;
  FRows := ARows;
  if Length(FRows) = 0 then
  begin
    FSelected := -1;
    if FList <> nil then
      FList.Visible := False;
    Exit;
  end;
  FSelected := 0;
  PlaceList;
end;

procedure TAtlasCommentEditor.PlaceList;
var
  mForm: TCustomForm;
  mRow: string;
  mPos: LRESULT;
  mCaret: TPoint;
  mLine, mWidth, mHeight, mLeft, mTop: Integer;
begin
  mForm := GetParentForm(Self);
  if (mForm = nil) or not mForm.HandleAllocated or not FMemo.HandleAllocated then
    Exit;
  if FList = nil then
  begin
    FList := TListBox.Create(Self);
    FList.Parent := mForm;
    FList.TabStop := False;
    FList.OnClick := ListClick;
  end;
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for mRow in FRows do
      FList.Items.Add(mRow);
  finally
    FList.Items.EndUpdate;
  end;
  FList.ItemIndex := FSelected;
  // Unter dem getippten Wort; passt es nicht, darüber.
  mPos := FMemo.Perform(EM_POSFROMCHAR, WPARAM(FTrigger.Start), 0);
  if mPos = -1 then
    mCaret := Point(0, 0)
  else
    mCaret := Point(SmallInt(LoWord(mPos)), SmallInt(HiWord(mPos)));
  mLine := MulDiv(Abs(FMemo.Font.Size), FMemo.CurrentPPI, 72) + MulDiv(6, FMemo.CurrentPPI, 96);
  mWidth := MulDiv(ListWidth, FMemo.CurrentPPI, 96);
  mHeight := Min(Length(FRows), TAtlasCommentEditing.MaxSuggestions) * FList.ItemHeight + 4;
  mCaret := mForm.ScreenToClient(FMemo.ClientToScreen(mCaret));
  mLeft := Max(0, Min(mCaret.X, mForm.ClientWidth - mWidth));
  mTop := mCaret.Y + mLine;
  if (mTop + mHeight > mForm.ClientHeight) and (mCaret.Y - mHeight - 2 >= 0) then
    mTop := mCaret.Y - mHeight - 2;
  FList.SetBounds(mLeft, mTop, mWidth, mHeight);
  FList.Visible := True;
  FList.BringToFront;
end;

procedure TAtlasCommentEditor.HideList;
begin
  if FTimer <> nil then
    FTimer.Enabled := False;
  // Antworten auf alte Anfragen verfallen über die Generation.
  Inc(FGeneration);
  FTrigger := TAtlasCommentTrigger.None;
  FRows := nil;
  FUsers := nil;
  FIssues := nil;
  FSelected := -1;
  if FList <> nil then
    FList.Visible := False;
end;

procedure TAtlasCommentEditor.MoveSelection(ADelta: Integer);
begin
  if not ListShown then
    Exit;
  FSelected := EnsureRange(FSelected + ADelta, 0, High(FRows));
  if (FList <> nil) and FList.Visible then
    FList.ItemIndex := FSelected;
end;

procedure TAtlasCommentEditor.ListClick(Sender: TObject);
begin
  if FList = nil then
    Exit;
  Accept(FList.ItemIndex);
  if FMemo.CanFocus and FMemo.Showing then
    FMemo.SetFocus;
end;

procedure TAtlasCommentEditor.Accept(AIndex: Integer);
var
  mValue, mText: string;
  mCaret: Integer;
  mTrigger: TAtlasCommentTrigger;
begin
  if (AIndex < 0) or (AIndex > High(FRows)) or (FTrigger.Kind = TAtlasCommentTriggerKind.None) then
    Exit;
  if FListKind = TAtlasCommentTriggerKind.Mention then
    mValue := TAtlasCommentEditing.MentionText(FUsers[AIndex])
  else
    mValue := Trim(FIssues[AIndex].Key);
  mTrigger := FTrigger;
  HideList;
  mText := TAtlasCommentEditing.Replace(FMemo.Text, mTrigger, mValue, mCaret);
  ApplyEdit(mText, mCaret, 0);
end;

procedure TAtlasCommentEditor.ApplyEdit(const AText: string; AStart, ALength: Integer);
begin
  FChanging := True;
  try
    FMemo.Text := AText;
  finally
    FChanging := False;
  end;
  FMemo.SelStart := AStart;
  FMemo.SelLength := ALength;
  RestartDraftTimer;
end;

procedure TAtlasCommentEditor.Bold;
var
  mStart, mLength: Integer;
  mText: string;
begin
  mText := TAtlasCommentEditing.ToggleInline(FMemo.Text, FMemo.SelStart, FMemo.SelLength,
    TAtlasCommentEditing.BoldMarker, mStart, mLength);
  ApplyEdit(mText, mStart, mLength);
end;

procedure TAtlasCommentEditor.Italic;
var
  mStart, mLength: Integer;
  mText: string;
begin
  mText := TAtlasCommentEditing.ToggleInline(FMemo.Text, FMemo.SelStart, FMemo.SelLength,
    TAtlasCommentEditing.ItalicMarker, mStart, mLength);
  ApplyEdit(mText, mStart, mLength);
end;

procedure TAtlasCommentEditor.CodeBlock;
var
  mStart, mLength: Integer;
  mText: string;
begin
  mText := TAtlasCommentEditing.CodeBlock(FMemo.Text, FMemo.SelStart, FMemo.SelLength, mStart, mLength);
  ApplyEdit(mText, mStart, mLength);
end;

procedure TAtlasCommentEditor.InsertSnippet(AIndex: Integer);
var
  mSnippets: TArray<TAtlasCommentSnippet>;
  mText: string;
  mSelf: TAtlasCommentEditor;
begin
  if (FAssist = nil) or FMemo.ReadOnly then
    Exit;
  mSnippets := FAssist.Snippets;
  if (AIndex < 0) or (AIndex > High(mSnippets)) then
    Exit;
  mText := mSnippets[AIndex].Text;
  mSelf := Self;
  // Werte der Platzhalter kommen aus der IDE (Versionsverwaltung im Hintergrund).
  FAssist.Values(
    procedure(const AValues: TAtlasCommentValues)
    begin
      mSelf.SnippetReady(mText, AValues);
    end);
end;

procedure TAtlasCommentEditor.SnippetReady(const AText: string; const AValues: TAtlasCommentValues);
var
  mText: string;
  mCaret: Integer;
begin
  if FMemo.ReadOnly then
    Exit;
  if FPreviewing then
    Previewing := False;
  mText := TAtlasCommentEditing.Insert(FMemo.Text, FMemo.SelStart, FMemo.SelLength,
    TAtlasCommentSnippets.Expand(MemoText(AText), AValues), mCaret);
  ApplyEdit(mText, mCaret, 0);
  if FMemo.CanFocus and FMemo.Showing then
    FMemo.SetFocus;
end;

procedure TAtlasCommentEditor.PopupSnippets(const AScreen: TPoint);
var
  mSnippets: TArray<TAtlasCommentSnippet>;
  mItem: TMenuItem;
  mIndex: Integer;
begin
  if FAssist = nil then
    Exit;
  mSnippets := FAssist.Snippets;
  FSnippetMenu.Items.Clear;
  for mIndex := 0 to High(mSnippets) do
  begin
    mItem := TMenuItem.Create(FSnippetMenu);
    mItem.Caption := StringReplace(mSnippets[mIndex].Name, '&', '&&', [rfReplaceAll]);
    mItem.Tag := mIndex;
    mItem.OnClick := SnippetItemClick;
    FSnippetMenu.Items.Add(mItem);
  end;
  if Length(mSnippets) = 0 then
  begin
    mItem := TMenuItem.Create(FSnippetMenu);
    mItem.Caption := TAtlasStrings.Text(TAtlasTextId.CommentEditorNoSnippets);
    mItem.Enabled := False;
    FSnippetMenu.Items.Add(mItem);
  end;
  FSnippetMenu.Popup(AScreen.X, AScreen.Y);
end;

procedure TAtlasCommentEditor.SnippetClick(Sender: TObject);
begin
  PopupSnippets(FSnippetButton.ClientToScreen(Point(0, FSnippetButton.Height)));
end;

procedure TAtlasCommentEditor.SnippetItemClick(Sender: TObject);
begin
  if Sender is TMenuItem then
    InsertSnippet(TMenuItem(Sender).Tag);
end;

function TAtlasCommentEditor.CaretScreenPoint: TPoint;
var
  mCaret: TPoint;
begin
  if not Winapi.Windows.GetCaretPos(mCaret) then
    mCaret := Point(0, 0);
  Inc(mCaret.Y, MulDiv(Abs(FMemo.Font.Size), FMemo.CurrentPPI, 72) + 4);
  Result := FMemo.ClientToScreen(mCaret);
end;

procedure TAtlasCommentEditor.PreviewClick(Sender: TObject);
begin
  Previewing := not FPreviewing;
end;

procedure TAtlasCommentEditor.SetPreviewing(AValue: Boolean);
begin
  if AValue = FPreviewing then
    Exit;
  FPreviewing := AValue;
  HideList;
  if AValue then
    BuildPreview
  else
    ClearPreview;
  FPreview.Visible := AValue;
  FMemo.Visible := not AValue;
  FSnippetButton.Enabled := not AValue;
  if AValue then
    FPreviewButton.Caption := TAtlasStrings.Text(TAtlasTextId.CommentEditorEdit)
  else
  begin
    FPreviewButton.Caption := TAtlasStrings.Text(TAtlasTextId.CommentEditorPreview);
    if FMemo.CanFocus and FMemo.Showing then
      FMemo.SetFocus;
  end;
end;

procedure TAtlasCommentEditor.ClearPreview;
var
  mPart: TControl;
begin
  if FPreviewParts = nil then
    Exit;
  for mPart in FPreviewParts do
    mPart.Free;
  FPreviewParts.Clear;
end;

procedure TAtlasCommentEditor.BuildPreview;
var
  mSegment: TAtlasMarkdownSegment;
  mSegments: TArray<TAtlasMarkdownSegment>;
  mBox: TAtlasIssueDocBox;
  mLabel: TLabel;
  mTop: Integer;

  procedure Place(AControl: TControl);
  begin
    // Untereinander in der Reihenfolge des Anlegens: alTop ordnet nach Top.
    Inc(mTop, 1000);
    AControl.Parent := FPreview;
    AControl.Align := alTop;
    AControl.AlignWithMargins := True;
    AControl.Top := mTop;
    FPreviewParts.Add(AControl);
  end;

begin
  FPreview.DisableAlign;
  try
    ClearPreview;
    mTop := 0;
    // Derselbe Renderer wie in der Vorschau (#1264); Bilder stehen hier nur als Name.
    mSegments := TAtlasTrackerMarkdown.Segments(Text);
    if Trim(Text) = '' then
    begin
      mLabel := TLabel.Create(Self);
      Place(mLabel);
      mLabel.Caption := TAtlasStrings.Text(TAtlasTextId.CommentEditorPreviewEmpty);
      mLabel.Font.Color := ToColor(FColors.Muted);
      Exit;
    end;
    for mSegment in mSegments do
    begin
      if mSegment.Kind = TAtlasMarkdownSegmentKind.Doc then
      begin
        mBox := TAtlasIssueDocBox.Create(Self);
        Place(mBox);
        mBox.SetDoc(mSegment.Doc, FColors, FMono);
        Continue;
      end;
      mLabel := TLabel.Create(Self);
      Place(mLabel);
      mLabel.ShowAccelChar := False;
      mLabel.Font.Color := ToColor(FColors.Muted);
      if mSegment.Image.Text <> '' then
        mLabel.Caption := TAtlasStrings.Fmt(TAtlasTextId.CommentEditorImage, [mSegment.Image.Text])
      else
        mLabel.Caption := TAtlasStrings.Fmt(TAtlasTextId.CommentEditorImage, [mSegment.Image.Url]);
    end;
  finally
    FPreview.EnableAlign;
  end;
end;

procedure TAtlasCommentEditor.MemoKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);

  procedure Handled;
  begin
    Key := 0;
    // Das Zeichen der Taste (Strg+I = Tab, Strg+Enter = Zeilenvorschub) nicht ins Memo.
    FSwallowChar := True;
  end;

begin
  FSwallowChar := False;
  if (Key = VK_RETURN) and (ssCtrl in Shift) then
  begin
    Handled;
    HideList;
    if Assigned(FOnSend) then
      FOnSend(Self);
    Exit;
  end;
  if not FEnhanced then
    Exit;
  if ListShown then
    case Key of
      VK_UP:
        begin
          MoveSelection(-1);
          Handled;
          Exit;
        end;
      VK_DOWN:
        begin
          MoveSelection(1);
          Handled;
          Exit;
        end;
      VK_PRIOR:
        begin
          MoveSelection(-TAtlasCommentEditing.MaxSuggestions);
          Handled;
          Exit;
        end;
      VK_NEXT:
        begin
          MoveSelection(TAtlasCommentEditing.MaxSuggestions);
          Handled;
          Exit;
        end;
      VK_RETURN, VK_TAB:
        if Shift = [] then
        begin
          Accept(FSelected);
          Handled;
          Exit;
        end;
      VK_ESCAPE:
        begin
          HideList;
          Handled;
          Exit;
        end;
    end;
  if Key = VK_ESCAPE then
  begin
    Handled;
    KeepDraft;
    if Assigned(FOnCancel) then
      FOnCancel(Self);
    Exit;
  end;
  if (Key = VK_SPACE) and (Shift = [ssCtrl]) then
  begin
    Handled;
    HideList;
    PopupSnippets(CaretScreenPoint);
    Exit;
  end;
  if (Key = Ord('B')) and (Shift = [ssCtrl]) then
  begin
    Handled;
    Bold;
    Exit;
  end;
  if (Key = Ord('I')) and (Shift = [ssCtrl]) then
  begin
    Handled;
    Italic;
    Exit;
  end;
  if (Key = Ord('K')) and (Shift = [ssCtrl, ssShift]) then
  begin
    Handled;
    CodeBlock;
    Exit;
  end;
  // Die Schreibmarke verlässt das Wort.
  if ListShown and ((Key = VK_LEFT) or (Key = VK_RIGHT) or (Key = VK_HOME) or (Key = VK_END)) then
    HideList;
end;

procedure TAtlasCommentEditor.MemoKeyPress(Sender: TObject; var Key: Char);
begin
  if FSwallowChar then
  begin
    Key := #0;
    FSwallowChar := False;
  end;
end;

end.
