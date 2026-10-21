unit Atlas.UI.Search.Dialog;

// Atlas-Suchdialog (#877, #878): Suchtext; Bereich Methode, Unit oder
// Auswahl, bei Methode die Stufe (innerste … äußerste umgebende Routine);
// Optionen Groß-/Kleinschreibung, ganzes Wort, Bezeichner statt Text.
// Beim Tippen sucht der Dialog sofort (Rückruf OnRun) und zeigt die Treffer
// als Liste „Zeile: Text“. Enter im Suchfeld springt zum nächsten Treffer ab
// dem Cursor, Enter oder Doppelklick in der Liste zum gewählten; danach
// schließt der Dialog. Esc schließt ohne Sprung. Reine VCL; gesucht und
// gesprungen wird vom Aufrufer (Atlas.IDE.Search.Commands).

interface

uses
  System.SysUtils,
  System.Classes,
  Winapi.Windows,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Atlas.Core.Search.Matching;

type
  /// <summary>Sucht mit AQuery; liefert die Zeilen der Trefferliste und eine Meldung ('' ohne).</summary>
  TAtlasSearchRun = reference to procedure(const AQuery: TAtlasSearchQuery; out ACaptions: TArray<string>;
    out AMessage: string);

  TAtlasSearchDialog = class(TForm)
  private
    FTextLabel: TLabel;
    FText: TEdit;
    FScope: TComboBox;
    FLevel: TComboBox;
    FCase: TCheckBox;
    FWhole: TCheckBox;
    FIdentifier: TCheckBox;
    FStatus: TLabel;
    FList: TListBox;
    FFooter: TLabel;
    FRun: TAtlasSearchRun;
    FQuery: TAtlasSearchQuery;
    FLevels: TArray<string>;
    FHasSelection: Boolean;
    FFilled: Boolean;
    FChosen: Integer;
    procedure Changed(Sender: TObject);
    procedure TextKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ListDblClick(Sender: TObject);
    procedure Fill;
    procedure Refresh;
    function AddCheck(const ACaption: string): TCheckBox;
  protected
    procedure DoShow; override;
  public
    constructor CreateDialog(AOwner: TComponent; const AQuery: TAtlasSearchQuery; const ALevels: TArray<string>;
      AHasSelection: Boolean; const ARun: TAtlasSearchRun);
    /// <summary>Suche nach den Feldern des Dialogs.</summary>
    function Query: TAtlasSearchQuery;
    /// <summary>Gewählter Treffer der Liste; -1 = nächster ab dem Cursor.</summary>
    property Chosen: Integer read FChosen;
    /// <summary>Modal; True mit Suche und gewähltem Treffer, False bei Esc.</summary>
    class function Execute(var AQuery: TAtlasSearchQuery; const ALevels: TArray<string>; AHasSelection: Boolean;
      const ARun: TAtlasSearchRun; out AChosen: Integer): Boolean; static;
  end;

implementation

uses
  Atlas.UI.Strings;

const
  Gap = 8;
  DialogWidth = 560;
  ListHeight = 260;

{ TAtlasSearchDialog }

constructor TAtlasSearchDialog.CreateDialog(AOwner: TComponent; const AQuery: TAtlasSearchQuery;
  const ALevels: TArray<string>; AHasSelection: Boolean; const ARun: TAtlasSearchRun);
var
  Row: TPanel;
