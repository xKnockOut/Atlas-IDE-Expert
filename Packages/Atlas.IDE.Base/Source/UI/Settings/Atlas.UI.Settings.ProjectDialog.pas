unit Atlas.UI.Settings.ProjectDialog;

// Dialog der Server-Einstellungen (#227) für eine Ebene: atlas.json des
// Projekts oder die globale Datei %APPDATA%\Atlas\settings.json. Seiten und
// Bedienelemente entstehen aus dem JSON-Schema (TAtlasSettingsSchema), die
// Werte aus TAtlasSettingsModel. Jede Einstellung hat genau einen Ort (x-scope
// im Schema): Der Aufrufer reicht nur die Felder dieser Datei herein, im
// Projekt ohne globale Ebene. Je Einstellung steht, ob sie gesetzt ist oder der
// Standard gilt; „Auf Standard zurücksetzen“ entfernt den Schlüssel.
// Eigene Bedienelemente, wo Text, Zahl, Auswahl und Liste nicht reichen:
//   - Auswahl aus Werten, die die IDE-Schicht liefert (OnChoices): installierte
//     Delphi-Versionen, Konfigurationen und Plattformen der .dproj, Profile.
//   - Textfelder mit Beispielen im Schema als Auswahl mit freier Eingabe.
//   - Dateiauswahl für x-control „Datei wählen“ (logFile, traceFile).
//   - "rules": Den Regel-Editor (#909) mit einem Knoten je Regelgruppe liefert
//     das Modul Prüfregeln als abgeleitete Dialogklasse (IAtlasSettingsDialogProvider,
//     #1755). Ohne Modul steht "rules" als JSON-Text da wie die übrigen Werte.
//   - Übrige Werte (profiles, overrides, dfmPropertyRules, profile als Objekt)
//     als JSON-Text.
// Vor dem Schließen mit OK prüft OnValidate den neuen Text (beim Server, sonst
// nur die Syntax). Geschrieben wird nicht hier: Der Aufrufer schreibt
// Model.ResultText.

// Aufbau in einer Vorfahrenkette, je Ebene eine Aufgabe: Rahmen mit Knöpfen
// und Hinweis (TAtlasSettingsDialogFrame), Seitenbaum und Navigation
// (TAtlasSettingsDialogPages), Felder einer Seite und ihre Prüfung
// (TAtlasSettingsDialogFields), Dialog mit Katalog (TAtlasProjectSettingsDialog,
// Grundlage des Regel-Editors im Modul Prüfregeln).

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Vcl.Dialogs,
  Vcl.Graphics,
  Atlas.Core.Settings.Schema,
  Atlas.Core.Settings.Layers,
  Atlas.Core.Settings.Choices,
  Atlas.Core.Settings.Validation;

