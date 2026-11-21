unit Atlas.UI.Assistants.LogFrame;

// Inhalt des Fensters „Atlas-KI-Protokoll“ (#2049), reine VCL: oben die Kopfzeile („seit 10:38 · 3 Änderungen ·
// 1 Build · 1 abgelehnt“) und die Knöpfe „Unterschied“, „Zurücknehmen“, „Alle dieser Sitzung“, „Leeren“, darunter die
// virtuelle Liste mit Zeit, Art, Datei · Stelle und Ergebnis, neueste unten. Unten steht, warum sich der gewählte
// Eintrag nicht zurücknehmen lässt („Stelle wurde seither geändert“). Doppelklick oder Enter springt zur Stelle.
// Ob Zurücknehmen geht, fragt der Frame bei jeder Auswahl über OnSelect; die IDE-Schicht antwortet mit
// SetRevertState. Die DFM ist leer, weil TCustomFrame.Create für abgeleitete Frames eine Ressource verlangt;
// aufgebaut wird im Code.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Vcl.Forms,
  Atlas.Core.Assistants.Log;

type
  TAtlasLogEntryProc = reference to procedure(const AEntry: TAtlasAssistantsLogEntry);

{$SCOPEDENUMS ON}
  /// <summary>Knöpfe über der Liste, in ihrer Reihenfolge.</summary>
  TAtlasLogButton = (Diff, Revert, Session, Clear);
{$SCOPEDENUMS OFF}

  /// <summary>Texte des Fensters ohne Frame: Zellen, Art, Kopfzeile, Grund gegen Zurücknehmen.</summary>
  TAtlasAssistantsLogTexts = class
  public
    /// <summary>Text der Spalten: Zeit, Art, Datei · Stelle, Ergebnis.</summary>
    class function Cells(const AEntry: TAtlasAssistantsLogEntry): TArray<string>; static;
    class function KindCaption(AKind: TAtlasAssistantsLogKind): string; static;
    /// <summary>Kopfzeile; leer ohne Einträge.</summary>
    class function HeaderText(const ACounts: TAtlasAssistantsLogCounts; ASince: TDateTime): string; static;
    /// <summary>Warum sich ein Eintrag nicht zurücknehmen lässt; '' wenn doch.</summary>
    class function BlockText(ABlock: TAtlasLogRevertBlock): string; static;
  end;

  TAtlasAssistantsLogFrame = class(TFrame)
  private type
    TEvents = record
      Open: TAtlasLogEntryProc;
      Diff: TAtlasLogEntryProc;
      Revert: TAtlasLogEntryProc;
      Select: TAtlasLogEntryProc;
      Session: TProc;
      Clear: TProc;
    end;
  private
    FHeader: TLabel;
    FButtons: array[TAtlasLogButton] of TButton;
    FList: TListView;
    FEmpty: TLabel;
    FNote: TLabel;
    FEntries: TArray<TAtlasAssistantsLogEntry>;
    FCounts: TAtlasAssistantsLogCounts;
    FSince: TDateTime;
    FEvents: TEvents;
    procedure CreateBar;
    procedure CreateList;
    function AddButton(AParent: TWinControl; const ACaption: string; AButton: TAtlasLogButton): TButton;
    function GetButton(AButton: TAtlasLogButton): TButton;
    procedure ListData(Sender: TObject; Item: TListItem);
    procedure ListDblClick(Sender: TObject);
    procedure ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ListSelect(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure ButtonClick(Sender: TObject);
    procedure Run(const AProc: TAtlasLogEntryProc);
    procedure SelectionChanged;
  protected
    procedure CreateWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Einträge (älteste zuerst), Zahlen und Beginn zeigen; die Auswahl bleibt, ohne Auswahl rollt die
    /// Liste ans Ende.</summary>
    procedure SetEntries(const AEntries: TArray<TAtlasAssistantsLogEntry>; const ACounts: TAtlasAssistantsLogCounts;
      ASince: TDateTime);
    /// <summary>Liste neu füllen (braucht ein Fenster; CreateWnd ruft erneut).</summary>
    procedure Refill;
    /// <summary>„Zurücknehmen“ freigeben bzw. mit Grund sperren.</summary>
    procedure SetRevertState(ABlock: TAtlasLogRevertBlock);
    function TrySelected(out AEntry: TAtlasAssistantsLogEntry): Boolean;
    property List: TListView read FList;
    property Header: TLabel read FHeader;
    property Note: TLabel read FNote;
    property Buttons[AButton: TAtlasLogButton]: TButton read GetButton;
    property OnOpen: TAtlasLogEntryProc read FEvents.Open write FEvents.Open;
    property OnDiff: TAtlasLogEntryProc read FEvents.Diff write FEvents.Diff;
    property OnRevert: TAtlasLogEntryProc read FEvents.Revert write FEvents.Revert;
    property OnSelect: TAtlasLogEntryProc read FEvents.Select write FEvents.Select;
    property OnSession: TProc read FEvents.Session write FEvents.Session;
    property OnClear: TProc read FEvents.Clear write FEvents.Clear;
  end;

implementation

uses
  Winapi.Windows,
  Vcl.Graphics,
  Atlas.UI.Foundation.Dialog,
  Atlas.UI.Foundation.ListView,
  Atlas.UI.Foundation.WrapLabel,
  Atlas.UI.Assistants.Strings,
  Atlas.UI.Foundation.Theme;

{$R *.dfm}

const
  // Maße in logischen Pixeln (96 dpi).
  cBarHeight = 30;
  cButtonPadding = 24;
  cTimeWidth = 70;
  cKindWidth = 110;
  cPlaceWidth = 360;
  cResultWidth = 260;
  cKindTexts: array[TAtlasAssistantsLogKind] of TAtlasAssistantsTextId = (TAtlasAssistantsTextId.LogKindEdited,
    TAtlasAssistantsTextId.LogKindRefused, TAtlasAssistantsTextId.LogKindHeld, TAtlasAssistantsTextId.LogKindDiscarded,
    TAtlasAssistantsTextId.LogKindBuild, TAtlasAssistantsTextId.LogKindQuestion,
    TAtlasAssistantsTextId.LogKindReverted);
  cButtonTexts: array[TAtlasLogButton] of TAtlasAssistantsTextId = (TAtlasAssistantsTextId.LogDiff,
    TAtlasAssistantsTextId.LogRevert, TAtlasAssistantsTextId.LogSession, TAtlasAssistantsTextId.LogClear);

{ TAtlasAssistantsLogTexts }

class function TAtlasAssistantsLogTexts.KindCaption(AKind: TAtlasAssistantsLogKind): string;
begin
  Result := TAtlasAssistantsStrings.Text(cKindTexts[AKind]);
end;

class function TAtlasAssistantsLogTexts.Cells(const AEntry: TAtlasAssistantsLogEntry): TArray<string>;
var
  mPlace, mResult: string;
begin
  mPlace := ExtractFileName(AEntry.FileName);
  mResult := AEntry.Detail;
  if AEntry.HasChange then
  begin
    if AEntry.Change.LastLine > AEntry.Change.FirstLine then
    begin
      mPlace := mPlace + ' · ' + TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.LogLines,
        [AEntry.Change.FirstLine, AEntry.Change.LastLine]);
    end
    else
    begin
      mPlace := mPlace + ' · ' + TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.LogLine,
        [AEntry.Change.FirstLine]);
    end;
    if AEntry.Method <> '' then
    begin
      mPlace := mPlace + ' · ' + AEntry.Method;
    end;
    mResult := TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.LogPlusMinus, [AEntry.Change.Added,
      AEntry.Change.Removed]);
  end;
  if AEntry.Reverted then
  begin
    mResult := mResult + ' · ' + KindCaption(TAtlasAssistantsLogKind.Reverted);
  end;
  if (AEntry.Kind = TAtlasAssistantsLogKind.Question) and (AEntry.Client <> '') then
  begin
    mPlace := AEntry.Client;
  end;
  Result := TArray<string>.Create(FormatDateTime('hh:nn:ss', AEntry.Time, FormatSettings), KindCaption(AEntry.Kind),
    mPlace, mResult);