begin
  inherited CreateNew(AOwner);
  FQuery := AQuery;
  FLevels := ALevels;
  FHasSelection := AHasSelection;
  FRun := ARun;
  FChosen := -1;
  Caption := TAtlasStrings.Text(TAtlasTextId.SearchDialogTitle);
  BorderStyle := bsSizeToolWin;
  BorderIcons := [biSystemMenu];
  Position := poMainFormCenter;
  KeyPreview := True;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  ClientWidth := ScaleValue(DialogWidth);
  ClientHeight := ScaleValue(ListHeight + 170);

  FTextLabel := TLabel.Create(Self);
  FTextLabel.Parent := Self;
  FTextLabel.Align := alTop;
  FTextLabel.AlignWithMargins := True;
  FTextLabel.Margins.SetBounds(Gap, Gap, Gap, 2);
  FTextLabel.ShowAccelChar := False;
  FTextLabel.Caption := TAtlasStrings.Text(TAtlasTextId.SearchTextLabel);

  FText := TEdit.Create(Self);
  FText.Parent := Self;
  FText.Align := alTop;
  FText.AlignWithMargins := True;
  FText.Margins.SetBounds(Gap, 0, Gap, Gap div 2);
  FText.Top := FTextLabel.Top + FTextLabel.Height + 1;
  FText.Text := AQuery.Text;
  FText.AutoSelect := True;
  FText.OnChange := Changed;
  FText.OnKeyDown := TextKeyDown;
  FTextLabel.FocusControl := FText;

  // Zeile: Bereich und Stufe der Methode.
  Row := TPanel.Create(Self);
  Row.Parent := Self;
  Row.Align := alTop;
  Row.Top := FText.Top + FText.Height + 1;
  Row.BevelOuter := bvNone;
  Row.Height := ScaleValue(30);
  FScope := TComboBox.Create(Self);
  FScope.Parent := Row;
  FScope.Style := csDropDownList;
  FScope.SetBounds(ScaleValue(Gap), ScaleValue(3), ScaleValue(140), ScaleValue(24));
  FScope.OnChange := Changed;
  FLevel := TComboBox.Create(Self);
  FLevel.Parent := Row;
  FLevel.Style := csDropDownList;
  FLevel.SetBounds(ScaleValue(Gap + 150), ScaleValue(3), ScaleValue(DialogWidth - 150 - 2 * Gap), ScaleValue(24));
  FLevel.Anchors := [akLeft, akTop, akRight];
  FLevel.OnChange := Changed;

  FCase := AddCheck(TAtlasStrings.Text(TAtlasTextId.SearchCaseSensitive));
  FCase.Checked := AQuery.Options.CaseSensitive;
  FWhole := AddCheck(TAtlasStrings.Text(TAtlasTextId.SearchWholeWord));
  FWhole.Checked := AQuery.Options.WholeWord;
  FIdentifier := AddCheck(TAtlasStrings.Text(TAtlasTextId.SearchIdentifier));
  FIdentifier.Checked := AQuery.Options.Identifier;

  FStatus := TLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.Align := alTop;
  FStatus.Top := FIdentifier.Top + FIdentifier.Height + 1;
  FStatus.AlignWithMargins := True;
  FStatus.Margins.SetBounds(Gap, Gap div 2, Gap, 2);
  FStatus.ShowAccelChar := False;

  FFooter := TLabel.Create(Self);
  FFooter.Parent := Self;
  FFooter.Align := alBottom;
  FFooter.AlignWithMargins := True;
  FFooter.Margins.SetBounds(Gap, 2, Gap, Gap div 2);
  FFooter.ShowAccelChar := False;
  FFooter.Caption := TAtlasStrings.Text(TAtlasTextId.SearchFooter);

  FList := TListBox.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.AlignWithMargins := True;
  FList.Margins.SetBounds(Gap, 0, Gap, 0);
  FList.OnKeyDown := ListKeyDown;
  FList.OnDblClick := ListDblClick;

  ActiveControl := FText;
end;

function TAtlasSearchDialog.AddCheck(const ACaption: string): TCheckBox;
var
  Last: TControl;
begin
  Result := TCheckBox.Create(Self);
  Result.Parent := Self;
  Result.Align := alTop;
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(Gap, 1, Gap, 1);
  Last := Controls[ControlCount - 2];
  Result.Top := Last.Top + Last.Height + 1;
  Result.Caption := ACaption;
  Result.OnClick := Changed;
end;

procedure TAtlasSearchDialog.DoShow;
begin
  inherited DoShow;
  // Listen brauchen ein Fenster: erst beim Zeigen füllen.
  if not FFilled then
    Fill;
end;

procedure TAtlasSearchDialog.Fill;
var
  Level: string;
