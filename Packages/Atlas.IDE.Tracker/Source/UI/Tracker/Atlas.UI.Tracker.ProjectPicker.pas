unit Atlas.UI.Tracker.ProjectPicker;

// Klappliste „Tracker-Projekt“ in „Meine Issues“ (#1927, Mockup Runde 82 TP1),
// reine VCL: links in der Zeile über der Liste „Projekt: Automatisch ▾“.
//   ● Automatisch – nach dem Delphi-Projekt (Kasse)
//     YouTrack · KASSE
//     GitHub · xKnockOut/Atlas-IDE-Expert
//     Alle Tracker-Projekte                 (#1928, issues.allProjects)
//   ─────────────
//     Tracker-Projekte bearbeiten …
// Einträge und Wahl kommen aus der Ansicht (TAtlasIssuesView); die Wahl geht
// über AOnSelect an die Quelle. Mit issues.projectPicker aus bzw. ohne Zeilen
// in issues.projects bleibt die Klappliste weg.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Menus,
  Vcl.StdCtrls,
  Atlas.Core.Tracker.MyIssues;

type
  TAtlasTrackerProjectPicker = class
  private
    FLabel: TLabel;
    FMenu: TPopupMenu;
    FView: TAtlasIssuesView;
    // Schlüssel je Eintrag (Tag = Index).
    FKeys: TArray<string>;
    FOnSelect: TProc<string>;
    FOnEdit: TProc;
    procedure LabelClick(Sender: TObject);
    procedure ItemClick(Sender: TObject);
    procedure EditClick(Sender: TObject);
    procedure AddItem(const ACaption, AKey: string; AChecked: Boolean);
  public
    /// <summary>Beschriftung links in ABar; AOnSelect bekommt den Schlüssel der Wahl, AOnEdit „bearbeiten …“.
    /// </summary>
    constructor Create(AOwner: TComponent; ABar: TWinControl; const AOnSelect: TProc<string>; const AOnEdit: TProc);
    /// <summary>Sichtbarkeit und Beschriftung nach AView; AMeasure: die Beschriftung hat ein Fenster.</summary>
    procedure Update(const AView: TAtlasIssuesView; AMeasure: Boolean);
    /// <summary>Klappliste füllen (auch für Tests).</summary>
    procedure Fill;
    function Visible: Boolean;
    /// <summary>Klappliste sichtbar: eingeschaltet und mindestens ein Tracker-Projekt.</summary>
    class function Shows(const AView: TAtlasIssuesView): Boolean; static;
    /// <summary>„Projekt: …“ ohne Pfeil.</summary>
    class function CaptionOf(const AView: TAtlasIssuesView): string; static;
    property ProjectLabel: TLabel read FLabel;
    property Menu: TPopupMenu read FMenu;
  end;

implementation

uses
  System.Types,
  Vcl.Graphics,
  Atlas.Core.Tracker.Projects,
  Atlas.UI.Tracker.Strings;

const
  cMenuLine = '-';
  cDropMark = ' ' + #$25BE;
  cMargin = 4;

{ TAtlasTrackerProjectPicker }

constructor TAtlasTrackerProjectPicker.Create(AOwner: TComponent; ABar: TWinControl; const AOnSelect: TProc<string>;
  const AOnEdit: TProc);
begin
  inherited Create;
  FOnSelect := AOnSelect;
  FOnEdit := AOnEdit;
  FMenu := TPopupMenu.Create(AOwner);
  FLabel := TLabel.Create(AOwner);
  FLabel.Parent := ABar;
  FLabel.Align := alLeft;
  FLabel.AlignWithMargins := True;
  FLabel.Margins.SetBounds(cMargin, cMargin, cMargin, 0);
  FLabel.Cursor := crHandPoint;
  FLabel.ShowHint := True;
  FLabel.Hint := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuesProjectHint);
  FLabel.Font.Color := clHotLight;
  FLabel.Visible := False;
  FLabel.OnClick := LabelClick;
