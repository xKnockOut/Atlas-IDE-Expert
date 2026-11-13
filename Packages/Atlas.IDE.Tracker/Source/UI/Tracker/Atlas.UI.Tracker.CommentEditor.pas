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
  TAtlasCommentEditor = class;

  /// <summary>Strg+B, Strg+I bzw. Strg+Umschalt+K.</summary>
  {$SCOPEDENUMS ON}
  TAtlasCommentStyle = (Bold, Italic, Code);
  {$SCOPEDENUMS OFF}

  /// <summary>Steuerelemente des Kommentarfelds; sie gehören dem Feld.</summary>
  TAtlasCommentEditorParts = record
    Memo: TMemo;
    Bar: TFlowPanel;
    PreviewButton: TButton;
    SnippetButton: TButton;
    DraftNote: TLabel;
    DraftButton: TButton;
    Preview: TScrollBox;
    SnippetMenu: TPopupMenu;
  end;

  /// <summary>Strg+Enter (Send) und Esc ohne Liste (Cancel); nil = nichts.</summary>
  TAtlasCommentEditorEvents = record
    Send: TNotifyEvent;
    Cancel: TNotifyEvent;
    constructor Create(const ASend, ACancel: TNotifyEvent);
  end;

  /// <summary>Vorschlagsliste an der Schreibmarke: Benutzer nach "@", Issues nach "#…" bzw. "ATL-…".</summary>
  TAtlasCommentSuggest = class
  public const
    cListWidth = 340;
  private
    FEditor: TAtlasCommentEditor;
    FList: TListBox;
    FTimer: TTimer;
    FTrigger: TAtlasCommentTrigger;
    FUsers: TArray<TAtlasTrackerUser>;
    FIssues: TArray<TAtlasTrackerIssue>;
    FRows: TArray<string>;
    FSelected: Integer;
    FKind: TAtlasCommentTriggerKind;
    FGeneration: Integer;
    FRequestDelay: Integer;
    procedure Request;
    procedure UsersAnswered(AGeneration: Integer; const AUsers: TArray<TAtlasTrackerUser>);
    procedure IssuesAnswered(AGeneration: Integer; const AIssues: TArray<TAtlasTrackerIssue>);
    procedure ShowRows(AKind: TAtlasCommentTriggerKind; const ARows: TArray<string>);
    procedure PlaceList;
    procedure ListClick(Sender: TObject);
    procedure TimerTick(Sender: TObject);
  public
    constructor Create(AEditor: TAtlasCommentEditor);
    destructor Destroy; override;
    /// <summary>Auslöser an der Schreibmarke neu bestimmen (nach Eingabe, für Tests auch direkt).</summary>
    procedure Check;
    /// <summary>Liste schließen und offene Anfragen verwerfen.</summary>
    procedure Hide;
    /// <summary>Vorschlag AIndex der Liste einfügen.</summary>
    procedure Accept(AIndex: Integer);
    procedure Move(ADelta: Integer);
    function Shown: Boolean;
    property Trigger: TAtlasCommentTrigger read FTrigger;
    /// <summary>Zeilen der Liste und die gewählte (-1 ohne).</summary>
    property Rows: TArray<string> read FRows;
    property Selected: Integer read FSelected;
    /// <summary>Wartezeit vor der Anfrage (Vorgabe DelayMs des Felds); 0 fragt sofort (Tests).</summary>
    property RequestDelay: Integer read FRequestDelay write FRequestDelay;
  end;

  /// <summary>Entwurf: beim Binden angeboten, 2 s nach der letzten Änderung und beim Lösen gespeichert, nach dem
  /// Senden gelöscht. Unveränderte Vorgaben gelten nicht als Entwurf.</summary>
  TAtlasCommentDraft = class
  public const
    /// <summary>Wartezeit nach der letzten Änderung bis zum Speichern.</summary>
    cDelayMs = 2000;
  private
    FEditor: TAtlasCommentEditor;
    FTimer: TTimer;
    FInitialText: string;
    FOffered: string;
    FRestored: Boolean;
    procedure TimerTick(Sender: TObject);
    procedure ShowNote(const AText, AButton: string);
    procedure ButtonClick(Sender: TObject);
  public
    constructor Create(AEditor: TAtlasCommentEditor);
    destructor Destroy; override;
    /// <summary>Gebunden: Entwurf in ein leeres Feld setzen, sonst anbieten.</summary>
    procedure Offer;
    /// <summary>Jetzt speichern, wenn sich der Text gegenüber der Vorgabe geändert hat.</summary>
    procedure Keep;
    procedure Restart;
    /// <summary>Gesendet: Entwurf löschen.</summary>
    procedure Discard;
    /// <summary>Angebot und Hinweis zurücksetzen; AInitial gilt als Vorgabe.</summary>
    procedure Reset(const AInitial: string);
    function Changed: Boolean;
    /// <summary>Entwurf, der angeboten, aber nicht eingesetzt wurde; '' ohne.</summary>
    property Offered: string read FOffered;
  end;

  /// <summary>Vorschau des Texts mit demselben Renderer wie die Issue-Vorschau (#1264).</summary>
  TAtlasCommentPreview = class
  private
    FBox: TScrollBox;
    FParts: TList<TControl>;
    FColors: TAtlasColors;
    FMono: TFont;
    FText: string;
    procedure Place(AControl: TControl);
    procedure SetMono(AValue: TFont);
  public
    constructor Create(ABox: TScrollBox);
    destructor Destroy; override;
    procedure Build(const AText: string);
    procedure Clear;
    procedure ApplyColors(const AColors: TAtlasColors);
    property Mono: TFont read FMono write SetMono;
  end;

  TAtlasCommentEditor = class(TCustomPanel)
  public const
    /// <summary>Wartezeit nach der letzten Eingabe bis zur Anfrage.</summary>
    cDelayMs = 300;
  private
    FParts: TAtlasCommentEditorParts;
    FSuggest: TAtlasCommentSuggest;
    FDraft: TAtlasCommentDraft;
    FPreview: TAtlasCommentPreview;
    FAssist: IAtlasCommentAssist;
    FEnhanced: Boolean;
    FPreviewing: Boolean;
    FSwallowChar: Boolean;
    FChanging: Boolean;
    FEvents: TAtlasCommentEditorEvents;
    procedure MemoChange(Sender: TObject);
    procedure MemoKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure MemoKeyPress(Sender: TObject; var Key: Char);
    procedure MemoClick(Sender: TObject);
    procedure MemoExit(Sender: TObject);
    /// <summary>Vorschau, Textbaustein-Knopf und Einträge des Textbaustein-Menüs.</summary>
    procedure ButtonClick(Sender: TObject);
    procedure SetEnhanced(AValue: Boolean);
    procedure SetPreviewing(AValue: Boolean);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>An Tracker, Issue und Feld binden (über AAssist); bietet den Entwurf an. nil löst nur.</summary>
    procedure Bind(const AAssist: IAtlasCommentAssist);
    /// <summary>Entwurf speichern und lösen (Wechsel des Issues, Schließen).</summary>
    procedure Unbind;
    /// <summary>Gesendet: Entwurf löschen, Feld leeren.</summary>
    procedure Sent;
    /// <summary>Vorgabe setzen (Zeilen mit #10 oder #13#10); gilt nicht als Entwurf.</summary>
    procedure SetText(const AText: string);
    /// <summary>Fett, kursiv bzw. Code-Block auf die Auswahl anwenden.</summary>
    procedure ApplyStyle(AStyle: TAtlasCommentStyle);
    /// <summary>Textbaustein AIndex an der Schreibmarke einfügen (Platzhalter über die IDE).</summary>
    procedure InsertSnippet(AIndex: Integer);
    /// <summary>Text mit #10 als Zeilenumbruch, wie er an den Tracker geht.</summary>
    function Text: string;
    property Memo: TMemo read FParts.Memo;
    property Parts: TAtlasCommentEditorParts read FParts;
    property Assist: IAtlasCommentAssist read FAssist;
    /// <summary>issues.commentEditor: Ergänzung, Textbausteine, Vorschau und Entwürfe.</summary>
    property Enhanced: Boolean read FEnhanced write SetEnhanced;
    property Previewing: Boolean read FPreviewing write SetPreviewing;
    property Suggest: TAtlasCommentSuggest read FSuggest;
    property Draft: TAtlasCommentDraft read FDraft;
    property Preview: TAtlasCommentPreview read FPreview;
    property Events: TAtlasCommentEditorEvents read FEvents write FEvents;
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
  Atlas.UI.Tracker.Workflow.Strings,
  Atlas.UI.Tracker.DocBox;

