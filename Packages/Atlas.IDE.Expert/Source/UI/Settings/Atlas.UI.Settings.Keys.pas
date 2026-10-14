unit Atlas.UI.Settings.Keys;

// Seite „Tastenkonflikte“ unter Tools › Optionen › Drittanbieter › Atlas
// (#494). Je Taste von Atlas (Befehlspalette, Syntaxprüfung,
// Vervollständigung, Parameter-Hint) eine Zeile: Funktion, Taste als Text wie
// im Menü, die Wahl „Atlas verwenden“, „anderer Belegung überlassen“ oder
// „andere Taste für Atlas“ und darunter, wer die Taste sonst belegt. Wer eine
// Taste belegt, fragt die IDE-Schicht über OwnerOf ab; die Seite selbst kennt
// die Open Tools API nicht. Darunter die erkannten Erweiterungen mit eigener
// Vervollständigung. Reine VCL, im Code aufgebaut wie Atlas.UI.Settings.Page.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Forms,
  Vcl.Menus,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Commands.KeyConflicts,
  Atlas.UI.Strings;

type
  /// <summary>Wer belegt die Taste außer Atlas? '' wenn frei.</summary>
  TAtlasKeyOwnerFunc = reference to function(AShortCut: Word): string;

  TAtlasKeysPage = class(TFrame)
  private type
    TRow = record
      Key: TEdit;
      Choice: TComboBox;
      Status: TLabel;
    end;
  private
    FEntries: TArray<TAtlasKeyEntry>;
    FRows: TArray<TRow>;
    FForeign: TLabel;
    FOwnerOf: TAtlasKeyOwnerFunc;
    FNextTop: Integer;
    FUpdating: Boolean;
    function AddPanel(AHeight: Integer): TPanel;
    function AddLabel(AParent: TWinControl; const ACaption: string; ALeft, ATop: Integer): TLabel;
    procedure AddRow(AIndex: Integer);
    procedure KeyChange(Sender: TObject);
    procedure ChoiceChange(Sender: TObject);
    procedure UpdateRow(AIndex: Integer);
    procedure SetOwnerOf(const AValue: TAtlasKeyOwnerFunc);
    class function FunctionCaption(AFunc: TAtlasKeyFunction): string; static;
  public
    constructor Create(AOwner: TComponent); override;
    procedure LoadFrom(const ASettings: TAtlasPluginSettings);
    procedure SaveTo(var ASettings: TAtlasPluginSettings);
    /// <summary>Text der Statuszeile für AEntry bei fremder Belegung AOwner.</summary>
    class function StatusText(const AEntry: TAtlasKeyEntry; const AOwner: string): string; static;
    /// <summary>Erkannte Erweiterungen mit eigener Vervollständigung (#494).</summary>
    procedure ShowForeignCompletions(const ANames: TArray<string>);
    property OwnerOf: TAtlasKeyOwnerFunc read FOwnerOf write SetOwnerOf;
    /// <summary>Zum Testen: Steuerelemente der Zeile AIndex.</summary>
    function KeyEdit(AIndex: Integer): TEdit;
    function ChoiceBox(AIndex: Integer): TComboBox;
    function StatusLabel(AIndex: Integer): TLabel;
    function ForeignLabel: TLabel;
  end;

implementation

{$R *.dfm}

const
  KeyLeft = 150;
  ChoiceLeft = 290;

{ TAtlasKeysPage }

constructor TAtlasKeysPage.Create(AOwner: TComponent);
var
  Title, Intro: TLabel;
  Panel: TPanel;
  Index: Integer;
begin
  inherited Create(AOwner);
  Name := 'AtlasKeysPage';
  Width := 480;
  Height := 420;
  FNextTop := 0;
  Title := TLabel.Create(Self);
  Title.Parent := Self;
  Title.Align := alTop;
  Title.AlignWithMargins := True;
  Title.Caption := TAtlasStrings.Text(TAtlasTextId.KeysTitle);
  Title.Font.Style := [fsBold];
  Title.Top := FNextTop;
  Inc(FNextTop, 100);
  Intro := TLabel.Create(Self);
  Intro.Parent := Self;
  Intro.Align := alTop;
  Intro.AlignWithMargins := True;
  Intro.WordWrap := True;
  Intro.Caption := TAtlasStrings.Text(TAtlasTextId.KeysIntro);
  Intro.Top := FNextTop;
  Inc(FNextTop, 100);
  Panel := AddPanel(20);
  AddLabel(Panel, TAtlasStrings.Text(TAtlasTextId.KeysHeaderFunction), 0, 2).Font.Style := [fsBold];
  AddLabel(Panel, TAtlasStrings.Text(TAtlasTextId.KeysHeaderKey), KeyLeft, 2).Font.Style := [fsBold];
  AddLabel(Panel, TAtlasStrings.Text(TAtlasTextId.KeysHeaderChoice), ChoiceLeft, 2).Font.Style := [fsBold];
  FEntries := TAtlasKeyEntry.FromSettings(TAtlasPluginSettings.Defaults);
  SetLength(FRows, Length(FEntries));
  for Index := 0 to High(FEntries) do
    AddRow(Index);
  FForeign := TLabel.Create(Self);
  FForeign.Parent := Self;
  FForeign.Align := alTop;
  FForeign.AlignWithMargins := True;
  FForeign.WordWrap := True;
  FForeign.Top := FNextTop;
  Inc(FNextTop, 100);
  ShowForeignCompletions(nil);
