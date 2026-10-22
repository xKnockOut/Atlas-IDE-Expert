unit Atlas.UI.EditorToolbar.Customize;

// Atlas-Editorleiste (#1101): Dialog „Leiste anpassen“. Links die verfügbaren
// Befehle der Befehlspalette (#600) samt „— Trennstrich —“, rechts die Knöpfe
// der Leiste mit Symbol in ihrer Reihenfolge. Dazwischen →/← (hinzufügen,
// entfernen), daneben ↑/↓ (verschieben); Doppelklick fügt hinzu bzw. entfernt.
// Darunter „Text neben den Symbolen“, die Position und „Standard
// wiederherstellen“. Der Dialog arbeitet auf einer Kopie (TAtlasToolbarConfig);
// erst OK übernimmt sie. Die Listenschritte selbst stecken in
// TAtlasToolbarItems (ohne VCL getestet). Die Listen werden erst mit Fenster
// gefüllt (TListBox.Items braucht eins), Änderungen ohne Fenster nur gemerkt.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Atlas.Core.Settings.ToolbarItems,
  Atlas.Core.EditorToolbar.Icons;

type
  /// <summary>Ein Befehl, der in die Leiste kann (aus der Befehlspalette).</summary>
  TAtlasToolbarCommandInfo = record
    Id: string;
    Caption: string;
    class function Create(const AId, ACaption: string): TAtlasToolbarCommandInfo; static;
  end;

  /// <summary>Was der Dialog ändert.</summary>
  TAtlasToolbarConfig = record
    Items: TArray<string>;
    Labels: Boolean;
    /// <summary>belowBreadcrumbs, aboveBreadcrumbs oder inBreadcrumbs.</summary>
    Position: string;
  end;

  TAtlasToolbarCustomizeDialog = class(TForm)
  private
    FCommands: TArray<TAtlasToolbarCommandInfo>;
    FConfig: TAtlasToolbarConfig;
    /// <summary>Kennungen der linken Liste in Anzeigereihenfolge (zuerst der Trennstrich).</summary>
    FAvailable: TArray<string>;
    FAvailableList: TListBox;
    FCurrentList: TListBox;
    FAddButton: TButton;
    FRemoveButton: TButton;
    FUpButton: TButton;
    FDownButton: TButton;
    FLabelsCheck: TCheckBox;
    FPositionCombo: TComboBox;
    FDefaultButton: TButton;
    FOk: TButton;
    FCancel: TButton;
    FFilled: Boolean;
    function NewButton(AParent: TWinControl; const ACaption, AHint: string; AClick: TNotifyEvent): TButton;
    function NewList(AParent: TWinControl): TListBox;
    procedure BuildAvailable;
    procedure Fill(ACurrentIndex, AAvailableIndex: Integer);
    procedure UpdateButtons;
    procedure AddClick(Sender: TObject);
    procedure RemoveClick(Sender: TObject);
    procedure UpClick(Sender: TObject);
    procedure DownClick(Sender: TObject);
    procedure DefaultClick(Sender: TObject);
    procedure OkClick(Sender: TObject);
    procedure ListClick(Sender: TObject);
    procedure LabelsClick(Sender: TObject);
    procedure PositionChange(Sender: TObject);
    procedure CurrentDrawItem(Control: TWinControl; Index: Integer; Rect: TRect; State: TOwnerDrawState);
  protected
    procedure DoShow; override;
  public
    constructor CreateDialog(AOwner: TComponent; const ACommands: TArray<TAtlasToolbarCommandInfo>;
      const AConfig: TAtlasToolbarConfig);
    /// <summary>Beschriftung zur Kennung; '|' ist der Trennstrich, unbekannte Kennungen bleiben, wie sie sind.</summary>
    function CaptionOf(const AId: string): string;
    /// <summary>Linke Liste: Kennungen in Anzeigereihenfolge (Trennstrich zuerst, dann nach Beschriftung).</summary>
    function Available: TArray<string>;
    /// <summary>Eintrag AAvailableIndex der linken Liste vor AIndex einfügen; liefert den neuen Index oder -1.</summary>
    function AddItem(AAvailableIndex, AIndex: Integer): Integer;
    function RemoveItem(AIndex: Integer): Boolean;
    function MoveItem(AIndex, ADelta: Integer): Integer;
    procedure RestoreDefault;
    procedure SetLabels(AValue: Boolean);
    procedure SetPosition(const AValue: string);
    property Config: TAtlasToolbarConfig read FConfig;
    property AvailableList: TListBox read FAvailableList;
    property CurrentList: TListBox read FCurrentList;
    property OkButton: TButton read FOk;
    property CancelButton: TButton read FCancel;
    /// <summary>Zeigt den Dialog modal; True und die neue Belegung in AConfig bei OK.</summary>
    class function Execute(const ACommands: TArray<TAtlasToolbarCommandInfo>;
      var AConfig: TAtlasToolbarConfig): Boolean; static;
  end;

