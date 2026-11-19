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
// wird; das Memo behält den Fokus. Was eine Taste bewirkt, bestimmt
// TAtlasCommentKeyPlan; Tasten, Formatieren und Textbausteine führt
// TAtlasCommentCommands aus.

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
  Atlas.Core.Tracker.CommentEditor,
  Atlas.Core.Tracker.CommentKeyPlan;

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
    /// <summary>Auslöser an der Schreibmarke; None, wenn das Feld gerade nichts vorschlägt.</summary>
    function TriggerAt: TAtlasCommentTrigger;
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

  /// <summary>Befehle des Felds: Tasten (TAtlasCommentKeyPlan), Formatieren und Textbausteine (Menü, Einfügen mit
  /// den Werten der Platzhalter).</summary>
  TAtlasCommentCommands = class
  private
    FEditor: TAtlasCommentEditor;
    FMenu: TPopupMenu;
    FSwallowChar: Boolean;
    procedure MemoKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure MemoKeyPress(Sender: TObject; var Key: Char);
    procedure Run(AKey: TAtlasCommentKey);
    procedure MenuClick(Sender: TObject);
    /// <summary>Textbaustein mit den Werten der Platzhalter an der Schreibmarke einsetzen.</summary>
    procedure SnippetReady(const AText: string; const AValues: TAtlasCommentValues);
  public
    constructor Create(AEditor: TAtlasCommentEditor);
    destructor Destroy; override;
    /// <summary>Fett, kursiv bzw. Code-Block auf die Auswahl anwenden.</summary>
    procedure ApplyStyle(AStyle: TAtlasCommentStyle);
    /// <summary>Menü der Textbausteine an AScreen zeigen.</summary>
    procedure PopupSnippets(const AScreen: TPoint);
    /// <summary>Textbaustein AIndex an der Schreibmarke einfügen (Platzhalter über die IDE).</summary>
    procedure InsertSnippet(AIndex: Integer);
    property Menu: TPopupMenu read FMenu;
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
    FChanging: Boolean;
    FEvents: TAtlasCommentEditorEvents;
    FCommands: TAtlasCommentCommands;
    /// <summary>Leiste unten: Vorschau, Textbaustein, Hinweis und Knopf zum Entwurf. Fließend: Reihenfolge =
    /// Erzeugungsreihenfolge, bei schmalem Fenster Umbruch in weitere Zeilen.</summary>
    procedure AddBar;
    /// <summary>Memo und Vorschaukasten.</summary>
    procedure AddMemo;
    /// <summary>Text des Memos setzen, ohne dass es als Eingabe zählt.</summary>
    procedure SetMemoText(const AText: string);
    procedure MemoChange(Sender: TObject);
    procedure MemoClick(Sender: TObject);
    procedure MemoExit(Sender: TObject);
    /// <summary>Vorschau und Textbaustein-Knopf.</summary>
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
    /// <summary>Bearbeiteten Text setzen, Auswahl wiederherstellen, Entwurf vormerken.</summary>
    procedure ApplyEdit(const AText: string; AStart, ALength: Integer);
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
    property Commands: TAtlasCommentCommands read FCommands;
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

const
  /// <summary>Schriftgröße in Punkt: 72 je Zoll.</summary>
  cPointsPerInch = 72;
  /// <summary>Abstand der Vorschlagsliste unter der Zeile der Schreibmarke bei 96 dpi.</summary>
  cCaretGap = 4;
  /// <summary>Zeilenabstand der Vorschlagsliste über die Schrifthöhe hinaus bei 96 dpi.</summary>
  cLinePadding = 6;
  /// <summary>Rahmen der Vorschlagsliste oben und unten zusammen.</summary>
  cListBorder = 4;
  /// <summary>Abstand der Liste über der Schreibmarke, wenn sie unten keinen Platz hat.</summary>
  cAboveGap = 2;

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

function MemoText(const AText: string): string;
begin
  Result := AdjustLineBreaks(AText, tlbsCRLF);
end;

/// <summary>Fokus ins Memo, wenn es ihn nehmen kann.</summary>
procedure FocusMemo(AMemo: TMemo);
begin
  if AMemo.CanFocus and AMemo.Showing then
  begin
    AMemo.SetFocus;
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

