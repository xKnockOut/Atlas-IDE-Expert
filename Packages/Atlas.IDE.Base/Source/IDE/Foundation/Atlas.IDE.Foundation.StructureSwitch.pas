unit Atlas.IDE.Foundation.StructureSwitch;

// Schaltet Anzeigen der IDE ab, die Atlas selbst übernimmt, und stellt sie
// wieder her, wenn die Atlas-Anzeige aus ist:
//   - Strukturhervorhebung, solange Atlas eigene Blocklinien zeichnet (#514):
//     <Basisschlüssel>\Editor\Highlight\Structural Highlighting, Enabled;
//     Merker IdeStructureDisabled.
//   - Help Insight, solange der Atlas-Tooltip an ist (#442): Wert Help Insight
//     unter <Basisschlüssel>\Code Insight\<Ort>; Ort je Version und alle Orte,
//     die den Wert schon tragen (TAtlasCodeInsightKeys, #1246: unter Delphi 12
//     traf Atlas vorher nur den Ort von Delphi 13, und die IDE zeigte beide
//     Hinweise). Merker IdeHelpInsightDisabled je Version und Ort.
//   - Error Insight auf Knopfdruck aus der Einrichtung (#625), nie von selbst:
//     Wert Error Insight an denselben Orten; gelesen am Ort der Version.
//     Merker IdeErrorInsightDisabled. ErrorInsightChanged hält fest, dass die
//     IDE den neuen Wert erst nach dem nächsten Start liest.
// Es gibt dafür keine Open Tools API: Die Schalter stehen in der Registry und
// werden von der IDE beim Start gelesen. Die Merker unter
// HKCU\Software\Atlas\IdePlugin halten fest, was Atlas abgeschaltet hat; nur
// das wird zurückgedreht. Sie gelten je Version (#1246), sonst drehte eine
// zweite installierte IDE zurück, was Atlas in der anderen abgeschaltet hat.

interface

type
  TAtlasIdeStructureSwitch = class
  private
    /// <summary>Ein Schalter an einem Ort; AMarker ist der volle Name des Merkers, ALegacyMarker ein älterer, der
    /// gilt, solange der neue fehlt ('' ohne).</summary>
    class function ApplySwitch(const ASubKey, AValueName, AMarker, ALegacyMarker: string;
      AOwn: Boolean): Boolean; static;
    /// <summary>AValueName an allen Orten unter Code Insight schalten (#1246).</summary>
    class function ApplyCodeInsight(const AValueName, AMarker: string; AOwn: Boolean): Boolean; static;
  public
    /// <summary>Strukturhervorhebung angleichen; True, wenn geändert (wirkt nach dem nächsten Start der IDE).</summary>
    class function Apply(AOwnGuides: Boolean): Boolean; static;
    /// <summary>Help Insight angleichen; True, wenn geändert (wirkt nach dem nächsten Start der IDE).</summary>
    class function ApplyHelpInsight(AOwnTooltip: Boolean): Boolean; static;
    /// <summary>Wert-Tooltip der IDE beim Debuggen angleichen (aus, solange der Atlas-Hover die Werte zeigt);
    /// True, wenn geändert (wirkt nach dem nächsten Start der IDE).</summary>
    class function ApplyTooltipWatches(AOwnValues: Boolean): Boolean; static;
    /// <summary>Beides nach den aktuellen Einstellungen; meldet Änderungen im Meldungsfenster.</summary>
    class procedure Sync; static;
    /// <summary>Error Insight der IDE an (#625)? Ohne Wert gilt die Vorgabe der IDE: an.</summary>
    class function ErrorInsight: Boolean; static;
    /// <summary>Error Insight schalten (#625); True, wenn geschrieben. Wirkt nach dem nächsten Start der IDE.</summary>
    class function SetErrorInsight(AEnabled: Boolean): Boolean; static;
    /// <summary>In dieser Sitzung umgeschaltet: Die IDE zeigt noch den alten Stand.</summary>
    class function ErrorInsightChanged: Boolean; static;
  end;

implementation

uses
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Guard,
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Win.Registry,
  ToolsAPI,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Editor.Guides,
  Atlas.Core.Editor.CodeInsightKeys,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.Settings;

const
  StructureKey = '\Editor\Highlight\Structural Highlighting';
  StructureMarker = 'IdeStructureDisabled';
  HelpInsightValue = 'Help Insight';
  HelpInsightMarker = 'IdeHelpInsightDisabled';
  // Delphi: „Ausdrucksauswertung im Kurzhinweis“ – eigener Wert-Tooltip über dem Atlas-Hover.
  TooltipWatchesValue = 'ToolTip Watches';
  TooltipWatchesMarker = 'IdeTooltipWatchesDisabled';
  ErrorInsightValue = 'Error Insight';
  ErrorInsightMarker = 'IdeErrorInsightDisabled';

var
  // Wert von Error Insight beim ersten Lesen in dieser Sitzung; so liest ihn die IDE bis zum Neustart.
  ErrorInsightAtStart: Integer = -1;

class function TAtlasIdeStructureSwitch.ApplySwitch(const ASubKey, AValueName, AMarker, ALegacyMarker: string;
  AOwn: Boolean): Boolean;
