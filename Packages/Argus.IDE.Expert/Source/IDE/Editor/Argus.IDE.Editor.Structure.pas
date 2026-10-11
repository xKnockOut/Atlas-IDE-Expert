unit Argus.IDE.Editor.Structure;

// Schaltet Anzeigen der IDE ab, die Argus selbst übernimmt, und stellt sie
// wieder her, wenn die Argus-Anzeige aus ist:
//   - Strukturhervorhebung, solange Argus eigene Blocklinien zeichnet (#514):
//     <Basisschlüssel>\Editor\Highlight\Structural Highlighting, Enabled;
//     Merker IdeStructureDisabled.
//   - Help Insight, solange der Argus-Tooltip an ist (#442; unter Delphi 12
//     zeigte die IDE sonst beide): <Basisschlüssel>\Code Insight\
//     Borland.EditOptions.Borland.CodeInsight.LSP.Pascal, Help Insight;
//     Merker IdeHelpInsightDisabled.
// Es gibt dafür keine Open Tools API: Die Schalter stehen in der Registry und
// werden von der IDE beim Start gelesen. Die Merker unter
// HKCU\Software\Argus\IdePlugin halten fest, was Argus abgeschaltet hat; nur
// das wird zurückgedreht.

interface

type
  TArgusIdeStructureSwitch = class
  private
    class function ApplySwitch(const ASubKey, AValueName, AMarker: string; AOwn: Boolean): Boolean; static;
  public
    /// <summary>Strukturhervorhebung angleichen; True, wenn geändert (wirkt nach dem nächsten Start der IDE).</summary>
    class function Apply(AOwnGuides: Boolean): Boolean; static;
    /// <summary>Help Insight angleichen; True, wenn geändert (wirkt nach dem nächsten Start der IDE).</summary>
    class function ApplyHelpInsight(AOwnTooltip: Boolean): Boolean; static;
    /// <summary>Beides nach den aktuellen Einstellungen; meldet Änderungen im Meldungsfenster.</summary>
    class procedure Sync; static;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Win.Registry,
  ToolsAPI,
  Argus.Core.Settings.Plugin,
  Argus.Core.Editor.Guides,
  Argus.UI.Strings,
  Argus.IDE.Settings.Store;

const
  StructureKey = '\Editor\Highlight\Structural Highlighting';
  StructureMarker = 'IdeStructureDisabled';
  HelpInsightKey = '\Code Insight\Borland.EditOptions.Borland.CodeInsight.LSP.Pascal';
  HelpInsightMarker = 'IdeHelpInsightDisabled';

class function TArgusIdeStructureSwitch.ApplySwitch(const ASubKey, AValueName, AMarker: string;
  AOwn: Boolean): Boolean;
var
  Services: IOTAServices;
  Registry: TRegistry;
  Key: string;
  State, Next: TArgusIdeStructure;
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
      State.DisabledByArgus := False;
      if Registry.OpenKey(ArgusRegistryKey, True) and Registry.ValueExists(AMarker) then
        State.DisabledByArgus := Registry.ReadInteger(AMarker) <> 0;
      Registry.CloseKey;
      Next := TArgusGuides.Switch(State, AOwn);
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
      if (Next.DisabledByArgus <> State.DisabledByArgus) and Registry.OpenKey(ArgusRegistryKey, True) then
      begin
        Registry.WriteInteger(AMarker, Ord(Next.DisabledByArgus));
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

class function TArgusIdeStructureSwitch.Apply(AOwnGuides: Boolean): Boolean;
begin
  Result := ApplySwitch(StructureKey, 'Enabled', StructureMarker, AOwnGuides);
end;

class function TArgusIdeStructureSwitch.ApplyHelpInsight(AOwnTooltip: Boolean): Boolean;
begin
  Result := ApplySwitch(HelpInsightKey, 'Help Insight', HelpInsightMarker, AOwnTooltip);
end;

class procedure TArgusIdeStructureSwitch.Sync;
var
  Settings: TArgusPluginSettings;
  Own, OwnTooltip: Boolean;
  Texts: TArray<string>;
begin
  Settings := TArgusIdeSettings.Current;
  Own := Settings.PairColors and Settings.PairGuides;
  OwnTooltip := Settings.Enabled and Settings.HoverTooltip;
  Texts := nil;
  if Apply(Own) then
    if Own then
      Texts := Texts + [TArgusStrings.Text(TArgusTextId.PairGuidesIdeOff)]
    else
      Texts := Texts + [TArgusStrings.Text(TArgusTextId.PairGuidesIdeOn)];
  if ApplyHelpInsight(OwnTooltip) then
    if OwnTooltip then
      Texts := Texts + [TArgusStrings.Text(TArgusTextId.HelpInsightIdeOff)]
    else
      Texts := Texts + [TArgusStrings.Text(TArgusTextId.HelpInsightIdeOn)];
  if Length(Texts) = 0 then
    Exit;
  // Beim Laden des Plugins ist das Meldungsfenster noch nicht bereit.
  TThread.ForceQueue(nil,
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
