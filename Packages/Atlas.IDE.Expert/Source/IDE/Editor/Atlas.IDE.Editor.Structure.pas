unit Atlas.IDE.Editor.Structure;

// Schaltet Anzeigen der IDE ab, die Atlas selbst übernimmt, und stellt sie
// wieder her, wenn die Atlas-Anzeige aus ist:
//   - Strukturhervorhebung, solange Atlas eigene Blocklinien zeichnet (#514):
//     <Basisschlüssel>\Editor\Highlight\Structural Highlighting, Enabled;
//     Merker IdeStructureDisabled.
//   - Help Insight, solange der Atlas-Tooltip an ist (#442; unter Delphi 12
//     zeigte die IDE sonst beide): <Basisschlüssel>\Code Insight\
//     Borland.EditOptions.Borland.CodeInsight.LSP.Pascal, Help Insight;
//     Merker IdeHelpInsightDisabled.
//   - Error Insight auf Knopfdruck aus der Einrichtung (#625), nie von selbst:
//     <Basisschlüssel>\Code Insight\Borland.EditOptions.Borland.CodeInsight.LSP.
//     Pascal, Error Insight (Ort wie Help Insight, in der IDE zu bestätigen);
//     Merker IdeErrorInsightDisabled. ErrorInsightChanged hält fest, dass die
//     IDE den neuen Wert erst nach dem nächsten Start liest.
// Es gibt dafür keine Open Tools API: Die Schalter stehen in der Registry und
// werden von der IDE beim Start gelesen. Die Merker unter
// HKCU\Software\Atlas\IdePlugin halten fest, was Atlas abgeschaltet hat; nur
// das wird zurückgedreht.

interface

type
  TAtlasIdeStructureSwitch = class
  private
    class function ApplySwitch(const ASubKey, AValueName, AMarker: string; AOwn: Boolean): Boolean; static;
  public
    /// <summary>Strukturhervorhebung angleichen; True, wenn geändert (wirkt nach dem nächsten Start der IDE).</summary>
    class function Apply(AOwnGuides: Boolean): Boolean; static;
    /// <summary>Help Insight angleichen; True, wenn geändert (wirkt nach dem nächsten Start der IDE).</summary>
    class function ApplyHelpInsight(AOwnTooltip: Boolean): Boolean; static;
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
  Atlas.UI.Strings,
  Atlas.IDE.Settings.Store;

const
  StructureKey = '\Editor\Highlight\Structural Highlighting';
  StructureMarker = 'IdeStructureDisabled';
  HelpInsightKey = '\Code Insight\Borland.EditOptions.Borland.CodeInsight.LSP.Pascal';
  HelpInsightMarker = 'IdeHelpInsightDisabled';
  ErrorInsightValue = 'Error Insight';
  ErrorInsightMarker = 'IdeErrorInsightDisabled';

var
  // Wert von Error Insight beim ersten Lesen in dieser Sitzung; so liest ihn die IDE bis zum Neustart.
  ErrorInsightAtStart: Integer = -1;

class function TAtlasIdeStructureSwitch.ApplySwitch(const ASubKey, AValueName, AMarker: string;
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
      if Registry.OpenKey(AtlasRegistryKey, True) and Registry.ValueExists(AMarker) then
        State.DisabledByAtlas := Registry.ReadInteger(AMarker) <> 0;
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
      if (Next.DisabledByAtlas <> State.DisabledByAtlas) and Registry.OpenKey(AtlasRegistryKey, True) then
      begin
        Registry.WriteInteger(AMarker, Ord(Next.DisabledByAtlas));
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

class function TAtlasIdeStructureSwitch.Apply(AOwnGuides: Boolean): Boolean;
begin
  Result := ApplySwitch(StructureKey, 'Enabled', StructureMarker, AOwnGuides);
end;

class function TAtlasIdeStructureSwitch.ApplyHelpInsight(AOwnTooltip: Boolean): Boolean;
begin
  Result := ApplySwitch(HelpInsightKey, 'Help Insight', HelpInsightMarker, AOwnTooltip);
end;

function BaseKey: string;
var
  Services: IOTAServices;
begin
  Result := '';
  if Supports(BorlandIDEServices, IOTAServices, Services) then
    Result := Services.GetBaseRegistryKey;
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
    if Registry.OpenKeyReadOnly(BaseKey + HelpInsightKey) and Registry.ValueExists(ErrorInsightValue) then
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
      if Registry.OpenKey(BaseKey + HelpInsightKey, True) then
      begin
        if AEnabled then
          Registry.WriteString(ErrorInsightValue, 'True')
        else
          Registry.WriteString(ErrorInsightValue, 'False');
        Result := True;
      end;
      Registry.CloseKey;
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
