unit Atlas.UI.Generate.Choice;

// Auswahldialog der Assistenten in der Objektgalerie (#1821), reine VCL: oben
// ein Suchfeld, darunter die Liste (Treffer aus TAtlasChoiceFilter), dazu
// „OK“ und „Abbrechen“. ↓ und ↑ im Suchfeld bewegen die Markierung, Enter
// oder Doppelklick übernimmt. Die Vorauswahl bleibt markiert, solange sie zur
// Suche passt. Aufgebaut im Code (keine DFM).

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Atlas.UI.Foundation.Dialog;

type
  TAtlasChoiceDialog = class(TAtlasDialog)
  private
    FItems: TArray<string>;
    FMatches: TArray<Integer>;
    FPrompt: TLabel;
    FSearch: TEdit;
    FList: TListBox;
    FOk: TButton;
    FCancel: TButton;
    procedure SearchChange(Sender: TObject);
    procedure SearchKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ListDblClick(Sender: TObject);
    procedure Fill(APreselect: Integer);
    function Chosen: Integer;
  public
    constructor CreateDialog(AOwner: TComponent; const ACaption, APrompt: string; const AItems: TArray<string>);
    /// <summary>Modal zeigen; True mit AIndex (Index in AItems), wenn „OK“ mit einem Eintrag gewählt wurde.
    /// AIndex ist beim Aufruf die Vorauswahl (-1 = keine).</summary>
    class function Execute(const ACaption, APrompt: string; const AItems: TArray<string>;
      var AIndex: Integer): Boolean; static;
  end;

implementation

uses
  Winapi.Windows,
  Atlas.Core.Generate.Choice,
  Atlas.UI.Generate.Strings;

const
  cGap = 12;
  cWidth = 420;
  cListHeight = 260;
  /// <summary>Abstand zwischen Beschriftung, Suchfeld und Liste.</summary>
  cLineGap = 4;
  /// <summary>Abstand zwischen den Knöpfen.</summary>
  cButtonGap = 8;

// Nicht "Scaled": In Methoden des Formulars verdeckt TCustomForm.Scaled (Boolean) den Namen (E2066/E2010).
function ScaledPx(ADialog: TForm; AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, ADialog.CurrentPPI, 96);
end;

constructor TAtlasChoiceDialog.CreateDialog(AOwner: TComponent; const ACaption, APrompt: string;
  const AItems: TArray<string>);
var
  mGap, mY: Integer;
begin
  inherited CreateDialog(AOwner, '', 0);
  FItems := AItems;
  Caption := ACaption;
  mGap := ScaledPx(Self, cGap);
  ClientWidth := ScaledPx(Self, cWidth) + 2 * mGap;
  mY := mGap;
  FPrompt := TLabel.Create(Self);
  FPrompt.Parent := Self;
  FPrompt.SetBounds(mGap, mY, ScaledPx(Self, cWidth), FPrompt.Height);
  FPrompt.Caption := APrompt;
  Inc(mY, FPrompt.Height + ScaledPx(Self, cLineGap));
  FSearch := TEdit.Create(Self);
  FSearch.Parent := Self;
  FSearch.SetBounds(mGap, mY, ScaledPx(Self, cWidth), FSearch.Height);
  FSearch.TextHint := TAtlasGenerateStrings.Text(TAtlasGenerateTextId.GalleryChoiceSearch);
  FSearch.OnChange := SearchChange;
  FSearch.OnKeyDown := SearchKeyDown;
  FPrompt.FocusControl := FSearch;
  Inc(mY, FSearch.Height + ScaledPx(Self, cLineGap));
  FList := TListBox.Create(Self);
  FList.Parent := Self;
  FList.SetBounds(mGap, mY, ScaledPx(Self, cWidth), ScaledPx(Self, cListHeight));
  FList.OnDblClick := ListDblClick;
  Inc(mY, FList.Height + mGap);
  FCancel := TButton.Create(Self);
  FCancel.Parent := Self;
  FCancel.Caption := TAtlasGenerateStrings.Text(TAtlasGenerateTextId.GalleryChoiceCancel);
  FCancel.Cancel := True;
  FCancel.ModalResult := mrCancel;
  FCancel.Top := mY;
  FCancel.Left := ClientWidth - mGap - FCancel.Width;
  FOk := TButton.Create(Self);
  FOk.Parent := Self;
  FOk.Caption := TAtlasGenerateStrings.Text(TAtlasGenerateTextId.GalleryChoiceOk);
  FOk.Default := True;
  FOk.ModalResult := mrOk;
  FOk.Top := mY;
  FOk.Left := FCancel.Left - ScaledPx(Self, cButtonGap) - FOk.Width;
  ClientHeight := mY + FOk.Height + mGap;
  ActiveControl := FSearch;
end;

procedure TAtlasChoiceDialog.Fill(APreselect: Integer);
var
  mIndex: Integer;
begin
  FMatches := TAtlasChoiceFilter.Matches(FItems, FSearch.Text);
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for mIndex in FMatches do
    begin
      FList.Items.Add(FItems[mIndex]);
    end;
  finally
    FList.Items.EndUpdate;
  end;
  FList.ItemIndex := TAtlasChoiceFilter.PositionOf(FMatches, APreselect);
  FOk.Enabled := FList.ItemIndex >= 0;
end;

function TAtlasChoiceDialog.Chosen: Integer;
begin
  Result := -1;
  if (FList.ItemIndex >= 0) and (FList.ItemIndex <= High(FMatches)) then
  begin
    Result := FMatches[FList.ItemIndex];
  end;
end;

procedure TAtlasChoiceDialog.SearchChange(Sender: TObject);
begin
  Fill(Chosen);
end;

procedure TAtlasChoiceDialog.SearchKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_DOWN:
      begin
        if FList.ItemIndex < FList.Items.Count - 1 then
        begin
          FList.ItemIndex := FList.ItemIndex + 1;
        end;
        Key := 0;
      end;
    VK_UP:
      begin
        if FList.ItemIndex > 0 then
        begin
          FList.ItemIndex := FList.ItemIndex - 1;
        end;
        Key := 0;
      end;
  end;
end;

procedure TAtlasChoiceDialog.ListDblClick(Sender: TObject);
begin
  if Chosen >= 0 then
  begin
    ModalResult := mrOk;
  end;
end;

class function TAtlasChoiceDialog.Execute(const ACaption, APrompt: string; const AItems: TArray<string>;
  var AIndex: Integer): Boolean;
var
  mDialog: TAtlasChoiceDialog;
begin
  mDialog := TAtlasChoiceDialog.CreateDialog(Application, ACaption, APrompt, AItems);
  try
    mDialog.Fill(AIndex);
    Result := (mDialog.ShowModal = mrOk) and (mDialog.Chosen >= 0);
    if Result then
    begin
      AIndex := mDialog.Chosen;
    end;
  finally
    mDialog.Free;
  end;
end;

end.