type
  /// <summary>Auswahl für ein Feld (Pfad); leer = keine eigene Auswahl.</summary>
  TAtlasSettingChoicesFunc = reference to function(const APath: string): TArray<TAtlasSettingChoice>;
  /// <summary>Prüft AText; AChecked = False, wenn nur die Syntax geprüft werden konnte.</summary>
  TAtlasSettingsCheckFunc = reference to function(const AText: string; out AChecked: Boolean)
    : TArray<TAtlasSettingIssue>;

  /// <summary>Rahmen des Dialogs: Titel, Knöpfe unten, Hinweis oben und die Fläche für die Felder.</summary>
  TAtlasSettingsDialogFrame = class(TForm)
  private
    FOnOpenFile: TProc;
    FBuildHint: string;
    FServerChecks: Boolean;
    procedure CreateButtons(const AFileName: string);
    procedure CreateHint;
    procedure UpdateHint;
    procedure OpenClick(Sender: TObject);
    procedure OkClick(Sender: TObject);
    procedure SetBuildHint(const AValue: string);
    procedure SetServerChecks(AValue: Boolean);
  protected
    FModel: TAtlasSettingsModel;
    FBox: TScrollBox;
    FHint: TLabel;
    /// <summary>AModel bleibt beim Aufrufer. AFileName: bearbeitete Datei für die Anzeige.</summary>
    constructor CreateFrame(AOwner: TComponent; AModel: TAtlasSettingsModel; const AFileName: string);
    /// <summary>Fläche der Felder; nach dem Seitenbaum anlegen.</summary>
    procedure CreateBox;
    /// <summary>Höhe des Hinweises zur neuen Breite: Ein umbrechendes Label rechnet sie nur beim Setzen des
    /// Textes, vor dem Anzeigen war es noch schmal und hinterließ einen hohen leeren Streifen.</summary>
    procedure Resize; override;
  public
    /// <summary>Prüfen wie bei OK; True, wenn gespeichert werden darf.</summary>
    function Validate: Boolean; virtual; abstract;
    property Model: TAtlasSettingsModel read FModel;
    property HintLabel: TLabel read FHint;
    property OnOpenFile: TProc read FOnOpenFile write FOnOpenFile;
    /// <summary>Hinweis auf eine Auswahl von Konfiguration und Plattform in der IDE (selectBuild); '' ohne.</summary>
    property BuildHint: string read FBuildHint write SetBuildHint;
    /// <summary>Der Server prüft beim Speichern; sonst steht oben ein Hinweis.</summary>
    property ServerChecks: Boolean read FServerChecks write SetServerChecks;
  end;

  /// <summary>Seitenbaum: ein Knoten je Seite, unter der Seite mit "rules" einer je Regelgruppe (RuleGroups).
  /// </summary>
  TAtlasSettingsDialogPages = class(TAtlasSettingsDialogFrame)
  private
    FSelecting: Boolean;
    procedure CreateTree;
    procedure AddGroupNodes(APage: Integer);
    procedure PageTreeChange(Sender: TObject; Node: TTreeNode);
  protected
    FPages: TArray<string>;
    FPageTree: TTreeView;
    /// <summary>Knoten je Seite (Index wie FPages) und je Regelgruppe (Index wie FGroups).</summary>
    FPageNodes: TArray<TTreeNode>;
    FGroups: TArray<string>;
    FGroupNodes: TArray<TTreeNode>;
    /// <summary>Gezeigt: Seite FCurrentPage oder Gruppe FCurrentGroup (Index), das andere -1.</summary>
    FCurrentPage: Integer;
    FCurrentGroup: Integer;
    /// <summary>Feld "rules"; -1 ohne.</summary>
    FRuleIndex: Integer;
    constructor CreatePages(AOwner: TComponent; AModel: TAtlasSettingsModel; const AFileName: string);
    /// <summary>Seite mit dem Feld "rules"; -1 ohne.</summary>
    function RulePage: Integer;
    procedure SelectNode(ANode: TTreeNode);
    procedure ShowCurrent;
    procedure ShowPage(APage: Integer); virtual; abstract;
    procedure ShowGroup(AGroup: Integer); virtual; abstract;
    /// <summary>Regelgruppen für die Knoten unter der Seite mit "rules"; ohne Regel-Editor keine. Wird schon im
    /// Konstruktor gefragt.</summary>
    function RuleGroups: TArray<string>; virtual;
    /// <summary>Beschriftung des Knotens der Regelgruppe AGroup.</summary>
    function RuleGroupCaption(const AGroup: string): string; virtual;
  public
    /// <summary>Seite mit diesem Namen zeigen; False ohne sie.</summary>
    function SelectPage(const APage: string): Boolean;
    /// <summary>Knoten der Regelgruppe AGroup; nil ohne.</summary>
    function GroupNode(const AGroup: string): TTreeNode;
    property Pages: TArray<string> read FPages;
    property PageTree: TTreeView read FPageTree;
  end;

  /// <summary>Felder einer Seite mit Zustand und „Auf Standard zurücksetzen“ und ihre Prüfung vor OK.</summary>
  TAtlasSettingsDialogFields = class(TAtlasSettingsDialogPages)
  private
    FOnChoices: TAtlasSettingChoicesFunc;
    FOnValidate: TAtlasSettingsCheckFunc;
    function RawProblem(AIndex: Integer): string;
    function RawValid: Boolean;
    function ServerAccepts: Boolean;
    procedure CheckClick(Sender: TObject);
    procedure EditChange(Sender: TObject);
    procedure ComboChange(Sender: TObject);
    procedure TextComboChange(Sender: TObject);
    procedure MemoChange(Sender: TObject);
    procedure JsonChange(Sender: TObject);
    procedure BrowseClick(Sender: TObject);
    procedure ResetClick(Sender: TObject);
    procedure SetProjectHint(const AValue: string);
  protected
    // Getippter Text der Zahlen- und JSON-Felder; ungültige Eingaben verhindern OK.
    FRaw: TArray<string>;
    FRawValid: TArray<Boolean>;
    FStates: TArray<TLabel>;
    FResets: TArray<TButton>;
    FFileEdits: TArray<TEdit>;
    FTextChoices: TArray<TArray<TAtlasSettingChoice>>;
    FProjectHint: string;
    constructor CreateFields(AOwner: TComponent; AModel: TAtlasSettingsModel; const AFileName: string);
    function ChoicesOf(AIndex: Integer): TArray<TAtlasSettingChoice>;
    function AddLabel(const AText: string; ATop: Integer): TLabel;
    procedure ClearBox; virtual;
    procedure ShowPage(APage: Integer); override;
    procedure UpdateState(AIndex: Integer);
    /// <summary>Wert von AIndex auf den Standard zurücksetzen.</summary>
    procedure ResetValue(AIndex: Integer); virtual;
    /// <summary>"rules" mit eigenem Editor (Modul Prüfregeln); sonst als JSON-Text.</summary>
    function HasRuleEditor: Boolean; virtual;
    /// <summary>Regeltabelle ab ATop, mit AGroup nur diese Gruppe; liefert die Oberkante darunter. Nur mit
    /// HasRuleEditor.</summary>
    function AddRuleTable(ATop: Integer; const AGroup: string): Integer; virtual;
  public
    /// <summary>Text des Zustands eines Felds auf der gezeigten Seite; '' wenn nicht gezeigt.</summary>
    function StateText(const APath: string): string;
    function Validate: Boolean; override;
    /// <summary>Vor dem ersten Anzeigen einer Seite setzen.</summary>
    property OnChoices: TAtlasSettingChoicesFunc read FOnChoices write FOnChoices;
    property OnValidate: TAtlasSettingsCheckFunc read FOnValidate write FOnValidate;
    /// <summary>Aktives Projekt für den Hinweis beim Feld "project"; '' ohne.</summary>
    property ProjectHint: string read FProjectHint write SetProjectHint;
  end;

  /// <summary>Dialog über eine Einstellungsdatei mit dem Katalog des Servers. Der Regel-Editor (#909) für "rules"
  /// kommt aus dem Modul Prüfregeln als abgeleitete Klasse (#1755).</summary>
  TAtlasProjectSettingsDialog = class(TAtlasSettingsDialogFields)
  protected
    FCatalog: TJSONValue;
    procedure ShowGroup(AGroup: Integer); override;
    /// <summary>Nach dem Aufbau, bevor die erste Seite erscheint: Werte der Ableitung lesen.</summary>
    procedure ValuesReady; virtual;
  public
    /// <summary>AModel bleibt beim Aufrufer. AFileName: bearbeitete Datei für die Anzeige.</summary>
    constructor CreateDialog(AOwner: TComponent; AModel: TAtlasSettingsModel; const AFileName: string); virtual;
    /// <summary>Knoten der Gruppe der Regel zeigen und die Regel markieren („Regel einstellen…“, #909); False
    /// ohne Regel-Editor, ohne Katalog, ohne "rules" oder ohne die Regel.</summary>
    function SelectRule(const AId: string): Boolean; virtual;
    /// <summary>Antwort von atlas.server.settingsCatalog für die Regeltabelle; bleibt beim Aufrufer.</summary>
    property Catalog: TJSONValue read FCatalog write FCatalog;
  end;

  TAtlasProjectSettingsDialogClass = class of TAtlasProjectSettingsDialog;

  /// <summary>Dialogklasse mit Regel-Editor; das Modul Prüfregeln stellt sie bereit (#1755), der Aufrufer fragt
  /// laufende Module bei jedem Öffnen. Ohne Modul gilt TAtlasProjectSettingsDialog.</summary>
  IAtlasSettingsDialogProvider = interface
    ['{C41D7E62-9B35-4F08-A2D7-5E8F13B9C604}']
    function DialogClass: TAtlasProjectSettingsDialogClass;
  end;