function TAtlasCommentSuggest.TriggerAt: TAtlasCommentTrigger;
var
  mMemo: TMemo;
begin
  mMemo := FEditor.Memo;
  if not FEditor.Enhanced or (FEditor.Assist = nil) or mMemo.ReadOnly or FEditor.Previewing or
    (mMemo.SelLength > 0) then
  begin
    Result := TAtlasCommentTrigger.None;
  end
  else
  begin
    Result := TAtlasCommentEditing.Trigger(mMemo.Text, mMemo.SelStart, FEditor.Assist.Target);
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

procedure TAtlasCommentSuggest.ListClick(Sender: TObject);
begin
  if FList = nil then
  begin
    Exit;
  end;
  Accept(FList.ItemIndex);
  FocusMemo(FEditor.Memo);
end;

procedure TAtlasCommentSuggest.TimerTick(Sender: TObject);
begin
  FTimer.Enabled := False;
  Request;
end;

procedure TAtlasCommentSuggest.Check;
var
  mTrigger: TAtlasCommentTrigger;
begin
  mTrigger := TriggerAt;
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
  mLine := MulDiv(Abs(mMemo.Font.Size), mMemo.CurrentPPI, cPointsPerInch) +
    MulDiv(cLinePadding, mMemo.CurrentPPI, 96);
  mWidth := MulDiv(cListWidth, mMemo.CurrentPPI, 96);
  mHeight := Min(Length(FRows), TAtlasCommentEditing.cMaxSuggestions) * FList.ItemHeight + cListBorder;
  mCaret := mForm.ScreenToClient(mMemo.ClientToScreen(WordPoint(mMemo, FTrigger.Start)));
  mLeft := Max(0, Min(mCaret.X, mForm.ClientWidth - mWidth));
  mTop := mCaret.Y + mLine;
  if (mTop + mHeight > mForm.ClientHeight) and (mCaret.Y - mHeight - cAboveGap >= 0) then
  begin
    mTop := mCaret.Y - mHeight - cAboveGap;
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
  mText := TAtlasCommentEditing.Replace(FEditor.Memo.Text, mTrigger, mValue, mCaret);
  FEditor.ApplyEdit(mText, mCaret, 0);
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

function TAtlasCommentSuggest.Shown: Boolean;
begin
  Result := Length(FRows) > 0;
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

procedure TAtlasCommentDraft.ShowNote(const AText, AButton: string);
begin
  FEditor.FParts.DraftNote.Caption := AText;
  FEditor.FParts.DraftButton.Caption := AButton;
  FEditor.FParts.DraftButton.Visible := AButton <> '';
end;

procedure TAtlasCommentDraft.ButtonClick(Sender: TObject);
begin
  if FOffered <> '' then
  begin
    FEditor.SetMemoText(MemoText(FOffered));
    FOffered := '';
    ShowNote('', '');
    Restart;
  end
  else if FRestored then
  begin
    Discard;
    FEditor.SetMemoText(FInitialText);
    FRestored := False;
    ShowNote('', '');
  end;
  FocusMemo(FEditor.Memo);
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
    FEditor.SetMemoText(MemoText(mText));
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

procedure TAtlasCommentDraft.Restart;
begin
  if not FEditor.FEnhanced or (FEditor.FAssist = nil) then
  begin
    Exit;
  end;
  FTimer.Enabled := False;
  FTimer.Enabled := True;
end;

procedure TAtlasCommentDraft.Discard;
begin
  FTimer.Enabled := False;
  if FEditor.FAssist <> nil then
  begin
    FEditor.FAssist.DeleteDraft;
  end;
end;

procedure TAtlasCommentDraft.Reset(const AInitial: string);
begin
  FInitialText := AInitial;
  FOffered := '';
  FRestored := False;
  ShowNote('', '');
end;

function TAtlasCommentDraft.Changed: Boolean;
begin
  Result := FEditor.FParts.Memo.Text <> FInitialText;
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

