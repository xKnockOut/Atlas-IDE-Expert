unit Atlas.UI.Tracker.SettingsRows;

// Bausteine für den Abschnitt Issue-Tracker im Optionsdialog (#1455):
// - TAtlasTrackerSettingsRows legt Zeilen über IAtlasSettingsSectionHost an
//   (gebundene Felder, eigene Zeilen mit Beschriftung, Knöpfe, Tabellen,
//   Hinweise). Eigene Steuerelemente gehören einem Besitzer, den Detach
//   freigibt; danach legt nichts mehr Zeilen an.
// - TAtlasTrackerSettingsHooks: Haken zur IDE (Token, Prüfung, Projekt, Werte
//   vom Tracker …). Atlas.IDE.Tracker.Settings setzt sie; ohne Haken keine
//   Prüfung, kein Token. Der Abschnitt gibt sie in Close frei (Regel 3).

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Atlas.UI.Settings.Contract,
  Atlas.Core.Tracker.Connections,
  Atlas.Core.Tracker.Projects,
  Atlas.Core.Tracker.Queries,
  Atlas.UI.Settings.ChoiceBox,
  Atlas.UI.Tracker.ValueBox,
  Atlas.UI.Tracker.QueryDialog;

type
  /// <summary>Zustand des Tokens einer Tracker-Verbindung (#1260), ohne Netz.</summary>
  TAtlasTrackerStateEvent = reference to function(const AConnection: TAtlasTrackerConnection): TAtlasTrackerTokenStatus;
  /// <summary>Knopf an einer Tracker-Verbindung (#1260): Token hinterlegen, prüfen, entfernen.</summary>
  TAtlasTrackerConnectionEvent = reference to procedure(const AConnection: TAtlasTrackerConnection);
  /// <summary>„Hinzufügen …“ der Tabelle Projekte (#1261): .dproj bzw. .groupproj (AFolder False) oder Ordner
  /// wählen; False bei Abbruch.</summary>
  TAtlasTrackerBrowseEvent = reference to function(AFolder: Boolean; out APath: string): Boolean;
  /// <summary>„Bearbeiten …“ der Tabelle Abfragen (#1263): AQuery im Dialog ändern; True bei OK. ATaken: Namen der
  /// übrigen Abfragen.</summary>
  TAtlasTrackerQueryEditEvent = reference to function(var AQuery: TAtlasTrackerQuery;
    const AConnections: TArray<TAtlasTrackerConnection>; const ATaken: TArray<string>): Boolean;
  /// <summary>„Werte vom Tracker laden“ (#1266) für AConnection mit dem Zustandsfeld AStateField; das Ergebnis meldet
  /// TrackerValuesDone.</summary>
  TAtlasTrackerValuesEvent = reference to procedure(const AConnection: TAtlasTrackerConnection;
    const AStateField: string);
  /// <summary>„Prüfen“ der Arbeitskopien (#1926): je Ordner Art und Branch im Hintergrund; ADone bekommt je Ordner
  /// eine Zeile (Hauptthread).</summary>
  TAtlasTrackerPathsCheckEvent = reference to procedure(const AFolders: TArray<string>;
    const ADone: TProc<TArray<string>>);
  /// <summary>„Vorschlagen …“ (#1929): Dialog mit Funden für AMapping; True und die angehakten Ordner in APaths bei
  /// „Übernehmen“, True mit leerem APaths nach „Ordner selbst wählen …“.</summary>
  TAtlasTrackerPathsSuggestEvent = reference to function(const AMapping: TAtlasTrackerProjectMapping;
    out APaths: TArray<string>): Boolean;
  /// <summary>Eine Tabelle hat sich geändert; die folgenden bauen neu auf.</summary>
  TAtlasTrackerTableChanged = procedure of object;

  /// <summary>Haken des Abschnitts zur IDE; nil = Knopf gesperrt bzw. Vorgabe.</summary>
  TAtlasTrackerSettingsHooks = class
  private
    FOnState: TAtlasTrackerStateEvent;
    FOnToken: TAtlasTrackerConnectionEvent;
    FOnCheck: TAtlasTrackerConnectionEvent;
    FOnRemove: TAtlasTrackerConnectionEvent;
    FOnTeam: TFunc<TArray<TAtlasTrackerConnection>>;
    FOnValues: TAtlasTrackerValuesEvent;
    FOnQueryTest: TAtlasQueryTestEvent;
    FOnQueryEdit: TAtlasTrackerQueryEditEvent;
    FOnContext: TFunc<TAtlasTrackerProjectContext>;
    FOnBrowse: TAtlasTrackerBrowseEvent;
    FOnCheckPaths: TAtlasTrackerPathsCheckEvent;
    FOnSuggestPaths: TAtlasTrackerPathsSuggestEvent;
  public
    /// <summary>Zustand je Server (ohne Netz); nil = „fehlt“.</summary>
    property OnState: TAtlasTrackerStateEvent read FOnState write FOnState;
    /// <summary>„Token hinterlegen …“ für die gewählte Verbindung; danach baut die Tabelle neu auf.</summary>
    property OnToken: TAtlasTrackerConnectionEvent read FOnToken write FOnToken;
    /// <summary>„Verbindung prüfen“ im Hintergrund; das Ergebnis meldet TrackerCheckDone.</summary>
    property OnCheck: TAtlasTrackerConnectionEvent read FOnCheck write FOnCheck;
    /// <summary>Vor dem Entfernen einer Verbindung: fragt, ob das Token mit entfernt werden soll.</summary>
    property OnRemove: TAtlasTrackerConnectionEvent read FOnRemove write FOnRemove;
    /// <summary>Verbindung aus der .atlas des aktiven Projekts; leer ohne.</summary>
    property OnTeam: TFunc<TArray<TAtlasTrackerConnection>> read FOnTeam write FOnTeam;
    /// <summary>„Werte vom Tracker laden“ (#1266) im Hintergrund; das Ergebnis meldet TrackerValuesDone.</summary>
    property OnValues: TAtlasTrackerValuesEvent read FOnValues write FOnValues;
    /// <summary>„Testen“ im Dialog „Abfrage bearbeiten“ (#1263); nil = Knopf gesperrt.</summary>
    property OnQueryTest: TAtlasQueryTestEvent read FOnQueryTest write FOnQueryTest;
    /// <summary>Statt des Dialogs (Tests); nil = TAtlasTrackerQueryDialog.</summary>
    property OnQueryEdit: TAtlasTrackerQueryEditEvent read FOnQueryEdit write FOnQueryEdit;
    /// <summary>Tabelle Projekte (#1261): aktives Projekt, geöffnete .groupproj und Zeile aus der .atlas.</summary>
    property OnContext: TFunc<TAtlasTrackerProjectContext> read FOnContext write FOnContext;
    /// <summary>„Hinzufügen …“ (#1261); nil = Datei- bzw. Ordnerauswahl von Windows.</summary>
    property OnBrowse: TAtlasTrackerBrowseEvent read FOnBrowse write FOnBrowse;
    /// <summary>„Prüfen“ der Arbeitskopien (#1926); nil = Knopf gesperrt.</summary>
    property OnCheckPaths: TAtlasTrackerPathsCheckEvent read FOnCheckPaths write FOnCheckPaths;
    /// <summary>„Vorschlagen …“ (#1929); nil = kein Knopf (auch mit issues.suggestPaths aus).</summary>
    property OnSuggestPaths: TAtlasTrackerPathsSuggestEvent read FOnSuggestPaths write FOnSuggestPaths;
  end;

  /// <summary>Zeilen des Abschnitts über den Host der Seite.</summary>
  TAtlasTrackerSettingsRows = class
  public const
    cRowHeight = 26;
    cButtonRow = 32;
    cNoteRow = 18;
    cHintRow = 34;
    cListRow = 110;
    cFieldLeft = 90;
    cFieldWidth = 180;
    cWideWidth = 376;
    cButtonWidth = 100;
    cWideButtonWidth = 140;
    cButtonGap = 6;
  private
    FHost: IAtlasSettingsSectionHost;
    FOwner: TComponent;
    function AddLabel(AParent: TWinControl; const ACaption: string): TLabel;
  public
    constructor Create(const AHost: IAtlasSettingsSectionHost);
    destructor Destroy; override;
    /// <summary>Die Seite schließt: eigene Steuerelemente freigeben, den Host vergessen.</summary>
    procedure Detach;
    function Active: Boolean;
    procedure AddTitle(const ACaption: string);
    function AddPanel(AHeight: Integer): TWinControl;
    /// <summary>Eigene Zeile, deren Wert unter AKey steht (Punkt, Zurücksetzen, Sperre).</summary>
    function AddKeyedPanel(AHeight: Integer; const AKey: string): TWinControl;
    function AddCheck(const AKey, ACaption: string): TCheckBox;
    function AddNumber(const AKey, ACaption: string): TEdit;
    function AddText(const AKey, ACaption: string): TEdit;
    function AddChoice(const AKey, ACaption: string; const ACaptions, AValues: TArray<string>): TAtlasChoiceBox;
    /// <summary>Zeile: Beschriftung links, AControl (Breite AWidth) rechts daneben.</summary>
    function AddLabelled(const ACaption: string; AControl: TWinControl; AWidth: Integer): TWinControl;
    /// <summary>Wie AddLabelled, AControl in voller Breite und Höhe AHeight.</summary>
    function AddTallLabelled(const ACaption: string; AControl: TWinControl; AHeight: Integer): TWinControl;
    /// <summary>Knopf in AParent an ALeft.</summary>
    function AddButton(AParent: TWinControl; ALeft, AWidth: Integer; const ACaption: string;
      AClick: TNotifyEvent): TButton;
    /// <summary>Tabelle in voller Größe von AParent; Zeilen erst mit Fenster (ListReady).</summary>
    function AddList(AParent: TWinControl; ASelect: TLVSelectItemEvent): TListView;
    class procedure AddColumn(AList: TListView; const ACaption: string; AWidth: Integer); static;
    /// <summary>Zeile mit einem Hinweis unter den Feldern (Grund, warum eine Eingabe nicht greift) bei AAnchor.
    /// </summary>
    function AddNote(AAnchor: TControl): TLabel;
    /// <summary>Umbrochener grauer Hinweis bei AAnchor.</summary>
    procedure AddHint(const ACaption: string; AAnchor: TControl);
    /// <summary>Klappliste mit Werten vom Tracker in eigener Zeile unter AKey (#1266).</summary>
    function AddValueBox(const AKey, ACaption: string; ALeft: Integer): TAtlasValueBox;
    function NewEdit(AChange: TNotifyEvent): TEdit;
    procedure Attach(ARow, AAnchor: TControl);
    /// <summary>Über den Host: Eine Sperre durch den Hauptschalter bleibt bestehen.</summary>
    procedure Allow(AControl: TControl; AEnabled: Boolean);
    function ListReady(AControl: TWinControl): Boolean;
    function Reveal(const AKey: string): Boolean;
    /// <summary>Fokus auf AControl, wenn es ihn nehmen kann.</summary>
    class procedure Focus(AControl: TWinControl); static;
    property Owner: TComponent read FOwner;
  end;