const
  /// <summary>Werte von editor.toolbar.position in der Reihenfolge der Auswahl.</summary>
  AtlasToolbarPositions: array[0..2] of string = ('belowBreadcrumbs', 'aboveBreadcrumbs', 'inBreadcrumbs');

implementation

uses
  System.Math,
  System.UITypes,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.UI.Strings,
  Atlas.UI.EditorToolbar.Glyphs;

const
  Gap = 8;

{ TAtlasToolbarCommandInfo }

class function TAtlasToolbarCommandInfo.Create(const AId, ACaption: string): TAtlasToolbarCommandInfo;
begin
  Result.Id := AId;
  Result.Caption := ACaption;
end;

{ TAtlasToolbarCustomizeDialog }

constructor TAtlasToolbarCustomizeDialog.CreateDialog(AOwner: TComponent;
  const ACommands: TArray<TAtlasToolbarCommandInfo>; const AConfig: TAtlasToolbarConfig);
var
  Lists, Middle, Side, Bottom, Options: TPanel;
  Caption_: TLabel;
  Index: Integer;
begin
  inherited CreateNew(AOwner);
  FCommands := ACommands;
  FConfig := AConfig;
  FConfig.Items := TAtlasToolbarItems.Clean(AConfig.Items);
  Caption := TAtlasStrings.Text(TAtlasTextId.EditorToolbarCustomizeTitle);
  BorderStyle := bsSizeable;
  BorderIcons := [biSystemMenu];
  Position := poMainFormCenter;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  ClientWidth := ScaleValue(640);
  ClientHeight := ScaleValue(440);
  Constraints.MinWidth := ScaleValue(480);
  Constraints.MinHeight := ScaleValue(320);

  Bottom := TPanel.Create(Self);
  Bottom.Parent := Self;
  Bottom.Align := alBottom;
  Bottom.Height := ScaleValue(44);
  Bottom.BevelOuter := bvNone;
  FCancel := NewButton(Bottom, TAtlasStrings.Text(TAtlasTextId.EditorToolbarCancel), '', nil);
  FCancel.Cancel := True;
  FCancel.ModalResult := mrCancel;
  FCancel.Left := Bottom.ClientWidth - FCancel.Width - ScaleValue(Gap);
  FCancel.Anchors := [akTop, akRight];
  FOk := NewButton(Bottom, TAtlasStrings.Text(TAtlasTextId.EditorToolbarOk), '', OkClick);
  FOk.Default := True;
  FOk.Left := FCancel.Left - FOk.Width - ScaleValue(Gap);
  FOk.Anchors := [akTop, akRight];
  FDefaultButton := NewButton(Bottom, TAtlasStrings.Text(TAtlasTextId.EditorToolbarRestoreDefault), '',
    DefaultClick);
  FDefaultButton.Left := ScaleValue(Gap);

  Options := TPanel.Create(Self);
  Options.Parent := Self;
  Options.Align := alBottom;
  Options.Height := ScaleValue(36);
  Options.BevelOuter := bvNone;
  FLabelsCheck := TCheckBox.Create(Self);
  FLabelsCheck.Parent := Options;
  FLabelsCheck.Caption := TAtlasStrings.Text(TAtlasTextId.EditorToolbarLabels);
  FLabelsCheck.SetBounds(ScaleValue(Gap), ScaleValue(Gap), ScaleValue(220), ScaleValue(20));
  FLabelsCheck.Checked := FConfig.Labels;
  FLabelsCheck.OnClick := LabelsClick;
  Caption_ := TLabel.Create(Self);
  Caption_.Parent := Options;
  Caption_.Caption := TAtlasStrings.Text(TAtlasTextId.EditorToolbarPosition);
  Caption_.SetBounds(ScaleValue(250), ScaleValue(Gap + 2), ScaleValue(70), ScaleValue(20));
  FPositionCombo := TComboBox.Create(Self);
  FPositionCombo.Parent := Options;
  FPositionCombo.Style := csDropDownList;
  FPositionCombo.SetBounds(ScaleValue(330), ScaleValue(Gap - 2), ScaleValue(240), ScaleValue(24));
  FPositionCombo.OnChange := PositionChange;
  Caption_.FocusControl := FPositionCombo;

  Lists := TPanel.Create(Self);
  Lists.Parent := Self;
  Lists.Align := alClient;
  Lists.BevelOuter := bvNone;

  // Links verfügbar, Mitte → ←, rechts die Leiste, ganz rechts ↑ ↓.
  Side := TPanel.Create(Self);
  Side.Parent := Lists;
  Side.Align := alRight;
  Side.Width := ScaleValue(48);
  Side.BevelOuter := bvNone;
  FUpButton := NewButton(Side, '↑', TAtlasStrings.Text(TAtlasTextId.EditorToolbarUpHint), UpClick);
  FUpButton.SetBounds(ScaleValue(Gap), ScaleValue(80), ScaleValue(32), ScaleValue(28));
  FDownButton := NewButton(Side, '↓', TAtlasStrings.Text(TAtlasTextId.EditorToolbarDownHint), DownClick);
  FDownButton.SetBounds(ScaleValue(Gap), ScaleValue(116), ScaleValue(32), ScaleValue(28));

  FCurrentList := NewList(Lists);
  FCurrentList.Align := alRight;
  FCurrentList.Width := ScaleValue(260);
  FCurrentList.Style := lbOwnerDrawFixed;
  FCurrentList.ItemHeight := ScaleValue(24);
  FCurrentList.OnDrawItem := CurrentDrawItem;
  FCurrentList.OnDblClick := RemoveClick;

  Middle := TPanel.Create(Self);
  Middle.Parent := Lists;
  Middle.Align := alRight;
  Middle.Width := ScaleValue(56);
  Middle.BevelOuter := bvNone;
  FAddButton := NewButton(Middle, '→', TAtlasStrings.Text(TAtlasTextId.EditorToolbarAddHint), AddClick);
  FAddButton.SetBounds(ScaleValue(12), ScaleValue(80), ScaleValue(32), ScaleValue(28));
  FRemoveButton := NewButton(Middle, '←', TAtlasStrings.Text(TAtlasTextId.EditorToolbarRemoveHint), RemoveClick);
  FRemoveButton.SetBounds(ScaleValue(12), ScaleValue(116), ScaleValue(32), ScaleValue(28));

  FAvailableList := NewList(Lists);
  FAvailableList.Align := alClient;
  FAvailableList.OnDblClick := AddClick;

  // Überschriften über den Listen.
  Caption_ := TLabel.Create(Self);
  Caption_.Parent := Self;
  Caption_.Align := alTop;
  Caption_.AlignWithMargins := True;
  Caption_.Margins.SetBounds(ScaleValue(Gap), ScaleValue(Gap), ScaleValue(Gap), 0);
  Caption_.ShowAccelChar := False;
  Caption_.Caption := TAtlasStrings.Text(TAtlasTextId.EditorToolbarAvailable) + '  ›  ' +
    TAtlasStrings.Text(TAtlasTextId.EditorToolbarCurrent);

  ShowHint := True;
  BuildAvailable;
  for Index := 0 to High(AtlasToolbarPositions) do
    if SameText(AtlasToolbarPositions[Index], FConfig.Position) then
      FConfig.Position := AtlasToolbarPositions[Index];
  if FConfig.Position = '' then
    FConfig.Position := AtlasToolbarPositions[0];