type
  /// <summary>Was eine Taste im Feld auslöst.</summary>
  {$SCOPEDENUMS ON}
  TCommentKey = (None, Send, Cancel, Up, Down, PageUp, PageDown, Accept, CloseList, Snippets, Bold, Italic, Code,
    LeaveWord);
  {$SCOPEDENUMS OFF}

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

function MemoText(const AText: string): string;
begin
  Result := AdjustLineBreaks(AText, tlbsCRLF);
end;

/// <summary>Text des Memos setzen, ohne dass es als Eingabe zählt.</summary>
procedure SetMemoText(AEditor: TAtlasCommentEditor; const AText: string);
begin
  AEditor.FChanging := True;
  try
    AEditor.FParts.Memo.Text := AText;
  finally
    AEditor.FChanging := False;
  end;
end;

/// <summary>Bearbeiteten Text setzen, Auswahl wiederherstellen, Entwurf vormerken.</summary>
procedure ApplyEdit(AEditor: TAtlasCommentEditor; const AText: string; AStart, ALength: Integer);
begin
  SetMemoText(AEditor, AText);
  AEditor.FParts.Memo.SelStart := AStart;
  AEditor.FParts.Memo.SelLength := ALength;
  AEditor.FDraft.Restart;
end;

procedure FocusMemo(AEditor: TAtlasCommentEditor);
begin
  if AEditor.FParts.Memo.CanFocus and AEditor.FParts.Memo.Showing then
  begin
    AEditor.FParts.Memo.SetFocus;
  end;
end;

procedure Fire(const AEvent: TNotifyEvent; ASender: TObject);
begin
  if Assigned(AEvent) then
  begin
    AEvent(ASender);
  end;
end;

{ TAtlasCommentEditorEvents }

constructor TAtlasCommentEditorEvents.Create(const ASend, ACancel: TNotifyEvent);
begin
  Send := ASend;
  Cancel := ACancel;
end;

{ TAtlasCommentSuggest }

constructor TAtlasCommentSuggest.Create(AEditor: TAtlasCommentEditor);
begin
  inherited Create;
  FEditor := AEditor;
  FSelected := -1;
  FRequestDelay := TAtlasCommentEditor.cDelayMs;
  FTrigger := TAtlasCommentTrigger.None;
  // Der Zeitgeber gehört dem Feld; die Liste legt PlaceList auf der Form an.
  FTimer := TTimer.Create(AEditor);
  FTimer.Enabled := False;
  FTimer.Interval := TAtlasCommentEditor.cDelayMs;
  FTimer.OnTimer := TimerTick;
end;

destructor TAtlasCommentSuggest.Destroy;
begin
  FTimer.Enabled := False;
  FTimer.OnTimer := nil;
  if FList <> nil then
  begin
    FList.OnClick := nil;
  end;
  FRows := nil;
  FUsers := nil;
  FIssues := nil;
  inherited;
end;

function TAtlasCommentSuggest.Shown: Boolean;
begin
  Result := Length(FRows) > 0;
end;

/// <summary>Auslöser an der Schreibmarke; None, wenn das Feld gerade nichts vorschlägt.</summary>
function TriggerAt(AEditor: TAtlasCommentEditor): TAtlasCommentTrigger;
var
  mMemo: TMemo;