implementation

uses
  Vcl.Graphics;

const
  cLabelTop = 5;
  cControlTop = 1;
  cButtonTop = 3;

{ TAtlasTrackerSettingsRows }

constructor TAtlasTrackerSettingsRows.Create(const AHost: IAtlasSettingsSectionHost);
begin
  inherited Create;
  FHost := AHost;
  FOwner := TComponent.Create(nil);
end;

destructor TAtlasTrackerSettingsRows.Destroy;
begin
  Detach;
  inherited Destroy;
end;

procedure TAtlasTrackerSettingsRows.Detach;
begin
  FHost := nil;
  // Die Zeilen gehören der Seite; die Elemente darin dem Abschnitt.
  FreeAndNil(FOwner);
end;

function TAtlasTrackerSettingsRows.Active: Boolean;
begin
  Result := FHost <> nil;
end;

procedure TAtlasTrackerSettingsRows.AddTitle(const ACaption: string);
begin
  FHost.AddTitle(ACaption);
end;

function TAtlasTrackerSettingsRows.AddPanel(AHeight: Integer): TWinControl;
begin
  Result := FHost.AddRow(AHeight, nil);
end;

function TAtlasTrackerSettingsRows.AddKeyedPanel(AHeight: Integer; const AKey: string): TWinControl;
begin
  Result := FHost.AddRow(AHeight, TArray<string>.Create(AKey));
