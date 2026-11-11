unit Atlas.UI.Rules.SettingsSection;

// Abschnitte des Moduls Prüfregeln im Optionsdialog (#1456; vorher in den Teilen
// „Prüfregeln“ und „Editor“ von Base). Fenster „Atlas-Prüfung“, Prüfen beim Speichern und deren Einstellungen
// bleiben in Base.
// - „Prüfregeln“: Modulschalter, Sammelkorrektur im Kontextmenü des Fensters (#1352), der Weg zu den Regeln (sie
//   stehen in den Dialogen der Einstellungsdateien, Projekt und global), Profile, Stand der Baseline mit „neu
//   erzeugen“ und „löschen“ und die Unterdrückungen je Regel (#909, #97, #147; seit #1755 hier statt in Base und
//   auf der Seite „Atlas.Server“). Was dafür Dateien oder den Server braucht, kommt über Hooks
//   (Atlas.IDE.Rules.Settings).
// - „Editor“: Basislinie aktualisieren und DFM-Eigenschaftsregeln anwenden.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Atlas.UI.Settings.Section;

type
  /// <summary>Was der Abschnitt „Prüfregeln“ von der IDE-Schicht braucht; nicht gesetzte Haken lassen ihren Knopf
  /// gesperrt.</summary>
  TAtlasRulesChecksHooks = record
    /// <summary>„Projekt-Prüfregeln bearbeiten …“ bzw. „Globale Prüfregeln bearbeiten …“.</summary>
    OpenProject: TProc;
    OpenGlobal: TProc;
    /// <summary>Stand der Baseline des aktiven Projekts als Text; neu erzeugen und löschen liefern danach den
    /// Stand oder die Meldung.</summary>
    BaselineInfo: TFunc<string>;
    BaselineUpdate: TFunc<string>;
    BaselineDelete: TFunc<string>;
    /// <summary>Unterdrückungen je Regel als Zeilen.</summary>
    Suppressions: TFunc<TArray<string>>;
    /// <summary>Rückfrage vor dem Löschen; nil = Dialog mit Ja/Nein.</summary>
    Confirm: TFunc<string, Boolean>;
  end;

  TAtlasRulesChecksSection = class(TAtlasSettingsSection)
  private
    FHooks: TAtlasRulesChecksHooks;
    /// <summary>Besitzer der eigenen Elemente; die Zeilen gehören der Seite.</summary>
    FControls: TComponent;
    /// <summary>Modulschalter: Die eigenen Zeilen stehen in seinem Rahmen im Hauptknoten der Seite.</summary>
    FSwitch: TCheckBox;
    FRulesProject: TButton;
    FRulesGlobal: TButton;
    FBaselineInfo: TLabel;
    FBaselineUpdate: TButton;
    FBaselineDelete: TButton;
    FSuppressions: TListBox;
    FSuppressionsRefresh: TButton;
    /// <summary>Zeile ohne eigenen Schlüssel im Rahmen des Modulschalters.</summary>
    function AddRow(AHeight: Integer): TWinControl;
    function AddButton(ARow: TWinControl; const ACaption: string; ALeft: Integer; AClick: TNotifyEvent): TButton;
    procedure AddRulesLinks;
    procedure AddBaseline;
    procedure AddSuppressions;
    function Confirmed(const AQuestion: string): Boolean;
    procedure RulesLinkClick(Sender: TObject);
    procedure BaselineClick(Sender: TObject);
    procedure SuppressionsClick(Sender: TObject);
  protected
    procedure BuildRows; override;
  public
    function OwnerId: string; override;
    function AreaId: string; override;
    destructor Destroy; override;
    procedure Close; override;
    property Hooks: TAtlasRulesChecksHooks read FHooks write FHooks;
    property RulesProjectButton: TButton read FRulesProject;
    property RulesGlobalButton: TButton read FRulesGlobal;
    property BaselineInfoLabel: TLabel read FBaselineInfo;
    property BaselineUpdateButton: TButton read FBaselineUpdate;
    property BaselineDeleteButton: TButton read FBaselineDelete;
    property SuppressionsList: TListBox read FSuppressions;
    property SuppressionsRefreshButton: TButton read FSuppressionsRefresh;
  end;

  TAtlasRulesEditorSection = class(TAtlasSettingsSection)
  protected
    procedure BuildRows; override;
  public
    function OwnerId: string; override;
    function AreaId: string; override;
  end;

