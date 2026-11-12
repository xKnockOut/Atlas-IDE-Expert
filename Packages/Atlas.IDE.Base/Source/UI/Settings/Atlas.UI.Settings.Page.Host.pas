unit Atlas.UI.Settings.Page.Host;

// Mittlere Stufe der Optionsseite „Atlas“ (#227): Teile der Seite (je Bereich eine Klasse), Bindung der Elemente an
// Plugin-Einstellungen, Markierung (Punkte, Zurücksetzen), Sprungziele (#628), zusammengehörige Zeilen und eigene
// Sperren der Elemente. Die Teile kennen nur diese Stufe; Baum, Knoten und die Sperren durch Hauptschalter liefert
// die Seite über die abstrakten Methoden.

interface

uses
  System.Classes,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.Forms,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.Catalog,
  Atlas.UI.Strings,
  Atlas.UI.Settings.ChoiceBox,
  Atlas.UI.Settings.Bindings,
  Atlas.UI.Settings.Marks,
  Atlas.UI.Settings.Page.Sheets;

const
  cPartMissing = 'Teil %s fehlt auf der Optionsseite'; // german-ok: Programmierfehler, nie in der Oberfläche

type
  TAtlasSettingsPageHost = class;

  /// <summary>Teil der Seite: baut die Elemente eines Bereichs, lädt und speichert sie. Die Bausteine (AddCheck,
  /// BindCheck …) reicht er an die Seite weiter, die Elemente gehören der Seite.</summary>
  TAtlasSettingsPagePart = class
  protected
    FPage: TAtlasSettingsPageHost;
    procedure AddSheet(AId: TAtlasTextId);
    function AddCheck(const ACaption: string): TCheckBox;
    function AddPanel(AHeight: Integer): TWinControl;
    function AddNumber(const ACaption: string): TEdit;
    function AddChoice(const ACaption: string; const AItems: array of string): TAtlasChoiceBox;
    procedure AddTitle(AId: TAtlasTextId);
    function AddKey(const ACaption: string): TEdit;
    function AddWrappedLabel(AHeight: Integer; const ACaption: string): TLabel;
    function AddTextLine(const ACaption: string): TEdit;
    function AddFieldRow(AId: TAtlasTextId; AControl: TWinControl; AWidth: Integer): TWinControl;
    function AddRowButton(AParent: TWinControl; ALeft, AWidth: Integer; AId: TAtlasTextId;
      AClick: TNotifyEvent): TButton;
    function ListReady(AControl: TWinControl): Boolean;
    function BindCheck(const AName: string; AControl: TCheckBox): TCheckBox;
    function BindText(const AName: string; AControl: TEdit): TEdit;
    function BindKey(const AName: string; AControl: TEdit): TEdit;
    procedure Attach(ARow, AAnchor: TControl);
    procedure Allow(AControl: TControl; AValue: Boolean);
  public
    constructor Create(APage: TAtlasSettingsPageHost);
    /// <summary>Werte ohne generische Bindung (Auswahl aus Namen, Listen aus Haken, abgeleitete Felder).</summary>
    procedure Load(const ASettings: TAtlasPluginSettings); virtual;
    procedure Save(var ASettings: TAtlasPluginSettings); virtual;
    /// <summary>Markierung (Punkt, Zurücksetzen) der Elemente ohne generische Bindung; nach dem Aufbau.</summary>
    procedure BindMarks; virtual;
    /// <summary>Die Seite hat ein Fenster: Listen füllen.</summary>
    procedure WindowReady; virtual;
    procedure SheetShown(ASheet: TTabSheet); virtual;
    /// <summary>Eigene Knoten im Baum, nachdem die Seite die Bereiche verteilt hat.</summary>
    procedure AddNodePages; virtual;
  end;

  TAtlasSettingsPageHost = class(TAtlasSettingsPageSheets)
  protected
    /// <summary>Teile in der Reihenfolge des Aufbaus; Laden und Speichern folgen ihr.</summary>
    FParts: TObjectList<TAtlasSettingsPagePart>;
    /// <summary>Einfache Elemente der Seite an ihren Plugin-Einstellungen: Laden und Speichern über den Namen.
    /// </summary>
    FBindings: TAtlasSettingsBindings;
    /// <summary>Schlüssel und Steuerelement für Reveal (#628).</summary>
    FRevealKeys: TArray<string>;
    FRevealControls: TArray<TControl>;
    FMarks: TAtlasSettingsMarks;
    FCatalog: TAtlasSettingsCatalog;
    /// <summary>Zeile ohne eigene Einstellung → Element, zu dem sie gehört (Liste und Knöpfe einer Funktion).</summary>
    FAttached: TDictionary<TControl, TControl>;
    /// <summary>Von der Seite selbst abgeschaltet (Liste leer, kein Server); bleibt aus, auch ohne Sperre.</summary>
    FOwnOff: TList<TControl>;
    /// <summary>Durch einen Hauptschalter gesperrt.</summary>
    FLockedControls: TList<TControl>;
    /// <summary>Zeilen der Abschnitte eines Moduls → Id des Moduls (#1903: Knoten je Package).</summary>
    FSectionOwners: TDictionary<TControl, string>;
  private
    procedure MarksChanged(Sender: TObject);
    procedure MarksResetPage(Sender: TObject);
  protected
    /// <summary>Freigegebene Zeilen aus FSectionOwners nehmen (Abschnitt eines Moduls geschlossen).</summary>
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Teil der Klasse T; jeder Teil steht einmal auf der Seite.</summary>
    function Part<T: TAtlasSettingsPagePart>: T;
    procedure AddPart(APart: TAtlasSettingsPagePart);
    /// <summary>AControl hat der Abschnitt des Moduls AOwnerId angelegt (#1903).</summary>
    procedure MarkSectionOwner(AControl: TControl; const AOwnerId: string);
    /// <summary>Module, deren Abschnitte AControl oder eins seiner Elemente angelegt haben.</summary>
    function SectionOwnersIn(AControl: TControl): TArray<string>;
    /// <summary>ARow (ohne eigene Einstellung) gehört zur Funktion von AAnchor: gleicher Rahmen, gleiche Sperre.
    /// </summary>
    procedure Attach(ARow, AAnchor: TControl);
    procedure SetLocked(AControl: TControl; ALocked: Boolean);
    /// <summary>Statt Enabled := AValue: Eine Sperre durch den Hauptschalter bleibt bestehen.</summary>
    procedure Allow(AControl: TControl; AValue: Boolean);
    procedure Bind(const AKey: string; AControl: TControl);
    /// <summary>Bindet AControl an die Plugin-Einstellung AName (Registry-Name); liefert AControl.</summary>
    function BindCheck(const AName: string; AControl: TCheckBox): TCheckBox;
    function BindText(const AName: string; AControl: TEdit): TEdit;
    function BindKey(const AName: string; AControl: TEdit): TEdit;
    procedure BindValues(ABindings: TAtlasSettingsBindings; const AName: string; AControl: TControl;
      AKind: TAtlasSettingsBindingKind; const AValues: TArray<string>);
    function Catalog: TAtlasSettingsCatalog;
    /// <summary>Gebundenes Element der Einstellung AName (Registry-Name); nil ohne (Modul fehlt).</summary>
    function ControlOfSetting(const AName: string): TControl;
    /// <summary>Steuerelement zu AKey; nil, wenn die Seite den Schlüssel nicht kennt.</summary>
    function ControlOf(const AKey: string): TControl;
    function PageOf(AControl: TControl): Integer; virtual; abstract;
    procedure SelectPage(AIndex: Integer); virtual; abstract;
    procedure RefreshMarks; virtual; abstract;
    procedure LoadFrom(const ASettings: TAtlasPluginSettings); virtual; abstract;
    function CurrentSettings: TAtlasPluginSettings; virtual; abstract;
    procedure ResetPage; virtual; abstract;
    procedure ResetNames(const ANames: TArray<string>); virtual; abstract;
    /// <summary>Kasten der Seite des Knotens ANode im Bereich AArea; legt sie bei Bedarf an.</summary>
    function NodeBox(AArea: Integer; const ANode, ACaption: string): TScrollBox; virtual; abstract;
    /// <summary>Zeigt die Einstellung AKey (Name der Plugin-Einstellung, #628): Reiter, ins Bild rollen, Fokus,
    /// Zeile fett. False, wenn die Seite den Schlüssel nicht kennt.</summary>
    function Reveal(const AKey: string): Boolean; virtual; abstract;
    /// <summary>Zum Testen: Übertragen (#723).</summary>
    property Marks: TAtlasSettingsMarks read FMarks;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Settings.Group;