begin
  mMemo := AEditor.FParts.Memo;
  if not AEditor.FEnhanced or (AEditor.FAssist = nil) or mMemo.ReadOnly or AEditor.FPreviewing or
    (mMemo.SelLength > 0) then
  begin
    Result := TAtlasCommentTrigger.None;
  end
  else
  begin
    Result := TAtlasCommentEditing.Trigger(mMemo.Text, mMemo.SelStart, AEditor.FAssist.Target);
  end;
end;

procedure TAtlasCommentSuggest.Check;
var
  mTrigger: TAtlasCommentTrigger;
begin
  mTrigger := TriggerAt(FEditor);
  if mTrigger.Kind = TAtlasCommentTriggerKind.None then
  begin
    Hide;
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
  begin
    Request;
  end
  else
  begin
    FTimer.Interval := Cardinal(FRequestDelay);
    FTimer.Enabled := True;
  end;
end;

procedure TAtlasCommentSuggest.TimerTick(Sender: TObject);
begin
  FTimer.Enabled := False;
  Request;
end;

procedure TAtlasCommentSuggest.Request;
var
  mSelf: TAtlasCommentSuggest;
  mGeneration: Integer;
begin
  FTimer.Enabled := False;
  if (FEditor.FAssist = nil) or (FTrigger.Kind = TAtlasCommentTriggerKind.None) then
  begin
    Exit;
  end;
  mSelf := Self;
  mGeneration := FGeneration;
  if FTrigger.Kind = TAtlasCommentTriggerKind.Mention then
  begin
    FEditor.FAssist.FindUsers(FTrigger.Text,
      procedure(const AUsers: TArray<TAtlasTrackerUser>)
      begin
        mSelf.UsersAnswered(mGeneration, AUsers);
      end);
  end
  else
  begin
    FEditor.FAssist.FindIssues(FTrigger.Query,
      procedure(const AIssues: TArray<TAtlasTrackerIssue>)
      begin
        mSelf.IssuesAnswered(mGeneration, AIssues);
      end);
  end;
end;

procedure TAtlasCommentSuggest.UsersAnswered(AGeneration: Integer; const AUsers: TArray<TAtlasTrackerUser>);
var
  mRows: TArray<string>;
  mIndex: Integer;
begin
  // Weitergetippt, geschlossen oder anderes Wort: Die Antwort zählt nicht mehr.
  if (AGeneration <> FGeneration) or (FTrigger.Kind <> TAtlasCommentTriggerKind.Mention) then
  begin
    Exit;
  end;
  FUsers := Copy(AUsers, 0, TAtlasCommentEditing.cMaxSuggestions);
  FIssues := nil;
  SetLength(mRows, Length(FUsers));
  for mIndex := 0 to High(FUsers) do
  begin
    mRows[mIndex] := TAtlasCommentEditing.UserRow(FUsers[mIndex]);
  end;
  ShowRows(TAtlasCommentTriggerKind.Mention, mRows);
end;

procedure TAtlasCommentSuggest.IssuesAnswered(AGeneration: Integer; const AIssues: TArray<TAtlasTrackerIssue>);
var
  mRows: TArray<string>;
  mIndex: Integer;
begin
  if (AGeneration <> FGeneration) or (FTrigger.Kind <> TAtlasCommentTriggerKind.Issue) then
  begin
    Exit;
  end;
  FIssues := Copy(AIssues, 0, TAtlasCommentEditing.cMaxSuggestions);
  FUsers := nil;
  SetLength(mRows, Length(FIssues));
  for mIndex := 0 to High(FIssues) do
  begin
    mRows[mIndex] := TAtlasCommentEditing.IssueRow(FIssues[mIndex]);
  end;
  ShowRows(TAtlasCommentTriggerKind.Issue, mRows);
end;

procedure TAtlasCommentSuggest.ShowRows(AKind: TAtlasCommentTriggerKind; const ARows: TArray<string>);
begin
  FKind := AKind;
  FRows := ARows;
  if Length(FRows) = 0 then
  begin
    FSelected := -1;
    if FList <> nil then
    begin
      FList.Visible := False;
    end;
    Exit;
  end;
  FSelected := 0;
  PlaceList;
end;

/// <summary>Lage des getippten Worts im Memo (Client-Koordinaten); (0, 0), wenn unbekannt.</summary>
function WordPoint(AMemo: TMemo; AStart: Integer): TPoint;
var
  mPos: LRESULT;
begin
  mPos := AMemo.Perform(EM_POSFROMCHAR, WPARAM(AStart), 0);
  if mPos = -1 then
  begin
    Result := Point(0, 0);
  end
  else
  begin
    Result := Point(SmallInt(LoWord(mPos)), SmallInt(HiWord(mPos)));
  end;
end;

/// <summary>Zeilen in die Liste schreiben und die gewählte markieren.</summary>
procedure FillList(AList: TListBox; const ARows: TArray<string>; ASelected: Integer);
var
  mRow: string;
begin
  AList.Items.BeginUpdate;
  try
    AList.Items.Clear;
    for mRow in ARows do
    begin
      AList.Items.Add(mRow);
    end;
  finally
    AList.Items.EndUpdate;
  end;
  AList.ItemIndex := ASelected;
end;

procedure TAtlasCommentSuggest.PlaceList;
var
  mForm: TCustomForm;
  mMemo: TMemo;
  mCaret: TPoint;
  mLine, mWidth, mHeight, mLeft, mTop: Integer;
begin
  mMemo := FEditor.FParts.Memo;
  mForm := GetParentForm(FEditor);
  if (mForm = nil) or not mForm.HandleAllocated or not mMemo.HandleAllocated then
  begin
    Exit;
  end;
  if FList = nil then
  begin
    FList := TListBox.Create(FEditor);
    FList.Parent := mForm;
    FList.TabStop := False;
    FList.OnClick := ListClick;
  end;
  FillList(FList, FRows, FSelected);
  // Unter dem getippten Wort; passt es nicht, darüber.
  mLine := MulDiv(Abs(mMemo.Font.Size), mMemo.CurrentPPI, 72) + MulDiv(6, mMemo.CurrentPPI, 96);
  mWidth := MulDiv(cListWidth, mMemo.CurrentPPI, 96);
  mHeight := Min(Length(FRows), TAtlasCommentEditing.cMaxSuggestions) * FList.ItemHeight + 4;
  mCaret := mForm.ScreenToClient(mMemo.ClientToScreen(WordPoint(mMemo, FTrigger.Start)));
  mLeft := Max(0, Min(mCaret.X, mForm.ClientWidth - mWidth));
  mTop := mCaret.Y + mLine;
  if (mTop + mHeight > mForm.ClientHeight) and (mCaret.Y - mHeight - 2 >= 0) then
  begin
    mTop := mCaret.Y - mHeight - 2;
  end;
  FList.SetBounds(mLeft, mTop, mWidth, mHeight);
  FList.Visible := True;
  FList.BringToFront;