end;

class function TAtlasAssistantsLogTexts.HeaderText(const ACounts: TAtlasAssistantsLogCounts;
  ASince: TDateTime): string;
begin
  Result := '';
  if ASince <> 0 then
  begin
    Result := TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.LogHeader,
      [FormatDateTime('hh:nn', ASince, FormatSettings), ACounts.Edits, ACounts.Builds, ACounts.Refused]);
  end;
end;

class function TAtlasAssistantsLogTexts.BlockText(ABlock: TAtlasLogRevertBlock): string;
begin
  case ABlock of
    TAtlasLogRevertBlock.ChangedSince:
      Result := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.LogRevertChanged);
    TAtlasLogRevertBlock.TooLarge:
      Result := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.LogRevertTooLarge);
    TAtlasLogRevertBlock.AlreadyReverted:
      Result := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.LogRevertAlready);
  else
    Result := '';
  end;
end;

{ TAtlasAssistantsLogFrame }

constructor TAtlasAssistantsLogFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Der Name aus der DFM stört, wenn mehrere Frames denselben Besitzer haben.
  Name := '';
  CreateBar;
  FNote := TLabel.Create(Self);
  FNote.Parent := Self;
  FNote.Align := alBottom;
  FNote.AlignWithMargins := True;
  FNote.ShowAccelChar := False;
  TAtlasUiTheme.UseFontColor(FNote, clGrayText);
  FNote.Caption := '';
  CreateList;
  FEmpty := TAtlasWrapLabel.Create(Self);
  FEmpty.Parent := Self;
  FEmpty.Align := alClient;
  FEmpty.AlignWithMargins := True;
  FEmpty.ShowAccelChar := False;
  TAtlasUiTheme.UseFontColor(FEmpty, clGrayText);
  FEmpty.Caption := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.LogEmpty);
  FEmpty.Visible := False;