end;

function TAtlasTrackerSettingsRows.AddCheck(const AKey, ACaption: string): TCheckBox;
begin
  Result := FHost.AddSwitch(AKey, ACaption) as TCheckBox;
end;

function TAtlasTrackerSettingsRows.AddNumber(const AKey, ACaption: string): TEdit;
begin
  Result := FHost.AddNumber(AKey, ACaption) as TEdit;
end;

function TAtlasTrackerSettingsRows.AddText(const AKey, ACaption: string): TEdit;
begin
  Result := FHost.AddText(AKey, ACaption) as TEdit;
end;

function TAtlasTrackerSettingsRows.AddChoice(const AKey, ACaption: string;
  const ACaptions, AValues: TArray<string>): TAtlasChoiceBox;
begin
  Result := FHost.AddChoice(AKey, ACaption, ACaptions, AValues) as TAtlasChoiceBox;
end;

function TAtlasTrackerSettingsRows.AddLabel(AParent: TWinControl; const ACaption: string): TLabel;
begin
  Result := TLabel.Create(FOwner);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.Left := 0;
  Result.Top := cLabelTop;
end;

function TAtlasTrackerSettingsRows.AddLabelled(const ACaption: string; AControl: TWinControl;
  AWidth: Integer): TWinControl;
begin
  Result := AddPanel(cRowHeight);
  AddLabel(Result, ACaption + ':');
  AControl.Parent := Result;
  AControl.Left := cFieldLeft;
  AControl.Top := cControlTop;
  AControl.Width := AWidth;
  if AWidth >= cWideWidth then
  begin
    AControl.Anchors := [akLeft, akTop, akRight];
  end;
