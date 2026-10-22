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
  Marker = 'IdeNavigationToolbarHidden';

var
  /// <summary>Zuletzt protokollierter Weg; gleiche Zeilen nicht bei jedem Aufruf wiederholen.</summary>
  LoggedWay: string;

procedure LogWay(const AWay: string);
begin
  if AWay = LoggedWay then
    Exit;
  LoggedWay := AWay;
  TAtlasGuard.Log(AWay);
end;

function ReadMarker: Boolean;
var
  Registry: TRegistry;
begin
  Result := False;
  Registry := TRegistry.Create(KEY_READ);
  try
    Registry.RootKey := HKEY_CURRENT_USER;
    try
      if Registry.OpenKeyReadOnly(AtlasRegistryKey) and Registry.ValueExists(Marker) then
        Result := Registry.ReadInteger(Marker) <> 0;
    except
      on E: ERegistryException do
        TAtlasGuard.Log('Navigationsleiste: Merker nicht lesbar (' + TAtlasGuard.SafeMessage(E.Message) + ')');
    end;
  finally
    Registry.Free;
  end;
end;

procedure WriteMarker(AValue: Boolean);
var
  Registry: TRegistry;
begin
  Registry := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    Registry.RootKey := HKEY_CURRENT_USER;
    try
      if Registry.OpenKey(AtlasRegistryKey, True) then
        Registry.WriteInteger(Marker, Ord(AValue));
    except
      on E: ERegistryException do
        TAtlasGuard.Log('Navigationsleiste: Merker nicht geschrieben (' + TAtlasGuard.SafeMessage(E.Message) + ')');
    end;
  finally
    Registry.Free;
  end;
end;

function OptionNames(const AOptions: IOTAEnvironmentOptions): TArray<string>;
var
  Names: TOTAOptionNameArray;
  Index: Integer;
begin
  Names := AOptions.GetOptionNames;
  SetLength(Result, Length(Names));
  for Index := 0 to High(Names) do
    Result[Index] := Names[Index].Name;
end;

class function TAtlasIdeNavigationOption.Apply(AHide: Boolean): Boolean;
var
  Services: IOTAServices;
  Options: IOTAEnvironmentOptions;
  Names: TArray<string>;
  Name: string;
  Value: Variant;
  State, Next: TAtlasIdeStructure;
begin
  Result := False;
  if not Supports(BorlandIDEServices, IOTAServices, Services) then
    Exit;
  try
    Options := Services.GetEnvironmentOptions;
    if Options = nil then
      Exit;
    Names := OptionNames(Options);
    Name := TAtlasNavigationOption.Find(Names);
    if Name = '' then
    begin
      LogWay(Format('Navigationsleiste: Die IDE hat keine Option dafür (ähnliche Namen: %s); zum Ausblenden ' +
        'hängt Atlas die Leiste um (Netz)', [string.Join(', ', TAtlasNavigationOption.Candidates(Names))]));
      Exit;
    end;
    Value := Options.Values[Name];
    State.Enabled := TAtlasNavigationOption.IsOn(Value);
    State.DisabledByAtlas := ReadMarker;
    Next := TAtlasGuides.Switch(State, AHide);
    if Next.Enabled <> State.Enabled then
      Options.Values[Name] := TAtlasNavigationOption.Encode(Value, Next.Enabled);
    if Next.DisabledByAtlas <> State.DisabledByAtlas then
      WriteMarker(Next.DisabledByAtlas);
    LogWay(Format('Navigationsleiste: über die Option %s der IDE (an: %s, von Atlas ausgeschaltet: %s)', [Name,
      BoolToStr(Next.Enabled, True), BoolToStr(Next.DisabledByAtlas, True)]));
    Result := True;
  except
    // Die IDE lehnt Lesen oder Schreiben ab: Dann bleibt das Umhängen (Netz); der Grund steht im Protokoll.
    on E: Exception do
      LogWay('Navigationsleiste: Option der IDE nicht nutzbar (' + E.ClassName + ': ' +
        TAtlasGuard.SafeMessage(E.Message) + '); zum Ausblenden hängt Atlas die Leiste um (Netz)');
  end;
end;

end.