end;

procedure TAtlasAssistantsLogFrame.CreateWnd;
begin
  inherited CreateWnd;
  // Items.Count der virtuellen Liste braucht ein Fenster.
  Refill;
end;

function TAtlasAssistantsLogFrame.AddButton(AParent: TWinControl; const ACaption: string;
  AButton: TAtlasLogButton): TButton;
begin
  Result := TButton.Create(Self);
  // Lage vor Align und Parent: alLeft ordnet nach Left, die Knöpfe sollen in der Reihenfolge des Anlegens stehen.
  Result.Left := (AParent.ControlCount + 1) * MulDiv(cBarHeight, CurrentPPI, 96) * 10;
  Result.Align := alLeft;
  Result.AlignWithMargins := True;
  Result.Caption := ACaption;
  // Breite nach dem Text, Rand links und rechts.
  Result.Width := TAtlasDialog.TextWidth(Font, ACaption) + MulDiv(cButtonPadding, CurrentPPI, 96);
  Result.Parent := AParent;
  Result.Tag := Ord(AButton);
  Result.OnClick := ButtonClick;
  FButtons[AButton] := Result;
end;

function TAtlasAssistantsLogFrame.GetButton(AButton: TAtlasLogButton): TButton;
begin
  Result := FButtons[AButton];
end;

procedure TAtlasAssistantsLogFrame.CreateBar;
var
  mBar: TPanel;
  mButton: TAtlasLogButton;
begin
  FHeader := TLabel.Create(Self);
  FHeader.Top := 0;
  FHeader.Align := alTop;
  FHeader.AlignWithMargins := True;
  FHeader.ShowAccelChar := False;
  FHeader.Caption := '';
  FHeader.Parent := Self;

  mBar := TPanel.Create(Self);
  mBar.Top := FHeader.Top + FHeader.Height + 1;
  mBar.Height := MulDiv(cBarHeight, CurrentPPI, 96);
  mBar.Align := alTop;
  mBar.Parent := Self;
  mBar.BevelOuter := bvNone;
  mBar.ShowCaption := False;
  mBar.ParentBackground := True;
  for mButton := Low(TAtlasLogButton) to High(TAtlasLogButton) do
  begin
    AddButton(mBar, TAtlasAssistantsStrings.Text(cButtonTexts[mButton]), mButton);
  end;
end;

procedure TAtlasAssistantsLogFrame.CreateList;
begin
  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.AlignWithMargins := True;
  FList.ViewStyle := vsReport;
  FList.OwnerData := True;
  FList.RowSelect := True;
  FList.HideSelection := False;
  FList.ReadOnly := True;
  FList.MultiSelect := False;
  FList.ColumnClick := False;
  TAtlasListView.AddColumnTo(FList, TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.LogColumnTime), cTimeWidth);
  TAtlasListView.AddColumnTo(FList, TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.LogColumnKind), cKindWidth);
  TAtlasListView.AddColumnTo(FList, TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.LogColumnPlace), cPlaceWidth);
  TAtlasListView.AddColumnTo(FList, TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.LogColumnResult), cResultWidth);
  FList.OnData := ListData;
  FList.OnDblClick := ListDblClick;
  FList.OnKeyDown := ListKeyDown;
  FList.OnSelectItem := ListSelect;
end;

procedure TAtlasAssistantsLogFrame.SetEntries(const AEntries: TArray<TAtlasAssistantsLogEntry>;
  const ACounts: TAtlasAssistantsLogCounts; ASince: TDateTime);
