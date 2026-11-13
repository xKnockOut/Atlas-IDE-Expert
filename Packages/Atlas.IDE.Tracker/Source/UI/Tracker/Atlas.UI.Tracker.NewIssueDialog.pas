unit Atlas.UI.Tracker.NewIssueDialog;

// Dialog „Issue anlegen“ (#1268) mit Vorschau des Textes, bevor etwas an den
// Tracker geht: Tracker (Klappliste bei mehreren Verbindungen), Projekt,
// Titel, Beschreibung (Markdown, bearbeitbar), Häkchen „Codeausschnitt
// mitsenden“ mit dem Ausschnitt darunter (Vorgabe aus
// issues.create.includeCode), Typ, Priorität und Zuständig (Listen vom
// Tracker, frei eintippbar), „mir zuweisen“ und „gleich beginnen“.
// - GitHub (#2137): Klappliste „Vorlage“ mit den Issue-Vorlagen des
//   Repositorys (dazu „Leeres Issue“, wenn config.yml es erlaubt). Ein
//   Formular ersetzt Beschreibung und Codeausschnitt durch seine Felder
//   (TAtlasNewIssueFormPanel), vorbelegt aus Setup.Facts und Setup.Mappings;
//   Pflichtfelder werden vor dem Senden geprüft. Eine Markdown-Vorlage setzt
//   ihren Text vor die Beschreibung. Titel-Präfix, Labels, Zuständige, Typ und
//   Projekte der Vorlage werden übernommen. „Typ“ ist der Issue-Typ, wenn das
//   Repository welche hat; „Meilenstein“ und die Issue-Felder erscheinen nur,
//   wenn es sie gibt. „Im Browser fortsetzen“ öffnet das Formular auf GitHub
//   mit Titel und Werten (Setup.OnBrowse).
// - Gesendet wird nur mit „Anlegen“. Das Netz macht der Aufrufer im
//   Hintergrund (OnLoad für die Listen, OnSend für das Anlegen); die
//   Ergebnisse kommen im Hauptthread. Ist der Dialog dann schon zu, verfallen
//   sie (TAtlasNewIssueLink).
// - Schlägt das Anlegen fehl, bleibt der Dialog offen und nennt die Ursache;
//   der Aufrufer ändert am Code nichts. Während des Sendens lässt er sich
//   nicht schließen, damit kein Issue ohne Kennung im Code entsteht.
// Reine VCL; Kennung, TODO und Zwischenablage macht der Aufrufer.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.IssueForms,
  Atlas.Core.Tracker.NewIssue,
  Atlas.UI.Foundation.Dialog,
  Atlas.UI.Tracker.NewIssueBox,
  Atlas.UI.Tracker.NewIssueForm;

