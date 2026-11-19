unit Atlas.UI.Tracker.IssueFrame.Chrome;

// Feste Steuerelemente des Fensters „Atlas-Issue“ (#1264), die über jedem Issue gleich bleiben:
//   Werkzeugleiste [◀] [▶] [Beginnen] [Beenden …] [Prüfen …] [Im Browser öffnen] [Kennung kopieren] [Anhängen …]
//   [Aktualisieren] mit Kontextmenü (#1276) und Alt+Links/Alt+Rechts;
//   Ladeleiste und Statuszeile (Stand, Fehler mit Knopf zum Beheben, „Wird gespeichert …“);
//   Kommentarfeld unten (#1266, #1278);
//   Reiter „Details“ (Bildlauf des Inhalts) und „Entwicklung“ (#1269).
// Was die Knöpfe bewirken, entscheidet der Frame: Jeder Klick geht an AOnClick, der Tag ist
// cAtlasIssueToolTag + Ord(TAtlasIssueTool). Freischalten, Statuszeile und Reiter folgen dem Zustand, den der Frame
// übergibt.

interface

uses
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.ActnList,
  Vcl.Forms,
  Atlas.Core.Style.Palette,
  Atlas.Core.Tracker.Preview,
  Atlas.UI.Tracker.Issue.Strings,
  Atlas.UI.Tracker.IssueFrame.Contract;

type
  /// <summary>Werkzeugleiste, Statuszeile, Kommentarfeld und Reiter des Fensters „Atlas-Issue“; sie und die
  /// Steuerelemente gehören AFrame. Angelegt vor den Steuerelementen, wird sie erst nach ihnen freigegeben.</summary>
  TAtlasIssueChrome = class(TComponent)
  private
    FFrame: TFrame;
    FOnClick: TNotifyEvent;
    FParts: TAtlasIssueFrameParts;
    FFixKind: TAtlasIssueFix;
    /// <summary>Knopf in der Werkzeugleiste hinter den bisherigen.</summary>
    function AddTool(const ACaption: string; ATool: TAtlasIssueTool): TButton;
    /// <summary>Knopf mit Text und Tooltip aus den Texten des Fensters.</summary>
    function AddHintedTool(ACaption, AHint: TAtlasIssueTextId; ATool: TAtlasIssueTool): TButton;
    procedure AddMenu;
    procedure AddToolbar;
    procedure AddStatus;
    function AddCommentLabel(AAlign: TAlign; const ACaption: string): TLabel;
    procedure AddCommentPanel;
    function AddSheet(AText: TAtlasIssueTextId): TTabSheet;
    procedure AddPages;
    procedure AddActions;
    procedure ScrollWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint;
      var Handled: Boolean);
  public
    /// <summary>Legt alle festen Steuerelemente in AFrame an; Klicks gehen an AOnClick.</summary>
    constructor Create(AFrame: TFrame; AOnClick: TNotifyEvent); reintroduce;
    /// <summary>Knöpfe, Menü und Kommentarfeld nach Issue (AHasDetails) und Schaltern freischalten.</summary>
    procedure UpdateButtons(AHasDetails: Boolean; AFlags: TAtlasIssueFlags);
    /// <summary>Statuszeile mit AText ohne Knopf zeigen.</summary>
    procedure ShowStatusLine(const AText: string; AVisible: Boolean);
    /// <summary>Fehler bzw. Hinweis mit Knopf zum Beheben (TAtlasIssueFix.None: ohne Knopf).</summary>
    procedure ShowError(const AText: string; AFix: TAtlasIssueFix);
    procedure HideStatus;
    /// <summary>Laden beginnt bzw. endet; ohne bisherigen Inhalt (AHasDetails) steht „Wird geladen …“ da.</summary>
    procedure LoadingChanged(AValue, AHasDetails: Boolean);
    /// <summary>Zurückschreiben der Checkliste läuft (#1273): „Wird gespeichert …“.</summary>
    procedure BusyChanged(AValue: Boolean);
    /// <summary>Kommentar wird gesendet (#1266): Feld gesperrt.</summary>
    procedure SendingChanged(AValue: Boolean);
    /// <summary>Ergebnis des Sendens: AError '' = gesendet (Feld und Entwurf leer), sonst der Grund unter dem Feld.
    /// </summary>
    procedure CommentDone(const AError: string);
    /// <summary>Text im Kommentarfeld ohne Leerraum außen, Zeilenenden als #10.</summary>
    function CommentText: string;
    /// <summary>Reiter „Entwicklung“ zeigen oder verbergen; ohne Fenster bleibt es beim nächsten Aufruf.</summary>
    procedure ApplyTabs(AShowDevelopment: Boolean);
    /// <summary>Reiter wählen; True, wenn „Entwicklung“ dadurch neu gewählt wurde.</summary>
    function SelectPage(ADevelopment: Boolean): Boolean;
    function DevelopmentSelected: Boolean;
    procedure SetHistory(ACanBack, ACanForward: Boolean);
    procedure ApplyColors(const AColors: TAtlasColors);
    /// <summary>Text der Statuszeile; '' wenn sie verborgen ist.</summary>
    function StatusText: string;
    property Parts: TAtlasIssueFrameParts read FParts;
    /// <summary>Was der Knopf der Statuszeile beheben soll.</summary>
    property FixKind: TAtlasIssueFix read FFixKind;
  end;

