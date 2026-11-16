unit Atlas.UI.Editor.LearnedSuggestions;

// Gelernte Vorschläge (#1890): Texte für Befehl, Optionsseite und die Liste
// „Gelernte Vorschläge“, deutsch und englisch (eigene Tabelle, weil
// Atlas.UI.Strings über der Grenze der Unitlänge liegt), und die Liste selbst,
// reine VCL: je Muster Auslöser, Folge, Anteil, Stellen, Herkunft (Projekt
// oder atlas.json) und wie oft es übernommen bzw. verworfen wurde. Das
// Kästchen schaltet ein Muster ab, „Vergessen“ löscht seine Lernzähler,
// Doppelklick bzw. „Zum Beleg“ zeigt die erste Stelle. Die Liste kennt die
// Ablage nicht; die IDE-Schicht reicht Zustand und Rückrufe herein.
// Das Fenster ist ein TAtlasDialog (Dialogschrift, IDE-Thema), ziehbar; die
// Liste füllt den Platz zwischen Einleitung und Knopfleiste, Spalten passen
// sich dem Inhalt an („Folge“ nimmt den Rest), Klick auf den Kopf sortiert.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Vcl.Forms,
  Atlas.Core.Localization.Language,
  Atlas.Core.Editor.LearnedSuggestions;

type
{$SCOPEDENUMS ON}
  TAtlasLearnedText = (Command, Title, Intro, Empty, NoServer, ColumnTrigger, ColumnFollow, ColumnShare, ColumnCount,
    ColumnOrigin, ColumnUsed, OriginProject, OriginTeam, Used, Forget, GoToExample, Close, SettingLearned, SettingDelay,
    SettingMinShare, SettingMinCount, SettingLearnFromUsage);
{$SCOPEDENUMS OFF}

  TAtlasLearnedTexts = class
  public
    class function Text(AId: TAtlasLearnedText): string; static;
  end;

  /// <summary>Zeile der Liste.</summary>
  TAtlasLearnedListItem = record
    Pattern: TAtlasLearnedPattern;
    /// <summary>Nicht abgeschaltet.</summary>
    On_: Boolean;
    Accepted: Integer;
    Rejected: Integer;
  end;

  /// <summary>Rückrufe der Liste; AIndex zählt in den übergebenen Zeilen.</summary>
  TAtlasLearnedListEvents = record
    /// <summary>Muster an- bzw. abschalten.</summary>
    Toggle: TProc<Integer, Boolean>;
    /// <summary>Lernzähler vergessen; liefert die Zeile danach.</summary>
    Forget: TFunc<Integer, TAtlasLearnedListItem>;
    /// <summary>Zum ersten Beleg springen.</summary>
    GoTo_: TProc<Integer>;
  end;

  TAtlasLearnedList = class
  public
    /// <summary>Modal; kehrt mit „Schließen“ oder Esc zurück.</summary>
    class procedure Execute(const AItems: TArray<TAtlasLearnedListItem>; const AEvents: TAtlasLearnedListEvents);
      static;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.CommCtrl,
  System.Types,
  System.Math,
  Vcl.Graphics,
  Atlas.UI.Foundation.Dialog,
  Atlas.UI.Foundation.ListView,
  Atlas.UI.Foundation.WrapLabel;

const
  cTexts: array[TAtlasLanguage, TAtlasLearnedText] of string = (
    ('Gelernte Vorschläge anzeigen …', 'Gelernte Vorschläge',
      'Was im Projekt meist auf einen Auslöser folgt. Das Kästchen schaltet ein Muster ab, „Vergessen“ löscht, wie ' +
      'oft es übernommen oder verworfen wurde.',
      'Noch keine Muster ab zwei Stellen. Atlas lernt beim Indizieren aus dem Projekt und aus suggestions.patterns ' +
      'in atlas.json.',
      'Die Liste ist nicht verfügbar: Der Atlas-Server läuft nicht oder antwortet nicht.',
      'Auslöser', 'Folge', 'Anteil', 'Stellen', 'Herkunft', 'Genutzt', 'Projekt', 'atlas.json',
      '%d× übernommen, %d× verworfen', 'Vergessen', 'Zum Beleg', 'Schließen',
      'Gelernte Vorschläge nach Enter (Tab übernimmt, Esc verwirft)', 'Pause bis zum Vorschlag (ms):',
      'Mindestanteil der Folge (%):', 'Mindestzahl der Stellen:', 'Aus der Nutzung lernen (Tab und Esc zählen)'),
    ('Show learned suggestions …', 'Learned suggestions',
      'What usually follows a trigger in the project. The check box turns a pattern off, "Forget" clears how often ' +
      'it was accepted or discarded.',
      'No patterns with two or more places yet. Atlas learns while indexing the project and from ' +
      'suggestions.patterns in atlas.json.',
      'The list is not available: the Atlas server is not running or does not answer.',
      'Trigger', 'Follow-up', 'Share', 'Places', 'Origin', 'Used', 'Project', 'atlas.json',
      '%d× accepted, %d× discarded', 'Forget', 'Go to example', 'Close',
      'Learned suggestions after Enter (Tab accepts, Esc discards)', 'Pause before the suggestion (ms):',
      'Minimum share of the follow-up (%):', 'Minimum number of places:', 'Learn from usage (Tab and Esc count)'));