begin
  FEntries := AEntries;
  FCounts := ACounts;
  FSince := ASince;
  Refill;
end;

procedure TAtlasAssistantsLogFrame.Refill;
var
  mHadSelection: Boolean;
begin
  FHeader.Caption := TAtlasAssistantsLogTexts.HeaderText(FCounts, FSince);
  FEmpty.Visible := FEntries = nil;
  FList.Visible := FEntries <> nil;
  FButtons[TAtlasLogButton.Session].Enabled := FCounts.Edits > 0;
  FButtons[TAtlasLogButton.Clear].Enabled := FEntries <> nil;
  if not FList.HandleAllocated then
  begin
    SelectionChanged;
    Exit;
  end;
  // Neue Einträge kommen ans Ende: Die Nummer einer Auswahl bleibt gültig, solange nichts vorn wegfällt.
  mHadSelection := FList.Selected <> nil;
  FList.Items.Count := Length(FEntries);
  if not mHadSelection and (FEntries <> nil) then
  begin
    // Ohne Auswahl rollt die Liste mit.
    FList.Items[High(FEntries)].MakeVisible(False);
  end;
  FList.Invalidate;
  SelectionChanged;
end;

procedure TAtlasAssistantsLogFrame.ListData(Sender: TObject; Item: TListItem);
var
  mTexts: TArray<string>;
  mPart: Integer;
begin
  if Item.Index > High(FEntries) then
  begin
    Exit;
  end;
  mTexts := TAtlasAssistantsLogTexts.Cells(FEntries[Item.Index]);
  Item.Caption := mTexts[0];
  for mPart := 1 to High(mTexts) do
  begin
    Item.SubItems.Add(mTexts[mPart]);
  end;
end;

function TAtlasAssistantsLogFrame.TrySelected(out AEntry: TAtlasAssistantsLogEntry): Boolean;
begin
  AEntry := Default(TAtlasAssistantsLogEntry);
  Result := FList.HandleAllocated and (FList.Selected <> nil) and (FList.Selected.Index <= High(FEntries));
  if Result then
  begin
    AEntry := FEntries[FList.Selected.Index];
  end;
end;

procedure TAtlasAssistantsLogFrame.SelectionChanged;
var
  mEntry: TAtlasAssistantsLogEntry;
begin
  if not TrySelected(mEntry) then
  begin
    FButtons[TAtlasLogButton.Diff].Enabled := False;
    FButtons[TAtlasLogButton.Revert].Enabled := False;
    FNote.Caption := '';
    Exit;
  end;
  FButtons[TAtlasLogButton.Diff].Enabled := mEntry.HasChange and mEntry.Change.Kept;
  FButtons[TAtlasLogButton.Revert].Enabled := False;
  FNote.Caption := '';
  if (mEntry.Kind = TAtlasAssistantsLogKind.Edited) and Assigned(FEvents.Select) then
  begin
    FEvents.Select(mEntry);
  end;
end;

procedure TAtlasAssistantsLogFrame.SetRevertState(ABlock: TAtlasLogRevertBlock);
begin
  FButtons[TAtlasLogButton.Revert].Enabled := ABlock = TAtlasLogRevertBlock.None;
  FNote.Caption := TAtlasAssistantsLogTexts.BlockText(ABlock);
end;

procedure TAtlasAssistantsLogFrame.ListSelect(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  SelectionChanged;
end;

procedure TAtlasAssistantsLogFrame.Run(const AProc: TAtlasLogEntryProc);
var
  mEntry: TAtlasAssistantsLogEntry;
begin
  if Assigned(AProc) and TrySelected(mEntry) then
  begin
    AProc(mEntry);
  end;
end;

procedure TAtlasAssistantsLogFrame.ListDblClick(Sender: TObject);
begin
  Run(FEvents.Open);
end;

procedure TAtlasAssistantsLogFrame.ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    Run(FEvents.Open);
    Key := 0;
  end;
end;

procedure TAtlasAssistantsLogFrame.ButtonClick(Sender: TObject);
begin
  case TAtlasLogButton((Sender as TButton).Tag) of
    TAtlasLogButton.Diff:
      Run(FEvents.Diff);
    TAtlasLogButton.Revert:
      Run(FEvents.Revert);
    TAtlasLogButton.Session:
      if Assigned(FEvents.Session) then
      begin
        FEvents.Session();
      end;
    TAtlasLogButton.Clear:
      if Assigned(FEvents.Clear) then
      begin
        FEvents.Clear();
      end;
  end;
end;

end.