const
  cRulesSettingsOwner = 'atlas.ruleChecks';

implementation

uses
  System.UITypes,
  Vcl.Dialogs,
  Vcl.Graphics,
  Atlas.UI.Rules.Strings;

const
  cButtonWidth = 210;
  cButtonGap = 216;
  cRowHeight = 28;

{ TAtlasRulesChecksSection }

function TAtlasRulesChecksSection.OwnerId: string;
begin
  Result := cRulesSettingsOwner;
end;

function TAtlasRulesChecksSection.AreaId: string;
begin
  // Seite (x-page) im Schema, kein angezeigter Text.
  Result := 'Prüfregeln'; // german-ok
end;

procedure TAtlasRulesChecksSection.BuildRows;
begin
  // Erst der Modulschalter und die Zeilen in seinem Rahmen (Hauptknoten), dann die Sammelkorrektur (Unterpunkt
  // „Prüffenster“): Zeilen ohne Schlüssel stehen sonst auf dem Unterpunkt der Zeile davor.
  FControls := TComponent.Create(nil);
  FSwitch := ModuleSwitch('ruleChecks.enabled');
  AddRulesLinks;
  AddBaseline;
  AddSuppressions;
  Switch('fix.bulk', TAtlasRulesStrings.Text(TAtlasRulesTextId.SettingsFixBulk));
end;

function TAtlasRulesChecksSection.AddRow(AHeight: Integer): TWinControl;
begin
  Result := Host.AddRow(AHeight, nil);
  Host.Attach(Result, FSwitch);
end;