type
  /// <summary>Ein Eintrag der Klappliste „Tracker“.</summary>
  TAtlasNewIssueTracker = record
    /// <summary>"YouTrack Firma", "GitHub · github.com".</summary>
    Caption: string;
    /// <summary>Anbieter, Adresse, Projekt und Sprache.</summary>
    Target: TAtlasTrackerTarget;
    class function Create(const ACaption: string; const ATarget: TAtlasTrackerTarget): TAtlasNewIssueTracker;
      static;
  end;

  /// <summary>Vorbelegung des Dialogs.</summary>
  TAtlasNewIssueSetup = record
    Trackers: TArray<TAtlasNewIssueTracker>;
    /// <summary>Vorgewählter Eintrag in Trackers (Zuordnung bzw. .atlas).</summary>
    TrackerIndex: Integer;
    Title: string;
    /// <summary>Beschreibung ohne Codeausschnitt.</summary>
    Description: string;
    Code: string;
    /// <summary>Häkchen „Codeausschnitt mitsenden“ (issues.create.includeCode).</summary>
    IncludeCode: Boolean;
    /// <summary>„gleich beginnen“ möglich (Bereich „Meine Issues“ an).</summary>
    CanStart: Boolean;
    /// <summary>Version des Plugins und der IDE für die Vorbelegung einer Vorlage (#2137); Code und Befund
    /// ergänzt der Dialog aus Code und Description.</summary>
    Facts: TAtlasIssueFormFacts;
    /// <summary>Feld-Id → Platzhalter (issues.github.templateFields, .atlas tracker.templateFields).</summary>
    Mappings: TAtlasIssueFormMappings;
    /// <summary>Adresse im Browser öffnen („Im Browser fortsetzen“); nil = Knopf fehlt.</summary>
    OnBrowse: TProc<string>;
    class function Empty: TAtlasNewIssueSetup; static;
  end;

  TAtlasNewIssueFieldsDone = reference to procedure(const AFields: TAtlasNewIssueFields; ALoaded: Boolean);
  /// <summary>Listen des Trackers im Hintergrund laden; ADone im Hauptthread.</summary>
  TAtlasNewIssueLoadEvent = reference to procedure(const ATarget: TAtlasTrackerTarget;
    const ADone: TAtlasNewIssueFieldsDone);
  TAtlasNewIssueSendDone = reference to procedure(const AResult: TAtlasNewIssueResult);
  /// <summary>Issue im Hintergrund anlegen; ADone im Hauptthread.</summary>
  TAtlasNewIssueSendEvent = reference to procedure(const ATarget: TAtlasTrackerTarget;
    const ADraft: TAtlasNewIssueDraft; const ADone: TAtlasNewIssueSendDone);

  TAtlasNewIssueDialog = class;

  /// <summary>Verbindung von laufenden Anfragen zum Dialog; nil, sobald der Dialog weg ist.</summary>
  TAtlasNewIssueLink = class(TInterfacedObject)
  private
    FDialog: TAtlasNewIssueDialog;
  public
    property Dialog: TAtlasNewIssueDialog read FDialog write FDialog;
  end;

  /// <summary>Aufbau der Zeilen im Dialog: Beschriftung links, Steuerelement rechts, Höhen skaliert; Zeilen
  /// wachsen und schrumpfen mit dem Fenster.</summary>
  TAtlasNewIssueLayout = class
  private
    FForm: TForm;
  protected
    function Scaled(AValue: Integer): Integer;
    function AddBox(const ACaption: string; AStyle: TComboBoxStyle): TAtlasNewIssueBox;
  public
    constructor Create(AForm: TForm);
    /// <summary>Zeile mit Beschriftung ACaption (leer = ohne) und AControl unter dem bisher untersten Element von
    /// AParent.</summary>
    function AddRow(AParent: TWinControl; const ACaption: string; AControl: TWinControl; AHeight: Integer): TPanel;
    /// <summary>Knopf in AParent, so breit wie seine Beschriftung (mindestens cButtonMinWidth).</summary>
    function AddButton(AParent: TWinControl; const ACaption: string): TButton;
    /// <summary>Höhe einer Zeile ändern (0 = ausgeblendet, ihre Steuerelemente unsichtbar); das Fenster wächst bzw.
    /// schrumpft mit.</summary>
    procedure Resize(ARow: TWinControl; AHeight: Integer);
    property Form: TForm read FForm;
  end;

  /// <summary>Bereich für Beschreibung und Codeausschnitt oder, bei einer Vorlage (#2137), für ihre Felder; je eins
  /// ist sichtbar.</summary>
  TAtlasNewIssueContent = class(TPanel)
  private
    FLayout: TAtlasNewIssueLayout;
    FFree: TPanel;
    FDescription: TMemo;
    FIncludeCode: TCheckBox;
    FCode: TMemo;
    FFormPanel: TAtlasNewIssueFormPanel;
  public
    /// <summary>Baut den Bereich als Zeile im Formular von ALayout.</summary>
    constructor CreateIn(ALayout: TAtlasNewIssueLayout);
    /// <summary>Formular statt Beschreibung zeigen (bzw. zurück).</summary>
    procedure ShowFormPanel(AShow: Boolean);
    /// <summary>Breite des Inhalts im Formularbereich.</summary>
    function FormWidth: Integer;
    property DescriptionMemo: TMemo read FDescription;
    property IncludeCodeBox: TCheckBox read FIncludeCode;
    property CodeMemo: TMemo read FCode;
    property FormPanel: TAtlasNewIssueFormPanel read FFormPanel;
  end;

  /// <summary>Leiste unten mit „Im Browser fortsetzen“, „Anlegen“ und „Abbrechen“.</summary>
  TAtlasNewIssueButtons = class(TPanel)
  private
    FBrowse: TButton;
    FCreate: TButton;
    FCancel: TButton;
  public
    /// <summary>Baut die Leiste am unteren Rand des Formulars von ALayout.</summary>
    constructor CreateIn(ALayout: TAtlasNewIssueLayout);
    property BrowseButton: TButton read FBrowse;
    property CreateButton: TButton read FCreate;
    property CancelButton: TButton read FCancel;
  end;

  /// <summary>Steuerelemente des Dialogs (Zeilen mit Beschriftung, Häkchen, Stand, Knöpfe).</summary>
  TAtlasNewIssueParts = class(TAtlasNewIssueLayout)
  private
    FTracker: TAtlasNewIssueBox;
    FProject: TEdit;
    FTemplateRow: TPanel;
    FTemplate: TAtlasNewIssueBox;
    FTitle: TEdit;
    FContent: TAtlasNewIssueContent;
    FType: TAtlasNewIssueBox;
    FPriority: TAtlasNewIssueBox;
    FAssignee: TAtlasNewIssueBox;
    FMilestoneRow: TPanel;
    FMilestone: TAtlasNewIssueBox;
    FFieldRows: TAtlasNewIssueFieldRows;
    FAssignToMe: TCheckBox;
    FStartNow: TCheckBox;
    FStatus: TLabel;
    FButtons: TAtlasNewIssueButtons;
    procedure CreateRows;
    procedure CreateLists;
    procedure CreateOptions;
    procedure CreateStatus;
    procedure CreateButtons;
  public
    /// <summary>Baut alle Steuerelemente in AForm (Besitzer und Eltern ist AForm).</summary>
    constructor Create(AForm: TForm);
    property TrackerBox: TAtlasNewIssueBox read FTracker;
    property ProjectEdit: TEdit read FProject;
    property TemplateRow: TPanel read FTemplateRow;
    property TemplateBox: TAtlasNewIssueBox read FTemplate;
    property TitleEdit: TEdit read FTitle;
    property Content: TAtlasNewIssueContent read FContent;
    property TypeBox: TAtlasNewIssueBox read FType;
    property PriorityBox: TAtlasNewIssueBox read FPriority;
    property AssigneeBox: TAtlasNewIssueBox read FAssignee;
    property MilestoneRow: TPanel read FMilestoneRow;
    property MilestoneBox: TAtlasNewIssueBox read FMilestone;
    property FieldRows: TAtlasNewIssueFieldRows read FFieldRows;
    property AssignToMeBox: TCheckBox read FAssignToMe;
    property StartNowBox: TCheckBox read FStartNow;
    property StatusLabel: TLabel read FStatus;
    property Buttons: TAtlasNewIssueButtons read FButtons;
  end;

  TAtlasNewIssueDialog = class(TAtlasDialog)
  private
    FParts: TAtlasNewIssueParts;
    FSetup: TAtlasNewIssueSetup;
    FFields: TAtlasNewIssueFields;
    FResult: TAtlasNewIssueResult;
    FOnLoad: TAtlasNewIssueLoadEvent;
    FOnSend: TAtlasNewIssueSendEvent;
    FLink: TAtlasNewIssueLink;
    FLinkRef: IInterface;
    FSending: Boolean;
    /// <summary>Zählt Ladevorgänge; ein älteres Ergebnis nach einem Wechsel des Trackers verfällt.</summary>
    FLoadTicket: Integer;
    /// <summary>Gewählte Vorlage (Index in FFields.GitHub.Forms); -1 = leeres Issue bzw. keine.</summary>
    FFormIndex: Integer;
    /// <summary>Vorbelegung aus FSetup in die Felder und Ereignisse verbinden.</summary>
    procedure ApplySetup;
    procedure Changed(Sender: TObject);
    procedure TrackerChange(Sender: TObject);
    procedure TemplateChange(Sender: TObject);
    procedure CreateClick(Sender: TObject);
    procedure BrowseClick(Sender: TObject);
    procedure CancelClick(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure ClearFields;
    /// <summary>Vorlagen, Typen, Meilensteine und Issue-Felder aus FFields.GitHub zeigen.</summary>
    procedure ShowGitHub;
    /// <summary>Titel, Beschreibung bzw. Formular für die Vorlage AIndex (-1 = leeres Issue).</summary>
    procedure ApplyTemplate(AIndex: Integer);
    /// <summary>Zeile über den Formularfeldern: Labels, Zuständige und Projekte der Vorlage.</summary>
    function TemplateNote(const AForm: TAtlasIssueForm): string;
    /// <summary>Was vor dem Senden fehlt (Pflichtfeld, falscher Feldwert, nicht darstellbare Vorlage); '' = nichts.
    /// </summary>
    function Problem: string;
  protected
    procedure DoShow; override;
  public
    constructor CreateDialog(AOwner: TComponent; const ASetup: TAtlasNewIssueSetup;
      const AOnLoad: TAtlasNewIssueLoadEvent; const AOnSend: TAtlasNewIssueSendEvent);
    destructor Destroy; override;
    /// <summary>Gewählter Tracker mit dem Projekt aus dem Feld; False ohne Tracker.</summary>
    function Target(out ATarget: TAtlasTrackerTarget): Boolean;
    /// <summary>Gewählte Vorlage; False beim leeren Issue bzw. ohne Vorlagen.</summary>
    function CurrentForm(out AForm: TAtlasIssueForm): Boolean;
    /// <summary>Was „Anlegen“ sendet: Titel, Beschreibung (mit Codeausschnitt nur bei Häkchen, bei einem Formular
    /// dessen Felder), Felder; bei GitHub Vorlage, Meilenstein, Issue-Typ und Issue-Felder.</summary>
    function Draft: TAtlasNewIssueDraft;
    /// <summary>Adresse für „Im Browser fortsetzen“; '' ohne GitHub-Tracker.</summary>
    function BrowserUrl: string;
    /// <summary>Listen des Trackers für den gewählten Tracker laden (beim Anzeigen und nach einem Wechsel).
    /// </summary>
    procedure LoadFields;
    /// <summary>Listen übernehmen; was schon eingetippt ist, bleibt.</summary>
    procedure ShowFields(const AFields: TAtlasNewIssueFields; ALoaded: Boolean);
    /// <summary>Ergebnis von „Anlegen“: bei Erfolg schließt der Dialog mit mrOk, sonst bleibt er mit der Ursache.
    /// </summary>
    procedure ShowResult(const AResult: TAtlasNewIssueResult);
    /// <summary>Text zum Ergebnis; AProject für „Projekt unbekannt“, AServer für „kein Token“.</summary>
    class function ResultText(const AResult: TAtlasNewIssueResult; const AProject, AServer: string): string; static;
    /// <summary>Modal; True mit dem angelegten Issue in AResult, AStartNow für „gleich beginnen“.</summary>
    class function Execute(const ASetup: TAtlasNewIssueSetup; const AOnLoad: TAtlasNewIssueLoadEvent;
      const AOnSend: TAtlasNewIssueSendEvent; out AResult: TAtlasNewIssueResult; out AStartNow: Boolean): Boolean;
      static;
    property Parts: TAtlasNewIssueParts read FParts;
    property Sending: Boolean read FSending;
    property IssueResult: TAtlasNewIssueResult read FResult;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  Atlas.Core.Tracker.NewIssueGitHub,
  Atlas.UI.Tracker.NewIssue.Strings;

const
  cGap = 8;
  cLabelWidth = 110;
  cDialogWidth = 640;
  cRowHeight = 30;
  cCodeFontName = 'Consolas';
  cMemoHeight = 120;
  cCheckHeight = 26;
  /// <summary>Höhe des Bereichs für Beschreibung und Code bzw. für die Felder einer Vorlage.</summary>
  cContentHeight = cMemoHeight + cCheckHeight + cMemoHeight;
  cFormHeight = 340;
  cOptionsHeight = 28;
  cControlTop = 4;
  cAssignToMeWidth = 180;
  cStartNowWidth = 200;
  cBottomHeight = 44;
  cStatusSpace = 40;
  cButtonExtra = 32;
  cButtonMinWidth = 90;
  cButtonHeight = 28;
  /// <summary>Breite der senkrechten Bildlaufleiste, die der Formularbereich freihält.</summary>
  cScrollBarSpace = 24;

{ TAtlasNewIssueTracker }

class function TAtlasNewIssueTracker.Create(const ACaption: string;
  const ATarget: TAtlasTrackerTarget): TAtlasNewIssueTracker;
begin
  Result.Caption := ACaption;
  Result.Target := ATarget;
end;

{ TAtlasNewIssueSetup }

class function TAtlasNewIssueSetup.Empty: TAtlasNewIssueSetup;
begin
  Result := Default(TAtlasNewIssueSetup);
  Result.Trackers := nil;
  Result.IncludeCode := True;
  Result.Mappings := nil;
  Result.OnBrowse := nil;
end;

{ TAtlasNewIssueLayout }

constructor TAtlasNewIssueLayout.Create(AForm: TForm);
begin
  inherited Create;
  FForm := AForm;
end;

function TAtlasNewIssueLayout.Scaled(AValue: Integer): Integer;
begin
  Result := FForm.ScaleValue(AValue);
end;

/// <summary>Unter dem bisher untersten Element von AParent (alTop stapelt nach Top).</summary>
function NextTop(AParent: TWinControl): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  for mIndex := 0 to AParent.ControlCount - 1 do
  begin
    Result := Max(Result, AParent.Controls[mIndex].Top + AParent.Controls[mIndex].Height + 1);
  end;
end;

/// <summary>Neue Zeile alTop unter dem bisher Untersten von AParent; Lage vor Align und Parent.</summary>
function NewRow(AForm: TForm; AParent: TWinControl; AHeight: Integer): TPanel;
begin
  Result := TPanel.Create(AForm);
  Result.Top := NextTop(AParent);
  Result.Height := AHeight;
  Result.Align := alTop;
  Result.Parent := AParent;
  Result.BevelOuter := bvNone;
end;

function TAtlasNewIssueLayout.AddBox(const ACaption: string; AStyle: TComboBoxStyle): TAtlasNewIssueBox;
begin
  Result := TAtlasNewIssueBox.Create(FForm);
  Result.Style := AStyle;
  AddRow(FForm, ACaption, Result, cRowHeight);
end;

function TAtlasNewIssueLayout.AddRow(AParent: TWinControl; const ACaption: string; AControl: TWinControl;
  AHeight: Integer): TPanel;
var
  mLabel: TLabel;
begin
  Result := NewRow(FForm, AParent, Scaled(AHeight));
  AControl.Parent := Result;
  AControl.Left := Scaled(cGap + cLabelWidth);
  AControl.Top := Scaled(cControlTop);
  AControl.Width := Result.ClientWidth - AControl.Left - Scaled(cGap);
  if AHeight > cRowHeight then
  begin
    AControl.Height := Result.ClientHeight - Scaled(cGap);
    AControl.Anchors := [akLeft, akTop, akRight, akBottom];
  end
  else
  begin
    AControl.Anchors := [akLeft, akTop, akRight];
  end;
  if ACaption <> '' then
  begin
    mLabel := TLabel.Create(FForm);
    mLabel.Parent := Result;
    mLabel.Left := Scaled(cGap);
    mLabel.Top := Scaled(cGap);
    mLabel.Caption := ACaption;
    mLabel.ShowAccelChar := False;
    mLabel.FocusControl := AControl;
  end;
end;

function TAtlasNewIssueLayout.AddButton(AParent: TWinControl; const ACaption: string): TButton;
begin
  Result := TButton.Create(FForm);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  FForm.Canvas.Font := FForm.Font;
  Result.Width := Max(FForm.Canvas.TextWidth(ACaption) + Scaled(cButtonExtra), Scaled(cButtonMinWidth));
  Result.Top := Scaled(cGap div 2);
  Result.Height := Scaled(cButtonHeight);
  Result.Anchors := [akTop, akRight];
end;

procedure TAtlasNewIssueLayout.Resize(ARow: TWinControl; AHeight: Integer);
var
  mDelta, mIndex: Integer;
begin
  mDelta := AHeight - ARow.Height;
  // Die Feldzeilen blenden ihre Steuerelemente selbst ein und aus.
  if not (ARow is TAtlasNewIssueFieldRows) then
  begin
    for mIndex := 0 to ARow.ControlCount - 1 do
    begin
      ARow.Controls[mIndex].Visible := AHeight > 0;
    end;
  end;
  if mDelta = 0 then
  begin
    Exit;
  end;
  // Erst die Mindesthöhe senken bzw. danach heben, damit die Grenze das Fenster nicht festhält.
  if mDelta < 0 then
  begin
    FForm.Constraints.MinHeight := Max(0, FForm.Constraints.MinHeight + mDelta);
  end;
  ARow.Height := AHeight;
  FForm.ClientHeight := FForm.ClientHeight + mDelta;
  if (mDelta > 0) and (FForm.Constraints.MinHeight > 0) then
  begin
    FForm.Constraints.MinHeight := FForm.Constraints.MinHeight + mDelta;
  end;
end;

{ TAtlasNewIssueContent }

constructor TAtlasNewIssueContent.CreateIn(ALayout: TAtlasNewIssueLayout);
var
  mForm: TForm;
begin
  mForm := ALayout.Form;
  inherited Create(mForm);
  FLayout := ALayout;
  // Lage vor Align und Parent (alTop unter dem bisher Untersten).
  Top := NextTop(mForm);
  Height := ALayout.Scaled(cContentHeight);
  Align := alTop;
  Parent := mForm;
  BevelOuter := bvNone;
  FFree := TPanel.Create(mForm);
  FFree.BevelOuter := bvNone;
  FFree.Align := alClient;
  FFree.Parent := Self;
  FDescription := TMemo.Create(mForm);
  FDescription.ScrollBars := ssVertical;
  FDescription.WantReturns := True;
  ALayout.AddRow(FFree, TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId.NewIssueDescription), FDescription,
    cMemoHeight);
  FIncludeCode := TCheckBox.Create(mForm);
  FIncludeCode.Caption := TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId.NewIssueIncludeCode);
  ALayout.AddRow(FFree, '', FIncludeCode, cCheckHeight);
  FCode := TMemo.Create(mForm);
  FCode.ScrollBars := ssBoth;
  FCode.WordWrap := False;
  FCode.WantReturns := True;
  FCode.Font.Name := cCodeFontName;
  ALayout.AddRow(FFree, '', FCode, cMemoHeight);
  FFormPanel := TAtlasNewIssueFormPanel.Create(mForm);
  FFormPanel.Visible := False;
  FFormPanel.AlignWithMargins := True;
  FFormPanel.Margins.SetBounds(ALayout.Scaled(cGap + cLabelWidth), ALayout.Scaled(cControlTop),
    ALayout.Scaled(cGap), ALayout.Scaled(cControlTop));
  FFormPanel.Align := alClient;
  FFormPanel.Parent := Self;