var
  Services: IOTAServices;
  Registry: TRegistry;
  Key: string;
  State, Next: TAtlasIdeStructure;
begin
  Result := False;
  if not Supports(BorlandIDEServices, IOTAServices, Services) then
    Exit;
  Key := Services.GetBaseRegistryKey + ASubKey;
  Registry := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    Registry.RootKey := HKEY_CURRENT_USER;
    try
      // Ohne Wert gilt die Vorgabe der IDE: eingeschaltet.
      State.Enabled := True;
      if Registry.OpenKey(Key, True) and Registry.ValueExists(AValueName) then
        State.Enabled := SameText(Registry.ReadString(AValueName), 'True');
      Registry.CloseKey;
      State.DisabledByAtlas := False;
      if Registry.OpenKey(AtlasRegistryKey, True) then
      begin
        if Registry.ValueExists(AMarker) then
          State.DisabledByAtlas := Registry.ReadInteger(AMarker) <> 0
        else if (ALegacyMarker <> '') and Registry.ValueExists(ALegacyMarker) then
          State.DisabledByAtlas := Registry.ReadInteger(ALegacyMarker) <> 0;
      end;
      Registry.CloseKey;
      Next := TAtlasGuides.Switch(State, AOwn);
      if Next.Enabled <> State.Enabled then
      begin
        if Registry.OpenKey(Key, True) then
        begin
          if Next.Enabled then
            Registry.WriteString(AValueName, 'True')
          else
            Registry.WriteString(AValueName, 'False');
          Result := True;
        end;
        Registry.CloseKey;
      end;
      // Den Merker immer unter seinem neuen Namen festhalten; der alte entfällt dann.
      if Registry.OpenKey(AtlasRegistryKey, True) then
      begin
        if (Next.DisabledByAtlas <> State.DisabledByAtlas) or not Registry.ValueExists(AMarker) then
          Registry.WriteInteger(AMarker, Ord(Next.DisabledByAtlas));
        if (ALegacyMarker <> '') and Registry.ValueExists(ALegacyMarker) then
          Registry.DeleteValue(ALegacyMarker);
        Registry.CloseKey;
      end;
    except
      // Ohne Schreibrecht bleibt die IDE, wie sie ist.
      on ERegistryException do
        Result := False;
    end;
  finally
    Registry.Free;
  end;
end;

function BaseKey: string;
var
  Services: IOTAServices;
begin
  Result := '';
  if Supports(BorlandIDEServices, IOTAServices, Services) then
    Result := Services.GetBaseRegistryKey;
end;

/// <summary>Unterschlüssel von Code Insight, die AValueName schon tragen (#1246).</summary>
function KeysWithValue(const AValueName: string): TArray<string>;
var
  mRegistry: TRegistry;
  mNames: TStringList;
  mName: string;
