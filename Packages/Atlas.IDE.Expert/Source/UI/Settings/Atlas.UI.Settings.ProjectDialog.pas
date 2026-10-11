unit Atlas.UI.Settings.ProjectDialog;

// Dialog „Projekt > Atlas-Einstellungen…“ (#227): Seiten und Bedienelemente
// entstehen aus dem JSON-Schema (TAtlasSettingsSchema), Werte aus atlas.json
// neben der .dproj. Je Einstellung steht, ob der Wert aus dem Projekt kommt oder
// der Standard gilt; „Zurücksetzen“ entfernt den Schlüssel wieder. Geschrieben
// wird nicht hier: Changes liefert die geänderten Pfade für TAtlasJsonText.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Graphics,
  Atlas.Core.Settings.Schema;

type
  TAtlasProjectSettingsDialog = class(TForm)
  private
    FFields: TArray<TAtlasSettingField>;
    FOriginal: TArray<string>;
    FCurrent: TArray<string>;
    // Getippter Text der Zahlenfelder; ungültige Eingaben verhindern OK.
    FRaw: TArray<string>;
    FStates: TArray<TLabel>;
    FResets: TArray<TButton>;
    FPages: TArray<string>;
    FPageList: TListBox;
    FBox: TScrollBox;
    FOnOpenFile: TProc;
    function Effective(AIndex: Integer): string;
    function Editable(AIndex: Integer): Boolean;
    procedure ShowPage(APage: Integer);
    procedure UpdateState(AIndex: Integer);
    procedure PageClick(Sender: TObject);
    procedure CheckClick(Sender: TObject);
    procedure EditChange(Sender: TObject);
    procedure ComboChange(Sender: TObject);
    procedure MemoChange(Sender: TObject);
    procedure ResetClick(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure OkClick(Sender: TObject);
  public
    /// <summary>ARoot: Inhalt von atlas.json (darf nil sein); bleibt beim Aufrufer.</summary>
    constructor CreateDialog(AOwner: TComponent; const AFields: TArray<TAtlasSettingField>; ARoot: TJSONObject;
      const AFileName: string);
    /// <summary>Geänderte Einstellungen: Pfad und JSON-Text, '' = Schlüssel entfernen.</summary>
    function Changes: TArray<TPair<string, string>>;
    property OnOpenFile: TProc read FOnOpenFile write FOnOpenFile;
  end;

implementation

uses
  Atlas.Core.Settings.JsonText,
  Atlas.UI.Strings;

const
  Gap = 8;

constructor TAtlasProjectSettingsDialog.CreateDialog(AOwner: TComponent; const AFields: TArray<TAtlasSettingField>;
  ARoot: TJSONObject; const AFileName: string);
var
  Index: Integer;
  Bottom: TPanel;
  Button: TButton;
  FileLabel: TLabel;
  Page: string;
begin
  inherited CreateNew(AOwner);
  Caption := TAtlasStrings.Text(TAtlasTextId.ProjectSettingsTitle);
  BorderStyle := bsSizeable;
  Position := poMainFormCenter;
  Width := 860;
  Height := 620;
  FFields := AFields;
  SetLength(FOriginal, Length(FFields));
  SetLength(FCurrent, Length(FFields));
  SetLength(FRaw, Length(FFields));
  SetLength(FStates, Length(FFields));
  SetLength(FResets, Length(FFields));
  for Index := 0 to High(FFields) do
  begin
    if ARoot <> nil then
      FOriginal[Index] := TAtlasJsonText.ValueAt(ARoot, FFields[Index].Path);
    FCurrent[Index] := FOriginal[Index];
    FRaw[Index] := TAtlasSettingsSchema.Display(FOriginal[Index]);
  end;

  Bottom := TPanel.Create(Self);
  Bottom.Parent := Self;
  Bottom.Align := alBottom;
  Bottom.Height := 44;
  Bottom.BevelOuter := bvNone;
  FileLabel := TLabel.Create(Self);
  FileLabel.Parent := Bottom;
  FileLabel.Left := 150;
  FileLabel.Top := 14;
  FileLabel.Caption := TAtlasStrings.Fmt(TAtlasTextId.ProjectSettingsFile, [AFileName]);
  Button := TButton.Create(Self);
  Button.Parent := Bottom;
  Button.SetBounds(Gap, 8, 130, 28);
  Button.Caption := TAtlasStrings.Text(TAtlasTextId.ProjectSettingsOpenFile);
  Button.OnClick := OpenClick;
  Button := TButton.Create(Self);
  Button.Parent := Bottom;
  Button.SetBounds(Bottom.Width - 2 * (90 + Gap), 8, 90, 28);
  Button.Anchors := [akTop, akRight];
  Button.Caption := TAtlasStrings.Text(TAtlasTextId.ProjectSettingsOk);
  Button.Default := True;
  Button.OnClick := OkClick;
  Button := TButton.Create(Self);
  Button.Parent := Bottom;
  Button.SetBounds(Bottom.Width - (90 + Gap), 8, 90, 28);
  Button.Anchors := [akTop, akRight];
  Button.Caption := TAtlasStrings.Text(TAtlasTextId.ProjectSettingsCancel);
  Button.Cancel := True;
  Button.ModalResult := mrCancel;

  FPageList := TListBox.Create(Self);
  FPageList.Parent := Self;
  FPageList.Align := alLeft;
  FPageList.Width := 170;
  FPageList.OnClick := PageClick;
  FPages := TAtlasSettingsSchema.Pages(FFields);
  for Page in FPages do
    FPageList.Items.Add(Page);

  FBox := TScrollBox.Create(Self);
  FBox.Parent := Self;
  FBox.Align := alClient;
  FBox.BorderStyle := bsNone;
  FBox.VertScrollBar.Tracking := True;

  if FPageList.Items.Count > 0 then
  begin
    FPageList.ItemIndex := 0;
    ShowPage(0);
  end;
end;

function TAtlasProjectSettingsDialog.Effective(AIndex: Integer): string;
begin
  Result := FCurrent[AIndex];
  if Result = '' then
    Result := FFields[AIndex].DefaultJson;
end;

function TAtlasProjectSettingsDialog.Editable(AIndex: Integer): Boolean;
begin
  // Ein Wert, der nicht zur Art passt (z. B. Profil als Objekt), bleibt unangetastet.
  Result := (FFields[AIndex].Kind <> TAtlasSettingKind.Complex) and FFields[AIndex].Accepts(FOriginal[AIndex]);
end;

procedure TAtlasProjectSettingsDialog.UpdateState(AIndex: Integer);
begin
  if FStates[AIndex] = nil then
    Exit;
  if FCurrent[AIndex] <> '' then
    FStates[AIndex].Caption := TAtlasStrings.Text(TAtlasTextId.ProjectSettingsFromProject)
  else if FFields[AIndex].DefaultJson <> '' then
    FStates[AIndex].Caption := TAtlasStrings.Fmt(TAtlasTextId.ProjectSettingsDefault,
      [TAtlasSettingsSchema.Display(FFields[AIndex].DefaultJson)])
  else
    FStates[AIndex].Caption := TAtlasStrings.Text(TAtlasTextId.ProjectSettingsDefaultNone);
  if FResets[AIndex] <> nil then
    FResets[AIndex].Enabled := FCurrent[AIndex] <> '';
end;

procedure TAtlasProjectSettingsDialog.ShowPage(APage: Integer);
var
  Index, Y, ControlWidth, Choice: Integer;
  Name, Description, Note: TLabel;
  Check: TCheckBox;
  Edit: TEdit;
  Combo: TComboBox;
  Memo: TMemo;
  Reset: TButton;
  Value: TJSONValue;
  Item: TJSONValue;
  Control: TControl;
begin
  FBox.VertScrollBar.Position := 0;
  while FBox.ControlCount > 0 do
    FBox.Controls[0].Free;
  for Index := 0 to High(FStates) do
  begin
    FStates[Index] := nil;
    FResets[Index] := nil;
  end;
  ControlWidth := 300;
  Y := Gap;
  for Index := 0 to High(FFields) do
  begin
    if not SameText(FFields[Index].Page, FPages[APage]) then
      Continue;
    Name := TLabel.Create(FBox);
    Name.Parent := FBox;
    Name.SetBounds(Gap * 2, Y, 400, 16);
    Name.Font.Style := [fsBold];
    Name.Caption := FFields[Index].Path;
    Inc(Y, 20);
    if FFields[Index].Description <> '' then
    begin
      Description := TLabel.Create(FBox);
      Description.Parent := FBox;
      Description.WordWrap := True;
      Description.AutoSize := True;
      Description.SetBounds(Gap * 2, Y, FBox.ClientWidth - Gap * 5, 16);
      Description.Caption := FFields[Index].Description;
      Inc(Y, Description.Height + 4);
    end;
    Control := nil;
    if not Editable(Index) then
    begin
      Note := TLabel.Create(FBox);
      Note.Parent := FBox;
      Note.SetBounds(Gap * 2, Y, FBox.ClientWidth - Gap * 5, 16);
      Note.Font.Color := clGrayText;
      Note.Caption := TAtlasStrings.Text(TAtlasTextId.ProjectSettingsComplex);
      if FOriginal[Index] <> '' then
        Note.Caption := Note.Caption + ': ' + Copy(FOriginal[Index], 1, 120);
      Inc(Y, 24);
      Inc(Y, Gap);
      Continue;
    end;
    case FFields[Index].Kind of
      TAtlasSettingKind.Boolean_:
        begin
          Check := TCheckBox.Create(FBox);
          Check.Parent := FBox;
          Check.Caption := FFields[Index].Path;
          Check.Checked := Effective(Index) = 'true';
          Check.OnClick := CheckClick;
          Control := Check;
        end;
      TAtlasSettingKind.Integer_, TAtlasSettingKind.Text:
        begin
          Edit := TEdit.Create(FBox);
          Edit.Parent := FBox;
          if FCurrent[Index] <> '' then
            Edit.Text := FRaw[Index]
          else
            Edit.TextHint := TAtlasSettingsSchema.Display(FFields[Index].DefaultJson);
          Edit.OnChange := EditChange;
          Control := Edit;
        end;
      TAtlasSettingKind.Choice:
        begin
          Combo := TComboBox.Create(FBox);
          Combo.Parent := FBox;
          Combo.Style := csDropDownList;
          for Choice := 0 to High(FFields[Index].Choices) do
          begin
            Combo.Items.Add(TAtlasSettingsSchema.Display(FFields[Index].Choices[Choice]));
            if FFields[Index].Choices[Choice] = Effective(Index) then
              Combo.ItemIndex := Choice;
          end;
          Combo.OnChange := ComboChange;
          Control := Combo;
        end;
      TAtlasSettingKind.List:
        begin
          Memo := TMemo.Create(FBox);
          Memo.Parent := FBox;
          Memo.Height := 72;
          Memo.ScrollBars := ssVertical;
          Value := TJSONObject.ParseJSONValue(Effective(Index));
          try
            if Value is TJSONArray then
              for Item in TJSONArray(Value) do
                if Item is TJSONString then
                  Memo.Lines.Add(TJSONString(Item).Value);
          finally
            Value.Free;
          end;
          Memo.OnChange := MemoChange;
          Control := Memo;
        end;
    end;
    if Control = nil then
      Continue;
    Control.Tag := Index;
    Control.SetBounds(Gap * 2, Y, ControlWidth, Control.Height);
    FStates[Index] := TLabel.Create(FBox);
    FStates[Index].Parent := FBox;
    FStates[Index].SetBounds(Gap * 3 + ControlWidth, Y + 4, 200, 16);
    FStates[Index].Font.Color := clGrayText;
    Reset := TButton.Create(FBox);
    Reset.Parent := FBox;
    Reset.SetBounds(Gap * 4 + ControlWidth + 200, Y, 100, 24);
    Reset.Caption := TAtlasStrings.Text(TAtlasTextId.ProjectSettingsReset);
    Reset.Tag := Index;
    Reset.OnClick := ResetClick;
    FResets[Index] := Reset;
    UpdateState(Index);
    Inc(Y, Control.Height + Gap * 2);
  end;
end;

procedure TAtlasProjectSettingsDialog.PageClick(Sender: TObject);
begin
  if FPageList.ItemIndex >= 0 then
    ShowPage(FPageList.ItemIndex);
end;

procedure TAtlasProjectSettingsDialog.CheckClick(Sender: TObject);
var
  Index: Integer;
begin
  Index := TCheckBox(Sender).Tag;
  if TCheckBox(Sender).Checked then
    FCurrent[Index] := 'true'
  else
    FCurrent[Index] := 'false';
  UpdateState(Index);
end;

procedure TAtlasProjectSettingsDialog.EditChange(Sender: TObject);
var
  Index, Number: Integer;
  Text: string;
begin
  Index := TEdit(Sender).Tag;
  Text := Trim(TEdit(Sender).Text);
  FRaw[Index] := Text;
  if Text = '' then
    FCurrent[Index] := ''
  else if FFields[Index].Kind = TAtlasSettingKind.Text then
    FCurrent[Index] := TAtlasJsonText.Quote(Text)
  else if TryStrToInt(Text, Number) then
    FCurrent[Index] := IntToStr(Number);
  UpdateState(Index);
end;

procedure TAtlasProjectSettingsDialog.ComboChange(Sender: TObject);
var
  Index: Integer;
begin
  Index := TComboBox(Sender).Tag;
  if TComboBox(Sender).ItemIndex >= 0 then
    FCurrent[Index] := FFields[Index].Choices[TComboBox(Sender).ItemIndex];
  UpdateState(Index);
end;

procedure TAtlasProjectSettingsDialog.MemoChange(Sender: TObject);
var
  Index: Integer;
  Line: string;
  List: TJSONArray;
begin
  Index := TMemo(Sender).Tag;
  List := TJSONArray.Create;
  try
    for Line in TMemo(Sender).Lines do
      if Trim(Line) <> '' then
        List.Add(Trim(Line));
    if List.Count = 0 then
      FCurrent[Index] := ''
    else
      FCurrent[Index] := List.ToJSON;
  finally
    List.Free;
  end;
  UpdateState(Index);
end;

procedure TAtlasProjectSettingsDialog.ResetClick(Sender: TObject);
var
  Index: Integer;
begin
  Index := TButton(Sender).Tag;
  FCurrent[Index] := '';
  FRaw[Index] := '';
  // Nicht im Klick des Knopfs neu aufbauen: ShowPage gibt ihn frei.
  TThread.ForceQueue(nil,
    procedure
    begin
      if FPageList.ItemIndex >= 0 then
        ShowPage(FPageList.ItemIndex);
    end);
end;

procedure TAtlasProjectSettingsDialog.OpenClick(Sender: TObject);
begin
  if Assigned(FOnOpenFile) then
  begin
    ModalResult := mrCancel;
    FOnOpenFile();
  end;
end;

procedure TAtlasProjectSettingsDialog.OkClick(Sender: TObject);
var
  Index, Number: Integer;
begin
  for Index := 0 to High(FFields) do
    if (FFields[Index].Kind = TAtlasSettingKind.Integer_) and (FRaw[Index] <> '') and
      not TryStrToInt(FRaw[Index], Number) then
    begin
      MessageBox(Handle, PChar(TAtlasStrings.Fmt(TAtlasTextId.ProjectSettingsBadNumber,
        [FFields[Index].Path, FRaw[Index]])), PChar(Caption), MB_ICONWARNING or MB_OK);
      Exit;
    end;
  ModalResult := mrOk;
end;

function TAtlasProjectSettingsDialog.Changes: TArray<TPair<string, string>>;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to High(FFields) do
    if Editable(Index) and (FCurrent[Index] <> FOriginal[Index]) then
      Result := Result + [TPair<string, string>.Create(FFields[Index].Path, FCurrent[Index])];
end;

end.
