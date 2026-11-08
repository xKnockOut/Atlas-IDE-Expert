unit Atlas.UI.Settings.Overview;

// Übersicht „Atlas“ unter Tools › Optionen (#1903): oben der Stand der Packages (installiert, eingeschaltet),
// darunter eine Suche über alle Einstellungen. Einen Hauptschalter für ganz Atlas gibt es nicht; die Code Insight
// von Atlas schaltet Base › Allgemein, jedes Modul seinen Modulschalter. Ein Treffer nennt den Knoten, in dem die Einstellung
// steht (Module › <Package> › <Bereich>). Die Einstellungen selbst stehen in den Knoten unter „Module“.
// Reine VCL; den Namen eines Moduls zu seinem Schalter liefert die IDE-Schicht (OnModuleName).

interface

uses
  System.Classes,
  System.SysUtils,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Forms,
  Atlas.Core.Settings.Catalog,
  Atlas.Core.Settings.Groups;

type
  TAtlasSettingsOverview = class(TFrame)
  private const
    cMaxHits = 30;
  private
    FCatalog: TAtlasSettingsCatalog;
    FGroups: TAtlasSettingsGroups;
    FPackages: TLabel;
    FSearch: TEdit;
    FHits: TPanel;
    FOnModuleName: TFunc<string, string>;
    FOnOpen: TProc<string, string>;
    FHitNames: TArray<string>;
    FHitModules: TArray<string>;
    procedure HitClick(Sender: TObject);
    procedure PackagesClick(Sender: TObject);
    class procedure MakeLink(ALabel: TLabel); static;
    procedure AddRow(var ATop: Integer; AControl: TControl; AHeight: Integer);
    procedure SearchChange(Sender: TObject);
    function ModuleName(const ASwitch: string): string;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Stand der Packages: installiert von bekannt, davon eingeschaltet.</summary>
    procedure Load(AInstalled, AKnown, ASwitchedOn: Integer);
    /// <summary>Zum Testen: Zeile mit dem Stand der Packages.</summary>
    function PackagesText: string;
    /// <summary>Text der Suche setzen (Tests) und Treffer zeigen.</summary>
    procedure SearchFor(const AText: string);
    /// <summary>Zum Testen: Zeilen der Treffer.</summary>
    function HitTexts: TArray<string>;
    /// <summary>Zum Testen: Klick auf den Treffer AIndex bzw. auf die Zeile der Packages.</summary>
    procedure ClickHit(AIndex: Integer);
    procedure ClickPackages;
    property OnModuleName: TFunc<string, string> read FOnModuleName write FOnModuleName;
    /// <summary>Klick: Einstellung (Name) und Modulschalter ihres Knotens; Name '' = Knoten „Module“.</summary>
    property OnOpen: TProc<string, string> read FOnOpen write FOnOpen;
  end;

implementation

{$R *.dfm}

uses
  System.UITypes,
  Vcl.Graphics,
  Atlas.Core.Settings.NodeScope,
  Atlas.UI.Strings;

constructor TAtlasSettingsOverview.Create(AOwner: TComponent);
var
  mTop: Integer;
  mLabel: TLabel;
begin
  inherited Create(AOwner);
  FCatalog := TAtlasSettingsCatalog.CreateDefault;
  FGroups := TAtlasSettingsGroups.Create(FCatalog);
  mTop := 12;
  mLabel := TLabel.Create(Self);
  mLabel.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsTitle);
  mLabel.Font.Style := [fsBold];
  AddRow(mTop, mLabel, 24);
  FPackages := TLabel.Create(Self);
  FPackages.ShowAccelChar := False;
  MakeLink(FPackages);
  FPackages.OnClick := PackagesClick;
  AddRow(mTop, FPackages, 30);
  mLabel := TLabel.Create(Self);
  mLabel.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsAtlasSearch);
  AddRow(mTop, mLabel, 20);
  FSearch := TEdit.Create(Self);
  FSearch.OnChange := SearchChange;
  AddRow(mTop, FSearch, 30);
  FHits := TPanel.Create(Self);
  FHits.BevelOuter := bvNone;
  FHits.ParentBackground := True;
  FHits.Parent := Self;
  FHits.Left := 12;
  FHits.Top := mTop;
  FHits.Width := Width - 24;
  FHits.Height := cMaxHits * 20;
  FHits.Anchors := [akLeft, akTop, akRight];
end;

destructor TAtlasSettingsOverview.Destroy;
begin
  FreeAndNil(FGroups);
  FreeAndNil(FCatalog);
  inherited Destroy;
end;