function TAtlasRulesChecksSection.AddButton(ARow: TWinControl; const ACaption: string; ALeft: Integer;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(FControls);
  Result.Parent := ARow;
  Result.Caption := ACaption;
  Result.SetBounds(ALeft, 1, cButtonWidth, 25);
  Result.OnClick := AClick;
end;

procedure TAtlasRulesChecksSection.AddRulesLinks;
var
  mRow: TWinControl;
begin
  // Die Regeln stehen in atlas.json des Projekts und in settings.json („Weitere globale Einstellungen“), mit
  // einem Knoten je Gruppe; hier nur der Weg dorthin.
  Host.AddHint(TAtlasRulesStrings.Text(TAtlasRulesTextId.RulesGlobalNote), 34);
  mRow := AddRow(cRowHeight);
  FRulesProject := AddButton(mRow, TAtlasRulesStrings.Text(TAtlasRulesTextId.RulesProjectButton), 0, RulesLinkClick);
  FRulesGlobal := AddButton(mRow, TAtlasRulesStrings.Text(TAtlasRulesTextId.RulesGlobalButton), cButtonGap,
    RulesLinkClick);
  FRulesProject.Enabled := Assigned(FHooks.OpenProject);
  FRulesGlobal.Enabled := Assigned(FHooks.OpenGlobal);
end;

procedure TAtlasRulesChecksSection.AddBaseline;
var
  mRow: TWinControl;
  mTitle: TLabel;
begin
  // Profile gelten je Projekt (atlas.json), die Baseline je Projekt.
  Title(TAtlasRulesStrings.Text(TAtlasRulesTextId.RulesProfilesNode));
  Host.AddHint(TAtlasRulesStrings.Text(TAtlasRulesTextId.RulesProfilesText), 34);
  mRow := AddRow(20);
  mTitle := TLabel.Create(FControls);
  mTitle.Parent := mRow;
  mTitle.SetBounds(0, 2, 400, 16);
  mTitle.ShowAccelChar := False;
  mTitle.Font.Style := [TFontStyle.fsBold];
  mTitle.Caption := TAtlasRulesStrings.Text(TAtlasRulesTextId.ServerPageBaselineTitle);
  mRow := AddRow(cRowHeight);
  FBaselineInfo := TLabel.Create(FControls);
  FBaselineInfo.Parent := mRow;
  FBaselineInfo.SetBounds(0, 6, 400, 16);
  FBaselineInfo.ShowAccelChar := False;
  FBaselineInfo.Caption := TAtlasRulesStrings.Text(TAtlasRulesTextId.ServerPageBaselineNone);
  if Assigned(FHooks.BaselineInfo) then
  begin
    FBaselineInfo.Caption := FHooks.BaselineInfo();
  end;
  mRow := AddRow(cRowHeight);
  FBaselineUpdate := AddButton(mRow, TAtlasRulesStrings.Text(TAtlasRulesTextId.ServerPageBaselineUpdate), 0,
    BaselineClick);
  FBaselineDelete := AddButton(mRow, TAtlasRulesStrings.Text(TAtlasRulesTextId.ServerPageBaselineDelete), cButtonGap,
    BaselineClick);
  FBaselineUpdate.Enabled := Assigned(FHooks.BaselineUpdate);
  FBaselineDelete.Enabled := Assigned(FHooks.BaselineDelete);
end;

procedure TAtlasRulesChecksSection.AddSuppressions;
var
  mRow: TWinControl;
begin
  // Unterdrückungen „lsp-ignore“ je Regel (#147, nur Anzeige); gefüllt erst auf Klick (startet AtlasServer.exe).
  Title(TAtlasRulesStrings.Text(TAtlasRulesTextId.ServerPageSuppressionsTitle));
  mRow := AddRow(110);
  FSuppressions := TListBox.Create(FControls);
  FSuppressions.Parent := mRow;
  FSuppressions.Align := alClient;
  mRow := AddRow(cRowHeight);
  FSuppressionsRefresh := AddButton(mRow, TAtlasRulesStrings.Text(TAtlasRulesTextId.ServerPageSuppressionsRefresh), 0,
    SuppressionsClick);
  FSuppressionsRefresh.Enabled := Assigned(FHooks.Suppressions);
end;

function TAtlasRulesChecksSection.Confirmed(const AQuestion: string): Boolean;
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

procedure TAtlasRulesChecksSection.RulesLinkClick(Sender: TObject);
var
  mOpen: TProc;
begin
  mOpen := FHooks.OpenGlobal;
  if Sender = FRulesProject then
  begin
    mOpen := FHooks.OpenProject;
  end;
  if Assigned(mOpen) then
  begin
    mOpen();
  end;
end;

procedure TAtlasRulesChecksSection.BaselineClick(Sender: TObject);
begin
  if Sender = FBaselineUpdate then
  begin
    if Assigned(FHooks.BaselineUpdate) then
    begin
      FBaselineInfo.Caption := FHooks.BaselineUpdate();
    end;
  end
  else if Assigned(FHooks.BaselineDelete) and
    Confirmed(TAtlasRulesStrings.Text(TAtlasRulesTextId.ServerPageBaselineDeleteConfirm)) then
  begin
    FBaselineInfo.Caption := FHooks.BaselineDelete();
  end;
end;

procedure TAtlasRulesChecksSection.SuppressionsClick(Sender: TObject);
var
  mLine: string;
begin
  if not Assigned(FHooks.Suppressions) then
  begin
    Exit;
  end;
  FSuppressions.Items.BeginUpdate;
  try
    FSuppressions.Items.Clear;
    for mLine in FHooks.Suppressions() do
    begin
      FSuppressions.Items.Add(mLine);
    end;
  finally
    FSuppressions.Items.EndUpdate;
  end;
end;

procedure TAtlasRulesChecksSection.Close;
begin
  // Rückwärts zum Aufbau: erst die eigenen Elemente (Klassen des Moduls), dann die Haken zur IDE.
  FSwitch := nil;
  FRulesProject := nil;
  FRulesGlobal := nil;
  FBaselineInfo := nil;
  FBaselineUpdate := nil;
  FBaselineDelete := nil;
  FSuppressions := nil;
  FSuppressionsRefresh := nil;
  FreeAndNil(FControls);
  FHooks := Default(TAtlasRulesChecksHooks);
  inherited Close;
end;

destructor TAtlasRulesChecksSection.Destroy;
begin
  FreeAndNil(FControls);
  inherited Destroy;
end;

{ TAtlasRulesEditorSection }

function TAtlasRulesEditorSection.OwnerId: string;
begin
  Result := cRulesSettingsOwner;
end;

function TAtlasRulesEditorSection.AreaId: string;
begin
  Result := 'Editor';
end;

procedure TAtlasRulesEditorSection.BuildRows;
begin
  Switch('baseline.update', TAtlasRulesStrings.Text(TAtlasRulesTextId.SettingsBaselineUpdate));
  Switch('dfmRules.apply', TAtlasRulesStrings.Text(TAtlasRulesTextId.SettingsDfmPropertyRules));
end;

end.
