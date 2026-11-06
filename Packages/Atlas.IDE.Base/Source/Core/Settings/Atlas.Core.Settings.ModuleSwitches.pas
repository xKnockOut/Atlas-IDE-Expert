unit Atlas.Core.Settings.ModuleSwitches;

// Modul-Schalter (#1454), ohne VCL und ohne Open Tools API. Ein Modul ist eine
// Gruppe von Funktionen, die ab 2.0 ein eigenes Package wird (ADR 0017):
// Debugger, Issue-Tracker, Analyse, Tests, Build-Werkzeuge, Lesezeichen,
// Designer, Prüfregeln, Suche, Willkommensseite. Sein Schalter ist eine
// boolesche Plugin-Einstellung mit "x-module": "<Kennung>" im Plugin-Katalog;
// zum Modul gehört alles, was darunter liegt (x-parent bzw. Präfixregel, wie
// die Sperren der Optionsseite in Atlas.Core.Settings.Groups).
// Ist ein Schalter aus, liefern die wirksamen Werte (TAtlasIdeSettings.Current)
// für jede boolesche Einstellung des Moduls „aus“ und für eine mit x-offValue
// diesen Wert. So startet kein Teil des Moduls, und jedes laufende Teil hört
// über seine eigene Einstellung auf, ohne Neustart. Gespeichert bleiben die
// eigenen Werte (Optionsseite, Export); nach dem Wiedereinschalten gelten sie
// wieder. Zustände (x-state) und Rechnerwerte (x-machine) bleiben unberührt.

interface

uses
  System.SysUtils,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.Catalog;

type
  TAtlasModuleSwitch = record
    /// <summary>Kennung aus x-module, z. B. "debug".</summary>
    Module: string;
    /// <summary>Name des Schalters in TAtlasPluginSettings.Load/Save, z. B. "DebugEnabled".</summary>
    Name: string;
    /// <summary>x-key des Schalters, z. B. "debug.enabled".</summary>
    Key: string;
    Caption: string;
    CaptionEn: string;
    /// <summary>Einstellungen des Moduls mit einem Wert für „aus“ (boolesch oder x-offValue).</summary>
    Members: TArray<TAtlasCatalogEntry>;
  end;

  TAtlasModuleSwitches = class
  public
    /// <summary>Alle Modul-Schalter des Plugin-Katalogs in Katalogreihenfolge, mit ihren Einstellungen.</summary>
    class function Read(ACatalog: TAtlasSettingsCatalog): TArray<TAtlasModuleSwitch>; static;
    /// <summary>Wirksame Werte: Für jeden ausgeschalteten Modul-Schalter in ASettings bekommen die Einstellungen
    /// des Moduls ihren Wert für „aus“; sonst genau ASettings.</summary>
    class function Apply(const ASettings: TAtlasPluginSettings;
      const ASwitches: TArray<TAtlasModuleSwitch>): TAtlasPluginSettings; static;
    /// <summary>Ist das Modul AModule in ASettings an? Unbekannte Kennung = an.</summary>
    class function IsOn(const ASettings: TAtlasPluginSettings; const ASwitches: TArray<TAtlasModuleSwitch>;
      const AModule: string): Boolean; static;
    /// <summary>Kennungen der ausgeschalteten Module in Katalogreihenfolge.</summary>
    class function OffModules(const ASettings: TAtlasPluginSettings;
      const ASwitches: TArray<TAtlasModuleSwitch>): TArray<string>; static;
    /// <summary>Kennung des Moduls, zu dem die Einstellung AName (Name oder x-key) gehört; '' = Kern.</summary>
    class function ModuleOf(const ASwitches: TArray<TAtlasModuleSwitch>; const AName: string): string; static;
  end;

implementation

uses
  Atlas.Core.Settings.Groups,
  Atlas.Core.Settings.History;

function HasOffValue(const AEntry: TAtlasCatalogEntry): Boolean;
begin
  Result := not AEntry.State and not AEntry.Machine and
    ((AEntry.Kind = akBoolean) or ((AEntry.Kind = akString) and (AEntry.OffJson <> '')));
end;

function Contains(const ANames: TArray<string>; const AName: string): Boolean;
var
  mName: string;
begin
  Result := False;
  for mName in ANames do
  begin
    if SameText(mName, AName) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Wert eines Schalters aus dem Speicher; ohne Eintrag an (Vorgabe der Modul-Schalter).</summary>
function SwitchOn(const AStore: IAtlasMemorySettingsStore; const ASwitch: TAtlasModuleSwitch): Boolean;
begin
  Result := AStore.ReadInteger(ASwitch.Name, 1) <> 0;
end;

procedure WriteOff(const AStore: IAtlasMemorySettingsStore; const AEntry: TAtlasCatalogEntry);
var
  mValue: string;