end;

procedure TAtlasNewIssueContent.ShowFormPanel(AShow: Boolean);
begin
  FFree.Visible := not AShow;
  FFormPanel.Visible := AShow;
  if AShow then
  begin
    FLayout.Resize(Self, FLayout.Scaled(cFormHeight));
  end
  else
  begin
    FLayout.Resize(Self, FLayout.Scaled(cContentHeight));
  end;
end;

function TAtlasNewIssueContent.FormWidth: Integer;
begin
  Result := Max(FLayout.Scaled(cLabelWidth), ClientWidth - FLayout.Scaled(2 * cGap + cLabelWidth + cScrollBarSpace));
end;

{ TAtlasNewIssueButtons }

constructor TAtlasNewIssueButtons.CreateIn(ALayout: TAtlasNewIssueLayout);
begin
  inherited Create(ALayout.Form);
  Parent := ALayout.Form;
  Align := alBottom;
  Height := ALayout.Scaled(cBottomHeight);
  BevelOuter := bvNone;
  FCancel := ALayout.AddButton(Self, TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId.NewIssueCancel));
  FCancel.Cancel := True;
  FCancel.Left := ClientWidth - FCancel.Width - ALayout.Scaled(cGap);
  FCreate := ALayout.AddButton(Self, TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId.NewIssueCreate));
  FCreate.Left := FCancel.Left - FCreate.Width - ALayout.Scaled(cGap);
  FBrowse := ALayout.AddButton(Self, TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId.NewIssueBrowser));
  FBrowse.Left := FCreate.Left - FBrowse.Width - ALayout.Scaled(cGap);