procedure TAtlasSettingsOverview.AddRow(var ATop: Integer; AControl: TControl; AHeight: Integer);
begin
  AControl.Parent := Self;
  AControl.Left := 12;
  AControl.Top := ATop;
  AControl.Width := Width - 24;
  AControl.Anchors := [akLeft, akTop, akRight];
  Inc(ATop, AHeight);
end;

procedure TAtlasSettingsOverview.Load(AInstalled, AKnown, ASwitchedOn: Integer);
begin
  FPackages.Caption := TAtlasStrings.Fmt(TAtlasTextId.SettingsAtlasPackages, [AInstalled, AKnown, ASwitchedOn]);
end;

function TAtlasSettingsOverview.PackagesText: string;
begin
  Result := FPackages.Caption;
end;

function TAtlasSettingsOverview.ModuleName(const ASwitch: string): string;
begin
  Result := '';
  if Assigned(FOnModuleName) then
  begin
    Result := FOnModuleName(ASwitch);
  end;
  if Result = '' then
  begin
    Result := ASwitch;
  end;
  if ASwitch = '' then
  begin
    Result := 'Base';
  end;
end;

procedure TAtlasSettingsOverview.SearchChange(Sender: TObject);
var
  mHits: TArray<TAtlasSettingHit>;
  mHit: TAtlasSettingHit;
  mTop: Integer;
  mLabel: TLabel;
begin
  while FHits.ControlCount > 0 do
  begin
    FHits.Controls[0].Free;
  end;
  FHitNames := nil;
  FHitModules := nil;
  mHits := TAtlasSettingsSearch.Find(FCatalog, FGroups, FSearch.Text, TAtlasStrings.Language = TAtlasLanguage.English,
    cMaxHits);
  mTop := 0;
  for mHit in mHits do
  begin
    mLabel := TLabel.Create(Self);
    mLabel.Parent := FHits;
    mLabel.Left := 0;
    mLabel.Top := mTop;
    mLabel.ShowAccelChar := False;
    mLabel.Caption := TAtlasStrings.Fmt(TAtlasTextId.SettingsAtlasHit,
      [mHit.Caption, TAtlasStrings.Text(TAtlasTextId.SettingsModulesNode), ModuleName(mHit.Module), mHit.AreaCaption]);
    mLabel.Tag := Length(FHitNames);
    MakeLink(mLabel);
    mLabel.OnClick := HitClick;
    FHitNames := FHitNames + [mHit.Name];
    FHitModules := FHitModules + [mHit.Module];
    Inc(mTop, 20);
  end;
  if (Length(mHits) = 0) and (Trim(FSearch.Text) <> '') then
  begin
    mLabel := TLabel.Create(Self);
    mLabel.Parent := FHits;
    mLabel.Left := 0;
    mLabel.Top := 0;
    mLabel.Font.Style := [fsItalic];
    mLabel.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsAtlasNoHits);
  end;
end;

class procedure TAtlasSettingsOverview.MakeLink(ALabel: TLabel);
begin
  ALabel.Cursor := crHandPoint;
  ALabel.Font.Style := ALabel.Font.Style + [fsUnderline];
end;

procedure TAtlasSettingsOverview.HitClick(Sender: TObject);
var
  mIndex: Integer;
begin
  mIndex := (Sender as TComponent).Tag;
  if Assigned(FOnOpen) and (mIndex >= 0) and (mIndex <= High(FHitNames)) then
  begin
    FOnOpen(FHitNames[mIndex], FHitModules[mIndex]);
  end;
end;

procedure TAtlasSettingsOverview.PackagesClick(Sender: TObject);
begin
  if Assigned(FOnOpen) then
  begin
    FOnOpen('', '');
  end;
end;

procedure TAtlasSettingsOverview.ClickHit(AIndex: Integer);
var
  mIndex: Integer;
begin
  for mIndex := FHits.ControlCount - 1 downto 0 do
  begin
    if Assigned(TLabel(FHits.Controls[mIndex]).OnClick) and (FHits.Controls[mIndex].Tag = AIndex) then
    begin
      HitClick(FHits.Controls[mIndex]);
      Exit;
    end;
  end;
end;

procedure TAtlasSettingsOverview.ClickPackages;
begin
  PackagesClick(FPackages);
end;

procedure TAtlasSettingsOverview.SearchFor(const AText: string);
begin
  FSearch.Text := AText;
  SearchChange(FSearch);
end;

function TAtlasSettingsOverview.HitTexts: TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to FHits.ControlCount - 1 do
  begin
    if FHits.Controls[mIndex] is TLabel then
    begin
      Result := Result + [TLabel(FHits.Controls[mIndex]).Caption];
    end;
  end;
end;

end.