{ TAtlasSettingsPagePart }

constructor TAtlasSettingsPagePart.Create(APage: TAtlasSettingsPageHost);
begin
  inherited Create;
  FPage := APage;
end;

procedure TAtlasSettingsPagePart.AddSheet(AId: TAtlasTextId);
begin
  FPage.AddSheet(AId);
end;

function TAtlasSettingsPagePart.AddCheck(const ACaption: string): TCheckBox;
begin
  Result := FPage.AddCheck(ACaption);
end;

function TAtlasSettingsPagePart.AddPanel(AHeight: Integer): TWinControl;
begin
  Result := FPage.AddPanel(AHeight);
end;

function TAtlasSettingsPagePart.AddNumber(const ACaption: string): TEdit;
begin
  Result := FPage.AddNumber(ACaption);
end;

function TAtlasSettingsPagePart.AddChoice(const ACaption: string; const AItems: array of string): TAtlasChoiceBox;
begin
  Result := FPage.AddChoice(ACaption, AItems);
end;

procedure TAtlasSettingsPagePart.AddTitle(AId: TAtlasTextId);
begin
  FPage.AddTitle(AId);
end;

function TAtlasSettingsPagePart.AddKey(const ACaption: string): TEdit;
begin
  Result := FPage.AddKey(ACaption);
