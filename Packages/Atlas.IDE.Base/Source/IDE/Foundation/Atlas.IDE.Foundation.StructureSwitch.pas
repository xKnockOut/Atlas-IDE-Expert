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

/// <summary>Schalter der IDE unter AKey als Text, wie die IDE ihn schreibt.</summary>
function SwitchText(AEnabled: Boolean): string;
begin
  Result := 'False';
  if AEnabled then
  begin
    Result := 'True';
  end;
end;

/// <summary>AValueName unter AKey schreiben; True, wenn der Schlüssel offen war.</summary>
function WriteSwitch(ARegistry: TRegistry; const AKey, AValueName: string; AEnabled: Boolean): Boolean;
begin
  Result := ARegistry.OpenKey(AKey, True);
  if Result then
  begin
    ARegistry.WriteString(AValueName, SwitchText(AEnabled));
  end;
  ARegistry.CloseKey;
end;

/// <summary>Merker im offenen Schlüssel gesetzt: neuer Name, solange er fehlt der alte.</summary>
function MarkerSet(ARegistry: TRegistry; const AMarker, ALegacyMarker: string): Boolean;
begin
  Result := False;
  if ARegistry.ValueExists(AMarker) then
  begin
    Result := ARegistry.ReadInteger(AMarker) <> 0;
  end
  else if (ALegacyMarker <> '') and ARegistry.ValueExists(ALegacyMarker) then
  begin
    Result := ARegistry.ReadInteger(ALegacyMarker) <> 0;
  end;
end;

/// <summary>Stand des Schalters unter AKey und des Merkers (neuer Name, sonst ALegacyMarker).</summary>
function ReadSwitch(ARegistry: TRegistry; const AKey, AValueName, AMarker, ALegacyMarker: string):
  TAtlasIdeStructure;
begin
  // Ohne Wert gilt die Vorgabe der IDE: eingeschaltet.
  Result.Enabled := True;
  if ARegistry.OpenKey(AKey, True) and ARegistry.ValueExists(AValueName) then
  begin
    Result.Enabled := SameText(ARegistry.ReadString(AValueName), 'True');
  end;
  ARegistry.CloseKey;
  Result.DisabledByAtlas := ARegistry.OpenKey(AtlasRegistryKey, True) and MarkerSet(ARegistry, AMarker, ALegacyMarker);
  ARegistry.CloseKey;
end;

/// <summary>Den Merker immer unter seinem neuen Namen festhalten; der alte entfällt dann.</summary>
procedure WriteMarker(ARegistry: TRegistry; const AMarker, ALegacyMarker: string; AChanged, ADisabled: Boolean);
begin
  if not ARegistry.OpenKey(AtlasRegistryKey, True) then
  begin
    Exit;
  end;
  if AChanged or not ARegistry.ValueExists(AMarker) then
  begin
    ARegistry.WriteInteger(AMarker, Ord(ADisabled));
  end;
  if (ALegacyMarker <> '') and ARegistry.ValueExists(ALegacyMarker) then
  begin
    ARegistry.DeleteValue(ALegacyMarker);
  end;
  ARegistry.CloseKey;
end;

class function TAtlasIdeStructureSwitch.ApplySwitch(const ASubKey, AValueName, AMarker, ALegacyMarker: string;
  AOwn: Boolean): Boolean;
var
  mServices: IOTAServices;
  mRegistry: TRegistry;
  mKey: string;
  mState, mNext: TAtlasIdeStructure;
begin
  Result := False;
  if not Supports(BorlandIDEServices, IOTAServices, mServices) then
  begin
    Exit;
  end;
  mKey := mServices.GetBaseRegistryKey + ASubKey;
  mRegistry := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    mRegistry.RootKey := HKEY_CURRENT_USER;
    try
      mState := ReadSwitch(mRegistry, mKey, AValueName, AMarker, ALegacyMarker);
      mNext := TAtlasGuides.Switch(mState, AOwn);
      if mNext.Enabled <> mState.Enabled then
      begin
        Result := WriteSwitch(mRegistry, mKey, AValueName, mNext.Enabled);
      end;
      WriteMarker(mRegistry, AMarker, ALegacyMarker, mNext.DisabledByAtlas <> mState.DisabledByAtlas,
        mNext.DisabledByAtlas);
    except
      // Ohne Schreibrecht bleibt die IDE, wie sie ist.
      on ERegistryException do
        Result := False;
    end;
  finally
    mRegistry.Free;
  end;
end;

function BaseKey: string;
var
  Services: IOTAServices;