procedure TAtlasCommentPreview.Place(AControl: TControl);
begin
  // Untereinander in der Reihenfolge des Anlegens: alTop ordnet nach Top.
  AControl.Parent := FBox;
  AControl.Align := alTop;
  AControl.AlignWithMargins := True;
  AControl.Top := 1000 * (FParts.Count + 1);
  FParts.Add(AControl);
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

{ TAtlasCommentCommands }

constructor TAtlasCommentCommands.Create(AEditor: TAtlasCommentEditor);
begin
  inherited Create;
  FEditor := AEditor;
  // Menü und Tasten gehören dem Feld.
  FMenu := TPopupMenu.Create(AEditor);
  AEditor.Memo.OnKeyDown := MemoKeyDown;
  AEditor.Memo.OnKeyPress := MemoKeyPress;
end;

destructor TAtlasCommentCommands.Destroy;
begin
  FEditor.Memo.OnKeyDown := nil;
  FEditor.Memo.OnKeyPress := nil;
  inherited;
end;

procedure TAtlasCommentCommands.MemoKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  mAction: TAtlasCommentKey;
begin
  mAction := TAtlasCommentKeyPlan.Action(Key, Shift, FEditor.Enhanced, FEditor.Suggest.Shown);
  // Das Zeichen der Taste (Strg+I = Tab, Strg+Enter = Zeilenvorschub) nicht ins Memo; das Verlassen des Worts
  // bewegt die Schreibmarke trotzdem.
  FSwallowChar := TAtlasCommentKeyPlan.Swallows(mAction);
  if FSwallowChar then
  begin
    Key := 0;
  end;
  // Zuletzt: Senden oder Abbrechen kann das Feld schließen.
  Run(mAction);
end;

procedure TAtlasCommentCommands.MemoKeyPress(Sender: TObject; var Key: Char);
begin
  if FSwallowChar then
  begin
    Key := #0;
    FSwallowChar := False;
  end;
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
  Inc(mCaret.Y, MulDiv(Abs(AMemo.Font.Size), AMemo.CurrentPPI, cPointsPerInch) + cCaretGap);
  Result := AMemo.ClientToScreen(mCaret);
end;

procedure TAtlasCommentCommands.Run(AKey: TAtlasCommentKey);
begin
  case AKey of
    TAtlasCommentKey.None:
      begin
        // Die Taste gehört dem Memo.
      end;
    TAtlasCommentKey.Send:
      begin
        FEditor.Suggest.Hide;
        Fire(FEditor.Events.Send, FEditor);
      end;
    TAtlasCommentKey.Cancel:
      begin
        FEditor.Draft.Keep;
        Fire(FEditor.Events.Cancel, FEditor);
      end;
    TAtlasCommentKey.Up:
      FEditor.Suggest.Move(-1);
    TAtlasCommentKey.Down:
      FEditor.Suggest.Move(1);
    TAtlasCommentKey.PageUp:
      FEditor.Suggest.Move(-TAtlasCommentEditing.cMaxSuggestions);
    TAtlasCommentKey.PageDown:
      FEditor.Suggest.Move(TAtlasCommentEditing.cMaxSuggestions);
    TAtlasCommentKey.Accept:
      FEditor.Suggest.Accept(FEditor.Suggest.Selected);
    TAtlasCommentKey.CloseList, TAtlasCommentKey.LeaveWord:
      FEditor.Suggest.Hide;
    TAtlasCommentKey.Snippets:
      begin
        FEditor.Suggest.Hide;
        PopupSnippets(CaretScreenPoint(FEditor.Memo));
      end;
    TAtlasCommentKey.Bold:
      ApplyStyle(TAtlasCommentStyle.Bold);
    TAtlasCommentKey.Italic:
      ApplyStyle(TAtlasCommentStyle.Italic);
    TAtlasCommentKey.Code:
      ApplyStyle(TAtlasCommentStyle.Code);
  end;
end;

procedure TAtlasCommentCommands.ApplyStyle(AStyle: TAtlasCommentStyle);
var
  mStart, mLength: Integer;
  mText: string;
  mMemo: TMemo;
begin
  mMemo := FEditor.Memo;
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
  FEditor.ApplyEdit(mText, mStart, mLength);