end;

{ TAtlasNewIssueParts }

constructor TAtlasNewIssueParts.Create(AForm: TForm);
begin
  inherited Create(AForm);
  CreateRows;
  FContent := TAtlasNewIssueContent.CreateIn(Self);
  CreateLists;
  CreateOptions;
  CreateStatus;
  CreateButtons;
end;

procedure TAtlasNewIssueParts.CreateRows;
begin
  FTracker := AddBox(TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId.NewIssueTracker), csDropDownList);
  FProject := TEdit.Create(FForm);
  AddRow(FForm, TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId.NewIssueProject), FProject, cRowHeight);
  // Vorlagen (#2137): erst sichtbar, wenn der Tracker welche hat.
  FTemplate := TAtlasNewIssueBox.Create(FForm);
  FTemplate.Style := csDropDownList;
  FTemplateRow := AddRow(FForm, TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId.NewIssueTemplate), FTemplate,
    cRowHeight);
  Resize(FTemplateRow, 0);
  FTitle := TEdit.Create(FForm);
  AddRow(FForm, TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId.NewIssueSummary), FTitle, cRowHeight);
end;

procedure TAtlasNewIssueParts.CreateLists;
begin
  FType := AddBox(TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId.NewIssueType), csDropDown);
  FPriority := AddBox(TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId.NewIssuePriority), csDropDown);
  FAssignee := AddBox(TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId.NewIssueAssignee), csDropDown);
  // Meilenstein und Issue-Felder (#2137): nur, wenn das Repository sie hat.
  FMilestone := TAtlasNewIssueBox.Create(FForm);
  FMilestone.Style := csDropDownList;
  FMilestoneRow := AddRow(FForm, TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId.NewIssueMilestone), FMilestone,
    cRowHeight);
  Resize(FMilestoneRow, 0);
  FFieldRows := TAtlasNewIssueFieldRows.Create(FForm);
  FFieldRows.Top := NextTop(FForm);
  FFieldRows.Height := 0;
  FFieldRows.Align := alTop;
  FFieldRows.Parent := FForm;
  FFieldRows.BevelOuter := bvNone;
end;

procedure TAtlasNewIssueParts.CreateOptions;
var
  mOptions: TPanel;
begin
  mOptions := NewRow(FForm, FForm, Scaled(cOptionsHeight));
  FAssignToMe := TCheckBox.Create(FForm);
  FAssignToMe.Parent := mOptions;
  FAssignToMe.Left := Scaled(cGap + cLabelWidth);
  FAssignToMe.Top := Scaled(cControlTop);
  FAssignToMe.Width := Scaled(cAssignToMeWidth);
  FAssignToMe.Caption := TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId.NewIssueAssignToMe);
  FStartNow := TCheckBox.Create(FForm);
  FStartNow.Parent := mOptions;
  FStartNow.Left := FAssignToMe.Left + FAssignToMe.Width + Scaled(cGap);
  FStartNow.Top := Scaled(cControlTop);
  FStartNow.Width := Scaled(cStartNowWidth);
  FStartNow.Caption := TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId.NewIssueStartNow);