implementation

uses
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Guard,
  System.Math,
  Atlas.Core.Settings.JsonText,
  Atlas.Core.Settings.PageNames,
  Atlas.UI.Strings,
  Atlas.UI.Settings.Strings;

const
  cGap = 8;
  cControlWidth = 320;
  cRulesPath = 'rules';
  /// <summary>Data der Gruppenknoten ab hier; darunter der Index der Seite.</summary>
  cGroupBase = 10000;

/// <summary>Gültiger JSON-Wert (auch Zahl oder String)?</summary>
function IsJsonValue(const AText: string): Boolean;
var
  mValue: TJSONValue;
begin
  mValue := TJSONObject.ParseJSONValue(TAtlasJsonText.StripComments(AText));
  Result := mValue <> nil;
  mValue.Free;
end;

function IsEnglish: Boolean;
begin
  Result := TAtlasStrings.Language = TAtlasLanguage.English;
end;

function DialogTitle(AGlobal: Boolean): string;
begin
  if AGlobal then
  begin
    Result := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.ProjectSettingsGlobalTitle);
  end
  else
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.ProjectSettingsTitle);
  end;
end;

function OpenFileCaption(AGlobal: Boolean): string;
begin
  if AGlobal then
  begin
    Result := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.GlobalSettingsOpenFile);
  end
  else
  begin
    Result := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.ProjectSettingsOpenFile);
  end;
end;

function NewButton(AParent: TWinControl; const ACaption: string; ALeft, AWidth: Integer): TButton;
begin
  Result := TButton.Create(AParent.Owner);
  Result.Parent := AParent;
  Result.SetBounds(ALeft, 8, AWidth, 28);
  Result.Caption := ACaption;
end;

/// <summary>Strings eines JSON-Arrays als Zeilen in ALines; anderes bleibt weg.</summary>
procedure AddJsonStrings(ALines: TStrings; const AJson: string);
var
  mValue: TJSONValue;
  mItem: TJSONValue;
begin
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONArray) then
    begin
      Exit;
    end;
    for mItem in TJSONArray(mValue) do
    begin
      if mItem is TJSONString then
      begin
        ALines.Add(TJSONString(mItem).Value);
      end;
    end;
  finally
    mValue.Free;
  end;
end;

function HasError(const AIssues: TArray<TAtlasSettingIssue>): Boolean;
var
  mIssue: TAtlasSettingIssue;
begin
  Result := False;
  for mIssue in AIssues do
  begin
    if mIssue.Error then
    begin
      Result := True;
    end;
  end;
end;

{ TAtlasSettingsDialogFrame }

constructor TAtlasSettingsDialogFrame.CreateFrame(AOwner: TComponent; AModel: TAtlasSettingsModel;
  const AFileName: string);
begin
  inherited CreateNew(AOwner);
  FModel := AModel;
  Caption := DialogTitle(FModel.Global);
  BorderStyle := bsSizeable;
  Position := poMainFormCenter;
  Width := 960;
  Height := 660;
  FServerChecks := True;
  CreateButtons(AFileName);
  CreateHint;
end;

procedure TAtlasSettingsDialogFrame.CreateButtons(const AFileName: string);
var
  mBottom: TPanel;
  mButton: TButton;
  mFileLabel: TLabel;
begin
  mBottom := TPanel.Create(Self);
  mBottom.Parent := Self;
  mBottom.Align := alBottom;
  mBottom.Height := 44;
  mBottom.BevelOuter := bvNone;
  mFileLabel := TLabel.Create(Self);
  mFileLabel.Parent := mBottom;
  mFileLabel.Left := 170;
  mFileLabel.Top := 14;
  mFileLabel.Caption := TAtlasSettingsStrings.Fmt(TAtlasSettingsTextId.ProjectSettingsFile, [AFileName]);
  mButton := NewButton(mBottom, OpenFileCaption(FModel.Global), cGap, 150);
  mButton.OnClick := OpenClick;
  mButton := NewButton(mBottom, TAtlasSettingsStrings.Text(TAtlasSettingsTextId.ProjectSettingsOk),
    mBottom.Width - 2 * (90 + cGap),
    90);
  mButton.Anchors := [akTop, akRight];
  mButton.Default := True;
  mButton.OnClick := OkClick;
  mButton := NewButton(mBottom, TAtlasStrings.Text(TAtlasTextId.ProjectSettingsCancel), mBottom.Width - (90 + cGap),
    90);
  mButton.Anchors := [akTop, akRight];
  mButton.Cancel := True;
  mButton.ModalResult := mrCancel;
end;

procedure TAtlasSettingsDialogFrame.CreateHint;
begin
  // Hinweise oben: Auswahl in der IDE (selectBuild) und Prüfung ohne Server.
  FHint := TLabel.Create(Self);
  FHint.Parent := Self;
  FHint.Align := alTop;
  FHint.AlignWithMargins := True;
  FHint.WordWrap := True;
  FHint.Font.Color := clGrayText;
  FHint.Visible := False;
end;

procedure TAtlasSettingsDialogFrame.CreateBox;
begin
  FBox := TScrollBox.Create(Self);
  FBox.Parent := Self;
  FBox.Align := alClient;
  FBox.BorderStyle := bsNone;
  FBox.VertScrollBar.Tracking := True;
end;

procedure TAtlasSettingsDialogFrame.UpdateHint;
var
  mLines: TArray<string>;
