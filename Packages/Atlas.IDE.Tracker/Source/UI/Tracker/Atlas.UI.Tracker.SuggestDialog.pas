unit Atlas.UI.Tracker.SuggestDialog;

// Dialog „Arbeitskopien vorschlagen“ (#1929, Mockup Runde 82 TP4), reine VCL:
//   Arbeitskopien vorschlagen – YouTrack · KASSE
//   Gefunden in … Häkchen setzen, dann „Übernehmen“.
//   [x] D:\SVN\Kasse\trunk          svn  Arbeitskopie von Kasse.groupproj
//   [x] D:\SVN\Basis\Packages\trunk svn  svn:externals in D:\SVN\Kasse\trunk
//   [ ] D:\Kunden\Kasse\Fremd\Lib   git  Projekt der Gruppe: Kasse.groupproj
//                                      [Übernehmen] [Abbrechen]
// Die Suche startet die IDE-Schicht im Hintergrund; ihr Ergebnis kommt über
// Fill, solange der Dialog offen ist (IAtlasTrackerPathsAlive). Ohne Fund
// steht dort „Nichts gefunden – Ordner selbst wählen …“; der Knopf schließt
// mit Browse, „Ordner hinzufügen …“ übernimmt dann.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Atlas.Core.Tracker.PathSuggestions;

type
  /// <summary>Lebt der Empfänger noch? Eine Arbeit im Hintergrund hält die Marke, nicht den Empfänger.</summary>
  IAtlasTrackerPathsAlive = interface
    ['{5B7D2E91-0C4A-4F38-9E6B-A12C3D4E5F60}']
    function Alive: Boolean;
    procedure Release;
  end;

  TAtlasTrackerPathsAlive = class(TInterfacedObject, IAtlasTrackerPathsAlive)
  private
    FAlive: Boolean;
  public
    constructor Create;
    function Alive: Boolean;
    procedure Release;
  end;

  /// <summary>Ergebnis der Suche an den Dialog.</summary>
  TAtlasTrackerSuggestFill = TProc<TArray<TAtlasTrackerPathSuggestion>>;
  /// <summary>Suche starten; AFill danach im Hauptthread.</summary>
  TAtlasTrackerSuggestStart = reference to procedure(const AFill: TAtlasTrackerSuggestFill);

{$SCOPEDENUMS ON}
  TAtlasTrackerSuggestAnswer = (Cancel, Apply, Browse);
{$SCOPEDENUMS OFF}

  TAtlasTrackerSuggestDialog = class(TForm)
  public const
    cDialogWidth = 720;
    cListHeight = 220;
    cPathWidth = 300;
    cKindWidth = 50;
    cWhyWidth = 320;
  private
    FIntro: TLabel;
    FList: TListView;
    FNote: TLabel;
    FBrowse: TButton;
    FApply: TButton;
    FCancel: TButton;
    FItems: TArray<TAtlasTrackerPathSuggestion>;
    function AddButton(AParent: TWinControl; const ACaption: string): TButton;
    procedure AddButtons;
    procedure AddColumn(const ACaption: string; AWidth: Integer);
  public
    constructor CreateDialog(AOwner: TComponent; const ATitle: string);
    /// <summary>Funde zeigen (ersetzt die Liste); ohne Fund den Hinweis mit „Ordner selbst wählen …“.</summary>
    procedure Fill(const AItems: TArray<TAtlasTrackerPathSuggestion>);
    /// <summary>Angehakte Ordner in Reihenfolge der Liste.</summary>
    function CheckedFolders: TArray<string>;
    /// <summary>Text der Spalte „Warum vorgeschlagen“.</summary>
    class function WhyText(const AItem: TAtlasTrackerPathSuggestion): string; static;
    /// <summary>Modal zeigen; AStart sucht im Hintergrund. Apply mit den angehakten Ordnern (mindestens einer),
    /// Browse nach „Ordner selbst wählen …“.</summary>
    class function Execute(const ATitle: string; const AStart: TAtlasTrackerSuggestStart;
      out APaths: TArray<string>): TAtlasTrackerSuggestAnswer; static;
    property List: TListView read FList;
    property Note: TLabel read FNote;
    property BrowseButton: TButton read FBrowse;
    property ApplyButton: TButton read FApply;
  end;

implementation

uses
  Atlas.UI.Tracker.Strings;

const
  cGap = 10;
  cBrowseResult = mrRetry;

{ TAtlasTrackerPathsAlive }

constructor TAtlasTrackerPathsAlive.Create;
begin
  inherited Create;
  FAlive := True;
end;

function TAtlasTrackerPathsAlive.Alive: Boolean;
begin
  Result := FAlive;
end;

procedure TAtlasTrackerPathsAlive.Release;
begin
  FAlive := False;
end;

{ TAtlasTrackerSuggestDialog }

constructor TAtlasTrackerSuggestDialog.CreateDialog(AOwner: TComponent; const ATitle: string);
begin
  inherited CreateNew(AOwner);
  Caption := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.SuggestTitle, [ATitle]);
  BorderStyle := bsDialog;
  Position := poMainFormCenter;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  ClientWidth := ScaleValue(cDialogWidth);

  FIntro := TLabel.Create(Self);
  FIntro.Parent := Self;
  FIntro.Align := alTop;
  FIntro.AlignWithMargins := True;
  FIntro.Margins.SetBounds(cGap, cGap, cGap, 0);
  FIntro.WordWrap := True;
  FIntro.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SuggestIntro);

  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alTop;
  FList.AlignWithMargins := True;
  FList.Margins.SetBounds(cGap, cGap, cGap, 0);
  FList.Top := FIntro.Top + FIntro.Height + 1;
  FList.Height := ScaleValue(cListHeight);
  FList.ViewStyle := vsReport;
  FList.Checkboxes := True;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  AddColumn(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SuggestColumnPath), cPathWidth);
  AddColumn(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SuggestColumnKind), cKindWidth);
  AddColumn(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SuggestColumnWhy), cWhyWidth);

  FNote := TLabel.Create(Self);
  FNote.Parent := Self;
  FNote.Align := alTop;
  FNote.AlignWithMargins := True;
  FNote.Margins.SetBounds(cGap, cGap div 2, cGap, 0);
  FNote.Top := FList.Top + FList.Height + 1;
  FNote.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SuggestSearching);

  AddButtons;