begin
  Result := nil;
  if BaseKey = '' then
    Exit;
  mRegistry := TRegistry.Create(KEY_READ);
  mNames := TStringList.Create;
  try
    mRegistry.RootKey := HKEY_CURRENT_USER;
    try
      if not mRegistry.OpenKeyReadOnly(BaseKey + TAtlasCodeInsightKeys.cRoot) then
        Exit;
      mRegistry.GetKeyNames(mNames);
      mRegistry.CloseKey;
      for mName in mNames do
      begin
        if mRegistry.OpenKeyReadOnly(BaseKey + TAtlasCodeInsightKeys.cRoot + '\' + mName) and
          mRegistry.ValueExists(AValueName) then
          Result := Result + [mName];
        mRegistry.CloseKey;
      end;
    except
      // Ohne Leserecht bleibt es beim Ort der Version.
      on ERegistryException do
        Result := nil;
    end;
  finally
    mNames.Free;
    mRegistry.Free;
  end;
end;

/// <summary>Merker vor #1246: ein Name für alle Versionen, nur am Ort von Delphi 13.</summary>
function LegacyMarker(const AMarker, ASubKey: string): string;
begin
  Result := '';
  if TAtlasCodeInsightKeys.UsesLegacyMarker(BaseKey, ASubKey) then
    Result := AMarker;
end;

class function TAtlasIdeStructureSwitch.ApplyCodeInsight(const AValueName, AMarker: string; AOwn: Boolean): Boolean;
var
  mSubKey: string;
begin
  Result := False;
  for mSubKey in TAtlasCodeInsightKeys.Targets(BaseKey, KeysWithValue(AValueName)) do
    if ApplySwitch(TAtlasCodeInsightKeys.cRoot + '\' + mSubKey, AValueName,
      TAtlasCodeInsightKeys.Marker(AMarker, BaseKey, mSubKey), LegacyMarker(AMarker, mSubKey), AOwn) then
      Result := True;
end;

class function TAtlasIdeStructureSwitch.Apply(AOwnGuides: Boolean): Boolean;
begin
  // Der alte Merker galt für alle Versionen; ab #1246 je Version.
  Result := ApplySwitch(StructureKey, 'Enabled', TAtlasCodeInsightKeys.Marker(StructureMarker, BaseKey, 'Editor'),
    StructureMarker, AOwnGuides);
end;

class function TAtlasIdeStructureSwitch.ApplyHelpInsight(AOwnTooltip: Boolean): Boolean;
begin
  Result := ApplyCodeInsight(HelpInsightValue, HelpInsightMarker, AOwnTooltip);
end;

class function TAtlasIdeStructureSwitch.ApplyTooltipWatches(AOwnValues: Boolean): Boolean;
begin
  Result := ApplyCodeInsight(TooltipWatchesValue, TooltipWatchesMarker, AOwnValues);
end;

function ReadErrorInsight: Boolean;
var
  Registry: TRegistry;
begin
  // Ohne Wert gilt die Vorgabe der IDE: eingeschaltet.
  Result := True;
  if BaseKey = '' then
    Exit;
  Registry := TRegistry.Create(KEY_READ);
  try
    Registry.RootKey := HKEY_CURRENT_USER;
    // Die IDE liest nur den Ort ihrer Version (#1246); bei unbekannter Version der erste bekannte.
    if Registry.OpenKeyReadOnly(BaseKey + TAtlasCodeInsightKeys.cRoot + '\' +
      TAtlasCodeInsightKeys.Targets(BaseKey, nil)[0]) and Registry.ValueExists(ErrorInsightValue) then
      Result := not SameText(Registry.ReadString(ErrorInsightValue), 'False');
  finally
    Registry.Free;
  end;
end;

class function TAtlasIdeStructureSwitch.ErrorInsight: Boolean;
begin
  Result := ReadErrorInsight;
  if ErrorInsightAtStart < 0 then
    ErrorInsightAtStart := Ord(Result);
end;

class function TAtlasIdeStructureSwitch.ErrorInsightChanged: Boolean;
begin
  Result := (ErrorInsightAtStart >= 0) and (Ord(ReadErrorInsight) <> ErrorInsightAtStart);
end;

class function TAtlasIdeStructureSwitch.SetErrorInsight(AEnabled: Boolean): Boolean;
var
  Registry: TRegistry;
  mSubKey: string;
begin
  Result := False;
  if BaseKey = '' then
    Exit;
  // Stand vor der Änderung merken, falls noch nicht gelesen.
  ErrorInsight;
  Registry := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    Registry.RootKey := HKEY_CURRENT_USER;
    try
      // An allen Orten wie Help Insight (#1246): dem der Version und jedem, der den Wert schon trägt.
      for mSubKey in TAtlasCodeInsightKeys.Targets(BaseKey, KeysWithValue(ErrorInsightValue)) do
      begin
        if Registry.OpenKey(BaseKey + TAtlasCodeInsightKeys.cRoot + '\' + mSubKey, True) then
        begin
          if AEnabled then
            Registry.WriteString(ErrorInsightValue, 'True')
          else
            Registry.WriteString(ErrorInsightValue, 'False');
          Result := True;
        end;
        Registry.CloseKey;
      end;
      if Result and Registry.OpenKey(AtlasRegistryKey, True) then
        Registry.WriteInteger(ErrorInsightMarker, Ord(not AEnabled));
      Registry.CloseKey;
    except
      // Ohne Schreibrecht bleibt die IDE, wie sie ist.
      on ERegistryException do
        Result := False;
    end;
  finally
    Registry.Free;
  end;
end;

class procedure TAtlasIdeStructureSwitch.Sync;
var
  Settings: TAtlasPluginSettings;
  Own, OwnTooltip: Boolean;
  Texts: TArray<string>;
begin
  Settings := TAtlasIdeSettings.Current;
  Own := Settings.PairColors and Settings.PairGuides;
  OwnTooltip := Settings.Enabled and Settings.HoverTooltip;
  Texts := nil;
  if Apply(Own) then
    if Own then
      Texts := Texts + [TAtlasStrings.Text(TAtlasTextId.PairGuidesIdeOff)]
    else
      Texts := Texts + [TAtlasStrings.Text(TAtlasTextId.PairGuidesIdeOn)];
  if ApplyHelpInsight(OwnTooltip) then
    if OwnTooltip then
      Texts := Texts + [TAtlasStrings.Text(TAtlasTextId.HelpInsightIdeOff)]
    else
      Texts := Texts + [TAtlasStrings.Text(TAtlasTextId.HelpInsightIdeOn)];
  if ApplyTooltipWatches(OwnTooltip and Settings.DebugHoverValues) then
    if OwnTooltip and Settings.DebugHoverValues then
      Texts := Texts + [TAtlasStrings.Text(TAtlasTextId.TooltipWatchesIdeOff)]
    else
      Texts := Texts + [TAtlasStrings.Text(TAtlasTextId.TooltipWatchesIdeOn)];
  if Length(Texts) = 0 then
    Exit;
  // Beim Laden des Plugins ist das Meldungsfenster noch nicht bereit.
  TAtlasMainThread.ForceQueue(TAtlasFeature.EditorCommands,
    procedure
    var
      Messages: IOTAMessageServices;
      Text: string;
    begin
      if Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
        for Text in Texts do
          Messages.AddTitleMessage(Text);
    end);
end;

end.
