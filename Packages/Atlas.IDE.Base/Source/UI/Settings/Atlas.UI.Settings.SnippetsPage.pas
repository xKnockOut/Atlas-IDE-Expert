unit Atlas.UI.Settings.SnippetsPage;

// Seite „Snippets“ unter Tools › Optionen › Drittanbieter › Atlas (#51, #227):
// alle Code-Vorlagen mit Herkunft (eigene, IDE, mitgeliefert); eigene lassen
// sich anlegen, bearbeiten und löschen, mitgelieferte und IDE-Vorlagen als
// eigene kopieren. Reine VCL, im Code aufgebaut wie Atlas.UI.Settings.Page;
// das Datenmodell ist TAtlasSnippetCatalog. Gespeichert wird beim Schließen
// des Dialogs mit OK (Atlas.IDE.Settings.Options).

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.ExtCtrls,
  Vcl.Forms,
  Atlas.Core.Completion.Snippets,
  Atlas.Core.Completion.SnippetCatalog,
  Atlas.UI.Settings.Strings;

type
  TAtlasSnippetsPage = class(TFrame)
  private
    FCatalog: TAtlasSnippetCatalog;
    FList: TListView;
    FPrefix: TEdit;
    FName: TEdit;
    FDescription: TEdit;
    FBody: TMemo;
    FReadOnlyHint: TLabel;
    FNew: TButton;
    FCopy: TButton;
    FDelete: TButton;
    // Felder werden gerade aus dem Katalog gefüllt: Änderungen nicht zurückschreiben.
    FFilling: Boolean;
    function AddField(AParent: TWinControl; const ACaption: string; ATop: Integer): TEdit;
    /// <summary>Leiste unten mit „Neu“, „Kopieren“ und „Löschen“.</summary>
    procedure CreateButtons;
    /// <summary>Liste der Vorlagen links.</summary>
    procedure CreateList;
    /// <summary>Felder der gewählten Vorlage rechts.</summary>
    procedure CreateEditor;
    procedure FillList(ASelect: Integer);
    procedure ShowEntry;
    function Selected: Integer;
    procedure ListSelect(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure FieldChange(Sender: TObject);
    procedure NewClick(Sender: TObject);
    procedure CopyClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Übernimmt ACatalog (gibt ihn frei).</summary>
    procedure Load(ACatalog: TAtlasSnippetCatalog);
    /// <summary>'' ohne Fehler, sonst die Meldung zur ersten fehlerhaften Vorlage (die dann ausgewählt ist).</summary>
    function Validate: string;
    property Catalog: TAtlasSnippetCatalog read FCatalog;
  end;

implementation

{$R *.dfm}

{ TAtlasSnippetsPage }

/// <summary>Knopf ACaption in der Leiste APanel an der Stelle ALeft mit der Breite AWidth.</summary>
function NewButton(APanel: TPanel; const ACaption: string; ALeft, AWidth: Integer; AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(APanel.Owner);
  Result.Parent := APanel;
  Result.SetBounds(ALeft, 4, AWidth, 25);
  Result.Caption := ACaption;
  Result.OnClick := AClick;
end;

constructor TAtlasSnippetsPage.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Name := 'AtlasSnippetsPage';
  Width := 560;
  Height := 420;
  CreateButtons;
  CreateList;
  CreateEditor;
  ShowEntry;
end;

procedure TAtlasSnippetsPage.CreateButtons;
var
  mButtons: TPanel;
begin
  mButtons := TPanel.Create(Self);
  mButtons.Parent := Self;
  mButtons.Align := alBottom;
  mButtons.BevelOuter := bvNone;
  mButtons.Height := 34;
  mButtons.ParentBackground := True;
  FNew := NewButton(mButtons, TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SnippetsNew), 4, 90, NewClick);
  FCopy := NewButton(mButtons, TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SnippetsCopy), 100, 150, CopyClick);
  FDelete := NewButton(mButtons, TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SnippetsDelete), 256, 90, DeleteClick);
end;

procedure TAtlasSnippetsPage.CreateList;
var
  mColumn: TListColumn;
begin
  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alLeft;
  FList.AlignWithMargins := True;
  FList.Width := 230;
  FList.ViewStyle := vsReport;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  FList.HideSelection := False;
  mColumn := FList.Columns.Add;
  mColumn.Caption := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SnippetsPrefix);
  mColumn.Width := 90;
  mColumn := FList.Columns.Add;
  mColumn.Caption := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SnippetsName);
  mColumn.Width := 130;
  FList.OnSelectItem := ListSelect;