end;

function TAtlasSettingsPagePart.AddWrappedLabel(AHeight: Integer; const ACaption: string): TLabel;
begin
  Result := FPage.AddWrappedLabel(AHeight, ACaption);
end;

function TAtlasSettingsPagePart.AddTextLine(const ACaption: string): TEdit;
begin
  Result := FPage.AddTextLine(ACaption);
end;

function TAtlasSettingsPagePart.AddFieldRow(AId: TAtlasTextId; AControl: TWinControl; AWidth: Integer): TWinControl;
begin
  Result := FPage.AddFieldRow(AId, AControl, AWidth);
end;

function TAtlasSettingsPagePart.AddRowButton(AParent: TWinControl; ALeft, AWidth: Integer; AId: TAtlasTextId;
  AClick: TNotifyEvent): TButton;
begin
  Result := FPage.AddRowButton(AParent, ALeft, AWidth, AId, AClick);
end;

function TAtlasSettingsPagePart.ListReady(AControl: TWinControl): Boolean;
begin
  Result := FPage.ListReady(AControl);
end;

function TAtlasSettingsPagePart.BindCheck(const AName: string; AControl: TCheckBox): TCheckBox;
begin
  Result := FPage.BindCheck(AName, AControl);
end;

function TAtlasSettingsPagePart.BindText(const AName: string; AControl: TEdit): TEdit;
begin
  Result := FPage.BindText(AName, AControl);
end;

function TAtlasSettingsPagePart.BindKey(const AName: string; AControl: TEdit): TEdit;
begin
  Result := FPage.BindKey(AName, AControl);