end;

procedure TAtlasNewIssueParts.CreateStatus;
begin
  FStatus := TLabel.Create(FForm);
  FStatus.Top := NextTop(FForm);
  FStatus.Align := alTop;
  FStatus.Parent := FForm;
  FStatus.AlignWithMargins := True;
  FStatus.Margins.SetBounds(Scaled(cGap + cLabelWidth), Scaled(cControlTop), Scaled(cGap), Scaled(cControlTop));
  FStatus.WordWrap := True;
  FStatus.ShowAccelChar := False;
  FStatus.Caption := '';
end;

procedure TAtlasNewIssueParts.CreateButtons;
begin
  FButtons := TAtlasNewIssueButtons.CreateIn(Self);
  // Kein Default-Knopf: Enter in der Beschreibung ist ein Zeilenumbruch, nie ein Senden.
  FForm.ClientHeight := FStatus.Top + Scaled(cStatusSpace) + FButtons.Height;
  FForm.Constraints.MinWidth := FForm.Width;
  FForm.Constraints.MinHeight := FForm.Height;
end;

{ TAtlasNewIssueDialog }

constructor TAtlasNewIssueDialog.CreateDialog(AOwner: TComponent; const ASetup: TAtlasNewIssueSetup;
  const AOnLoad: TAtlasNewIssueLoadEvent; const AOnSend: TAtlasNewIssueSendEvent);
begin
  inherited CreateDialog(AOwner, '', cDialogWidth);
  FSetup := ASetup;
  FOnLoad := AOnLoad;
  FOnSend := AOnSend;
  FFields := TAtlasNewIssueFields.Empty;
  FFormIndex := -1;
  FResult := TAtlasNewIssueResult.Create(TAtlasNewIssueOutcome.NotConfigured);
  FLink := TAtlasNewIssueLink.Create;
  FLink.Dialog := Self;
  FLinkRef := FLink;
  Caption := TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId.NewIssueDialogTitle);
  BorderStyle := bsSizeable;
  BorderIcons := [biSystemMenu];
  OnCloseQuery := FormCloseQuery;
  FParts := TAtlasNewIssueParts.Create(Self);
  FParts.Buttons.CancelButton.OnClick := CancelClick;
  FParts.Buttons.CreateButton.OnClick := CreateClick;
  FParts.Buttons.BrowseButton.OnClick := BrowseClick;
  ApplySetup;
  Changed(nil);
end;

procedure TAtlasNewIssueDialog.ApplySetup;
var
  mTracker: TAtlasNewIssueTracker;
  mCaptions: TArray<string>;