begin
  mLines := nil;
  if FBuildHint <> '' then
  begin
    mLines := mLines + [FBuildHint];
  end;
  if not FServerChecks then
  begin
    mLines := mLines + [TAtlasSettingsStrings.Text(TAtlasSettingsTextId.ProjectSettingsSyntaxOnly)];
  end;
  FHint.Caption := string.Join(sLineBreak, mLines);
  FHint.Visible := Length(mLines) > 0;
end;

procedure TAtlasSettingsDialogFrame.Resize;
begin
  inherited Resize;
  if (FHint <> nil) and FHint.Visible then
  begin
    FHint.AutoSize := False;
    FHint.AutoSize := True;
  end;
end;

procedure TAtlasSettingsDialogFrame.SetBuildHint(const AValue: string);
begin
  FBuildHint := AValue;
  UpdateHint;
end;

procedure TAtlasSettingsDialogFrame.SetServerChecks(AValue: Boolean);
begin
  FServerChecks := AValue;
  UpdateHint;
end;

procedure TAtlasSettingsDialogFrame.OpenClick(Sender: TObject);
begin
  if Assigned(FOnOpenFile) then
  begin
    ModalResult := mrCancel;
    FOnOpenFile();
  end;
end;

procedure TAtlasSettingsDialogFrame.OkClick(Sender: TObject);
begin
  if Validate then
  begin
    ModalResult := mrOk;
  end;
end;

{ TAtlasSettingsDialogPages }

constructor TAtlasSettingsDialogPages.CreatePages(AOwner: TComponent; AModel: TAtlasSettingsModel;
  const AFileName: string);
begin
  inherited CreateFrame(AOwner, AModel, AFileName);
  FCurrentPage := -1;
  FCurrentGroup := -1;
  FRuleIndex := FModel.IndexOf(cRulesPath);
  CreateTree;
  CreateBox;
end;

procedure TAtlasSettingsDialogPages.CreateTree;
var
  mIndex: Integer;
begin
  FPageTree := TTreeView.Create(Self);
  FPageTree.Parent := Self;
  FPageTree.Align := alLeft;
  FPageTree.Width := 190;
  FPageTree.ReadOnly := True;
  FPageTree.HideSelection := False;
  FPageTree.ShowLines := False;
  FPageTree.RowSelect := True;
  FPageTree.OnChange := PageTreeChange;
  FPages := TAtlasSettingsSchema.Pages(FModel.AllFields);
  SetLength(FPageNodes, Length(FPages));
  FPageTree.Items.BeginUpdate;
  try
    for mIndex := 0 to High(FPages) do
    begin
      FPageNodes[mIndex] := FPageTree.Items.Add(nil, TAtlasSettingsPageNames.Caption(FPages[mIndex], IsEnglish));
      FPageNodes[mIndex].Data := Pointer(NativeInt(mIndex));
    end;
    AddGroupNodes(RulePage);
  finally
    FPageTree.Items.EndUpdate;
  end;
end;

procedure TAtlasSettingsDialogPages.AddGroupNodes(APage: Integer);
var
  mGroup: string;
  mNode: TTreeNode;
begin
  // Prüfregeln (#909): unter der Seite mit "rules" je Gruppe ein Knoten mit Hauptschalter und Tabelle.
  if APage < 0 then
  begin
    Exit;
  end;
  for mGroup in RuleGroups do
  begin
    mNode := FPageTree.Items.AddChild(FPageNodes[APage], RuleGroupCaption(mGroup));
    mNode.Data := Pointer(NativeInt(cGroupBase + Length(FGroups)));
    FGroups := FGroups + [mGroup];
    FGroupNodes := FGroupNodes + [mNode];
  end;
  FPageNodes[APage].Expand(False);
end;

function TAtlasSettingsDialogPages.RuleGroups: TArray<string>;
begin
  Result := nil;
end;

function TAtlasSettingsDialogPages.RuleGroupCaption(const AGroup: string): string;
begin
  Result := AGroup;
end;

function TAtlasSettingsDialogPages.RulePage: Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  if FRuleIndex < 0 then
  begin
    Exit;
  end;
  for mIndex := 0 to High(FPages) do
  begin
    if SameText(FPages[mIndex], FModel.Fields[FRuleIndex].Page) then
    begin
      Result := mIndex;
    end;
  end;
end;

function TAtlasSettingsDialogPages.SelectPage(const APage: string): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FPages) do
  begin
    if SameText(FPages[mIndex], APage) then
    begin
      SelectNode(FPageNodes[mIndex]);
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TAtlasSettingsDialogPages.SelectNode(ANode: TTreeNode);
begin
  // Auch ein schon gewählter Knoten baut neu auf; OnChange käme dann nicht.
  FSelecting := True;
  try
    FPageTree.Selected := ANode;
  finally
    FSelecting := False;
  end;
  PageTreeChange(FPageTree, ANode);
end;

procedure TAtlasSettingsDialogPages.PageTreeChange(Sender: TObject; Node: TTreeNode);
var
  mTag: NativeInt;
begin
  if FSelecting or (Node = nil) or (FBox = nil) then
  begin
    Exit;
  end;
  mTag := NativeInt(Node.Data);
  if mTag >= cGroupBase then
  begin
    ShowGroup(mTag - cGroupBase);
  end
  else
  begin
    ShowPage(mTag);
  end;
end;

procedure TAtlasSettingsDialogPages.ShowCurrent;
begin
  if FCurrentGroup >= 0 then
  begin
    ShowGroup(FCurrentGroup);
  end
  else if FCurrentPage >= 0 then
  begin
    ShowPage(FCurrentPage);
  end;
end;

function TAtlasSettingsDialogPages.GroupNode(const AGroup: string): TTreeNode;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FGroups) do
  begin
    if SameText(FGroups[mIndex], AGroup) then
    begin
      Exit(FGroupNodes[mIndex]);
    end;
  end;
  Result := nil;
end;

{ TSettingsFieldRow }