end;

procedure TAtlasCommentSuggest.Hide;
begin
  FTimer.Enabled := False;
  // Antworten auf alte Anfragen verfallen über die Generation.
  Inc(FGeneration);
  FTrigger := TAtlasCommentTrigger.None;
  FRows := nil;
  FUsers := nil;
  FIssues := nil;
  FSelected := -1;
  if FList <> nil then
  begin
    FList.Visible := False;
  end;
end;

procedure TAtlasCommentSuggest.Move(ADelta: Integer);
begin
  if not Shown then
  begin
    Exit;
  end;
  FSelected := EnsureRange(FSelected + ADelta, 0, High(FRows));
  if (FList <> nil) and FList.Visible then
  begin
    FList.ItemIndex := FSelected;
  end;
end;

procedure TAtlasCommentSuggest.ListClick(Sender: TObject);
begin
  if FList = nil then
  begin
    Exit;
  end;
  Accept(FList.ItemIndex);
  FocusMemo(FEditor);
end;

procedure TAtlasCommentSuggest.Accept(AIndex: Integer);
var
  mValue, mText: string;
  mCaret: Integer;
  mTrigger: TAtlasCommentTrigger;
begin
  if (AIndex < 0) or (AIndex > High(FRows)) or (FTrigger.Kind = TAtlasCommentTriggerKind.None) then
  begin
    Exit;
  end;
  if FKind = TAtlasCommentTriggerKind.Mention then
  begin
    mValue := TAtlasCommentEditing.MentionText(FUsers[AIndex]);
  end
  else
  begin
    mValue := Trim(FIssues[AIndex].Key);
  end;
  mTrigger := FTrigger;
  Hide;
  mText := TAtlasCommentEditing.Replace(FEditor.FParts.Memo.Text, mTrigger, mValue, mCaret);
  ApplyEdit(FEditor, mText, mCaret, 0);
end;

{ TAtlasCommentDraft }

constructor TAtlasCommentDraft.Create(AEditor: TAtlasCommentEditor);
begin
  inherited Create;
  FEditor := AEditor;
  // Zeitgeber und Knopf gehören dem Feld.
  FTimer := TTimer.Create(AEditor);
  FTimer.Enabled := False;
  FTimer.Interval := cDelayMs;
  FTimer.OnTimer := TimerTick;
  AEditor.FParts.DraftButton.OnClick := ButtonClick;
end;

destructor TAtlasCommentDraft.Destroy;
begin
  FTimer.Enabled := False;
  FTimer.OnTimer := nil;
  FEditor.FParts.DraftButton.OnClick := nil;
  FInitialText := '';
  FOffered := '';
  inherited;
end;

function TAtlasCommentDraft.Changed: Boolean;
begin
  Result := FEditor.FParts.Memo.Text <> FInitialText;
end;

procedure TAtlasCommentDraft.ShowNote(const AText, AButton: string);
begin
  FEditor.FParts.DraftNote.Caption := AText;
  FEditor.FParts.DraftButton.Caption := AButton;
  FEditor.FParts.DraftButton.Visible := AButton <> '';
end;

procedure TAtlasCommentDraft.Reset(const AInitial: string);
begin
  FInitialText := AInitial;
  FOffered := '';
  FRestored := False;
  ShowNote('', '');
end;

procedure TAtlasCommentDraft.Offer;
var
  mText, mWhen: string;
  mSaved: TDateTime;
  mMemo: TMemo;
begin
  mMemo := FEditor.FParts.Memo;
  Reset(mMemo.Text);
  if (FEditor.FAssist = nil) or not FEditor.FEnhanced then
  begin
    Exit;
  end;
  if not FEditor.FAssist.LoadDraft(mText, mSaved) or (Trim(mText) = '') or (MemoText(mText) = mMemo.Text) then
  begin
    Exit;
  end;
  mWhen := FormatDateTime('dd.mm. hh:nn', TTimeZone.Local.ToLocalTime(mSaved), FormatSettings);
  if Trim(mMemo.Text) = '' then
  begin
    // Leeres Feld: der Entwurf gleich darin, mit „Verwerfen“.
    SetMemoText(FEditor, MemoText(mText));
    FRestored := True;
    ShowNote(TAtlasWorkflowStrings.Fmt(TAtlasWorkflowTextId.CommentEditorDraftRestored, [mWhen]),
      TAtlasWorkflowStrings.Text(TAtlasWorkflowTextId.CommentEditorDraftDiscard));
  end
  else
  begin
    // Vorgefülltes Feld (Vorlage beim Beenden): Entwurf nur anbieten.
    FOffered := mText;
    ShowNote(TAtlasWorkflowStrings.Fmt(TAtlasWorkflowTextId.CommentEditorDraftOffered, [mWhen]),
      TAtlasWorkflowStrings.Text(TAtlasWorkflowTextId.CommentEditorDraftApply));
  end;
end;

procedure TAtlasCommentDraft.Keep;
begin
  FTimer.Enabled := False;
  if (FEditor.FAssist = nil) or not FEditor.FEnhanced or not Changed then
  begin
    Exit;
  end;
  // Leer gemacht heißt: kein Entwurf mehr.
  FEditor.FAssist.SaveDraft(FEditor.Text);
end;