end;

procedure TAtlasSettingsPagePart.Attach(ARow, AAnchor: TControl);
begin
  FPage.Attach(ARow, AAnchor);
end;

procedure TAtlasSettingsPagePart.Allow(AControl: TControl; AValue: Boolean);
begin
  FPage.Allow(AControl, AValue);
end;

procedure TAtlasSettingsPagePart.Load(const ASettings: TAtlasPluginSettings);
begin
  // Ohne eigene Werte: alles über die generische Bindung.
end;

procedure TAtlasSettingsPagePart.Save(var ASettings: TAtlasPluginSettings);
begin
  // Ohne eigene Werte: alles über die generische Bindung.
end;

procedure TAtlasSettingsPagePart.BindMarks;
begin
  // Ohne eigene Elemente: Die generische Bindung markiert.
end;

procedure TAtlasSettingsPagePart.WindowReady;
begin
  // Ohne Listen, die ein Fenster brauchen.
end;

procedure TAtlasSettingsPagePart.SheetShown(ASheet: TTabSheet);
begin
  // Kein Reiter, der beim ersten Zeigen etwas abfragt.
end;

procedure TAtlasSettingsPagePart.AddNodePages;
begin
  // Keine eigenen Knoten.
end;

{ TAtlasSettingsPageHost }

constructor TAtlasSettingsPageHost.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FParts := TObjectList<TAtlasSettingsPagePart>.Create;
  FAttached := TDictionary<TControl, TControl>.Create;
  FBindings := TAtlasSettingsBindings.Create;
  FOwnOff := TList<TControl>.Create;
  FLockedControls := TList<TControl>.Create;
  FSectionOwners := TDictionary<TControl, string>.Create;
  FMarks := TAtlasSettingsMarks.Create(Self);
  FMarks.OnChanged := MarksChanged;
  FMarks.OnResetPage := MarksResetPage;
  FMarks.OnReset :=
    procedure(ANames: TArray<string>)
    begin
      ResetNames(ANames);
    end;
end;

destructor TAtlasSettingsPageHost.Destroy;
begin
  // Ereignisse der Elemente zeigen auf Methoden der Teile: Mit csDestroying melden die Elemente nichts mehr.
  Destroying;
  FreeAndNil(FParts);
  FreeAndNil(FCatalog);
  FreeAndNil(FAttached);
  FreeAndNil(FOwnOff);
  FreeAndNil(FLockedControls);
  FreeAndNil(FSectionOwners);
  FreeAndNil(FBindings);
  inherited Destroy;
end;

procedure TAtlasSettingsPageHost.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (FSectionOwners <> nil) and (AComponent is TControl) then
  begin
    FSectionOwners.Remove(TControl(AComponent));
  end;
end;

procedure TAtlasSettingsPageHost.MarkSectionOwner(AControl: TControl; const AOwnerId: string);
begin
  FSectionOwners.AddOrSetValue(AControl, AOwnerId);
  AControl.FreeNotification(Self);
end;

function TAtlasSettingsPageHost.SectionOwnersIn(AControl: TControl): TArray<string>;
var
  mPair: TPair<TControl, string>;
  mParent: TControl;
begin
  Result := nil;
  for mPair in FSectionOwners do
  begin
    mParent := mPair.Key;
    while (mParent <> nil) and (mParent <> AControl) do
    begin
      mParent := mParent.Parent;
    end;
    if mParent <> nil then
    begin
      Result := Result + [mPair.Value];
    end;
  end;
end;

function TAtlasSettingsPageHost.Part<T>: T;
var
  mPart: TAtlasSettingsPagePart;
begin
  for mPart in FParts do
  begin
    if mPart is T then
    begin
      Exit(T(mPart));
    end;
  end;
  raise EInvalidOperation.CreateFmt(cPartMissing, [T.ClassName]);
end;