begin
  if AEntry.Kind = akBoolean then
  begin
    AStore.WriteInteger(AEntry.Name, 0);
  end
  else
  begin
    mValue := TAtlasJsonValues.Display(AEntry.OffJson);
    AStore.WriteString(AEntry.Name, mValue);
  end;
end;

{ TAtlasModuleSwitches }

class function TAtlasModuleSwitches.Read(ACatalog: TAtlasSettingsCatalog): TArray<TAtlasModuleSwitch>;
var
  mGroups: TAtlasSettingsGroups;
  mIndex, mOther: Integer;
  mSwitch: TAtlasModuleSwitch;
  mEntry: TAtlasCatalogEntry;
begin
  Result := nil;
  mGroups := TAtlasSettingsGroups.Create(ACatalog);
  try
    for mIndex := 0 to ACatalog.Count - 1 do
    begin
      mEntry := ACatalog[mIndex];
      if (mEntry.Source <> asPlugin) or (mEntry.Module = '') or (mEntry.Kind <> akBoolean) then
      begin
        Continue;
      end;
      mSwitch := Default(TAtlasModuleSwitch);
      mSwitch.Module := mEntry.Module;
      mSwitch.Name := mEntry.Name;
      mSwitch.Key := mEntry.Key;
      mSwitch.Caption := mEntry.Caption;
      mSwitch.CaptionEn := mEntry.CaptionEn;
      for mOther := 0 to ACatalog.Count - 1 do
      begin
        if (ACatalog[mOther].Source = asPlugin) and HasOffValue(ACatalog[mOther]) and
          Contains(mGroups.AncestorsOf(ACatalog[mOther].Name), mEntry.Name) then
        begin
          mSwitch.Members := mSwitch.Members + [ACatalog[mOther]];
        end;
      end;
      Result := Result + [mSwitch];
    end;
  finally
    mGroups.Free;
  end;
end;

class function TAtlasModuleSwitches.Apply(const ASettings: TAtlasPluginSettings;
  const ASwitches: TArray<TAtlasModuleSwitch>): TAtlasPluginSettings;
var
  mStore: IAtlasMemorySettingsStore;
  mSwitch: TAtlasModuleSwitch;
  mEntry: TAtlasCatalogEntry;
  mChanged: Boolean;
begin
  Result := ASettings;
  if Length(ASwitches) = 0 then
  begin
    Exit;
  end;
  mStore := TAtlasMemorySettingsStore.FromSettings(ASettings);
  mChanged := False;
  for mSwitch in ASwitches do
  begin
    if not SwitchOn(mStore, mSwitch) then
    begin
      for mEntry in mSwitch.Members do
      begin
        WriteOff(mStore, mEntry);
      end;
      mChanged := True;
    end;
  end;
  if mChanged then
  begin
    Result.Load(mStore);
  end;
end;

class function TAtlasModuleSwitches.IsOn(const ASettings: TAtlasPluginSettings;
  const ASwitches: TArray<TAtlasModuleSwitch>; const AModule: string): Boolean;
var
  mStore: IAtlasMemorySettingsStore;
  mSwitch: TAtlasModuleSwitch;
begin
  Result := True;
  for mSwitch in ASwitches do
  begin
    if SameText(mSwitch.Module, AModule) then
    begin
      mStore := TAtlasMemorySettingsStore.FromSettings(ASettings);
      Exit(SwitchOn(mStore, mSwitch));
    end;
  end;
end;

class function TAtlasModuleSwitches.OffModules(const ASettings: TAtlasPluginSettings;
  const ASwitches: TArray<TAtlasModuleSwitch>): TArray<string>;
var
  mStore: IAtlasMemorySettingsStore;
  mSwitch: TAtlasModuleSwitch;
begin
  Result := nil;
  if Length(ASwitches) = 0 then
  begin
    Exit;
  end;
  mStore := TAtlasMemorySettingsStore.FromSettings(ASettings);
  for mSwitch in ASwitches do
  begin
    if not SwitchOn(mStore, mSwitch) then
    begin
      Result := Result + [mSwitch.Module];
    end;
  end;
end;

class function TAtlasModuleSwitches.ModuleOf(const ASwitches: TArray<TAtlasModuleSwitch>;
  const AName: string): string;
var
  mSwitch: TAtlasModuleSwitch;
  mEntry: TAtlasCatalogEntry;
begin
  Result := '';
  for mSwitch in ASwitches do
  begin
    if SameText(mSwitch.Name, AName) or SameText(mSwitch.Key, AName) then
    begin
      Exit(mSwitch.Module);
    end;
    for mEntry in mSwitch.Members do
    begin
      if SameText(mEntry.Name, AName) or SameText(mEntry.Key, AName) then
      begin
        Exit(mSwitch.Module);
      end;
    end;
  end;
end;

end.
