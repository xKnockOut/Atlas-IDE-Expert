unit Atlas.UI.VersionControl.SettingsPart;

// Bausteine der Seite „Versionsverwaltung“ im Optionsdialog (#1905, vorher Teile der Optionsseite von Base):
// - TAtlasVcsSettingsPart: ein Teil der Seite (Art, Programme, Projekt, Projekte, Server, Branches). Die Bausteine
//   AddTitle, AddPanel, AddFieldRow … legen Zeilen über IAtlasSettingsSectionHost an; gebundene Felder lädt und
//   speichert Base, eigene Zeilen liest und schreibt der Teil über IAtlasSettingsValues.
// - TAtlasVcsSettingsOwner: Besitzer der eigenen Steuerelemente eines Abschnitts (freigegeben in Close) und Zugang
//   zu den anderen Teilen (Part<T>) und zur Seite (Host).

interface

uses
  System.Classes,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Atlas.Core.Settings.Contract,
  Atlas.UI.Strings,
  Atlas.UI.Settings.Contract,
  Atlas.UI.Settings.ChoiceBox;

const
  cVcsButtonGap = 6;

type
  TAtlasVcsSettingsPart = class;

  TAtlasVcsSettingsOwner = class(TComponent)
  private
    FHost: IAtlasSettingsSectionHost;
    FParts: TList<TAtlasVcsSettingsPart>;
  public
    constructor CreateFor(const AHost: IAtlasSettingsSectionHost; AParts: TList<TAtlasVcsSettingsPart>);
    /// <summary>Teil der Klasse T; jeder Teil steht einmal im Abschnitt.</summary>
    function Part<T: TAtlasVcsSettingsPart>: T;
    /// <summary>Ein Wert in einer eigenen Zeile hat sich geändert: Punkte und Sperren neu.</summary>
    procedure RefreshMarks;
    property Host: IAtlasSettingsSectionHost read FHost;
  end;

  TAtlasVcsSettingsPart = class
  protected
    /// <summary>Besitzer der eigenen Steuerelemente; nil vor Build und nach Close.</summary>
    FPage: TAtlasVcsSettingsOwner;
    function Host: IAtlasSettingsSectionHost;
    procedure AddTitle(AId: TAtlasTextId);
    /// <summary>Eigene Zeile; AKeys: Schlüssel, die der Teil darin selbst liest und schreibt.</summary>
    function AddPanel(AHeight: Integer): TWinControl; overload;
    function AddPanel(AHeight: Integer; const AKeys: TArray<string>): TWinControl; overload;
    function AddWrappedLabel(AHeight: Integer; const ACaption: string): TLabel;
    /// <summary>Zeile mit Beschriftung links und AControl daneben.</summary>
    function AddFieldRow(AId: TAtlasTextId; AControl: TWinControl; AWidth: Integer): TWinControl;
    function AddRowButton(AParent: TWinControl; ALeft, AWidth: Integer; AId: TAtlasTextId;
      AClick: TNotifyEvent): TButton;
    class procedure AddListColumn(AList: TListView; AId: TAtlasTextId; AWidth: Integer); static;
    /// <summary>Auswahl an AKey, gespeichert als AValues in derselben Reihenfolge wie ACaptions.</summary>
    function AddChoice(const AKey: string; ACaption: TAtlasTextId; const ACaptions: array of TAtlasTextId;
      const AValues: TArray<string>): TAtlasChoiceBox;
    procedure Allow(AControl: TControl; AValue: Boolean);
    procedure Attach(ARow, AAnchor: TControl);
    function ListReady(AControl: TWinControl): Boolean;
  public
    /// <summary>Zeilen anlegen; FPage ist gesetzt.</summary>
    procedure Build; virtual;
    procedure Load(const AValues: IAtlasSettingsValues); virtual;
    procedure Save(const AValues: IAtlasSettingsValues); virtual;
    /// <summary>Die Seite hat ein Fenster: Listen füllen; alle Abschnitte sind gebaut.</summary>
    procedure WindowReady; virtual;
    /// <summary>Vor Build bzw. nach Close: Besitzer setzen bzw. lösen.</summary>
    procedure Attached(APage: TAtlasVcsSettingsOwner); virtual;
  end;

implementation

uses
  System.SysUtils;

const
  cRowButtonTop = 3;

{ TAtlasVcsSettingsOwner }

constructor TAtlasVcsSettingsOwner.CreateFor(const AHost: IAtlasSettingsSectionHost;
  AParts: TList<TAtlasVcsSettingsPart>);
begin
  inherited Create(nil);
  FHost := AHost;
  FParts := AParts;
end;

function TAtlasVcsSettingsOwner.Part<T>: T;
var
  mPart: TAtlasVcsSettingsPart;