type
  /// <summary>Baut die Zeile eines Felds auf der Seite: Name, Hinweise, Bedienelement, Zustand und
  /// Zurücksetzen.</summary>
  TSettingsFieldRow = record
    Dialog: TAtlasSettingsDialogFields;
    Box: TScrollBox;
    Index: Integer;
    Field: TAtlasSettingField;
    Top: Integer;
    Width_: Integer;
    Control: TControl;
    procedure Header;
    procedure Note(const AText: string; AGray: Boolean);
    procedure Notes;
    procedure JsonMemo;
    function NewCheck: TControl;
    function NewEdit: TEdit;
    function TextCombo(const AChoices: TArray<TAtlasSettingChoice>): TControl;
    procedure FileButton(AEdit: TEdit);
    procedure TextControl;
    function ChoiceCombo: TControl;
    function ListMemo: TControl;
    procedure ValueControl;
    procedure StateAndReset;
    /// <summary>Baut die Zeile ab ATop und liefert die Oberkante der nächsten.</summary>
    function Build(ADialog: TAtlasSettingsDialogFields; AIndex, ATop: Integer): Integer;
  end;

procedure TSettingsFieldRow.Header;
var
  mName: TLabel;
begin
  mName := TLabel.Create(Box);
  mName.Parent := Box;
  mName.SetBounds(cGap * 2, Top, 400, 16);
  mName.Font.Style := [fsBold];
  mName.Caption := Field.Path;
  if Field.Experimental then
  begin
    mName.Caption := mName.Caption + '  [' + TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsExperimentalTag) +
      ']';
  end;
  Inc(Top, 20);
end;

procedure TSettingsFieldRow.Note(const AText: string; AGray: Boolean);
var
  mNote: TLabel;
begin
  mNote := Dialog.AddLabel(AText, Top);
  if AGray then
  begin
    mNote.Font.Color := clGrayText;
  end;
  Inc(Top, mNote.Height + 4);
end;

procedure TSettingsFieldRow.Notes;
begin
  if Field.DescriptionFor(IsEnglish) <> '' then
  begin
    Note(Field.DescriptionFor(IsEnglish), False);
  end;
  if Field.Restart then
  begin
    Note(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.ProjectSettingsRestart), True);
  end;
  if (Field.Path = 'project') and (Dialog.FProjectHint <> '') then
  begin
    Note(TAtlasSettingsStrings.Fmt(TAtlasSettingsTextId.ProjectSettingsActiveProject, [Dialog.FProjectHint]), True);
  end;
end;

procedure TSettingsFieldRow.JsonMemo;
var
  mMemo: TMemo;
begin
  // JSON-Text für alles, was mehr als ein einfacher Wert ist.
  Note(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.ProjectSettingsJsonHint), True);
  mMemo := TMemo.Create(Box);
  mMemo.Parent := Box;
  mMemo.Height := 120;
  mMemo.ScrollBars := ssBoth;
  mMemo.WordWrap := False;
  mMemo.Font.Name := 'Consolas';
  mMemo.Text := Dialog.FRaw[Index];
  mMemo.OnChange := Dialog.JsonChange;
  Control := mMemo;
  Width_ := Max(cControlWidth, Box.ClientWidth - cGap * 5 - 300);
end;

function TSettingsFieldRow.NewCheck: TControl;
var
  mCheck: TCheckBox;
begin
  mCheck := TCheckBox.Create(Box);
  mCheck.Parent := Box;
  mCheck.Caption := Field.Path;
  mCheck.Checked := Dialog.FModel.Effective(Index) = 'true';
  mCheck.OnClick := Dialog.CheckClick;
  Result := mCheck;
end;

function TSettingsFieldRow.NewEdit: TEdit;
begin
  Result := TEdit.Create(Box);
  Result.Parent := Box;
  if Dialog.FModel.Current(Index) <> '' then
  begin
    Result.Text := Dialog.FRaw[Index];
  end
  else
  begin
    Result.TextHint := TAtlasSettingsSchema.Display(Dialog.FModel.Fallback(Index));
  end;
  Result.OnChange := Dialog.EditChange;
end;

function TSettingsFieldRow.TextCombo(const AChoices: TArray<TAtlasSettingChoice>): TControl;
var
  mCombo: TComboBox;
  mChoice: Integer;
begin
  // Auswahl mit freier Eingabe: Anzeige der Auswahl, gespeichert wird ihr JSON-Text.
  Dialog.FTextChoices[Index] := AChoices;
  mCombo := TComboBox.Create(Box);
  mCombo.Parent := Box;
  mCombo.Style := csDropDown;
  mCombo.Items.BeginUpdate;
  try
    for mChoice := 0 to High(AChoices) do
    begin
      mCombo.Items.Add(AChoices[mChoice].Caption);
    end;
  finally
    mCombo.Items.EndUpdate;
  end;
  mChoice := TAtlasSettingChoices.IndexOf(AChoices, Dialog.FModel.Current(Index));
  if mChoice >= 0 then
  begin
    mCombo.ItemIndex := mChoice;
  end
  else if Dialog.FModel.Current(Index) <> '' then
  begin
    mCombo.Text := Dialog.FRaw[Index];
  end
  else
  begin
    mCombo.TextHint := TAtlasSettingsSchema.Display(Dialog.FModel.Fallback(Index));
  end;
  mCombo.OnChange := Dialog.TextComboChange;
  Result := mCombo;
end;

procedure TSettingsFieldRow.FileButton(AEdit: TEdit);
var
  mBrowse: TButton;
begin
  Dialog.FFileEdits[Index] := AEdit;
  Width_ := cControlWidth - 34;
  mBrowse := TButton.Create(Box);
  mBrowse.Parent := Box;
  mBrowse.SetBounds(cGap * 2 + cControlWidth - 30, Top, 30, 24);
  mBrowse.Caption := '…';
  mBrowse.Tag := Index;
  mBrowse.OnClick := Dialog.BrowseClick;
end;

procedure TSettingsFieldRow.TextControl;
var
  mChoices: TArray<TAtlasSettingChoice>;
  mEdit: TEdit;
