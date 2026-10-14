unit Atlas.UI.Settings.ServerPage;

// Seite „Atlas › Server“ unter Tools › Optionen › Drittanbieter (#227):
//   - Einstellungen des Servers für alle Projekte (%APPDATA%\Atlas\settings.json)
//     und die des aktiven Projekts (atlas.json) im Dialog bearbeiten.
//   - Baseline (#97): Anzahl der Treffer in atlas-baseline.json, „Baseline neu
//     erzeugen“ und „Baseline löschen“.
//   - Unterdrückungen „lsp-ignore“ je Regel (#147, nur Anzeige).
//   - „Index-Cache löschen“ (#184).
// Reine VCL; die Seite kennt weder Server noch Dateien. Die IDE-Schicht liefert
// Texte und führt die Aktionen aus (AtlasServer.exe als Prozess bzw. Dialog).

interface

uses
  System.SysUtils,
  System.Classes,
  System.UITypes,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Forms,
  Vcl.Dialogs,
  Atlas.UI.Strings;

type
  TAtlasServerPage = class(TFrame)
  private
    FNextTop: Integer;
    FEditGlobal: TButton;
    FEditProject: TButton;
    FBaselineInfo: TLabel;
    FBaselineUpdate: TButton;
    FBaselineDelete: TButton;
    FSuppressions: TListBox;
    FSuppressionsRefresh: TButton;
    FCacheInfo: TLabel;
    FCacheClear: TButton;
    FOnEditGlobal: TProc;
    FOnEditProject: TProc;
    FOnBaselineInfo: TFunc<string>;
    FOnBaselineUpdate: TFunc<string>;
    FOnBaselineDelete: TFunc<string>;
    FOnSuppressions: TFunc<TArray<string>>;
    FOnClearCache: TFunc<string>;
    FConfirm: TFunc<string, Boolean>;
    function AddPanel(AHeight: Integer): TPanel;
    function AddTitle(const ACaption: string): TLabel;
    function AddButton(APanel: TPanel; const ACaption: string; ALeft: Integer; AClick: TNotifyEvent): TButton;
    function Confirmed(const AQuestion: string): Boolean;
    procedure EditGlobalClick(Sender: TObject);
    procedure EditProjectClick(Sender: TObject);
    procedure BaselineUpdateClick(Sender: TObject);
    procedure BaselineDeleteClick(Sender: TObject);
    procedure SuppressionsClick(Sender: TObject);
    procedure CacheClearClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Knöpfe nach den gesetzten Ereignissen freigeben, Anzahl der Baseline neu lesen.</summary>
    procedure Refresh;
    property EditGlobal: TButton read FEditGlobal;
    property EditProject: TButton read FEditProject;
    property BaselineInfo: TLabel read FBaselineInfo;
    property BaselineUpdate: TButton read FBaselineUpdate;
    property BaselineDelete: TButton read FBaselineDelete;
    property Suppressions: TListBox read FSuppressions;
    property SuppressionsRefresh: TButton read FSuppressionsRefresh;
    property CacheInfo: TLabel read FCacheInfo;
    property CacheClear: TButton read FCacheClear;
    property OnEditGlobal: TProc read FOnEditGlobal write FOnEditGlobal;
    property OnEditProject: TProc read FOnEditProject write FOnEditProject;
    /// <summary>Text zur Baseline des aktiven Projekts.</summary>
    property OnBaselineInfo: TFunc<string> read FOnBaselineInfo write FOnBaselineInfo;
    /// <summary>Aktionen; Ergebnis als Meldung unter dem Abschnitt.</summary>
    property OnBaselineUpdate: TFunc<string> read FOnBaselineUpdate write FOnBaselineUpdate;
    property OnBaselineDelete: TFunc<string> read FOnBaselineDelete write FOnBaselineDelete;
    property OnSuppressions: TFunc<TArray<string>> read FOnSuppressions write FOnSuppressions;
    property OnClearCache: TFunc<string> read FOnClearCache write FOnClearCache;
    /// <summary>Rückfrage vor dem Löschen; Standard: Dialog mit Ja/Nein.</summary>
    property Confirm: TFunc<string, Boolean> read FConfirm write FConfirm;
  end;

implementation

{$R *.dfm}

{ TAtlasServerPage }

constructor TAtlasServerPage.Create(AOwner: TComponent);
var
  Panel: TPanel;