implementation

uses
  System.Actions,
  System.Math,
  System.SysUtils,
  System.UITypes,
  Winapi.Windows,
  Vcl.Graphics,
  Vcl.ExtCtrls,
  Vcl.Menus,
  Atlas.UI.Foundation.WrapLabel,
  Atlas.UI.Tracker.CommentEditor,
  Atlas.UI.Tracker.DevelopmentView,
  Atlas.UI.Foundation.Scaling;

const
  /// <summary>Maße bei 96 dpi: Knöpfe der Werkzeugleiste, Leiste, Pfeilknöpfe, Mindestbreite und Breite je Zeichen
  /// eines Knopfs.</summary>
  cToolHeight = 26;
  cToolbarHeight = 32;
  cArrowWidth = 32;
  cToolMinWidth = 80;
  cCharWidth = 8;
  /// <summary>Ladeleiste, Abstand der Statuszeile unter der Werkzeugleiste, Statuszeile, Knopf zum Beheben.
  /// </summary>
  cProgressHeight = 3;
  cStatusGap = 10;
  cStatusHeight = 30;
  cFixWidth = 150;
  /// <summary>Kommentarfeld und Knopf „Senden“.</summary>
  cCommentHeight = 150;
  cSendWidth = 90;
  /// <summary>Innenabstand des Bildlaufs (links, oben, rechts, unten).</summary>
  cScrollPadSide = 8;
  cScrollPadTop = 4;

{ TAtlasIssueChrome }

constructor TAtlasIssueChrome.Create(AFrame: TFrame; AOnClick: TNotifyEvent);
begin
  inherited Create(AFrame);
  FFrame := AFrame;
  FOnClick := AOnClick;
  AddToolbar;
  AddStatus;
  AddCommentPanel;
  AddPages;
  AddActions;
end;

function TAtlasIssueChrome.AddTool(const ACaption: string; ATool: TAtlasIssueTool): TButton;
begin
  Result := TButton.Create(FFrame);
  // Reihenfolge wie angelegt: Die Leiste reiht in der Reihenfolge der Kinder.
  Result.Parent := FParts.Tools;
  Result.AlignWithMargins := True;
  Result.Height := Result.ScaleValue(cToolHeight);
  Result.Caption := ACaption;
  Result.ShowHint := True;
  Result.Width := Result.ScaleValue(Max(cToolMinWidth, Length(ACaption) * cCharWidth));
  Result.Tag := cAtlasIssueToolTag + Ord(ATool);
  Result.OnClick := FOnClick;
end;

function TAtlasIssueChrome.AddHintedTool(ACaption, AHint: TAtlasIssueTextId; ATool: TAtlasIssueTool): TButton;
begin
  Result := AddTool(TAtlasIssueStrings.Text(ACaption), ATool);
  Result.Hint := TAtlasIssueStrings.Text(AHint);
end;

/// <summary>Kontextmenü des Fensters (#1276): Kinder ohne eigenes Menü übernehmen es.</summary>
procedure TAtlasIssueChrome.AddMenu;
begin
  FParts.Menu := TPopupMenu.Create(FFrame);
  FParts.AttachItem := TMenuItem.Create(FParts.Menu);
  FParts.AttachItem.Caption := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewAttachMenu);
  FParts.AttachItem.Tag := cAtlasIssueToolTag + Ord(TAtlasIssueTool.Attach);
  FParts.AttachItem.OnClick := FOnClick;
  FParts.AttachItem.Visible := False;
  FParts.Menu.Items.Add(FParts.AttachItem);
  FFrame.PopupMenu := FParts.Menu;
