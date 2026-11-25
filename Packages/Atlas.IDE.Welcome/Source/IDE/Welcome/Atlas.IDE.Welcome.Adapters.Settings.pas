unit Atlas.IDE.Welcome.Adapters.Settings;

// Abschnitt „Willkommensseite“ im Optionsdialog, IDE-Teil des Moduls
// Willkommensseite (#1456).
// TAtlasIdeWelcomeSettings ist der IAtlasSettingsSectionProvider, den die
// Composition des Moduls über seinen Scope anmeldet: Für jede Optionsseite
// entsteht ein TAtlasWelcomeSettingsSection mit den Haken dazu, den die
// Composition in den Vertrag hüllt.
// - „Zählung zurücksetzen“ leert die Befehlsnutzung von Base
//   (TAtlasIdeCommandUsage, meldet das selbst an alle Hörer),
// - „Gesperrte Tipps wieder zeigen“ hebt die Sperren von „Atlas entdecken“
//   (#757) auf und speichert sie sofort (Haken der Composition).
// - Schalter der Kacheln anderer Module (#1903): aus dem Kachel-Vertrag
//   (SwitchKey, SettingsKey), in Reihenfolge der Kacheln; die Willkommensseite
//   kennt die Schlüssel der Module nicht.

interface

uses
  System.SysUtils,
  Atlas.UI.Settings.Contract,
  Atlas.UI.Welcome.SettingsSection;

type
  TAtlasIdeWelcomeSettings = class(TInterfacedObject, IAtlasSettingsSectionProvider)
  private
    FWrap: TFunc<TAtlasWelcomeSettingsSection, IAtlasSettingsSection>;
    FUnblockTips: TProc;
  public
    /// <summary>AWrap hüllt einen neuen Abschnitt in den Vertrag (übernimmt ihn); AUnblockTips hebt die Sperren
    /// von „Atlas entdecken“ auf.</summary>
    constructor Create(const AWrap: TFunc<TAtlasWelcomeSettingsSection, IAtlasSettingsSection>;
      const AUnblockTips: TProc);
    function CreateSection: IAtlasSettingsSection;
  end;

implementation

uses
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Plugin.Diagnostics.Guard,
  Atlas.IDE.Base.Core.Modules.Registry,
  Atlas.Plugin.Settings.Catalog,
  Atlas.IDE.Base.Foundation.WelcomeTiles,
  Atlas.IDE.Commands.Usage;

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

{ TAtlasIdeWelcomeSettings }

constructor TAtlasIdeWelcomeSettings.Create(const AWrap: TFunc<TAtlasWelcomeSettingsSection, IAtlasSettingsSection>;
  const AUnblockTips: TProc);
begin
  inherited Create;
  FWrap := AWrap;
  FUnblockTips := AUnblockTips;
end;

function TAtlasIdeWelcomeSettings.CreateSection: IAtlasSettingsSection;
var
  mSection: TAtlasWelcomeSettingsSection;
  mUnblock: TProc;
begin
  mSection := TAtlasWelcomeSettingsSection.Create;
  Result := FWrap(mSection);
  mUnblock := FUnblockTips;
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
          if Assigned(mUnblock) then
          begin
            mUnblock();
          end;
        end);
    end;
end;

end.