begin
  inherited Create(AOwner);
  Name := 'AtlasServerPage';
  Width := 480;
  Height := 520;
  FNextTop := 100;
  AddTitle(TAtlasStrings.Text(TAtlasTextId.ServerPageGlobalTitle));
  Panel := AddPanel(32);
  FEditGlobal := AddButton(Panel, TAtlasStrings.Text(TAtlasTextId.ServerPageGlobalEdit), 0, EditGlobalClick);
  FEditProject := AddButton(Panel, TAtlasStrings.Text(TAtlasTextId.ServerPageProjectEdit), 230, EditProjectClick);

  AddTitle(TAtlasStrings.Text(TAtlasTextId.ServerPageBaselineTitle));
  Panel := AddPanel(20);
  FBaselineInfo := TLabel.Create(Self);
  FBaselineInfo.Parent := Panel;
  FBaselineInfo.Left := 0;
  FBaselineInfo.Top := 2;
  FBaselineInfo.Font.Color := clGrayText;
  Panel := AddPanel(32);
  FBaselineUpdate := AddButton(Panel, TAtlasStrings.Text(TAtlasTextId.ServerPageBaselineUpdate), 0,
    BaselineUpdateClick);
  FBaselineDelete := AddButton(Panel, TAtlasStrings.Text(TAtlasTextId.ServerPageBaselineDelete), 230,
    BaselineDeleteClick);

  AddTitle(TAtlasStrings.Text(TAtlasTextId.ServerPageSuppressionsTitle));
  Panel := AddPanel(110);
  FSuppressions := TListBox.Create(Self);
  FSuppressions.Parent := Panel;
  FSuppressions.Align := alClient;
  Panel := AddPanel(32);
  FSuppressionsRefresh := AddButton(Panel, TAtlasStrings.Text(TAtlasTextId.ServerPageSuppressionsRefresh), 0,
    SuppressionsClick);

  AddTitle(TAtlasStrings.Text(TAtlasTextId.ServerPageCacheTitle));
  Panel := AddPanel(32);
  FCacheClear := AddButton(Panel, TAtlasStrings.Text(TAtlasTextId.ServerPageCacheClear), 0, CacheClearClick);
  Panel := AddPanel(20);
  FCacheInfo := TLabel.Create(Self);
  FCacheInfo.Parent := Panel;
  FCacheInfo.Left := 0;
  FCacheInfo.Top := 2;
  FCacheInfo.Font.Color := clGrayText;
  Refresh;
end;

function TAtlasServerPage.AddPanel(AHeight: Integer): TPanel;
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

function TAtlasServerPage.AddTitle(const ACaption: string): TLabel;
var
  Panel: TPanel;
begin
  Panel := AddPanel(22);
  Result := TLabel.Create(Self);
  Result.Parent := Panel;
  Result.Caption := ACaption;
  Result.Font.Style := [fsBold];
  Result.Left := 0;
  Result.Top := 4;
end;

function TAtlasServerPage.AddButton(APanel: TPanel; const ACaption: string; ALeft: Integer;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := APanel;
  Result.Caption := ACaption;
  Result.Left := ALeft;
  Result.Top := 3;
  Result.Width := 220;
  Result.OnClick := AClick;
end;

procedure TAtlasServerPage.Refresh;
begin
  FEditGlobal.Enabled := Assigned(FOnEditGlobal);
  FEditProject.Enabled := Assigned(FOnEditProject);
  FBaselineUpdate.Enabled := Assigned(FOnBaselineUpdate);
  FBaselineDelete.Enabled := Assigned(FOnBaselineDelete);
  FSuppressionsRefresh.Enabled := Assigned(FOnSuppressions);
  FCacheClear.Enabled := Assigned(FOnClearCache);
  if Assigned(FOnBaselineInfo) then
    FBaselineInfo.Caption := FOnBaselineInfo()
  else
    FBaselineInfo.Caption := '';
end;

function TAtlasServerPage.Confirmed(const AQuestion: string): Boolean;
begin
  if Assigned(FConfirm) then
    Result := FConfirm(AQuestion)
  else
    Result := MessageDlg(AQuestion, mtConfirmation, [mbYes, mbNo], 0) = mrYes;
end;

procedure TAtlasServerPage.EditGlobalClick(Sender: TObject);
begin
  if Assigned(FOnEditGlobal) then
    FOnEditGlobal();
end;

procedure TAtlasServerPage.EditProjectClick(Sender: TObject);
begin
  if Assigned(FOnEditProject) then
    FOnEditProject();
end;

procedure TAtlasServerPage.BaselineUpdateClick(Sender: TObject);
begin
  if Assigned(FOnBaselineUpdate) then
    FBaselineInfo.Caption := FOnBaselineUpdate();
end;

procedure TAtlasServerPage.BaselineDeleteClick(Sender: TObject);
begin
  if Assigned(FOnBaselineDelete) and
    Confirmed(TAtlasStrings.Text(TAtlasTextId.ServerPageBaselineDeleteConfirm)) then
    FBaselineInfo.Caption := FOnBaselineDelete();
end;

procedure TAtlasServerPage.SuppressionsClick(Sender: TObject);
var
  Line: string;
begin
  if not Assigned(FOnSuppressions) then
    Exit;
  FSuppressions.Items.BeginUpdate;
  try
    FSuppressions.Items.Clear;
    for Line in FOnSuppressions() do
      FSuppressions.Items.Add(Line);
  finally
    FSuppressions.Items.EndUpdate;
  end;
end;

procedure TAtlasServerPage.CacheClearClick(Sender: TObject);
begin
  if Assigned(FOnClearCache) and Confirmed(TAtlasStrings.Text(TAtlasTextId.ServerPageCacheConfirm)) then
    FCacheInfo.Caption := FOnClearCache();
end;

end.