end;

/// <summary>Werkzeugleiste: Zurück, Vor, Beginnen, Beenden, Prüfen, Browser, Kennung, Anhängen,
/// Aktualisieren.</summary>
procedure TAtlasIssueChrome.AddToolbar;
begin
  FParts.Tools := TFlowPanel.Create(FFrame);
  FParts.Tools.Height := FParts.Tools.ScaleValue(cToolbarHeight);
  FParts.Tools.Parent := FFrame;
  FParts.Tools.Align := alTop;
  FParts.Tools.BevelOuter := bvNone;
  FParts.Tools.ShowCaption := False;
  // Schmales Fenster: Knöpfe in die nächste Zeile statt abgeschnitten.
  FParts.Tools.AutoSize := True;
  FParts.Back := AddTool('◀', TAtlasIssueTool.Back);
  FParts.Back.Hint := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewBack);
  FParts.Back.Width := FParts.Back.ScaleValue(cArrowWidth);
  FParts.Forward := AddTool('▶', TAtlasIssueTool.Forward);
  FParts.Forward.Hint := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewForward);
  FParts.Forward.Width := FParts.Forward.ScaleValue(cArrowWidth);
  FParts.Start := AddTool(TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewStart), TAtlasIssueTool.Start);
  FParts.Finish := AddHintedTool(TAtlasIssueTextId.IssuePreviewEnd, TAtlasIssueTextId.IssuePreviewEndHint,
    TAtlasIssueTool.Finish);
  FParts.Finish.Visible := False;
  FParts.Review := AddHintedTool(TAtlasIssueTextId.IssuePreviewReview, TAtlasIssueTextId.IssuePreviewReviewHint,
    TAtlasIssueTool.Review);
  FParts.Review.Visible := False;
  FParts.Browse := AddTool(TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewBrowse), TAtlasIssueTool.Browse);
  FParts.CopyKey := AddTool(TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewCopyKey),
    TAtlasIssueTool.CopyKey);
  FParts.Attach := AddHintedTool(TAtlasIssueTextId.IssuePreviewAttach, TAtlasIssueTextId.IssuePreviewAttachHint,
    TAtlasIssueTool.Attach);
  FParts.Attach.Visible := False;
  AddMenu;
  FParts.Refresh := AddTool(TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewRefresh),
    TAtlasIssueTool.Refresh);
end;

/// <summary>Leiste beim Laden und Zeile für Stand, Fehler und Hinweise mit Knopf zum Beheben.</summary>
procedure TAtlasIssueChrome.AddStatus;
begin
  FParts.Progress := TProgressBar.Create(FFrame);
  FParts.Progress.Parent := FFrame;
  FParts.Progress.Align := alTop;
  FParts.Progress.Top := FParts.Tools.Height;
  FParts.Progress.Height := FParts.Progress.ScaleValue(cProgressHeight);
  FParts.Progress.Style := pbstMarquee;
  FParts.Progress.Visible := False;
  FParts.Status := TPanel.Create(FFrame);
  FParts.Status.Parent := FFrame;
  FParts.Status.Align := alTop;
  FParts.Status.Top := FParts.Tools.Height + FParts.Status.ScaleValue(cStatusGap);
  FParts.Status.BevelOuter := bvNone;
  FParts.Status.Height := FParts.Status.ScaleValue(cStatusHeight);
  FParts.Status.ShowCaption := False;
  FParts.Status.Visible := False;
  FParts.Fix := TButton.Create(FFrame);
  FParts.Fix.Parent := FParts.Status;
  FParts.Fix.Align := alRight;
  FParts.Fix.AlignWithMargins := True;
  FParts.Fix.Width := FParts.Fix.ScaleValue(cFixWidth);
  FParts.Fix.Tag := cAtlasIssueToolTag + Ord(TAtlasIssueTool.Fix);
  FParts.Fix.OnClick := FOnClick;
  FParts.StatusLabel := TLabel.Create(FFrame);
  FParts.StatusLabel.Parent := FParts.Status;
  FParts.StatusLabel.Align := alClient;
  FParts.StatusLabel.AlignWithMargins := True;
  FParts.StatusLabel.Layout := tlCenter;
  FParts.StatusLabel.ShowAccelChar := False;
  FParts.StatusLabel.EllipsisPosition := epEndEllipsis;