{ TAtlasLearnedTexts }

class function TAtlasLearnedTexts.Text(AId: TAtlasLearnedText): string;
begin
  Result := cTexts[TAtlasTextLanguage.Current, AId];
end;

function T(AId: TAtlasLearnedText): string;
begin
  Result := TAtlasLearnedTexts.Text(AId);
end;

const
  /// <summary>Maße in Pixeln bei 96 dpi.</summary>
  cWindowWidth = 860;
  cMinWidth = 520;
  cMinHeight = 280;
  cGap = 8;
  cButtonBarHeight = 44;
  cButtonPadding = 32;
  cButtonMinWidth = 90;
  /// <summary>Spalte „Folge“ füllt den Rest, mindestens so breit.</summary>
  cFollowMinWidth = 160;
  /// <summary>Übrige Spalten nach Inhalt, höchstens so breit.</summary>
  cColumnMaxWidth = 320;
  /// <summary>Anfangs so viele Zeilen sichtbar, mehr nur mit Rollen.</summary>
  cInitialRows = 18;
  /// <summary>Höchstens dieser Anteil (Prozent) des Arbeitsbereichs als Anfangsgröße.</summary>
  cMaxScreenShare = 80;
  cColumnFollow = 1;

type
  /// <summary>Fenster der Liste mit seinen Ereignissen.</summary>
  TListWindow = class(TAtlasDialog)
  private
    FItems: TArray<TAtlasLearnedListItem>;
    FEvents: TAtlasLearnedListEvents;
    FIntro: TLabel;
    FButtons: TPanel;
    FList: TAtlasListView;
    FForget: TButton;
    FGoTo: TButton;
    /// <summary>Beim Füllen keine Rückrufe für die Kästchen.</summary>
    FFilling: Boolean;
    procedure Fill(AItem: TListItem; const ARow: TAtlasLearnedListItem);
    procedure Build;
    procedure BuildIntro;
    procedure BuildButtons;
    procedure BuildList;
    procedure FillList;
    procedure FitToContent;
    function AddButton(const ACaption: string; AAlign: TAlign): TButton;
    procedure ItemChecked(Sender: TObject; Item: TListItem);
    procedure ItemSelected(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure ForgetClick(Sender: TObject);
    procedure GoToClick(Sender: TObject);
    procedure UpdateButtons;
  end;

{ TListWindow }

procedure TListWindow.Fill(AItem: TListItem; const ARow: TAtlasLearnedListItem);
var
  mOrigin: string;
begin
  mOrigin := T(TAtlasLearnedText.OriginProject);
  if ARow.Pattern.Team then
  begin
    mOrigin := T(TAtlasLearnedText.OriginTeam);
  end;
  AItem.Caption := ARow.Pattern.Trigger;
  AItem.SubItems.Clear;
  AItem.SubItems.Add(ARow.Pattern.Text);
  AItem.SubItems.Add(Format('%d %%', [ARow.Pattern.Share]));
  AItem.SubItems.Add(Format('%d / %d', [ARow.Pattern.Count, ARow.Pattern.Total]));
  AItem.SubItems.Add(mOrigin);
  AItem.SubItems.Add(Format(T(TAtlasLearnedText.Used), [ARow.Accepted, ARow.Rejected]));
  AItem.Checked := ARow.On_;
end;

procedure TListWindow.Build;
begin
  BorderStyle := bsSizeable;
  BorderIcons := [biSystemMenu];
  // Reihenfolge: Leiste unten und Einleitung oben vor der Liste, die den Rest füllt.
  BuildButtons;
  BuildIntro;
  BuildList;
  FillList;
  FitToContent;
  FList.OnItemChecked := ItemChecked;
  FList.OnSelectItem := ItemSelected;
  FList.OnDblClick := GoToClick;
  if FList.Items.Count > 0 then
  begin
    FList.Items[0].Selected := True;
    ActiveControl := FList;
  end;
  UpdateButtons;
end;

procedure TListWindow.BuildIntro;
begin
  // Umbrechende Beschriftung: Ein TLabel behielte die Höhe, die es bei seiner Anfangsbreite (65 Pixel) hatte.
  FIntro := TAtlasWrapLabel.Create(Self);
  FIntro.Top := 0;
  FIntro.AlignWithMargins := True;
  FIntro.Margins.SetBounds(ScaleValue(cGap), ScaleValue(cGap), ScaleValue(cGap), ScaleValue(cGap));
  FIntro.Caption := T(TAtlasLearnedText.Intro);
  if Length(FItems) = 0 then
  begin
    FIntro.Caption := FIntro.Caption + sLineBreak + sLineBreak + T(TAtlasLearnedText.Empty);
  end;
  FIntro.Align := alTop;
  FIntro.Parent := Self;
end;

procedure TListWindow.BuildButtons;
var
  mClose: TButton;
begin
  FButtons := TPanel.Create(Self);
  // Lage vor Align und Parent: Sonst kann die VCL die Reihenfolge beim Anlegen des Fensters vertauschen.
  FButtons.Top := ClientHeight;
  FButtons.Height := ScaleValue(cButtonBarHeight);
  FButtons.BevelOuter := bvNone;
  FButtons.ShowCaption := False;
  FButtons.Align := alBottom;
  FButtons.Parent := Self;
  FForget := AddButton(T(TAtlasLearnedText.Forget), alLeft);
  FForget.OnClick := ForgetClick;
  FGoTo := AddButton(T(TAtlasLearnedText.GoToExample), alLeft);
  FGoTo.Left := FForget.Left + FForget.Width + 1;
  FGoTo.OnClick := GoToClick;
  mClose := AddButton(T(TAtlasLearnedText.Close), alRight);
  mClose.ModalResult := mrOk;
  mClose.Cancel := True;
  mClose.Default := True;
end;

procedure TListWindow.BuildList;
begin
  FList := TAtlasListView.Create(Self);
  FList.AlignWithMargins := True;
  FList.Margins.SetBounds(ScaleValue(cGap), 0, ScaleValue(cGap), 0);
  FList.Align := alClient;
  FList.Parent := Self;
  FList.Checkboxes := True;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  FList.HideSelection := False;
  FList.Sortable := True;
  // Breiten setzt FitToContent nach dem Inhalt; hier nur die Spalten.
  FList.AddColumn(T(TAtlasLearnedText.ColumnTrigger), 0);
  FList.AddColumn(T(TAtlasLearnedText.ColumnFollow), 0);
  FList.AddColumn(T(TAtlasLearnedText.ColumnShare), 0, taRightJustify);
  FList.AddColumn(T(TAtlasLearnedText.ColumnCount), 0, taRightJustify);
  FList.AddColumn(T(TAtlasLearnedText.ColumnOrigin), 0);
  FList.AddColumn(T(TAtlasLearnedText.ColumnUsed), 0);
end;

procedure TListWindow.FillList;
var
  mIndex: Integer;
  mItem: TListItem;
begin
  // Ohne Fenster nimmt die Liste keine Zeilen an (Items braucht ein Handle).
  FList.HandleNeeded;
  FFilling := True;
  FList.Items.BeginUpdate;
  try
    for mIndex := 0 to High(FItems) do
    begin
      mItem := FList.Items.Add;
      mItem.Data := Pointer(mIndex);
      Fill(mItem, FItems[mIndex]);
    end;
  finally
    FList.Items.EndUpdate;
    FFilling := False;
  end;
end;

procedure TListWindow.FitToContent;
var
  mArea, mRow: TRect;
  mWidth, mIndex, mRows, mRowHeight, mHeight: Integer;
begin
  mArea := MainFormWorkArea;
  FList.FillColumn(cColumnFollow, cFollowMinWidth);
  FList.FitColumnsToContent(cColumnMaxWidth);
  // Breit genug für alle Spalten samt ganzer Folge, Rand und senkrechter Rollleiste.
  mWidth := FList.ContentWidth(cColumnFollow) + 2 * ScaleValue(cGap) +
    MulDiv(GetSystemMetrics(SM_CXVSCROLL), CurrentPPI, Screen.PixelsPerInch) + ScaleValue(cGap);
  for mIndex := 0 to FList.Columns.Count - 1 do
  begin
    if mIndex <> cColumnFollow then
    begin
      Inc(mWidth, FList.Columns[mIndex].Width);
    end;
  end;
  ClientWidth := Max(Min(mWidth, mArea.Width * cMaxScreenShare div 100), ScaleValue(cMinWidth));
  // Ohne Fenster ordnet die VCL nicht an: Breite der Einleitung und damit ihre Höhe wären die vorläufigen.
  HandleNeeded;
  Realign;
  // Ohne Zeile: Schrifthöhe plus Rand.
  mRowHeight := Abs(FList.Font.Height) + ScaleValue(cGap);
  if (FList.Items.Count > 0) and ListView_GetItemRect(FList.Handle, 0, mRow, LVIR_BOUNDS) then
  begin
    mRowHeight := mRow.Height;
  end;
  mRows := Max(Min(FList.Items.Count, cInitialRows), 1);
  // Kopfzeile etwa so hoch wie eine Zeile, dazu Rahmen der Liste.
  mHeight := FIntro.Top + FIntro.Height + FIntro.Margins.Bottom + (mRows + 2) * mRowHeight + FButtons.Height;
  ClientHeight := Max(Min(mHeight, mArea.Height * cMaxScreenShare div 100), ScaleValue(cMinHeight));
  Constraints.MinWidth := Width - ClientWidth + ScaleValue(cMinWidth);
  Constraints.MinHeight := Height - ClientHeight + ScaleValue(cMinHeight);
end;

function TListWindow.AddButton(const ACaption: string; AAlign: TAlign): TButton;
var
  mBitmap: TBitmap;
begin
  Result := TButton.Create(Self);
  Result.Caption := ACaption;
  mBitmap := TBitmap.Create;
  try
    mBitmap.Canvas.Font.Assign(Font);
    Result.Width := Max(mBitmap.Canvas.TextWidth(ACaption) + ScaleValue(cButtonPadding), ScaleValue(cButtonMinWidth));
  finally
    mBitmap.Free;
  end;
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(ScaleValue(cGap), ScaleValue(cGap), 0, ScaleValue(cGap));
  if AAlign = alRight then
  begin
    Result.Margins.SetBounds(0, ScaleValue(cGap), ScaleValue(cGap), ScaleValue(cGap));
  end;
  Result.Align := AAlign;
  Result.Parent := FButtons;
end;

procedure TListWindow.ItemChecked(Sender: TObject; Item: TListItem);
var
  mIndex: Integer;
begin
  if FFilling or (Item = nil) then
  begin
    Exit;
  end;
  mIndex := NativeInt(Item.Data);
  FItems[mIndex].On_ := Item.Checked;
  if Assigned(FEvents.Toggle) then
  begin
    FEvents.Toggle(mIndex, Item.Checked);
  end;
end;

procedure TListWindow.ItemSelected(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  UpdateButtons;
end;

procedure TListWindow.ForgetClick(Sender: TObject);
var
  mIndex: Integer;
begin
  if (FList.Selected = nil) or not Assigned(FEvents.Forget) then
  begin
    Exit;
  end;
  mIndex := NativeInt(FList.Selected.Data);
  FItems[mIndex] := FEvents.Forget(mIndex);
  FFilling := True;
  try
    Fill(FList.Selected, FItems[mIndex]);
  finally
    FFilling := False;
  end;
end;

procedure TListWindow.GoToClick(Sender: TObject);
begin
  if (FList.Selected <> nil) and Assigned(FEvents.GoTo_) and
    (Length(FItems[NativeInt(FList.Selected.Data)].Pattern.Evidence) > 0) then
  begin
    FEvents.GoTo_(NativeInt(FList.Selected.Data));
  end;
end;

procedure TListWindow.UpdateButtons;
var
  mSelected: Boolean;
begin
  mSelected := FList.Selected <> nil;
  FForget.Enabled := mSelected;
  FGoTo.Enabled := mSelected and (Length(FItems[NativeInt(FList.Selected.Data)].Pattern.Evidence) > 0);
end;

{ TAtlasLearnedList }

class procedure TAtlasLearnedList.Execute(const AItems: TArray<TAtlasLearnedListItem>;
  const AEvents: TAtlasLearnedListEvents);
var
  mWindow: TListWindow;
begin
  mWindow := TListWindow.CreateDialog(nil, T(TAtlasLearnedText.Title), cWindowWidth);
  try
    mWindow.FItems := Copy(AItems);
    mWindow.FEvents := AEvents;
    mWindow.Build;
    mWindow.ShowModal;
  finally
    mWindow.Free;
  end;
end;

initialization
  TAtlasTextLanguage.AddTable('Atlas.UI.Editor.LearnedSuggestions', cTexts[TAtlasLanguage.German],
    cTexts[TAtlasLanguage.English]);

end.