end;

function TAtlasKeysPage.AddPanel(AHeight: Integer): TPanel;
begin
  Result := TPanel.Create(Self);
  Result.Parent := Self;
  Result.Align := alTop;
  Result.AlignWithMargins := True;
  Result.BevelOuter := bvNone;
  Result.Height := AHeight;
  // alTop stapelt nach Top: jedes neue Element unter das vorige.
  Result.Top := FNextTop;
  Inc(FNextTop, 100);
  Result.ParentBackground := True;
end;

function TAtlasKeysPage.AddLabel(AParent: TWinControl; const ACaption: string; ALeft, ATop: Integer): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.Left := ALeft;
  Result.Top := ATop;
end;

procedure TAtlasKeysPage.AddRow(AIndex: Integer);
var
  Panel: TPanel;
begin
  Panel := AddPanel(46);
  AddLabel(Panel, FunctionCaption(FEntries[AIndex].Func), 0, 5);
  FRows[AIndex].Key := TEdit.Create(Self);
  FRows[AIndex].Key.Parent := Panel;
  FRows[AIndex].Key.Left := KeyLeft;
  FRows[AIndex].Key.Top := 1;
  FRows[AIndex].Key.Width := 130;
  FRows[AIndex].Key.Tag := AIndex;
  // Leer bei Vervollständigung und Parameter-Hint: die Taste der IDE.
  if FEntries[AIndex].IdeKey <> 0 then
    FRows[AIndex].Key.TextHint := ShortCutToText(TShortCut(FEntries[AIndex].IdeKey));
  FRows[AIndex].Key.OnChange := KeyChange;
  FRows[AIndex].Choice := TComboBox.Create(Self);
  FRows[AIndex].Choice.Parent := Panel;
  FRows[AIndex].Choice.Style := csDropDownList;
  FRows[AIndex].Choice.Left := ChoiceLeft;
  FRows[AIndex].Choice.Top := 1;
  FRows[AIndex].Choice.Width := 180;
  FRows[AIndex].Choice.Anchors := [akLeft, akTop, akRight];
  FRows[AIndex].Choice.Tag := AIndex;
  // Reihenfolge wie TAtlasKeyChoice.
  FRows[AIndex].Choice.Items.Add(TAtlasStrings.Text(TAtlasTextId.KeysChoiceAtlas));
  FRows[AIndex].Choice.Items.Add(TAtlasStrings.Text(TAtlasTextId.KeysChoiceOther));
  FRows[AIndex].Choice.Items.Add(TAtlasStrings.Text(TAtlasTextId.KeysChoiceNewKey));
  FRows[AIndex].Choice.OnChange := ChoiceChange;
  FRows[AIndex].Status := AddLabel(Panel, '', KeyLeft, 27);
  FRows[AIndex].Status.Font.Color := clGrayText;
end;

class function TAtlasKeysPage.FunctionCaption(AFunc: TAtlasKeyFunction): string;
begin
  case AFunc of
    TAtlasKeyFunction.Palette:
      Result := TAtlasStrings.Text(TAtlasTextId.SettingsPaletteKey);
    TAtlasKeyFunction.Check:
      Result := TAtlasStrings.Text(TAtlasTextId.SettingsCheckKey);
    TAtlasKeyFunction.Completion:
      Result := TAtlasStrings.Text(TAtlasTextId.SettingsCompletionKey);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.SettingsSignatureKey);
  end;
end;

class function TAtlasKeysPage.StatusText(const AEntry: TAtlasKeyEntry; const AOwner: string): string;
begin
  case AEntry.Status(AOwner) of
    TAtlasKeyStatus.NoKey:
      Result := TAtlasStrings.Text(TAtlasTextId.KeysStatusNone);
    TAtlasKeyStatus.IdeKey:
      Result := TAtlasStrings.Fmt(TAtlasTextId.KeysStatusIdeKey, [ShortCutToText(TShortCut(AEntry.IdeKey))]);
    TAtlasKeyStatus.Free:
      Result := TAtlasStrings.Text(TAtlasTextId.KeysStatusFree);
    TAtlasKeyStatus.AtlasWins:
      Result := TAtlasStrings.Fmt(TAtlasTextId.KeysStatusAtlasWins, [AOwner]);
  else
    Result := TAtlasStrings.Fmt(TAtlasTextId.KeysStatusLeft, [AOwner]);
  end;