end;

function TAtlasIssueChrome.AddCommentLabel(AAlign: TAlign; const ACaption: string): TLabel;
begin
  Result := TLabel.Create(FFrame);
  Result.Parent := FParts.CommentPanel;
  Result.Align := AAlign;
  Result.AlignWithMargins := True;
  Result.ShowAccelChar := False;
  Result.Caption := ACaption;
end;

/// <summary>Kommentar schreiben (#1266): unten, nur mit CanWrite.</summary>
procedure TAtlasIssueChrome.AddCommentPanel;
begin
  FParts.CommentPanel := TPanel.Create(FFrame);
  FParts.CommentPanel.Parent := FFrame;
  FParts.CommentPanel.Align := alBottom;
  FParts.CommentPanel.BevelOuter := bvNone;
  FParts.CommentPanel.Height := FParts.CommentPanel.ScaleValue(cCommentHeight);
  FParts.CommentPanel.ShowCaption := False;
  FParts.CommentPanel.Visible := False;
  FParts.CommentHint := AddCommentLabel(alTop, TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewCommentHint));
  FParts.CommentNote := AddCommentLabel(alBottom, '');
  FParts.CommentSend := TButton.Create(FFrame);
  FParts.CommentSend.Parent := FParts.CommentPanel;
  FParts.CommentSend.Align := alRight;
  FParts.CommentSend.AlignWithMargins := True;
  FParts.CommentSend.Width := FParts.CommentSend.ScaleValue(cSendWidth);
  FParts.CommentSend.Caption := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewCommentSend);
  FParts.CommentSend.Tag := cAtlasIssueToolTag + Ord(TAtlasIssueTool.CommentSend);
  FParts.CommentSend.OnClick := FOnClick;
  // Kommentar-Editor (#1278): Strg+Enter sendet; Vorschläge, Textbausteine und Entwurf, sobald die IDE ihn bindet.
  FParts.Comment := TAtlasCommentEditor.Create(FFrame);
  FParts.Comment.Parent := FParts.CommentPanel;
  FParts.Comment.Align := alClient;
  FParts.Comment.AlignWithMargins := True;
  FParts.Comment.Tag := cAtlasIssueToolTag + Ord(TAtlasIssueTool.CommentSend);
  FParts.Comment.Events := TAtlasCommentEditorEvents.Create(FOnClick, nil);
  FParts.CommentEdit := FParts.Comment.Memo;
end;

function TAtlasIssueChrome.AddSheet(AText: TAtlasIssueTextId): TTabSheet;
begin
  Result := TTabSheet.Create(FFrame);
  Result.TabVisible := False;
  Result.PageControl := FParts.Pages;
  Result.Caption := TAtlasIssueStrings.Text(AText);
end;

/// <summary>Reiter „Details“ (Bildlauf mit dem Inhalt) und „Entwicklung“ (#1269).</summary>
procedure TAtlasIssueChrome.AddPages;
begin
  FParts.Pages := TPageControl.Create(FFrame);
  FParts.Pages.Parent := FFrame;
  FParts.Pages.Align := alClient;
  // Ohne Reiter einhängen: Ein sichtbarer Reiter braucht das Fenster des PageControls (ApplyTabs in CreateWnd).
  FParts.DetailsSheet := AddSheet(TAtlasIssueTextId.IssuePreviewTabDetails);
  FParts.DevelopmentSheet := AddSheet(TAtlasIssueTextId.IssuePreviewTabDevelopment);
  FParts.Pages.Tag := cAtlasIssueToolTag + Ord(TAtlasIssueTool.Pages);
  FParts.Pages.OnChange := FOnClick;
  FParts.Development := TAtlasIssueDevelopmentView.Create(FFrame);
  FParts.Development.Parent := FParts.DevelopmentSheet;
  FParts.Development.Align := alClient;
  FParts.Scroll := TScrollBox.Create(FFrame);
  FParts.Scroll.Parent := FParts.DetailsSheet;
  FParts.Scroll.Align := alClient;
  FParts.Scroll.BorderStyle := bsNone;
  FParts.Scroll.VertScrollBar.Tracking := True;
  FParts.Scroll.HorzScrollBar.Visible := False;
  TAtlasControlScaling.SetPadding(FParts.Scroll, cScrollPadSide, cScrollPadTop, cScrollPadSide, cScrollPadSide);
  FParts.Scroll.OnMouseWheel := ScrollWheel;
  FParts.Empty := TAtlasWrapLabel.Create(FFrame);
  FParts.Empty.Parent := FParts.Scroll;
  FParts.Empty.Align := alTop;
  FParts.Empty.AlignWithMargins := True;
  FParts.Empty.ShowAccelChar := False;
  FParts.Empty.Caption := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewEmpty);
