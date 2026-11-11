unit Atlas.UI.Settings.ServerPage;

// Seite „Atlas › Server“ unter Tools › Optionen › Drittanbieter (#227):
//   - Weitere Einstellungen des Servers für alle Projekte (%APPDATA%\Atlas\settings.json,
//     ohne die Werte der übrigen Reiter) und die des aktiven Projekts (atlas.json)
//     im Dialog bearbeiten; jede Einstellung hat genau einen Ort (#227).
//   - „Index-Cache löschen“ (#184).
// Baseline (#97) und Unterdrückungen je Regel (#147) stehen seit #1755 auf der
// Seite Prüfregeln im Abschnitt des Moduls Prüfregeln.
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
  Atlas.UI.Settings.Strings;

type
  /// <summary>Was die IDE-Schicht für die Seite liefert; nicht gesetzte Haken lassen ihren Knopf aus.</summary>
  TAtlasServerPageHooks = record
    EditGlobal: TProc;
    EditProject: TProc;
    ClearCache: TFunc<string>;
    Confirm: TFunc<string, Boolean>;
  end;

  TAtlasServerPage = class(TFrame)
  private
    FNextTop: Integer;
    FEditGlobal: TButton;
    FEditProject: TButton;
    FCacheInfo: TLabel;
    FCacheClear: TButton;
    FHooks: TAtlasServerPageHooks;
    function AddPanel(AHeight: Integer): TPanel;
    function AddTitle(const ACaption: string): TLabel;
    function AddButton(APanel: TPanel; const ACaption: string; ALeft: Integer; AClick: TNotifyEvent): TButton;
    function Confirmed(const AQuestion: string): Boolean;
    procedure EditGlobalClick(Sender: TObject);
    procedure EditProjectClick(Sender: TObject);
    procedure CacheClearClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Knöpfe nach den gesetzten Ereignissen freigeben.</summary>
    procedure Reload;
    property EditGlobal: TButton read FEditGlobal;
    property CacheInfo: TLabel read FCacheInfo;
    property CacheClear: TButton read FCacheClear;
    property OnEditGlobal: TProc read FHooks.EditGlobal write FHooks.EditGlobal;
    property OnEditProject: TProc read FHooks.EditProject write FHooks.EditProject;
    /// <summary>Index-Cache leeren; Ergebnis als Meldung unter dem Abschnitt.</summary>
    property OnClearCache: TFunc<string> read FHooks.ClearCache write FHooks.ClearCache;
    /// <summary>Rückfrage vor dem Löschen; Standard: Dialog mit Ja/Nein.</summary>
    property Confirm: TFunc<string, Boolean> read FHooks.Confirm write FHooks.Confirm;
  end;

implementation

const
  // Linker Rand des Knopfs für die Projekteinstellungen.
  cEditProjectLeft = 230;

{$R *.dfm}

{ TAtlasServerPage }

constructor TAtlasServerPage.Create(AOwner: TComponent);
var
  mPanel: TPanel;
begin
  inherited Create(AOwner);
  Name := 'AtlasServerPage';
  Width := ScaleValue(480);
  Height := ScaleValue(520);
  FNextTop := 100;
  AddTitle(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.ServerPageGlobalTitle));
  mPanel := AddPanel(32);
  FEditGlobal := AddButton(mPanel, TAtlasSettingsStrings.Text(TAtlasSettingsTextId.ServerPageGlobalEdit), 0,
    EditGlobalClick);
  FEditProject := AddButton(mPanel, TAtlasSettingsStrings.Text(TAtlasSettingsTextId.ServerPageProjectEdit),
    cEditProjectLeft,
    EditProjectClick);

  AddTitle(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.ServerPageCacheTitle));
  mPanel := AddPanel(32);
  FCacheClear := AddButton(mPanel, TAtlasSettingsStrings.Text(TAtlasSettingsTextId.ServerPageCacheClear), 0,
    CacheClearClick);
  mPanel := AddPanel(20);
  FCacheInfo := TLabel.Create(Self);
  FCacheInfo.Parent := mPanel;
  FCacheInfo.Left := 0;
  FCacheInfo.Top := FCacheInfo.ScaleValue(2);
  FCacheInfo.Font.Color := clGrayText;
  Reload;
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
  mPanel: TPanel;
begin
  mPanel := AddPanel(22);
  Result := TLabel.Create(Self);
  Result.Parent := mPanel;
  Result.Caption := ACaption;
  Result.Font.Style := [fsBold];
  Result.Left := 0;
  Result.Top := Result.ScaleValue(4);
end;

function TAtlasServerPage.AddButton(APanel: TPanel; const ACaption: string; ALeft: Integer;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := APanel;
  Result.Caption := ACaption;
  Result.Left := ALeft;
  Result.Top := Result.ScaleValue(3);
  Result.Width := Result.ScaleValue(220);
  Result.OnClick := AClick;
end;

procedure TAtlasServerPage.Reload;
begin
  FEditGlobal.Enabled := Assigned(FHooks.EditGlobal);
  FEditProject.Enabled := Assigned(FHooks.EditProject);
  FCacheClear.Enabled := Assigned(FHooks.ClearCache);
end;

function TAtlasServerPage.Confirmed(const AQuestion: string): Boolean;
begin
  if Assigned(FHooks.Confirm) then
  begin
    Result := FHooks.Confirm(AQuestion);
  end
  else
  begin
    Result := MessageDlg(AQuestion, mtConfirmation, [mbYes, mbNo], 0) = mrYes;
  end;
end;

procedure TAtlasServerPage.EditGlobalClick(Sender: TObject);
begin
  if Assigned(FHooks.EditGlobal) then
  begin
    FHooks.EditGlobal();
  end;
end;

procedure TAtlasServerPage.EditProjectClick(Sender: TObject);
begin
  if Assigned(FHooks.EditProject) then
  begin
    FHooks.EditProject();
  end;
end;

procedure TAtlasServerPage.CacheClearClick(Sender: TObject);
begin
  if Assigned(FHooks.ClearCache) and Confirmed(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.ServerPageCacheConfirm))
    then
  begin
    FCacheInfo.Caption := FHooks.ClearCache();
  end;
end;

end.