end;

function TAtlasTrackerSettingsRows.AddTallLabelled(const ACaption: string; AControl: TWinControl;
  AHeight: Integer): TWinControl;
begin
  Result := AddPanel(AHeight);
  AddLabel(Result, ACaption + ':');
  AControl.Parent := Result;
  AControl.Left := cFieldLeft;
  AControl.Top := cControlTop;
  AControl.Width := cWideWidth;
  AControl.Height := AHeight - cControlTop - cControlTop;
  AControl.Anchors := [akLeft, akTop, akRight];
end;

function TAtlasTrackerSettingsRows.AddButton(AParent: TWinControl; ALeft, AWidth: Integer; const ACaption: string;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(FOwner);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.Left := ALeft;
  Result.Top := cButtonTop;
  Result.Width := AWidth;
  Result.OnClick := AClick;
end;

function TAtlasTrackerSettingsRows.AddList(AParent: TWinControl; ASelect: TLVSelectItemEvent): TListView;
begin
  Result := TListView.Create(FOwner);
  Result.Parent := AParent;
  Result.Align := alClient;
  Result.ViewStyle := vsReport;
  Result.ReadOnly := True;
  Result.RowSelect := True;
  Result.HideSelection := False;
  Result.OnSelectItem := ASelect;
end;

class procedure TAtlasTrackerSettingsRows.AddColumn(AList: TListView; const ACaption: string; AWidth: Integer);
var
  mColumn: TListColumn;
begin
  mColumn := AList.Columns.Add;
  mColumn.Caption := ACaption;
  mColumn.Width := AWidth;
end;

function TAtlasTrackerSettingsRows.AddNote(AAnchor: TControl): TLabel;
var
  mPanel: TWinControl;
begin
  mPanel := AddPanel(cNoteRow);
  Result := TLabel.Create(FOwner);
  Result.Parent := mPanel;
  Result.Left := cFieldLeft;
  Result.Top := cControlTop;
  Result.Font.Color := clRed;
  Attach(mPanel, AAnchor);
end;

procedure TAtlasTrackerSettingsRows.AddHint(const ACaption: string; AAnchor: TControl);
var
  mPanel: TWinControl;
  mHint: TLabel;
begin
  mPanel := AddPanel(cHintRow);
  mHint := TLabel.Create(FOwner);
  mHint.Parent := mPanel;
  mHint.Align := alClient;
  mHint.WordWrap := True;
  mHint.Font.Color := clGrayText;
  mHint.Caption := ACaption;
  Attach(mPanel, AAnchor);
end;

function TAtlasTrackerSettingsRows.AddValueBox(const AKey, ACaption: string; ALeft: Integer): TAtlasValueBox;
var
  mPanel: TWinControl;
begin
  mPanel := AddKeyedPanel(cRowHeight, AKey);
  AddLabel(mPanel, ACaption);
  Result := TAtlasValueBox.Create(FOwner);
  Result.Parent := mPanel;
  Result.Left := ALeft;
  Result.Top := cControlTop;
  Result.Width := cFieldWidth;
end;

function TAtlasTrackerSettingsRows.NewEdit(AChange: TNotifyEvent): TEdit;
begin
  Result := TEdit.Create(FOwner);
  Result.OnChange := AChange;
end;

procedure TAtlasTrackerSettingsRows.Attach(ARow, AAnchor: TControl);
begin
  FHost.Attach(ARow, AAnchor);
end;

procedure TAtlasTrackerSettingsRows.Allow(AControl: TControl; AEnabled: Boolean);
begin
  if FHost <> nil then
  begin
    FHost.Allow(AControl, AEnabled);
  end
  else
  begin
    AControl.Enabled := AEnabled;
  end;
end;

function TAtlasTrackerSettingsRows.ListReady(AControl: TWinControl): Boolean;
begin
  Result := (FHost <> nil) and FHost.ListReady(AControl);
end;

function TAtlasTrackerSettingsRows.Reveal(const AKey: string): Boolean;
begin
  Result := (FHost <> nil) and FHost.Reveal(AKey);
end;

class procedure TAtlasTrackerSettingsRows.Focus(AControl: TWinControl);
begin
  if AControl.CanFocus and AControl.Showing then
  begin
    AControl.SetFocus;
  end;
end;

end.