end;

procedure TAtlasTrackerSuggestDialog.AddColumn(const ACaption: string; AWidth: Integer);
var
  mColumn: TListColumn;
begin
  mColumn := FList.Columns.Add;
  mColumn.Caption := ACaption;
  mColumn.Width := ScaleValue(AWidth);
end;

function TAtlasTrackerSuggestDialog.AddButton(AParent: TWinControl; const ACaption: string): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.Width := Canvas.TextWidth(ACaption) + ScaleValue(32);
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(0, 0, cGap, 0);
end;

procedure TAtlasTrackerSuggestDialog.AddButtons;
var
  mButtons: TFlowPanel;
begin
  mButtons := TFlowPanel.Create(Self);
  mButtons.Parent := Self;
  mButtons.Align := alTop;
  mButtons.AutoSize := True;
  mButtons.BevelOuter := bvNone;
  mButtons.AlignWithMargins := True;
  mButtons.Margins.SetBounds(cGap, cGap, cGap, cGap);
  mButtons.Top := FNote.Top + FNote.Height + 1;
  Canvas.Font := Font;
  FBrowse := AddButton(mButtons, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SuggestNothing));
  FBrowse.ModalResult := cBrowseResult;
  FBrowse.Visible := False;
  FApply := AddButton(mButtons, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SuggestApply));
  FApply.Default := True;
  FApply.ModalResult := mrOk;
  FApply.Enabled := False;
  FCancel := AddButton(mButtons, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDialogCancel));
  FCancel.Cancel := True;
  FCancel.ModalResult := mrCancel;
  ClientHeight := mButtons.Top + mButtons.Height + cGap;
end;

class function TAtlasTrackerSuggestDialog.WhyText(const AItem: TAtlasTrackerPathSuggestion): string;
const
  cIds: array[TAtlasTrackerPathReason] of TAtlasTrackerTextId = (TAtlasTrackerTextId.SuggestWhyProject,
    TAtlasTrackerTextId.SuggestWhyExternal, TAtlasTrackerTextId.SuggestWhySubmodule,
    TAtlasTrackerTextId.SuggestWhyGroup, TAtlasTrackerTextId.SuggestWhyRemote,
    TAtlasTrackerTextId.SuggestWhyWorktree);
begin
  Result := TAtlasTrackerStrings.Fmt(cIds[AItem.Reason], [AItem.Detail]);
end;

procedure TAtlasTrackerSuggestDialog.Fill(const AItems: TArray<TAtlasTrackerPathSuggestion>);
var
  mItem: TAtlasTrackerPathSuggestion;
  mRow: TListItem;
begin
  FItems := Copy(AItems);
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for mItem in FItems do
    begin
      mRow := FList.Items.Add;
      mRow.Caption := mItem.Folder;
      mRow.SubItems.Add(mItem.Kind);
      mRow.SubItems.Add(WhyText(mItem));
      mRow.Checked := mItem.Checked;
    end;
  finally
    FList.Items.EndUpdate;
  end;
  FNote.Caption := '';
  FBrowse.Visible := Length(FItems) = 0;
  FApply.Enabled := Length(FItems) > 0;
end;

function TAtlasTrackerSuggestDialog.CheckedFolders: TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to FList.Items.Count - 1 do
  begin
    if FList.Items[mIndex].Checked then
    begin
      Result := Result + [FList.Items[mIndex].Caption];
    end;
  end;
end;

class function TAtlasTrackerSuggestDialog.Execute(const ATitle: string; const AStart: TAtlasTrackerSuggestStart;
  out APaths: TArray<string>): TAtlasTrackerSuggestAnswer;
var
  mDialog: TAtlasTrackerSuggestDialog;
  mAlive: IAtlasTrackerPathsAlive;
  mModal: Integer;
begin
  APaths := nil;
  mAlive := TAtlasTrackerPathsAlive.Create;
  mDialog := TAtlasTrackerSuggestDialog.CreateDialog(nil, ATitle);
  try
    if Assigned(AStart) then
    begin
      AStart(
        procedure(AItems: TArray<TAtlasTrackerPathSuggestion>)
        begin
          // Dialog schon zu: Das Ergebnis gilt nicht mehr.
          if mAlive.Alive then
          begin
            mDialog.Fill(AItems);
          end;
        end);
    end;
    mModal := mDialog.ShowModal;
    APaths := mDialog.CheckedFolders;
    Result := TAtlasTrackerSuggestAnswer.Cancel;
    if mModal = cBrowseResult then
    begin
      Result := TAtlasTrackerSuggestAnswer.Browse;
    end
    else if (mModal = mrOk) and (Length(APaths) > 0) then
    begin
      Result := TAtlasTrackerSuggestAnswer.Apply;
    end;
  finally
    mAlive.Release;
    mDialog.Free;
  end;
end;

end.
