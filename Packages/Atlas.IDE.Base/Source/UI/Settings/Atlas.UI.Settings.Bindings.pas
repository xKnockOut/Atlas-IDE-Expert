unit Atlas.UI.Settings.Bindings;

// Bindung der Steuerelemente der Optionsseite an Plugin-Einstellungen (#227, #1455): Jedes gebundene Element steht
// einmal mit dem Registry-Namen seiner Einstellung in der Liste; Laden und Speichern laufen über einen Speicher mit
// den Werten von TAtlasPluginSettings (TAtlasMemorySettingsStore.FromSettings, danach TAtlasPluginSettings.Load).
// So steht eine einfache Einstellung nicht mehr als Feld, Laden und Speichern einzeln auf der Seite.
// Arten: Haken (0/1), Text (Zahlen bleiben Zahlen, sonst Text; beim Speichern ohne Leerraum am Rand),
// Tastenkürzel (Zahl im Speicher, Text wie „Strg+K“ im Feld) und Auswahl (gespeicherte Werte je Eintrag).

interface

uses
  System.Generics.Collections,
  Vcl.Controls,
  Atlas.Core.Settings.History;

type
  TAtlasSettingsBindingKind = (sbkCheck, sbkText, sbkShortcut, sbkChoice);

  /// <summary>Element an einer Plugin-Einstellung: Registry-Name, Element, Art, bei einer Auswahl die gespeicherten
  /// Werte je Eintrag.</summary>
  TAtlasSettingsValueBinding = record
    Name: string;
    Control: TControl;
    Kind: TAtlasSettingsBindingKind;
    Values: TArray<string>;
  end;

  TAtlasSettingsBindings = class
  private
    FItems: TList<TAtlasSettingsValueBinding>;
    class procedure LoadOne(const AStore: IAtlasMemorySettingsStore; const ABinding: TAtlasSettingsValueBinding); static;
    class procedure SaveOne(const AStore: IAtlasMemorySettingsStore; const ABinding: TAtlasSettingsValueBinding); static;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>AControl muss zur Art passen: TCheckBox (Haken), TEdit (Text, Tastenkürzel), TAtlasChoiceBox
    /// (Auswahl, AValues gleich lang wie die Einträge).</summary>
    procedure Add(const AName: string; AControl: TControl; AKind: TAtlasSettingsBindingKind;
      const AValues: TArray<string>);
    procedure Load(const AStore: IAtlasMemorySettingsStore);
    procedure Save(const AStore: IAtlasMemorySettingsStore);
    procedure Clear;
    function Count: Integer;
    function Item(AIndex: Integer): TAtlasSettingsValueBinding;
    /// <summary>Index von AValue in AValues ohne Rücksicht auf Groß-/Kleinschreibung; 0 ohne Treffer.</summary>
    class function ChoiceOf(const AValue: string; const AValues: array of string): Integer; static;
    /// <summary>Zahlen stehen als Zahl im Speicher (wie TAtlasPluginSettings.Save), alles andere als Text; ein
    /// Text, der keine Zahl ist, lässt eine Zahl unverändert.</summary>
    class procedure WriteText(const AStore: IAtlasMemorySettingsStore; const AName, AText: string); static;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Vcl.StdCtrls,
  Vcl.Menus,
  Atlas.UI.Settings.ChoiceBox;

constructor TAtlasSettingsBindings.Create;
begin
  inherited Create;
  FItems := TList<TAtlasSettingsValueBinding>.Create;
end;

destructor TAtlasSettingsBindings.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

procedure TAtlasSettingsBindings.Add(const AName: string; AControl: TControl; AKind: TAtlasSettingsBindingKind;
  const AValues: TArray<string>);
var
  mBinding: TAtlasSettingsValueBinding;
begin
  mBinding := Default(TAtlasSettingsValueBinding);
  mBinding.Name := AName;
  mBinding.Control := AControl;
  mBinding.Kind := AKind;
  mBinding.Values := AValues;
  FItems.Add(mBinding);
end;

procedure TAtlasSettingsBindings.Clear;
begin
  FItems.Clear;
end;

function TAtlasSettingsBindings.Count: Integer;
begin
  Result := FItems.Count;
end;

function TAtlasSettingsBindings.Item(AIndex: Integer): TAtlasSettingsValueBinding;
begin
  Result := FItems[AIndex];
end;

procedure TAtlasSettingsBindings.Load(const AStore: IAtlasMemorySettingsStore);
var
  mBinding: TAtlasSettingsValueBinding;
begin
  for mBinding in FItems do
  begin
    LoadOne(AStore, mBinding);
  end;
end;

procedure TAtlasSettingsBindings.Save(const AStore: IAtlasMemorySettingsStore);
var
  mBinding: TAtlasSettingsValueBinding;
begin
  for mBinding in FItems do
  begin
    SaveOne(AStore, mBinding);
  end;
end;

class procedure TAtlasSettingsBindings.LoadOne(const AStore: IAtlasMemorySettingsStore;
  const ABinding: TAtlasSettingsValueBinding);
begin
  case ABinding.Kind of
    sbkCheck:
      (ABinding.Control as TCheckBox).Checked := AStore.ReadInteger(ABinding.Name, 0) <> 0;
    sbkText:
      (ABinding.Control as TEdit).Text := AStore.Text(ABinding.Name);
    sbkShortcut:
      (ABinding.Control as TEdit).Text := ShortCutToText(TShortCut(AStore.ReadInteger(ABinding.Name, 0)));
    sbkChoice:
      (ABinding.Control as TAtlasChoiceBox).Choice := ChoiceOf(AStore.Text(ABinding.Name), ABinding.Values);
  end;
end;

class procedure TAtlasSettingsBindings.SaveOne(const AStore: IAtlasMemorySettingsStore;
  const ABinding: TAtlasSettingsValueBinding);
var
  mChoice: Integer;
begin
  case ABinding.Kind of
    sbkCheck:
      AStore.WriteInteger(ABinding.Name, Ord((ABinding.Control as TCheckBox).Checked));
    sbkText:
      WriteText(AStore, ABinding.Name, Trim((ABinding.Control as TEdit).Text));
    sbkShortcut:
      AStore.WriteInteger(ABinding.Name, Integer(TextToShortCut(Trim((ABinding.Control as TEdit).Text))));
    sbkChoice:
      begin
        mChoice := (ABinding.Control as TAtlasChoiceBox).Choice;
        if (mChoice >= 0) and (mChoice <= High(ABinding.Values)) then
        begin
          WriteText(AStore, ABinding.Name, ABinding.Values[mChoice]);
        end;
      end;
  end;
end;

class function TAtlasSettingsBindings.ChoiceOf(const AValue: string; const AValues: array of string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AValues) do
  begin
    if SameText(AValues[mIndex], AValue) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := 0;
end;

class procedure TAtlasSettingsBindings.WriteText(const AStore: IAtlasMemorySettingsStore; const AName, AText: string);
var
  mValue: Integer;
begin
  if AStore.HasInteger(AName) then
  begin
    if TryStrToInt(AText, mValue) then
    begin
      AStore.WriteInteger(AName, mValue);
    end;
  end
  else
  begin
    AStore.WriteString(AName, AText);
  end;
end;

end.