begin
  FFilled := True;
  FScope.Items.Add(TAtlasStrings.Text(TAtlasTextId.SearchScopeMethod));
  FScope.Items.Add(TAtlasStrings.Text(TAtlasTextId.SearchScopeUnit));
  if FHasSelection then
    FScope.Items.Add(TAtlasStrings.Text(TAtlasTextId.SearchScopeSelection));
  // Ohne Auswahl fällt „Auswahl“ auf „Unit“ zurück.
  if (FQuery.Scope = TAtlasSearchScope.Selection) and not FHasSelection then
    FQuery.Scope := TAtlasSearchScope.UnitFile;
  FScope.ItemIndex := Ord(FQuery.Scope);
  for Level in FLevels do
    FLevel.Items.Add(Level);
  if Length(FLevels) > 0 then
  begin
    FLevel.ItemIndex := FQuery.Level;
    if FLevel.ItemIndex < 0 then
      FLevel.ItemIndex := 0;
  end;
  Refresh;
end;

function TAtlasSearchDialog.Query: TAtlasSearchQuery;
begin
  Result := FQuery;
  Result.Text := FText.Text;
  Result.Options := TAtlasSearchOptions.Create(FCase.Checked, FWhole.Checked, FIdentifier.Checked);
  if FScope.ItemIndex >= 0 then
    Result.Scope := TAtlasSearchScope(FScope.ItemIndex);
  Result.Level := FLevel.ItemIndex;
  if Result.Level < 0 then
    Result.Level := 0;
end;

procedure TAtlasSearchDialog.Refresh;
var
  Captions: TArray<string>;
  Message, Line: string;
begin
  if not FFilled then
    Exit;
  FLevel.Enabled := (FScope.ItemIndex = Ord(TAtlasSearchScope.Method)) and (FLevel.Items.Count > 0);
  // Bezeichner-Modus kennt nur ganze Bezeichner ohne Rücksicht auf die Schreibweise.
  FCase.Enabled := not FIdentifier.Checked;
  FWhole.Enabled := not FIdentifier.Checked;
  Captions := nil;
  Message := '';
  if Assigned(FRun) and (FText.Text <> '') then
    FRun(Query, Captions, Message);
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for Line in Captions do
      FList.Items.Add(Line);
  finally
    FList.Items.EndUpdate;
  end;
  if FList.Items.Count > 0 then
    FList.ItemIndex := 0;
  if Message <> '' then
    FStatus.Caption := Message
  else if FText.Text = '' then
    FStatus.Caption := ''
  else if Length(Captions) = 0 then
    FStatus.Caption := TAtlasStrings.Text(TAtlasTextId.SearchNoHits)
  else
    FStatus.Caption := TAtlasStrings.Fmt(TAtlasTextId.SearchHitCount, [Length(Captions)]);
end;

procedure TAtlasSearchDialog.Changed(Sender: TObject);
begin
  Refresh;
end;

procedure TAtlasSearchDialog.TextKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_RETURN:
      begin
        Key := 0;
        if FText.Text = '' then
          Exit;
        FChosen := -1;
        ModalResult := mrOk;
      end;
    VK_DOWN:
      if FList.Items.Count > 0 then
      begin
        Key := 0;
        FList.SetFocus;
      end;
    VK_ESCAPE:
      begin
        Key := 0;
        ModalResult := mrCancel;
      end;
  end;
end;

procedure TAtlasSearchDialog.ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_RETURN:
      begin
        Key := 0;
        ListDblClick(Sender);
      end;
    VK_ESCAPE:
      begin
        Key := 0;
        ModalResult := mrCancel;
      end;
  end;
end;

procedure TAtlasSearchDialog.ListDblClick(Sender: TObject);
begin
  if FList.ItemIndex < 0 then
    Exit;
  FChosen := FList.ItemIndex;
  ModalResult := mrOk;
end;

class function TAtlasSearchDialog.Execute(var AQuery: TAtlasSearchQuery; const ALevels: TArray<string>;
  AHasSelection: Boolean; const ARun: TAtlasSearchRun; out AChosen: Integer): Boolean;
var
  Dialog: TAtlasSearchDialog;
begin
  AChosen := -1;
  Dialog := TAtlasSearchDialog.CreateDialog(nil, AQuery, ALevels, AHasSelection, ARun);
  try
    Result := (Dialog.ShowModal = mrOk) and (Dialog.Query.Text <> '');
    if Result then
    begin
      AQuery := Dialog.Query;
      AChosen := Dialog.Chosen;
    end;
  finally
    Dialog.Free;
  end;
end;

end.