begin
  Result := '';
  if Supports(BorlandIDEServices, IOTAServices, Services) then
  begin
    Result := Services.GetBaseRegistryKey;
  end;
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
  begin
    Exit;
  end;
  mRegistry := TRegistry.Create(KEY_READ);
  mNames := TStringList.Create;
  try
    mRegistry.RootKey := HKEY_CURRENT_USER;
    try
      if not mRegistry.OpenKeyReadOnly(BaseKey + TAtlasCodeInsightKeys.cRoot) then
      begin
        Exit;
      end;
      mRegistry.GetKeyNames(mNames);
      mRegistry.CloseKey;
      for mName in mNames do
      begin
        if mRegistry.OpenKeyReadOnly(BaseKey + TAtlasCodeInsightKeys.cRoot + '\' + mName) and
          mRegistry.ValueExists(AValueName) then
        begin
          Result := Result + [mName];
        end;
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
  begin
    Result := AMarker;
  end;
end;

class function TAtlasIdeStructureSwitch.ApplyCodeInsight(const AValueName, AMarker: string; AOwn: Boolean): Boolean;
var
  mSubKey: string;
begin
  Result := False;
  for mSubKey in TAtlasCodeInsightKeys.Targets(BaseKey, KeysWithValue(AValueName)) do
  begin
    if ApplySwitch(TAtlasCodeInsightKeys.cRoot + '\' + mSubKey, AValueName,
      TAtlasCodeInsightKeys.Marker(AMarker, BaseKey, mSubKey), LegacyMarker(AMarker, mSubKey), AOwn) then
    begin
      Result := True;
    end;
  end;
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
  begin
    Exit;
  end;
  Registry := TRegistry.Create(KEY_READ);
  try
    Registry.RootKey := HKEY_CURRENT_USER;
    // Die IDE liest nur den Ort ihrer Version (#1246); bei unbekannter Version der erste bekannte.
    if Registry.OpenKeyReadOnly(BaseKey + TAtlasCodeInsightKeys.cRoot + '\' +
      TAtlasCodeInsightKeys.Targets(BaseKey, nil)[0]) and Registry.ValueExists(ErrorInsightValue) then
    begin
      Result := not SameText(Registry.ReadString(ErrorInsightValue), 'False');
    end;
  finally
    Registry.Free;
  end;
end;

class function TAtlasIdeStructureSwitch.ErrorInsight: Boolean;
begin
  Result := ReadErrorInsight;
  if ErrorInsightAtStart < 0 then
  begin
    ErrorInsightAtStart := Ord(Result);
  end;
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
  begin
    Exit;
  end;
  // Stand vor der Änderung merken, falls noch nicht gelesen.
  ErrorInsight;
  Registry := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    Registry.RootKey := HKEY_CURRENT_USER;
    try
      // An allen Orten wie Help Insight (#1246): dem der Version und jedem, der den Wert schon trägt.
      for mSubKey in TAtlasCodeInsightKeys.Targets(BaseKey, KeysWithValue(ErrorInsightValue)) do
      begin
        if WriteSwitch(Registry, BaseKey + TAtlasCodeInsightKeys.cRoot + '\' + mSubKey, ErrorInsightValue,
          AEnabled) then
        begin
          Result := True;
        end;
      end;
      if Result and Registry.OpenKey(AtlasRegistryKey, True) then
      begin
        Registry.WriteInteger(ErrorInsightMarker, Ord(not AEnabled));
      end;
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

/// <summary>Meldung zu einem geänderten Schalter: AOffId, wenn Atlas übernimmt, sonst AOnId.</summary>
procedure AddSwitchText(var ATexts: TArray<string>; AChanged, AOwn: Boolean; AOffId, AOnId: TAtlasTextId);
begin
  if not AChanged then
  begin
    Exit;
  end;
  if AOwn then
  begin
    ATexts := ATexts + [TAtlasStrings.Text(AOffId)];
  end
  else
  begin
    ATexts := ATexts + [TAtlasStrings.Text(AOnId)];
  end;
end;

/// <summary>Meldungen ins Meldungsfenster; beim Laden des Plugins ist es noch nicht bereit.</summary>
procedure ShowSwitchTexts(const ATexts: TArray<string>);
begin
  TAtlasMainThread.ForceQueue(TAtlasFeature.EditorCommands,
    procedure
    var
      mMessages: IOTAMessageServices;
      mText: string;
    begin
      if Supports(BorlandIDEServices, IOTAMessageServices, mMessages) then
      begin
        for mText in ATexts do
        begin
          mMessages.AddTitleMessage(mText);
        end;
      end;
    end);
end;

class procedure TAtlasIdeStructureSwitch.Sync;
var
  mSettings: TAtlasPluginSettings;
  mOwn, mOwnTooltip, mOwnValues: Boolean;
  mTexts: TArray<string>;
begin
  mSettings := TAtlasIdeSettings.Current;
  mOwn := mSettings.PairColors and mSettings.PairGuides;
  mOwnTooltip := mSettings.Enabled and mSettings.HoverTooltip;
  mOwnValues := mOwnTooltip and mSettings.DebugHoverValues;
  mTexts := nil;
  AddSwitchText(mTexts, Apply(mOwn), mOwn, TAtlasTextId.PairGuidesIdeOff, TAtlasTextId.PairGuidesIdeOn);
  AddSwitchText(mTexts, ApplyHelpInsight(mOwnTooltip), mOwnTooltip, TAtlasTextId.HelpInsightIdeOff,
    TAtlasTextId.HelpInsightIdeOn);
  AddSwitchText(mTexts, ApplyTooltipWatches(mOwnValues), mOwnValues, TAtlasTextId.TooltipWatchesIdeOff,
    TAtlasTextId.TooltipWatchesIdeOn);
  if Length(mTexts) > 0 then
  begin
    ShowSwitchTexts(mTexts);
  end;
end;

end.