begin
  mCaptions := nil;
  for mTracker in FSetup.Trackers do
  begin
    mCaptions := mCaptions + [mTracker.Caption];
  end;
  FParts.TrackerBox.SetValues(mCaptions);
  if (FSetup.TrackerIndex >= 0) and (FSetup.TrackerIndex <= High(FSetup.Trackers)) then
  begin
    FParts.TrackerBox.Choice := FSetup.TrackerIndex;
  end
  else if Length(FSetup.Trackers) > 0 then
  begin
    FParts.TrackerBox.Choice := 0;
  end;
  if FParts.TrackerBox.Choice >= 0 then
  begin
    FParts.ProjectEdit.Text := FSetup.Trackers[FParts.TrackerBox.Choice].Target.Project;
  end;
  FParts.TitleEdit.Text := FSetup.Title;
  FParts.Content.DescriptionMemo.Text := StringReplace(FSetup.Description, #10, sLineBreak, [rfReplaceAll]);
  FParts.Content.CodeMemo.Text := StringReplace(FSetup.Code, #10, sLineBreak, [rfReplaceAll]);
  FParts.Content.IncludeCodeBox.Checked := FSetup.IncludeCode and (Trim(FSetup.Code) <> '');
  FParts.Content.IncludeCodeBox.Enabled := Trim(FSetup.Code) <> '';
  FParts.StartNowBox.Enabled := FSetup.CanStart;
  FParts.Buttons.BrowseButton.Visible := Assigned(FSetup.OnBrowse);
  FParts.TrackerBox.OnChange := TrackerChange;
  FParts.TemplateBox.OnChange := TemplateChange;
  FParts.TitleEdit.OnChange := Changed;
  FParts.ProjectEdit.OnChange := Changed;
  FParts.Content.IncludeCodeBox.OnClick := Changed;
  FParts.AssignToMeBox.OnClick := Changed;
  if FSetup.Title = '' then
  begin
    ActiveControl := FParts.TitleEdit;
  end
  else
  begin
    ActiveControl := FParts.Content.DescriptionMemo;
  end;
end;

destructor TAtlasNewIssueDialog.Destroy;
begin
  // Antworten, die danach kommen, finden keinen Dialog mehr.
  if FLink <> nil then
  begin
    FLink.Dialog := nil;
  end;
  FLinkRef := nil;
  ClearFields;
  // Die Steuerelemente gehören dem Formular; hier geht nur die Hülle.
  FreeAndNil(FParts);
  inherited Destroy;
end;

procedure TAtlasNewIssueDialog.ClearFields;
begin
  FSetup := TAtlasNewIssueSetup.Empty;
  FFields := TAtlasNewIssueFields.Empty;
  FResult := TAtlasNewIssueResult.Create(TAtlasNewIssueOutcome.NotConfigured);
end;

procedure TAtlasNewIssueDialog.DoShow;
begin
  inherited DoShow;
  LoadFields;
end;

function TAtlasNewIssueDialog.Target(out ATarget: TAtlasTrackerTarget): Boolean;
var
  mIndex: Integer;
  mLanguage: string;
begin
  mIndex := FParts.TrackerBox.Choice;
  Result := (mIndex >= 0) and (mIndex <= High(FSetup.Trackers));
  if not Result then
  begin
    ATarget := TAtlasTrackerTarget.Create('', '', '', '');
    Exit;
  end;
  ATarget := FSetup.Trackers[mIndex].Target;
  // Projekt aus dem Feld; Create normiert (GitHub owner/repo, Schrägstriche).
  mLanguage := ATarget.Language;
  ATarget := TAtlasTrackerTarget.Create(ATarget.Provider, ATarget.Url, FParts.ProjectEdit.Text, ATarget.Query);
  ATarget.Language := mLanguage;
end;

function TAtlasNewIssueDialog.CurrentForm(out AForm: TAtlasIssueForm): Boolean;
begin
  Result := (FFormIndex >= 0) and (FFormIndex <= High(FFields.GitHub.Forms));
  if Result then
  begin
    AForm := FFields.GitHub.Forms[FFormIndex];
  end
  else
  begin
    AForm := TAtlasIssueForm.Empty;
  end;
end;

/// <summary>Nummer des gewählten Meilensteins (Eintrag 0 = keiner); 0 ohne.</summary>
function MilestoneOf(ABox: TAtlasNewIssueBox; const AMilestones: TArray<TAtlasGitHubMilestone>): Integer;
begin
  Result := 0;
  if (ABox.Choice > 0) and (ABox.Choice - 1 <= High(AMilestones)) then
  begin
    Result := AMilestones[ABox.Choice - 1].Number;
  end;
end;

function TAtlasNewIssueDialog.Draft: TAtlasNewIssueDraft;
var
  mForm: TAtlasIssueForm;
begin
  Result := TAtlasNewIssueDraft.Empty;
  Result.Title := Trim(FParts.TitleEdit.Text);
  Result.Description := TAtlasNewIssues.Compose(FParts.Content.DescriptionMemo.Text, FParts.Content.CodeMemo.Text,
    FParts.Content.IncludeCodeBox.Checked);
  Result.IssueType := Trim(FParts.TypeBox.Text);
  Result.Priority := Trim(FParts.PriorityBox.Text);
  Result.Assignee := Trim(FParts.AssigneeBox.Text);
  Result.AssignToMe := FParts.AssignToMeBox.Checked;
  Result.TypeField := FFields.TypeField;
  Result.PriorityField := FFields.PriorityField;
  Result.AssigneeField := FFields.AssigneeField;
  // GitHub (#2137): Mit Issue-Typen ist „Typ“ der Typ statt eines Labels.
  if Length(FFields.GitHub.IssueTypes) > 0 then
  begin
    Result.GitHub.IssueType := Result.IssueType;
    Result.IssueType := '';
  end;
  Result.GitHub.Milestone := MilestoneOf(FParts.MilestoneBox, FFields.GitHub.Milestones);
  Result.GitHub.FieldValues := FParts.FieldRows.Values;
  if not CurrentForm(mForm) then
  begin
    Exit;
  end;
  Result.GitHub.Labels := mForm.Labels;
  Result.GitHub.Assignees := mForm.Assignees;
  Result.GitHub.Projects := mForm.Projects;
  if (Result.GitHub.IssueType = '') and (Length(FFields.GitHub.IssueTypes) > 0) then
  begin
    Result.GitHub.IssueType := mForm.IssueType;
  end;
  if not mForm.IsMarkdown then
  begin
    Result.Description := TAtlasIssueForms.Body(mForm, FParts.Content.FormPanel.Answers);
  end;
end;

function TAtlasNewIssueDialog.BrowserUrl: string;
var
  mTarget: TAtlasTrackerTarget;
  mForm: TAtlasIssueForm;
  mLink: TAtlasIssueFormLink;
  mDraft: TAtlasNewIssueDraft;
  mMilestone: Integer;
begin
  Result := '';
  if not Target(mTarget) or not SameText(mTarget.Provider, TAtlasTrackerTarget.cGitHub) then
  begin
    Exit;
  end;
  mDraft := Draft;
  mLink := TAtlasIssueFormLink.Empty;
  mLink.Repository := TAtlasGitHubNewIssue.RepositoryPage(mTarget);
  mLink.Title := mDraft.Title;
  mLink.IssueType := mDraft.GitHub.IssueType;
  mLink.Labels := mDraft.GitHub.Labels;
  if mDraft.IssueType <> '' then
  begin
    mLink.Labels := mLink.Labels + [mDraft.IssueType];
  end;
  mMilestone := FParts.MilestoneBox.Choice;
  if (mMilestone > 0) and (mMilestone - 1 <= High(FFields.GitHub.Milestones)) then
  begin
    mLink.Milestone := FFields.GitHub.Milestones[mMilestone - 1].Title;
  end;
  if CurrentForm(mForm) then
  begin
    // Labels, Zuständige und Projekte setzt das Formular auf GitHub selbst.
    mLink.Template := mForm.FileName;
    mLink.Labels := nil;
    if not mForm.IsMarkdown then
    begin
      mLink.Fields := TAtlasIssueForms.LinkFields(mForm, FParts.Content.FormPanel.Answers);
      Exit(TAtlasIssueForms.BrowserUrl(mLink));
    end;
  end;
  mLink.Body := mDraft.Description;
  Result := TAtlasIssueForms.BrowserUrl(mLink);
end;

procedure TAtlasNewIssueDialog.Changed(Sender: TObject);
var
  mTarget: TAtlasTrackerTarget;
  mHasTarget: Boolean;
begin
  mHasTarget := Target(mTarget) and mTarget.Configured;
  FParts.Buttons.CreateButton.Enabled := not FSending and mHasTarget and (Trim(FParts.TitleEdit.Text) <> '') and
    Assigned(FOnSend);
  FParts.Buttons.CancelButton.Enabled := not FSending;
  FParts.Buttons.BrowseButton.Enabled := not FSending and mHasTarget and
    SameText(mTarget.Provider, TAtlasTrackerTarget.cGitHub) and Assigned(FSetup.OnBrowse);
  FParts.Content.CodeMemo.Enabled := FParts.Content.IncludeCodeBox.Checked;
  FParts.AssigneeBox.Enabled := not FParts.AssignToMeBox.Checked;
  if not FSending and (Length(FSetup.Trackers) = 0) then
  begin
    FParts.StatusLabel.Caption := TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId.NewIssueNoTracker);
  end;
end;

procedure TAtlasNewIssueDialog.TrackerChange(Sender: TObject);
var
  mIndex: Integer;
begin
  mIndex := FParts.TrackerBox.Choice;
  if (mIndex >= 0) and (mIndex <= High(FSetup.Trackers)) then
  begin
    FParts.ProjectEdit.Text := FSetup.Trackers[mIndex].Target.Project;
  end;
  // Vorlagen und Felder des vorigen Trackers gelten nicht mehr.
  FFields.GitHub := TAtlasNewIssueFields.Empty.GitHub;
  ShowGitHub;
  Changed(Sender);
  LoadFields;
end;

procedure TAtlasNewIssueDialog.LoadFields;
var
  mTarget: TAtlasTrackerTarget;
  mLinkRef: IInterface;
  mLink: TAtlasNewIssueLink;
  mTicket: Integer;
begin
  if not Assigned(FOnLoad) or not Target(mTarget) or not mTarget.Configured then
  begin
    Exit;
  end;
  Inc(FLoadTicket);
  mTicket := FLoadTicket;
  mLinkRef := FLinkRef;
  mLink := FLink;
  FParts.StatusLabel.Caption := TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId.NewIssueLoading);
  FOnLoad(mTarget,
    procedure(const AFields: TAtlasNewIssueFields; ALoaded: Boolean)
    begin
      if (mLinkRef <> nil) and (mLink.Dialog <> nil) and (mLink.Dialog.FLoadTicket = mTicket) then
      begin
        mLink.Dialog.ShowFields(AFields, ALoaded);
      end;
    end);
end;

procedure TAtlasNewIssueDialog.ShowFields(const AFields: TAtlasNewIssueFields; ALoaded: Boolean);
begin
  FFields := AFields;
  FParts.TypeBox.SetValues(AFields.Types);
  FParts.PriorityBox.SetValues(AFields.Priorities);
  FParts.AssigneeBox.SetValues(AFields.Assignees);
  ShowGitHub;
  if FSending then
  begin
    Exit;
  end;
  if ALoaded then
  begin
    FParts.StatusLabel.Caption := '';
  end
  else
  begin
    FParts.StatusLabel.Caption := TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId.NewIssueLoadFailed);
  end;