begin
  mChoices := Dialog.ChoicesOf(Index);
  if Length(mChoices) > 0 then
  begin
    Control := TextCombo(mChoices);
    Exit;
  end;
  mEdit := NewEdit;
  Control := mEdit;
  if Field.PicksFile then
  begin
    FileButton(mEdit);
  end;
end;

function TSettingsFieldRow.ChoiceCombo: TControl;
var
  mCombo: TComboBox;
  mChoice: Integer;
begin
  mCombo := TComboBox.Create(Box);
  mCombo.Parent := Box;
  mCombo.Style := csDropDownList;
  for mChoice := 0 to High(Field.Choices) do
  begin
    mCombo.Items.Add(TAtlasSettingsSchema.Display(Field.Choices[mChoice]));
    if Field.Choices[mChoice] = Dialog.FModel.Effective(Index) then
    begin
      mCombo.ItemIndex := mChoice;
    end;
  end;
  mCombo.OnChange := Dialog.ComboChange;
  Result := mCombo;
end;

function TSettingsFieldRow.ListMemo: TControl;
var
  mMemo: TMemo;
begin
  mMemo := TMemo.Create(Box);
  mMemo.Parent := Box;
  mMemo.Height := 72;
  mMemo.ScrollBars := ssVertical;
  AddJsonStrings(mMemo.Lines, Dialog.FModel.Effective(Index));
  mMemo.OnChange := Dialog.MemoChange;
  Result := mMemo;
end;

procedure TSettingsFieldRow.ValueControl;
begin
  case Field.Kind of
    TAtlasSettingKind.Boolean_:
      Control := NewCheck;
    TAtlasSettingKind.Integer_:
      Control := NewEdit;
    TAtlasSettingKind.Text:
      TextControl;
    TAtlasSettingKind.Choice:
      Control := ChoiceCombo;
    TAtlasSettingKind.List:
      Control := ListMemo;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

procedure TSettingsFieldRow.StateAndReset;
var
  mState: TLabel;
  mReset: TButton;
begin
  mState := TLabel.Create(Box);
  mState.Parent := Box;
  if Control <> nil then
  begin
    Control.Tag := Index;
    Control.SetBounds(cGap * 2, Top, Width_, Control.Height);
    mState.SetBounds(cGap * 2 + Width_ + cGap, Top + 4, 150, 16);
  end
  else
  begin
    mState.SetBounds(cGap * 2, Top, 150, 16);
  end;
  mState.Font.Color := clGrayText;
  Dialog.FStates[Index] := mState;
  // Eine Ebene je Datei: Ohne den Schlüssel gilt immer der Standard.
  mReset := TButton.Create(Box);
  mReset.Parent := Box;
  mReset.SetBounds(mState.Left + 150 + cGap, mState.Top - 4, 140, 24);
  mReset.Caption := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.ProjectSettingsResetDefault);
  mReset.Tag := Index;
  mReset.OnClick := Dialog.ResetClick;
  Dialog.FResets[Index] := mReset;
  Dialog.UpdateState(Index);
end;

function TSettingsFieldRow.Build(ADialog: TAtlasSettingsDialogFields; AIndex, ATop: Integer): Integer;
begin
  Dialog := ADialog;
  Box := ADialog.FBox;
  Index := AIndex;
  Field := ADialog.FModel.Fields[AIndex];
  Top := ATop;
  Width_ := cControlWidth;
  Control := nil;
  Header;
  Notes;
  if (Index = Dialog.FRuleIndex) and Dialog.HasRuleEditor then
  begin
    // Regeltabelle aus dem Katalog; der Zustand gilt für "rules" als Ganzes.
    Top := Dialog.AddRuleTable(Top, '');
  end
  else if not Dialog.FModel.Typed(Index) then
  begin
    JsonMemo;
  end
  else
  begin
    ValueControl;
  end;
  StateAndReset;
  Result := Top + 24 + cGap * 2;
  if Control <> nil then
  begin
    Result := Top + Control.Height + cGap * 2;
  end;
end;

{ TAtlasSettingsDialogFields }

constructor TAtlasSettingsDialogFields.CreateFields(AOwner: TComponent; AModel: TAtlasSettingsModel;
  const AFileName: string);
var
  mIndex: Integer;
begin
  inherited CreatePages(AOwner, AModel, AFileName);
  SetLength(FRaw, FModel.Count);
  SetLength(FRawValid, FModel.Count);
  SetLength(FStates, FModel.Count);
  SetLength(FResets, FModel.Count);
  SetLength(FFileEdits, FModel.Count);
  SetLength(FTextChoices, FModel.Count);
  for mIndex := 0 to FModel.Count - 1 do
  begin
    FRaw[mIndex] := FModel.Current(mIndex);
    if FModel.Typed(mIndex) then
    begin
      FRaw[mIndex] := TAtlasSettingsSchema.Display(FModel.Current(mIndex));
    end;
    FRawValid[mIndex] := True;
  end;
end;

function TAtlasSettingsDialogFields.StateText(const APath: string): string;
var
  mIndex: Integer;
begin
  Result := '';
  mIndex := FModel.IndexOf(APath);
  if (mIndex >= 0) and (FStates[mIndex] <> nil) then
  begin
    Result := FStates[mIndex].Caption;
  end;
end;

function TAtlasSettingsDialogFields.ChoicesOf(AIndex: Integer): TArray<TAtlasSettingChoice>;
begin
  Result := nil;
  if Assigned(FOnChoices) then
  begin
    Result := FOnChoices(FModel.Fields[AIndex].Path);
  end;
  // Beispiele aus dem Schema als Vorschläge (encoding, config …), wenn die IDE nichts liefert.
  if (Length(Result) = 0) and (FModel.Fields[AIndex].Kind = TAtlasSettingKind.Text) then
  begin
    Result := TAtlasSettingChoices.FromTexts(FModel.Fields[AIndex].Examples);
  end;
end;

