unit Atlas.IDE.Welcome.Settings;

// Abschnitt „Willkommensseite“ im Optionsdialog, IDE-Teil des Moduls
// Willkommensseite (#1456; vorher fest in Atlas.UI.Settings.Page).
// TAtlasIdeWelcomeSettings ist der IAtlasSettingsSectionProvider, den die
// Composition des Moduls über seinen Scope anmeldet: Für jede Optionsseite
// entsteht ein TAtlasWelcomeSettingsSection mit den Haken dazu.
// - „Zählung zurücksetzen“ leert die Befehlsnutzung von Base
//   (TAtlasIdeCommandUsage, meldet das selbst an alle Hörer),
// - „Gesperrte Tipps wieder zeigen“ hebt die Sperren von „Atlas entdecken“
//   (#757) auf und speichert sie sofort.
// - Schalter der Kacheln anderer Module (#1903): aus dem Kachel-Vertrag
//   (SwitchKey, SettingsKey), in Reihenfolge der Kacheln; die Willkommensseite
//   kennt die Schlüssel der Module nicht.

interface

uses
  Atlas.UI.Settings.Contract;

type
  TAtlasIdeWelcomeSettings = class(TInterfacedObject, IAtlasSettingsSectionProvider)
  public
    function CreateSection: IAtlasSettingsSection;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Settings.Catalog,
  Atlas.IDE.Contracts.WelcomeTiles,
  Atlas.IDE.Commands.Usage,
  Atlas.IDE.Welcome.Discover,
  Atlas.UI.Welcome.SettingsSection;

/// <summary>Schalter der Kacheln anderer Module in Reihenfolge ihrer Kacheln.</summary>
function TileSwitches: TArray<TAtlasWelcomeTileSwitch>;
var
  mInfos: TArray<TAtlasWelcomeTileInfo>;
  mItem: IInterface;
  mTile: IAtlasWelcomeTile;
  mInfo: TAtlasWelcomeTileInfo;
  mSwitch: TAtlasWelcomeTileSwitch;
  mCatalog: TAtlasSettingsCatalog;
  mIndex: Integer;
begin
  Result := nil;
  mInfos := nil;
  for mItem in AtlasModuleRegistry.FindAll(IAtlasWelcomeTile) do
  begin
    if Supports(mItem, IAtlasWelcomeTile, mTile) and (mTile.Info.SwitchKey <> '') then
    begin
      mInfos := mInfos + [mTile.Info];
    end;
  end;
  if Length(mInfos) = 0 then
  begin
    Exit;
  end;
  TArray.Sort<TAtlasWelcomeTileInfo>(mInfos, TComparer<TAtlasWelcomeTileInfo>.Construct(
    function(const ALeft, ARight: TAtlasWelcomeTileInfo): Integer
    begin
      Result := ALeft.Order - ARight.Order;
      if Result = 0 then
      begin
        Result := CompareText(ALeft.Id, ARight.Id);
      end;
    end));
  mCatalog := TAtlasSettingsCatalog.CreateDefault;
  try
    for mInfo in mInfos do
    begin
      mSwitch := Default(TAtlasWelcomeTileSwitch);
      mSwitch.Key := mInfo.SwitchKey;
      mSwitch.SettingsKey := mInfo.SettingsKey;
      mIndex := mCatalog.IndexOfKey(mInfo.SwitchKey);
      if mIndex >= 0 then
      begin
        mSwitch.Setting := mCatalog[mIndex].Name;
      end;
      Result := Result + [mSwitch];
    end;
  finally
    mCatalog.Free;
  end;
end;

function TAtlasIdeWelcomeSettings.CreateSection: IAtlasSettingsSection;
var
  mSection: TAtlasWelcomeSettingsSection;
begin
  mSection := TAtlasWelcomeSettingsSection.Create;
  Result := mSection;
  mSection.Hooks.TileSwitches := TileSwitches;
  mSection.Hooks.OnResetUsage :=
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Settings,
        procedure
        begin
          TAtlasIdeCommandUsage.ResetCounts;
        end);
    end;
  mSection.Hooks.OnUnblockTips :=
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Settings,
        procedure
        begin
          TAtlasIdeDiscover.UnblockAll;
        end);
    end;
end;

end.