end;

procedure TAtlasNewIssueDialog.ShowGitHub;
var
  mNames: TArray<string>;
  mForm: TAtlasIssueForm;
  mMilestone: TAtlasGitHubMilestone;
  mOffset: Integer;
begin
  // Typ: Issue-Typen des Repositorys statt Labels.
  if Length(FFields.GitHub.IssueTypes) > 0 then
  begin
    FParts.TypeBox.SetValues(FFields.GitHub.IssueTypes);
  end;
  mNames := [TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId.NewIssueNone)];
  for mMilestone in FFields.GitHub.Milestones do
  begin
    mNames := mNames + [mMilestone.Title];
  end;
  FParts.MilestoneBox.SetValues(mNames);
  FParts.MilestoneBox.Choice := 0;
  if Length(FFields.GitHub.Milestones) > 0 then
  begin
    FParts.Resize(FParts.MilestoneRow, FParts.Scaled(cRowHeight));
  end
  else
  begin
    FParts.Resize(FParts.MilestoneRow, 0);
  end;
  FParts.FieldRows.ShowFields(FFields.GitHub.Fields, cLabelWidth, cRowHeight);
  FParts.Resize(FParts.FieldRows, FParts.FieldRows.Height);
  // Vorlagen: „Leeres Issue“ zuerst, wenn erlaubt; sonst ist die erste Vorlage gewählt.
  mNames := nil;
  mOffset := 0;
  if FFields.GitHub.BlankAllowed then
  begin
    mNames := [TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId.NewIssueBlank)];
    mOffset := 1;
  end;
  for mForm in FFields.GitHub.Forms do
  begin
    mNames := mNames + [mForm.Name];
  end;
  FParts.TemplateBox.SetValues(mNames);
  FParts.TemplateBox.Choice := 0;
  FParts.TemplateBox.Tag := mOffset;
  if Length(FFields.GitHub.Forms) > 0 then
  begin
    FParts.Resize(FParts.TemplateRow, FParts.Scaled(cRowHeight));
    ApplyTemplate(-mOffset);
  end
  else
  begin
    FParts.Resize(FParts.TemplateRow, 0);
    ApplyTemplate(-1);
  end;
end;

procedure TAtlasNewIssueDialog.TemplateChange(Sender: TObject);
begin
  ApplyTemplate(FParts.TemplateBox.Choice - FParts.TemplateBox.Tag);
end;

function TAtlasNewIssueDialog.TemplateNote(const AForm: TAtlasIssueForm): string;
var
  mParts: TArray<string>;
begin
  if AForm.Unsupported then
  begin
    Exit(TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId.NewIssueUnsupported));
  end;
  mParts := nil;
  if Length(AForm.Labels) > 0 then
  begin
    mParts := mParts + [TAtlasNewIssueStrings.Fmt(TAtlasNewIssueTextId.NewIssueTemplateLabels,
      [string.Join(', ', AForm.Labels)])];
  end;
  if Length(AForm.Assignees) > 0 then
  begin
    mParts := mParts + [TAtlasNewIssueStrings.Fmt(TAtlasNewIssueTextId.NewIssueTemplateAssignees,
      [string.Join(', ', AForm.Assignees)])];
  end;
  if Length(AForm.Projects) > 0 then
  begin
    mParts := mParts + [TAtlasNewIssueStrings.Fmt(TAtlasNewIssueTextId.NewIssueTemplateProjects,
      [string.Join(', ', AForm.Projects)])];
  end;
  Result := '';
  if Length(mParts) > 0 then
  begin
    Result := TAtlasNewIssueStrings.Fmt(TAtlasNewIssueTextId.NewIssueFromTemplate, [string.Join(' · ', mParts)]);
  end;
  if AForm.About <> '' then
  begin
    Result := Trim(AForm.About + sLineBreak + Result);
  end;
end;

procedure TAtlasNewIssueDialog.ApplyTemplate(AIndex: Integer);
var
  mOld, mForm: TAtlasIssueForm;
  mTitle: string;
  mFacts: TAtlasIssueFormFacts;
begin
  CurrentForm(mOld);
  FFormIndex := AIndex;
  CurrentForm(mForm);
  // Titel: Präfix der vorigen Vorlage weg, das der neuen davor (Eingetipptes bleibt).
  mTitle := FParts.TitleEdit.Text;
  if (Trim(mOld.TitlePrefix) <> '') and StartsText(mOld.TitlePrefix, mTitle) then
  begin
    mTitle := Copy(mTitle, Length(mOld.TitlePrefix) + 1, MaxInt);
  end;
  FParts.TitleEdit.Text := TAtlasIssueForms.TitleOf(mForm, mTitle);
  if (mForm.IssueType <> '') and (Length(FFields.GitHub.IssueTypes) > 0) then
  begin
    FParts.TypeBox.Text := mForm.IssueType;
  end;
  // Markdown-Vorlage: ihr Text vor der Beschreibung von Atlas; Code bleibt beim Häkchen. Ohne Markdown-Vorlage
  // vorher und nachher bleibt die Beschreibung, wie sie ist (auch Eingetipptes, wenn die Listen spät kommen).
  if mOld.IsMarkdown or mForm.IsMarkdown then
  begin
    FParts.Content.DescriptionMemo.Text := StringReplace(Trim(Trim(mForm.Body + #10#10) + #10#10 + FSetup.Description),
      #10, sLineBreak, [rfReplaceAll]);
  end;
  FParts.Content.ShowFormPanel((AIndex >= 0) and not mForm.IsMarkdown);
  if (AIndex < 0) or mForm.IsMarkdown then
  begin
    Changed(nil);
    Exit;
  end;
  mFacts := FSetup.Facts;
  mFacts.Finding := FSetup.Description;
  mFacts.Code := '';
  if FParts.Content.IncludeCodeBox.Checked then
  begin
    mFacts.Code := FSetup.Code;
  end;
  FParts.Content.FormPanel.ShowForm(mForm, TAtlasIssueForms.Prefill(mForm, FSetup.Mappings, mFacts),
    FParts.Content.FormWidth, TemplateNote(mForm));
  Changed(nil);
end;

function TAtlasNewIssueDialog.Problem: string;
var
  mForm: TAtlasIssueForm;
  mMissing: TArray<string>;
  mInvalid: string;
begin
  Result := '';
  if CurrentForm(mForm) and mForm.Unsupported then
  begin
    Exit(TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId.NewIssueUnsupported));
  end;
  if CurrentForm(mForm) then
  begin
    mMissing := TAtlasIssueForms.Missing(mForm, FParts.Content.FormPanel.Answers);
    if Length(mMissing) = 1 then
    begin
      FParts.Content.FormPanel.FocusCaption(mMissing[0]);
      Exit(TAtlasNewIssueStrings.Fmt(TAtlasNewIssueTextId.NewIssueRequired, [mMissing[0]]));
    end;
    if Length(mMissing) > 1 then
    begin
      FParts.Content.FormPanel.FocusCaption(mMissing[0]);
      Exit(TAtlasNewIssueStrings.Fmt(TAtlasNewIssueTextId.NewIssueRequiredMany, [string.Join(', ', mMissing)]));
    end;
  end;
  mInvalid := FParts.FieldRows.InvalidField;
  if mInvalid <> '' then
  begin
    Result := TAtlasNewIssueStrings.Fmt(TAtlasNewIssueTextId.NewIssueFieldInvalid, [mInvalid]);
  end;
end;

procedure TAtlasNewIssueDialog.CreateClick(Sender: TObject);
var
  mTarget: TAtlasTrackerTarget;
  mLinkRef: IInterface;
  mLink: TAtlasNewIssueLink;
  mProblem: string;
begin
  if FSending or not Assigned(FOnSend) or not Target(mTarget) then
  begin
    Exit;
  end;
  if Trim(FParts.TitleEdit.Text) = '' then
  begin
    FParts.StatusLabel.Caption := TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId.NewIssueNoTitle);
    Exit;
  end;
  // Pflichtfelder der Vorlage und Werte der Issue-Felder vor dem Senden (#2137).
  mProblem := Problem;
  if mProblem <> '' then
  begin
    FParts.StatusLabel.Caption := mProblem;
    Exit;
  end;
  FSending := True;
  FParts.StatusLabel.Caption := TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId.NewIssueSending);
  Changed(Sender);
  mLinkRef := FLinkRef;
  mLink := FLink;
  FOnSend(mTarget, Draft,
    procedure(const AResult: TAtlasNewIssueResult)
    begin
      if (mLinkRef <> nil) and (mLink.Dialog <> nil) then
      begin
        mLink.Dialog.ShowResult(AResult);
      end;
    end);