procedure TAtlasSettingsDialogFields.SetProjectHint(const AValue: string);
begin
  FProjectHint := AValue;
  ShowCurrent;
end;

procedure TAtlasSettingsDialogFields.UpdateState(AIndex: Integer);
var
  mText: string;
begin
  if FStates[AIndex] = nil then
  begin
    Exit;
  end;
  case FModel.Origin(AIndex) of
    TAtlasSettingOrigin.Project:
      mText := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.ProjectSettingsFromProject);
    TAtlasSettingOrigin.Global:
      if FModel.Global then
      begin
        mText := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.ProjectSettingsFromGlobal);
      end
      else
      begin
        mText := TAtlasSettingsStrings.Fmt(TAtlasSettingsTextId.ProjectSettingsInherited,
          [Copy(TAtlasSettingsSchema.Display(FModel.Inherited_(AIndex)), 1, 60)]);
      end;
  else
    if FModel.Fields[AIndex].DefaultJson <> '' then
    begin
      mText := TAtlasSettingsStrings.Fmt(TAtlasSettingsTextId.ProjectSettingsDefault,
        [Copy(TAtlasSettingsSchema.Display(FModel.Fields[AIndex].DefaultJson), 1, 60)]);
    end
    else
    begin
      mText := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.ProjectSettingsDefaultNone);
    end;
  end;
  FStates[AIndex].Caption := mText;
  if FResets[AIndex] <> nil then
  begin
    FResets[AIndex].Enabled := FModel.Current(AIndex) <> '';
  end;
end;

function TAtlasSettingsDialogFields.AddLabel(const AText: string; ATop: Integer): TLabel;
begin
  Result := TLabel.Create(FBox);
  Result.Parent := FBox;
  Result.WordWrap := True;
  Result.AutoSize := True;
  Result.SetBounds(cGap * 2, ATop, FBox.ClientWidth - cGap * 5, 16);
  Result.Caption := AText;
end;

procedure TAtlasSettingsDialogFields.ShowPage(APage: Integer);
var
  mIndex, mTop: Integer;
  mRow: TSettingsFieldRow;
begin
  ClearBox;
  FCurrentPage := APage;
  FCurrentGroup := -1;
  mTop := cGap;
  for mIndex := 0 to FModel.Count - 1 do
  begin
    if SameText(FModel.Fields[mIndex].Page, FPages[APage]) then
    begin
      mRow := Default(TSettingsFieldRow);
      mTop := mRow.Build(Self, mIndex, mTop);
    end;
  end;
end;

function TAtlasSettingsDialogFields.HasRuleEditor: Boolean;
begin
  Result := False;
end;

function TAtlasSettingsDialogFields.AddRuleTable(ATop: Integer; const AGroup: string): Integer;
begin
  Result := ATop;
end;

procedure TAtlasSettingsDialogFields.ClearBox;
var
  mIndex: Integer;
begin
  FBox.VertScrollBar.Position := 0;
  while FBox.ControlCount > 0 do
  begin
    FBox.Controls[0].Free;
  end;
  for mIndex := 0 to High(FStates) do
  begin
    FStates[mIndex] := nil;
    FResets[mIndex] := nil;
    FFileEdits[mIndex] := nil;
  end;
end;

procedure TAtlasSettingsDialogFields.CheckClick(Sender: TObject);
var
  mIndex: Integer;
begin
  mIndex := TCheckBox(Sender).Tag;
  if TCheckBox(Sender).Checked then
  begin
    FModel.SetValue(mIndex, 'true');
  end
  else
  begin
    FModel.SetValue(mIndex, 'false');
  end;
  UpdateState(mIndex);
end;

procedure TAtlasSettingsDialogFields.EditChange(Sender: TObject);
var
  mIndex, mNumber: Integer;
  mText: string;
begin
  mIndex := TEdit(Sender).Tag;
  mText := Trim(TEdit(Sender).Text);
  FRaw[mIndex] := mText;
  FRawValid[mIndex] := True;
  if mText = '' then
  begin
    FModel.SetValue(mIndex, '');
  end
  else if FModel.Fields[mIndex].Kind = TAtlasSettingKind.Text then
  begin
    FModel.SetValue(mIndex, TAtlasJsonText.Quote(mText));
  end
  else if TryStrToInt(mText, mNumber) then
  begin
    FModel.SetValue(mIndex, IntToStr(mNumber));
  end
  else
  begin
    FRawValid[mIndex] := False;
  end;
  UpdateState(mIndex);
end;

procedure TAtlasSettingsDialogFields.ComboChange(Sender: TObject);
var
  mIndex: Integer;
begin
  mIndex := TComboBox(Sender).Tag;
  if TComboBox(Sender).ItemIndex >= 0 then
  begin
    FModel.SetValue(mIndex, FModel.Fields[mIndex].Choices[TComboBox(Sender).ItemIndex]);
  end;
  UpdateState(mIndex);
end;

procedure TAtlasSettingsDialogFields.TextComboChange(Sender: TObject);
var
  mIndex, mChoice: Integer;
  mText, mJson: string;
begin
  mIndex := TComboBox(Sender).Tag;
  mText := Trim(TComboBox(Sender).Text);
  FRaw[mIndex] := mText;
  mJson := '';
  if mText <> '' then
  begin
    mJson := TAtlasJsonText.Quote(mText);
  end;
  // Eine Anzeige aus der Liste speichert ihren Wert ("Delphi 12 (23.0)" → "23.0"), sonst den Text.
  for mChoice := High(FTextChoices[mIndex]) downto 0 do
  begin
    if FTextChoices[mIndex][mChoice].Caption = mText then
    begin
      mJson := FTextChoices[mIndex][mChoice].Json;
    end;
  end;
  FModel.SetValue(mIndex, mJson);
  UpdateState(mIndex);
end;

procedure TAtlasSettingsDialogFields.MemoChange(Sender: TObject);
var
  mIndex: Integer;
  mLine: string;
  mList: TJSONArray;