end;

class function TAtlasTrackerProjectPicker.Shows(const AView: TAtlasIssuesView): Boolean;
begin
  Result := AView.ProjectPicker and (Length(AView.ProjectChoices) > 0);
end;

class function TAtlasTrackerProjectPicker.CaptionOf(const AView: TAtlasIssuesView): string;
var
  mName: string;
  mIndex: Integer;
begin
  mName := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuesProjectAuto);
  mIndex := TAtlasTrackerProjects.IndexOfChoice(AView.ProjectChoices, AView.ProjectKey);
  if mIndex >= 0 then
  begin
    mName := AView.ProjectChoices[mIndex].Caption;
  end
  else if AView.ProjectKey = TAtlasTrackerProjects.cAllKey then
  begin
    mName := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuesProjectAll);
  end;
  Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssuesProjectLabel, [mName]);
end;

function TAtlasTrackerProjectPicker.Visible: Boolean;
begin
  Result := FLabel.Visible;
end;

procedure TAtlasTrackerProjectPicker.Update(const AView: TAtlasIssuesView; AMeasure: Boolean);
begin
  FView := AView;
  FLabel.Visible := Shows(AView);
  if FLabel.Visible and AMeasure then
  begin
    FLabel.Caption := CaptionOf(AView) + cDropMark;
  end;
end;

procedure TAtlasTrackerProjectPicker.AddItem(const ACaption, AKey: string; AChecked: Boolean);
var
  mItem: TMenuItem;
begin
  mItem := TMenuItem.Create(FMenu);
  mItem.Caption := ACaption;
  mItem.RadioItem := True;
  mItem.Checked := AChecked;
  mItem.Tag := Length(FKeys);
  FKeys := FKeys + [AKey];
  mItem.OnClick := ItemClick;
  FMenu.Items.Add(mItem);
end;

procedure TAtlasTrackerProjectPicker.Fill;
var
  mChoice: TAtlasTrackerChoice;
  mAuto: string;
  mItem: TMenuItem;
begin
  FMenu.Items.Clear;
  FKeys := nil;
  mAuto := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuesProjectAutoNone);
  if FView.AutomaticName <> '' then
  begin
    mAuto := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssuesProjectAutoItem, [FView.AutomaticName]);
  end;
  AddItem(mAuto, '', FView.ProjectKey = '');
  for mChoice in FView.ProjectChoices do
  begin
    AddItem(mChoice.Caption, mChoice.Key, SameText(mChoice.Key, FView.ProjectKey));
  end;
  if FView.AllProjects and (Length(FView.ProjectChoices) > 1) then
  begin
    AddItem(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuesProjectAll), TAtlasTrackerProjects.cAllKey,
      FView.ProjectKey = TAtlasTrackerProjects.cAllKey);
  end;
  mItem := TMenuItem.Create(FMenu);
  mItem.Caption := cMenuLine;
  FMenu.Items.Add(mItem);
  mItem := TMenuItem.Create(FMenu);
  mItem.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuesProjectEdit);
  mItem.OnClick := EditClick;
  FMenu.Items.Add(mItem);
end;

procedure TAtlasTrackerProjectPicker.LabelClick(Sender: TObject);
var
  mPoint: TPoint;
begin
  Fill;
  mPoint := FLabel.ClientToScreen(Point(0, FLabel.Height));
  FMenu.Popup(mPoint.X, mPoint.Y);
end;

procedure TAtlasTrackerProjectPicker.ItemClick(Sender: TObject);
begin
  if Assigned(FOnSelect) and (TMenuItem(Sender).Tag >= 0) and (TMenuItem(Sender).Tag <= High(FKeys)) then
  begin
    FOnSelect(FKeys[TMenuItem(Sender).Tag]);
  end;
end;

procedure TAtlasTrackerProjectPicker.EditClick(Sender: TObject);
begin
  if Assigned(FOnEdit) then
  begin
    FOnEdit();
  end;
end;

end.