end;

/// <summary>Alt+Links und Alt+Rechts blättern im Verlauf.</summary>
procedure TAtlasIssueChrome.AddActions;
begin
  FParts.Actions := TActionList.Create(FFrame);
  FParts.BackAction := TAction.Create(FFrame);
  FParts.BackAction.ActionList := FParts.Actions;
  FParts.BackAction.ShortCut := ShortCut(VK_LEFT, [ssAlt]);
  FParts.BackAction.Tag := cAtlasIssueToolTag + Ord(TAtlasIssueTool.Back);
  FParts.BackAction.OnExecute := FOnClick;
  FParts.ForwardAction := TAction.Create(FFrame);
  FParts.ForwardAction.ActionList := FParts.Actions;
  FParts.ForwardAction.ShortCut := ShortCut(VK_RIGHT, [ssAlt]);
  FParts.ForwardAction.Tag := cAtlasIssueToolTag + Ord(TAtlasIssueTool.Forward);
  FParts.ForwardAction.OnExecute := FOnClick;
end;

procedure TAtlasIssueChrome.ScrollWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint; var Handled: Boolean);
begin
  FParts.Scroll.VertScrollBar.Position := FParts.Scroll.VertScrollBar.Position - WheelDelta div 2;
  Handled := True;
end;

procedure TAtlasIssueChrome.UpdateButtons(AHasDetails: Boolean; AFlags: TAtlasIssueFlags);
var
  mWrite, mAttach, mLoading: Boolean;
begin
  mWrite := TAtlasIssueFlag.CanWrite in AFlags;
  mAttach := TAtlasIssueFlag.CanAttach in AFlags;
  mLoading := TAtlasIssueFlag.Loading in AFlags;
  FParts.Start.Enabled := AHasDetails and (TAtlasIssueFlag.CanStart in AFlags);
  // Ausgeblendete Knöpfe mit alLeft reihen sich nach Left ein: direkt hinter „Beginnen“.
  if mWrite and not FParts.Finish.Visible then
  begin
    FParts.Finish.Left := FParts.Start.Left + FParts.Start.Width + 1;
  end;
  FParts.Finish.Visible := mWrite;
  FParts.Finish.Enabled := AHasDetails and (TAtlasIssueFlag.CanEnd in AFlags);
  FParts.Review.Visible := AHasDetails and (TAtlasIssueFlag.CanReview in AFlags);
  FParts.CommentPanel.Visible := mWrite and AHasDetails;
  FParts.CommentSend.Enabled := AHasDetails and not (TAtlasIssueFlag.CommentSending in AFlags);
  FParts.Browse.Enabled := AHasDetails;
  FParts.CopyKey.Enabled := AHasDetails;
  FParts.Attach.Visible := mAttach;
  FParts.Attach.Enabled := AHasDetails;
  FParts.AttachItem.Visible := mAttach;
  FParts.AttachItem.Enabled := AHasDetails;
  FParts.Refresh.Enabled := AHasDetails or mLoading;
  FParts.Refresh.Caption := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewRefresh);
  if mLoading then
  begin
    FParts.Refresh.Caption := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewCancel);
  end;
  FParts.BackAction.Enabled := FParts.Back.Enabled;
  FParts.ForwardAction.Enabled := FParts.Forward.Enabled;
end;

procedure TAtlasIssueChrome.ShowStatusLine(const AText: string; AVisible: Boolean);
begin
  FParts.StatusLabel.Caption := AText;
  FParts.Fix.Visible := False;
  FParts.Status.Visible := AVisible;
end;

function FixCaption(AFix: TAtlasIssueFix): string;
begin
  Result := '';
  case AFix of
    TAtlasIssueFix.EnterToken:
      Result := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewFixToken);
    TAtlasIssueFix.Settings:
      Result := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewFixSettings);
    TAtlasIssueFix.Browser:
      Result := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewBrowse);
    TAtlasIssueFix.Retry:
      Result := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewFixRetry);
    TAtlasIssueFix.None:
      begin
        // Kein Knopf.
      end;
  end;
