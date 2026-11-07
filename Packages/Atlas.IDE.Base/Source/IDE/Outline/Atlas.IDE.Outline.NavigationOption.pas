unit Atlas.IDE.Outline.NavigationOption;

// Navigationsleiste der IDE über ihre eigene Option aus- und wieder
// einblenden (Bericht M3, editor.breadcrumbsHideIdeToolbar): „Navigations-
// symbolleiste anzeigen“ steht in den Umgebungsoptionen der IDE
// (IOTAEnvironmentOptions); den Namen sucht TAtlasNavigationOption.Find.
// - Apply(True) schaltet die Option aus, wenn sie an ist, und merkt unter
//   HKCU\Software\Atlas\IdePlugin, Wert IdeNavigationToolbarHidden, dass
//   Atlas das war. Apply(False) schaltet sie nur dann wieder an
//   (TAtlasGuides.Switch, wie bei Strukturhervorhebung und Help Insight). Die
//   Brotkrumen rufen Apply(False) auch beim Entladen; so bleibt nach dem
//   Deinstallieren die Wahl des Benutzers.
// - Hat die IDE die Option nicht oder lehnt sie den Wert ab, liefert Apply
//   False; dann hängt TAtlasNavigationToolbar die Leiste um (Netz). Welcher
//   Weg gilt, steht bei jedem Wechsel im atlas.log, ohne Option samt
//   ähnlichen Namen.
// Nur im Hauptthread.

interface

type
  TAtlasIdeNavigationOption = class
  public
    /// <summary>Navigationsleiste über die Option der IDE ausblenden (AHide) bzw. wieder einblenden, wenn Atlas sie
    /// ausgeblendet hatte. True, wenn die IDE die Option hat (Atlas hängt dann nichts um); False, wenn nicht.</summary>
    class function Apply(AHide: Boolean): Boolean; static;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Variants,
  System.Win.Registry,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Editor.Guides,
  Atlas.Core.Outline.NavigationOption,
  Atlas.IDE.Foundation.Settings;

const
  cMarker = 'IdeNavigationToolbarHidden';

var
  /// <summary>Zuletzt protokollierter Weg; gleiche Zeilen nicht bei jedem Aufruf wiederholen.</summary>
  LoggedWay: string;

procedure LogWay(const AWay: string);
begin
  if AWay = LoggedWay then
  begin
    Exit;
  end;
  LoggedWay := AWay;
  TAtlasGuard.Log(AWay);
end;

function ReadMarker: Boolean;
var
  mRegistry: TRegistry;
begin
  Result := False;
  mRegistry := TRegistry.Create(KEY_READ);
  try
    mRegistry.RootKey := HKEY_CURRENT_USER;
    try
      if mRegistry.OpenKeyReadOnly(AtlasRegistryKey) and mRegistry.ValueExists(cMarker) then
      begin
        Result := mRegistry.ReadInteger(cMarker) <> 0;
      end;
    except
      on E: ERegistryException do
        TAtlasGuard.Log('Navigationsleiste: Merker nicht lesbar (' + TAtlasGuard.MessageText(E.Message) + ')');
    end;
  finally
    mRegistry.Free;
  end;
end;

procedure WriteMarker(AValue: Boolean);
var
  mRegistry: TRegistry;
begin
  mRegistry := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    mRegistry.RootKey := HKEY_CURRENT_USER;
    try
      if mRegistry.OpenKey(AtlasRegistryKey, True) then
      begin
        mRegistry.WriteInteger(cMarker, Ord(AValue));
      end;
    except
      on E: ERegistryException do
        TAtlasGuard.Log('Navigationsleiste: Merker nicht geschrieben (' + TAtlasGuard.MessageText(E.Message) + ')');
    end;
  finally
    mRegistry.Free;
  end;
end;

function OptionNames(const AOptions: IOTAEnvironmentOptions): TArray<string>;
var
  mNames: TOTAOptionNameArray;
  mIndex: Integer;
begin
  mNames := AOptions.GetOptionNames;
  SetLength(Result, Length(mNames));
  for mIndex := 0 to High(mNames) do
  begin
    Result[mIndex] := mNames[mIndex].Name;
  end;
end;

class function TAtlasIdeNavigationOption.Apply(AHide: Boolean): Boolean;
var
  mServices: IOTAServices;
  mOptions: IOTAEnvironmentOptions;
  mNames: TArray<string>;
  mName: string;
  mValue: Variant;
  mState, mNext: TAtlasIdeStructure;
begin
  Result := False;
  if not Supports(BorlandIDEServices, IOTAServices, mServices) then
  begin
    Exit;
  end;
  try
    mOptions := mServices.GetEnvironmentOptions;
    if mOptions = nil then
    begin
      Exit;
    end;
    mNames := OptionNames(mOptions);
    mName := TAtlasNavigationOption.Find(mNames);
    if mName = '' then
    begin
      LogWay(Format('Navigationsleiste: Die IDE hat keine Option dafür (ähnliche Namen: %s); zum Ausblenden ' +
        'hängt Atlas die Leiste um (Netz)', [string.Join(', ', TAtlasNavigationOption.Candidates(mNames))]));
      Exit;
    end;
    mValue := mOptions.Values[mName];
    mState.Enabled := TAtlasNavigationOption.IsOn(mValue);
    mState.DisabledByAtlas := ReadMarker;
    mNext := TAtlasGuides.Switch(mState, AHide);
    if mNext.Enabled <> mState.Enabled then
    begin
      mOptions.Values[mName] := TAtlasNavigationOption.Encode(mValue, mNext.Enabled);
    end;
    if mNext.DisabledByAtlas <> mState.DisabledByAtlas then
    begin
      WriteMarker(mNext.DisabledByAtlas);
    end;
    LogWay(Format('Navigationsleiste: über die Option %s der IDE (an: %s, von Atlas ausgeschaltet: %s)', [mName,
      BoolToStr(mNext.Enabled, True), BoolToStr(mNext.DisabledByAtlas, True)]));
    Result := True;
  except
    // Die IDE lehnt Lesen oder Schreiben ab: Dann bleibt das Umhängen (Netz); der Grund steht im Protokoll.
    on E: Exception do
      LogWay('Navigationsleiste: Option der IDE nicht nutzbar (' + E.ClassName + ': ' +
        TAtlasGuard.SafeMessage(E.Message) + '); zum Ausblenden hängt Atlas die Leiste um (Netz)');
  end;
end;

end.