end;

procedure TAtlasNewIssueDialog.BrowseClick(Sender: TObject);
var
  mUrl: string;
begin
  mUrl := BrowserUrl;
  if (mUrl <> '') and Assigned(FSetup.OnBrowse) then
  begin
    FSetup.OnBrowse(mUrl);
  end;
end;

procedure TAtlasNewIssueDialog.ShowResult(const AResult: TAtlasNewIssueResult);
var
  mTarget: TAtlasTrackerTarget;
begin
  FSending := False;
  FResult := AResult;
  if AResult.Outcome = TAtlasNewIssueOutcome.Created then
  begin
    ModalResult := mrOk;
    Exit;
  end;
  Target(mTarget);
  FParts.StatusLabel.Caption := ResultText(AResult, mTarget.Project, mTarget.Server);
  Changed(nil);
end;

/// <summary>"Meilenstein, Typ, Projekt x" aus ADropped; '' ohne.</summary>
function DroppedText(const ADropped: TAtlasGitHubDropped): string;
var
  mParts: TArray<string>;
begin
  mParts := nil;
  if ADropped.Milestone then
  begin
    mParts := mParts + [TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId.NewIssueDroppedMilestone)];
  end;
  if ADropped.IssueType then
  begin
    mParts := mParts + [TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId.NewIssueDroppedType)];
  end;
  if Length(ADropped.Projects) > 0 then
  begin
    mParts := mParts + [TAtlasNewIssueStrings.Fmt(TAtlasNewIssueTextId.NewIssueDroppedProjects,
      [string.Join(', ', ADropped.Projects)])];
  end;
  Result := string.Join(', ', mParts);
end;

class function TAtlasNewIssueDialog.ResultText(const AResult: TAtlasNewIssueResult;
  const AProject, AServer: string): string;
begin
  case AResult.Outcome of
    TAtlasNewIssueOutcome.Created:
      begin
        Result := TAtlasNewIssueStrings.Fmt(TAtlasNewIssueTextId.NewIssueCreated, [AResult.Key]);
        // GitHub setzt Typ und Meilenstein nur mit Schreibrechten und schweigt sonst (#2137).
        if AResult.Dropped.Any then
        begin
          Result := TAtlasNewIssueStrings.Fmt(TAtlasNewIssueTextId.NewIssueDropped, [AResult.Key,
            DroppedText(AResult.Dropped)]);
        end;
      end;
    TAtlasNewIssueOutcome.NoToken:
      Result := TAtlasNewIssueStrings.Fmt(TAtlasNewIssueTextId.NewIssueNoToken, [AServer]);
    TAtlasNewIssueOutcome.NotConfigured:
      Result := TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId.NewIssueNotConfigured);
    TAtlasNewIssueOutcome.Rejected:
      Result := TAtlasNewIssueStrings.Fmt(TAtlasNewIssueTextId.NewIssueRejected, [AResult.HttpStatus]);
    TAtlasNewIssueOutcome.ProjectUnknown:
      Result := TAtlasNewIssueStrings.Fmt(TAtlasNewIssueTextId.NewIssueProjectUnknown, [AProject]);
    TAtlasNewIssueOutcome.Invalid:
      Result := TAtlasNewIssueStrings.Fmt(TAtlasNewIssueTextId.NewIssueInvalid, [AResult.TrackerMessage]);
    TAtlasNewIssueOutcome.Unreadable:
      Result := TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId.NewIssueUnreadable);
    TAtlasNewIssueOutcome.ServerError:
      Result := TAtlasNewIssueStrings.Fmt(TAtlasNewIssueTextId.NewIssueServerError, [AResult.HttpStatus]);
  else
    Result := TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId.NewIssueUnreachable);
  end;
end;

procedure TAtlasNewIssueDialog.CancelClick(Sender: TObject);
begin
  if FSending then
  begin
    Exit;
  end;
  ModalResult := mrCancel;
end;

procedure TAtlasNewIssueDialog.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  // Während des Sendens nicht schließen: Sonst entstünde ein Issue, dessen Kennung nicht in den Code kommt.
  CanClose := not FSending;
end;

class function TAtlasNewIssueDialog.Execute(const ASetup: TAtlasNewIssueSetup;
  const AOnLoad: TAtlasNewIssueLoadEvent; const AOnSend: TAtlasNewIssueSendEvent; out AResult: TAtlasNewIssueResult;
  out AStartNow: Boolean): Boolean;
var
  mDialog: TAtlasNewIssueDialog;
begin
  AResult := TAtlasNewIssueResult.Create(TAtlasNewIssueOutcome.NotConfigured);
  AStartNow := False;
  mDialog := TAtlasNewIssueDialog.CreateDialog(nil, ASetup, AOnLoad, AOnSend);
  try
    Result := (mDialog.ShowModal = mrOk) and (mDialog.IssueResult.Outcome = TAtlasNewIssueOutcome.Created);
    if Result then
    begin
      AResult := mDialog.IssueResult;
      AStartNow := mDialog.Parts.StartNowBox.Checked and mDialog.Parts.StartNowBox.Enabled;
    end;
  finally
    mDialog.Free;
  end;
end;

end.