end;

procedure TAtlasCommentCommands.PopupSnippets(const AScreen: TPoint);
var
  mSnippets: TArray<TAtlasCommentSnippet>;
  mItem: TMenuItem;
  mIndex: Integer;
begin
  if FEditor.Assist = nil then
  begin
    Exit;
  end;
  mSnippets := FEditor.Assist.Snippets;
  FMenu.Items.Clear;
  for mIndex := 0 to High(mSnippets) do
  begin
    mItem := TMenuItem.Create(FMenu);
    mItem.Caption := StringReplace(mSnippets[mIndex].Name, '&', '&&', [rfReplaceAll]);
    mItem.Tag := mIndex;
    mItem.OnClick := MenuClick;
    FMenu.Items.Add(mItem);
  end;
  if Length(mSnippets) = 0 then
  begin
    mItem := TMenuItem.Create(FMenu);
    mItem.Caption := TAtlasWorkflowStrings.Text(TAtlasWorkflowTextId.CommentEditorNoSnippets);
    mItem.Enabled := False;
    FMenu.Items.Add(mItem);
  end;
  FMenu.Popup(AScreen.X, AScreen.Y);
end;

procedure TAtlasCommentCommands.MenuClick(Sender: TObject);
begin
  InsertSnippet(TMenuItem(Sender).Tag);
end;

procedure TAtlasCommentCommands.InsertSnippet(AIndex: Integer);
var
  mSnippets: TArray<TAtlasCommentSnippet>;
  mText: string;
  mSelf: TAtlasCommentCommands;
begin
  if (FEditor.Assist = nil) or FEditor.Memo.ReadOnly then
  begin
    Exit;
  end;
  mSnippets := FEditor.Assist.Snippets;
  if (AIndex < 0) or (AIndex > High(mSnippets)) then
  begin
    Exit;
  end;
  mText := mSnippets[AIndex].Text;
  mSelf := Self;
  // Werte der Platzhalter kommen aus der IDE (Versionsverwaltung im Hintergrund).
  FEditor.Assist.Values(
    procedure(const AValues: TAtlasCommentValues)
    begin
      mSelf.SnippetReady(mText, AValues);
    end);
end;

procedure TAtlasCommentCommands.SnippetReady(const AText: string; const AValues: TAtlasCommentValues);
var
  mText: string;
  mCaret: Integer;
  mMemo: TMemo;
begin
  mMemo := FEditor.Memo;
  if mMemo.ReadOnly then
  begin
    Exit;
  end;
  FEditor.Previewing := False;
  mText := TAtlasCommentEditing.Insert(mMemo.Text, mMemo.SelStart, mMemo.SelLength,
    TAtlasCommentSnippets.Expand(MemoText(AText), AValues), mCaret);
  FEditor.ApplyEdit(mText, mCaret, 0);
  FocusMemo(mMemo);
end;

{ TAtlasCommentEditor }

/// <summary>Knopf in der Leiste; AWidth in logischen Pixeln (96 dpi).</summary>
function AddBarButton(AOwner: TComponent; ABar: TFlowPanel; AWidth: Integer; const ACaption: string): TButton;
begin
  Result := TButton.Create(AOwner);
  Result.Parent := ABar;
  Result.AlignWithMargins := True;
  Result.Width := Result.ScaleValue(AWidth);
  Result.Caption := ACaption;
end;

procedure TAtlasCommentEditor.AddBar;
const
  // Breiten der Knöpfe Vorschau und Textbaustein.
  cPreviewWidth = 90;
  cSnippetWidth = 120;
  cDraftWidth = 100;
  /// <summary>Hinweis zum Entwurf auf Höhe der Knopfbeschriftung.</summary>
  cNoteTop = 7;