end;

function TAtlasToolbarCustomizeDialog.NewButton(AParent: TWinControl; const ACaption, AHint: string;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.Hint := AHint;
  Result.OnClick := AClick;
  Canvas.Font := Font;
  Result.Width := Max(ScaleValue(90), Canvas.TextWidth(ACaption) + ScaleValue(32));
  Result.Top := ScaleValue(Gap);
  Result.Height := ScaleValue(28);
end;

function TAtlasToolbarCustomizeDialog.NewList(AParent: TWinControl): TListBox;
begin
  Result := TListBox.Create(Self);
  Result.Parent := AParent;
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(ScaleValue(Gap), ScaleValue(4), 0, ScaleValue(Gap));
  Result.OnClick := ListClick;
end;

function TAtlasToolbarCustomizeDialog.CaptionOf(const AId: string): string;
var
  Command: TAtlasToolbarCommandInfo;
begin
  if TAtlasToolbarItems.IsSeparator(AId) then
    Exit(TAtlasStrings.Text(TAtlasTextId.EditorToolbarSeparator));
  for Command in FCommands do
    if SameText(Command.Id, AId) then
      Exit(Command.Caption);
  Result := AId;
end;

procedure TAtlasToolbarCustomizeDialog.BuildAvailable;
var
  Command: TAtlasToolbarCommandInfo;
  Item: string;
  Used: Boolean;
  Rest: TList<TAtlasToolbarCommandInfo>;
begin
  Rest := TList<TAtlasToolbarCommandInfo>.Create;
  try
    for Command in FCommands do
    begin
      Used := False;
      for Item in FConfig.Items do
        if SameText(Item, Command.Id) then
          Used := True;
      if not Used then
        Rest.Add(Command);
    end;
    Rest.Sort(TComparer<TAtlasToolbarCommandInfo>.Construct(
      function(const A, B: TAtlasToolbarCommandInfo): Integer
      begin
        Result := CompareText(A.Caption, B.Caption);
      end));
    FAvailable := [TAtlasToolbarItems.Separator];
    for Command in Rest do
      FAvailable := FAvailable + [Command.Id];
  finally
    Rest.Free;
  end;
end;

function TAtlasToolbarCustomizeDialog.Available: TArray<string>;
begin
  Result := FAvailable;
end;

function TAtlasToolbarCustomizeDialog.AddItem(AAvailableIndex, AIndex: Integer): Integer;
var
  Next: Integer;
begin
  if (AAvailableIndex < 0) or (AAvailableIndex > High(FAvailable)) then
    Exit(-1);
  Result := TAtlasToolbarItems.Add(FConfig.Items, FAvailable[AAvailableIndex], AIndex);
  if Result < 0 then
    Exit;
  BuildAvailable;
  // Links bleibt die Auswahl an derselben Stelle (der Trennstrich bleibt stehen).
  Next := Min(AAvailableIndex, High(FAvailable));
  Fill(Result, Next);
end;

function TAtlasToolbarCustomizeDialog.RemoveItem(AIndex: Integer): Boolean;
begin
  Result := TAtlasToolbarItems.Remove(FConfig.Items, AIndex);
  if not Result then
    Exit;
  BuildAvailable;
  Fill(Min(AIndex, High(FConfig.Items)), -1);
end;

function TAtlasToolbarCustomizeDialog.MoveItem(AIndex, ADelta: Integer): Integer;
begin
  Result := TAtlasToolbarItems.Move(FConfig.Items, AIndex, ADelta);
  Fill(Result, -1);
end;

procedure TAtlasToolbarCustomizeDialog.RestoreDefault;
begin
  FConfig.Items := TAtlasToolbarItems.Default;
  FConfig.Labels := False;
  FConfig.Position := AtlasToolbarPositions[0];
  BuildAvailable;
  Fill(-1, -1);
end;

procedure TAtlasToolbarCustomizeDialog.SetLabels(AValue: Boolean);
begin
  FConfig.Labels := AValue;
  if FFilled and (FLabelsCheck.Checked <> AValue) then
    FLabelsCheck.Checked := AValue;
end;

procedure TAtlasToolbarCustomizeDialog.SetPosition(const AValue: string);
var
  Index: Integer;
begin
  for Index := 0 to High(AtlasToolbarPositions) do
    if SameText(AtlasToolbarPositions[Index], AValue) then
    begin
      FConfig.Position := AtlasToolbarPositions[Index];
      if FFilled then
        FPositionCombo.ItemIndex := Index;
    end;
end;

procedure TAtlasToolbarCustomizeDialog.DoShow;
begin
  inherited DoShow;
  Fill(-1, -1);
end;

procedure TAtlasToolbarCustomizeDialog.Fill(ACurrentIndex, AAvailableIndex: Integer);
var
  Item: string;
  Index: Integer;
begin
  // Ohne Fenster bleibt es bei FConfig; DoShow füllt dann.
  if not HandleAllocated then
    Exit;
  FFilled := True;
  FAvailableList.Items.BeginUpdate;
  try
    FAvailableList.Items.Clear;
    for Item in FAvailable do
      FAvailableList.Items.Add(CaptionOf(Item));
  finally
    FAvailableList.Items.EndUpdate;
  end;
  FCurrentList.Items.BeginUpdate;
  try
    FCurrentList.Items.Clear;
    for Item in FConfig.Items do
      FCurrentList.Items.Add(CaptionOf(Item));
  finally
    FCurrentList.Items.EndUpdate;
  end;
  FCurrentList.ItemIndex := ACurrentIndex;
  FAvailableList.ItemIndex := AAvailableIndex;
  FLabelsCheck.Checked := FConfig.Labels;
  if FPositionCombo.Items.Count = 0 then
  begin
    FPositionCombo.Items.Add(TAtlasStrings.Text(TAtlasTextId.EditorToolbarPositionBelow));
    FPositionCombo.Items.Add(TAtlasStrings.Text(TAtlasTextId.EditorToolbarPositionAbove));
    FPositionCombo.Items.Add(TAtlasStrings.Text(TAtlasTextId.EditorToolbarPositionInline));
  end;
  FPositionCombo.ItemIndex := 0;
  for Index := 0 to High(AtlasToolbarPositions) do
    if AtlasToolbarPositions[Index] = FConfig.Position then
      FPositionCombo.ItemIndex := Index;
  UpdateButtons;
end;

procedure TAtlasToolbarCustomizeDialog.UpdateButtons;
var
  Current: Integer;
begin
  Current := FCurrentList.ItemIndex;
  FAddButton.Enabled := FAvailableList.ItemIndex >= 0;
  FRemoveButton.Enabled := Current >= 0;
  FUpButton.Enabled := Current > 0;
  FDownButton.Enabled := (Current >= 0) and (Current < High(FConfig.Items));
end;

procedure TAtlasToolbarCustomizeDialog.ListClick(Sender: TObject);
begin
  UpdateButtons;
end;

procedure TAtlasToolbarCustomizeDialog.AddClick(Sender: TObject);
var
  Target: Integer;
begin
  // Hinter dem ausgewählten Knopf der Leiste einfügen, sonst hinten.
  Target := Length(FConfig.Items);
  if FCurrentList.ItemIndex >= 0 then
    Target := FCurrentList.ItemIndex + 1;
  AddItem(FAvailableList.ItemIndex, Target);
end;

procedure TAtlasToolbarCustomizeDialog.RemoveClick(Sender: TObject);
begin
  RemoveItem(FCurrentList.ItemIndex);
end;

procedure TAtlasToolbarCustomizeDialog.UpClick(Sender: TObject);
begin
  MoveItem(FCurrentList.ItemIndex, -1);
end;

procedure TAtlasToolbarCustomizeDialog.DownClick(Sender: TObject);
begin
  MoveItem(FCurrentList.ItemIndex, 1);
end;

procedure TAtlasToolbarCustomizeDialog.DefaultClick(Sender: TObject);
begin
  RestoreDefault;
end;

procedure TAtlasToolbarCustomizeDialog.LabelsClick(Sender: TObject);
begin
  FConfig.Labels := FLabelsCheck.Checked;
end;

procedure TAtlasToolbarCustomizeDialog.PositionChange(Sender: TObject);
begin
  if (FPositionCombo.ItemIndex >= 0) and (FPositionCombo.ItemIndex <= High(AtlasToolbarPositions)) then
    FConfig.Position := AtlasToolbarPositions[FPositionCombo.ItemIndex];
end;

procedure TAtlasToolbarCustomizeDialog.OkClick(Sender: TObject);
begin
  // Trennstriche am Rand oder doppelt fallen beim Übernehmen weg.
  FConfig.Items := TAtlasToolbarItems.Clean(FConfig.Items);
  ModalResult := mrOk;
end;

procedure TAtlasToolbarCustomizeDialog.CurrentDrawItem(Control: TWinControl; Index: Integer; Rect: TRect;
  State: TOwnerDrawState);
var
  List: TListBox;
  Id: string;
  Icon, Text: TRect;
  Caption_: string;
  Size, Middle: Integer;
begin
  List := TListBox(Control);
  List.Canvas.FillRect(Rect);
  if (Index < 0) or (Index > High(FConfig.Items)) then
    Exit;
  Id := FConfig.Items[Index];
  Caption_ := CaptionOf(Id);
  Size := ScaleValue(16);
  Icon := System.Types.Rect(Rect.Left + ScaleValue(4), Rect.Top + (Rect.Height - Size) div 2,
    Rect.Left + ScaleValue(4) + Size, Rect.Top + (Rect.Height - Size) div 2 + Size);
  if TAtlasToolbarItems.IsSeparator(Id) then
  begin
    Middle := (Rect.Top + Rect.Bottom) div 2;
    List.Canvas.Pen.Color := List.Canvas.Font.Color;
    List.Canvas.MoveTo(Icon.Left, Middle);
    List.Canvas.LineTo(Icon.Right, Middle);
  end
  else
    TAtlasGlyphPainter.Draw(List.Canvas, TAtlasToolbarIcons.IconOf(Id), Icon, List.Canvas.Font.Color,
      List.Canvas.Brush.Color, Caption_);
  Text := System.Types.Rect(Icon.Right + ScaleValue(6), Rect.Top, Rect.Right - ScaleValue(2), Rect.Bottom);
  List.Canvas.Brush.Style := bsClear;
  DrawText(List.Canvas.Handle, PChar(Caption_), -1, Text, DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX or
    DT_END_ELLIPSIS);
  List.Canvas.Brush.Style := bsSolid;
end;

class function TAtlasToolbarCustomizeDialog.Execute(const ACommands: TArray<TAtlasToolbarCommandInfo>;
  var AConfig: TAtlasToolbarConfig): Boolean;
var
  Dialog: TAtlasToolbarCustomizeDialog;
begin
  Dialog := TAtlasToolbarCustomizeDialog.CreateDialog(nil, ACommands, AConfig);
  try
    Result := Dialog.ShowModal = mrOk;
    if Result then
      AConfig := Dialog.Config;
  finally
    Dialog.Free;
  end;
end;

end.