end;

procedure TAtlasSnippetsPage.CreateEditor;
var
  mEditor: TPanel;
  mCaption: TLabel;
begin
  mEditor := TPanel.Create(Self);
  mEditor.Parent := Self;
  mEditor.Align := alClient;
  mEditor.BevelOuter := bvNone;
  mEditor.ParentBackground := True;
  FPrefix := AddField(mEditor, TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SnippetsPrefix), 4);
  FName := AddField(mEditor, TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SnippetsName), 32);
  FDescription := AddField(mEditor, TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SnippetsDescription), 60);
  mCaption := TLabel.Create(Self);
  mCaption.Parent := mEditor;
  mCaption.SetBounds(4, 92, 300, 15);
  mCaption.Caption := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SnippetsBody);
  FBody := TMemo.Create(Self);
  FBody.Parent := mEditor;
  FBody.SetBounds(4, 110, mEditor.Width - 8, 200);
  FBody.Anchors := [akLeft, akTop, akRight, akBottom];
  FBody.ScrollBars := ssBoth;
  FBody.WordWrap := False;
  FBody.WantTabs := False;
  FBody.Font.Name := 'Consolas';
  FBody.OnChange := FieldChange;
  FReadOnlyHint := TLabel.Create(Self);
  FReadOnlyHint.Parent := mEditor;
  FReadOnlyHint.Align := alBottom;
  FReadOnlyHint.AlignWithMargins := True;
  FReadOnlyHint.WordWrap := True;
  FReadOnlyHint.Font.Color := clGrayText;
  FReadOnlyHint.Caption := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SnippetsReadOnly);
end;

destructor TAtlasSnippetsPage.Destroy;
begin
  FCatalog.Free;
  inherited Destroy;
end;

function TAtlasSnippetsPage.AddField(AParent: TWinControl; const ACaption: string; ATop: Integer): TEdit;
var
  mCaption: TLabel;
begin
  mCaption := TLabel.Create(Self);
  mCaption.Parent := AParent;
  mCaption.SetBounds(4, ATop + 4, 90, 15);
  mCaption.Caption := ACaption;
  Result := TEdit.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(100, ATop, AParent.Width - 104, 23);
  Result.Anchors := [akLeft, akTop, akRight];
  Result.OnChange := FieldChange;
end;

procedure TAtlasSnippetsPage.Load(ACatalog: TAtlasSnippetCatalog);
begin
  FCatalog.Free;
  FCatalog := ACatalog;
  FillList(0);
end;

function OriginText(AOrigin: TAtlasSnippetOrigin): string;
begin
  case AOrigin of
    TAtlasSnippetOrigin.User:
      Result := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SnippetsOriginUser);
    TAtlasSnippetOrigin.Ide:
      Result := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SnippetsOriginIde);
  else
    Result := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SnippetsOriginBuiltIn);
  end;
end;

procedure TAtlasSnippetsPage.FillList(ASelect: Integer);
var
  mIndex: Integer;
  mItem: TListItem;
  mEntry: TAtlasSnippetEntry;
  mDetail: string;
begin
  FFilling := True;
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    if FCatalog <> nil then
    begin
      for mIndex := 0 to FCatalog.Count - 1 do
      begin
        mEntry := FCatalog.Entry(mIndex);
        mItem := FList.Items.Add;
        mItem.Caption := mEntry.Snippet.Prefix;
        // Herkunft und, falls eine andere Vorlage mit demselben Kürzel gilt, „ersetzt“.
        mDetail := OriginText(mEntry.Snippet.Origin);
        if FCatalog.Replaced(mIndex) then
        begin
          mDetail := mDetail + ', ' + TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SnippetsReplaced);
        end;
        mItem.SubItems.Add(mEntry.Snippet.Name + ' (' + mDetail + ')');
      end;
    end;
  finally
    FList.Items.EndUpdate;
    FFilling := False;
  end;
  if (ASelect >= 0) and (ASelect < FList.Items.Count) then
  begin
    FList.Items[ASelect].Selected := True;
    FList.Items[ASelect].MakeVisible(False);
  end;
  ShowEntry;
end;

function TAtlasSnippetsPage.Selected: Integer;
begin
  if (FCatalog = nil) or (FList.Selected = nil) then
  begin
    Result := -1;
  end
  else
  begin
    Result := FList.Selected.Index;
  end;
end;