procedure TAtlasCommentDraft.Discard;
begin
  FTimer.Enabled := False;
  if FEditor.FAssist <> nil then
  begin
    FEditor.FAssist.DeleteDraft;
  end;
end;

procedure TAtlasCommentDraft.ButtonClick(Sender: TObject);
begin
  if FOffered <> '' then
  begin
    SetMemoText(FEditor, MemoText(FOffered));
    FOffered := '';
    ShowNote('', '');
    Restart;
  end
  else if FRestored then
  begin
    Discard;
    SetMemoText(FEditor, FInitialText);
    FRestored := False;
    ShowNote('', '');
  end;
  FocusMemo(FEditor);
end;

procedure TAtlasCommentDraft.Restart;
begin
  if not FEditor.FEnhanced or (FEditor.FAssist = nil) then
  begin
    Exit;
  end;
  FTimer.Enabled := False;
  FTimer.Enabled := True;
end;

procedure TAtlasCommentDraft.TimerTick(Sender: TObject);
begin
  FTimer.Enabled := False;
  if (FEditor.FAssist = nil) or not Changed then
  begin
    Exit;
  end;
  Keep;
  if not FEditor.FParts.DraftButton.Visible then
  begin
    ShowNote(TAtlasWorkflowStrings.Text(TAtlasWorkflowTextId.CommentEditorDraftSaved), '');
  end;
end;

{ TAtlasCommentPreview }

constructor TAtlasCommentPreview.Create(ABox: TScrollBox);
begin
  inherited Create;
  FBox := ABox;
  FParts := TList<TControl>.Create;
  FColors := TAtlasColors.Light;
  FMono := TFont.Create;
  FMono.Name := 'Consolas';
  FMono.Size := 10;
end;

destructor TAtlasCommentPreview.Destroy;
begin
  // Die Teile gehören dem Kasten und gehen mit ihm.
  FParts.Free;
  FMono.Free;
  FText := '';
  inherited;
end;

procedure TAtlasCommentPreview.SetMono(AValue: TFont);
begin
  FMono.Assign(AValue);
  if FBox.Visible then
  begin
    Build(FText);
  end;
end;

procedure TAtlasCommentPreview.ApplyColors(const AColors: TAtlasColors);
begin
  FColors := AColors;
  FBox.Color := ToColor(AColors.Surface);
  FBox.ParentBackground := False;
  if FBox.Visible then
  begin
    Build(FText);
  end;
end;

procedure TAtlasCommentPreview.Clear;
var
  mPart: TControl;
begin
  for mPart in FParts do
  begin
    mPart.Free;
  end;
  FParts.Clear;
end;

procedure TAtlasCommentPreview.Place(AControl: TControl);
begin
  // Untereinander in der Reihenfolge des Anlegens: alTop ordnet nach Top.
  AControl.Parent := FBox;
  AControl.Align := alTop;
  AControl.AlignWithMargins := True;
  AControl.Top := 1000 * (FParts.Count + 1);
  FParts.Add(AControl);
end;

/// <summary>Bild in der Vorschau: nur als Name.</summary>
function ImageCaption(const ASegment: TAtlasMarkdownSegment): string;
begin
  if ASegment.Image.Text <> '' then
  begin
    Result := TAtlasWorkflowStrings.Fmt(TAtlasWorkflowTextId.CommentEditorImage, [ASegment.Image.Text]);
  end
  else
  begin
    Result := TAtlasWorkflowStrings.Fmt(TAtlasWorkflowTextId.CommentEditorImage, [ASegment.Image.Url]);
  end;
end;

procedure TAtlasCommentPreview.Build(const AText: string);
var
  mSegment: TAtlasMarkdownSegment;
  mBox: TAtlasIssueDocBox;
  mLabel: TLabel;
begin
  FText := AText;
  FBox.DisableAlign;
  try
    Clear;
    if Trim(AText) = '' then
    begin
      mLabel := TLabel.Create(FBox);
      Place(mLabel);
      mLabel.Caption := TAtlasWorkflowStrings.Text(TAtlasWorkflowTextId.CommentEditorPreviewEmpty);
      mLabel.Font.Color := ToColor(FColors.Muted);
      Exit;
    end;
    for mSegment in TAtlasTrackerMarkdown.Segments(AText) do
    begin
      if mSegment.Kind = TAtlasMarkdownSegmentKind.Doc then
      begin
        mBox := TAtlasIssueDocBox.Create(FBox);
        Place(mBox);
        mBox.SetDoc(mSegment.Doc, FColors, FMono);
        Continue;
      end;
      mLabel := TLabel.Create(FBox);
      Place(mLabel);
      mLabel.ShowAccelChar := False;
      mLabel.Font.Color := ToColor(FColors.Muted);
      mLabel.Caption := ImageCaption(mSegment);
    end;
  finally
    FBox.EnableAlign;
  end;
end;

{ TAtlasCommentEditor }

function AddBarButton(AEditor: TAtlasCommentEditor; AWidth: Integer; const ACaption: string): TButton;
begin
  Result := TButton.Create(AEditor);
  Result.Parent := AEditor.FParts.Bar;
  Result.AlignWithMargins := True;
  Result.Width := AWidth;
  Result.Caption := ACaption;
end;

/// <summary>Leiste unten: Vorschau, Textbaustein, Hinweis und Knopf zum Entwurf. Fließend: Reihenfolge =
/// Erzeugungsreihenfolge, bei schmalem Fenster Umbruch in weitere Zeilen.</summary>
procedure AddBar(AEditor: TAtlasCommentEditor);
const
  // Breiten der Knöpfe Vorschau und Textbaustein.
  cPreviewWidth = 90;
  cSnippetWidth = 120;