begin
  for mPart in FParts do
  begin
    if mPart is T then
    begin
      Exit(T(mPart));
    end;
  end;
  raise EArgumentException.CreateFmt('Teil %s fehlt im Abschnitt Versionsverwaltung', // german-ok: Programmierfehler
    [T.ClassName]);
end;

procedure TAtlasVcsSettingsOwner.RefreshMarks;
begin
  if FHost <> nil then
  begin
    FHost.Changed;
  end;
end;

{ TAtlasVcsSettingsPart }

function TAtlasVcsSettingsPart.Host: IAtlasSettingsSectionHost;
begin
  Result := FPage.Host;
end;

procedure TAtlasVcsSettingsPart.AddTitle(AId: TAtlasTextId);
begin
  Host.AddTitle(TAtlasStrings.Text(AId));
end;

function TAtlasVcsSettingsPart.AddPanel(AHeight: Integer): TWinControl;
begin
  Result := Host.AddRow(AHeight, nil);
end;

function TAtlasVcsSettingsPart.AddPanel(AHeight: Integer; const AKeys: TArray<string>): TWinControl;
begin
  Result := Host.AddRow(AHeight, AKeys);
end;

function TAtlasVcsSettingsPart.AddWrappedLabel(AHeight: Integer; const ACaption: string): TLabel;
begin
  Result := Host.AddHint(ACaption, AHeight) as TLabel;
end;

function TAtlasVcsSettingsPart.AddFieldRow(AId: TAtlasTextId; AControl: TWinControl; AWidth: Integer): TWinControl;
var
  mCaption: TLabel;
begin
  Result := AddPanel(26);
  mCaption := TLabel.Create(FPage);
  mCaption.Parent := Result;
  mCaption.Caption := TAtlasStrings.Text(AId) + ':';
  mCaption.Left := 0;
  mCaption.Top := 5;
  AControl.Parent := Result;
  AControl.Left := 90;
  AControl.Top := 1;
  AControl.Width := AWidth;
end;

function TAtlasVcsSettingsPart.AddRowButton(AParent: TWinControl; ALeft, AWidth: Integer; AId: TAtlasTextId;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(FPage);
  Result.Parent := AParent;
  Result.Caption := TAtlasStrings.Text(AId);
  Result.Left := ALeft;
  Result.Top := cRowButtonTop;
  Result.Width := AWidth;
  Result.OnClick := AClick;
end;

class procedure TAtlasVcsSettingsPart.AddListColumn(AList: TListView; AId: TAtlasTextId; AWidth: Integer);
var
  mColumn: TListColumn;
begin
  mColumn := AList.Columns.Add;
  mColumn.Caption := TAtlasStrings.Text(AId);
  mColumn.Width := AWidth;
end;

function TAtlasVcsSettingsPart.AddChoice(const AKey: string; ACaption: TAtlasTextId;
  const ACaptions: array of TAtlasTextId; const AValues: TArray<string>): TAtlasChoiceBox;
var
  mCaptions: TArray<string>;
  mIndex: Integer;
begin
  SetLength(mCaptions, Length(ACaptions));
  for mIndex := 0 to High(ACaptions) do
  begin
    mCaptions[mIndex] := TAtlasStrings.Text(ACaptions[mIndex]);
  end;
  Result := Host.AddChoice(AKey, TAtlasStrings.Text(ACaption), mCaptions, AValues) as TAtlasChoiceBox;
end;

procedure TAtlasVcsSettingsPart.Allow(AControl: TControl; AValue: Boolean);
begin
  if (FPage <> nil) and (AControl <> nil) then
  begin
    Host.Allow(AControl, AValue);
  end;
end;

procedure TAtlasVcsSettingsPart.Attach(ARow, AAnchor: TControl);
begin
  Host.Attach(ARow, AAnchor);
end;

function TAtlasVcsSettingsPart.ListReady(AControl: TWinControl): Boolean;
begin
  Result := (FPage <> nil) and Host.ListReady(AControl);
end;

procedure TAtlasVcsSettingsPart.Build;
begin
  // Ohne eigene Zeilen.
end;

procedure TAtlasVcsSettingsPart.Load(const AValues: IAtlasSettingsValues);
begin
  // Gebundene Felder lädt die Seite selbst.
end;

procedure TAtlasVcsSettingsPart.Save(const AValues: IAtlasSettingsValues);
begin
  // Gebundene Felder speichert die Seite selbst.
end;

procedure TAtlasVcsSettingsPart.WindowReady;
begin
  // Ohne Listen.
end;

procedure TAtlasVcsSettingsPart.Attached(APage: TAtlasVcsSettingsOwner);
begin
  FPage := APage;
end;

end.