end;

procedure TAtlasKeysPage.UpdateRow(AIndex: Integer);
var
  Owner, Text: string;
  Status: TAtlasKeyStatus;
begin
  Text := Trim(FRows[AIndex].Key.Text);
  if (Text <> '') and (TextToShortCut(Text) = 0) then
  begin
    FRows[AIndex].Status.Caption := TAtlasStrings.Fmt(TAtlasTextId.KeysInvalid, [Text]);
    Exit;
  end;
  Owner := '';
  if Assigned(FOwnerOf) and (FEntries[AIndex].Key <> 0) then
    Owner := FOwnerOf(FEntries[AIndex].Key);
  Status := FEntries[AIndex].Status(Owner);
  FRows[AIndex].Status.Caption := StatusText(FEntries[AIndex], Owner);
  FUpdating := True;
  try
    FRows[AIndex].Choice.ItemIndex := Ord(FEntries[AIndex].Choice);
    // Zu entscheiden gibt es nur bei einer Belegung (bzw. bei der Taste der IDE).
    FRows[AIndex].Choice.Enabled := (Status <> TAtlasKeyStatus.Free) and (Status <> TAtlasKeyStatus.NoKey);
  finally
    FUpdating := False;
  end;
end;

procedure TAtlasKeysPage.KeyChange(Sender: TObject);
var
  Index: Integer;
begin
  if FUpdating then
    Exit;
  Index := TEdit(Sender).Tag;
  FEntries[Index].Key := Word(TextToShortCut(Trim(TEdit(Sender).Text)));
  UpdateRow(Index);
end;

procedure TAtlasKeysPage.ChoiceChange(Sender: TObject);
var
  Index: Integer;
  Choice: TAtlasKeyChoice;
  Key: TEdit;
begin
  if FUpdating or (TComboBox(Sender).ItemIndex < 0) then
    Exit;
  Index := TComboBox(Sender).Tag;
  Choice := TAtlasKeyChoice(TComboBox(Sender).ItemIndex);
  FEntries[Index].Choose(Choice);
  Key := FRows[Index].Key;
  FUpdating := True;
  try
    // „Atlas verwenden“ ohne eigene Taste übernimmt die Taste der IDE.
    if (FEntries[Index].Key <> 0) and (Trim(Key.Text) = '') then
      Key.Text := ShortCutToText(TShortCut(FEntries[Index].Key));
  finally
    FUpdating := False;
  end;
  UpdateRow(Index);
  if (Choice = TAtlasKeyChoice.OtherKey) and Key.CanFocus then
  begin
    Key.SetFocus;
    Key.SelectAll;
  end;
end;

procedure TAtlasKeysPage.SetOwnerOf(const AValue: TAtlasKeyOwnerFunc);
var
  Index: Integer;
begin
  FOwnerOf := AValue;
  for Index := 0 to High(FRows) do
    UpdateRow(Index);
end;

procedure TAtlasKeysPage.LoadFrom(const ASettings: TAtlasPluginSettings);
var
  Index: Integer;
begin
  FEntries := TAtlasKeyEntry.FromSettings(ASettings);
  FUpdating := True;
  try
    for Index := 0 to High(FRows) do
      if FEntries[Index].Key = 0 then
        FRows[Index].Key.Text := ''
      else
        FRows[Index].Key.Text := ShortCutToText(TShortCut(FEntries[Index].Key));
  finally
    FUpdating := False;
  end;
  for Index := 0 to High(FRows) do
    UpdateRow(Index);
end;

procedure TAtlasKeysPage.SaveTo(var ASettings: TAtlasPluginSettings);
begin
  TAtlasKeyEntry.ToSettings(FEntries, ASettings);
  ASettings.Normalize;
end;

procedure TAtlasKeysPage.ShowForeignCompletions(const ANames: TArray<string>);
begin
  if Length(ANames) = 0 then
    FForeign.Caption := TAtlasStrings.Text(TAtlasTextId.KeysForeignNone)
  else
    FForeign.Caption := TAtlasStrings.Fmt(TAtlasTextId.KeysForeign, [string.Join(', ', ANames)]);
end;

function TAtlasKeysPage.KeyEdit(AIndex: Integer): TEdit;
begin
  Result := FRows[AIndex].Key;
end;

function TAtlasKeysPage.ChoiceBox(AIndex: Integer): TComboBox;
begin
  Result := FRows[AIndex].Choice;
end;

function TAtlasKeysPage.StatusLabel(AIndex: Integer): TLabel;
begin
  Result := FRows[AIndex].Status;
end;

function TAtlasKeysPage.ForeignLabel: TLabel;
begin
  Result := FForeign;
end;

end.