begin
  AEditor.FParts.Bar := TFlowPanel.Create(AEditor);
  AEditor.FParts.Bar.Parent := AEditor;
  AEditor.FParts.Bar.Align := alBottom;
  AEditor.FParts.Bar.BevelOuter := bvNone;
  AEditor.FParts.Bar.ShowCaption := False;
  AEditor.FParts.Bar.AutoWrap := True;
  AEditor.FParts.Bar.AutoSize := True;
  AEditor.FParts.PreviewButton := AddBarButton(AEditor, cPreviewWidth,
    TAtlasWorkflowStrings.Text(TAtlasWorkflowTextId.CommentEditorPreview));
  AEditor.FParts.PreviewButton.OnClick := AEditor.ButtonClick;
  AEditor.FParts.SnippetButton := AddBarButton(AEditor, cSnippetWidth,
    TAtlasWorkflowStrings.Text(TAtlasWorkflowTextId.CommentEditorSnippets));
  AEditor.FParts.SnippetButton.OnClick := AEditor.ButtonClick;
  AEditor.FParts.DraftNote := TLabel.Create(AEditor);
  AEditor.FParts.DraftNote.Parent := AEditor.FParts.Bar;
  AEditor.FParts.DraftNote.AlignWithMargins := True;
  AEditor.FParts.DraftNote.AutoSize := True;
  AEditor.FParts.DraftNote.Margins.Top := AEditor.FParts.DraftNote.ScaleValue(7);
  AEditor.FParts.DraftNote.ShowAccelChar := False;
  AEditor.FParts.DraftNote.Font.Color := clGrayText;
  AEditor.FParts.DraftNote.Caption := '';
  AEditor.FParts.DraftButton := AddBarButton(AEditor, 100, '');
  AEditor.FParts.DraftButton.Visible := False;
end;

/// <summary>Memo, Vorschaukasten und Menü der Textbausteine.</summary>
procedure AddMemo(AEditor: TAtlasCommentEditor);
begin
  AEditor.FParts.Memo := TMemo.Create(AEditor);
  AEditor.FParts.Memo.Parent := AEditor;
  AEditor.FParts.Memo.Align := alClient;
  AEditor.FParts.Memo.ScrollBars := ssVertical;
  AEditor.FParts.Memo.WantReturns := True;
  AEditor.FParts.Memo.WantTabs := False;
  AEditor.FParts.Memo.Hint := TAtlasWorkflowStrings.Text(TAtlasWorkflowTextId.CommentEditorHint);
  AEditor.FParts.Memo.ShowHint := True;
  AEditor.FParts.Memo.OnChange := AEditor.MemoChange;
  AEditor.FParts.Memo.OnKeyDown := AEditor.MemoKeyDown;
  AEditor.FParts.Memo.OnKeyPress := AEditor.MemoKeyPress;
  AEditor.FParts.Memo.OnClick := AEditor.MemoClick;
  AEditor.FParts.Memo.OnExit := AEditor.MemoExit;
  AEditor.FParts.Preview := TScrollBox.Create(AEditor);
  AEditor.FParts.Preview.Parent := AEditor;
  AEditor.FParts.Preview.Align := alClient;
  AEditor.FParts.Preview.Visible := False;
  AEditor.FParts.Preview.VertScrollBar.Tracking := True;
  AEditor.FParts.SnippetMenu := TPopupMenu.Create(AEditor);
end;

constructor TAtlasCommentEditor.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  ShowCaption := False;
  Caption := '';
  FEnhanced := True;
  AddBar(Self);
  AddMemo(Self);
  FSuggest := TAtlasCommentSuggest.Create(Self);
  FDraft := TAtlasCommentDraft.Create(Self);
  FPreview := TAtlasCommentPreview.Create(FParts.Preview);
end;

destructor TAtlasCommentEditor.Destroy;
begin
  // Nichts darf nach dem Freigeben ankommen: offene Anfragen verwerfen. Den Entwurf sichert der Gastgeber mit
  // Unbind, solange das Fenster lebt; hier nur noch, wenn das Memo sein Fenster hat (ohne Fenster wäre der Text
  // veraltet und könnte den Entwurf löschen).
  if FAssist <> nil then
  begin
    if (FDraft <> nil) and (FParts.Memo <> nil) and FParts.Memo.HandleAllocated then
    begin
      FDraft.Keep;
    end;
    FAssist.Cancel;
    FAssist := nil;
  end;
  // Ereignisse des Memos erreichen die Teile nicht mehr, die gleich freigegeben werden.
  if FParts.Memo <> nil then
  begin
    FParts.Memo.OnChange := nil;
    FParts.Memo.OnClick := nil;
    FParts.Memo.OnExit := nil;
  end;
  FreeAndNil(FSuggest);
  FreeAndNil(FDraft);
  FreeAndNil(FPreview);
  inherited;
end;

procedure TAtlasCommentEditor.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  // Die Liste liegt auf der Form; geht die zuerst, gibt sie die Liste mit frei.
  if (Operation = opRemove) and (FSuggest <> nil) and (AComponent = FSuggest.FList) then
  begin
    FSuggest.FList := nil;
  end;
end;