procedure TAtlasSettingsPageHost.AddPart(APart: TAtlasSettingsPagePart);
begin
  FParts.Add(APart);
end;

procedure TAtlasSettingsPageHost.MarksResetPage(Sender: TObject);
begin
  ResetPage;
end;

procedure TAtlasSettingsPageHost.Bind(const AKey: string; AControl: TControl);
begin
  if AControl = nil then
  begin
    Exit;
  end;
  FRevealKeys := FRevealKeys + [AKey];
  FRevealControls := FRevealControls + [AControl];
end;

function TAtlasSettingsPageHost.ControlOf(const AKey: string): TControl;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FRevealKeys) do
  begin
    if SameText(FRevealKeys[mIndex], AKey) then
    begin
      Exit(FRevealControls[mIndex]);
    end;
  end;
  Result := nil;
end;

function TAtlasSettingsPageHost.Catalog: TAtlasSettingsCatalog;
begin
  if FCatalog = nil then
  begin
    FCatalog := TAtlasSettingsCatalog.CreateDefault;
  end;
  Result := FCatalog;
end;

procedure TAtlasSettingsPageHost.MarksChanged(Sender: TObject);
begin
  RefreshMarks;
end;

procedure TAtlasSettingsPageHost.Attach(ARow, AAnchor: TControl);
begin
  if (ARow <> nil) and (AAnchor <> nil) then
  begin
    FAttached.AddOrSetValue(ARow, AAnchor);
  end;
end;

procedure TAtlasSettingsPageHost.SetLocked(AControl: TControl; ALocked: Boolean);
var
  mIndex: Integer;
begin
  if AControl = nil then
  begin
    Exit;
  end;
  if not ALocked then
  begin
    FLockedControls.Remove(AControl);
  end
  else if not FLockedControls.Contains(AControl) then
  begin
    FLockedControls.Add(AControl);
  end;
  AControl.Enabled := not ALocked and not FOwnOff.Contains(AControl);
  if (AControl is TWinControl) and not (AControl is TAtlasSettingsGroup) then
  begin
    for mIndex := 0 to TWinControl(AControl).ControlCount - 1 do
    begin
      SetLocked(TWinControl(AControl).Controls[mIndex], ALocked);
    end;
  end;
end;

procedure TAtlasSettingsPageHost.Allow(AControl: TControl; AValue: Boolean);
begin
  // Eigene Logik der Seite (Liste leer, Server fehlt); eine Sperre durch den Hauptschalter bleibt bestehen.
  if AValue then
  begin
    FOwnOff.Remove(AControl);
  end
  else if not FOwnOff.Contains(AControl) then
  begin
    FOwnOff.Add(AControl);
  end;
  AControl.Enabled := AValue and not FLockedControls.Contains(AControl);
end;

procedure TAtlasSettingsPageHost.BindValues(ABindings: TAtlasSettingsBindings; const AName: string; AControl: TControl;
  AKind: TAtlasSettingsBindingKind; const AValues: TArray<string>);
begin
  ABindings.Add(AName, AControl, AKind, AValues);
  Bind(AName, AControl);
end;

function TAtlasSettingsPageHost.BindCheck(const AName: string; AControl: TCheckBox): TCheckBox;
begin
  BindValues(FBindings, AName, AControl, sbkCheck, nil);
  Result := AControl;
end;

function TAtlasSettingsPageHost.BindText(const AName: string; AControl: TEdit): TEdit;
begin
  BindValues(FBindings, AName, AControl, sbkText, nil);
  Result := AControl;
end;

function TAtlasSettingsPageHost.BindKey(const AName: string; AControl: TEdit): TEdit;
begin
  BindValues(FBindings, AName, AControl, sbkShortcut, nil);
  Result := AControl;
end;

function TAtlasSettingsPageHost.ControlOfSetting(const AName: string): TControl;
begin
  Result := FMarks.ControlOfName(AName);
end;

end.