end;

procedure TAtlasIssueChrome.ShowError(const AText: string; AFix: TAtlasIssueFix);
begin
  FFixKind := AFix;
  FParts.StatusLabel.Caption := AText;
  FParts.Fix.Visible := AFix <> TAtlasIssueFix.None;
  if FParts.Fix.Visible then
  begin
    FParts.Fix.Caption := FixCaption(AFix);
  end;
  FParts.Status.Visible := True;
end;

procedure TAtlasIssueChrome.HideStatus;
begin
  FParts.Status.Visible := False;
end;

procedure TAtlasIssueChrome.LoadingChanged(AValue, AHasDetails: Boolean);
begin
  FParts.Progress.Visible := AValue;
  if AValue then
  begin
    ShowStatusLine(TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewLoading), not AHasDetails);
  end;
end;

procedure TAtlasIssueChrome.BusyChanged(AValue: Boolean);
var
  mSaving: string;
begin
  mSaving := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssueChecklistSaving);
  if AValue then
  begin
    ShowStatusLine(mSaving, True);
  end
  else if FParts.StatusLabel.Caption = mSaving then
  begin
    FParts.Status.Visible := False;
  end;
end;

procedure TAtlasIssueChrome.SendingChanged(AValue: Boolean);
begin
  FParts.CommentEdit.ReadOnly := AValue;
  if AValue then
  begin
    FParts.CommentNote.Caption := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewCommentSending);
  end;
end;

procedure TAtlasIssueChrome.CommentDone(const AError: string);
begin
  FParts.CommentNote.Caption := AError;
  // Gesendet: Feld leeren und den Entwurf löschen; bei einem Fehler bleibt beides.
  if AError = '' then
  begin
    FParts.Comment.Sent;
  end;
end;

function TAtlasIssueChrome.CommentText: string;
begin
  Result := StringReplace(Trim(FParts.CommentEdit.Text), #13#10, #10, [rfReplaceAll]);
end;

procedure TAtlasIssueChrome.ApplyTabs(AShowDevelopment: Boolean);
begin
  // Sichtbare Reiter brauchen das Fenster des PageControls; ohne bleibt es beim Schalter Development.
  if not FFrame.HandleAllocated then
  begin
    Exit;
  end;
  FParts.DevelopmentSheet.TabVisible := AShowDevelopment;
  // Mit nur einem Reiter keine Reiterleiste.
  FParts.DetailsSheet.TabVisible := AShowDevelopment;
  FParts.Pages.ActivePage := FParts.DetailsSheet;
end;

function TAtlasIssueChrome.SelectPage(ADevelopment: Boolean): Boolean;
begin
  Result := False;
  if not ADevelopment then
  begin
    FParts.Pages.ActivePage := FParts.DetailsSheet;
  end
  else if FParts.Pages.ActivePage <> FParts.DevelopmentSheet then
  begin
    FParts.Pages.ActivePage := FParts.DevelopmentSheet;
    Result := True;
  end;
end;

function TAtlasIssueChrome.DevelopmentSelected: Boolean;
begin
  Result := FParts.Pages.ActivePage = FParts.DevelopmentSheet;
end;

procedure TAtlasIssueChrome.SetHistory(ACanBack, ACanForward: Boolean);
begin
  FParts.Back.Enabled := ACanBack;
  FParts.Forward.Enabled := ACanForward;
end;

procedure TAtlasIssueChrome.ApplyColors(const AColors: TAtlasColors);
begin
  FParts.Scroll.Color := TColor(AColors.Surface);
  FParts.Scroll.ParentBackground := False;
  FParts.Development.ApplyColors(AColors);
  FParts.Empty.Font.Color := TColor(AColors.Muted);
  FParts.CommentHint.Font.Color := TColor(AColors.Muted);
  FParts.CommentNote.Font.Color := TColor(AColors.Muted);
  FParts.Comment.Preview.ApplyColors(AColors);
end;

function TAtlasIssueChrome.StatusText: string;
begin
  Result := '';
  if FParts.Status.Visible then
  begin
    Result := FParts.StatusLabel.Caption;
  end;
end;

end.