begin
  mIndex := TMemo(Sender).Tag;
  mList := TJSONArray.Create;
  try
    for mLine in TMemo(Sender).Lines do
    begin
      if Trim(mLine) <> '' then
      begin
        mList.Add(Trim(mLine));
      end;
    end;
    if mList.Count = 0 then
    begin
      FModel.SetValue(mIndex, '');
    end
    else
    begin
      FModel.SetValue(mIndex, mList.ToJSON);
    end;
  finally
    mList.Free;
  end;
  UpdateState(mIndex);
end;

procedure TAtlasSettingsDialogFields.JsonChange(Sender: TObject);
var
  mIndex: Integer;
  mText: string;
begin
  mIndex := TMemo(Sender).Tag;
  mText := Trim(TMemo(Sender).Text);
  FRaw[mIndex] := mText;
  FRawValid[mIndex] := (mText = '') or IsJsonValue(mText);
  if mText = '' then
  begin
    FModel.SetValue(mIndex, '');
  end
  else if FRawValid[mIndex] then
  begin
    FModel.SetValue(mIndex, mText);
  end;
  if FRawValid[mIndex] then
  begin
    TMemo(Sender).Font.Color := clWindowText;
  end
  else
  begin
    TMemo(Sender).Font.Color := clRed;
  end;
  UpdateState(mIndex);
end;

procedure TAtlasSettingsDialogFields.BrowseClick(Sender: TObject);
var
  mIndex: Integer;
  mDialog: TSaveDialog;
begin
  mIndex := TButton(Sender).Tag;
  mDialog := TSaveDialog.Create(nil);
  try
    mDialog.Filter := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.ProjectSettingsFileFilter);
    mDialog.Options := mDialog.Options - [ofOverwritePrompt];
    if FRaw[mIndex] <> '' then
    begin
      mDialog.FileName := FRaw[mIndex];
    end;
    if mDialog.Execute and (FFileEdits[mIndex] <> nil) then
    begin
      FFileEdits[mIndex].Text := mDialog.FileName;
    end;
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasSettingsDialogFields.ResetValue(AIndex: Integer);
begin
  FModel.Reset(AIndex);
  FRaw[AIndex] := '';
  FRawValid[AIndex] := True;
end;

procedure TAtlasSettingsDialogFields.ResetClick(Sender: TObject);
begin
  ResetValue(TButton(Sender).Tag);
  // Nicht im Klick des Knopfs neu aufbauen: ShowPage gibt ihn frei.
  TAtlasMainThread.ForceQueue(TAtlasFeature.Settings,
    procedure
    begin
      ShowCurrent;
    end);
end;

function TAtlasSettingsDialogFields.RawProblem(AIndex: Integer): string;
var
  mNumber: Integer;
begin
  Result := '';
  if (FModel.Fields[AIndex].Kind = TAtlasSettingKind.Integer_) and FModel.Typed(AIndex) and (FRaw[AIndex] <> '') and
    not TryStrToInt(FRaw[AIndex], mNumber) then
  begin
    Result := TAtlasSettingsStrings.Fmt(TAtlasSettingsTextId.ProjectSettingsBadNumber, [FModel.Fields[AIndex].Path,
      FRaw[AIndex]]);
  end
  else if not FRawValid[AIndex] then
  begin
    Result := TAtlasSettingsStrings.Fmt(TAtlasSettingsTextId.ProjectSettingsJsonInvalid, [FModel.Fields[AIndex].Path]);
  end;
end;

function TAtlasSettingsDialogFields.RawValid: Boolean;
var
  mIndex: Integer;
  mProblem: string;
begin
  Result := True;
  for mIndex := 0 to FModel.Count - 1 do
  begin
    mProblem := RawProblem(mIndex);
    if mProblem <> '' then
    begin
      MessageBox(Handle, PChar(mProblem), PChar(Caption), MB_ICONWARNING or MB_OK);
      Exit(False);
    end;
  end;
end;

function TAtlasSettingsDialogFields.ServerAccepts: Boolean;
var
  mIssues: TArray<TAtlasSettingIssue>;
  mChecked: Boolean;
  mLines: string;
begin
  Result := True;
  if not FModel.Modified or not Assigned(FOnValidate) then
  begin
    Exit;
  end;
  // Derselbe Parser wie im Server; Fehler verhindern das Speichern, Hinweise fragen nach.
  mIssues := FOnValidate(FModel.ResultText, mChecked);
  if Length(mIssues) = 0 then
  begin
    Exit;
  end;
  mLines := string.Join(sLineBreak, TAtlasSettingsValidation.Lines(mIssues));
  if HasError(mIssues) then
  begin
    MessageBox(Handle,
      PChar(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.ProjectSettingsCheckErrors) + sLineBreak + sLineBreak +
      mLines), PChar(Caption), MB_ICONWARNING or MB_OK);
    Exit(False);
  end;
  Result := MessageBox(Handle,
    PChar(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.ProjectSettingsCheckWarnings) + sLineBreak +
    sLineBreak + mLines), PChar(Caption), MB_ICONQUESTION or MB_YESNO) = IDYES;
end;

function TAtlasSettingsDialogFields.Validate: Boolean;
begin
  Result := RawValid and ServerAccepts;
end;

{ TAtlasProjectSettingsDialog }

constructor TAtlasProjectSettingsDialog.CreateDialog(AOwner: TComponent; AModel: TAtlasSettingsModel;
  const AFileName: string);
begin
  inherited CreateFields(AOwner, AModel, AFileName);
  ValuesReady;
  if Length(FPageNodes) > 0 then
  begin
    SelectNode(FPageNodes[0]);
  end;
end;

procedure TAtlasProjectSettingsDialog.ValuesReady;
begin
  // Ohne Regel-Editor nichts zu lesen.
end;

procedure TAtlasProjectSettingsDialog.ShowGroup(AGroup: Integer);
begin
  // Ohne Regel-Editor gibt es keine Gruppenknoten.
end;

function TAtlasProjectSettingsDialog.SelectRule(const AId: string): Boolean;
begin
  Result := False;
end;

end.