function TAtlasCommentEditor.Text: string;
begin
  Result := StringReplace(FParts.Memo.Text, #13#10, #10, [rfReplaceAll]);
end;

procedure TAtlasCommentEditor.SetText(const AText: string);
begin
  FSuggest.Hide;
  SetMemoText(Self, MemoText(AText));
  FDraft.FInitialText := FParts.Memo.Text;
end;

procedure TAtlasCommentEditor.Bind(const AAssist: IAtlasCommentAssist);
begin
  if FAssist <> nil then
  begin
    Unbind;
  end;
  FAssist := AAssist;
  FDraft.Offer;
end;

procedure TAtlasCommentEditor.Unbind;
begin
  FDraft.Keep;
  FSuggest.Hide;
  if FAssist <> nil then
  begin
    FAssist.Cancel;
  end;
  FAssist := nil;
  FDraft.FOffered := '';
  FDraft.ShowNote('', '');
end;

procedure TAtlasCommentEditor.Sent;
begin
  FDraft.Discard;
  FSuggest.Hide;
  Previewing := False;
  SetMemoText(Self, '');
  FDraft.Reset('');
end;

procedure TAtlasCommentEditor.SetEnhanced(AValue: Boolean);
begin
  FEnhanced := AValue;
  FParts.Bar.Visible := AValue;
  FParts.Memo.ShowHint := AValue;
  if AValue then
  begin
    Exit;
  end;
  FSuggest.Hide;
  Previewing := False;
  FDraft.ShowNote('', '');
end;

procedure TAtlasCommentEditor.MemoChange(Sender: TObject);
begin
  if FChanging then
  begin
    Exit;
  end;
  FDraft.Restart;
  FSuggest.Check;
end;

procedure TAtlasCommentEditor.MemoClick(Sender: TObject);
begin
  // Die Schreibmarke kann in ein anderes Wort gesprungen sein.
  if FSuggest.Shown or (FSuggest.Trigger.Kind <> TAtlasCommentTriggerKind.None) then
  begin
    FSuggest.Check;
  end;
end;

procedure TAtlasCommentEditor.MemoExit(Sender: TObject);
var
  mForm: TCustomForm;
begin
  // Ein Klick in die Liste nimmt dem Memo den Fokus: dann bleibt sie offen.
  mForm := GetParentForm(Self);
  if (FSuggest.FList <> nil) and (mForm <> nil) and (mForm.ActiveControl = FSuggest.FList) then
  begin
    Exit;
  end;
  FSuggest.Hide;
end;

procedure TAtlasCommentEditor.ApplyStyle(AStyle: TAtlasCommentStyle);
var
  mStart, mLength: Integer;
  mText: string;
  mMemo: TMemo;
begin
  mMemo := FParts.Memo;
  case AStyle of
    TAtlasCommentStyle.Bold:
      mText := TAtlasCommentEditing.ToggleInline(mMemo.Text, mMemo.SelStart, mMemo.SelLength,
        TAtlasCommentEditing.cBoldMarker, mStart, mLength);
    TAtlasCommentStyle.Italic:
      mText := TAtlasCommentEditing.ToggleInline(mMemo.Text, mMemo.SelStart, mMemo.SelLength,
        TAtlasCommentEditing.cItalicMarker, mStart, mLength);
  else
    mText := TAtlasCommentEditing.CodeBlock(mMemo.Text, mMemo.SelStart, mMemo.SelLength, mStart, mLength);
  end;
  ApplyEdit(Self, mText, mStart, mLength);
end;

/// <summary>Textbaustein mit den Werten der Platzhalter an der Schreibmarke einsetzen.</summary>
procedure SnippetReady(AEditor: TAtlasCommentEditor; const AText: string; const AValues: TAtlasCommentValues);
var
  mText: string;
  mCaret: Integer;
  mMemo: TMemo;
begin
  mMemo := AEditor.FParts.Memo;
  if mMemo.ReadOnly then
  begin
    Exit;
  end;
  AEditor.Previewing := False;
  mText := TAtlasCommentEditing.Insert(mMemo.Text, mMemo.SelStart, mMemo.SelLength,
    TAtlasCommentSnippets.Expand(MemoText(AText), AValues), mCaret);
  ApplyEdit(AEditor, mText, mCaret, 0);
  FocusMemo(AEditor);
end;

procedure TAtlasCommentEditor.InsertSnippet(AIndex: Integer);
var
  mSnippets: TArray<TAtlasCommentSnippet>;
  mText: string;
  mSelf: TAtlasCommentEditor;
begin
  if (FAssist = nil) or FParts.Memo.ReadOnly then
  begin
    Exit;
  end;
  mSnippets := FAssist.Snippets;
  if (AIndex < 0) or (AIndex > High(mSnippets)) then
  begin
    Exit;
  end;
  mText := mSnippets[AIndex].Text;
  mSelf := Self;
  // Werte der Platzhalter kommen aus der IDE (Versionsverwaltung im Hintergrund).
  FAssist.Values(
    procedure(const AValues: TAtlasCommentValues)
    begin
      SnippetReady(mSelf, mText, AValues);
    end);
end;

/// <summary>Menü der Textbausteine an AScreen zeigen.</summary>
procedure PopupSnippets(AEditor: TAtlasCommentEditor; const AScreen: TPoint);
var
  mSnippets: TArray<TAtlasCommentSnippet>;
  mMenu: TPopupMenu;
  mItem: TMenuItem;
  mIndex: Integer;
begin
  if AEditor.FAssist = nil then
  begin
    Exit;
  end;
  mSnippets := AEditor.FAssist.Snippets;
  mMenu := AEditor.FParts.SnippetMenu;
  mMenu.Items.Clear;
  for mIndex := 0 to High(mSnippets) do
  begin
    mItem := TMenuItem.Create(mMenu);
    mItem.Caption := StringReplace(mSnippets[mIndex].Name, '&', '&&', [rfReplaceAll]);
    mItem.Tag := mIndex;
    mItem.OnClick := AEditor.ButtonClick;
    mMenu.Items.Add(mItem);
  end;
  if Length(mSnippets) = 0 then
  begin
    mItem := TMenuItem.Create(mMenu);
    mItem.Caption := TAtlasWorkflowStrings.Text(TAtlasWorkflowTextId.CommentEditorNoSnippets);
    mItem.Enabled := False;
    mMenu.Items.Add(mItem);
  end;
  mMenu.Popup(AScreen.X, AScreen.Y);
end;

/// <summary>Bildschirmpunkt unter der Schreibmarke (für das Menü bei Strg+Leer).</summary>
function CaretScreenPoint(AMemo: TMemo): TPoint;
var
  mCaret: TPoint;
begin
  if not Winapi.Windows.GetCaretPos(mCaret) then
  begin
    mCaret := Point(0, 0);
  end;
  Inc(mCaret.Y, MulDiv(Abs(AMemo.Font.Size), AMemo.CurrentPPI, 72) + 4);
  Result := AMemo.ClientToScreen(mCaret);
end;

procedure TAtlasCommentEditor.ButtonClick(Sender: TObject);
begin
  if Sender is TMenuItem then
  begin
    InsertSnippet(TMenuItem(Sender).Tag);
  end
  else if Sender = FParts.PreviewButton then
  begin
    Previewing := not FPreviewing;
  end
  else if Sender = FParts.SnippetButton then
  begin
    PopupSnippets(Self, FParts.SnippetButton.ClientToScreen(Point(0, FParts.SnippetButton.Height)));
  end;
end;

procedure TAtlasCommentEditor.SetPreviewing(AValue: Boolean);
begin
  if AValue = FPreviewing then
  begin
    Exit;
  end;
  FPreviewing := AValue;
  FSuggest.Hide;
  if AValue then
  begin
    FPreview.Build(Text);
    FParts.PreviewButton.Caption := TAtlasWorkflowStrings.Text(TAtlasWorkflowTextId.CommentEditorEdit);
  end
  else
  begin
    FPreview.Clear;
    FParts.PreviewButton.Caption := TAtlasWorkflowStrings.Text(TAtlasWorkflowTextId.CommentEditorPreview);
  end;
  FParts.Preview.Visible := AValue;
  FParts.Memo.Visible := not AValue;
  FParts.SnippetButton.Enabled := not AValue;
  if not AValue then
  begin
    FocusMemo(Self);
  end;
end;

/// <summary>Tasten, solange die Vorschlagsliste offen ist.</summary>
function ListKey(AKey: Word; AShift: TShiftState): TCommentKey;
begin
  Result := TCommentKey.None;
  case AKey of
    VK_UP:
      Result := TCommentKey.Up;
    VK_DOWN:
      Result := TCommentKey.Down;
    VK_PRIOR:
      Result := TCommentKey.PageUp;
    VK_NEXT:
      Result := TCommentKey.PageDown;
    VK_RETURN, VK_TAB:
      if AShift = [] then
      begin
        Result := TCommentKey.Accept;
      end;
    VK_ESCAPE:
      Result := TCommentKey.CloseList;
  end;
end;

/// <summary>Esc, Strg+Leer, Strg+B, Strg+I und Strg+Umschalt+K.</summary>
function ShortcutKey(AKey: Word; AShift: TShiftState): TCommentKey;
begin
  Result := TCommentKey.None;
  if AKey = VK_ESCAPE then
  begin
    Result := TCommentKey.Cancel;
  end
  else if (AKey = VK_SPACE) and (AShift = [ssCtrl]) then
  begin
    Result := TCommentKey.Snippets;
  end
  else if (AKey = Ord('B')) and (AShift = [ssCtrl]) then
  begin
    Result := TCommentKey.Bold;
  end
  else if (AKey = Ord('I')) and (AShift = [ssCtrl]) then
  begin
    Result := TCommentKey.Italic;
  end
  else if (AKey = Ord('K')) and (AShift = [ssCtrl, ssShift]) then
  begin
    Result := TCommentKey.Code;
  end;
end;

/// <summary>Pfeil links/rechts, Pos1, Ende: Die Schreibmarke verlässt das Wort.</summary>
function LeavesWord(AKey: Word): Boolean;
begin
  Result := (AKey = VK_LEFT) or (AKey = VK_RIGHT) or (AKey = VK_HOME) or (AKey = VK_END);
end;

function KeyAction(AEditor: TAtlasCommentEditor; AKey: Word; AShift: TShiftState): TCommentKey;
begin
  Result := TCommentKey.None;
  if (AKey = VK_RETURN) and (ssCtrl in AShift) then
  begin
    Result := TCommentKey.Send;
  end
  else if AEditor.FEnhanced then
  begin
    if AEditor.FSuggest.Shown then
    begin
      Result := ListKey(AKey, AShift);
    end;
    if Result = TCommentKey.None then
    begin
      Result := ShortcutKey(AKey, AShift);
    end;
    if (Result = TCommentKey.None) and AEditor.FSuggest.Shown and LeavesWord(AKey) then
    begin
      Result := TCommentKey.LeaveWord;
    end;
  end;
end;

procedure RunKey(AEditor: TAtlasCommentEditor; AKey: TCommentKey);
begin
  case AKey of
    TCommentKey.None:
      begin
        // Die Taste gehört dem Memo.
      end;
    TCommentKey.Send:
      begin
        AEditor.FSuggest.Hide;
        Fire(AEditor.FEvents.Send, AEditor);
      end;
    TCommentKey.Cancel:
      begin
        AEditor.FDraft.Keep;
        Fire(AEditor.FEvents.Cancel, AEditor);
      end;
    TCommentKey.Up:
      AEditor.FSuggest.Move(-1);
    TCommentKey.Down:
      AEditor.FSuggest.Move(1);
    TCommentKey.PageUp:
      AEditor.FSuggest.Move(-TAtlasCommentEditing.cMaxSuggestions);
    TCommentKey.PageDown:
      AEditor.FSuggest.Move(TAtlasCommentEditing.cMaxSuggestions);
    TCommentKey.Accept:
      AEditor.FSuggest.Accept(AEditor.FSuggest.Selected);
    TCommentKey.CloseList, TCommentKey.LeaveWord:
      AEditor.FSuggest.Hide;
    TCommentKey.Snippets:
      begin
        AEditor.FSuggest.Hide;
        PopupSnippets(AEditor, CaretScreenPoint(AEditor.FParts.Memo));
      end;
    TCommentKey.Bold:
      AEditor.ApplyStyle(TAtlasCommentStyle.Bold);
    TCommentKey.Italic:
      AEditor.ApplyStyle(TAtlasCommentStyle.Italic);
    TCommentKey.Code:
      AEditor.ApplyStyle(TAtlasCommentStyle.Code);
  end;
end;

procedure TAtlasCommentEditor.MemoKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  mAction: TCommentKey;
begin
  mAction := KeyAction(Self, Key, Shift);
  // Das Zeichen der Taste (Strg+I = Tab, Strg+Enter = Zeilenvorschub) nicht ins Memo; das Verlassen des Worts
  // bewegt die Schreibmarke trotzdem.
  FSwallowChar := (mAction <> TCommentKey.None) and (mAction <> TCommentKey.LeaveWord);
  if FSwallowChar then
  begin
    Key := 0;
  end;
  // Zuletzt: Senden oder Abbrechen kann das Feld schließen.
  RunKey(Self, mAction);
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