procedure TAtlasSnippetsPage.ShowEntry;
var
  mIndex: Integer;
  mEntry: TAtlasSnippetEntry;
  mCanEdit: Boolean;
begin
  mIndex := Selected;
  FFilling := True;
  try
    if mIndex < 0 then
    begin
      FPrefix.Text := '';
      FName.Text := '';
      FDescription.Text := '';
      FBody.Text := '';
      mCanEdit := False;
    end
    else
    begin
      mEntry := FCatalog.Entry(mIndex);
      FPrefix.Text := mEntry.Snippet.Prefix;
      FName.Text := mEntry.Snippet.Name;
      FDescription.Text := mEntry.Snippet.Description;
      FBody.Text := StringReplace(mEntry.Snippet.Body, #10, #13#10, [rfReplaceAll]);
      mCanEdit := FCatalog.Editable(mIndex);
    end;
  finally
    FFilling := False;
  end;
  FPrefix.ReadOnly := not mCanEdit;
  FName.ReadOnly := not mCanEdit;
  FDescription.ReadOnly := not mCanEdit;
  FBody.ReadOnly := not mCanEdit;
  FReadOnlyHint.Visible := (mIndex >= 0) and not mCanEdit;
  FCopy.Enabled := mIndex >= 0;
  FDelete.Enabled := mCanEdit;
  FNew.Enabled := FCatalog <> nil;
end;

procedure TAtlasSnippetsPage.ListSelect(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if not FFilling then
  begin
    ShowEntry;
  end;
end;

procedure TAtlasSnippetsPage.FieldChange(Sender: TObject);
var
  mIndex: Integer;
  mSnippet: TAtlasSnippet;
  mEntry: TAtlasSnippetEntry;
begin
  mIndex := Selected;
  if FFilling or (mIndex < 0) or not FCatalog.Editable(mIndex) then
  begin
    Exit;
  end;
  mSnippet := FCatalog.Entry(mIndex).Snippet;
  mSnippet.Prefix := Trim(FPrefix.Text);
  mSnippet.Name := Trim(FName.Text);
  mSnippet.Description := Trim(FDescription.Text);
  mSnippet.Body := StringReplace(StringReplace(FBody.Text, #13#10, #10, [rfReplaceAll]), #13, #10, [rfReplaceAll]);
  FCatalog.Update(mIndex, mSnippet);
  // Nur die Zeile in der Liste anpassen; die Auswahl bleibt.
  mEntry := FCatalog.Entry(mIndex);
  FList.Items[mIndex].Caption := mEntry.Snippet.Prefix;
end;

procedure TAtlasSnippetsPage.NewClick(Sender: TObject);
begin
  if FCatalog = nil then
  begin
    Exit;
  end;
  FillList(FCatalog.AddNew);
  if FPrefix.CanFocus and FPrefix.Showing then
  begin
    FPrefix.SetFocus;
  end;
end;

procedure TAtlasSnippetsPage.CopyClick(Sender: TObject);
begin
  if Selected >= 0 then
  begin
    FillList(FCatalog.CopyAsOwn(Selected));
  end;
end;

procedure TAtlasSnippetsPage.DeleteClick(Sender: TObject);
var
  mIndex: Integer;
begin
  mIndex := Selected;
  if (mIndex < 0) or not FCatalog.Editable(mIndex) then
  begin
    Exit;
  end;
  FCatalog.Delete(mIndex);
  if mIndex >= FCatalog.Count then
  begin
    mIndex := FCatalog.Count - 1;
  end;
  FillList(mIndex);
end;

function TAtlasSnippetsPage.Validate: string;
var
  mProblems: TArray<TAtlasSnippetProblem>;
  mReason: string;
begin
  Result := '';
  if (FCatalog = nil) or FCatalog.Validate(mProblems) then
  begin
    Exit;
  end;
  case mProblems[0].Kind of
    TAtlasSnippetProblemKind.PrefixMissing:
      mReason := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SnippetsPrefixMissing);
    TAtlasSnippetProblemKind.PrefixInvalid:
      mReason := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SnippetsPrefixInvalid);
    TAtlasSnippetProblemKind.PrefixTwice:
      mReason := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SnippetsPrefixTwice);
  else
    mReason := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SnippetsBodyMissing);
  end;
  Result := Format(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SnippetsInvalid),
    [FCatalog.Entry(mProblems[0].Index).Snippet.Prefix, mReason]);
  FillList(mProblems[0].Index);
end;

end.