begin
  FParts.Bar := TFlowPanel.Create(Self);
  FParts.Bar.Parent := Self;
  FParts.Bar.Align := alBottom;
  FParts.Bar.BevelOuter := bvNone;
  FParts.Bar.ShowCaption := False;
  FParts.Bar.AutoWrap := True;
  FParts.Bar.AutoSize := True;
  FParts.PreviewButton := AddBarButton(Self, FParts.Bar, cPreviewWidth,
    TAtlasWorkflowStrings.Text(TAtlasWorkflowTextId.CommentEditorPreview));
  FParts.PreviewButton.OnClick := ButtonClick;
  FParts.SnippetButton := AddBarButton(Self, FParts.Bar, cSnippetWidth,
    TAtlasWorkflowStrings.Text(TAtlasWorkflowTextId.CommentEditorSnippets));
  FParts.SnippetButton.OnClick := ButtonClick;
  FParts.DraftNote := TLabel.Create(Self);
  FParts.DraftNote.Parent := FParts.Bar;
  FParts.DraftNote.AlignWithMargins := True;
  FParts.DraftNote.AutoSize := True;
  FParts.DraftNote.Margins.Top := FParts.DraftNote.ScaleValue(cNoteTop);
  FParts.DraftNote.ShowAccelChar := False;
  FParts.DraftNote.Font.Color := clGrayText;
  FParts.DraftNote.Caption := '';
  FParts.DraftButton := AddBarButton(Self, FParts.Bar, cDraftWidth, '');
  FParts.DraftButton.Visible := False;
end;

procedure TAtlasCommentEditor.AddMemo;
begin
  FParts.Memo := TMemo.Create(Self);
  FParts.Memo.Parent := Self;
  FParts.Memo.Align := alClient;
  FParts.Memo.ScrollBars := ssVertical;
  FParts.Memo.WantReturns := True;
  FParts.Memo.WantTabs := False;
  FParts.Memo.Hint := TAtlasWorkflowStrings.Text(TAtlasWorkflowTextId.CommentEditorHint);
  FParts.Memo.ShowHint := True;
  FParts.Memo.OnChange := MemoChange;
  FParts.Memo.OnClick := MemoClick;
  FParts.Memo.OnExit := MemoExit;
  FParts.Preview := TScrollBox.Create(Self);
  FParts.Preview.Parent := Self;
  FParts.Preview.Align := alClient;
  FParts.Preview.Visible := False;
  FParts.Preview.VertScrollBar.Tracking := True;
end;

constructor TAtlasCommentEditor.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  ShowCaption := False;
  Caption := '';
  FEnhanced := True;
  AddBar;
  AddMemo;
  FSuggest := TAtlasCommentSuggest.Create(Self);
  FDraft := TAtlasCommentDraft.Create(Self);
  FPreview := TAtlasCommentPreview.Create(FParts.Preview);
  FCommands := TAtlasCommentCommands.Create(Self);
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
  FreeAndNil(FCommands);
  FreeAndNil(FSuggest);
  FreeAndNil(FDraft);
  FreeAndNil(FPreview);
  inherited;
end;

procedure TAtlasCommentEditor.SetMemoText(const AText: string);
begin
  FChanging := True;
  try
    FParts.Memo.Text := AText;
  finally
    FChanging := False;
  end;
end;

procedure TAtlasCommentEditor.ApplyEdit(const AText: string; AStart, ALength: Integer);
begin
  SetMemoText(AText);
  FParts.Memo.SelStart := AStart;
  FParts.Memo.SelLength := ALength;
  FDraft.Restart;
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
    FocusMemo(FParts.Memo);
  end;
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
  SetMemoText('');
  FDraft.Reset('');
end;

procedure TAtlasCommentEditor.SetText(const AText: string);
begin
  FSuggest.Hide;
  SetMemoText(MemoText(AText));
  FDraft.FInitialText := FParts.Memo.Text;
end;

procedure TAtlasCommentEditor.ButtonClick(Sender: TObject);
begin
  if Sender = FParts.PreviewButton then
  begin
    Previewing := not FPreviewing;
  end
  else if Sender = FParts.SnippetButton then
  begin
    FCommands.PopupSnippets(FParts.SnippetButton.ClientToScreen(Point(0, FParts.SnippetButton.Height)));
  end;
end;

function TAtlasCommentEditor.Text: string;
begin
  Result := StringReplace(FParts.Memo.Text, #13#10, #10, [rfReplaceAll]);
end;

end.
